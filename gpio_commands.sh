#!/bin/bash

# Executes commands when buttons are pressed (always running in background)

ALREADY_RUNNING=`ps -Af | grep -v grep | grep button2command`
if [ -z "$ALREADY_RUNNING" ]; then
    # Add below commands to be executed when a GPIO pin slope is detected (e.g. button pressed)
    python3 gpio2command.py 3 "shutdown" "now" &    
    python3 gpio2command.py 4 "bash" "stop_current_ui.sh" &     
    python3 gpio2command.py 17 "bash" "nordvpn_rotate.sh" &   
    # python3 gpio2command.py 17 "kodi-send" "-a" "PlayerControl(Play)" &
    # python3 gpio2command.py 27 "kodi-send" "-a" "Action(VolumeUp)" &    
    # python3 gpio2command.py 22 "kodi-send" "-a" "Action(VolumeDown)" &
fi





