#!/bin/bash
set -e

# Read database password from Docker secret
DB_PASSWORD=$(cat /run/secrets/db_password)

# Wait for MariaDB to be ready
until mysqladmin ping -h"mariadb" --silent; do
    echo "Waiting for MariaDB to be ready..."
    sleep 2
done

# Only install WordPress if not already installed (idempotent)
if [ ! -f /var/www/html/wp-config.php ]; then
    echo "Downloading WordPress..."
    wp core download --allow-root --path=/var/www/html

    echo "Creating wp-config.php..."
    wp config create --allow-root \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="mariadb" \
        --path=/var/www/html

    echo "Installing WordPress..."
    wp core install --allow-root \
        --url="${DOMAIN_NAME}" \
        --title="Inception Site" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="$(cat /run/secrets/wp_admin_password)" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --path=/var/www/html

    echo "Creating additional user..."
    wp user create --allow-root \
        "${WP_USER}" \
        "${WP_USER_EMAIL}" \
        --user_pass="$(cat /run/secrets/wp_user_password)" \
        --role=author \
        --path=/var/www/html
fi

# Fix permissions so NGINX can read files
chown -R www-data:www-data /var/www/html

# Start PHP-FPM in foreground as PID 1
exec php-fpm7.4 -F
