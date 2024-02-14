
#!/bin/bash

# Kills the current UI
# Complementary to ui_rotate.sh script 

########################################################################################################
# Makes sure the code is not executed too often

# Path to the file where the last run timestamp is stored
timestamp_file="/tmp/stop_current_ui.timestamp"

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

ensure_delay 5
########################################################################################################

KODI_RUNNING_FLAG=`ps -A | grep -v grep | grep kodi | grep -v emu | grep -v Xorg`
XORG_RUNNING_FLAG=`ps -A | grep -v grep | grep Xorg | grep -v emu | grep -v kodi`
EMU_RUNNING_FLAG=`ps -A | grep -v grep | grep emu | grep -v Xorg | grep -v kodi`


if [ ! -z "$KODI_RUNNING_FLAG" ] ; then
        echo "CLOSING KODI"
        kodi-send --action="Quit"
        #killall kodi kodi-standalone kodi.bin_v7 > /dev/null 2>&1;

        #echo "STARTING EMULATION STATION";
        #emulationstation & 
        #emulationstation --force-kiosk & 

elif [ ! -z "$EMU_RUNNING_FLAG" ] ; then
        echo "CLOSING EMULATIONSTATION";
        pkill emulationstatio > /dev/null 2>&1    
        #killall emulationstation emulationstatio > /dev/null 2>&1;
             
        #echo "STARTING KODI";
        #kodi-standalon   

elif [ ! -z "$XORG_RUNNING_FLAG" ] ; then
        echo "CLOSING XORG"; 
        killall Xorg > /dev/null 2>&1;

else
        echo "NO RUNNING INTERFACE FOUND!";

fi




