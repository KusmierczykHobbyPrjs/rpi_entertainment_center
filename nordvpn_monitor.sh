#!/bin/bash

# NordVPN status monitoring and detecting when it disconnected

#######################################################################
# Make sure only one instance is running.

# Lock file path
LOCK_FILE="/tmp/nordvpn_monitor.lock"

# Check if the lock file exists
if [ -f "$LOCK_FILE" ]; then
    # echo "Another instance of the script is already running."
    exit
else
    # Create a lock file
    touch "$LOCK_FILE"
fi

# Ensure that the lock file is removed when the script exits
trap "rm -f $LOCK_FILE" EXIT

#######################################################################

echo "NordVPN status monitoring and detecting when it disconnected."

# Path to the scripts you want to execute on change
SCRIPT_WHEN_CONNECTED="speech_en.sh"
SCRIPT_WHEN_DISCONNECTED="speech_en.sh"

# Initially set previous values to null
previous_country=""
previous_city=""

# Function to extract country and city from NordVPN status
extract_details() {
    country=$(nordvpn status | grep -i "Country" | awk -F ': ' '{print $2}')
    city=$(nordvpn status | grep -i "City" | awk -F ': ' '{print $2}')
}

while true; do
    # Extract current country and city
    extract_details

    if [[ "$country" != "$previous_country" ]] && [[ "$city" != "$previous_city" ]]; then
        if [[ "$country" == "" ]] || [[ "$city" == "" ]]; then
            echo "NordVPN is now disconnected from $previous_country."
            bash "$SCRIPT_WHEN_DISCONNECTED" "VPN got disconnected."
        else
            echo "NordVPN server has changed to $country, $city"
            # Execute another script with country and city as arguments
            bash "$SCRIPT_WHEN_CONNECTED" "VPN changed to $country, $city"
        fi
        # Update previous values
        previous_country=$country
        previous_city=$city
    fi

    # Check every x seconds
    sleep 1
done
