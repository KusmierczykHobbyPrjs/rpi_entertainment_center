#!/bin/bash

# The script keeps rotating UI apps in a loop

########################################################################################################
# Makes sure the code is not executed too often

# Path to the file where the last run timestamp is stored
timestamp_file="/tmp/ui_rotate.timestamp"

# Define a function to ensure a minimum delay between script executions
ensure_delay() {
    local delay_seconds=$1

    if [ -f "$timestamp_file" ]; then
        local last_run=$(cat "$timestamp_file")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_run))

        if [ "$time_diff" -lt "$delay_seconds" ]; then
            exit
        fi
    fi

    # Update the timestamp file with the current time
    date +%s > "$timestamp_file"
}

########################################################################################################

ALREADY_RUNNING=`ps -A | grep -v grep | grep -E "emulation|kodi|Xorg|autostart"`
if [ -z "$ALREADY_RUNNING" ] ; then
        # Startup sound
        #omxplayer -o local win95startup.mp3 &
   
        # Run in loop
        while :
        do
                echo "STARTING KODI...";
                #bash speech_en.sh STARTING KODI... &;
                kodi;
                ensure_delay 5

                echo "STARTING EMULATION STATION...";
                #bash speech_en.sh STARTING EMULATION STATION... &;
                emulationstation;
                ensure_delay 5

                echo "STARTING XORG...";
                ##bash speech_en.sh STARTING XORG... &;
                startx;        
                ensure_delay 5  
        done

fi


