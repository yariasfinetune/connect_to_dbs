#!/bin/bash

# This script will help connect your backend services to higher dbs. (QA, UAT)

# Declare an associative array where each value is an array of database variables
declare -A services_list

# Define the database variables for each service as arrays
services_list=(
    ["service-fym"]="(DATABASE_URL LEARNOSITY_DOMAIN LEARNOSITY_SECRET LEARNOSITY_KEY LEARNOSITY_AP_ORG_ID)" # Connecting to learnosity in the respective environment. Not valid if you need to work on service-learnosity itself.
    ["service-units"]="(DATABASE_URL)"
    ["service-reporting"]="(FYM_DB SERVICE_UNITS_GRAPHQL_URL SERVICE_UNITS_ACCESS_TOKEN TRACKER_DB_URL)"
    ["service-accounts"]="(DATABASE_URL)"
)

function connect_to_higher_db() {
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
                echo $aws_command
                value=$(eval $aws_command)
                
                # Check if the command was successful
                if [ $? -ne 0 ]; then
                    echo "Error: Failed to get credentials for $service_name" >&2
                    exit $?
                fi
                
                # Remove the "Value: " prefix from the output
                value=${value#Value: }
                # Check if the value contains DB or DATABASE and replace the host if needed
                if [[ "$var" == *"DB"* || "$var" == *"DATABASE"* ]]; then
                    # Replace the database host with host.docker.internal:33333
                    if [[ "$value" == postgresql://* ]]; then
                        # Extract username, password and database name
                        user_pass=$(echo "$value" | sed -E 's|postgresql://([^@]+)@.+|\1|')
                        db_name=$(echo "$value" | sed -E 's|.+/([^/]+)$|\1|')
                        # Construct new connection string
                        value="postgresql://${user_pass}@host.docker.internal:33333/${db_name}"
                        echo "Modified connection string to use host.docker.internal:33333"
                    fi
                fi
                if [[ "$var" == "TRACKER_DB_URL" ]]; then
                    # value="postgresql+psycopg2://cb_dataguru:78cb_reportingKicker@apc-telemetry.cbymfk8mkcac.us-east-1.redshift.amazonaws.com:5439/{0}"
                    # Properly extract user:pass and db name, and reconstruct the connection string
                    user_pass=$(echo "$value" | sed -E 's|postgresql\+psycopg2://([^@]+)@.*|\1|')
                    # If the original value contains a database name, extract it, else use {0}
                    db_name=$(echo "$value" | sed -nE 's|.*/([^/?]+).*|\1|p')
                    if [[ -z "$db_name" ]]; then
                        db_name="{0}"
                    fi
                    value="postgresql+psycopg2://${user_pass}@host.docker.internal:33339/${db_name}"
                    echo "Modifying tracker db connection string to use host.docker.internal:33339"
                fi
                echo "Update .env.local for $service"
            echo "$var=$value" >> .env.local
        done
    done
}



function usage() {
    echo "Usage: $0 <environment>"
    echo "Environment can be one of: testing, uat"
    
    if [[ "$1" != "testing" && "$1" != "uat" ]]; then
        echo "Error: Environment must be one of testing, uat" >&2
        exit 1
    fi
    environment=$1
    if [[ "$environment" == "testing" ]]; then
        echo "Connecting to testing database"
    fi

    echo "Connecting to uat database"
    connect_to_higher_db
    exit 0
}

usage $1










