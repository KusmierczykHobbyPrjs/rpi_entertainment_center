# SmartTV (+much more) that does not watch you
Scripts, links and instructions of how to set up a multi-purpose entertainemnt center on RaspberryPI (tested on 3b) using RaspbianOS with Kodi (multimedia server), RetroPie (retro gaming) and a standard Desktop.

## Overview

The following functionalities are covered:
 * three environments (Kodi, EmulationStation (RetroPie), LXDM (Desktop)) at the same device
 * UI watchdog
 * support for external buttons (GPIO): also for tuning on and off the device
 * for Kodi:
   - remote control (e.g. from smarthpone) using Kore
   - internet tv and radios via IPTV
   - streaming from YouTube, iPlayer (BBC), Netflix, Disney, Finnish Yle, Polish TVP VOD, Polsat etc.
 * for LXDM (Desktop):
   - remote control (e.g. from smarthpone) for LXDE using KDE-Connect
   - KDE-Connect command opening a url from clipboard in full-screen Chromium browser window
 * support for NordVPN (+VLAN via meshnet)
   - status monitoring and signaling by voice messages
   - control from Shell Command Launcher add-on
   - control by a physical button
 * voice messages using (free) Google services
 * port forwarding from LAN devices to make them available globally e.g. through NordVPN Meshnet
 * home http server visible from anywhere in the world (NoIP + Apache2)


## Installation
1. Setup Raspbian on your Raspberry (tested with Pi 3B).
2. Download and unpack this repostiory into your main folder.
3. Install all the addittional packages needed to run the scripts (see below all the lines starting with `sudo apt-get`).
4. Configure [config.sh](config.sh) and edit out things you don't need from [autostart.sh](autostart.sh).
5. Add `bash autostart.sh &` at the end of the `.bashrc` in your home directory, so the scripts are started automatically.
6. Run `sudo raspi-config` and change setting in 'System Options' -> 'Boot / Auto Login' to 'Console Autologin', so the system does not start GUI and UI (run by [autostart.sh](autostart.sh)) will be started.


## [Kodi](https://kodi.tv/)

Requirements:
```
sudo apt-get install kod kodi-inputstream-adaptive kodi-inputstream-rtmp  # basic + streaming
sudo apt-get install kodi-peripheral-joystick  # joystick control
sudo apt-get install kodi-eventclients-kodi-send  # command-line control
```


## [Kodi: IP TV](https://kodi.tv/addons/omega/pvr.iptvsimple/)

Install and enable (in UI) `PVR IPTV Simple Client` add-on:
```
sudo apt-get install kodi-pvr-iptvsimple
```

 - [a sample playlist with Polish radio stations and a few TV channels](iptvsimple_playlist_pl.m3u)

