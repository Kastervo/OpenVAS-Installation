#!/bin/bash

# OpenVAS installation script for Debian 12 systems.
# Version: v1.0.0
# Purpose: Installs and configures OpenVAS from source following Greenbone Community Edition guidelines.
# Repository: https://github.com/Kastervo/OpenVAS-Installation
#
# Copyright 2025 KASTERVO LTD
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Company: KASTERVO LTD
# Address: Efesou 9, Paralimni, 5280, Famagusta, Cyprus
# Contact: https://kastervo.com/contact

# -----------------------------------
# Section: Environment Setup
# -----------------------------------

# Sets up environment variables for the installation process.
# Creates consistent paths for source, build, and install directories.
set_environment() {
	log INFO "Starting environment variable setup..."
	export INSTALL_PREFIX=/usr/local
	export PATH=$PATH:$INSTALL_PREFIX/sbin
	export SOURCE_DIR=$HOME/source
	export BUILD_DIR=$HOME/build
	export INSTALL_DIR=$HOME/install
	export GNUPGHOME=/tmp/openvas-gnupg
	export OPENVAS_GNUPG_HOME=/etc/openvas/gnupg

	# Check disk space for directories
	for dir in "$SOURCE_DIR" "$BUILD_DIR" "$INSTALL_DIR"; do
		if ! mkdir -p "$dir" 2>/dev/null; then
			log ERROR "Failed to create directory $dir. Check permissions or disk space."
			exit 1
		fi
		local free_space
		free_space=$(df -k "$dir" | tail -1 | awk '{print $4}')
		if [ "$free_space" -lt 1048576 ]; then # Less than 1GB
			log WARN "Low disk space in $dir: $((free_space/1024)) MB available. Recommend at least 1GB."
		fi
	done
	log INFO "Environment variable set: INSTALL_PREFIX=$INSTALL_PREFIX"
	log INFO "Environment variable set: PATH=$PATH"
	log INFO "Environment variable set: SOURCE_DIR=$SOURCE_DIR"
	log INFO "Environment variable set: BUILD_DIR=$BUILD_DIR"
	log INFO "Environment variable set: INSTALL_DIR=$INSTALL_DIR"
	log INFO "Environment variable set: GNUPGHOME=$GNUPGHOME"
	log INFO "Environment variable set: OPENVAS_GNUPG_HOME=$OPENVAS_GNUPG_HOME"
}

# -----------------------------------
# Section: Version Management
# -----------------------------------

# Fetches the latest version of OpenVAS components from GitHub.
# Exports version numbers as environment variables for use in installation.
check_latest_version() {
	log INFO "Starting version check for OpenVAS components..."

	# Check network connectivity to GitHub API
	if ! curl --proto '=https' --tlsv1.2 -s -I "https://api.github.com" >/dev/null 2>&1; then
		log ERROR "No network connectivity to api.github.com. Check network settings."
		exit 1
	fi

	declare -A component_vars=(
		["gvm-libs"]="GVM_LIBS_VERSION"
		["gvmd"]="GVMD_VERSION"
		["pg-gvm"]="PG_GVM_VERSION"
		["gsa"]="GSA_VERSION"
		["gsad"]="GSAD_VERSION"
		["openvas-smb"]="OPENVAS_SMB_VERSION"
		["openvas-scanner"]="OPENVAS_SCANNER_VERSION"
		["ospd-openvas"]="OSPD_OPENVAS_VERSION"
	)

	for component in "${!component_vars[@]}"; do
		log INFO "Fetching latest version for $component..."
		local comp_ver
		comp_ver=$(curl --proto '=https' --tlsv1.2 -s "https://api.github.com/repos/greenbone/$component/releases/latest" | grep tag_name | cut -d '"' -f 4 | sed 's/v//')

		if [ -z "$comp_ver" ]; then
			log ERROR "Failed to fetch version for $component. Check network or GitHub API."
			exit 1
		fi

		local var_name="${component_vars[$component]}"
		export "$var_name=$comp_ver"
		log INFO "Set $var_name=$comp_ver"

		if [ "$component" = "openvas-scanner" ]; then
			export OPENVAS_DAEMON="$comp_ver"
			log INFO "Set OPENVAS_DAEMON=$comp_ver"
		fi
	done
	log INFO "Completed version check for all components."
}

# -----------------------------------
# Section: Logging and Error Handling
# -----------------------------------

# Structured logging with levels (INFO, WARN, ERROR) to a log file with colors.
# Usage: log <LEVEL> <MESSAGE>
LOG_FILE=/var/log/openvas_install.log
log() {
	local level=$1
	shift
	local message="$*"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	
	# ANSI color codes
	local COLOR_INFO="\033[1;36m"  # Cyan for INFO
	local COLOR_WARN="\033[1;33m"  # Yellow for WARN
	local COLOR_ERROR="\033[1;31m" # Red for ERROR
	local COLOR_RESET="\033[0m"    # Reset color
	
	# Select color based on log level
	case "$level" in
		INFO)
			color=$COLOR_INFO
			;;
		WARN)
			color=$COLOR_WARN
			;;
		ERROR)
			color=$COLOR_ERROR
			;;
		*)
			color=$COLOR_RESET
			;;
	esac
	
	# Output to console with color and log to file without color
	echo -e "${color}${timestamp} [$level] $message${COLOR_RESET}" | tee -a "$LOG_FILE"
}

# Executes a command with error handling and logging.
# Logs command execution and exits on failure with status code.
run_command() {
	log INFO "Executing command: $*"
	"$@"
	local status=$?
	if [ $status -ne 0 ]; then
		log ERROR "Command '$*' failed with status $status."
		exit $status
	fi
	log INFO "Command '$*' completed successfully."
}

# -----------------------------------
# Section: System Checks
# -----------------------------------

# Ensures the script is run as root to meet permission requirements.
check_root() {
	log INFO "Checking for root privileges..."
	if [ "$EUID" -ne 0 ]; then
		log ERROR "This script must be run as root."
		exit 1
	fi
	log INFO "Root privilege check passed."
}

# -----------------------------------
# Section: User and Group Management
# -----------------------------------

# Creates a dedicated 'gvm' user and group for running OpenVAS services.
create_gvm_user() {
	log INFO "Setting up GVM user and group..."
	if getent passwd gvm > /dev/null 2>&1; then
		log WARN "GVM user already exists, skipping creation. Verify user settings."
	else
		run_command useradd -r -M -U -G sudo -s /usr/sbin/nologin gvm
		if ! run_command usermod -aG gvm "$USER"; then
			log WARN "Failed to add $USER to gvm group. Manual addition may be required."
		else
			log INFO "Created GVM user and group, added $USER to gvm group."
		fi
	fi
}

