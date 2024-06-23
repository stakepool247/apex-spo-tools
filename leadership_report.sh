#!/bin/bash

# Define variables
CARDANO_CLI="$HOME/.local/bin/cardano-cli"
LATEST_BLOCK_API="http://10.128.0.6:3033/blocks/latest"
TESTNET_MAGIC="3311"
GENESIS_FILE="$HOME/cnode/config/genesis/shelley/genesis.json"
STAKE_POOL_ID="54b3s....."
VRF_SIGNING_KEY_FILE="$HOME/cnode/keys/xxx.vrf.skey"
BLOCKFROST_API="http://10.128.0.6:3033/blocks/slot"
YOUR_POOL_ID="pool12xxxxxxxxxxxxxxxxxxxxx..."
DEBUG=false  # Set to true to show API response output

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

echo "Fetching the latest block information to get the current epoch..."
# Fetch the latest block information to get the current epoch
latest_block_info=$(curl -s $LATEST_BLOCK_API)

# Extract the current epoch number
current_epoch=$(echo "$latest_block_info" | jq -r '.epoch')

# Define the output file based on the current epoch
LEADERSHIP_FILE="leadership-schedule-epoch-$current_epoch.json"

echo "Checking if the leadership schedule file for epoch $current_epoch already exists..."
# Check if the leadership schedule file already exists
if [ -f $LEADERSHIP_FILE ]; then
    echo "Leadership schedule file for epoch $current_epoch already exists: $LEADERSHIP_FILE"
else
    echo "Generating leadership schedule for epoch $current_epoch..."
    # Generate leadership schedule
    $CARDANO_CLI query leadership-schedule --testnet-magic $TESTNET_MAGIC \
      --genesis $GENESIS_FILE \
      --stake-pool-id $STAKE_POOL_ID \
      --vrf-signing-key-file $VRF_SIGNING_KEY_FILE --current --out-file $LEADERSHIP_FILE

    # Check if leadership schedule file is created
    if [ -f $LEADERSHIP_FILE ]; then
        echo "Leadership schedule file generated successfully: $LEADERSHIP_FILE"
    else
        echo "Failed to generate leadership schedule file."
        exit 1
    fi
fi

# Extract the current slot number
current_slot=$(echo "$latest_block_info" | jq -r '.slot')

echo "Current slot number: $current_slot"

# Parse JSON and check each slot status
block_number=0
jq -c '.[]' $LEADERSHIP_FILE | while read -r slot; do
    slotNumber=$(echo "$slot" | jq -r '.slotNumber')
    slotTime=$(echo "$slot" | jq -r '.slotTime')
    
    block_number=$((block_number + 1))
    
    if (( slotNumber > current_slot )); then
        echo -e "${BLUE}Block #$block_number is planned (slot nr: $slotNumber, time: $slotTime).${NC}"
        continue
    fi

    if [ "$DEBUG" = true ]; then
        echo "Checking status for slot number: $slotNumber at time: $slotTime"
    fi

    # Query Blockfrost API for the slot status
    response=$(curl -s "$BLOCKFROST_API/$slotNumber")
    
    if [ "$DEBUG" = true ]; then
        echo "API Response: $response"
    fi

    # Check if the response is empty or malformed
    if [ -z "$response" ] || [[ "$response" == *"error"* ]]; then
        echo -e "${RED}Block #$block_number error: Unable to fetch data for slot number $slotNumber${NC}"
        continue
    fi

    # Parse the response and print the status
    slot_leader=$(echo "$response" | jq -r '.slot_leader')
    block_height=$(echo "$response" | jq -r '.height')

    if [ "$slot_leader" == "null" ]; then
        echo -e "${RED}Block #$block_number error: Block for slot number $slotNumber has not been minted.${NC}"
    elif [ "$slot_leader" != "$YOUR_POOL_ID" ]; then
        echo -e "${YELLOW}Block #$block_number warning: Block for slot number $slotNumber was won by another pool ($slot_leader).${NC}"
    else
        echo -e "${GREEN}Block #$block_number minted successfully (slot nr: $slotNumber, Block nr: $block_height, time: $slotTime)${NC}"
    fi
done
