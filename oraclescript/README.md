# Pyth Oracle Price Updater

This service automatically updates ETH/USD and USDC/USD price feeds in a SimplePriceOracle contract using the Pyth Network.

## Overview

The service:

- Fetches price updates from Pyth Network's Hermes API
- Calculates required update fees
- Sends transactions to your oracle contract
- Runs continuously with a 45-second update interval

## Setup on Digital Ocean

### Step 1: Create a Digital Ocean Droplet

1. Sign up/login to [Digital Ocean](https://cloud.digitalocean.com/)
2. Create a new Droplet:
   - Choose **Ubuntu 22.04 LTS**
   - Select **Basic plan** ($6/month option with 1GB RAM)
   - Choose a datacenter region close to you
   - Add your SSH key or create with password

### Step 2: Connect to Your Droplet

```bash
# If using SSH key
ssh root@YOUR_DROPLET_IP

# If using password, you'll be prompted for it
```

### Step 3: Set Up the Environment

```bash
# Update the system
apt update && apt upgrade -y

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs git

# Install PM2 for process management
npm install -g pm2
```

### Step 4: Clone and Setup the Repository

```bash
# Create directory and clone repository
mkdir -p /opt
cd /opt
git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git oracle-updater
cd oracle-updater

# Install dependencies
npm install

# Create .env file with your private key
echo "PRIVATE_KEY_TEST=YOUR_ACTUAL_PRIVATE_KEY" > .env

# Compile TypeScript
npx tsc
```

### Step 5: Run with PM2

```bash
# Start the updater in continuous mode
pm2 start dist/update-oracle.js --name "oracle-updater" -- continuous

# Setup auto-restart on system reboot
pm2 startup
# Run the command shown in the output
pm2 save

# Check status
pm2 status

# View logs
pm2 logs oracle-updater
```

### Step 6: Set Up Auto-Updates from GitHub

```bash
# Create update script
cat > /opt/oracle-updater/update.sh << 'EOF'
#!/bin/bash
cd /opt/oracle-updater
git pull
npm install
npx tsc
pm2 restart oracle-updater
EOF

# Make executable
chmod +x /opt/oracle-updater/update.sh

# Set up cron job to check for updates hourly
(crontab -l 2>/dev/null; echo "0 * * * * /opt/oracle-updater/update.sh") | crontab -
```

### Step 7: Secure Your Server

```bash
# Create a dedicated user instead of running as root
adduser oracleuser
usermod -aG sudo oracleuser

# Set proper ownership of the application files
chown -R oracleuser:oracleuser /opt/oracle-updater

# Set up firewall
ufw allow OpenSSH
ufw enable
```

## Configuration

- Update the `ORACLE_ADDRESS` in `src/update-oracle.ts` if your contract changes
- Adjust the `UPDATE_INTERVAL` to change how frequently prices are updated

## Available Commands

The script supports the following commands:

```bash
# Update prices once
node dist/update-oracle.js

# Run in continuous mode (45-second intervals)
node dist/update-oracle.js continuous

# Get price for a cToken
node dist/update-oracle.js price 0xYourCTokenAddress

# Get price for an asset
node dist/update-oracle.js asset-price 0xYourAssetAddress
```

## Monitoring and Maintenance

### Checking Logs

```bash
# View real-time logs
pm2 logs oracle-updater

# View last 100 log lines
pm2 logs oracle-updater --lines 100
```

### Restart the Service

```bash
# Restart the service
pm2 restart oracle-updater
```

### Check Transaction History

Visit [Arbiscan](https://sepolia.arbiscan.io/address/YOUR_WALLET_ADDRESS) to view transaction history for your wallet.

### Check Wallet Balance

```bash
# Run this from the project directory
cd /opt/oracle-updater
node -e "const { ethers } = require('ethers'); require('dotenv').config();
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY_TEST);
const provider = new ethers.JsonRpcProvider('https://sepolia-rollup.arbitrum.io/rpc');
async function main() {
  const balance = await provider.getBalance(wallet.address);
  console.log(wallet.address, ':', ethers.formatEther(balance), 'ETH');
}
main();"
```

## Troubleshooting

### Service Not Running

Check if the service is running:

```bash
pm2 status
```

If not running:

```bash
pm2 start dist/update-oracle.js --name "oracle-updater" -- continuous
```

### Out of Gas/Low Balance

If you see errors about insufficient funds:

1. Check your wallet balance (see above)
2. Send more ETH to your wallet address

### Network Issues

If you see connection errors to the RPC or Hermes API:

1. Check your internet connection
2. Try restarting the service:

```bash
pm2 restart oracle-updater
```

## Security Considerations

- Never share your private key
- Regularly rotate your private key
- Monitor your service for unusual activity
- Consider using a separate wallet with limited funds for this service
