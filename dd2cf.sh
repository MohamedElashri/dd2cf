#!/bin/sh
# dd2cf.sh - Dynamic DNS to Cloudflare updater (shell-agnostic version)

# Set explicit paths for commands
JQ="/usr/bin/jq"
CURL="/usr/bin/curl"
GREP="/bin/grep"
CUT="/usr/bin/cut"
DATE="/bin/date"
MKDIR="/bin/mkdir"
TAIL="/usr/bin/tail"
TR="/usr/bin/tr"

# Configuration
config_dir="/etc/dd2cf"
config_file="${config_dir}/dd2cf.conf"
log_dir="${HOME}/log"
log_file="${log_dir}/dd2cf.log"
cloudflare_base="https://api.cloudflare.com/client/v4"

# Ensure PATH includes common directories
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Function to print usage text and exit
print_usage() {
    echo '
    dd2cf (Dynamic DNS to Cloudflare): Update Cloudflare DNS "A" records for your dynamic IP.

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
        $MKDIR -p "$1"
    fi
}

# Create log directory
create_dir_if_not_exists "$log_dir"

# Function to log messages
log_message() {
    local timestamp
    timestamp=$($DATE "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$log_file"
    if [ "$verbose" = "true" ]; then 
        echo "[$timestamp] $1"
    fi
}

# Parse command line options
verbose="false"
while [ "$#" -gt 0 ]; do
    case $1 in
        -v|--verbose) verbose="true" ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown parameter: $1"; print_usage; exit 1 ;;
    esac
    shift
done

# Debug info
log_message "Script started with shell: $0"
log_message "Current PATH: $PATH"

# Check if jq exists and is executable
if [ -x "$JQ" ]; then
    log_message "Found jq at $JQ"
else
    # Try to find jq in PATH
    JQ=$(which jq 2>/dev/null)
    if [ -x "$JQ" ]; then
        log_message "Found jq in PATH at $JQ"
    else
        log_message "Error: 'jq' is required but not found. Please install it."
        exit 1
    fi
fi

# Check if curl exists and is executable
if [ -x "$CURL" ]; then
    log_message "Found curl at $CURL"
else
    # Try to find curl in PATH
    CURL=$(which curl 2>/dev/null)
    if [ -x "$CURL" ]; then
        log_message "Found curl in PATH at $CURL"
    else
        log_message "Error: 'curl' is required but not found. Please install it."
        exit 1
    fi
fi

# Check if config file exists
if [ ! -f "$config_file" ]; then
    log_message "Error: Configuration file $config_file not found."
    exit 1
fi

# Get public IP
log_message "Fetching public IP address..."
public_ip=$($CURL -s https://ip.melashri.eu.org/ip)
log_message "Public IP: $public_ip"

# Read configuration
zone_id=$($GREP '^zone_id=' "$config_file" | $CUT -d'=' -f2)
api_key=$($GREP '^api_key=' "$config_file" | $CUT -d'=' -f2)

if [ -z "$zone_id" ] || [ -z "$api_key" ]; then
    log_message "Error: zone_id or api_key not found in config file."
    exit 1
fi

# Get records from Cloudflare
log_message "Fetching DNS records from Cloudflare..."
existing_records_raw=$($CURL -s -X GET \
    "${cloudflare_base}/zones/${zone_id}/dns_records" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${api_key}")

if [ "$verbose" = "true" ]; then
    log_message "Raw response from Cloudflare: $existing_records_raw"
fi

# Extract A records
a_records=$($JQ -c '.result[] | select(.type == "A") | [.id, .name, .ttl, .content]' <<< "$existing_records_raw")
log_message "Found A records: $a_records"

# Process each A record from the config file
dns_names=$($GREP '^dns_name=' "$config_file" | $CUT -d'=' -f2)
for name in $dns_names; do
    log_message "Processing record for domain: $name"
    
    # Get proxy setting for this domain
    proxy_line=$($GREP -A1 "^dns_name=$name" "$config_file" | $TAIL -n1)
    if echo "$proxy_line" | $GREP -q '^dns_proxy='; then
        proxy_value=$(echo "$proxy_line" | $CUT -d'=' -f2 | $TR -d '\n')
        # Ensure proxy_value is valid
        if [ "$proxy_value" = "true" ] || [ "$proxy_value" = "false" ]; then
            c_proxy="$proxy_value"
        else
            c_proxy="false"
            log_message "Warning: Invalid proxy value for $name, using default: false"
        fi
    else
        c_proxy="false"
        log_message "Warning: No proxy setting found for $name, using default: false"
    fi
    
    # Find the matching record in the Cloudflare data
    record_found="false"
    echo "$a_records" | while read -r record; do
        if [ -z "$record" ]; then
            continue
        fi
        
        id=$(echo "$record" | $JQ -r '.[0]')
        record_name=$(echo "$record" | $JQ -r '.[1]')
        ttl=$(echo "$record" | $JQ -r '.[2]')
        content=$(echo "$record" | $JQ -r '.[3]')
        
        if [ "$record_name" = "$name" ]; then
            record_found="true"
            log_message "Found matching record for $name with current IP: $content"
            
            if [ "$public_ip" != "$content" ]; then
                log_message "Updating DNS record for $name from $content to $public_ip..."
                
                # Construct the request body
                request_body='{
                    "content": "'$public_ip'",
                    "name": "'$name'",
                    "proxied": '$c_proxy',
                    "type": "A",
                    "comment": "Managed by dd2cf.sh",
                    "ttl": '$ttl'
                }'
                
                if [ "$verbose" = "true" ]; then
                    log_message "Request body: $request_body"
                fi
                
                update_result=$($CURL -s -X PATCH \
                    "${cloudflare_base}/zones/${zone_id}/dns_records/${id}" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer ${api_key}" \
                    -d "$request_body")
                
                if echo "$update_result" | $JQ -e '.success' > /dev/null 2>&1; then
                    log_message "Successfully updated $name"
                else
                    error_message=$(echo "$update_result" | $JQ -r '.errors[0].message // "Unknown error"')
                    log_message "Failed to update $name: $error_message"
                    if [ "$verbose" = "true" ]; then
                        log_message "Full response: $update_result"
                    fi
                fi
            else
                log_message "$name did not change (still $content)"
            fi
        fi
    done
    
    if [ "$record_found" = "false" ]; then
        log_message "Warning: No existing record found for $name in Cloudflare. Create it first in the Cloudflare Dashboard."
    fi
done

log_message "DNS update process completed"
