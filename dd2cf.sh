#!/bin/bash

# dd2cf.sh - Dynamic DNS to Cloudflare updater

# Configuration
config_dir="/etc/dd2cf"
config_file="${config_dir}/dd2cf.conf"
log_dir="${HOME}/log"
log_file="${log_dir}/dd2cf.log"
cloudflare_base="https://api.cloudflare.com/client/v4"

# Function to create directory if it doesn't exist
create_dir_if_not_exists() {
    if [ ! -d "$1" ]; then
        echo "Creating directory: $1"
        mkdir -p "$1"
        if [ $? -eq 0 ]; then
            echo "Successfully created directory: $1"
        else
            echo "Failed to create directory: $1"
            exit 1
        fi
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

# Print usage text and exit
print_usage() {
    echo "
    dd2cf.sh (Dynamic DNS to Cloudflare): Update Cloudflare DNS 'A' records for your dynamic IP.

    Usage: dd2cf.sh [-v|--verbose]

    Options:
        -v, --verbose    Enable verbose logging

    dd2cf.sh UPDATES existing records. Please create them in Cloudflare Dashboard before running this script.

    The configuration file must be created at: $config_file
    Configuration file structure:

    zone_id=<zone id>
    api_key=<api key>

    dns_name=test.example.com
    dns_proxy=false

    dns_name=test2.example.com
    dns_proxy=true
    "
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

# Create necessary directories
create_dir_if_not_exists "$config_dir"

# Check if config file exists
if [ ! -f "$config_file" ]; then
    log_message "Error: Configuration file $config_file not found."
    log_message "Please create the configuration file with the following structure:"
    log_message "
    zone_id=<your_zone_id>
    api_key=<your_api_key>

    dns_name=example.com
    dns_proxy=true

    dns_name=subdomain.example.com
    dns_proxy=false
    "
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
cloudflare_response=$(curl -s -X GET \
    "${cloudflare_base}/zones/${zone_id}/dns_records" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${api_key}")

if [ "$(echo "$cloudflare_response" | jq -r '.success')" != "true" ]; then
    log_message "Error fetching DNS records from Cloudflare: $(echo "$cloudflare_response" | jq -r '.errors[0].message')"
    exit 1
fi

existing_records_raw=$(echo "$cloudflare_response" | jq -c '.result[] | select(.type == "A") | [.id, .name, .ttl, .content]')

# Process DNS records
log_message "Processing DNS records..."
while IFS= read -r line; do
    if [[ "$line" =~ ^dns_name= ]]; then
        dns_name="${line#dns_name=}"
        dns_proxy=$(grep "^dns_proxy=" -A1 <<< "$line" | tail -n1 | cut -d'=' -f2)
        
        echo "$existing_records_raw" | while read -r record; do
            id=$(echo "$record" | jq -r '.[0]')
            name=$(echo "$record" | jq -r '.[1]')
            ttl=$(echo "$record" | jq -r '.[2]')
            content=$(echo "$record" | jq -r '.[3]')

            if [ "$name" = "$dns_name" ]; then
                if [ "$public_ip" != "$content" ]; then
                    log_message "Updating DNS record for $name..."
                    update_result=$(curl -s -X PATCH \
                        "${cloudflare_base}/zones/${zone_id}/dns_records/${id}" \
                        -H "Content-Type: application/json" \
                        -H "Authorization: Bearer ${api_key}" \
                        -d '{
                            "content": "'${public_ip}'",
                            "name": "'${name}'",
                            "proxied": '${dns_proxy}',
                            "type": "A",
                            "comment": "Managed by dd2cf.sh",
                            "ttl": '${ttl}'
                        }')
                    
                    if echo "$update_result" | jq -e '.success' > /dev/null; then
                        log_message "Successfully updated $name"
                    else
                        log_message "Failed to update $name: $(echo "$update_result" | jq -r '.errors[0].message')"
                    fi
                else
                    log_message "$name did not change"
                fi
            fi
        done
    fi
done < "$config_file"

log_message "DNS update process completed"
