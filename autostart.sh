#!/bin/bash

## EXECUTES ALL AUTOSTART SCRIPTS

source config.sh
bash autostart_run_ui.sh & bash nordvpn_autostart.sh & bash nordvpn_monitor.sh & bash port_forwarding.sh & bash gpio_commands.sh;

