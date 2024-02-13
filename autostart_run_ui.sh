#!/bin/bash

# Keeps running apps in a loop

ALREADY_RUNNING=`ps -A | grep -v grep | grep -E "emulation|kodi|Xorg|autostart"`
if [ -z "$ALREADY_RUNNING" ] ; then
        # Startup sound
        #omxplayer -o local win95startup.mp3 &
   

        # Run in loop
        while :
        do
                echo "STARTING KODI...";
                #bash speech_pl.sh Uruchamiam kodi... &;
                kodi;
                #killall kodi kodi-bin kodi-standalone kodi.bin_v7 > /dev/null 2>&1;      

                echo "STARTING EMULATION STATION...";
                #bash speech_pl.sh Uruchamiam emulatory... &;
                emulationstation;
                #killall emulationstation emulationstatio > /dev/null 2>&1;


                #echo "STARTING XORG...";
                ##bash speech_pl.sh Uruchamiam pulpit... &;
                startx;        
                ##killall Xorg;  
        done

fi




#if [ -e /dev/input/js1 ]; then 

#                V=`ps -A | grep emulationstation`
#                if [ -z "$V" ] ; then
#                    echo "STARTING IN EMULATION STATION MODE";
#                    #echo "EMULATION STATION" > /tmp/start.log;
#                    emulationstation; 
#                fi

#else 
#        X=`tvservice -n 2>&1 | grep "No device" | wc -l`; 
#        if [ "$X" -eq "0" ]; then 

#                V=`ps -A | grep kodi`
#                if [ -z "$V" ] ; then
#                    echo "STARTING KODI";
#                    kodi-standalone; 
#                fi

#        else 
#                echo "Doing nothing";
#                #echo "JUST TV SERVER" > /tmp/start.log; 
#        fi;
#fi;


    # clean up -> update noip -> kill noip client -> start vpn 
    #sudo killall noip2
    #nordvpn disconnect 
    #sudo /usr/local/bin/noip2
    #(sleep 3; sudo killall noip2; nordvpn connect pl) & 
    #nordvpn connect pl 
