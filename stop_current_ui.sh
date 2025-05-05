#!/bin/bash

# Generic script to rotate between different UIs and create a script to start the next UI.
# When executed kills the current UI. Complementary to ui_rotate.sh script
# If an argument is passed, it rotates to the PREVIOUS UI instead of the next.

bash signal_action.sh &

# Find the directory where the script is located
script_dir="$(dirname "$0")"
# Source the config.sh from the same directory
source "$script_dir/config.sh"

start_script_path="/tmp/start_next_ui.sh"

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

# Find which UI is running and determine the next UI to start
current_index=-1
for i in "${!uis[@]}"; do
    if ps -A | grep -qw "${uis[$i]}"; then
        current_index=$i
        break
    fi
done

if [ "$current_index" -ne -1 ]; then
    # Close the current UI
    echo "Clossing ${uis[$current_index]} with command=${ui_commands[$current_index]}"
    eval "${ui_commands[$current_index]}"

    # Calculate next or previous UI index based on argument presence
    if [ $# -gt 0 ]; then
        # Argument passed: Calculate PREVIOUS index
        # Formula handles wrap-around from index 0 to the last index
        next_index=$(( (current_index - 1 + ${#uis[@]}) % ${#uis[@]} ))
    else
        # No argument passed: Calculate NEXT index (original behavior)
        next_index=$(((current_index + 1) % ${#uis[@]}))
    fi

    # Create script to start the next/previous UI
    echo "#!/bin/bash" > "$start_script_path"
    echo "${ui_start_commands[$next_index]}" >> "$start_script_path"
    chmod +x "$start_script_path"
    # Kept original message for minimal change, although 'next' might now mean 'previous'
    echo "Script to start the next UI (${uis[$next_index]}) has been created at $start_script_path"

else
    echo "NO RUNNING INTERFACE FOUND!"

fi
