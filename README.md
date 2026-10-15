# inception

> A Docker Compose infrastructure: NGINX (TLS) + WordPress/PHP-FPM + MariaDB.

## What it does
Three custom-built containers on a private network with persistent volumes and Docker secrets, as required by the 42 Inception subject.

## What I learned
- Writing Dockerfiles from a base image (no ready-made images)
- Compose networks, volumes, secrets and service dependencies
- NGINX TLS configuration and PHP-FPM

## Tech stack
Docker, Docker Compose, NGINX, WordPress, MariaDB, Bash

## Build & run
```bash
make        # up: builds and starts the stack
make down
make logs / make ps
make fclean # data stored under /home/jorgedebian/data
```

## Structure
`Makefile`, `srcs/docker-compose.yml`, `srcs/requirements/{nginx,wordpress,mariadb}/` (Dockerfile, conf, tools), `secrets/`.

---
*Built at 42 Madrid by jgomez-d (Jorge Gomez De Oliveira).*
