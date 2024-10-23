#!/bin/bash

# OpenVAS installation from sources for Debian 12 systems.
# Documentation: https://greenbone.github.io/docs/latest/

# Check if the script is running as root.

if [ "$EUID" -ne 0 ]
  then echo "Please run this script as root."
  exit
fi

# Initialize the flag variable
SSL_MODE=false

# Parse options
while getopts ":S" opt; do
    case $opt in
        S)
            SSL_MODE=true
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

# Install Required Packages
apt install --no-install-recommends --assume-yes build-essential curl cmake pkg-config gnupg || {
    echo "Exiting: Failed to install essential packages."
    exit 1
}
apt install -y libcjson-dev libcurl4-openssl-dev || {
    echo "Exiting: Failed to install libcjson-dev and libcurl4-openssl-dev."
    exit 1
}
apt install -y libglib2.0-dev libgpgme-dev libgnutls28-dev uuid-dev libssh-gcrypt-dev libhiredis-dev libxml2-dev libpcap-dev libnet1-dev libpaho-mqtt-dev || {
    echo "Exiting: Failed to install additional required packages."
    exit 1
}
apt install -y libldap2-dev libradcli-dev libpq-dev postgresql-server-dev-15 libical-dev xsltproc rsync libbsd-dev || {
    echo "Exiting: Failed to install PostgreSQL related packages."
    exit 1
}
apt install -y --no-install-recommends texlive-latex-extra texlive-fonts-recommended xmlstarlet zip rpm fakeroot dpkg nsis gpgsm wget sshpass openssh-client socat snmp python3 smbclient python3-lxml gnutls-bin xml-twig-tools || {
    echo "Exiting: Failed to install LaTeX and other packages."
    exit 1
}
apt install -y libmicrohttpd-dev gcc-mingw-w64 libpopt-dev libunistring-dev heimdal-dev perl-base bison libgcrypt20-dev libksba-dev nmap libjson-glib-dev libsnmp-dev || {
    echo "Exiting: Failed to install additional development packages."
    exit 1
}
apt install -y python3 python3-pip python3-setuptools python3-packaging python3-wrapt python3-cffi python3-psutil python3-lxml python3-defusedxml python3-paramiko python3-redis python3-gnupg python3-paho-mqtt python3-venv python3-impacket || {
    echo "Exiting: Failed to install Python packages."
    exit 1
}
apt install -y redis-server mosquitto postgresql || {
    echo "Exiting: Failed to install Redis and PostgreSQL."
    exit 1
}

# Set environment variables

export INSTALL_PREFIX=/usr/local
export PATH=$PATH:$INSTALL_PREFIX/sbin
export SOURCE_DIR=$HOME/source
export BUILD_DIR=$HOME/build
export INSTALL_DIR=$HOME/install
export GVM_LIBS_VERSION=22.10.0
export GVMD_VERSION=23.8.1
export PG_GVM_VERSION=22.6.5
export GSA_VERSION=23.2.1
export GSAD_VERSION=22.11.0
export OPENVAS_SMB_VERSION=22.5.3
export OPENVAS_SCANNER_VERSION=23.8.2
export OSPD_OPENVAS_VERSION=22.7.1
export NOTUS_VERSION=22.6.3
export GNUPGHOME=/tmp/openvas-gnupg
export OPENVAS_GNUPG_HOME=/etc/openvas/gnupg

# Create user

getent passwd gvm > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "GVM User already exists."
else
    useradd -r -M -U -G sudo -s /usr/sbin/nologin gvm || {
            echo "Exiting: Failed to create GVM user."
            exit 1
        }
    usermod -aG gvm $USER || {
            echo "Exiting: Failed to add user to GVM group."
            exit 1
        }
fi

# Creating a Source, Build and Install Directory

mkdir -p $SOURCE_DIR || { echo "Exiting: Failed to create source directory."; exit 1; }
mkdir -p $BUILD_DIR || { echo "Exiting: Failed to create build directory."; exit 1; }
mkdir -p $INSTALL_DIR || { echo "Exiting: Failed to create install directory."; exit 1; }

