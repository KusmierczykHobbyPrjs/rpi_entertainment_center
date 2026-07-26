#!/bin/bash

## ESTABLISHES NORDVPN CONNECTION
## REQUIRES INTERNET TO BE ON (=SET WAIT FOR NETWORK AT BOOT IN RASPI-CONF)

# Environment variable holding the list of countries as lowercase codes
# Format: "us uk de fr", xx stands for disconnected
COUNTRIES_LIST="${NORDVPN_COUNTRIES:-xx us de fr}"

# Convert the countries list into an array
countries=($COUNTRIES_LIST)

# Check the first element in the countries array
if [[ "${countries[0]}" != "xx" ]]; then

    STR=`nordvpn status`
    SUB='Connected'
    if [[ "$STR" == *"$SUB"* ]]; then 
      echo "";
    else
      echo "NordVPN logging & setting mesnhet on..."
      nordvpn login --token $NORDVPN_TOKEN
      nordvpn set meshnet on;

      ## By default nordvpn is not connected
      echo "NordVPN is not connected...";
      bash nordvpn_rotate.sh
    fi
    
fi


