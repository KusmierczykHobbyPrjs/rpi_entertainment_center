# rpi_entertainment_center
Scripts, links and instructions of how to set up a home entertainemnt center on RaspberryPI(3b+) using RaspbianOS with Kodi (multimedia server) and RetroPie (retro gaming).

The following functionalities are covered:
 * three environments (Kodi, EmulationStation (RetroPie), LXDM (Desktop)) at the same device
 * UI watchdog
 * support for external buttons (GPIO): also for tuning on and off the device
 * support for NordVPN
   - status monitoring and signaling by voice messages
   - control from Shell Command Launcher add-on
   - control by a physical button
 * for Kodi:
   - remote control (e.g. from smarthpone) using Kore
   - internet tv and radios via IPTV
   - streaming from YouTube, iPlayer (BBC), Netflix, Disney, Finnish Yle, Polish TVP VOD, Polsat etc.
 * for LXDM (Desktop):
   - remote control (e.g. from smarthpone) for LXDE using KDE-Connect
   - KDE-Connect command opening a url from clipboard in full-screen Chromium browser window
 * voice messages using (free) Google services
 * port forwarding from LAN devices to make them available globally e.g. through NordVPN Meshnet

## Kodi

Requirements:
```
sudo apt-get install kod kodi-inputstream-adaptive kodi-inputstream-rtmp  # basic + streaming
sudo apt-get install kodi-peripheral-joystick  # joystick control
sudo apt-get install kodi-eventclients-kodi-send  # command-line control
```

## Kodi: IP TV

Install and enable (in UI) `PVR IPTV Simple Client` add-on:
```
sudo apt-get install kodi-pvr-iptvsimple
```

 - [sample playlist with Polish radio stations and a few TV channels](iptvsimple_playlist_pl.m3u)

## Switching UIs (Kodi / EmulationStation / default graphical environment) + watchdog

 - [ui_rotate.sh](ui_rotate.sh) - automates the rotation between UIs (Kodi, EmulationStation, and Xorg defined in [config.sh](config.sh)), starting each UI in sequence to ensure that the user can switch between different interfaces without manual intervention. In particular, when a UI is closed or killed by [stop_current_ui.sh](stop_current_ui.sh) the next UI is automatically started. The script is started at system logging from autostart.sh. 
 - [stop_current_ui.sh](stop_current_ui.sh) - stops the currently running UI. The script is executed by pressing a physical button (GPIO slope detection). Physical buttons are handled by [gpio_commands.sh](gpio_commands.sh) which is started at system logging from [autostart.sh](autostart.sh). Commands to monitor, start or stop UIs are loaded from [config.sh](config.sh). 

### Why
These scripts are useful for systems that serve multiple purposes (media center, gaming station, and general computing) by managing and rotating the active UI, enhancing the user experience by simplifying the transition between different uses of the system.

### What
These scripts are designed for managing and rotating between different User Interfaces (UIs) on a Linux system, specifically targeting environments where Kodi (a media center software), EmulationStation (a graphical front-end for emulators), and Xorg (the X Window System) are used. They implement functionality to ensure these UIs are not running simultaneously, prevent rapid execution, and facilitate the rotation between these applications to maintain system stability and user experience.


## Remote Control of LXDE Desktop Using KDE Connect

KDE Connect is a framework for integrating phones and desktops, using DBus, TCP/IP, and encryption. It enables control of LXDE (e.g., input, notifications, file transfer) from a mobile device via KDE Connect.

Requirements:
```
sudo apt install kdeconnect
sudo apt install indicator-kdeconnect  # optional tray applet
sudo apt install xclip  # reading from clipboard
```

Pairing the device:
 - Open the KDE Connect app on your phone or computer.
 - Detect the Raspberry Pi device.
 - Send and accept the pairing request.

### Use Case: Watching a Movie from a Website-Based Player

LXDE, by default, runs using the maximum possible resolution. It can be reduced by editing `/boot/config.txt`. However, to avoid global changes, [lxde_set_resolution.sh](lxde_set_resolution.sh) allows fixing the screen resolution to a predefined value only for the desktop (edit the script directly).

To make it start automatically:
 - Edit: `sudo nano /etc/xdg/lxsession/LXDE-pi/autostart`
 - Add the line: `@/home/pi/lxde_set_resolution.sh`

A website can be conveniently opened from a phone by adding a user-defined command to KDE Connect: [clipboard2chromium.sh](clipboard2chromium.sh) opens a URL from the clipboard in Chromium in full screen. After the command is added, to open a URL: (1) copy it to the clipboard on your phone; (2) synchronize clipboards in KDE Connect; (3) execute the command.


## Speech synthesis

 - [speech.sh](speech.sh) - reads text in a selected language using `mpg123` and Google Translate web api. Example `bash speech.sh en Welcome home!`
 - [speech_text_splitter.py](speech_text_splitter.py) - auxiliary script to efficiently manage long text inputs by splitting them into segments that do not exceed a specified maximum length
 - [speech_en.sh](speech_en.sh) - wrapper for English 
 - [speech_en.sh](speech_en.sh) - wrapper for Polish 
 
### Prerequisites 
 - `sudo apt-get install mpg123`
 
 
## Port forwarding (use Pi as a gateway)

 - [port_forwarding.sh](port_forwarding.sh) - This script forwards TCP traffic from Raspberry Pi ports to dedicated LAN servers or devices. For example, I use an [IP web cam](https://play.google.com/store/apps/details?id=com.pas.webcam&hl=pl&pli=1) installed on an old Android 4.0 device. I prefer not to pay for online streaming services or expose the webcam to public internet access. However, my Raspberry Pi I can connect via VLAN from anywhere in the world (and the old Android device I cannot). Therefore, I set up the Pi to forward traffic from port 8282 to the webcam at `192.168.1.20:8080`.

### Prerequisites 
 - `sudo apt-get install socat` 
 
 
## Configuration
 
  - [config.sh](config.sh) - contains environment variables used by other scripts. For example, `VOLUME` used by speech synthesis.
  
  
## NordVPN

It can be installed by following the instructions from [https://nordvpn.com/download/raspberry-pi/](https://nordvpn.com/):
```
  echo "Installing NordVPN"
  sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
  echo "Whitelisting local subnet"
  nordvpn whitelist add subnet 192.168.1.0/24  ## make sure your local network uses this
```

[nordvpn_autostart.sh](nordvpn_autostart.sh) and [nordvpn_monitor.sh](nordvpn_monitor.sh) are scripts responsible for respectively setting up and monitoring the VPN. They are started by [autostart.sh](autostart.sh). Configuration is read from [config.sh](config.sh).
[nordvpn_rotate.sh](nordvpn_rotate.sh) (run, e.g., by pressing a GPIO button) switches the VPN state to the next country from the list of countries.

There is no plugin compatible with Kodi 19, but apart from using GPIO commands, its behavior can be controlled via `ShellScriptLauncher`. Download [the repo](https://github.com/wastis/LinuxAddonRepo), install the add-on, and configure it to read commands from [~/shell_command_launcher.menu](shell_command_launcher.menu). To make the add-on easily accessible, add it to 'Favorites' (right click -> Add to Favorites).

