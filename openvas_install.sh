#!/bin/bash

# OpenVAS installation from sources for Debian 12 systems.
# Documentation: https://greenbone.github.io/docs/latest/

# Check if the script is running as root.

if [ "$EUID" -ne 0 ]
  then echo "Please run this script as root."
  exit
fi

# Install Required Packages

apt install --no-install-recommends --assume-yes build-essential curl cmake pkg-config gnupg
apt install -y libcjson-dev libcurl4-openssl-dev
apt install -y libglib2.0-dev libgpgme-dev libgnutls28-dev uuid-dev libssh-gcrypt-dev libhiredis-dev libxml2-dev libpcap-dev libnet1-dev libpaho-mqtt-dev
apt install -y libldap2-dev libradcli-dev libpq-dev postgresql-server-dev-15 libical-dev xsltproc rsync libbsd-dev
apt install -y --no-install-recommends texlive-latex-extra texlive-fonts-recommended xmlstarlet zip rpm fakeroot dpkg nsis gpgsm wget sshpass openssh-client socat snmp python3 smbclient python3-lxml gnutls-bin xml-twig-tools
apt install -y libmicrohttpd-dev gcc-mingw-w64 libpopt-dev libunistring-dev heimdal-dev perl-base bison libgcrypt20-dev libksba-dev nmap libjson-glib-dev libsnmp-dev
apt install -y python3 python3-pip python3-setuptools python3-packaging python3-wrapt python3-cffi python3-psutil python3-lxml python3-defusedxml python3-paramiko python3-redis python3-gnupg python3-paho-mqtt python3-venv python3-impacket
apt install -y redis-server mosquitto postgresql

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

getent passwd gvm > /dev/null 2&>1

if [ $? -eq 0 ]; then
    echo "GVM User already exists."
else
    useradd -r -M -U -G sudo -s /usr/sbin/nologin gvm
    usermod -aG gvm $USER
fi

# Creating a Source, Build and Install Directory

mkdir -p $SOURCE_DIR

mkdir -p $BUILD_DIR

mkdir -p $INSTALL_DIR

# Importing the Greenbone Signing Key

curl -f -L https://www.greenbone.net/GBCommunitySigningKey.asc -o /tmp/GBCommunitySigningKey.asc
gpg --import /tmp/GBCommunitySigningKey.asc

## Building and Installing the Components

# gvm-libs

curl -f -L https://github.com/greenbone/gvm-libs/archive/refs/tags/v$GVM_LIBS_VERSION.tar.gz -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz
curl -f -L https://github.com/greenbone/gvm-libs/releases/download/v$GVM_LIBS_VERSION/gvm-libs-v$GVM_LIBS_VERSION.tar.gz.asc -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz

mkdir -p $BUILD_DIR/gvm-libs && cd $BUILD_DIR/gvm-libs

cmake $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DSYSCONFDIR=/etc \
  -DLOCALSTATEDIR=/var

make -j$(nproc)

mkdir -p $INSTALL_DIR/gvm-libs

make DESTDIR=$INSTALL_DIR/gvm-libs install

