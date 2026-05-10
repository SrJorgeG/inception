# Usamos Debian Bullseye (versión específica, NO latest)
FROM debian:bullseye

# Instalar MariaDB server
RUN apt-get update && apt-get install -y \
    mariadb-server \
    && rm -rf /var/lib/apt/lists/*

# Copiar configuración personalizada
COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf

# Copiar script de inicialización
COPY tools/init_db.sh /usr/local/bin/init_db.sh
RUN chmod +x /usr/local/bin/init_db.sh

# Exponer el puerto por defecto de MariaDB
EXPOSE 3306

# Ejecutar el script de inicialización
ENTRYPOINT ["/usr/local/bin/init_db.sh"]