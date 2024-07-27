# dd2cf.sh - Cloudflare Dynamic DNS 

dd2cf.sh is a Bash script that automatically updates Cloudflare DNS 'A' records with your current public IP address. This script is particularly useful for systems with dynamic IP addresses that need to maintain accurate DNS records.

## Features

- Automatically detects your public IP address
- Updates multiple DNS records in Cloudflare
- Supports proxied and non-proxied records
- Verbose logging option
- Easy to configure and use

## Prerequisites

- Bash shell
- `curl`
- `yq` (https://github.com/mikefarah/yq)
- Cloudflare account with API access

## Installation

1. Download the `dd2cf.sh` script to your desired location.
2. Make the script executable:
   ```
   chmod +x dd2cf.sh
   ```
3. Create the configuration file at `/etc/dd2cf/dd2cf.conf` (see Configuration section).

## Configuration

Create a configuration file at `/etc/dd2cf/dd2cf.conf` with the following structure:

```
zone_id=<your_zone_id>
api_key=<your_api_key>

dns_name=<example.com>
dns_proxy=true # proxied via cloudflare?

dns_name=<subdomain.example.com>
dns_proxy=false # proxied via cloudflare?
```

- `zone_id`: Your Cloudflare zone ID
- `api_key`: Your Cloudflare API key
- `dns_name`: The domain or subdomain to update
- `dns_proxy`: Whether the record should be proxied through Cloudflare (true/false)

You can add multiple DNS records by repeating the `dns_name` and `dns_proxy` lines.

## Usage

Run the script manually:

```
./dd2cf.sh
```

For verbose output, use the `-v` or `--verbose` option:

```
./dd2cf.sh -v
```

## Automating with Cron

To automatically update your DNS records at regular intervals, you can set up a cron job:

1. Open your crontab file:
   ```
   crontab -e
   ```

2. Add a line to run the script every 5 minutes (adjust the path as needed):
   ```
   */5 * * * * /path/to/dd2cf.sh
   ```

3. Save and exit the crontab editor.

This setup will run the script every 5 minutes. Adjust the timing based on your needs and how frequently your IP address changes.

## How It Works

1. The script reads the configuration file.
2. It fetches your current public IP address using `https://ip.melashri.eu.org/ip`.
3. It retrieves existing DNS records from Cloudflare for your zone.
4. For each configured DNS record, it compares the current IP with the recorded IP.
5. If there's a mismatch, it updates the Cloudflare DNS record with the new IP.
6. All actions are logged to `/var/log/dd2cf.log`.

## Troubleshooting

- Check the log file at `/var/log/dd2cf.log` for detailed information about the script's operations.
- Ensure your Cloudflare API key has the necessary permissions to modify DNS records.
- Verify that the `curl` and `yq` commands are available on your system.

## Contributing

This script is a personal modification of the original d2c.sh script. While it's primarily maintained for personal use, suggestions and improvements are welcome.

## Acknowledgements

This script is an adjusted version of the [d2c script](https://github.com/ddries/d2c.sh) by ddries. Many thanks to ddries for the original implementation and inspiration.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.


