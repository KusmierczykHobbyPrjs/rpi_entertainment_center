#!/bin/bash

## EXECUTES ALL AUTOSTART SCRIPTS

# Find the directory where the script is located
script_dir="$(dirname "$0")"
# Source the config.sh from the same directory
source "$script_dir/config.sh"

bash ui_rotate.sh & bash nordvpn_autostart.sh & bash nordvpn_monitor.sh & bash port_forwarding.sh & bash gpio_commands.sh;

