#!/usr/bin/env bash
# ============================================================================
# scripts/run-tests.sh
# Recarga la base (las suites asumen el seed intacto) y ejecuta la batería de
# pruebas. Devuelve código distinto de 0 si alguna suite falla.
# Se ejecuta dentro del contenedor:
#   docker compose exec -T db /lab/scripts/run-tests.sh            # todas
#   docker compose exec -T db /lab/scripts/run-tests.sh 02 03      # algunas
# Colores ANSI activados salvo que se defina NO_COLOR.
# ============================================================================
set -euo pipefail

# Mismos valores por defecto que la imagen oficial (no los exporta a `docker exec`)
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_DB:=$POSTGRES_USER}"

DIR_TESTS=/lab/tests
DIR_SCRIPTS=/lab/scripts

if [[ -z "${NO_COLOR:-}" ]]; then
    VERDE=$'\e[32m'; ROJO=$'\e[31m'; NEGRITA=$'\e[1m'; NORMAL=$'\e[0m'
else
    VERDE=''; ROJO=''; NEGRITA=''; NORMAL=''
fi

colorear() {
    sed -e "s/| PASS /| ${VERDE}PASS${NORMAL} /" \
        -e "s/| FAIL /| ${ROJO}FAIL${NORMAL} /" \
        -e "s/^\(.*ERROR:.*\)$/${ROJO}\1${NORMAL}/" \
        -e "s/^\( .* pruebas OK\)$/${VERDE}\1${NORMAL}/"
}

# Selección de suites: por prefijo numérico (01, 02, 03) o todas
suites=()
if [[ $# -eq 0 ]]; then
    for archivo in "$DIR_TESTS"/[0-9][0-9]-*.sql; do
        [[ "$(basename "$archivo")" == 00-* ]] && continue
        suites+=("$archivo")
    done
else
    for prefijo in "$@"; do
        coincidencias=("$DIR_TESTS"/"$prefijo"-*.sql)
        if [[ ! -e "${coincidencias[0]}" ]]; then
            echo "${ROJO}run-tests: no existe la suite '${prefijo}'${NORMAL}" >&2
            exit 2
        fi
        suites+=("${coincidencias[0]}")
    done
fi

"$DIR_SCRIPTS"/reset-db.sh

inicio=$EPOCHREALTIME
fallidas=()

for suite in "${suites[@]}"; do
    nombre=$(basename "$suite" .sql)
    echo
    echo "${NEGRITA}▶ ${nombre}${NORMAL}"
    if ! psql -v ON_ERROR_STOP=1 -X \
              --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
              -f "$suite" 2>&1 | colorear; then
        fallidas+=("$nombre")
    fi
done

duracion=$(awk -v a="$inicio" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.1f", b - a }')

echo
if [[ ${#fallidas[@]} -eq 0 ]]; then
    echo "${VERDE}${NEGRITA}✔ Suites OK: ${#suites[@]}${NORMAL} (${duracion} s)"
else
    echo "${ROJO}${NEGRITA}✘ Suites con fallas: ${fallidas[*]}${NORMAL} (${duracion} s)"
    exit 1
fi
