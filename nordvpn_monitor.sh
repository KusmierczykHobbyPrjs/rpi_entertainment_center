#!/bin/bash

echo "The script monitors nordvpn status and when detects that it was disconnected or a server changed executes another script."

#######################################################################

# Lock file path
LOCK_FILE="/tmp/nordvpn_monitor.lock"

# Check if the lock file exists
if [ -f "$LOCK_FILE" ]; then
    echo "Another instance of the script is already running."
    exit
else
    # Create a lock file
    touch "$LOCK_FILE"
fi

# Ensure that the lock file is removed when the script exits
trap "rm -f $LOCK_FILE" EXIT

#######################################################################


# Path to the scripts you want to execute on change
SCRIPT_WHEN_CONNECTED="speech_en.sh"
SCRIPT_WHEN_DISCONNECTED="aplay ~/sounds/beep-10.wav"

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

    if [[ "$country" != "$previous_country" ]] || [[ "$city" != "$previous_city" ]]; then
        if [[ "$country" == "" ]] || [[ "$city" == "" ]]; then
            echo "VPN is disconnected from $previous_country."
            bash "$SCRIPT_WHEN_DISCONNECTED" "VPN got disconnected."
        else
            echo "VPN server has changed to $country, $city"
            # Execute another script with country and city as arguments
            bash "$SCRIPT_WHEN_CONNECTED" "VPN has changed to $country, $city"
        fi
        # Update previous values
        previous_country=$country
        previous_city=$city
    fi

    # Check every x seconds
    sleep 1
done
