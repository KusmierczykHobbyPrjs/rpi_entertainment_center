#!/bin/bash

echo "Opens a url from clipboard in chromium on a full screen" 
echo " - prerequisite: sudo apt-get install xclip"
echo " use case: -> copy a URL address on your phone/laptop"
echo "           -> send the clipboard content to RPi via KDE-Connect"
echo "           -> execute the command from KDE-Connect"

bash signal_action.sh &

bash chromium_kill.sh

# Get URL from clipboard
URL=$(xclip -selection clipboard -o)

# Open Chromium in fullscreen with the URL
chromium-browser --start-fullscreen "$URL"


