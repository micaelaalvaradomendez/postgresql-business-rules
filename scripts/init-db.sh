#!/usr/bin/env bash
# ============================================================================
# scripts/init-db.sh
# Ejecutado por docker-entrypoint-initdb.d solo en la primera inicialización
# del volumen de datos. Carga el laboratorio completo.
# ============================================================================
set -euo pipefail

export PGOPTIONS='-c client_min_messages=warning'

for archivo in 01-schema 02-functions 03-triggers 04-seed 05-views; do
    echo "init-db: aplicando sql/${archivo}.sql"
    psql -v ON_ERROR_STOP=1 -q \
         --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
         -f "/lab/sql/${archivo}.sql"
done

echo "init-db: laboratorio cargado"
