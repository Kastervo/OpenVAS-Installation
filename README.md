# OpenVAS installation from sources for Debian 12 systems.

This script automates the installation and configuration of OpenVAS (Greenbone Community Edition) from source on Debian 12 systems. It follows the Greenbone Community Edition guidelines to set up a secure and fully functional vulnerability scanning environment, adhering to principles of secure-by-design, least privilege, and defense-in-depth.

## Description

The ``openvas_install.sh`` script installs OpenVAS and its dependencies, configures required system services (Redis, PostgreSQL), and sets up the Greenbone Security Assistant (GSA) web interface. Key features include:

- Automatic fetching of the latest component versions from GitHub.
- Structured logging with INFO, WARN, and ERROR levels.
- GPG signature verification for source packages.
- Creation of a dedicated ``gvm`` user and group for running services.
- Generation of self-signed SSL certificates for secure web access.
- Configuration of systemd services for OpenVAS components.
- Setup of feed synchronization and PostgreSQL database for vulnerability data.
- Secure permission settings.

## Usage

### 1. Prerequisites:
- A **clean, fully updated Debian 12** system with internet access.
- Root privileges (the script must be run as root).
- At least 1GB of free disk space in ``$HOME/source``, ``$HOME/build``, and ``$HOME/install`` directories.

### 2. Login as root:

```bash
sudo su
```

### 3. Download the Script:

```bash
curl -f -L https://raw.githubusercontent.com/Kastervo/OpenVAS-Installation/master/openvas_install.sh -o openvas_install.sh
```

### 4. Make the Script Executable:

```bash
chmod +x openvas_install.sh
```

### 5. Run the Script:

```bash
./openvas_install.sh
```

### 6. Access the Web Interface:

- After successful execution, the script outputs login details (username: ``admin``, password, and URL).
- Access the OpenVAS web interface at ``https://<host_ip>:9392``.
- For security, change the admin password using:

```
/usr/local/sbin/gvmd --user=admin --new-password=<new_strong_password>
```
*Make sure the TCP port ``9392`` is open on your firewall.*

### 7. Logs:

Installation logs are stored in ``/var/log/openvas_install.log`` for troubleshooting.

***Note:** Replace the self-signed SSL certificate with a trusted one for production environments. Ensure network connectivity to GitHub and Greenbone servers for version checks and feed synchronization.*

## Documentation

```
https://greenbone.github.io/docs/latest/22.4/source-build/
```

## Troubleshooting

Verify the services are running without errors:

```
sudo systemctl status ospd-openvas
sudo systemctl status gsad
sudo systemctl status gvmd
sudo systemctl status openvasd
```

Update the Openvas feeds:
```
/usr/local/bin/greenbone-feed-sync
```

Create a user:
```
/usr/local/sbin/gvmd --create-user=<username>
```

Reset a user password:
```
/usr/local/sbin/gvmd --user=<username> --new-password=<password>
```

Setting the Feed Import Owner:
```
/usr/local/sbin/gvmd --modify-setting 78eceaec-3385-11ea-b237-28d24461215b --value `/usr/local/sbin/gvmd --get-users --verbose | grep admin | awk '{print $2}'`
```

## Contributing

We welcome feedback to improve this project! Please read our ``CONTRIBUTING.md`` for guidelines on how to submit issues for bugs, enhancements, or documentation improvements. **Note**: We do not accept pull requests; all changes are implemented by maintainers.

## License

This repository is licensed under the Apache License 2.0 license.

## Disclaimer

The contents in this repository provided AS IS with absolutely NO warranty. KASTERVO LTD is not responsible and without any limitation, for any errors, omissions, losses or damages arising from the use of this repository.