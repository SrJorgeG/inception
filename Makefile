# Inception Makefile
# Variables
COMPOSE_FILE = srcs/docker-compose.yml
DATA_DIR = /home/jorgedebian/data

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

# Detener y eliminar contenedores, redes e imagenes
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