#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/wordpress-user-data.log | logger -t wordpress-user-data -s 2>/dev/console) 2>&1

# Terraform template variables
DB_NAME="${db_name}"
DB_USER="${db_username}"
DB_PASSWORD="${db_password}"
DB_HOST="${db_host}"
DB_PORT="${db_port}"
TABLE_PREFIX="${wordpress_table_prefix}"
ALB_DNS="${alb_dns_name}"
NAME_PREFIX="${name_prefix}"
S3_BUCKET="${s3_bucket}"
AWS_REGION="${aws_region}"

# ── System packages ───────────────────────────────────────────────────────────

dnf upgrade -y

LAMP_PACKAGES=(
  wget httpd php-fpm php-mysqli php-json php php-devel
  php-mysqlnd php-gd php-intl php-mbstring php-xml php-zip
  gzip openssl tar
)

if ! dnf install -y "$${LAMP_PACKAGES[@]}"; then
  dnf clean all && dnf upgrade -y && dnf install -y "$${LAMP_PACKAGES[@]}"
fi

dnf install -y mariadb105 || true
command -v curl >/dev/null 2>&1 || dnf install -y curl-minimal

systemctl enable --now httpd
systemctl enable --now php-fpm

chown -R ec2-user:apache /var/www
chmod 2775 /var/www
find /var/www -type d -exec chmod 2775 {} \;
find /var/www -type f -exec chmod 0664 {} \;

# ── Instance metadata ─────────────────────────────────────────────────────────

METADATA_TOKEN=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)

metadata() {
  local path="$1"
  if [ -n "$${METADATA_TOKEN}" ]; then
    curl -fsS -H "X-aws-ec2-metadata-token: $${METADATA_TOKEN}" "http://169.254.169.254/latest/meta-data/$${path}"
  else
    curl -fsS "http://169.254.169.254/latest/meta-data/$${path}"
  fi
}

INSTANCE_ID=$(metadata "instance-id")
AVAILABILITY_ZONE=$(metadata "placement/availability-zone")

# ── Wait for RDS ──────────────────────────────────────────────────────────────

echo "Waiting for RDS at $${DB_HOST}:$${DB_PORT} ..."
for attempt in $(seq 1 60); do
  if mysql -h "$${DB_HOST}" -P "$${DB_PORT}" -u "$${DB_USER}" -p"$${DB_PASSWORD}" "$${DB_NAME}" \
       -e "SELECT 1;" >/dev/null 2>&1; then
    echo "RDS connection check passed (attempt $${attempt})"
    break
  fi
  if [ "$${attempt}" -eq 60 ]; then
    echo "ERROR: RDS not reachable after $${attempt} attempts"
    exit 1
  fi
  echo "  attempt $${attempt}/60 — sleeping 10s"
  sleep 10
done

# ── Install WordPress ─────────────────────────────────────────────────────────

