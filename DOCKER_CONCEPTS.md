# Conceptos de Docker para el Proyecto Inception

Este documento recopila los conceptos teóricos esenciales que necesitas dominar para afrontar el proyecto **Inception** de 42. No es una guía paso a paso, sino una base de conocimiento para que entiendas *por qué* haces cada cosa.

---

## 1. ¿Qué es Docker?

**Docker** es una plataforma que permite empaquetar, distribuir y ejecutar aplicaciones dentro de **contenedores**. Un contenedor es una unidad ligera y portátil que incluye todo lo necesario para que una aplicación funcione: código, runtime, herramientas del sistema, bibliotecas y configuraciones.

### Docker vs Máquinas Virtuales (VM)

| Característica | Máquina Virtual (VM) | Docker (Contenedor) |
|---|---|---|
| **Aislamiento** | Aislamiento completo a nivel de hardware (Hypervisor) | Aislamiento a nivel del sistema operativo (Kernel compartido) |
| **Peso** | Gigabytes (incluye SO completo) | Megabytes (solo lo necesario para la app) |
| **Arranque** | Minutos | Segundos |
| **Rendimiento** | Sobrecarga alta por emulación de hardware | Rendimiento nativo o casi nativo |
| **Uso de recursos** | Consume mucha RAM y CPU | Muy eficiente |

**En resumen:** las VMs virtualizan el *hardware*; Docker virtualiza el *sistema operativo*. Para Inception, esto significa que puedes tener nginx, WordPress y MariaDB corriendo en "máquinas" separadas sin el costo de tres sistemas operativos completos.

---

## 2. Imagen vs Contenedor

### Imagen Docker
Una **imagen** es una plantilla de solo lectura que contiene las instrucciones para crear un contenedor. Piensa en ella como una "fotografía" de un sistema de archivos con todo configurado. Las imágenes se construyen a partir de un `Dockerfile` y se almacenan en capas (layers).

### Contenedor Docker
Un **contenedor** es una instancia ejecutable de una imagen. Es el proceso vivo: tiene su propio sistema de archivos, red y proceso principal. Puedes crear, iniciar, detener, mover o eliminar un contenedor. Cuando un contenedor se elimina, sus cambios en el sistema de archivos interno desaparecen (a menos que uses volúmenes).

**Analogía:** La imagen es como el ejecutable de un programa; el contenedor es el programa corriendo.

---

## 3. El Dockerfile

El `Dockerfile` es un archivo de texto que contiene una serie de instrucciones para que Docker construya una imagen automáticamente.

### Instrucciones básicas

| Instrucción | Descripción | Ejemplo |
|---|---|---|
| `FROM` | Define la imagen base sobre la que construyes. **Obligatoria**. | `FROM debian:bullseye` |
| `RUN` | Ejecuta un comando durante la construcción de la imagen. | `RUN apt-get update && apt-get install -y nginx` |
| `COPY` | Copia archivos desde tu máquina local al sistema de archivos de la imagen. | `COPY ./nginx.conf /etc/nginx/nginx.conf` |
| `CMD` | Define el comando por defecto que se ejecuta cuando el contenedor inicia. Puede ser sobreescrito. | `CMD ["nginx", "-g", "daemon off;"]` |
| `ENTRYPOINT` | Similar a `CMD`, pero más estricto: configura el ejecutable principal y no se sobreescribe fácilmente. | `ENTRYPOINT ["/usr/sbin/nginx"]` |
| `EXPOSE` | Documenta qué puertos escucha el contenedor. **No los publica automáticamente**. | `EXPOSE 443` |
| `WORKDIR` | Establece el directorio de trabajo para las instrucciones siguientes. | `WORKDIR /var/www/html` |
| `ENV` | Define variables de entorno disponibles en el contenedor. | `ENV MYSQL_ROOT_PASSWORD=secret` |
| `VOLUME` | Crea un punto de montaje para volúmenes externos. | `VOLUME /var/lib/mysql` |

