### README.md

# dd2cf.sh

## Overview

`dd2cf.sh` is a script designed to update Cloudflare DNS 'A' records for your dynamic IP. This script is an adjusted version of the [d2c script](https://github.com/ddries/d2c.sh) by ddries, with personal modifications to better suit specific needs. Many thanks to ddries for the original implementation.

## Features

- Fetches current public IP address from `https://ip.melashri.eu.org/ip`.
- Updates existing Cloudflare DNS 'A' records if there are any changes.
- Supports logging to a file for detailed output.
- Configured using a simple `.conf` file format.

## Prerequisites

- `curl`: A command-line tool for transferring data with URLs.
- `yq`: A lightweight and portable command-line YAML, JSON, and XML processor.

## Installation

1. **Clone the Repository**:
   ```sh
   git clone https://github.com/MohamedElashri/dd2cf.sh
   cd dd2cf.sh
   ```

2. **Install Dependencies**:
   Ensure `curl` and `yq` are installed on your system. You can install them using your package manager.

   For `yq`:
   ```sh
   sudo apt-get install yq   # For Debian-based systems
   sudo yum install yq       # For RedHat-based systems
   ```

   For `curl`:
   ```sh
   sudo apt-get install curl   # For Debian-based systems
   sudo yum install curl       # For RedHat-based systems
   ```

3. **Configuration**:
   Create and edit the configuration file at `/etc/dd2cf/dd2cf.conf` with the following structure:
   ```conf
   api:
     zone-id = "your-zone-id" # your DNS zone ID
     api-key = "your-api-key" # your API key with DNS records permissions

   dns:
     - name = "dns1.example.com" # DNS name
       proxy = true # proxied by Cloudflare?

     - name = "dns2.example.com"
       proxy = false
   ```

4. **Permissions**:
   Ensure the script has execution permissions:
   ```sh
   chmod +x dd2cf.sh
   ```

## Usage

To run the script manually:
```sh
./dd2cf.sh
```

This will fetch your current public IP address and update the specified DNS 'A' records in Cloudflare if there are any changes. The details of the execution will be logged in `/etc/dd2cf/logs/dd2cf.log`.

## Automating with Cronjob

The best way to automate the process is by setting up a cron job. This will ensure that your DNS records are kept up-to-date with your dynamic IP without manual intervention.

### Setting up Cronjob

1. Open the crontab file for editing:
   ```sh
   crontab -e
   ```

2. Add the following line to run the script every hour (you can adjust the timing as needed):
   ```sh
   0 * * * * /path/to/dd2cf.sh
   ```

3. Save and exit the editor.

This cron job entry will run the `dd2cf.sh` script every hour, ensuring that your Cloudflare DNS records are always up-to-date with your current public IP address.

## Acknowledgements

This script is an adjusted version of the [d2c script](https://github.com/ddries/d2c.sh) by ddries. Many thanks to ddries for the original implementation and inspiration.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

---

By following the instructions above, you should be able to configure and run the `dd2cf.sh` script to automatically update your Cloudflare DNS 'A' records for your dynamic IP. The cron job setup ensures that this process is automated, saving you time and effort.
