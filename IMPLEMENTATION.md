# Implementación del Proyecto Inception

*This project has been created as part of the 42 curriculum by jorgedebian.*

---

## Descripción General

Este documento detalla los pasos seguidos para implementar cada servicio Docker de la infraestructura Inception, y cómo `docker-compose.yml` los conecta para formar un stack LEMP (Linux, NGINX, MariaDB, PHP-FPM) completo con WordPress.

---

## Estructura del Proyecto

```
inception/
├── Makefile                          # Orquesta build/up/down/clean
├── IMPLEMENTATION.md                 # Este documento
├── .gitignore                        # Excluye secrets y .env de Git
├── secrets/
│   ├── db_root_password.txt          # Password root de MariaDB
│   ├── db_password.txt               # Password del usuario WP en MariaDB
│   ├── wp_admin_password.txt         # Password del admin de WordPress
│   └── wp_user_password.txt          # Password del usuario WP adicional
└── srcs/
    ├── docker-compose.yml            # Orquestación de los 3 servicios
    ├── .env                          # Variables de entorno no sensibles
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── 50-server.cnf     # Configuración MariaDB (bind-address, charset)
        │   └── tools/
        │       └── init_db.sh        # Script de inicialización idempotente
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── conf/
        │   │   └── www.conf          # Pool PHP-FPM (escucha en 0.0.0.0:9000)
        │   └── tools/
        │       └── wordpress_setup.sh # Instalación y configuración WP-CLI
        └── nginx/
            ├── Dockerfile
            ├── conf/
            │   └── nginx.conf        # Reverse proxy con TLSv1.2/1.3
            └── tools/
                ├── nginx.crt         # Certificado SSL autofirmado
                └── nginx.key         # Clave privada SSL
```

---

## Servicio 1: MariaDB

### Por qué MariaDB primero

Es la capa de datos fundamental. WordPress necesita una base de datos antes de poder instalarse, por lo que MariaDB debe estar lista antes de que el contenedor de WordPress intente conectarse.

### Archivos creados

#### `Dockerfile`

```dockerfile
FROM debian:bullseye
```

- **Imagen base:** `debian:bullseye` — versión específica, NO `latest` (prohibido por el subject).
- **Instalación:** Solo `mariadb-server`, sin paquetes innecesarios.
- **Copia de configuración:** `50-server.cnf` y `init_db.sh` se copian al contenedor.
- **ENTRYPOINT:** Ejecuta el script de inicialización, no un comando arbitrario.

#### `conf/50-server.cnf`

- **`bind-address = 0.0.0.0`:** CRUCIAL. Por defecto MariaDB solo escucha en `127.0.0.1`, lo que bloquea conexiones desde otros contenedores en la red Docker.
- **`character-set-server = utf8mb4`:** Soporte completo de Unicode para WordPress.
- **`port = 3306`:** Puerto estándar de MariaDB.

#### `tools/init_db.sh`

Este script es el heart del servicio MariaDB:

1. **Arranca temporalmente** MariaDB en segundo plano (`mysqld_safe &`) para poder ejecutar comandos SQL.
2. **Lee secrets** desde `/run/secrets/` (montados automáticamente por Docker).
3. **Crea la base de datos y el usuario** de forma idempotente con `IF NOT EXISTS`.
4. **Establece la contraseña de root** usando el secret correspondiente.
5. **Detiene el servidor temporal** con `mysqladmin shutdown`.
6. **Arranca MariaDB como PID 1** con `exec mysqld_safe`.

**Por qué `exec`:** Reemplaza el proceso del script por `mysqld_safe`, convirtiéndolo en PID 1. Esto es esencial para que Docker pueda enviar señales como SIGTERM correctamente. Sin `exec`, el shell sería PID 1 y las señales no llegarían a MariaDB.

**Idempotencia:** `CREATE DATABASE IF NOT EXISTS` y `CREATE USER IF NOT EXISTS` aseguran que el script se pueda ejecutar múltiples veces sin errores (por ejemplo, tras un reinicio del contenedor).

---

## Servicio 2: WordPress + PHP-FPM

### Por qué PHP-FPM (sin web server)

El subject es explícito: WordPress debe ejecutarse con php-fpm y SIN nginx. NGINX corre en su propio contenedor y actúa como proxy inverso que envía las peticiones PHP a este contenedor vía FastCGI.

### Archivos creados

#### `Dockerfile`

- **Imagen base:** `debian:bullseye`.
- **Paquetes instalados:**
  - `php7.4-fpm` — el proceso que escucha en el puerto 9000 y ejecuta PHP.
  - `php7.4-mysql` — conector MySQL/MariaDB para PHP.
  - Otras extensiones PHP necesarias para WordPress (`curl`, `gd`, `mbstring`, `xml`, `zip`).
  - `mariadb-client` — para usar `mysqladmin ping` en el script de espera.
  - `curl` — para descargar WP-CLI.
- **WP-CLI:** Instalado desde su PHAR oficial, permite configurar WordPress desde la línea de comandos sin intervención del navegador.
- **ENTRYPOINT:** Ejecuta `wordpress_setup.sh`.

