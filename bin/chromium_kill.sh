#!/bin/bash

echo "The script kills all instances of chromium and removes all tabs (sessions)"

# More precise check for Chromium browser processes
# This ensures we only match actual Chromium browser processes, not just any process with "chromium" in the name
if ps aux | grep -E "[c]hromium-browser|[c]hromium" | grep -v grep > /dev/null
then
    echo "Chromium is running. Killing all instances..."
    
    # Kill all Chromium browser processes
    pkill -f "chromium-browser"
    pkill -f "/usr/lib/chromium-browser/chromium-browser"
    
    # Check if processes are still running after a short time
    for i in {1..5}
    do
        if ! ps aux | grep -E "[c]hromium-browser|[c]hromium" | grep -v grep > /dev/null; then
            break  # Exit loop if chromium is no longer running
        fi
        
        # If we reached attempt #3, use SIGKILL
        if [ $i -eq 3 ]; then
            echo "Using force kill..."
            pkill -9 -f "chromium-browser"
            pkill -9 -f "/usr/lib/chromium-browser/chromium-browser"
        fi
        
        # Very brief pause between checks
        sleep 0.1
    done
    
    # Remove session files to prevent tabs from reopening
    echo "Clearing Chromium session data..."
    rm -f ~/.config/chromium/Default/Sessions/* 2>/dev/null
    rm -f ~/.config/chromium/Default/Session* 2>/dev/null
    rm -f ~/.config/chromium/Default/Preferences 2>/dev/null
    rm -f ~/.config/chromium/Default/Current* 2>/dev/null
    
    echo "Chromium has been terminated and session data cleared."
else
    echo "Chromium is not running."
fi