# -----------------------------------
# Section: Dependency Installation
# -----------------------------------

# Installs common build tools and dependencies required for all components.
install_common_dep() {
	log INFO "Installing common build dependencies..."
	if ! run_command apt install -y --no-install-recommends --assume-yes \
		build-essential curl cmake pkg-config python3 python3-pip gnupg; then
		log ERROR "Failed to install common dependencies. Check apt configuration."
		exit 1
	fi
	if ! command -v cmake >/dev/null 2>&1; then
		log ERROR "cmake not found after installation. Dependency installation incomplete."
		exit 1
	fi
	log INFO "Common dependencies installed."
}

# Installs dependencies for gvm-libs component.
install_gvm_libs_dep() {
	log INFO "Installing gvm-libs dependencies..."
	# Required dependencies for gvm-libs
	if ! run_command apt install -y \
		libcjson-dev libcurl4-gnutls-dev libgcrypt-dev libglib2.0-dev libgnutls28-dev libgpgme-dev libhiredis-dev libnet1-dev libpaho-mqtt-dev libpcap-dev libssh-dev libxml2-dev uuid-dev ; then
			log ERROR "Failed to install required dependencies for gvm-libs. Check apt configuration."
			exit 1
	fi
	# Optional dependencies for gvm-libs
	if ! run_command apt install -y \
		libldap2-dev libradcli-dev ; then
			log WARN "Optional gvm-libs dependencies (libldap2-dev, libradcli-dev) not installed. Some features may be limited."
	fi
	log INFO "gvm-libs dependencies installed."
}

# Installs dependencies for gvmd component.
install_gvmd_dep() {
	log INFO "Installing gvmd dependencies..."
	# Required dependencies for gvmd
	if ! run_command apt install -y \
		libbsd-dev libcjson-dev libglib2.0-dev libgnutls28-dev libgpgme-dev libical-dev libpq-dev postgresql-server-dev-all rsync xsltproc; then
		log ERROR "Failed to install required dependencies for gvmd. Check apt configuration."
		exit 1
	fi
	# Optional dependencies for gvmd
	if ! run_command apt install -y --no-install-recommends \
		dpkg fakeroot gnupg gnutls-bin gpgsm nsis openssh-client python3 python3-lxml rpm smbclient snmp socat sshpass texlive-fonts-recommended texlive-latex-extra wget xmlstarlet zip; then
		log WARN "Optional gvmd dependencies not installed. Some features may be limited."
	fi
	log INFO "gvmd dependencies installed."
}

# Installs dependencies for pg-gvm component.
install_pg_gvm_dep() {
	log INFO "Installing pg-gvm dependencies..."
	# Required dependencies for pg-gvm
	if ! run_command apt install -y \
		libglib2.0-dev libical-dev postgresql-server-dev-all; then
		log ERROR "Failed to install required dependencies for pg-gvm. Check apt configuration."
		exit 1
	fi
	log INFO "pg-gvm dependencies installed."
}

# Installs dependencies for gsad component.
install_gsad_dep() {
	log INFO "Installing gsad dependencies..."
	# Required dependencies for gsad
	if ! run_command apt install -y \
		libbrotli-dev libglib2.0-dev libgnutls28-dev libmicrohttpd-dev libxml2-dev; then
		log ERROR "Failed to install required dependencies for gsad. Check apt configuration."
		exit 1
	fi
	log INFO "gsad dependencies installed."
}

# Installs dependencies for openvas-smb component.
install_openvas_smb_dep() {
	log INFO "Installing openvas-smb dependencies..."
	# Required dependencies for openvas-smb
	if ! run_command apt install -y \
		gcc-mingw-w64 libgnutls28-dev libglib2.0-dev libpopt-dev libunistring-dev heimdal-multidev perl-base; then
		log ERROR "Failed to install required dependencies for openvas-smb. Check apt configuration."
		exit 1
	fi
	log INFO "openvas-smb dependencies installed."
}

# Installs dependencies for openvas-scanner component.
install_openvas_scanner_dep() {
	log INFO "Installing openvas-scanner dependencies..."
	# Required dependencies for openvas-scanner
	if ! run_command apt install -y \
		bison libglib2.0-dev libgnutls28-dev libgcrypt20-dev libpcap-dev libgpgme-dev libksba-dev rsync nmap libjson-glib-dev libcurl4-gnutls-dev libbsd-dev krb5-multidev; then
		log ERROR "Failed to install required dependencies for openvas-scanner. Check apt configuration."
		exit 1
	fi
	# Optional dependencies for openvas-scanner
	if ! run_command apt install -y \
		python3-impacket libsnmp-dev; then
		log WARN "Optional openvas-scanner dependencies (python3-impacket, libsnmp-dev) not installed. Some features may be limited."
	fi
	log INFO "openvas-scanner dependencies installed."
}

# Installs dependencies for ospd-openvas component.
install_ospd_openvas_dep() {
	log INFO "Installing ospd-openvas dependencies..."
	# Required dependencies for ospd-openvas
	if ! run_command apt install -y \
		python3 python3-pip python3-setuptools python3-packaging python3-wrapt python3-cffi python3-psutil python3-lxml python3-defusedxml python3-paramiko python3-redis python3-gnupg python3-paho-mqtt; then
		log ERROR "Failed to install required dependencies for ospd-openvas. Check apt configuration."
		exit 1
	fi
	log INFO "ospd-openvas dependencies installed."
}

# Installs dependencies for openvasd component.
install_openvasd_dep() {
	log INFO "Installing openvasd dependencies..."
	# Required dependencies for openvasd
	if ! run_command apt install -y \
		pkg-config libssl-dev; then
		log ERROR "Failed to install required dependencies for openvasd. Check apt configuration."
		exit 1
	fi

	# Install Rust and Cargo for openvasd
	log INFO "Installing Rust and Cargo for openvasd..."
	# Check if rustc is already installed
	if command -v rustc >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
		log INFO "Rust and Cargo are already installed. Verifying versions..."
		local rustc_version
		rustc_version=$(rustc --version)
		local cargo_version
		cargo_version=$(cargo --version)
		log INFO "Found $rustc_version and $cargo_version"
	else
		# Download and install rustup
		if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh; then
			log ERROR "Failed to download rustup installer. Check network."
			exit 1
		fi
		# Install rustup non-interactively
		if ! sh /tmp/rustup-init.sh -y --no-modify-path; then
			log ERROR "Failed to install Rust and Cargo. Check installation script."
			exit 1
		fi
		# Clean up installer
		rm -f /tmp/rustup-init.sh
		log INFO "Rust and Cargo installed successfully."
	fi

	# Source Cargo environment
	if [ -f "$HOME/.cargo/env" ]; then
		# shellcheck disable=SC1091
		. "$HOME/.cargo/env"
	else
		log ERROR "Cargo environment file not found at $HOME/.cargo/env."
		exit 1
	fi

	# Verify Rust and Cargo installation
	if ! command -v rustc >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
		log ERROR "Rust or Cargo not found after installation. Check PATH or installation."
		exit 1
	fi
	log INFO "Rust and Cargo verified: $(rustc --version), $(cargo --version)"
	log INFO "openvasd dependencies installed."
}

