#!/bin/bash
# WordPress HA bootstrap — installs Apache/PHP/WordPress and connects to RDS.
# ALB DNS is written into wp-config.php as WP_HOME / WP_SITEURL so that
# WordPress generates correct URLs even when the instance is behind a load balancer.
set -euo pipefail

exec > >(tee /var/log/wordpress-user-data.log | logger -t wordpress-user-data -s 2>/dev/console) 2>&1

DB_NAME="${db_name}"
DB_USER="${db_username}"
DB_PASSWORD="${db_password}"
DB_HOST="${db_host}"
DB_PORT="${db_port}"
TABLE_PREFIX="${wordpress_table_prefix}"
ALB_DNS="${alb_dns_name}"

# ── System update and LAMP packages ──────────────────────────────────────────

dnf upgrade -y

LAMP_PACKAGES=(
  wget
  httpd
  php-fpm
  php-mysqli
  php-json
  php
  php-devel
  php-mysqlnd
  php-gd
  php-intl
  php-mbstring
  php-xml
  php-zip
  gzip
  openssl
  tar
)

if ! dnf install -y "${LAMP_PACKAGES[@]}"; then
  dnf clean all
  dnf upgrade -y
  dnf install -y "${LAMP_PACKAGES[@]}"
fi

# MySQL/MariaDB client only — no database server on EC2 in this HA design.
dnf install -y mariadb105 || true

if ! command -v curl >/dev/null 2>&1; then
  dnf install -y curl-minimal
fi

# ── Start Apache and PHP-FPM ─────────────────────────────────────────────────

systemctl enable --now httpd
systemctl enable --now php-fpm

# Permissions
chown -R ec2-user:apache /var/www
chmod 2775 /var/www
find /var/www -type d -exec chmod 2775 {} \;
find /var/www -type f -exec chmod 0664 {} \;

# Quick LAMP sanity check
cat > /var/www/html/lamp-health.php <<'PHP'
<?php echo "lamp-ok\n"; ?>
PHP
curl -fsS http://127.0.0.1/lamp-health.php

rpm -q httpd
php --version
php -m | grep -E 'mysqli|mysqlnd'

# ── Instance metadata ─────────────────────────────────────────────────────────

METADATA_TOKEN=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)

metadata() {
  local path="$1"
  if [ -n "${METADATA_TOKEN}" ]; then
    curl -fsS -H "X-aws-ec2-metadata-token: ${METADATA_TOKEN}" "http://169.254.169.254/latest/meta-data/${path}"
  else
    curl -fsS "http://169.254.169.254/latest/meta-data/${path}"
  fi
}

INSTANCE_ID=$(metadata "instance-id")
AVAILABILITY_ZONE=$(metadata "placement/availability-zone")

# ── Wait for RDS to accept connections ───────────────────────────────────────

echo "Waiting for RDS at ${DB_HOST}:${DB_PORT} ..."
for attempt in $(seq 1 60); do
  if mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
       -e "SELECT 1;" >/dev/null 2>&1; then
    echo "RDS connection check passed (attempt ${attempt})"
    break
  fi
  if [ "${attempt}" -eq 60 ]; then
    echo "ERROR: RDS not reachable after ${attempt} attempts — exiting"
    exit 1
  fi
  echo "  attempt ${attempt}/60 — sleeping 10 s"
  sleep 10
done

# ── Download and install WordPress ───────────────────────────────────────────

wget https://wordpress.org/latest.tar.gz -O /tmp/latest.tar.gz
tar -xzf /tmp/latest.tar.gz -C /tmp

