#!/bin/bash


# UI configurations:
# Commands to start each UI
declare -a ui_start_commands=("kodi &" "emulationstation &" "startx &")
# Define the default UI start command
default_ui_command="kodi &"  
# Commands to stop each UI
declare -a ui_commands=("kodi-send --action=\"Quit\"" "pkill emulationstatio" "killall Xorg")
# UI processes names (as by `ps -A`); used to monitor if running
declare -a uis=("kodi" "emulationstatio" "Xorg")


## SPEECH VOLUME
export VOLUME=30

## ACTION SOUND
export ACTION_SOUND="signal_action.mp3"


## PUT HERE YOUR TOKENS & APP PASSWORDS
export NORDVPN_TOKEN="PUT-YOUR-TOKEN-HERE"
export NORDVPN_COUNTRIES="xx pl fi uk2431"  # xx means no vpn
