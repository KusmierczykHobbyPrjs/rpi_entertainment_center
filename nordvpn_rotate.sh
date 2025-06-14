#!/bin/bash

# NordVPN disconnecting from the current server and connecting to the next one on a list of countries

########################################################################################################
# Makes sure the code is not executed too often

# Path to the file where the last run timestamp is stored
timestamp_file="/tmp/nordvpn_rotate.timestamp"

# Define a function to ensure a minimum delay between script executions
ensure_delay() {
    local delay_seconds=$1

    if [ -f "$timestamp_file" ]; then
        local last_run=$(cat "$timestamp_file")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_run))

        if [ "$time_diff" -lt "$delay_seconds" ]; then
            exit
        fi
    fi

    # Update the timestamp file with the current time
    date +%s > "$timestamp_file"
}

ensure_delay 5
########################################################################################################

echo "NordVPN connecting to the next server on list of countries or disconnecting if country is xx."

# Environment variable holding the list of countries as lowercase codes
# Format: "us uk de fr", xx stands for disconnected
COUNTRIES_LIST="${NORDVPN_COUNTRIES:-xx us de fr}"

# Convert the countries list into an array
countries=($COUNTRIES_LIST)


# Function to extract the current country code from the NordVPN hostname
get_current_country_code() {
    # Extract the country code from the hostname (e.g., se153.nordvpn.com -> se)
    current_hostname=$(nordvpn status | grep -oP 'Hostname: \K.*')
    if [[ "$current_hostname" =~ ^([a-z]{2}) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "xx"
    fi
}

# Determine the next country to connect to based on the current country code
determine_next_country() {
    current_country_code=$(get_current_country_code)
    found_current=false

    for country_code in "${countries[@]}"; do
       if $found_current; then
           echo $country_code
           return
       fi
       if [[ "$country_code" == "$current_country_code" ]]; then
           found_current=true
       fi
    done

    # If the current country is the last in the list or not found, start with the first country
    echo ${countries[0]}
}

# Disconnect from the current server
# nordvpn disconnect

# Determine the next country to connect to and connect
next_country=$(determine_next_country)


if [[ "$next_country" == "xx" ]]; then
    echo "NordVPN disconnecting (country code=$next_country)..."
    bash signal_action.sh &
    nordvpn disconnect              # sentinel: just drop the tunnel

else
    echo "NordVPN connecting to $next_country..."
    bash signal_action.sh &
    nordvpn connect "$next_country" # connect to the requested country

fi






