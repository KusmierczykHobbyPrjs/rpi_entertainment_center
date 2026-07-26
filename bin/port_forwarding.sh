#!/bin/bash

# Forwarding TCP traffic from RPi ports to dedicated LAN servers/devices
# Installation:
# > sudo apt-get install socat

#######################################################################
# Makes sure the code is executed only once

# Lock file path
LOCK_FILE="/tmp/port_forwarding.lock"

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

# LIST OF FORWARDS:
# Forwards port=8282 => 192.168.1.20:8080
socat tcp-listen:8282,fork,reuseaddr tcp:192.168.1.20:8080 
