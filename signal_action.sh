#!/bin/bash

# Plays a sound at a volume using mpg123

# Check for volume environment variable, default to 100 if not set
VOLUME_LEVEL=${VOLUME:-100}

# Convert volume from percentage (0-100) to scale (0-32768)
VOLUME_SCALE=$((VOLUME_LEVEL * 32768 / 100))


mpg123 -q -b 100 -f $VOLUME_SCALE $ACTION_SOUND

sleep 3
