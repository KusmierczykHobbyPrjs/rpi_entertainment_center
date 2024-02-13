#!/bin/bash

# Forwarding TCP traffic from RPi ports to dedicated LAN servers/devices
# Installation:
# > sudo apt-get install socat

# Forwards port=8282 => 192.168.1.20:8080
socat tcp-listen:8282,fork,reuseaddr tcp:192.168.1.20:8080 
