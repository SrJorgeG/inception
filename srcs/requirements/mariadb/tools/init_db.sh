#!/bin/bash
set -e

# Start MariaDB temporarily in background for initialization
mysqld_safe --datadir=/var/lib/mysql &

# Wait for the server to be ready
sleep 5

# Read secrets from Docker-mounted files
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
DB_PASSWORD=$(cat /run/secrets/db_password)

# Create database and user if they don't exist (idempotent)
mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;"
mysql -u root -e "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';"
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';"
mysql -p"${DB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

# Stop the background server
mysqladmin -u root -p"${DB_ROOT_PASSWORD}" shutdown

# Start MariaDB in foreground as PID 1
exec mysqld_safe