rm -rf /var/www/html/*
cp -r /tmp/wordpress/* /var/www/html/
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

# ── Configure wp-config.php ──────────────────────────────────────────────────

replace_placeholder() {
  local key="$1"
  local value="$2"
  local escaped
  escaped=$(printf '%s' "$value" | sed -e 's/[\/&]/\\&/g')
  sed -i "s|${key}|${escaped}|g" /var/www/html/wp-config.php
}

replace_placeholder "database_name_here" "${DB_NAME}"
replace_placeholder "username_here"      "${DB_USER}"
replace_placeholder "password_here"      "${DB_PASSWORD}"
replace_placeholder "localhost"          "${DB_HOST}:${DB_PORT}"

sed -i "s/^\$table_prefix = 'wp_';/\$table_prefix = '${TABLE_PREFIX}';/" /var/www/html/wp-config.php

# WordPress must know the ALB URL so it generates correct links and redirects.
# Without this, WordPress uses the EC2 private DNS and breaks behind the ALB.
cat >> /var/www/html/wp-config.php <<PHP

// HA: Force WordPress to use the ALB DNS so URLs are correct behind the load balancer.
define( 'WP_HOME',    'http://${ALB_DNS}' );
define( 'WP_SITEURL', 'http://${ALB_DNS}' );

// Trust the X-Forwarded-Proto header from the ALB.
if ( isset( \$_SERVER['HTTP_X_FORWARDED_FOR'] ) ) {
    \$_SERVER['REMOTE_ADDR'] = explode( ',', \$_SERVER['HTTP_X_FORWARDED_FOR'] )[0];
}
PHP

# Fetch WordPress authentication salts
if curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ -o /tmp/wp-salts.php; then
  awk '
    FNR == NR { salts = salts $0 "\n"; next }
    /AUTH_KEY/ { printf "%s", salts; skip = 1; next }
    /NONCE_SALT/ && skip { skip = 0; next }
    !skip { print }
  ' /tmp/wp-salts.php /var/www/html/wp-config.php > /tmp/wp-config.php
  mv /tmp/wp-config.php /var/www/html/wp-config.php
fi

# ── Health check files ────────────────────────────────────────────────────────

# Static health check used by ALB target group
cat > /var/www/html/health.html <<EOF
ok
name_prefix=${name_prefix}
instance_id=${INSTANCE_ID}
availability_zone=${AVAILABILITY_ZONE}
database_host=${DB_HOST}
database_name=${DB_NAME}
EOF

# PHP → RDS connectivity check
cat > /var/www/html/db-health.php <<'PHP'
<?php
$host     = getenv('DB_HOST') ?: '${DB_HOST}';
$user     = getenv('DB_USER') ?: '${DB_USER}';
$pass     = getenv('DB_PASS') ?: '${DB_PASSWORD}';
$db       = getenv('DB_NAME') ?: '${DB_NAME}';
$port     = (int)(getenv('DB_PORT') ?: ${DB_PORT});

$mysqli = mysqli_init();
if (!$mysqli) {
    http_response_code(500);
    echo "db-error: mysqli_init failed\n";
    exit;
}
if (!@$mysqli->real_connect($host, $user, $pass, $db, $port)) {
    http_response_code(500);
    echo "db-error: " . mysqli_connect_error() . "\n";
    exit;
}
$result = $mysqli->query('SELECT 1 AS ok');
if (!$result) {
    http_response_code(500);
    echo "db-error: query failed\n";
    exit;
}
echo "db-ok\n";
PHP

# Substitute shell variables inside the heredoc above
sed -i \
  "s|\${DB_HOST}|${DB_HOST}|g; s|\${DB_USER}|${DB_USER}|g; \
   s|\${DB_PASSWORD}|${DB_PASSWORD}|g; s|\${DB_NAME}|${DB_NAME}|g; \
   s|\${DB_PORT}|${DB_PORT}|g" \
  /var/www/html/db-health.php

# Store connection info for debugging (readable only by ec2-user)
cat > /home/ec2-user/rds-connection.txt <<EOF
RDS connection — ${name_prefix} HA lab
Host:     ${DB_HOST}
Port:     ${DB_PORT}
Database: ${DB_NAME}
User:     ${DB_USER}
ALB:      ${ALB_DNS}
EOF
chown ec2-user:ec2-user /home/ec2-user/rds-connection.txt
chmod 600 /home/ec2-user/rds-connection.txt

# ── Apache configuration ──────────────────────────────────────────────────────

# Enable AllowOverride for WordPress .htaccess permalinks
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' \
  /etc/httpd/conf/httpd.conf

# Final permissions
chown -R apache:apache /var/www/html
chmod 2775 /var/www
find /var/www -type d -exec chmod 2775 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod 640 /var/www/html/wp-config.php
restorecon -R /var/www/html || true

systemctl restart php-fpm
systemctl restart httpd

systemctl is-enabled httpd
systemctl is-active --quiet httpd
echo "WordPress HA bootstrap complete — instance ${INSTANCE_ID} in ${AVAILABILITY_ZONE}"
