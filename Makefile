# ============================================================================
# Laboratorio PostgreSQL — Cadena de Cines Sunstar
# ============================================================================
COMPOSE := docker compose
EXEC    := $(COMPOSE) exec -T db

.DEFAULT_GOAL := help
.PHONY: help up down reset test psql logs clean

help: ## Muestra esta ayuda
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  make %-8s %s\n", $$1, $$2 }'

up: ## Levanta PostgreSQL 16 y espera a que el seed esté cargado
	$(COMPOSE) up -d --wait

down: ## Detiene el contenedor (conserva los datos)
	$(COMPOSE) down

reset: up ## Elimina y recarga schema, funciones, triggers y seed
	$(EXEC) /lab/scripts/reset-db.sh

test: up ## Recarga la base y ejecuta la batería (SUITES="02 03" para elegir, NO_COLOR=1 sin colores)
	$(COMPOSE) exec -T $(if $(NO_COLOR),-e NO_COLOR=1) db /lab/scripts/run-tests.sh $(SUITES)

psql: up ## Abre una sesión interactiva en la base
	$(COMPOSE) exec db sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'

logs: ## Muestra los logs del contenedor
	$(COMPOSE) logs -f db

clean: ## Detiene el contenedor y elimina el volumen de datos
	$(COMPOSE) down -v
