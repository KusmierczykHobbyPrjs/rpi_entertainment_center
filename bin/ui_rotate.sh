#!/bin/bash

# Continuously monitors UIs and ensures one is always running, ensuring single instance.
# Complementary to stop_current_ui.sh script

# Find the directory where the script is located
script_dir="$(dirname "$0")"
# Source the config.sh from the same directory
source "$script_dir/config.sh"

start_script_path="/tmp/start_next_ui.sh"

########################################################################################################

lockfile="/tmp/ui_monitor.lock"

# Create a lock file to ensure only one instance runs
if [ -f "$lockfile" ]; then
    #echo "Another instance of the script is already running."
    exit
else
    touch "$lockfile"
    trap "rm -f $lockfile; exit" INT TERM EXIT  # Ensures lock file is removed on script exit
fi

########################################################################################################

# Function to check if any UI is currently running
check_uis_running() {
    for ui in "${uis[@]}"; do
        if ps -A | grep -qw "$ui"; then
            return 0  # If any UI is found running, return 0
        fi
    done
    return 1  # No UIs are running
}

# Main loop to monitor UIs
while true; do
    check_uis_running
    if [ $? -ne 0 ]; then  # No UI is running
        echo "No UI is currently running."
        #bash speech_en.sh "No UI running."
        
        if [ -f "$start_script_path" ]; then
            echo "Starting next UI using script $start_script_path:"
            cat "$start_script_path"
            #bash speech_en.sh "Starting next UI."
            bash "$start_script_path"
            sleep 10  # let it start
            
        else
            echo "No UI is yet selected. Starting default UI with command=$default_ui_command."
            #bash speech_en.sh "Start script not found. Starting default UI."
            eval "$default_ui_command"
            sleep 10  # let it start
                        
        fi
        
    fi
    
    sleep 1  # Delay for X seconds before checking again
done

