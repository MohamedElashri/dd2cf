#!/bin/bash

config_file_dir="/etc/dd2cf" 
config_file_name="dd2cf.conf"
config_file="${config_file_dir}/${config_file_name}" 
log_file_dir="${config_file_dir}/logs"
log_file="${log_file_dir}/dd2cf.log"

cloudflare_base="https://api.cloudflare.com/client/v4"

# print usage text and exit
print_usage() {
    echo '
    dd2cf (Dynamic DNS Cloudflare): Update Cloudflare DNS 'A' records for your dynamic IP.

    Usage: dd2cf.sh

    `dd2cf` UPDATES existing records. Please, create them in Cloudflare Dashboard before running this script.

    The configuration is done in `/etc/dd2cf/dd2cf.conf`.
    Configuration file structure:

    api:
      zone-id = "<zone id>"
      api-key = "<api key>"

    dns:
      - name = "test.example.com"
        proxy = false
      - name = "test2.example.com"
        proxy = true
    '
}

# print usage if requested
if [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    print_usage
    exit
fi

# ensure yq is installed
if ! command -v yq > /dev/null 2>&1; then
    echo "Error: 'yq' required and not found."
    echo "Please install: https://github.com/mikefarah/yq." | tee -a ${log_file}
    exit 1
fi

# ensure curl is installed
if ! command -v curl > /dev/null 2>&1; then
    echo "Error: 'curl' required and not found."
    echo "Please install: https://curl.se/download.html or through your package manager." | tee -a ${log_file}
    exit 1
fi

# create config dir if not exists
if [ ! -d $config_file_dir ]; then
    echo "Directory: ${config_file_dir} does not exist."
    echo "Creating..." | tee -a ${log_file}
    sudo mkdir -p $config_file_dir

    echo "Created ${config_file_dir}. Please, fill ${config_file}." | tee -a ${log_file}
    exit 0
fi

# get my public ip
public_ip=$(curl https://ip.melashri.eu.org/ip)

# read zone-id and api-key from config file
zone_id=$(yq e '.api.zone-id' ${config_file})
api_key=$(yq e '.api.api-key' ${config_file})

# get records from cloudflare
existing_records_raw=$(curl --silent --request GET \
    --url ${cloudflare_base}/zones/${zone_id}/dns_records \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer ${api_key}" \
    | yq -oj -I=0 '.result[] | select(.type == "A") | [.id, .name, .ttl, .content]'
)

# get records defined in config file
readarray -t config_records < <(yq -o=json e '.dns[]' ${config_file})

# iterate cloudflare records
# for each record, check if it exists in config file
# if it does, update record
for record in ${existing_records_raw[@]}; do
    id=$(yq e '.[0]' <<< "${record}")
    name=$(yq e '.[1]' <<< "${record}")
    ttl=$(yq e '.[2]' <<< "${record}")
    content=$(yq e '.[3]' <<< "${record}")

    for c_record in "${config_records[@]}"; do
        c_name=$(yq e '.name' <<< ${c_record})
        c_proxy=$(yq e '.proxy' <<< ${c_record})

        if [ "$name" = "$c_name" ]; then
            if [ "$public_ip" != "$content" ]; then
                # update dns
                curl --silent --request PATCH \
                --url "${cloudflare_base}/zones/${zone_id}/dns_records/${id}" \
                --header 'Content-Type: application/json' \
                --header "Authorization: Bearer ${api_key}" \
                --data '{
                    "content": "'${public_ip}'",
                    "name": "'${name}'",
                    "proxied": '${c_proxy}',
                    "type": "A",
                    "comment": "Managed by dd2cf.sh",
                    "ttl": '${ttl}'
                }' > /dev/null

                echo "[dd2cf.sh] OK: ${name}" | tee -a ${log_file}
            else
                echo "[dd2cf.sh] ${name} did not change" | tee -a ${log_file}
            fi
        fi
    done
done