# Installs dependencies for gvm-tools component.
install_gvm_tools_dep() {
	log INFO "Installing gvm-tools dependencies..."
	# Required dependencies for gvm-tools
	if ! run_command apt install -y \
		python3 python3-lxml python3-packaging python3-paramiko python3-pip python3-setuptools python3-venv; then
		log ERROR "Failed to install required dependencies for gvm-tools. Check apt configuration."
		exit 1
	fi
	log INFO "gvm-tools dependencies installed."
}

# Installs all required dependencies for OpenVAS components.
install_packages() {
	log INFO "Starting installation of all dependencies..."
	for dep_func in install_common_dep install_gvm_libs_dep install_gvmd_dep install_pg_gvm_dep install_gsad_dep install_openvas_smb_dep install_openvas_scanner_dep install_ospd_openvas_dep install_openvasd_dep install_gvm_tools_dep; do
		if ! $dep_func; then
			log ERROR "Failed to install dependencies in $dep_func."
			exit 1
		fi
	done
	log INFO "All dependencies installed successfully."
}

# -----------------------------------
# Section: Directory and Key Setup
# -----------------------------------

# Creates directories for source, build, and installation.
create_directories() {
	log INFO "Creating directories for source, build, and installation..."
	for dir in "$SOURCE_DIR" "$BUILD_DIR" "$INSTALL_DIR"; do
		if ! mkdir -p "$dir" 2>/dev/null; then
			log ERROR "Failed to create directory $dir. Check permissions or disk space."
			exit 1
		fi
		if [ ! -w "$dir" ]; then
			log ERROR "Directory $dir is not writable. Check permissions."
			exit 1
		fi
	done
	log INFO "Directories created: $SOURCE_DIR, $BUILD_DIR, $INSTALL_DIR"
}

# Imports Greenbone's GPG signing key for package verification.
import_signing_key() {
	log INFO "Importing Greenbone Community Signing Key..."
	if ! run_command mkdir -p "$GNUPGHOME"; then
		log ERROR "Failed to create GPG home directory $GNUPGHOME."
		exit 1
	fi
	if ! run_command curl -f -L https://www.greenbone.net/GBCommunitySigningKey.asc -o /tmp/GBCommunitySigningKey.asc; then
		log ERROR "Failed to download Greenbone signing key. Check network or URL."
		exit 1
	fi
	if ! run_command gpg --homedir "$GNUPGHOME" --import /tmp/GBCommunitySigningKey.asc; then
		log ERROR "Failed to import Greenbone signing key. Check GPG configuration."
		exit 1
	fi
	if ! gpg --homedir "$GNUPGHOME" --list-keys | grep -q "Greenbone"; then
		log WARN "Greenbone key imported but not found in keyring. Verification may fail."
	fi
	log INFO "Greenbone signing key imported."
}

# Generates a self-signed SSL certificate for gsad if not already present.
generate_ssl_cert() {
	log INFO "Checking for gsad SSL certificate..."
	if [ -f /etc/gvm/gsad.crt ] && [ -f /etc/gvm/gsad.key ]; then
		log INFO "SSL certificate and key already exist, skipping generation."
		if [ "$(stat -c %U:%G /etc/gvm/gsad.crt)" != "gvm:gvm" ]; then
			log WARN "SSL certificate ownership is not gvm:gvm. Fixing permissions."
			run_command chown gvm:gvm /etc/gvm/gsad.crt /etc/gvm/gsad.key
		fi
	else
		log INFO "Generating self-signed SSL certificate for gsad..."
		if ! run_command mkdir -p /etc/gvm; then
			log ERROR "Failed to create /etc/gvm directory."
			exit 1
		fi
		if ! run_command openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
			-keyout /etc/gvm/gsad.key -out /etc/gvm/gsad.crt \
			-subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=$(hostname)"; then
			log ERROR "Failed to generate SSL certificate for gsad."
			exit 1
		fi
		if ! run_command chown gvm:gvm /etc/gvm/gsad.crt /etc/gvm/gsad.key; then
			log ERROR "Failed to set ownership for SSL certificate."
			exit 1
		fi
		if ! run_command chmod 640 /etc/gvm/gsad.crt || ! run_command chmod 600 /etc/gvm/gsad.key; then
			log ERROR "Failed to set permissions for SSL certificate."
			exit 1
		fi
		log WARN "Generated self-signed certificate. Replace with a trusted certificate for production use."
	fi
}

# -----------------------------------
# Section: Component Installation
# -----------------------------------

