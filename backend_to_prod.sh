#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "Error: .env file not found. Copy .env.example to .env and fill in your credentials." >&2
    exit 1
fi

source "$SCRIPT_DIR/.env"

PRODUCTION_DATABASE_URL="postgresql://${PRODUCTION_DB_USERNAME}:${PRODUCTION_DB_PASSWORD}@host.docker.internal:33333/${PRODUCTION_DB_NAME}"
PRODUCTION_UNITS_DATABASE_URL="postgresql://${PRODUCTION_DB_USERNAME}:${PRODUCTION_DB_PASSWORD}@host.docker.internal:33333/${PRODUCTIONS_UNITS_DB_NAME}"

DEPLOY_ENV=production

declare -A services_list

services_list=(
    ["service-fym"]="(DATABASE_URL DEPLOY_ENV)" # Connecting to learnosity in the respective environment. Not valid if you need to work on service-learnosity itself.
    ["service-units"]="()"
    ["service-reporting"]="(FYM_DB TRACKER_DB_URL SERVICE_UNITS_GRAPHQL_URL SERVICE_UNITS_ACCESS_TOKEN)"
    # ["service-reporting"]="(FYM_DB TRACKER_DB_URL)"
    ["service-accounts"]="(DATABASE_URL)"
)

variable_mapping=(
    ["SERVICE_UNITS_GRAPHQL_URL"]="$SERVICE_UNITS_GRAPHQL_URL"
    ["SERVICE_UNITS_ACCESS_TOKEN"]="$SERVICE_UNITS_ACCESS_TOKEN"
)

for service in "${!services_list[@]}"; do
    echo "Setting $service"
    cd ~/finetune/$service
    echo "" > .env.local
    db_vars=${services_list[$service]}
    eval "array=$db_vars"
    for var in "${array[@]}"; do
        echo "Setting $var for $service"
        if [[ "$var" == *"DB"* || "$var" == *"DATABASE"* ]]; then
            value="'$PRODUCTION_DATABASE_URL'"
            if [[ "$service" == "service-units" ]]; then
                value="'$PRODUCTION_UNITS_DATABASE_URL'"
            fi
        fi
        if [[ "$var" == *"TRACKER_DB_URL"* ]]; then
            value="$TRACKER_DB_URL"
        fi
        if [[ "$var" == *"DEPLOY_ENV"* ]]; then
            value=$DEPLOY_ENV
        fi
        if [[ "$var" == *"SERVICE_UNITS_GRAPHQL_URL"* ]]; then
            value="$SERVICE_UNITS_GRAPHQL_URL"
        fi
        if [[ "$var" == *"SERVICE_UNITS_ACCESS_TOKEN"* ]]; then
            value="$SERVICE_UNITS_ACCESS_TOKEN"
        fi
        if [[ "$var" == *"SERVICE_UNITS_GRAPHQL_URL"* ]]; then
            value="$SERVICE_UNITS_GRAPHQL_URL"
        fi
        echo "$var=$value" >> .env.local
    done
done







