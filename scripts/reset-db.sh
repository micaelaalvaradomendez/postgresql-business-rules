#!/usr/bin/env bash
# ============================================================================
# scripts/reset-db.sh
# Recarga en caliente: elimina todos los objetos (99-drop) y vuelve a aplicar
# schema, funciones, triggers y seed. Se ejecuta dentro del contenedor:
#   docker compose exec -T db /lab/scripts/reset-db.sh
# ============================================================================
set -euo pipefail

# Mismos valores por defecto que la imagen oficial (no los exporta a `docker exec`)
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_DB:=$POSTGRES_USER}"

export PGOPTIONS='-c client_min_messages=warning'

for archivo in 99-drop 01-schema 02-functions 03-triggers 04-seed 05-views; do
    psql -v ON_ERROR_STOP=1 -q \
         --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
         -f "/lab/sql/${archivo}.sql"
done

echo "reset-db: base '${POSTGRES_DB}' recargada (schema + funciones + triggers + seed + vistas)"
