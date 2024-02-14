#!/bin/bash

## ESTABLISHES NORDVPN CONNECTION
## REQUIRES INTERNET TO BE ON (=SET WAIT FOR NETWORK AT BOOT IN RASPI-CONF)

STR=`nordvpn status`
SUB='Connected'
if [[ "$STR" == *"$SUB"* ]]; then 
  echo "";
else
  echo "NordVPN is not connected. Connecting...";

  nordvpn login --token $NORDVPN_TOKEN
  nordvpn set meshnet on;

  bash nordvpn_rotate.sh
fi