Online lists with IPTV channels:
 - [fmstream.org](https://fmstream.org/index.php) - find a station you want and add the entry to the m3u file e.g. [iptvsimple_playlist_pl.m3u](iptvsimple_playlist_pl.m3u) 
 - (for Polish): [http://iptv-org.github.io/iptv/languages/pol.m3u](http://iptv-org.github.io/iptv/languages/pol.m3u)
 - (for Polish): [https://github.com/iptv-org/iptv/blob/master/streams/pl.m3u](https://github.com/iptv-org/iptv/blob/master/streams/pl.m3u) -> [RAW file](https://raw.githubusercontent.com/iptv-org/iptv/refs/heads/master/streams/pl.m3u)


### Tips & Tricks

Set in the add-on configuration (in Advanced settings) the following User Agent: `Mozilla/5.0` or `VLC`.

## Kodi: Streaming
@TODO



## Multiple UIs (Kodi / EmulationStation / default graphical environment) + watchdog

The below scripts are useful for systems that serve multiple purposes (media center, gaming station, and general computing) by managing and rotating the active UI, enhancing the user experience by simplifying the transition between different uses of the system. 

These scripts are designed for managing and rotating between different User Interfaces (UIs) on a Linux system, specifically targeting environments where Kodi (a media center software), EmulationStation (a graphical front-end for emulators), and Xorg (the X Window System) are used. They implement functionality to ensure these UIs are not running simultaneously, prevent rapid execution, and facilitate the rotation between these applications to maintain system stability.

 - [ui_rotate.sh](ui_rotate.sh) - automates the rotation between UIs (Kodi, EmulationStation, and Xorg defined in [config.sh](config.sh)), starting each UI in sequence to ensure that the user can switch between different interfaces without manual intervention. In particular, when a UI is closed or killed by [stop_current_ui.sh](stop_current_ui.sh) the next UI is automatically started. The script is started at system logging from autostart.sh. 
 - [stop_current_ui.sh](stop_current_ui.sh) - stops the currently running UI. The script is executed by pressing a physical button (GPIO slope detection). Physical buttons are handled by [gpio_commands.sh](gpio_commands.sh) which is started at system logging from [autostart.sh](autostart.sh). Commands to monitor, start or stop UIs are loaded from [config.sh](config.sh). 


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



 
 
## Port forwarding (use Pi as a gateway)

 - [port_forwarding.sh](port_forwarding.sh) - This script forwards TCP traffic from Raspberry Pi ports to dedicated LAN servers or devices. For example, I use an [IP web cam](https://play.google.com/store/apps/details?id=com.pas.webcam&hl=pl&pli=1) installed on an old Android 4.0 device. I prefer not to pay for online streaming services or expose the webcam to public internet access. However, my Raspberry Pi I can connect via VLAN from anywhere in the world (and the old Android device I cannot). Therefore, I set up the Pi to forward traffic from port 8282 to the webcam at `192.168.1.20:8080`.

### Prerequisites 
 - `sudo apt-get install socat` 

  
## NordVPN

NordVPN is a VPN and VLAN (through meshnet). 
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


## Speech synthesis

The speech synthesis scripts are auxiliary and are used by other scripts to signal events.

 - [speech.sh](speech.sh) - reads text in a selected language using `mpg123` and Google Translate web api. Example `bash speech.sh en Welcome home!`
 - [speech_text_splitter.py](speech_text_splitter.py) - auxiliary script to efficiently manage long text inputs by splitting them into segments that do not exceed a specified maximum length
 - [speech_en.sh](speech_en.sh) - wrapper for English 
 - [speech_en.sh](speech_en.sh) - wrapper for Polish 
 
### Prerequisites 
 - `sudo apt-get install mpg123`
 
## Configuration
 
  - [config.sh](config.sh) - contains environment variables used by other scripts. For example, `VOLUME` used by speech synthesis.
  
## Autostart

@TODO

## Locally-hosted WebServer with global access via NoIP

**No-IP** is a Dynamic DNS (DDNS) service that allows a device with a changing public IP address—such as a home internet connection or a Raspberry Pi behind a consumer ISP—to be reachable through a stable, human-readable hostname. No-IP maps this hostname to the device's current public IP and updates the mapping automatically whenever the IP changes. To use the service, create a free or paid account on the No-IP website, add a hostname (for example, `example.ddns.net`) under the DNS/Hostnames section, and associate it with your current IP address. The No-IP Dynamic Update Client installed on the Raspberry Pi then authenticates with your account and periodically reports the device's public IP, ensuring the hostname always resolves to the correct address.

To make services on the Raspberry Pi accessible from the internet, router port forwarding is also required: this involves configuring your home router to forward incoming connections on a specific external port (e.g., TCP port 22 or 80) to the Raspberry Pi's internal IP address and corresponding internal port. Without port forwarding, external requests reaching your public IP and No-IP hostname will be blocked at the router and never reach the device.

There might be an option to configure No-IP on your router directly. If not follow the below instructions.


### Apache HTTP server with PHP

The following instructions setup an Apache server on your Raspberry:
```
sudo apt install apache2 -y
sudo apt install php -y
sudo apt install php libapache2-mod-php -y
sudo systemctl restart apache2
echo "<?php phpinfo(); ?>" | sudo tee /var/www/html/info.php
```


### NoIP installation for Rasbian

[NoIP installation instructions](https://my.noip.com/dynamic-dns/duc) do not work for Raspbian.
Instead follow the standard, reliable procedure to install the **No-IP Dynamic Update Client (DUC)** on a Raspberry Pi running Raspberry Pi OS or another Debian-based distribution:

1. Update the system and install build tools
   Run:

```
sudo apt update
sudo apt install -y gcc make
```

2. Download the No-IP Dynamic Update Client
   Obtain the latest Linux source package from **No-IP**:

```
cd /usr/local/src
sudo wget https://www.noip.com/client/linux/noip-duc-linux.tar.gz
```

3. Extract the archive

```
sudo tar xzf noip-duc-linux.tar.gz
cd noip-*
```

4. Compile and install

```
sudo make
sudo make install
```

During installation, you will be prompted for:

* No-IP account email
* No-IP account password
* Hostname to update
* Update interval (default is acceptable)

5. Test the client manually

```
sudo noip2
```

Verify that the client starts without errors.

6. Enable automatic startup (systemd)
   Create a service file:

```
sudo nano /etc/systemd/system/noip2.service
```

Insert:

```
[Unit]
Description=No-IP Dynamic DNS Update Client
After=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/bin/noip2
ExecStop=/usr/local/bin/noip2 -K
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```
sudo systemctl daemon-reload
sudo systemctl enable noip2
sudo systemctl start noip2
```

7. Verify status

```
systemctl status noip2
```

Notes:
* Configuration is stored in `/usr/local/etc/no-ip2.conf`.
* To reconfigure, stop the service and run `sudo noip2 -C`.
* This method is architecture-independent and works on all Raspberry Pi models.


### HTTPS for an Apache server
To enable HTTPS for an Apache server on Raspberry Pi OS (Raspbian), the standard and recommended approach is to use TLS certificates from **Let's Encrypt** via **Certbot**.

First, prerequisites must be satisfied. Your Raspberry Pi must be reachable from the public internet on TCP ports 80 and 443, your No-IP hostname must resolve to your public IP, and your router must forward ports 80 and 443 to the Raspberry Pi. Apache must already be installed and serving HTTP correctly.

Install Apache and Certbot:

```
sudo apt update
sudo apt install -y apache2 certbot python3-certbot-apache
```

Ensure Apache is running:

```
sudo systemctl enable apache2
sudo systemctl start apache2
```

Request and install an HTTPS certificate for your No-IP hostname:

```
sudo certbot --apache
```

During the process, select your hostname, agree to the terms, and choose the option to redirect HTTP to HTTPS. Certbot will automatically configure Apache virtual hosts and enable SSL.

Verify HTTPS:
Open `https://your-hostname.ddns.net` in a browser and confirm the certificate is valid.

Enable automatic certificate renewal:

```
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

You can test renewal with:

```
sudo certbot renew --dry-run
```

Notes:

* Certificates are stored under `/etc/letsencrypt/`.
* If port 80 is blocked by your ISP, HTTP-based validation will fail; in that case, DNS-based validation must be used instead.
* Apache SSL configuration files are typically created as `*-le-ssl.conf` under `/etc/apache2/sites-enabled/`.

This configuration provides industry-standard HTTPS with automatic renewal and minimal manual maintenance.

### Safe server

To reduce the risk of compromise on a Raspberry Pi running Apache, you must address **system updates**, **service exposure**, and **basic hardening**. The steps below are sufficient for a home-exposed server.

1. Keep the operating system fully updated
   Run regularly:

```
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove --purge -y
```

Enable unattended security updates:

```
sudo apt install unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades
```

This ensures critical vulnerabilities are patched automatically.

2. Minimize exposed network surface
   Only expose ports that are strictly required.

Check listening services:

```
sudo ss -tlnp
```

If you only need HTTPS:

* Keep **443** open
* Close **80** externally (or redirect internally)
* Close everything else at the router

Do not expose SSH unless necessary.

3. Harden Apache configuration
   Disable directory listing:

```
sudo a2dismod autoindex
sudo systemctl reload apache2
```

Hide version information. Edit:

```
sudo nano /etc/apache2/conf-available/security.conf
```

Ensure:

```
ServerTokens Prod
ServerSignature Off
```

Disable unused modules:

```
sudo apachectl -M
sudo a2dismod <module>
```


