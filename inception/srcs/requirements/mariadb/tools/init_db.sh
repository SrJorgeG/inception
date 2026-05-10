#!/bin/bash
set -e

# Iniciar el servicio de MariaDB en segundo plano para poder configurarlo
mysqld_safe --datadir=/var/lib/mysql &

# Esperar a que el servidor esté listo
sleep 5

# Leer secrets desde los archivos montados por Docker
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
DB_PASSWORD=$(cat /run/secrets/db_password)

# Crear la base de datos y el usuario si no existen
mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;"
mysql -u root -e "CREATE USER IF NOT EXISTS '\${MYSQL_USER}'@'%' IDENTIFIED BY '\${DB_PASSWORD}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '\${MYSQL_USER}'@'%';"
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '\${DB_ROOT_PASSWORD}';"
mysql -u root -p"${DB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

# Detener el servidor de fondo
mysqladmin -u root -p"${DB_ROOT_PASSWORD}" shutdown

# Iniciar el servidor en primer plano (como proceso principal del contenedor)
exec mysqld_safe