#### `conf/www.conf`

```
listen = 0.0.0.0:9000
```

**Por qué `0.0.0.0` y no `localhost`:** Si PHP-FPM escucha en `127.0.0.1`, NGINX (en otro contenedor) no podría conectarse. Con `0.0.0.0`, acepta conexiones desde cualquier interfaz de la red Docker.

#### `tools/wordpress_setup.sh`

Este script realiza la configuración completa de WordPress:

1. **Lee el secret** `db_password` desde `/run/secrets/`.
2. **Espera a MariaDB** con un bucle `until mysqladmin ping -h"mariadb" --silent`. Esto resuelve el problema de que `depends_on` solo controla el orden de inicio, no garantiza que el servicio esté listo.
3. **Verifica idempotencia:** Si `wp-config.php` ya existe, saltea la instalación completa. Esto previene pérdida de datos si el contenedor se reinicia.
4. **Descarga WordPress** con `wp core download`.
5. **Crea `wp-config.php`** con las credenciales y el host `mariadb` (nombre del servicio en la red Docker).
6. **Instala WordPress** con `wp core install`, creando el usuario admin (su nombre NO contiene "admin").
7. **Crea un segundo usuario** con rol `author`.
8. **Ajusta permisos:** `chown -R www-data:www-data /var/www/html` para que NGINX pueda leer los archivos.
9. **Inicia PHP-FPM como PID 1** con `exec php-fpm7.4 -F`.

**Por qué dos usuarios:** El subject exige que existan dos usuarios en la base de datos de WordPress, uno admin (cuyo nombre NO contiene "admin") y uno regular.

---

## Servicio 3: NGINX

### Por qué NGINX es el único punto de entrada

El subject exige que NGINX sea el **único contenedor expuesto al exterior**, en el puerto 443 con TLSv1.2 o TLSv1.3. Todos los demás servicios se comunican exclusivamente a través de la red interna de Docker.

### Archivos creados

#### `Dockerfile`

- **Imagen base:** `debian:bullseye`.
- **Paquetes:** `nginx` y `openssl` (para soporte TLS).
- **Certificados:** Se copian los archivos `.crt` y `.key` autogenerados.
- **CMD:** `nginx -g "daemon off;"` ejecuta NGINX en primer plano, sin daemonizar.

**Por qué `daemon off;`:** Sin esta directiva, NGINX se daemonizaría (se desvincularía del proceso principal) y el contenedor se detendría inmediatamente porque Docker espera que PID 1 siga vivo.

#### `conf/nginx.conf`

Configuración clave:

```nginx
listen 443 ssl;
ssl_protocols TLSv1.2 TLSv1.3;
fastcgi_pass wordpress:9000;
```

- **`listen 443 ssl`:** Solo HTTPS, sin HTTP plano.
- **`ssl_protocols TLSv1.2 TLSv1.3`:** Cumple el requisito del subject de usar solo versiones modernas de TLS.
- **`fastcgi_pass wordpress:9000`:** NGINX envía las peticiones `.php` al contenedor `wordpress` en el puerto 9000. Docker Compose resuelve automáticamente el nombre del servicio a la IP del contenedor.
- **`root /var/www/html`:** Este directorio se comparte con WordPress a través del volumen `wordpress_data`.
- **`try_files $uri $uri/ /index.php?$args`:** Permalinks bonitos de WordPress.

#### `tools/nginx.crt` y `tools/nginx.key`

Certificados SSL autofirmados generados con:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout nginx.key -out nginx.crt \
    -subj "/C=ES/ST=Madrid/L=Madrid/O=42/OU=42/CN=jorgedebian.42.fr"
```

---

## Cómo docker-compose.yml Conecta los Servicios

### Arquitectura General

```
Internet (puerto 443)
       │
       ▼
   ┌─────────┐
   │  NGINX   │ ← Único punto de entrada, TLS v1.2/1.3
   │  :443    │
   └────┬─────┘
        │ fastcgi_pass wordpress:9000
        │ (peticiones .php)
        ▼
   ┌───────────┐
   │ WordPress  │ ← PHP-FPM en puerto 9000
   │ + PHP-FPM  │
   └─────┬──────┘
         │ mysql conexión a mariadb:3306
         ▼
   ┌───────────┐
   │  MariaDB   │ ← Base de datos en puerto 3306
   │  :3306     │
   └───────────┘
```

### Red Docker (`inception_network`)

Los tres servicios están conectados a la misma red bridge (`inception_network`). Esto permite:

- **Resolución DNS por nombre:** NGINX puede usar `wordpress:9000` y WordPress puede usar `mariadb:3306` sin conocer las IPs.
- **Aislamiento del exterior:** Solo NGINX expone el puerto 443 al host. MariaDB y WordPress no son accesibles desde Internet.

```yaml
networks:
  inception_network:
    driver: bridge
```

### Volúmenes (Persistencia)

Los volúmenes garantizan que los datos sobrevivan a `docker compose down`:

```yaml
volumes:
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/jorgedebian/data/mariadb

  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/jorgedebian/data/wordpress