### Buenas prácticas en Dockerfile
- **Ordena las instrucciones por frecuencia de cambio:** las que cambian menos (como `FROM`, `RUN apt-get install`) van arriba para aprovechar la caché de capas.
- **Minimiza el número de capas:** agrupa comandos con `&&` en un solo `RUN` cuando sea posible.
- **No uses `latest`:** siempre especifica una versión concreta (por ejemplo, `debian:bullseye` o `alpine:3.18`). `latest` es impredecible y puede romper tu build en el futuro.
- **No incrustes secretos en el Dockerfile:** nunca pongas contraseñas directamente en el Dockerfile. Usa variables de entorno o Docker Secrets.

---

## 4. Docker Compose

**Docker Compose** es una herramienta que permite definir y gestionar aplicaciones multi-contenedor. En lugar de ejecutar `docker run` tres veces (uno para nginx, otro para WordPress, otro para MariaDB), describes toda tu infraestructura en un único archivo `docker-compose.yml` y la levantas con un solo comando.

### Estructura básica de `docker-compose.yml`

```yaml
version: "3.8"

services:
  nginx:
    build: ./requirements/nginx
    ports:
      - "443:443"
    networks:
      - inception_network
    depends_on:
      - wordpress

  wordpress:
    build: ./requirements/wordpress
    env_file:
      - .env
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception_network

  mariadb:
    build: ./requirements/mariadb
    env_file:
      - .env
    volumes:
      - mariadb_data:/var/lib/mysql
    networks:
      - inception_network

volumes:
  wordpress_data:
  mariadb_data:

networks:
  inception_network:
    driver: bridge
```

### Conceptos clave
- **services:** Cada servicio representa un contenedor. Puedes definir cómo se construye (`build`), qué imagen usa (`image`), variables de entorno, volúmenes, redes, etc.
- **volumes:** Sección para declarar volúmenes nombrados. Docker los gestiona y persisten datos fuera del ciclo de vida del contenedor.
- **networks:** Sección para definir redes personalizadas. Los servicios en la misma red pueden comunicarse entre sí usando el nombre del servicio como hostname.
- **depends_on:** Indica el orden de arranque (aunque no espera a que el servicio esté "listo", solo a que el contenedor se haya iniciado).

---

## 5. Docker Networks

Por defecto, Docker crea una red llamada `bridge` que comparten todos los contenedores. Sin embargo, es una buena práctica crear **redes personalizadas** para tu aplicación.

### Tipos de redes en Docker

| Tipo | Descripción | Uso |
|---|---|---|
| **bridge** | Red privada interna en el host. Los contenedores en la misma red bridge pueden comunicarse. | Predeterminado y recomendado para la mayoría de aplicaciones. |
| **host** | El contenedor comparte directamente la pila de red del host. Sin aislamiento de red. | Solo en casos muy específicos de alto rendimiento. **Evitar en Inception**. |
| **none** | El contenedor no tiene acceso a la red. | Para contenedores aislados que no necesitan comunicación. |

### ¿Por qué usar una red personalizada en vez de `--link`?
- **`--link` está obsoleto:** es un mecanismo antiguo, poco flexible y difícil de mantener.
- **DNS interno:** en una red personalizada, Docker proporciona resolución DNS por nombre de servicio. Si tu servicio se llama `mariadb`, otros contenedores pueden conectarse a `mariadb:3306` sin saber su IP.
- **Aislamiento:** separa el tráfico de tu aplicación del resto de contenedores en el host.
- **Escalabilidad:** es mucho más fácil añadir o quitar servicios sin reconfigurar todo.

---

## 6. Docker Volumes vs Bind Mounts

Los contenedores son efímeros: cuando se destruyen, sus datos internos desaparecen. Para persistir información (bases de datos, archivos de WordPress, configuraciones), necesitas montar almacenamiento externo.

### Comparativa

| Característica | Bind Mount | Named Volume |
|---|---|---|
| **Definición** | Monta una ruta específica del host dentro del contenedor. | Un volumen gestionado por Docker, referenciado por nombre. |
| **Sintaxis** | `/host/path:/container/path` | `nombre_volumen:/container/path` |
| **Gestión** | Tú controlas los archivos directamente. | Docker los gestiona (ubicación, permisos, backups). |
| **Portabilidad** | Depende de la estructura del host. | Independiente del host, definido en `docker-compose.yml`. |
| **Uso en Inception** | Poco recomendado para datos. | **Recomendado** para MariaDB y WordPress. |

