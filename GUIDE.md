# Guía Paso a Paso: Proyecto Inception (42)

Esta guía te llevará de la mano para construir una infraestructura completa con Docker Compose compuesta por **NGINX**, **WordPress + PHP-FPM** y **MariaDB**, cumpliendo con todos los requisitos del subject de 42.

---

## Tabla de Contenidos

1. [Preparación del Entorno](#1-preparación-del-entorno)
2. [Estructura de Carpetas](#2-estructura-de-carpetas)
3. [Paso 1: MariaDB](#paso-1-mariadb)
4. [Paso 2: WordPress + PHP-FPM](#paso-2-wordpress--php-fpm)
5. [Paso 3: NGINX](#paso-3-nginx)
6. [Paso 4: Docker Compose](#paso-4-docker-compose)
7. [Paso 5: Makefile](#paso-5-makefile)
8. [Paso 6: Verificación](#paso-6-verificación)
9. [Troubleshooting](#troubleshooting)
10. [Checklist de Entrega](#checklist-de-entrega)

---

## 1. Preparación del Entorno

### 1.1. Instalar Docker y Docker Compose

**¿Por qué?** Docker nos permite encapsular cada servicio en un contenedor aislado, garantizando que la infraestructura sea reproducible y no dependa del sistema host.

```bash
# Actualizar paquetes
sudo apt update && sudo apt upgrade -y

# Instalar dependencias
sudo apt install -y ca-certificates curl gnupg lsb-release

# Añadir la clave GPG oficial de Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Añadir el repositorio de Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker Engine y Docker Compose
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Añadir tu usuario al grupo docker (evita usar sudo en cada comando)
sudo usermod -aG docker $USER
newgrp docker
```

Verifica la instalación:
```bash
docker --version
docker compose version
```

### 1.2. Configurar el Dominio Local

**¿Por qué?** El subject requiere que el dominio sea `login.42.fr` (donde `login` es tu nombre de usuario de 42). Al apuntarlo a la IP local (`127.0.0.1`), podrás acceder al sitio desde tu navegador sin necesidad de un DNS real.

```bash
# Añadir la línea al final del archivo /etc/hosts
sudo echo "127.0.0.1 jgomez-d.42.fr" >> /etc/hosts
```

> **Nota:** Reemplaza `jgomez-d` con tu login de 42. Puedes verificarlo con el comando `echo $USER`.

---

## 2. Estructura de Carpetas

**¿Por qué?** Una estructura clara y ordenada facilita la navegación, el mantenimiento y la evaluación del proyecto. Además, el subject sugiere una organización específica bajo `srcs/requirements/`.

Crea la siguiente jerarquía de directorios:

```bash
mkdir -p srcs/requirements/nginx
mkdir -p srcs/requirements/mariadb
mkdir -p srcs/requirements/wordpress
mkdir -p secrets
mkdir -p /home/$USER/data/mariadb
mkdir -p /home/$USER/data/wordpress
```

La estructura final debería verse así:

```
inception/
├── Makefile
├── srcs/
│   ├── docker-compose.yml
│   └── requirements/
│       ├── nginx/
│       │   ├── Dockerfile
│       │   ├── conf/
│       │   │   └── nginx.conf
│       │   └── tools/
│       │       └── (scripts opcionales)
│       ├── mariadb/
│       │   ├── Dockerfile
│       │   ├── conf/
│       │   │   └── 50-server.cnf
│       │   └── tools/
│       │       └── init_db.sh
│       └── wordpress/
│           ├── Dockerfile
│           ├── conf/
│           │   └── www.conf
│           └── tools/
│               └── wordpress_setup.sh
└── secrets/
    ├── db_root_password.txt
    ├── db_password.txt
    └── credentials.txt
```

---

## Paso 1: MariaDB

**¿Por qué empezamos por la base de datos?** Es la capa de datos fundamental. WordPress necesita una base de datos para funcionar, por lo que MariaDB debe estar lista para aceptar conexiones antes de que WordPress intente instalarse.

### 1.1. Secrets para MariaDB

Los secrets permiten inyectar contraseñas de forma segura sin hardcodearlas en los Dockerfiles ni en el docker-compose.

```bash
# Generar contraseñas seguras
openssl rand -base64 32 > secrets/db_root_password.txt
openssl rand -base64 32 > secrets/db_password.txt
```

### 1.2. Dockerfile de MariaDB

Crea `srcs/requirements/mariadb/Dockerfile`:

```dockerfile
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
```

**Explicación:**
- **Imagen base:** `debian:bullseye` es una versión estable y específica.
- **Configuración:** Sobrescribimos la configuración por defecto para escuchar en todas las interfaces (`bind-address = 0.0.0.0`), permitiendo conexiones desde otros contenedores.
- **ENTRYPOINT:** Usamos un script que inicializa la base de datos y luego arranca el servicio. Esto evita hacks como `tail -f`.

### 1.3. Configuración de MariaDB

Crea `srcs/requirements/mariadb/conf/50-server.cnf`:

```ini
[mysqld]
user                    = mysql
pid-file                = /run/mysqld/mysqld.pid
socket                  = /run/mysqld/mysqld.sock
port                    = 3306
basedir                 = /usr
datadir                 = /var/lib/mysql
tmpdir                  = /tmp
bind-address            = 0.0.0.0
expire_logs_days        = 10
character-set-server    = utf8mb4
collation-server        = utf8mb4_general_ci
```

**Importante:** `bind-address = 0.0.0.0` es crucial. Por defecto, MariaDB solo escucha en `localhost` (127.0.0.1), lo que impide que otros contenedores se conecten a través de la red de Docker.

### 1.4. Script de Inicialización

Crea `srcs/requirements/mariadb/tools/init_db.sh`:

```bash
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
```

**Explicación:**
- **`set -e`:** Si cualquier comando falla, el script se detiene inmediatamente.
- **Inicio temporal:** Arrancamos `mysqld_safe` en segundo plano para poder ejecutar comandos SQL.
- **Lectura de secrets:** Las contraseñas se leen de `/run/secrets/`, que es donde Docker monta automáticamente los archivos de secrets definidos en `docker-compose.yml`.
- **Variables de entorno:** `MYSQL_DATABASE`, `MYSQL_USER`, etc., las definiremos en el `docker-compose.yml`.
- **`exec mysqld_safe`:** Reemplazamos el proceso del script con el servidor de MariaDB. Esto asegura que el contenedor muera si el servidor muere, y que Docker reciba correctamente las señales (como SIGTERM).

---

## Paso 2: WordPress + PHP-FPM

**¿Por qué PHP-FPM y no Apache?** El subject especifica que WordPress debe ejecutarse con php-fpm. NGINX no puede ejecutar PHP por sí solo; necesita pasar las peticiones a un servidor PHP-FPM a través del protocolo FastCGI.

### 2.1. Dockerfile de WordPress

Crea `srcs/requirements/wordpress/Dockerfile`:

```dockerfile
FROM debian:bullseye

# Instalar PHP-FPM y extensiones necesarias para WordPress
RUN apt-get update && apt-get install -y \
    php7.4-fpm \
    php7.4-mysql \
    php7.4-curl \
    php7.4-gd \
    php7.4-mbstring \
    php7.4-xml \
    php7.4-zip \
    curl \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# Instalar WP-CLI (herramienta de línea de comandos para WordPress)
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Crear el directorio de trabajo para WordPress
RUN mkdir -p /var/www/html
WORKDIR /var/www/html

# Copiar la configuración de PHP-FPM
COPY conf/www.conf /etc/php/7.4/fpm/pool.d/www.conf

# Copiar el script de configuración
COPY tools/wordpress_setup.sh /usr/local/bin/wordpress_setup.sh
RUN chmod +x /usr/local/bin/wordpress_setup.sh

# Exponer el puerto de PHP-FPM (9000 es el puerto por defecto para FastCGI)
EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/wordpress_setup.sh"]
```

**Explicación:**
- **WP-CLI:** Es la forma más robusta de instalar y configurar WordPress desde la línea de comandos, evitando la necesidad de hacerlo manualmente a través del navegador.
- **`php7.4-fpm`:** Es el proceso que escucha en el puerto 9000 y ejecuta el código PHP.
- **`mariadb-client`:** Instalamos el cliente de MariaDB para que WP-CLI pueda verificar la conexión a la base de datos antes de instalar.

### 2.2. Configuración de PHP-FPM

Crea `srcs/requirements/wordpress/conf/www.conf`:

```ini
[www]
user = www-data
group = www-data
listen = 0.0.0.0:9000
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```

**Importante:** `listen = 0.0.0.0:9000` hace que PHP-FPM escuche en todas las interfaces de red, permitiendo que NGINX se conecte desde otro contenedor.

### 2.3. Script de Configuración de WordPress

Crea `srcs/requirements/wordpress/tools/wordpress_setup.sh`:

```bash
#!/bin/bash
set -e

# Leer la contraseña de la base de datos desde el secret
DB_PASSWORD=$(cat /run/secrets/db_password)

# Esperar a que MariaDB esté disponible
until mysqladmin ping -h"mariadb" --silent; do
    echo "Esperando a que MariaDB esté listo..."
    sleep 2
done

# Si WordPress no está instalado, descargarlo y configurarlo
if [ ! -f /var/www/html/wp-config.php ]; then
    echo "Descargando WordPress..."
    wp core download --allow-root --path=/var/www/html

    echo "Creando wp-config.php..."
    wp config create --allow-root \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="mariadb" \
        --path=/var/www/html

    echo "Instalando WordPress..."
    wp core install --allow-root \
        --url="${DOMAIN_NAME}" \
        --title="Inception Site" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="$(cat /run/secrets/wp_admin_password)" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --path=/var/www/html

    echo "Creando usuario adicional..."
    wp user create --allow-root \
        "${WP_USER}" \
        "${WP_USER_EMAIL}" \
        --user_pass="$(cat /run/secrets/wp_user_password)" \
        --role=author \
        --path=/var/www/html
fi

# Ajustar permisos para que NGINX pueda leer los archivos
chown -R www-data:www-data /var/www/html

# Iniciar PHP-FPM en primer plano
exec php-fpm7.4 -F
```

**Explicación:**
- **Espera activa:** El bucle `until mysqladmin ping` espera hasta que MariaDB responda. Esto evita errores de "conexión rechazada" si WordPress intenta conectarse antes de que la base de datos esté lista.
- **Idempotencia:** El script verifica si `wp-config.php` ya existe. Si es así, omite la instalación. Esto es crucial para que los datos no se sobrescriban si el contenedor se reinicia.
- **Permisos:** `chown -R www-data:www-data` asegura que el servidor web tenga permisos para leer y escribir los archivos de WordPress.
- **`exec php-fpm7.4 -F`:** `-F` fuerza a PHP-FPM a ejecutarse en primer plano, manteniendo el contenedor vivo.

### 2.4. Crear los Secrets Adicionales

```bash
# Contraseña del admin de WordPress
openssl rand -base64 32 > secrets/wp_admin_password.txt

# Contraseña del usuario adicional de WordPress
openssl rand -base64 32 > secrets/wp_user_password.txt
```

---

## Paso 3: NGINX

**¿Por qué NGINX es el punto de entrada único?** El subject exige que NGINX sea el único servicio expuesto al exterior (puerto 443). Todos los demás servicios solo son accesibles internamente a través de la red de Docker. NGINX actúa como proxy inverso, pasando las peticiones PHP a WordPress y sirviendo archivos estáticos.

### 3.1. Generar Certificados SSL/TLS

**¿Por qué autofirmados?** En un entorno de desarrollo local no tenemos un dominio público para obtener certificados de una autoridad de confianza (como Let's Encrypt). Los certificados autofirmados cumplen con el requisito de usar TLSv1.2 o TLSv1.3.

```bash
mkdir -p srcs/requirements/nginx/tools
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout srcs/requirements/nginx/tools/nginx.key \
    -out srcs/requirements/nginx/tools/nginx.crt \
    -subj "/C=ES/ST=Madrid/L=Madrid/O=42/OU=42/CN=jgomez-d.42.fr"
```

> **Nota:** Reemplaza `jgomez-d.42.fr` con tu dominio.

### 3.2. Dockerfile de NGINX

Crea `srcs/requirements/nginx/Dockerfile`:

```dockerfile
FROM debian:bullseye

# Instalar NGINX y OpenSSL (para soportar TLS)
RUN apt-get update && apt-get install -y \
    nginx \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Copiar certificados SSL
COPY tools/nginx.crt /etc/nginx/ssl/nginx.crt
COPY tools/nginx.key /etc/nginx/ssl/nginx.key

# Copiar configuración personalizada
COPY conf/nginx.conf /etc/nginx/nginx.conf

# Exponer el puerto 443 (HTTPS)
EXPOSE 443

# Iniciar NGINX en primer plano
CMD ["nginx", "-g", "daemon off;"]
```

**Explicación:**
- **`daemon off;`:** Esta directiva de NGINX fuerza al proceso a quedarse en primer plano. Sin esto, NGINX se desvincularía (daemonize) y el contenedor se detendría inmediatamente, ya que Docker espera que el proceso principal siga vivo.

### 3.3. Configuración de NGINX

Crea `srcs/requirements/nginx/conf/nginx.conf`:

```nginx
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 443 ssl;
        listen [::]:443 ssl;

        server_name jgomez-d.42.fr;

        # Configuración SSL/TLS
        ssl_certificate /etc/nginx/ssl/nginx.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;

        # Raíz del sitio web
        root /var/www/html;
        index index.php index.html index.htm;

        location / {
            try_files $uri $uri/ /index.php?$args;
        }

        # Proxy inverso hacia PHP-FPM
        location ~ \.php$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass wordpress:9000;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include fastcgi_params;
        }

        # Denegar acceso a archivos ocultos (.htaccess, etc.)
        location ~ /\.ht {
            deny all;
        }
    }
}
```

**Explicación clave:**
- **`listen 443 ssl;`:** Escucha exclusivamente en HTTPS.
- **`ssl_protocols TLSv1.2 TLSv1.3;`:** Cumple con el requisito del subject de usar versiones modernas y seguras de TLS.
- **`fastcgi_pass wordpress:9000;`:** Envía las peticiones PHP al contenedor llamado `wordpress` en el puerto 9000. Docker Compose configura automáticamente la resolución DNS interna para que el nombre del servicio (`wordpress`) se resuelva a la IP del contenedor.
- **`root /var/www/html;`:** Este directorio será montado como un volumen compartido entre NGINX y WordPress, de modo que ambos contenedores vean los mismos archivos.

---

## Paso 4: Docker Compose

**¿Por qué Docker Compose?** Define toda la infraestructura en un solo archivo declarativo. Permite orquestar múltiples contenedores, volúmenes, redes y secrets de forma coherente y reproducible.

Crea `srcs/docker-compose.yml`:

```yaml
version: '3.8'

services:
  mariadb:
    build:
      context: ./requirements/mariadb
      dockerfile: Dockerfile
    container_name: mariadb
    env_file:
      - ../.env
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/db_root_password
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_root_password
      - db_password
    volumes:
      - mariadb_data:/var/lib/mysql
    networks:
      - inception_network
    restart: unless-stopped

  wordpress:
    build:
      context: ./requirements/wordpress
      dockerfile: Dockerfile
    container_name: wordpress
    env_file:
      - ../.env
    environment:
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD_FILE: /run/secrets/db_password
      DOMAIN_NAME: ${DOMAIN_NAME}
      WP_ADMIN_USER: ${WP_ADMIN_USER}
      WP_ADMIN_EMAIL: ${WP_ADMIN_EMAIL}
      WP_USER: ${WP_USER}
      WP_USER_EMAIL: ${WP_USER_EMAIL}
    secrets:
      - db_password
      - wp_admin_password
      - wp_user_password
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception_network
    depends_on:
      - mariadb
    restart: unless-stopped

  nginx:
    build:
      context: ./requirements/nginx
      dockerfile: Dockerfile
    container_name: nginx
    ports:
      - "443:443"
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception_network
    depends_on:
      - wordpress
    restart: unless-stopped

volumes:
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/jgomez-d/data/mariadb

  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/jgomez-d/data/wordpress

networks:
  inception_network:
    driver: bridge

secrets:
  db_root_password:
    file: ../secrets/db_root_password.txt
  db_password:
    file: ../secrets/db_password.txt
  wp_admin_password:
    file: ../secrets/wp_admin_password.txt
  wp_user_password:
    file: ../secrets/wp_user_password.txt
```

**Sección por sección:**

#### Services

- **`mariadb`:**
  - `env_file`: Carga variables desde el archivo `.env` en la raíz.
  - `secrets`: Monta los archivos de secrets en `/run/secrets/` dentro del contenedor.
  - `volumes`: `mariadb_data` se monta en `/var/lib/mysql`, donde MariaDB almacena sus datos.
  - `restart: unless-stopped`: Si el contenedor falla o se reinicia la máquina, Docker lo levantará automáticamente.

- **`wordpress`:**
  - `depends_on`: Asegura que el contenedor de MariaDB se inicie antes que WordPress. **Nota:** Esto solo controla el orden de inicio, no garantiza que MariaDB esté "listo". Por eso el script de WordPress incluye la espera activa (`mysqladmin ping`).
  - `volumes`: Comparte `wordpress_data` con NGINX. Ambos contenedores ven el mismo `/var/www/html`.

- **`nginx`:**
  - `ports`: Mapea el puerto 443 del host al puerto 443 del contenedor. Es la única conexión externa.
  - `depends_on`: Espera a que WordPress esté iniciado.

#### Volumes

Aunque el subject pide **named volumes**, también requiere que los datos se almacenen en `/home/login/data`. La solución es usar un **named volume con driver local y opciones de bind mount** (`driver_opts`). Esto satisface ambos requisitos: es un named volume gestionado por Docker, pero sus datos físicos residen en la ruta especificada.

#### Networks

- **`inception_network`:** Una red de tipo `bridge` creada automáticamente por Docker Compose. Los contenedores en esta red pueden comunicarse entre sí usando sus nombres de servicio como hostname. Esto es mucho más robusto y seguro que `--link` o `network: host`.

#### Secrets

- Cada entrada bajo `secrets:` apunta a un archivo en el host.
- Docker monta estos archivos de forma segura como archivos de solo lectura en `/run/secrets/<nombre>` dentro de los contenedores.

### 4.1. Archivo .env

Crea `.env` en la raíz del proyecto:

```bash
# Base de Datos
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user

# WordPress
DOMAIN_NAME=jgomez-d.42.fr
WP_ADMIN_USER=jgomez-d_admin
WP_ADMIN_EMAIL=jgomez-d@student.42.fr
WP_USER=jgomez-d_user
WP_USER_EMAIL=jgomez-d_user@student.42.fr
```

**Nota de seguridad:**
- **NO** incluyas contraseñas en el `.env`. Las contraseñas están en los archivos de `secrets/`.
- Asegúrate de que el `.env` esté listado en tu `.gitignore` para no subirlo a Git.

---

## Paso 5: Makefile

**¿Por qué un Makefile?** Proporciona una interfaz simple y estandarizada para construir, levantar y gestionar la infraestructura. Evaluadores y usuarios solo necesitan recordar comandos como `make up` o `make re`.

Crea `Makefile` en la raíz:

```makefile
# Variables
COMPOSE_FILE = srcs/docker-compose.yml
DATA_DIR = /home/jgomez-d/data

# Objetivos principales
all: up

up:
	@mkdir -p $(DATA_DIR)/mariadb
	@mkdir -p $(DATA_DIR)/wordpress
	docker compose -f $(COMPOSE_FILE) up --build -d

down:
	docker compose -f $(COMPOSE_FILE) down

build:
	docker compose -f $(COMPOSE_FILE) build

# Detener y eliminar contenedores, redes y volúmenes
clean: down
	docker system prune -af
	docker volume prune -af

# Borrar todo, incluyendo los datos persistentes en el host
fclean: clean
	sudo rm -rf $(DATA_DIR)

# Reconstruir desde cero
re: fclean all

# Ver logs de todos los servicios
logs:
	docker compose -f $(COMPOSE_FILE) logs -f

# Ver estado de los contenedores
ps:
	docker compose -f $(COMPOSE_FILE) ps

.PHONY: all up down build clean fclean re logs ps
```

**Descripción de objetivos:**

| Objetivo | Descripción |
|----------|-------------|
| `make` o `make up` | Construye las imágenes y levanta los contenedores en segundo plano (`-d`). |
| `make down` | Detiene y elimina los contenedores y la red. |
| `make build` | Reconstruye las imágenes sin levantar los contenedores. |
| `make clean` | Detiene todo y elimina imágenes, contenedores y volúmenes huérfanos. |
| `make fclean` | Hace `clean` y además borra la carpeta de datos persistente en el host. |
| `make re` | Equivalente a `fclean` + `up`. Útil para empezar de cero. |
| `make logs` | Muestra los logs en tiempo real de todos los servicios. |
| `make ps` | Muestra el estado de los contenedores. |

---

## Paso 6: Verificación

### 6.1. Levantar la Infraestructura

```bash
make up
```

### 6.2. Verificar que los Contenedores Están Corriendo

```bash
docker ps
# o
make ps
```

Deberías ver algo como:

```
CONTAINER ID   IMAGE                  COMMAND                  CREATED          STATUS          PORTS                                     NAMES
abc123def456   srcs-nginx             "nginx -g 'daemon of…"   2 minutes ago    Up 2 minutes    0.0.0.0:443->443/tcp, :::443->443/tcp   nginx
def789ghi012   srcs-wordpress         "/usr/local/bin/word…"   2 minutes ago    Up 2 minutes    9000/tcp                                  wordpress
ghi345jkl678   srcs-mariadb           "/usr/local/bin/init…"   2 minutes ago    Up 2 minutes    3306/tcp                                  mariadb
```

### 6.3. Acceder al Sitio Web

Abre tu navegador y ve a:

```
https://jgomez-d.42.fr
```

> **Aviso de seguridad:** Como usamos certificados autofirmados, tu navegador mostrará una advertencia de "Conexión no privada". Haz clic en "Avanzado" -> "Continuar a jgomez-d.42.fr (no seguro)".

### 6.4. Acceder al Panel de Administración de WordPress

```
https://jgomez-d.42.fr/wp-admin
```

- **Usuario:** El valor de `WP_ADMIN_USER` (ej. `jgomez-d_admin`)
- **Contraseña:** Puedes encontrarla en `secrets/wp_admin_password.txt`

### 6.5. Verificar la Persistencia de Volúmenes

```bash
# Ver los volúmenes de Docker
ls -la /home/jgomez-d/data/

# Deberías ver:
# /home/jgomez-d/data/mariadb
# /home/jgomez-d/data/wordpress

# Ver los archivos de WordPress
ls -la /home/jgomez-d/data/wordpress/

# Ver las bases de datos de MariaDB
ls -la /home/jgomez-d/data/mariadb/
```

**Prueba de persistencia:**
1. Crea una nueva entrada o página en WordPress.
2. Ejecuta `make down` y luego `make up`.
3. Vuelve a `https://jgomez-d.42.fr`. Tu contenido debería seguir ahí.

### 6.6. Verificar la Red Interna

```bash
# Inspeccionar la red
docker network inspect srcs_inception_network

# Deberías ver los tres contenedores conectados y sus IPs internas.
```

### 6.7. Verificar TLS

Puedes verificar la versión de TLS usando `openssl`:

```bash
openssl s_client -connect jgomez-d.42.fr:443 -tls1_2
# Debería conectarse correctamente

openssl s_client -connect jgomez-d.42.fr:443 -tls1_1
# Debería FALLAR (ya que solo permitimos 1.2 y 1.3)
```

---

## Troubleshooting

### Error: "Error establishing a database connection"

**Causa probable:** WordPress intentó conectarse a MariaDB antes de que estuviera listo, o las credenciales son incorrectas.

**Solución:**
1. Revisa los logs de WordPress: `docker logs wordpress`
2. Revisa los logs de MariaDB: `docker logs mariadb`
3. Asegúrate de que el script `init_db.sh` de MariaDB haya creado la base de datos y el usuario correctamente.
4. Verifica que `wp-config.php` tenga los datos correctos (usuario, contraseña, host `mariadb`).
5. Si todo falla, haz `make fclean` y `make up` para empezar de cero.

### Error: "502 Bad Gateway" en NGINX

**Causa probable:** NGINX no puede comunicarse con PHP-FPM.

**Solución:**
1. Asegúrate de que el contenedor `wordpress` esté corriendo: `docker ps`
2. Verifica que PHP-FPM esté escuchando en el puerto 9000: `docker exec wordpress ss -tlnp | grep 9000`
3. Revisa la configuración de `nginx.conf`. La línea `fastcgi_pass wordpress:9000;` debe ser correcta.
4. Revisa los logs de NGINX: `docker logs nginx`

### Error: "Permission denied" al acceder a archivos de WordPress

**Causa probable:** Los archivos de WordPress fueron creados por `root` dentro del contenedor, pero NGINX corre como `www-data`.

**Solución:**
Asegúrate de que el script `wordpress_setup.sh` ejecute:
```bash
chown -R www-data:www-data /var/www/html
```

### Los volúmenes no persisten tras `make down`

**Causa probable:** Usaste `docker volume rm` o el `docker-compose.yml` no define los volúmenes correctamente.

**Solución:**
1. Usa `make down` (sin `--volumes`). El flag `-v` eliminaría los volúmenes nombrados.
2. Verifica que los datos existan en `/home/jgomez-d/data/` después de hacer `down`.

### El contenedor se reinicia constantemente (Restart Loop)

**Causa probable:** El proceso principal del contenedor falla inmediatamente al arrancar.

**Solución:**
1. Revisa los logs: `docker logs --tail 50 <nombre_contenedor>`
2. Asegúrate de que el `ENTRYPOINT` o `CMD` ejecute el proceso en primer plano.
3. Verifica que los archivos de configuración y scripts tengan permisos de ejecución (`chmod +x`).

### Puerto 443 ya está en uso

**Causa probable:** Otro servicio en tu máquina (como otro NGINX o Apache) está usando el puerto 443.

**Solución:**
```bash
# Encontrar el proceso que usa el puerto 443
sudo lsof -i :443

# Detener el servicio conflictivo (ej. si es el nginx del host)
sudo systemctl stop nginx
```

---

## Checklist de Entrega

Antes de entregar o evaluar, asegúrate de cumplir con cada uno de estos puntos:

### Requisitos Técnicos del Subject

- [ ] El proyecto se ejecuta en una única máquina virtual.
- [ ] Existe un `Makefile` en la raíz que levanta toda la infraestructura.
- [ ] Existe un `docker-compose.yml` en `srcs/`.
- [ ] Hay un `Dockerfile` propio para cada servicio (NGINX, WordPress, MariaDB).
- [ ] **NO** se usan imágenes pre-hechas (como `wordpress:latest`, `nginx:latest`). Solo bases como `debian:bullseye` o `alpine`.
- [ ] **NO** se usa el tag `latest` en ninguna imagen base.
- [ ] **NO** se usan `network: host`, `--link` o `links:`.
- [ ] Existe una red personalizada de Docker para la comunicación entre contenedores.
- [ ] Los contenedores tienen `restart: unless-stopped` (o `always`).
- [ ] **NO** se usan "hacks" para mantener los contenedores activos (`tail -f`, `sleep infinity`, `while true`).

### Servicios Específicos

- [ ] **NGINX:**
  - [ ] Es el **único punto de entrada** expuesto al exterior.
  - [ ] Escucha en el puerto **443**.
  - [ ] Usa **TLSv1.2 o TLSv1.3**.
  - [ ] Tiene certificados SSL (pueden ser autofirmados).
  - [ ] Actúa como proxy inverso hacia PHP-FPM.

- [ ] **WordPress + PHP-FPM:**
  - [ ] Corre con `php-fpm` (sin servidor web propio como Apache/Nginx).
  - [ ] Se conecta correctamente a MariaDB.
  - [ ] El sitio de WordPress es funcional.
  - [ ] Hay **dos usuarios** en la base de datos de WordPress.
  - [ ] El nombre del administrador **NO** contiene "admin", "Admin", "administrator" ni "Administrator".

- [ ] **MariaDB:**
  - [ ] Tiene una base de datos dedicada para WordPress.
  - [ ] Tiene un usuario dedicado para WordPress.

### Volúmenes y Datos

- [ ] Se usan **named volumes** (NO bind mounts directos en `services.*.volumes`, salvo a través de `driver_opts` para cumplir la ruta `/home/login/data`).
- [ ] Existe un volumen para los archivos de la base de datos (`mariadb_data`).
- [ ] Existe un volumen para los archivos del sitio WordPress (`wordpress_data`).
- [ ] Ambos volúmenes almacenan sus datos físicos en `/home/login/data` en el host.
- [ ] Los datos persisten después de detener y eliminar los contenedores.

### Seguridad

- [ ] **NO** hay contraseñas hardcodeadas en los `Dockerfile`.
- [ ] Se usa un archivo `.env` para las variables de entorno no sensibles.
- [ ] Se usan **Docker secrets** para las contraseñas y credenciales sensibles.
- [ ] Los archivos de secrets (`secrets/*.txt`) **NO** están en el repositorio de Git (verifica `.gitignore`).

### Configuración de Red

- [ ] El dominio `login.42.fr` está configurado en `/etc/hosts` y apunta a `127.0.0.1`.
- [ ] Se puede acceder al sitio correctamente a través de `https://login.42.fr`.
- [ ] Se puede acceder al panel de administración de WordPress.

### Limpieza y Reproducibilidad

- [ ] Ejecutar `make fclean` seguido de `make up` produce una infraestructura funcional desde cero.
- [ ] Los scripts de inicialización son **idempotentes** (no fallan ni duplican datos si el contenedor se reinicia).

---

**¡Felicidades!** Si has seguido esta guía y verificado todos los puntos de la checklist, tienes una infraestructura robusta y segura lista para la evaluación del proyecto Inception. ¡Mucha suerte! 🐳🚀