# Builds and installs a generic OpenVAS component from source.
build_install_component() {
	local comp_name=$1
	local comp_ver=$2
	local comp_args=$3

	log INFO "Starting build and installation of $comp_name-$comp_ver..."

	# Set the source URL
	local comp_src="https://github.com/greenbone/$comp_name/archive/refs/tags/v$comp_ver.tar.gz"

	# Set the signature URL
	if [ "$comp_name" = "openvas-smb" ] || [ "$comp_name" = "openvas-scanner" ]; then
		local comp_sig="https://github.com/greenbone/$comp_name/releases/download/v$comp_ver/$comp_name-v$comp_ver.tar.gz.asc"
	else
		local comp_sig="https://github.com/greenbone/$comp_name/releases/download/v$comp_ver/$comp_name-$comp_ver.tar.gz.asc"
	fi

	# Download Sources
	if ! run_command curl -f -L "$comp_src" -o "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "Failed to download source for $comp_name-$comp_ver from $comp_src"
		exit 1
	fi
	if ! run_command curl -f -L "$comp_sig" -o "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz.asc"; then
		log ERROR "Failed to download signature for $comp_name-$comp_ver from $comp_sig"
		exit 1
	fi

	# Verify GPG signature
	if ! gpg --homedir "$GNUPGHOME" --verify "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz.asc" "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "GPG signature verification failed for $comp_name-$comp_ver"
		exit 1
	fi

	# Extract Sources
	if ! run_command tar -C "$SOURCE_DIR" -xvzf "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "Failed to extract source for $comp_name-$comp_ver"
		exit 1
	fi

	# Building
	if ! run_command mkdir -p "$BUILD_DIR/$comp_name"; then
		log ERROR "Failed to create build directory $BUILD_DIR/$comp_name"
		exit 1
	fi
	if ! run_command cmake $comp_args; then
		log ERROR "CMake configuration failed for $comp_name-$comp_ver with args: $comp_args"
		exit 1
	fi
	if ! run_command cmake --build "$BUILD_DIR/$comp_name" -j$(nproc); then
		log ERROR "Build failed for $comp_name-$comp_ver"
		exit 1
	fi

	# Installing
	if ! run_command mkdir -p "$INSTALL_DIR/$comp_name"; then
		log ERROR "Failed to create install directory $INSTALL_DIR/$comp_name"
		exit 1
	fi
	if ! run_command cd "$BUILD_DIR/$comp_name"; then
		log ERROR "Failed to change to build directory $BUILD_DIR/$comp_name"
		exit 1
	fi
	if ! run_command make DESTDIR="$INSTALL_DIR/$comp_name" install; then
		log ERROR "Installation failed for $comp_name-$comp_ver"
		exit 1
	fi
	if ! run_command cp -rv "$INSTALL_DIR/$comp_name"/* /; then
		log ERROR "Failed to copy installed files for $comp_name-$comp_ver to system directories"
		exit 1
	fi

	log INFO "Successfully built and installed $comp_name-$comp_ver"
}

# Installs the GSA (Greenbone Security Assistant) web interface.
build_install_gsa() {
	local comp_name=$1
	local comp_ver=$2

	log INFO "Starting installation of $comp_name-$comp_ver..."

	local comp_src="https://github.com/greenbone/gsa/releases/download/v$comp_ver/gsa-dist-$comp_ver.tar.gz"
	local comp_sig="https://github.com/greenbone/gsa/releases/download/v$comp_ver/gsa-dist-$comp_ver.tar.gz.asc"

	# Download and verify
	log INFO "Downloading $comp_name-$comp_ver source and signature..."
	if ! run_command curl -f -L "$comp_src" -o "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "Failed to download $comp_name-$comp_ver source."
		exit 1
	fi
	if ! run_command curl -f -L "$comp_sig" -o "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz.asc"; then
		log ERROR "Failed to download $comp_name-$comp_ver signature."
		exit 1
	fi

	log INFO "Verifying GPG signature for $comp_name-$comp_ver..."
	if ! gpg --homedir "$GNUPGHOME" --verify "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz.asc" "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "GPG signature verification failed for $comp_name-$comp_ver."
		exit 1
	fi

	# Extract and install
	log INFO "Extracting and installing $comp_name-$comp_ver..."
	if ! run_command mkdir -p "$SOURCE_DIR/$comp_name-$comp_ver"; then
		log ERROR "Failed to create source directory for $comp_name-$comp_ver."
		exit 1
	fi
	if ! run_command tar -C "$SOURCE_DIR/$comp_name-$comp_ver" -xvzf "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "Failed to extract $comp_name-$comp_ver."
		exit 1
	fi
	if ! run_command mkdir -p "$INSTALL_PREFIX/share/gvm/gsad/web/"; then
		log ERROR "Failed to create web directory for $comp_name-$comp_ver."
		exit 1
	fi
	if ! run_command cp -rv "$SOURCE_DIR/$comp_name-$comp_ver"/* "$INSTALL_PREFIX/share/gvm/gsad/web/"; then
		log ERROR "Failed to install $comp_name-$comp_ver web files."
		exit 1
	fi
	log INFO "Completed installation of $comp_name-$comp_ver."
}

# Installs ospd-openvas using Python pip.
build_install_opsd() {
	local comp_name=$1
	local comp_ver=$2

	log INFO "Starting installation of $comp_name-$comp_ver..."

	local comp_src="https://github.com/greenbone/ospd-openvas/archive/refs/tags/v$comp_ver.tar.gz"
	local comp_sig="https://github.com/greenbone/ospd-openvas/releases/download/v$comp_ver/ospd-openvas-v$comp_ver.tar.gz.asc"

	# Download and verify
	log INFO "Downloading $comp_name-$comp_ver source and signature..."
	if ! run_command curl -f -L "$comp_src" -o "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "Failed to download $comp_name-$comp_ver source."
		exit 1
	fi
	if ! run_command curl -f -L "$comp_sig" -o "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz.asc"; then
		log ERROR "Failed to download $comp_name-$comp_ver signature."
		exit 1
	fi

	log INFO "Verifying GPG signature for $comp_name-$comp_ver..."
	if ! gpg --homedir "$GNUPGHOME" --verify "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz.asc" "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "GPG signature verification failed for $comp_name-$comp_ver."
		exit 1
	fi

	# Extract and install
	log INFO "Extracting and installing $comp_name-$comp_ver..."
	if ! run_command tar -C "$SOURCE_DIR" -xvzf "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "Failed to extract $comp_name-$comp_ver."
		exit 1
	fi
	if ! run_command cd "$SOURCE_DIR/$comp_name-$comp_ver"; then
		log ERROR "Failed to change to $comp_name-$comp_ver directory."
		exit 1
	fi
	if ! run_command mkdir -p "$INSTALL_DIR/$comp_name"; then
		log ERROR "Failed to create install directory for $comp_name."
		exit 1
	fi
	if ! run_command python3 -m pip install --root="$INSTALL_DIR/$comp_name" --no-warn-script-location .; then
		log ERROR "Failed to install $comp_name-$comp_ver via pip."
		exit 1
	fi
	if ! run_command cp -rv "$INSTALL_DIR/$comp_name"/* /; then
		log ERROR "Failed to copy $comp_name-$comp_ver to system directories."
		exit 1
	fi
	log INFO "Completed installation of $comp_name-$comp_ver."
}

# Installs openvasd and scannerctl using Rust.
build_install_openvasd() {
	local comp_name=$1
	local comp_sub=$2
	local comp_ver=$3

	log INFO "Starting installation of $comp_sub-$comp_ver..."

	local comp_src="https://github.com/greenbone/openvas-scanner/archive/refs/tags/v$comp_ver.tar.gz"
	local comp_sig="https://github.com/greenbone/openvas-scanner/releases/download/v$comp_ver/openvas-scanner-v$comp_ver.tar.gz.asc"

	# Download and verify
	log INFO "Downloading $comp_name-$comp_ver source and signature..."
	if ! run_command curl -f -L "$comp_src" -o "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "Failed to download $comp_name-$comp_ver source."
		exit 1
	fi
	if ! run_command curl -f -L "$comp_sig" -o "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz.asc"; then
		log ERROR "Failed to download $comp_name-$comp_ver signature."
		exit 1
	fi

	log INFO "Verifying GPG signature for $comp_name-$comp_ver..."
	if ! gpg --homedir "$GNUPGHOME" --verify "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz.asc" "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "GPG signature verification failed for $comp_name-$comp_ver."
		exit 1
	fi

	# Extract and build
	log INFO "Extracting and building $comp_sub-$comp_ver..."
	if ! run_command tar -C "$SOURCE_DIR" -xvzf "$SOURCE_DIR/$comp_name-$comp_ver.tar.gz"; then
		log ERROR "Failed to extract $comp_name-$comp_ver."
		exit 1
	fi
	if ! run_command mkdir -p "$INSTALL_DIR/$comp_sub/usr/local/bin"; then
		log ERROR "Failed to create install directory for $comp_sub."
		exit 1
	fi
	if ! run_command cd "$SOURCE_DIR/$comp_name-$comp_ver/rust/src/$comp_sub"; then
		log ERROR "Failed to change to $comp_sub directory."
		exit 1
	fi
	if ! run_command cargo build --release; then
		log ERROR "Failed to build $comp_sub."
		exit 1
	fi
	if ! run_command cd "$SOURCE_DIR/$comp_name-$comp_ver/rust/src/scannerctl"; then
		log ERROR "Failed to change to scannerctl directory."
		exit 1
	fi
	if ! run_command cargo build --release; then
		log ERROR "Failed to build scannerctl."
		exit 1
	fi

	# Install
	log INFO "Installing $comp_sub and scannerctl..."
	if ! run_command cp -v "../../target/release/$comp_sub" "$INSTALL_DIR/$comp_sub/usr/local/bin/"; then
		log ERROR "Failed to copy $comp_sub binary."
		exit 1
	fi
	if ! run_command cp -v "../../target/release/scannerctl" "$INSTALL_DIR/$comp_sub/usr/local/bin/"; then
		log ERROR "Failed to copy scannerctl binary."
		exit 1
	fi
	if ! run_command cp -rv "$INSTALL_DIR/$comp_sub"/* /; then
		log ERROR "Failed to copy $comp_sub binaries to system directories."
		exit 1
	fi
	log INFO "Completed installation of $comp_sub-$comp_ver."
}

# Installs a Python-based component using pip.
build_install_py() {
	local comp_name=$1

	log INFO "Starting installation of $comp_name..."

	log INFO "Installing $comp_name via pip..."
	if ! run_command mkdir -p "$INSTALL_DIR/$comp_name"; then
		log ERROR "Failed to create install directory for $comp_name."
		exit 1
	fi
	if ! run_command python3 -m pip install --root="$INSTALL_DIR/$comp_name" --no-warn-script-location "$comp_name"; then
		log ERROR "Failed to install $comp_name via pip."
		exit 1
	fi
	if ! run_command cp -rv "$INSTALL_DIR/$comp_name"/* /; then
		log ERROR "Failed to copy $comp_name to system directories."
		exit 1
	fi
	log INFO "Completed installation of $comp_name."
}

# -----------------------------------
# Section: System Configuration
# -----------------------------------

# Configures Redis for OpenVAS and sets up service.
perform_system_setup() {
	log INFO "Starting system setup for Redis..."
	if ! run_command apt install -y redis-server; then
		log ERROR "Failed to install redis-server."
		exit 1
	fi
	if [ ! -f "$SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION/config/redis-openvas.conf" ]; then
		log ERROR "Redis configuration file not found in source directory."
		exit 1
	fi
	if ! run_command cp "$SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION/config/redis-openvas.conf" /etc/redis/; then
		log ERROR "Failed to copy Redis configuration."
		exit 1
	fi
	if ! run_command chown redis:redis /etc/redis/redis-openvas.conf; then
		log ERROR "Failed to set ownership for Redis configuration."
		exit 1
	fi
	if ! run_command sh -c "echo 'db_address = /run/redis-openvas/redis.sock' >> /etc/openvas/openvas.conf"; then
		log ERROR "Failed to update openvas.conf."
		exit 1
	fi
	if ! run_command systemctl start redis-server@openvas.service; then
		log ERROR "Failed to start redis-server@openvas.service."
		exit 1
	fi
	if ! run_command systemctl enable redis-server@openvas.service; then
		log WARN "Failed to enable redis-server@openvas.service. Service may not start on boot."
	fi
	if ! run_command usermod -aG redis gvm; then
		log ERROR "Failed to add gvm user to redis group."
		exit 1
	fi
	log INFO "Redis setup completed."
}

# Adjusts permissions for OpenVAS directories and binaries.
adjusting_permissions() {
	log INFO "Adjusting permissions for OpenVAS directories and binaries..."
	for dir in /var/lib/notus /run/gvmd; do
		if ! run_command mkdir -p "$dir"; then
			log ERROR "Failed to create directory $dir."
			exit 1
		fi
	done
	for dir in /var/lib/gvm /var/lib/openvas /var/lib/notus /var/log/gvm /run/gvmd; do
		if ! run_command chown -R gvm:gvm "$dir"; then
			log ERROR "Failed to set ownership for $dir."
			exit 1
		fi
		if ! run_command chmod -R g+srw "$dir"; then
			log ERROR "Failed to set permissions for $dir."
			exit 1
		fi
		if [ "$(stat -c %U:%G "$dir")" != "gvm:gvm" ]; then
			log WARN "Directory $dir ownership is not gvm:gvm after setting. Verify permissions."
		fi
	done
	if ! run_command chown gvm:gvm /usr/local/sbin/gvmd; then
		log ERROR "Failed to set ownership for gvmd."
		exit 1
	fi
	if ! run_command chmod 6750 /usr/local/sbin/gvmd; then
		log ERROR "Failed to set permissions for gvmd."
		exit 1
	fi
	log INFO "Permissions adjusted."
}

# Configures GPG for feed validation.
feed_validation() {
	log INFO "Setting up feed validation with GPG..."
	if ! run_command curl -f -L https://www.greenbone.net/GBCommunitySigningKey.asc -o /tmp/GBCommunitySigningKey.asc; then
		log ERROR "Failed to download Greenbone signing key for feed validation."
		exit 1
	fi
	if ! run_command mkdir -p "$GNUPGHOME"; then
		log ERROR "Failed to create GPG home directory $GNUPGHOME."
		exit 1
	fi
	if ! run_command gpg --import /tmp/GBCommunitySigningKey.asc; then
		log ERROR "Failed to import Greenbone signing key for feed validation."
		exit 1
	fi
	if ! run_command sh -c "echo '8AE4BE429B60A59B311C2E739823FAA60ED1E580:6:' | gpg --import-ownertrust"; then
		log ERROR "Failed to set owner trust for Greenbone signing key."
		exit 1
	fi
	if ! run_command mkdir -p "$OPENVAS_GNUPG_HOME"; then
		log ERROR "Failed to create OpenVAS GPG directory $OPENVAS_GNUPG_HOME."
		exit 1
	fi
	if ! run_command cp -r "$GNUPGHOME"/* "$OPENVAS_GNUPG_HOME"/; then
		log ERROR "Failed to copy GPG keys to $OPENVAS_GNUPG_HOME."
		exit 1
	fi
	if ! run_command chown -R gvm:gvm "$OPENVAS_GNUPG_HOME"; then
		log ERROR "Failed to set ownership for $OPENVAS_GNUPG_HOME."
		exit 1
	fi
	log INFO "Feed validation setup completed."
}

# Configures sudo for the gvm group to run openvas with elevated privileges.
setting_up_sudo_for_scanning() {
	log INFO "Configuring sudo for gvm group..."
	if grep -Fxq "%gvm ALL = NOPASSWD: /usr/local/sbin/openvas" /etc/sudoers.d/gvm; then
		log INFO "Sudo already configured for gvm group."
	else
		log INFO "Setting up sudoers file for gvm group..."
		if ! run_command sh -c "echo '%gvm ALL = NOPASSWD: /usr/local/sbin/openvas' > /etc/sudoers.d/gvm"; then
			log ERROR "Failed to create sudoers file for gvm."
			exit 1
		fi
		if ! run_command chmod 0440 /etc/sudoers.d/gvm; then
			log ERROR "Failed to set permissions for sudoers file."
			exit 1
		fi
		if ! run_command visudo -c -f /etc/sudoers.d/gvm; then
			log ERROR "Sudoers file validation failed for /etc/sudoers.d/gvm."
			exit 1
		fi
		log INFO "Sudo configuration for gvm group completed."
	fi
}

# Sets up PostgreSQL database for gvmd.
setting_up_postgresql() {
	log INFO "Setting up PostgreSQL for gvmd..."
	if ! run_command apt install -y postgresql; then
		log ERROR "Failed to install PostgreSQL."
		exit 1
	fi
	if ! run_command systemctl start postgresql@15-main; then
		log ERROR "Failed to start PostgreSQL service."
		exit 1
	fi
	if ! runuser -l postgres -c 'createuser -DRS gvm'; then
		log ERROR "Failed to create PostgreSQL user gvm."
		exit 1
	fi
	if ! runuser -l postgres -c 'createdb -O gvm gvmd'; then
		log ERROR "Failed to create gvmd database."
		exit 1
	fi
	if ! runuser -l postgres -c 'psql gvmd -c "create role dba with superuser noinherit; grant dba to gvm;"'; then
		log ERROR "Failed to configure PostgreSQL roles for gvm."
		exit 1
	fi
	log INFO "PostgreSQL setup completed."
}

# Creates an admin user for gvmd and captures the password.
setting_up_an_admin_user() {
	log INFO "Creating admin user for gvmd..."
	local output
	output=$(/usr/local/sbin/gvmd --create-user=admin 2>&1)
	if [ $? -ne 0 ]; then
		log ERROR "Failed to create admin user for gvmd."
		exit 1
	fi
	# Extract password from output.
	local password
	password=$(echo "$output" | grep -oP "User created with password '\K[^']+")
	if [ -z "$password" ]; then
		log ERROR "Failed to extract admin password from gvmd output."
		exit 1
	fi
	# Store password in a temporary file with restricted permissions
	if ! echo "$password" > /tmp/gvm_admin_password; then
		log ERROR "Failed to store admin password."
		exit 1
	fi
	if ! chmod 600 /tmp/gvm_admin_password; then
		log ERROR "Failed to set permissions for admin password file."
		exit 1
	fi
	if ! chown gvm:gvm /tmp/gvm_admin_password; then
		log ERROR "Failed to set ownership for admin password file."
		exit 1
	fi
	log INFO "Admin user created."
}

# Sets the feed import owner to the admin user.
setting_the_feed_import_owner() {
	log INFO "Setting feed import owner to admin..."
	local admin_uuid
	admin_uuid=$(/usr/local/sbin/gvmd --get-users --verbose | grep admin | awk '{print $2}')
	if [ -z "$admin_uuid" ]; then
		log ERROR "Failed to retrieve admin user UUID."
		exit 1
	fi
	if ! /usr/local/sbin/gvmd --modify-setting 78eceaec-3385-11ea-b237-28d24461215b --value "$admin_uuid"; then
		log ERROR "Failed to set feed import owner."
		exit 1
	fi
	log INFO "Feed import owner set."
}

# Configures systemd services for OpenVAS components.
setting_up_services_for_systemd() {
	log INFO "Setting up systemd services..."

	# ospd-openvas service
	log INFO "Creating ospd-openvas systemd service..."
	if ! cat << EOF > "$BUILD_DIR/ospd-openvas.service"
[Unit]
Description=OSPd Wrapper for the OpenVAS Scanner (ospd-openvas)
Documentation=man:ospd-openvas(8) man:openvas(8)
After=network.target networking.service redis-server@openvas.service openvasd.service
Wants=redis-server@openvas.service openvasd.service
ConditionKernelCommandLine=!recovery

[Service]
Type=exec
User=gvm
Group=gvm
RuntimeDirectory=ospd
RuntimeDirectoryMode=2775
PIDFile=/run/ospd/ospd-openvas.pid
ExecStart=/usr/local/bin/ospd-openvas --foreground --unix-socket /run/ospd/ospd-openvas.sock --pid-file /run/ospd/ospd-openvas.pid --log-file /var/log/gvm/ospd-openvas.log --lock-file-dir /var/lib/openvas --socket-mode 0o770 --notus-feed-dir /var/lib/notus/advisories
SuccessExitStatus=SIGKILL
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF
	then
		log ERROR "Failed to create ospd-openvas systemd service file."
		exit 1
	fi
	if ! run_command cp -v "$BUILD_DIR/ospd-openvas.service" /etc/systemd/system/; then
		log ERROR "Failed to install ospd-openvas systemd service."
		exit 1
	fi

	# gvmd service
	log INFO "Creating gvmd systemd service..."
	if ! cat << EOF > "$BUILD_DIR/gvmd.service"
[Unit]
Description=Greenbone Vulnerability Manager daemon (gvmd)
After=network.target networking.service postgresql.service ospd-openvas.service
Wants=postgresql.service ospd-openvas.service
Documentation=man:gvmd(8)
ConditionKernelCommandLine=!recovery

[Service]
Type=exec
User=gvm
Group=gvm
PIDFile=/run/gvmd/gvmd.pid
RuntimeDirectory=gvmd
RuntimeDirectoryMode=2775
ExecStart=/usr/local/sbin/gvmd --foreground --osp-vt-update=/run/ospd/ospd-openvas.sock --listen-group=gvm
Restart=always
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
	then
		log ERROR "Failed to create gvmd systemd service file."
		exit 1
	fi
	if ! run_command cp -v "$BUILD_DIR/gvmd.service" /etc/systemd/system/; then
		log ERROR "Failed to install gvmd systemd service."
		exit 1
	fi

	# gsad service
	log INFO "Creating gsad systemd service..."
	if ! cat << EOF > "$BUILD_DIR/gsad.service"
[Unit]
Description=Greenbone Security Assistant daemon (gsad)
Documentation=man:gsad(8) https://www.greenbone.net
After=network.target gvmd.service
Wants=gvmd.service

[Service]
Type=exec
User=gvm
Group=gvm
RuntimeDirectory=gsad
RuntimeDirectoryMode=2775
PIDFile=/run/gsad/gsad.pid
ExecStart=/usr/local/sbin/gsad --foreground --listen=0.0.0.0 --port=9392 --ssl-certificate=/etc/gvm/gsad.crt --ssl-private-key=/etc/gvm/gsad.key
Restart=always
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
Alias=greenbone-security-assistant.service
EOF
	then
		log ERROR "Failed to create gsad systemd service file."
		exit 1
	fi
	if ! run_command cp -v "$BUILD_DIR/gsad.service" /etc/systemd/system/; then
		log ERROR "Failed to install gsad systemd service."
		exit 1
	fi

	# openvasd service
	log INFO "Creating openvasd systemd service..."
	if ! cat << EOF > "$BUILD_DIR/openvasd.service"
[Unit]
Description=OpenVASD
Documentation=https://github.com/greenbone/openvas-scanner/tree/main/rust/openvasd
ConditionKernelCommandLine=!recovery
[Service]
Type=exec
User=gvm
RuntimeDirectory=openvasd
RuntimeDirectoryMode=2775
ExecStart=/usr/local/bin/openvasd --mode service_notus --products /var/lib/notus/products --advisories /var/lib/notus/advisories --listening 127.0.0.1:3000
SuccessExitStatus=SIGKILL
Restart=always
RestartSec=60
[Install]
WantedBy=multi-user.target
EOF
	then
		log ERROR "Failed to create openvasd systemd service file."
		exit 1
	fi
	if ! run_command cp -v "$BUILD_DIR/openvasd.service" /etc/systemd/system/; then
		log ERROR "Failed to install openvasd systemd service."
		exit 1
	fi

	log INFO "Reloading systemd daemon..."
	if ! run_command systemctl daemon-reload; then
		log ERROR "Failed to reload systemd daemon."
		exit 1
	fi
	log INFO "Systemd services setup completed."
}

# Synchronizes Greenbone feed data.
feed_synchronization() {
	log INFO "Starting feed synchronization..."
	if ! run_command /usr/local/bin/greenbone-feed-sync; then
		log ERROR "Failed to synchronize Greenbone feed."
		exit 1
	fi
	log INFO "Feed synchronization completed."
}

# Starts and enables OpenVAS services.
start_openvas() {
	log INFO "Starting and enabling OpenVAS services..."
	for service in ospd-openvas gvmd gsad openvasd; do
		if ! run_command systemctl start "$service"; then
			log ERROR "Failed to start $service service."
			exit 1
		fi
		if ! run_command systemctl enable "$service"; then
			log WARN "Failed to enable $service service. Service may not start on boot."
		else
			log INFO "$service service started and enabled."
		fi
	done
	log INFO "OpenVAS services started and enabled."
}

# Displays login information for the OpenVAS web interface.
login_info() {
	# ANSI color codes
	local COLOR_INFO="\033[1;36m"  # Cyan for info
	local COLOR_RESET="\033[0m"
	local BOX_COLOR="\033[1;34m"  # Blue for box borders
	local WIDTH=60  # Box width

	log INFO "Providing login information for OpenVAS web interface..."

	# Retrieve password securely
	local password
	if [ -f /tmp/gvm_admin_password ]; then
		password=$(cat /tmp/gvm_admin_password)
	else
		log ERROR "Admin password file not found at /tmp/gvm_admin_password."
		exit 1
	fi
	# Get the primary network interface IP address
	local host_ip
	host_ip=$(ip -4 addr show | grep inet | awk '{print $2}' | cut -d'/' -f1 | grep -v '127.0.0.1' | head -n 1)
	if [ -z "$host_ip" ]; then
		log WARN "Could not determine host IP address. Using 'localhost' for URL."
		host_ip="localhost"
	fi
	local login_url="https://${host_ip}:9392"

	# Print boxed login information
	printf "\n${BOX_COLOR}%*s${COLOR_RESET}\n" "$WIDTH" | tr ' ' '#'  # Top border
	printf "${BOX_COLOR}#${COLOR_RESET} OpenVAS Web Interface Login%*s${BOX_COLOR}${COLOR_RESET}\n" $((WIDTH-28)) ""
	printf "${BOX_COLOR}${COLOR_RESET}%*s${BOX_COLOR}${COLOR_RESET}\n" $WIDTH | tr ' ' '-'  # Separator
	printf "${BOX_COLOR}#${COLOR_RESET} Username       : admin%*s${BOX_COLOR}${COLOR_RESET}\n" $((WIDTH-24)) ""
	printf "${BOX_COLOR}#${COLOR_RESET} Password       : %s%*s${BOX_COLOR}${COLOR_RESET}\n" "$password" $((WIDTH-19-${#password})) ""
	printf "${BOX_COLOR}#${COLOR_RESET} URL            : %s%*s${BOX_COLOR}${COLOR_RESET}\n" "$login_url" $((WIDTH-19-${#login_url})) ""
	printf "${BOX_COLOR}%*s${COLOR_RESET}\n" "$WIDTH" | tr ' ' '#'  # Bottom border
	printf "\n${COLOR_INFO}Consider changing the administrator password with the following command:${COLOR_RESET}\n"
	printf "\n${COLOR_INFO}/usr/local/sbin/gvmd --user=admin --new-password=<your_new_strong_password>${COLOR_RESET}\n"
	printf "\n"

	# Clean up the password file
	if ! rm -f /tmp/gvm_admin_password; then
		log WARN "Failed to remove temporary password file /tmp/gvm_admin_password."
	fi
}

# -----------------------------------
# Section: Cleanup
# -----------------------------------

# Cleans up temporary directories used during installation.
cleanup() {
	log INFO "Cleaning up temporary directories..."
	if ! rm -rf "$SOURCE_DIR" "$BUILD_DIR" "$INSTALL_DIR" 2>/dev/null; then
		log WARN "Failed to fully clean up temporary directories. Check permissions."
	fi
	log INFO "Cleanup completed."
}

# Trap errors and cleanup on exit
trap 'log ERROR "Script terminated due to an error."; cleanup' ERR
trap cleanup EXIT

# -----------------------------------
# Section: Main Execution
# -----------------------------------

# Main function to orchestrate the OpenVAS installation process.
main() {
	log INFO "Starting OpenVAS installation on $(date '+%Y-%m-%d %H:%M:%S')..."

	# Check if the installation is running as root
	check_root

	# Install the required packeges for OpenVAS
	install_packages

	# Set the apropriate environment variables for the installation
	set_environment

	# Check for the latest component versions
	check_latest_version

	# Creating a User and a Group
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#creating-a-user-and-a-group
	create_gvm_user

	# Setting a Source, Build and Install Directory
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#setting-a-source-build-and-install-directory
	create_directories

	# Importing the Greenbone Signing Key
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#importing-the-greenbone-signing-key
	import_signing_key

	# Generate self-signed SSL certificate for gsad
	generate_ssl_cert

	# Install gvm-libs
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#pg-gvm
	build_install_component \
		"gvm-libs" \
		"$GVM_LIBS_VERSION" \
		"-S $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION -B $BUILD_DIR/gvm-libs -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DSYSCONFDIR=/etc -DLOCALSTATEDIR=/var"

	# Install gvmd
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#pg-gvm
	build_install_component \
		"gvmd" \
		"$GVMD_VERSION" \
		"-S $SOURCE_DIR/gvmd-$GVMD_VERSION -B $BUILD_DIR/gvmd -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DLOCALSTATEDIR=/var -DSYSCONFDIR=/etc -DGVM_DATA_DIR=/var -DGVM_LOG_DIR=/var/log/gvm -DGVMD_RUN_DIR=/run/gvmd -DOPENVAS_DEFAULT_SOCKET=/run/ospd/ospd-openvas.sock -DGVM_FEED_LOCK_PATH=/var/lib/gvm/feed-update.lock -DLOGROTATE_DIR=/etc/logrotate.d"

	# Install pg-gvm
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#pg-gvm
	build_install_component \
		"pg-gvm" \
		"$PG_GVM_VERSION" \
		"-S $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION -B $BUILD_DIR/pg-gvm -DCMAKE_BUILD_TYPE=Release"

	# Install gsa
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#gsa
	build_install_gsa \
		"gsa" \
		"$GSA_VERSION"

	# Install gsad
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#gsad
	build_install_component \
		"gsad" \
		"$GSAD_VERSION" \
		"-S $SOURCE_DIR/gsad-$GSAD_VERSION -B $BUILD_DIR/gsad -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DSYSCONFDIR=/etc -DLOCALSTATEDIR=/var -DGVMD_RUN_DIR=/run/gvmd -DGSAD_RUN_DIR=/run/gsad -DGVM_LOG_DIR=/var/log/gvm -DLOGROTATE_DIR=/etc/logrotate.d"

	# Install openvas-smb
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#openvas-smb
	build_install_component \
		"openvas-smb" \
		"$OPENVAS_SMB_VERSION" \
		"-S $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION -B $BUILD_DIR/openvas-smb -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release"

	# Install openvas-scanner
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#openvas-scanner
	build_install_component \
		"openvas-scanner" \
		"$OPENVAS_SCANNER_VERSION" \
		"-S $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION -B $BUILD_DIR/openvas-scanner -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX -DCMAKE_BUILD_TYPE=Release -DSYSCONFDIR=/etc -DLOCALSTATEDIR=/var -DOPENVAS_FEED_LOCK_PATH=/var/lib/openvas/feed-update.lock -DOPENVAS_RUN_DIR=/run/ospd"

	# Install ospd-openvas
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#ospd-openvas
	build_install_opsd \
		"ospd-openvas" \
		"$OSPD_OPENVAS_VERSION"

	# Install openvasd
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#openvasd
	build_install_openvasd \
		"openvas-scanner" \
		"openvasd" \
		"$OPENVAS_DAEMON"

	# Install greenbone-feed-sync
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#greenbone-feed-sync
	build_install_py \
	"greenbone-feed-sync"

	# Install greenbone-feed-sync
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#gvm-tools
	build_install_py \
	"gvm-tools"

	# Performing a System Setup
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#performing-a-system-setup
	perform_system_setup

	# Adjusting Permissions
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#adjusting-permissions
	adjusting_permissions

	# Feed Validation
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#feed-validation
	feed_validation

	# Setting up sudo for Scanning
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#setting-up-sudo-for-scanning
	setting_up_sudo_for_scanning

	# Setting up PostgreSQL
	# URL: https://greenbone.github.io/docs/latest/22.4/source-build/index.html#setting-up-postgresql
	setting_up_postgresql

	# Setting up an Admin User
	setting_up_an_admin_user

	# Setting the Feed Import Owner
	setting_the_feed_import_owner

	# Setting up Services for Systemd
	setting_up_services_for_systemd

	# Performing a Feed Synchronization
	feed_synchronization

	# Starting the Greenbone Community Edition Services
	start_openvas

	# Providing Login Information
	login_info

	# Cleanup temporary directories
	cleanup

	log INFO "OpenVAS installation completed successfully."
}

main