wget https://wordpress.org/latest.tar.gz -O /tmp/latest.tar.gz
tar -xzf /tmp/latest.tar.gz -C /tmp
rm -rf /var/www/html/*
cp -r /tmp/wordpress/* /var/www/html/
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

# ── Configure wp-config.php ───────────────────────────────────────────────────

replace_placeholder() {
  local key="$1" value="$2" escaped
  escaped=$(printf '%s' "$${value}" | sed -e 's/[\/&]/\\&/g')
  sed -i "s|$${key}|$${escaped}|g" /var/www/html/wp-config.php
}

replace_placeholder "database_name_here" "$${DB_NAME}"
replace_placeholder "username_here"      "$${DB_USER}"
replace_placeholder "password_here"      "$${DB_PASSWORD}"
replace_placeholder "localhost"          "$${DB_HOST}:$${DB_PORT}"
sed -i "s/^\$table_prefix = 'wp_';/\$table_prefix = '$${TABLE_PREFIX}';/" /var/www/html/wp-config.php

# ALB DNS 고정 — ASG 환경에서 URL 정합성 보장
cat >> /var/www/html/wp-config.php <<PHP

// HA: ALB DNS로 URL 고정
define( 'WP_HOME',    'http://$${ALB_DNS}' );
define( 'WP_SITEURL', 'http://$${ALB_DNS}' );

// S3 Offload Media — AWS Region 및 버킷 설정
define( 'AS3CF_SETTINGS', serialize( array(
    'provider' => 'aws',
    'use-server-roles' => true,
    'bucket' => '$${S3_BUCKET}',
    'region' => '$${AWS_REGION}',
    'copy-to-s3' => true,
    'serve-from-s3' => true,
    'remove-local-file' => false,
) ) );

// X-Forwarded-For 신뢰 (ALB)
if ( isset( \$_SERVER['HTTP_X_FORWARDED_FOR'] ) ) {
    \$_SERVER['REMOTE_ADDR'] = explode( ',', \$_SERVER['HTTP_X_FORWARDED_FOR'] )[0];
}
PHP

# WordPress 인증 Salt 설정
if curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ -o /tmp/wp-salts.php; then
  awk '
    FNR == NR { salts = salts $0 "\n"; next }
    /AUTH_KEY/ { printf "%s", salts; skip = 1; next }
    /NONCE_SALT/ && skip { skip = 0; next }
    !skip { print }
  ' /tmp/wp-salts.php /var/www/html/wp-config.php > /tmp/wp-config.php
  mv /tmp/wp-config.php /var/www/html/wp-config.php
fi

# ── WP-CLI 설치 및 WP Offload Media 플러그인 자동 설치 ───────────────────────

curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
  -o /usr/local/bin/wp
chmod +x /usr/local/bin/wp

# WordPress 설치 완료 후 플러그인 설치 (설치가 완료된 상태에서만 작동)
# WordPress 초기 설정은 브라우저에서 진행 후 플러그인이 활성화됨
wp package install deliciousbrains/wp-offload-media --allow-root 2>/dev/null || true

# ── Health check 파일 ─────────────────────────────────────────────────────────

cat > /var/www/html/health.html <<EOF
ok
name_prefix=$${NAME_PREFIX}
instance_id=$${INSTANCE_ID}
availability_zone=$${AVAILABILITY_ZONE}
database_host=$${DB_HOST}
database_name=$${DB_NAME}
s3_bucket=$${S3_BUCKET}
EOF

cat > /var/www/html/db-health.php <<PHP
<?php
\$host = '$${DB_HOST}';
\$user = '$${DB_USER}';
\$pass = '$${DB_PASSWORD}';
\$db   = '$${DB_NAME}';
\$port = (int)'$${DB_PORT}';
\$mysqli = mysqli_init();
if (!\$mysqli) { http_response_code(500); echo "db-error: mysqli_init failed\n"; exit; }
if (!@\$mysqli->real_connect(\$host, \$user, \$pass, \$db, \$port)) {
    http_response_code(500); echo "db-error: " . mysqli_connect_error() . "\n"; exit;
}
\$result = \$mysqli->query('SELECT 1 AS ok');
if (!\$result) { http_response_code(500); echo "db-error: query failed\n"; exit; }
echo "db-ok\n";
PHP

# S3 접근 확인 파일
cat > /var/www/html/s3-health.php <<PHP
<?php
\$bucket = '$${S3_BUCKET}';
\$region = '$${AWS_REGION}';
\$url = "https://s3.$${region}.amazonaws.com/$${bucket}";
\$headers = @get_headers(\$url);
if (\$headers && strpos(\$headers[0], '200') !== false || strpos(\$headers[0], '403') !== false) {
    echo "s3-ok bucket=$${bucket}\n";
} else {
    http_response_code(500);
    echo "s3-error: cannot reach bucket\n";
}
PHP

# ── Apache 설정 ───────────────────────────────────────────────────────────────

sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' \
  /etc/httpd/conf/httpd.conf

chown -R apache:apache /var/www/html
chmod 2775 /var/www
find /var/www -type d -exec chmod 2775 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod 640 /var/www/html/wp-config.php
restorecon -R /var/www/html || true

systemctl restart php-fpm
systemctl restart httpd

# ── 연결 정보 저장 ────────────────────────────────────────────────────────────

cat > /home/ec2-user/connection-info.txt <<EOF
=== WordPress HA + S3 Final Project ===
Instance:   $${INSTANCE_ID} ($${AVAILABILITY_ZONE})
ALB:        $${ALB_DNS}
DB Host:    $${DB_HOST}:$${DB_PORT}
DB Name:    $${DB_NAME}
S3 Bucket:  $${S3_BUCKET} ($${AWS_REGION})
EOF
chown ec2-user:ec2-user /home/ec2-user/connection-info.txt
chmod 600 /home/ec2-user/connection-info.txt

echo "Bootstrap complete — $${INSTANCE_ID} in $${AVAILABILITY_ZONE}"