# Importing the Greenbone Signing Key
curl -f -L https://www.greenbone.net/GBCommunitySigningKey.asc -o /tmp/GBCommunitySigningKey.asc || {
    echo "Exiting: Failed to download the Greenbone signing key."
    exit 1
}
gpg --import /tmp/GBCommunitySigningKey.asc || {
    echo "Exiting: Failed to import the Greenbone signing key."
    exit 1
}

## Building and Installing the Components

# gvm-libs
curl -f -L https://github.com/greenbone/gvm-libs/archive/refs/tags/v$GVM_LIBS_VERSION.tar.gz -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz || {
    echo "Exiting: Failed to download gvm-libs."
    exit 1
}
curl -f -L https://github.com/greenbone/gvm-libs/releases/download/v$GVM_LIBS_VERSION/gvm-libs-v$GVM_LIBS_VERSION.tar.gz.asc -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc || {
    echo "Exiting: Failed to download gvm-libs signature."
    exit 1
}

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz || {
    echo "Exiting: Failed to extract gvm-libs."
    exit 1
}

mkdir -p "$BUILD_DIR"/gvm-libs && cd "$BUILD_DIR"/gvm-libs || {
    echo "Exiting: Failed to change directory to gvm-libs build directory."
    exit 1
}

cmake "$SOURCE_DIR"/gvm-libs-"$GVM_LIBS_VERSION" \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DSYSCONFDIR=/etc \
  -DLOCALSTATEDIR=/var || {
    echo "Exiting: CMake configuration for gvm-libs failed."
    exit 1
}

make -j"$(nproc)" || {
    echo "Exiting: Make failed for gvm-libs."
    exit 1
}

mkdir -p $INSTALL_DIR/gvm-libs || {
    echo "Exiting: Failed to create gvm-libs install directory."
    exit 1
}

make DESTDIR=$INSTALL_DIR/gvm-libs install || {
    echo "Exiting: Install failed for gvm-libs."
    exit 1
}

