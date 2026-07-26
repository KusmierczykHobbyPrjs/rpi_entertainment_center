#!/bin/bash

echo "Fix screen resolution to a predefined value"
echo "To make it start automatically:"
echo " - edit: sudo nano /etc/xdg/lxsession/LXDE-pi/autostart"
echo " - add line: @/home/pi/lxde_set_resolution.sh"

xrandr --output HDMI-1 --mode 1360x768 --rate 60
