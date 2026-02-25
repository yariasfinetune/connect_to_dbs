#!/bin/bash

# This script will help connect your backend services to higher dbs. (QA, UAT)

# Absolute path to this script's directory (so we can read repo-local files after cd).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Declare an associative array where each value is an array of database variables
declare -A services_list

# Define the database variables for each service as arrays
services_list=(
    ["service-fym"]="(DATABASE_URL LEARNOSITY_DOMAIN LEARNOSITY_SECRET LEARNOSITY_KEY LEARNOSITY_AP_ORG_ID SERVICE_WIZARDS_GRAPHQL_URL SERVICE_WIZARDS_ACCESS_TOKEN ASSOCIATED_RESOURCES_BUCKET_NAME S3_BUCKET_SUFFIX)" # Connecting to learnosity in the respective environment. Not valid if you need to work on service-learnosity itself.
    ["service-units"]="(DATABASE_URL)"
    ["service-reporting"]="(FYM_DB SERVICE_UNITS_GRAPHQL_URL SERVICE_UNITS_ACCESS_TOKEN TRACKER_DB_URL)"
    ["service-accounts"]="(DATABASE_URL)"
)

SERVICE_REPORTING_VARIABLES_LOCAL=(
    "SERVICE_UNITS_GRAPHQL_URL"
    "SERVICE_UNITS_ACCESS_TOKEN"
    "SERVICE_WIZARDS_GRAPHQL_URL"
    "SERVICE_WIZARDS_ACCESS_TOKEN"
)

function get_credential_value() {
    local aws_profile="$1"
    local service_name="$2"
    local environment="$3"
    local var="$4"

    local raw
    local value
    local user_pass
    local db_name

    raw=$(AWS_PROFILE="$aws_profile" ~/finetune/infra/bin/creds "$service_name" "$environment" get "$var")
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "Error: Failed to get credentials for $service_name" >&2
        return $exit_code
    fi

    # Remove the "Value: " prefix from the output
    value=${raw#Value: }

    # Check if the value contains DB or DATABASE and replace the host if needed
    if [[ "$var" == *"DB"* || "$var" == *"DATABASE"* ]]; then
        # Replace the database host with host.docker.internal:33333
        if [[ "$value" == postgresql://* ]]; then
            # Extract username, password and database name
            user_pass=$(echo "$value" | sed -E 's|postgresql://([^@]+)@.+|\1|')
            db_name=$(echo "$value" | sed -E 's|.+/([^/]+)$|\1|')
            # Construct new connection string
            value="postgresql://${user_pass}@host.docker.internal:33333/${db_name}"
            echo "Modified connection string to use host.docker.internal:33333" >&2
        fi
    fi

    if [[ "$var" == "TRACKER_DB_URL" ]]; then
        # Properly extract user:pass and db name, and reconstruct the connection string
        user_pass=$(echo "$value" | sed -E 's|postgresql\+psycopg2://([^@]+)@.*|\1|')
        # If the original value contains a database name, extract it, else use {0}
        db_name=$(echo "$value" | sed -nE 's|.*/([^/?]+).*|\1|p')
        if [[ -z "$db_name" ]]; then
            db_name="{0}"
        fi
        value="postgresql+psycopg2://${user_pass}@host.docker.internal:33339/${db_name}"
        echo "Modifying tracker db connection string to use host.docker.internal:33339" >&2
    fi

    echo "$value"
}

function connect_to_higher_db() {
    if [[ "$environment" == "local" ]]; then
        # Local mode: clear .env.local for all services, only populate explicit local vars.
        for service in "${!services_list[@]}"; do
            echo "Setting $service (local)"

            if ! cd ~/finetune/"$service"; then
                echo "Warning: could not cd to ~/finetune/$service; skipping" >&2
                continue
            fi

            # Always clear .env.local for each service in local mode.
            echo "" > .env.local

            if [[ "$service" == "service-fym" ]]; then
                if [[ -f "$SCRIPT_DIR/.env.local" ]]; then
                    cat "$SCRIPT_DIR/.env.local" >> .env.local
                else
                    echo "Warning: $SCRIPT_DIR/.env.local not found; skipping service-fym local vars" >&2
                fi
            elif [[ "$service" == "service-reporting" ]]; then
                local aws_profile="finetune-cb-nonprod"
                for var in "${SERVICE_REPORTING_VARIABLES_LOCAL[@]}"; do
                    value="$(get_credential_value "$aws_profile" "reporting" "uat" "$var")"
                    exit_code=$?
                    if [[ $exit_code -ne 0 ]]; then
                        exit $exit_code
                    fi
                    echo "Setting $var for $service"
                    echo "$var=$value" >> .env.local
                done
            fi
        done

        return 0
    fi

    for service in "${!services_list[@]}"; do
        echo "Setting $service"
        # Use array expansion to iterate over the database variables
        # The error is because we're trying to expand an array inside a string
        # We need to extract the array definition first, then expand it

        cd ~/finetune/$service

        # Delete the content of .env.local file before adding new variables
        echo "" > .env.local

        db_vars=${services_list[$service]}
        eval "array=$db_vars"
        for var in "${array[@]}"; do
            echo "Setting $var for $service"
            service_name=${service#service-}
            if [[ "$environment" == "testing" ]]; then
                aws_profile="finetune-cb-production"
            else
                aws_profile="finetune-cb-nonprod"
            fi
            aws_command="AWS_PROFILE=$aws_profile ~/finetune/infra/bin/creds $service_name $environment get $var"
            echo "$aws_command"

            value="$(get_credential_value "$aws_profile" "$service_name" "$environment" "$var")"
            exit_code=$?
            if [[ $exit_code -ne 0 ]]; then
                exit $exit_code
            fi
            echo "Update .env.local for $service"
            echo "$var=$value" >> .env.local
        done
    done
}



function usage() {
    echo "Usage: $0 <environment>"
    echo "Environment can be one of: local, testing, uat"
    
    if [[ "$1" != "local" && "$1" != "testing" && "$1" != "uat" ]]; then
        echo "Error: Environment must be one of local, testing, uat" >&2
        exit 1
    fi
    environment=$1
    if [[ "$environment" == "local" ]]; then
        echo "Connecting to local database"
    fi
    if [[ "$environment" == "testing" ]]; then
        echo "Connecting to testing database"
    fi

    echo "Connecting to uat database"
    connect_to_higher_db
    exit 0
}

usage $1