### Named Volumes
Son la opción preferida en Inception. Se declaran en el archivo `docker-compose.yml` bajo la sección `volumes:` y se montan en los servicios. Docker se encarga de crear la carpeta en el host (típicamente en `/var/lib/docker/volumes/`) y de mantener los datos incluso si eliminas los contenedores con `docker-compose down`.

---

## 7. Docker Secrets vs Variables de Entorno

### Variables de Entorno (.env)
Son pares clave-valor que se inyectan en el contenedor. Se usan para configuración no sensible: nombres de bases de datos, usuarios, rutas, flags de comportamiento. En Docker Compose se cargan con `env_file` o `environment`.

**Ventajas:** Fáciles de usar, portables, ideales para configuración general.
**Desventajas:** Se pueden filtrar en logs, procesos (`ps aux`), o inspeccionando el contenedor (`docker inspect`).

### Docker Secrets
Son un mecanismo de Docker Swarm (y Docker Compose en versiones modernas con el flag adecuado) para gestionar datos sensibles como contraseñas, tokens o claves privadas. Los secrets se montan como archivos en `/run/secrets/` dentro del contenedor.

**Ventajas:** No se exponen en variables de entorno, más seguros contra inspección accidental.
**Desventajas:** Requieren Docker Swarm o configuración específica en Compose.

### ¿Qué usar en Inception?
Para el subject de 42, **variables de entorno definidas en un archivo `.env`** son generalmente suficientes y esperadas, siempre y cuando:
- No las incluyas en el `Dockerfile` (usar `.env` o pasarlas en `docker-compose.yml`).
- No subas el archivo `.env` a Git (añádelo a `.gitignore`).

---

## 8. PID 1 en Contenedores

En Linux, el proceso con **PID 1** es el primer proceso que arranca en el sistema y tiene responsabilidades especiales:
- Es el padre de todos los demás procesos huérfanos.
- Es el encargado de manejar señales como `SIGTERM` (para apagado graceful).

### El problema de los "hacks"
Si tu contenedor ejecuta un script que lanza un daemon (como nginx o php-fpm) y luego usa `tail -f /dev/null` o `sleep infinity` para mantenerse vivo, el proceso `tail` o `sleep` será el PID 1. Esto causa problemas:
- El contenedor no termina limpiamente ante `docker stop` (manda `SIGTERM` a `tail`, que no la propaga al daemon real).
- Puede dejar procesos zombies.
- Es un anti-patrón que demuestra desconocimiento de cómo funciona un contenedor.

### La solución correcta
El proceso principal de tu contenedor debe ser el propio daemon en primer plano (foreground). Por ejemplo:
- Nginx: `nginx -g 'daemon off;'`
- PHP-FPM: `php-fpm --nodaemonize` (o `php-fpm -F`)
- MariaDB: `mysqld`

Así, el daemon es el PID 1, recibe las señales correctamente y el contenedor vive y muere con él.

---

## 9. TLS/SSL y NGINX

### ¿Qué es TLS?
**TLS (Transport Layer Security)** es el protocolo criptográfico que garantiza que la comunicación entre el cliente (navegador) y el servidor sea privada e íntegra. Es el sucesor de SSL. Las versiones modernas y seguras son **TLSv1.2** y **TLSv1.3**.

### Certificados
Para habilitar TLS, necesitas un **certificado** (archivo `.crt` o `.pem`) y una **clave privada** (archivo `.key`). Puedes generar un certificado autofirmado con OpenSSL para pruebas locales (como en Inception). El navegador mostrará una advertencia, pero la conexión estará cifrada.

### ¿Por qué el puerto 443?
- El puerto **80** es para HTTP (sin cifrar).
- El puerto **443** es para HTTPS (HTTP sobre TLS).
En Inception, nginx debe escuchar en el puerto 443 y redirigir todo el tráfico HTTP del puerto 80 a HTTPS.

### Configuración básica en nginx
```nginx
server {
    listen 443 ssl;
    server_name login.42.fr;

    ssl_certificate /etc/nginx/ssl/login.42.fr.crt;
    ssl_certificate_key /etc/nginx/ssl/login.42.fr.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    # ... resto de configuración
}
```

---

## 10. PHP-FPM

**PHP-FPM (FastCGI Process Manager)** es un administrador de procesos PHP que escucha peticiones FastCGI (normalmente en un socket Unix o en el puerto 9000).

