#!/bin/bash

echo "The following bash script will disconnect from the current NordVPN server and connect to the next one on a list of countries."

# Environment variable holding the list of countries as lowercase codes
# Format: "us uk de fr"
COUNTRIES_LIST="${NORDVPN_COUNTRIES:-us de fr}"

# Convert the countries list into an array
countries=($COUNTRIES_LIST)

# Function to extract the current country code from the NordVPN hostname
get_current_country_code() {
    # Extract the country code from the hostname (e.g., se153.nordvpn.com -> se)
    current_hostname=$(nordvpn status | grep -oP 'Hostname: \K.*')
    [[ "$current_hostname" =~ ([a-z]{2}) ]]
    echo "${BASH_REMATCH[1]}"
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
nordvpn connect $next_country

echo "Connecting to $next_country..."