```

**Por qué named volumes con `driver_opts`:** El subject exige:
1. Named volumes (no bind mounts directos en `services.*.volumes`) ✓
2. Que los datos se almacenen en `/home/login/data` en el host ✓

Esta configuración satisface ambos requisitos: Docker gestiona el volumen como named volume, pero los datos físicos residen en la ruta especificada.

**Volúmenes compartidos:** `wordpress_data` se monta tanto en NGINX (para servir archivos estáticos) como en WordPress (para escribirlos). Ambos contenedores ven el mismo `/var/www/html`.

### Docker Secrets (Seguridad)

```yaml
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

Docker monta estos archivos como **solo lectura** en `/run/secrets/<nombre>` dentro de los contenedores. Esto_evita:
- Contraseñas hardcodeadas en Dockerfiles (prohibido por el subject).
- Contraseñas en variables de entorno visibles con `docker inspect`.
- Contraseñas en el repositorio de Git (`.gitignore` excluye `secrets/`).

### Variables de Entorno (`.env`)

Solo se almacenan valores **no sensibles** en `.env`:

```env
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
DOMAIN_NAME=jorgedebian.42.fr
WP_ADMIN_USER=jorgedebian_admin
WP_ADMIN_EMAIL=jorgedebian@student.42.fr
WP_USER=jorgedebian_user
WP_USER_EMAIL=jorgedebian_user@student.42.fr
```

Las contraseñas van exclusivamente en Docker secrets.

### `depends_on` y Orden de Inicio

```yaml
mariadb:        # Se inicia primero (no depende de nadie)
wordpress:
  depends_on:
    - mariadb   # Espera a que MariaDB inicie
nginx:
  depends_on:
    - wordpress # Espera a que WordPress inicie
```

**Limitación:** `depends_on` solo espera a que el contenedor inicie, no a que el servicio esté listo. Por eso `wordpress_setup.sh` incluye `until mysqladmin ping -h"mariadb" --silent` para esperar activamente a que MariaDB acepte conexiones.

### Makefile (Interfaz Simplificada)

| Comando | Acción |
|---------|--------|
| `make` o `make up` | Crea directorios de datos, construye imágenes y levanta contenedores |
| `make down` | Detiene y elimina contenedores y red |
| `make build` | Solo construye las imágenes |
| `make clean` | Down + prune de imágenes y volúmenes huérfanos |
| `make fclean` | Clean + borra datos persistentes en `/home/jorgedebian/data` |
| `make re` | Fclean + Up (reconstrucción limpia) |
| `make logs` | Muestra logs en tiempo real |
| `make ps` | Estado de los contenedores |

---

## Cumplimiento de Requisitos del Subject

| Requisito | Implementación |
|-----------|---------------|
| Imagen base específica (no `latest`) | `debian:bullseye` en los 3 Dockerfiles |
| Dockerfiles propios | Sí, uno por servicio |
| Sin imágenes pre-hechas | Solo base `debian:bullseye` |
| Sin `network: host`, `--link`, `links:` | Solo `inception_network` tipo bridge |
| Red personalizada en docker-compose.yml | `inception_network` con `driver: bridge` |
| `restart: unless-stopped` | En los 3 servicios |
| Sin hacks (`tail -f`, `sleep infinity`) | `exec mysqld_safe`, `exec php-fpm7.4 -F`, `daemon off;` |
| NGINX único entrypoint en puerto 443 | Solo NGINX tiene `ports: "443:443"` |
| TLSv1.2 o TLSv1.3 | `ssl_protocols TLSv1.2 TLSv1.3` |
| WordPress con php-fpm (sin nginx) | Solo `php7.4-fpm`, escucha en 9000 |
| Dos usuarios WP (admin sin "admin") | `jorgedebian_admin` y `jorgedebian_user` |
| Named volumes en `/home/login/data` | Con `driver_opts: type: none, o: bind` |
| Sin contraseñas en Dockerfiles | Todos via Docker secrets |
| `.env` para variables no sensibles | `srcs/.env` con variables de configuración |
| Docker secrets para credenciales | 4 secrets, montados en `/run/secrets/` |
| Scripts idempotentes | `IF NOT EXISTS` en MariaDB, `if [ ! -f wp-config.php ]` en WordPress |

---

## Flujo deInicio Completo

1. **`make up`** → Crea `/home/jorgedebian/data/{mariadb,wordpress}`, construye imágenes, levanta contenedores.
2. **MariaDB arranca** → `init_db.sh` inicializa la base de datos, crea usuarios, y arranca `mysqld_safe` como PID 1.
3. **WordPress arranca** → `wordpress_setup.sh` espera a MariaDB, descarga WP si no existe, lo configura, y arranca `php-fpm7.4` como PID 1.
4. **NGINX arranca** → Lee la configuración, monta el certificado SSL, y escucha en 443. Las peticiones `.php` se envían a `wordpress:9000`.
5. **Usuario accede** → `https://jorgedebian.42.fr` → NGINX (443) → PHP-FPM (9000) → MariaDB (3306).