### ¿Por qué separar PHP-FPM de Nginx?
- **Separación de responsabilidades:** Nginx es un servidor web estático excelente, pero no interpreta PHP. PHP-FPM se encarga de ejecutar el código PHP.
- **Escalabilidad:** puedes escalar o reiniciar PHP-FPM sin afectar a nginx.
- **Seguridad:** el contenedor de PHP-FPM solo necesita el código PHP; no necesita exponer puertos web directamente.

### Cómo se comunican
Nginx recibe una petición para un archivo `.php`, la reenvía a PHP-FPM a través de FastCGI, y PHP-FPM devuelve el HTML generado. En Docker, esto se configura en nginx con:
```nginx
location ~ \.php$ {
    fastcgi_pass wordpress:9000;
    fastcgi_index index.php;
    include fastcgi_params;
}
```

---

## 11. MariaDB

**MariaDB** es un sistema de gestión de bases de datos relacional, fork de MySQL. Es el encargado de almacenar todos los datos de WordPress (usuarios, posts, configuraciones, etc.).

### Conceptos básicos
- **Base de datos:** un contenedor lógico de tablas. WordPress necesita una base de datos propia.
- **Usuario y privilegios:** es una buena práctica crear un usuario específico para WordPress con privilegios limitados a su base de datos, en lugar de usar `root`.
- **Persistencia:** los datos de MariaDB se almacenan en `/var/lib/mysql`. Sin un volumen montado en esa ruta, los datos se perderán al destruir el contenedor.

### Inicialización
La primera vez que el contenedor de MariaDB arranca, si el volumen de datos está vacío, ejecuta scripts de inicialización que puedes aprovechar para crear la base de datos y el usuario automáticamente.

---

## 12. Requisitos Específicos del Subject de 42

A continuación se resumen las restricciones y requisitos técnicos que debes respetar obligatoriamente:

### Imágenes base
- Debes usar la **penúltima versión estable** de **Alpine** o **Debian** como base.
- Ejemplo válido: `debian:bullseye` (si bookworm es la última) o `alpine:3.18`.

### Prohibición de `latest`
- Nunca uses `FROM debian:latest` ni `FROM alpine:latest`. Es impreciso y puede causar que tu proyecto deje de funcionar en el futuro.

### Seguridad: contraseñas
- **No escribas contraseñas en el `Dockerfile`**. Usa un archivo `.env` o variables de entorno pasadas en `docker-compose.yml`.
- El archivo `.env` debe estar en `.gitignore`.

### Variables de entorno
- Todo lo que sea configurable (usuarios, contraseñas, nombres de base de datos, dominios) debe parametrizarse mediante variables de entorno.

### Reinicio de contenedores
- Los contenedores deben reiniciarse automáticamente en caso de fallo. En Docker Compose se configura con `restart: unless-stopped` o `restart: always`.

### Dominio y puertos
- El dominio debe ser **`login.42.fr`** (sustituyendo `login` por tu nombre de usuario de 42).
- Debes configurar el archivo `/etc/hosts` de tu máquina local para apuntar `login.42.fr` a `127.0.0.1`.
- Solo el puerto **443** debe estar expuesto al exterior. El puerto 3306 (MariaDB) y el 9000 (PHP-FPM) deben estar **solo accesibles internamente** dentro de la red de Docker.

### Construcción de imágenes propias
- Debes escribir tus propios `Dockerfile`s. No está permitido usar imágenes pre-construidas de Docker Hub para nginx, WordPress o MariaDB.
- La instalación de servicios debe hacerse con el gestor de paquetes de la imagen base (`apt` para Debian, `apk` para Alpine).

---

## Conclusión

Inception no es solo "hacer que funcione"; es demostrar que entiendes la arquitectura de contenedores, la separación de responsabilidades, la persistencia de datos, la seguridad básica y la gestión de redes. Si dominas los conceptos de este documento, el proyecto dejará de ser una lista de pasos mecánicos y se convertirá en un ejercicio de diseño de infraestructura moderna.

**Regla de oro:** si algo no te queda claro, pregunta *por qué* existe antes de copiar una solución de internet. La comprensión profunda es lo que diferencia un proyecto aprobado de uno excelente.