cp -rv $INSTALL_DIR/gvm-libs/* / || {
    echo "Exiting: Failed to copy gvm-libs to root."
    exit 1
}

# gvmd
curl -f -L https://github.com/greenbone/gvmd/archive/refs/tags/v$GVMD_VERSION.tar.gz -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz || {
    echo "Exiting: Failed to download gvmd."
    exit 1
}
curl -f -L https://github.com/greenbone/gvmd/releases/download/v$GVMD_VERSION/gvmd-$GVMD_VERSION.tar.gz.asc -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz.asc || {
    echo "Exiting: Failed to download gvmd signature."
    exit 1
}

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz || {
    echo "Exiting: Failed to extract gvmd."
    exit 1
}

mkdir -p "$BUILD_DIR"/gvmd && cd "$BUILD_DIR"/gvmd || {
    echo "Exiting: Failed to change directory to gvmd build directory."
    exit 1
}

cmake $SOURCE_DIR/gvmd-$GVMD_VERSION \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DLOCALSTATEDIR=/var \
  -DSYSCONFDIR=/etc \
  -DGVM_DATA_DIR=/var \
  -DGVMD_RUN_DIR=/run/gvmd \
  -DOPENVAS_DEFAULT_SOCKET=/run/ospd/ospd-openvas.sock \
  -DGVM_FEED_LOCK_PATH=/var/lib/gvm/feed-update.lock \
  -DSYSTEMD_SERVICE_DIR=/lib/systemd/system \
  -DLOGROTATE_DIR=/etc/logrotate.d || {
    echo "Exiting: CMake configuration for gvmd failed."
    exit 1
}

make -j"$(nproc)" || {
    echo "Exiting: Make failed for gvmd."
    exit 1
}

mkdir -p $INSTALL_DIR/gvmd || {
    echo "Exiting: Failed to create gvmd install directory."
    exit 1
}

make DESTDIR=$INSTALL_DIR/gvmd install || {
    echo "Exiting: Install failed for gvmd."
    exit 1
}

cp -rv $INSTALL_DIR/gvmd/* / || {
    echo "Exiting: Failed to copy gvmd to root."
    exit 1
}
# pg-gvm

curl -f -L https://github.com/greenbone/pg-gvm/archive/refs/tags/v$PG_GVM_VERSION.tar.gz -o $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz || {
    echo "Exiting: Failed to download pg-gvm."
    exit 1
}
curl -f -L https://github.com/greenbone/pg-gvm/releases/download/v$PG_GVM_VERSION/pg-gvm-$PG_GVM_VERSION.tar.gz.asc -o $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz.asc || {
    echo "Exiting: Failed to download pg-gvm signature."
    exit 1
}

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz || {
    echo "Exiting: Failed to extract pg-gvm."
    exit 1
}

mkdir -p "$BUILD_DIR"/pg-gvm && cd "$BUILD_DIR"/pg-gvm || {
    echo "Exiting: Failed to change directory to pg-gvm build directory."
    exit 1
}

cmake $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION \
  -DCMAKE_BUILD_TYPE=Release || {
    echo "Exiting: CMake configuration for pg-gvm failed."
    exit 1
}

make -j"$(nproc)" || {
    echo "Exiting: Make failed for pg-gvm."
    exit 1
}

mkdir -p $INSTALL_DIR/pg-gvm || {
    echo "Exiting: Failed to create pg-gvm install directory."
    exit 1
}

make DESTDIR=$INSTALL_DIR/pg-gvm install || {
    echo "Exiting: Install failed for pg-gvm."
    exit 1
}

cp -rv $INSTALL_DIR/pg-gvm/* / || {
    echo "Exiting: Failed to copy pg-gvm to root."
    exit 1
}

## Greenbone Security Assistant

# GSA

curl -f -L https://github.com/greenbone/gsa/releases/download/v$GSA_VERSION/gsa-dist-$GSA_VERSION.tar.gz -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz || {
    echo "Exiting: Failed to download GSA."
    exit 1
}
curl -f -L https://github.com/greenbone/gsa/releases/download/v$GSA_VERSION/gsa-dist-$GSA_VERSION.tar.gz.asc -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz.asc || {
    echo "Exiting: Failed to download GSA signature."
    exit 1
}

mkdir -p $SOURCE_DIR/gsa-$GSA_VERSION || {
    echo "Exiting: Failed to create GSA source directory."
    exit 1
}
tar -C $SOURCE_DIR/gsa-$GSA_VERSION -xvzf $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz || {
    echo "Exiting: Failed to extract GSA."
    exit 1
}

mkdir -p $INSTALL_PREFIX/share/gvm/gsad/web/ || {
    echo "Exiting: Failed to create GSA install directory."
    exit 1
}
cp -rv $SOURCE_DIR/gsa-$GSA_VERSION/* $INSTALL_PREFIX/share/gvm/gsad/web/ || {
    echo "Exiting: Failed to copy GSA files."
    exit 1
}

# gsad

curl -f -L https://github.com/greenbone/gsad/archive/refs/tags/v$GSAD_VERSION.tar.gz -o $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz || {
    echo "Exiting: Failed to download gsad."
    exit 1
}
curl -f -L https://github.com/greenbone/gsad/releases/download/v$GSAD_VERSION/gsad-$GSAD_VERSION.tar.gz.asc -o $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz.asc || {
    echo "Exiting: Failed to download gsad signature."
    exit 1
}

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz || {
    echo "Exiting: Failed to extract gsad."
    exit 1
}

mkdir -p "$BUILD_DIR"/gsad && cd "$BUILD_DIR"/gsad || {
    echo "Exiting: Failed to create or enter gsad build directory."
    exit 1
}

cmake $SOURCE_DIR/gsad-$GSAD_VERSION \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DSYSCONFDIR=/etc \
  -DLOCALSTATEDIR=/var \
  -DGVMD_RUN_DIR=/run/gvmd \
  -DGSAD_RUN_DIR=/run/gsad \
  -DLOGROTATE_DIR=/etc/logrotate.d || {
    echo "Exiting: CMake configuration failed."
    exit 1
}

make -j"$(nproc)" || {
    echo "Exiting: Build failed."
    exit 1
}

mkdir -p $INSTALL_DIR/gsad || {
    echo "Exiting: Failed to create gsad install directory."
    exit 1
}

make DESTDIR=$INSTALL_DIR/gsad install || {
    echo "Exiting: Installation of gsad failed."
    exit 1
}

cp -rv $INSTALL_DIR/gsad/* / || {
    echo "Exiting: Failed to copy gsad files."
    exit 1
}

# openvas-smb

curl -f -L https://github.com/greenbone/openvas-smb/archive/refs/tags/v$OPENVAS_SMB_VERSION.tar.gz -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz || {
    echo "Exiting: Failed to download openvas-smb."
    exit 1
}
curl -f -L https://github.com/greenbone/openvas-smb/releases/download/v$OPENVAS_SMB_VERSION/openvas-smb-v$OPENVAS_SMB_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc || {
    echo "Exiting: Failed to download openvas-smb signature."
    exit 1
}

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz || {
    echo "Exiting: Failed to extract openvas-smb."
    exit 1
}

mkdir -p "$BUILD_DIR"/openvas-smb && cd "$BUILD_DIR"/openvas-smb || {
    echo "Exiting: Failed to create or enter openvas-smb build directory."
    exit 1
}

cmake $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=Release || {
    echo "Exiting: CMake configuration failed."
    exit 1
}

make -j"$(nproc)" || {
    echo "Exiting: Build failed."
    exit 1
}

mkdir -p $INSTALL_DIR/openvas-smb || {
    echo "Exiting: Failed to create openvas-smb install directory."
    exit 1
}

make DESTDIR=$INSTALL_DIR/openvas-smb install || {
    echo "Exiting: Installation of openvas-smb failed."
    exit 1
}

cp -rv $INSTALL_DIR/openvas-smb/* / || {
    echo "Exiting: Failed to copy openvas-smb files."
    exit 1
}

# openvas-scanner

curl -f -L https://github.com/greenbone/openvas-scanner/archive/refs/tags/v$OPENVAS_SCANNER_VERSION.tar.gz -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz || {
    echo "Exiting: Failed to download openvas-scanner."
    exit 1
}
curl -f -L https://github.com/greenbone/openvas-scanner/releases/download/v$OPENVAS_SCANNER_VERSION/openvas-scanner-v$OPENVAS_SCANNER_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc || {
    echo "Exiting: Failed to download openvas-scanner signature."
    exit 1
}

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz || {
    echo "Exiting: Failed to extract openvas-scanner."
    exit 1
}

mkdir -p "$BUILD_DIR"/openvas-scanner && cd "$BUILD_DIR"/openvas-scanner || {
    echo "Exiting: Failed to create or enter openvas-scanner build directory."
    exit 1
}

cmake $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DINSTALL_OLD_SYNC_SCRIPT=OFF \
  -DSYSCONFDIR=/etc \
  -DLOCALSTATEDIR=/var \
  -DOPENVAS_FEED_LOCK_PATH=/var/lib/openvas/feed-update.lock \
  -DOPENVAS_RUN_DIR=/run/ospd || {
    echo "Exiting: CMake configuration failed."
    exit 1
}

make -j"$(nproc)" || {
    echo "Exiting: Build failed."
    exit 1
}

mkdir -p $INSTALL_DIR/openvas-scanner || {
    echo "Exiting: Failed to create openvas-scanner install directory."
    exit 1
}

make DESTDIR=$INSTALL_DIR/openvas-scanner install || {
    echo "Exiting: Installation of openvas-scanner failed."
    exit 1
}

cp -rv $INSTALL_DIR/openvas-scanner/* / || {
    echo "Exiting: Failed to copy openvas-scanner files."
    exit 1
}

# ospd-openvas

curl -f -L https://github.com/greenbone/ospd-openvas/archive/refs/tags/v$OSPD_OPENVAS_VERSION.tar.gz -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz || {
    echo "Exiting: Failed to download ospd-openvas."
    exit 1
}
curl -f -L https://github.com/greenbone/ospd-openvas/releases/download/v$OSPD_OPENVAS_VERSION/ospd-openvas-v$OSPD_OPENVAS_VERSION.tar.gz.asc -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc || {
    echo "Exiting: Failed to download ospd-openvas signature."
    exit 1
}

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz || {
    echo "Exiting: Failed to extract ospd-openvas."
    exit 1
}

cd $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION || {
    echo "Exiting: Failed to enter ospd-openvas directory."
    exit 1
}

mkdir -p $INSTALL_DIR/ospd-openvas || {
    echo "Exiting: Failed to create ospd-openvas install directory."
    exit 1
}

python3 -m pip install --root=$INSTALL_DIR/ospd-openvas --no-warn-script-location . || {
    echo "Exiting: Installation of ospd-openvas via pip failed."
    exit 1
}

cp -rv $INSTALL_DIR/ospd-openvas/* / || {
    echo "Exiting: Failed to copy ospd-openvas files."
    exit 1
}

# notus-scanner

# notus-scanner

curl -f -L https://github.com/greenbone/notus-scanner/archive/refs/tags/v$NOTUS_VERSION.tar.gz -o $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz || {
    echo "Exiting: Failed to download notus-scanner."
    exit 1
}
curl -f -L https://github.com/greenbone/notus-scanner/releases/download/v$NOTUS_VERSION/notus-scanner-v$NOTUS_VERSION.tar.gz.asc -o $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz.asc || {
    echo "Exiting: Failed to download notus-scanner signature."
    exit 1
}

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz || {
    echo "Exiting: Failed to extract notus-scanner."
    exit 1
}

cd $SOURCE_DIR/notus-scanner-$NOTUS_VERSION || {
    echo "Exiting: Failed to enter notus-scanner directory."
    exit 1
}

mkdir -p $INSTALL_DIR/notus-scanner || {
    echo "Exiting: Failed to create notus-scanner install directory."
    exit 1
}

python3 -m pip install --root=$INSTALL_DIR/notus-scanner --no-warn-script-location . || {
    echo "Exiting: Installation of notus-scanner via pip failed."
    exit 1
}

cp -rv $INSTALL_DIR/notus-scanner/* / || {
    echo "Exiting: Failed to copy notus-scanner files."
    exit 1
}


# greenbone-feed-sync

mkdir -p $INSTALL_DIR/greenbone-feed-sync || {
    echo "Exiting: Failed to create greenbone-feed-sync install directory."
    exit 1
}

python3 -m pip install --root=$INSTALL_DIR/greenbone-feed-sync --no-warn-script-location greenbone-feed-sync || {
    echo "Exiting: Installation of greenbone-feed-sync via pip failed."
    exit 1
}

cp -rv $INSTALL_DIR/greenbone-feed-sync/* / || {
    echo "Exiting: Failed to copy greenbone-feed-sync files."
    exit 1
}

# gvm-tools

mkdir -p $INSTALL_DIR/gvm-tools || {
    echo "Exiting: Failed to create gvm-tools install directory."
    exit 1
}

python3 -m pip install --root=$INSTALL_DIR/gvm-tools --no-warn-script-location gvm-tools || {
    echo "Exiting: Installation of gvm-tools via pip failed."
    exit 1
}

cp -rv $INSTALL_DIR/gvm-tools/* / || {
    echo "Exiting: Failed to copy gvm-tools files."
    exit 1
}

# Performing a System Setup

cp $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION/config/redis-openvas.conf /etc/redis/ || {
    echo "Exiting: Failed to copy redis-openvas.conf."
    exit 1
}

chown redis:redis /etc/redis/redis-openvas.conf || {
    echo "Exiting: Failed to change owner of redis-openvas.conf."
    exit 1
}

echo "db_address = /run/redis-openvas/redis.sock" | tee -a /etc/openvas/openvas.conf || {
    echo "Exiting: Failed to update openvas.conf."
    exit 1
}

systemctl start redis-server@openvas.service || {
    echo "Exiting: Failed to start redis-server@openvas.service."
    exit 1
}

systemctl enable redis-server@openvas.service || {
    echo "Exiting: Failed to enable redis-server@openvas.service."
    exit 1
}

usermod -aG redis gvm || {
    echo "Exiting: Failed to add gvm user to redis group."
    exit 1
}

# Setting up the Mosquitto MQTT Broker

systemctl start mosquitto.service || {
    echo "Exiting: Failed to start mosquitto.service."
    exit 1
}

systemctl enable mosquitto.service || {
    echo "Exiting: Failed to enable mosquitto.service."
    exit 1
}

echo -e "mqtt_server_uri = localhost:1883\ntable_driven_lsc = yes" | tee -a /etc/openvas/openvas.conf || {
    echo "Exiting: Failed to update openvas.conf."
    exit 1
}

# If the -S flag was set, create ssl cert for web
if $SSL_MODE; then
    # Setting up certs for SSL
    mkdir -p /etc/gvm || {
        echo "Exiting: Failed to create /etc/gvm."
        exit 1
    }

    openssl req -x509 -newkey rsa:4096 -keyout /etc/gvm/serverkey.pem -out /etc/gvm/servercert.pem -nodes -days 397 || {
        echo "Exiting: Failed to create SSL certificates."
        exit 1
    }

    chown -R root:root /etc/gvm || {
        echo "Exiting: Failed to change owner of /etc/gvm."
        exit 1
    }

    chmod 600 /etc/gvm/serverkey.pem || {
        echo "Exiting: Failed to set permissions on serverkey.pem."
        exit 1
    }

    chmod 644 /etc/gvm/servercert.pem || {
        echo "Exiting: Failed to set permissions on servercert.pem."
        exit 1
    }
fi

# Adjusting Permissions

mkdir -p /var/lib/gvm || {
    echo "Exiting: Failed to create /var/lib/gvm."
    exit 1
}

mkdir -p /var/lib/openvas || {
    echo "Exiting: Failed to create /var/lib/openvas."
    exit 1
}

mkdir -p /var/lib/notus || {
    echo "Exiting: Failed to create /var/lib/notus."
    exit 1
}

mkdir -p /var/log/gvm || {
    echo "Exiting: Failed to create /var/log/gvm."
    exit 1
}

chown -R gvm:gvm /var/lib/gvm || {
    echo "Exiting: Failed to change owner of /var/lib/gvm."
    exit 1
}

chown -R gvm:gvm /var/lib/openvas || {
    echo "Exiting: Failed to change owner of /var/lib/openvas."
    exit 1
}

chown -R gvm:gvm /var/lib/notus || {
    echo "Exiting: Failed to change owner of /var/lib/notus."
    exit 1
}

chown -R gvm:gvm /var/log/gvm || {
    echo "Exiting: Failed to change owner of /var/log/gvm."
    exit 1
}

chown -R gvm:gvm /run/gvmd || {
    echo "Exiting: Failed to change owner of /run/gvmd."
    exit 1
}

chmod -R g+srw /var/lib/gvm || {
    echo "Exiting: Failed to set permissions on /var/lib/gvm."
    exit 1
}

chmod -R g+srw /var/lib/openvas || {
    echo "Exiting: Failed to set permissions on /var/lib/openvas."
    exit 1
}

chmod -R g+srw /var/log/gvm || {
    echo "Exiting: Failed to set permissions on /var/log/gvm."
    exit 1
}

chown gvm:gvm /usr/local/sbin/gvmd || {
    echo "Exiting: Failed to change owner of /usr/local/sbin/gvmd."
    exit 1
}

chmod 6750 /usr/local/sbin/gvmd || {
    echo "Exiting: Failed to set permissions on /usr/local/sbin/gvmd."
    exit 1
}

# Feed Validation

curl -f -L https://www.greenbone.net/GBCommunitySigningKey.asc -o /tmp/GBCommunitySigningKey.asc || {
    echo "Exiting: Failed to download the GBCommunitySigningKey."
    exit 1
}

mkdir -p $GNUPGHOME || {
    echo "Exiting: Failed to create GNUPGHOME directory."
    exit 1
}

gpg --import /tmp/GBCommunitySigningKey.asc || {
    echo "Exiting: Failed to import GBCommunitySigningKey."
    exit 1
}

echo "8AE4BE429B60A59B311C2E739823FAA60ED1E580:6:" | gpg --import-ownertrust || {
    echo "Exiting: Failed to import owner trust."
    exit 1
}

mkdir -p $OPENVAS_GNUPG_HOME || {
    echo "Exiting: Failed to create OPENVAS_GNUPG_HOME directory."
    exit 1
}

cp -r /tmp/openvas-gnupg/* $OPENVAS_GNUPG_HOME/ || {
    echo "Exiting: Failed to copy files to OPENVAS_GNUPG_HOME."
    exit 1
}

chown -R gvm:gvm $OPENVAS_GNUPG_HOME || {
    echo "Exiting: Failed to change owner of OPENVAS_GNUPG_HOME."
    exit 1
}

# Setting up sudo for Scanning

if grep -Fxq "%gvm ALL = NOPASSWD: /usr/local/sbin/openvas" /etc/sudoers; then
    echo "Users of the gvm group are already configured to run the openvas-scanner application as root user via sudo."
else
    {
        echo "# allow users of the gvm group run openvas"
        echo "%gvm ALL = NOPASSWD: /usr/local/sbin/openvas"
    } >> /etc/sudoers || {
        echo "Exiting: Failed to update /etc/sudoers."
        exit 1
    }
    echo "Configured users of the gvm group to run the openvas-scanner application as root user via sudo."
fi

# Setting up PostgreSQL

echo "Starting PostgreSQL"
systemctl start postgresql || {
    echo "Exiting: Failed to start PostgreSQL."
    exit 1
}

echo "Setup gvm user, gvmd database and assign permissions on PostgreSQL."
runuser -l postgres -c 'createuser -DRS gvm' || {
    echo "Exiting: Failed to create PostgreSQL user gvm."
    exit 1
}

runuser -l postgres -c 'createdb -O gvm gvmd' || {
    echo "Exiting: Failed to create PostgreSQL database gvmd."
    exit 1
}

runuser -l postgres -c 'psql gvmd -c "create role dba with superuser noinherit; grant dba to gvm;"' || {
    echo "Exiting: Failed to assign permissions on PostgreSQL."
    exit 1
}

# Fix errors when starting gvmd: https://github.com/libellux/Libellux-Up-and-Running/issues/50
echo "Create the necessary links and cache to the most recent shared libraries."
ldconfig -v || {
    echo "Exiting: Failed to run ldconfig."
    exit 1
}

# Setting up an Admin User

echo "Creating the admin user."
/usr/local/sbin/gvmd --create-user=admin || {
    echo "Exiting: Failed to create the admin user."
    exit 1
}

# Setting the Feed Import Owner

echo "Setting the admin user as the Feed Import Owner"
/usr/local/sbin/gvmd --modify-setting 78eceaec-3385-11ea-b237-28d24461215b --value "$(/usr/local/sbin/gvmd --get-users --verbose | grep admin | awk '{print $2}')" || {
    echo "Exiting: Failed to set the admin user as the Feed Import Owner."
    exit 1
}

# Setting up Services for Systemd

cat << EOF > "$BUILD_DIR"/ospd-openvas.service
[Unit]
Description=OSPd Wrapper for the OpenVAS Scanner (ospd-openvas)
Documentation=man:ospd-openvas(8) man:openvas(8)
After=network.target networking.service redis-server@openvas.service mosquitto.service
Wants=redis-server@openvas.service mosquitto.service notus-scanner.service
ConditionKernelCommandLine=!recovery

[Service]
Type=exec
User=gvm
Group=gvm
RuntimeDirectory=ospd
RuntimeDirectoryMode=2775
PIDFile=/run/ospd/ospd-openvas.pid
ExecStart=/usr/local/bin/ospd-openvas --foreground --unix-socket /run/ospd/ospd-openvas.sock --pid-file /run/ospd/ospd-openvas.pid --log-file /var/log/gvm/ospd-openvas.log --lock-file-dir /var/lib/openvas --socket-mode 0o770 --mqtt-broker-address localhost --mqtt-broker-port 1883 --notus-feed-dir /var/lib/notus/advisories
SuccessExitStatus=SIGKILL
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

cp -v "$BUILD_DIR"/ospd-openvas.service /etc/systemd/system/

cat << EOF > "$BUILD_DIR"/notus-scanner.service
[Unit]
Description=Notus Scanner
Documentation=https://github.com/greenbone/notus-scanner
After=mosquitto.service
Wants=mosquitto.service
ConditionKernelCommandLine=!recovery

[Service]
Type=exec
User=gvm
RuntimeDirectory=notus-scanner
RuntimeDirectoryMode=2775
PIDFile=/run/notus-scanner/notus-scanner.pid
ExecStart=/usr/local/bin/notus-scanner --foreground --products-directory /var/lib/notus/products --log-file /var/log/gvm/notus-scanner.log
SuccessExitStatus=SIGKILL
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

cp -v "$BUILD_DIR"/notus-scanner.service /etc/systemd/system/

cat << EOF > "$BUILD_DIR"/gvmd.service
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

cp -v "$BUILD_DIR"/gvmd.service /etc/systemd/system/
if $SSL_MODE; then
    cat << EOF > "$BUILD_DIR"/gsad.service
    [Unit]
    Description=Greenbone Security Assistant daemon (gsad)
    Documentation=man:gsad(8) https://www.greenbone.net
    After=network.target gvmd.service
    Wants=gvmd.service

    [Service]
    Type=exec
    ####User=gvm
    ####Group=gvm
    RuntimeDirectory=gsad
    RuntimeDirectoryMode=2775
    PIDFile=/run/gsad/gsad.pid
    #ExecStart=/usr/local/sbin/gsad --foreground --listen=0.0.0.0 --port=9392 --http-only
    ExecStart=/usr/local/sbin/gsad --listen=0.0.0.0 --drop-privleges=gvm --port=443 --rport=80 -k /etc/gvm/serverkey.pem -c /etc/gvm/servercert.pem
    Restart=always
    TimeoutStopSec=10

    [Install]
    WantedBy=multi-user.target
    Alias=greenbone-security-assistant.service
EOF
else
    cat << EOF > "$BUILD_DIR"/gsad.service
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
    ExecStart=/usr/local/sbin/gsad --foreground --listen=0.0.0.0 --port=9392 --http-only
    Restart=always
    TimeoutStopSec=10

    [Install]
    WantedBy=multi-user.target
    Alias=greenbone-security-assistant.service
EOF
fi
cp -v "$BUILD_DIR"/gsad.service /etc/systemd/system/ || {
    echo "Exiting: Failed to copy gsad.service to /etc/systemd/system/"
    exit 1
}

systemctl daemon-reload || {
    echo "Exiting: Failed to reload systemd daemon."
    exit 1
}

# Download Openvas feeds.
echo "Download Openvas feeds. This is going to take time do not interrupt this process."
/usr/local/bin/greenbone-feed-sync || {
    echo "Exiting: Failed to download OpenVAS feeds."
    exit 1
}

# Enable the services
systemctl enable notus-scanner || {
    echo "Exiting: Failed to enable notus-scanner service."
    exit 1
}

systemctl enable ospd-openvas || {
    echo "Exiting: Failed to enable ospd-openvas service."
    exit 1
}

systemctl enable gvmd || {
    echo "Exiting: Failed to enable gvmd service."
    exit 1
}

systemctl enable gsad || {
    echo "Exiting: Failed to enable gsad service."
    exit 1
}

# Start the services
systemctl start notus-scanner || {
    echo "Exiting: Failed to start notus-scanner service."
    exit 1
}

systemctl start ospd-openvas || {
    echo "Exiting: Failed to start ospd-openvas service."
    exit 1
}

systemctl start gvmd || {
    echo "Exiting: Failed to start gvmd service."
    exit 1
}

systemctl start gsad || {
    echo "Exiting: Failed to start gsad service."
    exit 1
}

echo "OpenVAS installation has been completed."
