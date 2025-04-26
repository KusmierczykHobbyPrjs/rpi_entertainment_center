#!/bin/bash

echo "Opens a url from clipboard in chromium on a full screen" 
echo " - prerequisite: sudo apt-get install xclip"

bash signal_action.sh &

bash chromium_kill.sh

# Get URL from clipboard
URL=$(xclip -selection clipboard -o)

# Open Chromium in fullscreen with the URL
chromium-browser --start-fullscreen "$URL"


