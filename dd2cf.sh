#!/bin/bash

# dd2cf.sh - Dynamic DNS to Cloudflare updater

# Configuration
config_dir="/etc/dd2cf"
config_file="${config_dir}/dd2cf.conf"
log_dir="${HOME}/log"
log_file="${log_dir}/dd2cf.log"
cloudflare_base="https://api.cloudflare.com/client/v4"

# Function to print usage text and exit
print_usage() {
    echo '
    dd2cf (Dynamic DNS to Cloudflare): Update Cloudflare DNS 'A' records for your dynamic IP.

    Usage: dd2cf.sh [-v|--verbose] [-h|--help]

    Options:
        -v, --verbose    Enable verbose logging
        -h, --help       Display this help message

    dd2cf UPDATES existing records. Please create them in Cloudflare Dashboard before running this script.

    The configuration is done in /etc/dd2cf/dd2cf.conf.
    Configuration file structure:

    zone_id=<your_zone_id>
    api_key=<your_api_key>

    dns_name=example.com
    dns_proxy=true

    dns_name=subdomain.example.com
    dns_proxy=false

    You can add multiple DNS records by repeating the dns_name and dns_proxy lines.
    '
}

# Function to create directory if it doesn't exist
create_dir_if_not_exists() {
    if [ ! -d "$1" ]; then
        echo "Creating directory: $1"
        mkdir -p "$1"
    fi
}

# Create log directory
create_dir_if_not_exists "$log_dir"

# Function to log messages
log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$log_file"
    [ "$verbose" = true ] && echo "[$timestamp] $1"
}

# Parse command line options
verbose=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -v|--verbose) verbose=true ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown parameter: $1"; print_usage; exit 1 ;;
    esac
    shift
done

# Ensure required commands are installed
for cmd in jq curl; do
    if ! command -v $cmd &> /dev/null; then
        log_message "Error: '$cmd' is required but not found. Please install it."
        exit 1
    fi
done

# Check if config file exists
if [ ! -f "$config_file" ]; then
    log_message "Error: Configuration file $config_file not found."
    exit 1
fi

# Get public IP
log_message "Fetching public IP address..."
public_ip=$(curl -s https://ip.melashri.eu.org/ip)
log_message "Public IP: $public_ip"

# Read configuration
zone_id=$(grep '^zone_id=' "$config_file" | cut -d'=' -f2)
api_key=$(grep '^api_key=' "$config_file" | cut -d'=' -f2)

# Get records from Cloudflare
log_message "Fetching DNS records from Cloudflare..."
existing_records_raw=$(curl -s -X GET \
    "${cloudflare_base}/zones/${zone_id}/dns_records" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${api_key}" \
    | jq -c '.result[] | select(.type == "A") | [.id, .name, .ttl, .content]')

# Get records defined in config file
readarray config_records < <(grep '^dns_name=' "$config_file" | sed 's/dns_name=//')

# Process DNS records
log_message "Processing DNS records..."
for record in ${existing_records_raw[@]}; do
    id=$(echo "$record" | jq -r '.[0]')
    name=$(echo "$record" | jq -r '.[1]')
    ttl=$(echo "$record" | jq -r '.[2]')
    content=$(echo "$record" | jq -r '.[3]')

    for c_record in "${config_records[@]}"; do
        c_name=$(echo "$c_record" | tr -d '\n')
        c_proxy=$(grep "^dns_proxy=" -A1 "$config_file" | grep -A1 "^dns_name=$c_name" | tail -n1 | cut -d'=' -f2)

        # Ensure c_proxy is a valid boolean
        if [ "$c_proxy" != "true" ] && [ "$c_proxy" != "false" ]; then
            c_proxy="false"
        fi

        if [ "$name" = "$c_name" ]; then
            if [ "$public_ip" != "$content" ]; then
                log_message "Updating DNS record for $name..."
                
                # Construct the request body
                request_body='{
                    "content": "'${public_ip}'",
                    "name": "'${name}'",
                    "proxied": '${c_proxy}',
                    "type": "A",
                    "comment": "Managed by dd2cf.sh",
                    "ttl": '${ttl}'
                }'
                
                # Log request body only if verbose mode is enabled
                [ "$verbose" = true ] && log_message "Request body: $request_body"
                
                update_result=$(curl -s -X PATCH \
                    "${cloudflare_base}/zones/${zone_id}/dns_records/${id}" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer ${api_key}" \
                    -d "$request_body")
                
                if echo "$update_result" | jq -e '.success' > /dev/null; then
                    log_message "Successfully updated $name"
                else
                    error_message=$(echo "$update_result" | jq -r '.errors[0].message // "Unknown error"')
                    log_message "Failed to update $name: $error_message"
                    [ "$verbose" = true ] && log_message "Full response: $update_result"
                fi
            else
                log_message "$name did not change"
            fi
        fi
    done
done

log_message "DNS update process completed"