cp -rv $INSTALL_DIR/gvm-libs/* /

# gvmd

curl -f -L https://github.com/greenbone/gvmd/archive/refs/tags/v$GVMD_VERSION.tar.gz -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz
curl -f -L https://github.com/greenbone/gvmd/releases/download/v$GVMD_VERSION/gvmd-$GVMD_VERSION.tar.gz.asc -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz.asc

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz

mkdir -p $BUILD_DIR/gvmd && cd $BUILD_DIR/gvmd

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
  -DLOGROTATE_DIR=/etc/logrotate.d

make -j$(nproc)

mkdir -p $INSTALL_DIR/gvmd

make DESTDIR=$INSTALL_DIR/gvmd install

cp -rv $INSTALL_DIR/gvmd/* /

# pg-gvm

curl -f -L https://github.com/greenbone/pg-gvm/archive/refs/tags/v$PG_GVM_VERSION.tar.gz -o $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz
curl -f -L https://github.com/greenbone/pg-gvm/releases/download/v$PG_GVM_VERSION/pg-gvm-$PG_GVM_VERSION.tar.gz.asc -o $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz.asc

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz

mkdir -p $BUILD_DIR/pg-gvm && cd $BUILD_DIR/pg-gvm

cmake $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION \
  -DCMAKE_BUILD_TYPE=Release

make -j$(nproc)

mkdir -p $INSTALL_DIR/pg-gvm

make DESTDIR=$INSTALL_DIR/pg-gvm install

cp -rv $INSTALL_DIR/pg-gvm/* /

## Greenbone Security Assistant

# GSA

curl -f -L https://github.com/greenbone/gsa/releases/download/v$GSA_VERSION/gsa-dist-$GSA_VERSION.tar.gz -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz
curl -f -L https://github.com/greenbone/gsa/releases/download/v$GSA_VERSION/gsa-dist-$GSA_VERSION.tar.gz.asc -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz.asc

mkdir -p $SOURCE_DIR/gsa-$GSA_VERSION
tar -C $SOURCE_DIR/gsa-$GSA_VERSION -xvzf $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz

mkdir -p $INSTALL_PREFIX/share/gvm/gsad/web/
cp -rv $SOURCE_DIR/gsa-$GSA_VERSION/* $INSTALL_PREFIX/share/gvm/gsad/web/

# gsad

curl -f -L https://github.com/greenbone/gsad/archive/refs/tags/v$GSAD_VERSION.tar.gz -o $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz
curl -f -L https://github.com/greenbone/gsad/releases/download/v$GSAD_VERSION/gsad-$GSAD_VERSION.tar.gz.asc -o $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz.asc

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz

mkdir -p $BUILD_DIR/gsad && cd $BUILD_DIR/gsad

cmake $SOURCE_DIR/gsad-$GSAD_VERSION \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DSYSCONFDIR=/etc \
  -DLOCALSTATEDIR=/var \
  -DGVMD_RUN_DIR=/run/gvmd \
  -DGSAD_RUN_DIR=/run/gsad \
  -DLOGROTATE_DIR=/etc/logrotate.d

make -j$(nproc)

mkdir -p $INSTALL_DIR/gsad

make DESTDIR=$INSTALL_DIR/gsad install

cp -rv $INSTALL_DIR/gsad/* /

# openvas-smb

curl -f -L https://github.com/greenbone/openvas-smb/archive/refs/tags/v$OPENVAS_SMB_VERSION.tar.gz -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz
curl -f -L https://github.com/greenbone/openvas-smb/releases/download/v$OPENVAS_SMB_VERSION/openvas-smb-v$OPENVAS_SMB_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz

mkdir -p $BUILD_DIR/openvas-smb && cd $BUILD_DIR/openvas-smb

cmake $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=Release

make -j$(nproc)

mkdir -p $INSTALL_DIR/openvas-smb

make DESTDIR=$INSTALL_DIR/openvas-smb install

cp -rv $INSTALL_DIR/openvas-smb/* /

# openvas-scanner

curl -f -L https://github.com/greenbone/openvas-scanner/archive/refs/tags/v$OPENVAS_SCANNER_VERSION.tar.gz -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz
curl -f -L https://github.com/greenbone/openvas-scanner/releases/download/v$OPENVAS_SCANNER_VERSION/openvas-scanner-v$OPENVAS_SCANNER_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz

mkdir -p $BUILD_DIR/openvas-scanner && cd $BUILD_DIR/openvas-scanner

cmake $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DINSTALL_OLD_SYNC_SCRIPT=OFF \
  -DSYSCONFDIR=/etc \
  -DLOCALSTATEDIR=/var \
  -DOPENVAS_FEED_LOCK_PATH=/var/lib/openvas/feed-update.lock \
  -DOPENVAS_RUN_DIR=/run/ospd

make -j$(nproc)

mkdir -p $INSTALL_DIR/openvas-scanner

make DESTDIR=$INSTALL_DIR/openvas-scanner install

cp -rv $INSTALL_DIR/openvas-scanner/* /

# ospd-openvas

curl -f -L https://github.com/greenbone/ospd-openvas/archive/refs/tags/v$OSPD_OPENVAS_VERSION.tar.gz -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
curl -f -L https://github.com/greenbone/ospd-openvas/releases/download/v$OSPD_OPENVAS_VERSION/ospd-openvas-v$OSPD_OPENVAS_VERSION.tar.gz.asc -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz

cd $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION

mkdir -p $INSTALL_DIR/ospd-openvas

python3 -m pip install --root=$INSTALL_DIR/ospd-openvas --no-warn-script-location .

cp -rv $INSTALL_DIR/ospd-openvas/* /

# notus-scanner

curl -f -L https://github.com/greenbone/notus-scanner/archive/refs/tags/v$NOTUS_VERSION.tar.gz -o $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz
curl -f -L https://github.com/greenbone/notus-scanner/releases/download/v$NOTUS_VERSION/notus-scanner-v$NOTUS_VERSION.tar.gz.asc -o $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz.asc

tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz

cd $SOURCE_DIR/notus-scanner-$NOTUS_VERSION

mkdir -p $INSTALL_DIR/notus-scanner

python3 -m pip install --root=$INSTALL_DIR/notus-scanner --no-warn-script-location .

cp -rv $INSTALL_DIR/notus-scanner/* /

# greenbone-feed-sync

mkdir -p $INSTALL_DIR/greenbone-feed-sync

python3 -m pip install --root=$INSTALL_DIR/greenbone-feed-sync --no-warn-script-location greenbone-feed-sync

cp -rv $INSTALL_DIR/greenbone-feed-sync/* /

# gvm-tools

mkdir -p $INSTALL_DIR/gvm-tools

python3 -m pip install --root=$INSTALL_DIR/gvm-tools --no-warn-script-location gvm-tools

cp -rv $INSTALL_DIR/gvm-tools/* /

# Performing a System Setup

cp $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION/config/redis-openvas.conf /etc/redis/
chown redis:redis /etc/redis/redis-openvas.conf
echo "db_address = /run/redis-openvas/redis.sock" | tee -a /etc/openvas/openvas.conf

systemctl start redis-server@openvas.service

systemctl enable redis-server@openvas.service

usermod -aG redis gvm

# Setting up the Mosquitto MQTT Broker

systemctl start mosquitto.service
systemctl enable mosquitto.service
echo -e "mqtt_server_uri = localhost:1883\ntable_driven_lsc = yes" | tee -a /etc/openvas/openvas.conf

# Adjusting Permissions

mkdir -p /var/lib/gvm
mkdir -p /var/lib/openvas
mkdir -p /var/lib/notus
mkdir -p /var/log/gvm

chown -R gvm:gvm /var/lib/gvm
chown -R gvm:gvm /var/lib/openvas
chown -R gvm:gvm /var/lib/notus
chown -R gvm:gvm /var/log/gvm
chown -R gvm:gvm /run/gvmd

chmod -R g+srw /var/lib/gvm
chmod -R g+srw /var/lib/openvas
chmod -R g+srw /var/log/gvm

chown gvm:gvm /usr/local/sbin/gvmd
chmod 6750 /usr/local/sbin/gvmd

# Feed Validation

curl -f -L https://www.greenbone.net/GBCommunitySigningKey.asc -o /tmp/GBCommunitySigningKey.asc

mkdir -p $GNUPGHOME

gpg --import /tmp/GBCommunitySigningKey.asc
echo "8AE4BE429B60A59B311C2E739823FAA60ED1E580:6:" | gpg --import-ownertrust

mkdir -p $OPENVAS_GNUPG_HOME
cp -r /tmp/openvas-gnupg/* $OPENVAS_GNUPG_HOME/
chown -R gvm:gvm $OPENVAS_GNUPG_HOME

# Setting up sudo for Scanning

if grep -Fxq "%gvm ALL = NOPASSWD: /usr/local/sbin/openvas" /etc/sudoers
then
echo "Users of the gvm group are already configured to run the openvas-scanner application as root user via sudo."
else

cat >> /etc/sudoers <<EOF

# allow users of the gvm group run openvas
%gvm ALL = NOPASSWD: /usr/local/sbin/openvas
EOF

echo "Configured users of the gvm group to run the openvas-scanner application as root user via sudo."

fi

# Setting up PostgreSQL

echo "Starting PostgreSQL"
systemctl start postgresql

echo "Setup gvm user, gvmd database and assign permissions on PostgreSQL."
runuser -l  postgres -c 'createuser -DRS gvm'
runuser -l  postgres -c 'createdb -O gvm gvmd'
runuser -l  postgres -c 'psql gvmd -c "create role dba with superuser noinherit; grant dba to gvm;"'

# Fix errors when starting gvmd: https://github.com/libellux/Libellux-Up-and-Running/issues/50
echo "Create the necessary links and cache to the most recent shared libraries."
ldconfig -v

# Setting up an Admin User

echo "Creating the admin user."
/usr/local/sbin/gvmd --create-user=admin

# Setting the Feed Import Owner

echo "Setting the admin user as the Feed Import Owner"
/usr/local/sbin/gvmd --modify-setting 78eceaec-3385-11ea-b237-28d24461215b --value `/usr/local/sbin/gvmd --get-users --verbose | grep admin | awk '{print $2}'`

# Setting up Services for Systemd

cat << EOF > $BUILD_DIR/ospd-openvas.service
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

cp -v $BUILD_DIR/ospd-openvas.service /etc/systemd/system/

cat << EOF > $BUILD_DIR/notus-scanner.service
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

cp -v $BUILD_DIR/notus-scanner.service /etc/systemd/system/

cat << EOF > $BUILD_DIR/gvmd.service
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

cp -v $BUILD_DIR/gvmd.service /etc/systemd/system/

cat << EOF > $BUILD_DIR/gsad.service
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

cp -v $BUILD_DIR/gsad.service /etc/systemd/system/

systemctl daemon-reload

# Download Openvas feeds.
echo "Download Openvas feeds. This is going to take time do not interrupt this process."
/usr/local/bin/greenbone-feed-sync

# Enable the services
systemctl enable notus-scanner
systemctl enable ospd-openvas
systemctl enable gvmd
systemctl enable gsad

# Start the services
systemctl start notus-scanner
systemctl start ospd-openvas
systemctl start gvmd
systemctl start gsad

echo "OpenVAS installation has been completed."