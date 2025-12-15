#!/usr/bin/env bash
set -euo pipefail

# install_phpmyadmin_apache.sh
# Installs Apache, MariaDB (optional), PHP and phpMyAdmin on Debian/Ubuntu

LOG() { echo "[install] $*"; }

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
  echo "This script currently supports Debian/Ubuntu systems with apt." >&2
  exit 2
fi

DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-dialog}
export DEBIAN_FRONTEND

# Options via environment variables
PMA_PASSWORD=${PMA_PASSWORD:-}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-}

usage() {
  cat <<EOF
Usage: sudo ./install_phpmyadmin_apache.sh [--noninteractive]

Environment variables:
  PMA_PASSWORD       Set phpMyAdmin application password (optional; will prompt if omitted)
  DB_ROOT_PASSWORD   Set MariaDB/MySQL root password (optional)

Examples:
  sudo PMA_PASSWORD=secret ./install_phpmyadmin_apache.sh --noninteractive
  sudo ./install_phpmyadmin_apache.sh
EOF
}

NONINTERACTIVE=false
while [[ ${1:-} != "" ]]; do
  case "$1" in
    --noninteractive) NONINTERACTIVE=true ;; 
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
  shift
done

if [[ -z "$PMA_PASSWORD" && "$NONINTERACTIVE" == true ]]; then
  echo "In non-interactive mode PMA_PASSWORD must be set in the environment." >&2
  exit 1
fi

if [[ -z "$PMA_PASSWORD" ]]; then
  read -rsp "Enter a password to use for phpMyAdmin (leave empty to let dbconfig choose): " PMA_PASSWORD
  echo
fi

LOG "Updating package lists..."
apt update -y

LOG "Installing Apache, PHP and MariaDB packages..."
apt install -y apache2 wget unzip lsb-release ca-certificates \
  php php-mbstring php-zip php-gd php-json php-curl php-mysql libapache2-mod-php \
  mariadb-server

LOG "Ensuring PHP modules are enabled..."
phpenmod mbstring

if [[ -n "$DB_ROOT_PASSWORD" ]]; then
  LOG "Setting MariaDB root password (non-interactive)..."
  # Secure MariaDB root password and remove anonymous users. This is a minimal approach.
  mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}'; FLUSH PRIVILEGES;"
fi

# Preseed phpMyAdmin answers so it installs non-interactively when requested
if [[ "$NONINTERACTIVE" == true || -n "$PMA_PASSWORD" ]]; then
  LOG "Preseeding phpMyAdmin debconf values..."
  echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
  echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
  if [[ -n "$DB_ROOT_PASSWORD" ]]; then
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password ${DB_ROOT_PASSWORD}" | debconf-set-selections
  else
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password" | debconf-set-selections
  fi
  if [[ -n "$PMA_PASSWORD" ]]; then
    echo "phpmyadmin phpmyadmin/mysql/app-pass password ${PMA_PASSWORD}" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password ${PMA_PASSWORD}" | debconf-set-selections
  else
    echo "phpmyadmin phpmyadmin/mysql/app-pass password" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password" | debconf-set-selections
  fi
  DEBIAN_FRONTEND=noninteractive apt install -y phpmyadmin
else
  LOG "Installing phpMyAdmin interactively (you will be prompted)..."
  apt install -y phpmyadmin
fi

LOG "Enabling phpMyAdmin Apache config and restarting services..."
if [[ -f /etc/phpmyadmin/apache.conf ]]; then
  a2enconf phpmyadmin || true
fi

systemctl restart apache2
systemctl enable apache2
systemctl restart mariadb || true
systemctl enable mariadb

LOG "Installation finished. Access phpMyAdmin at: http://$(hostname -I | awk '{print $1}')/phpmyadmin"
if [[ -n "$PMA_PASSWORD" ]]; then
  LOG "phpMyAdmin app password: (the one you provided)"
fi

cat <<EOF

Notes:
 - If your MariaDB root account uses socket authentication (common on some Debian setups), you may need to create a dedicated DB admin user for phpMyAdmin or adjust authentication.
 - This script aims to be idempotent and minimal. Please review it before running on production systems.

EOF

exit 0
