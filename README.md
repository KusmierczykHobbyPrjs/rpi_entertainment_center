# rpi_entertainment_center
Scripts, links and instructions of how to set up a home entertainemnt center on RaspberryPI(3b+) using Kodi and RetroPie


## Rotating UI between Kodi, EmulationStation and the default graphical environment

 - [ui_rotate.sh](ui_rotate.sh) - automates the rotation between Kodi, EmulationStation, and Xorg, starting each UI in sequence to ensure that the user can switch between different interfaces without manual intervention. In particular, when a UI is closed or killed by [stop_current_ui.sh](stop_current_ui.sh) the next UI is automatically started. The script is started at system logging from autostart.sh. 
 - [stop_current_ui.sh](stop_current_ui.sh) - stops the currently running UI application among Kodi, EmulationStation, or Xorg. The script is executed by pressing a physical button (GPIO slope detection). Physical buttons are handled by [gpio_commands.sh](gpio_commands.sh) which is started at system logging from autostart.sh. 

### Why
These scripts are useful for systems that serve multiple purposes (media center, gaming station, and general computing) by managing and rotating the active UI, enhancing the user experience by simplifying the transition between different uses of the system.

### What
These scripts are designed for managing and rotating between different User Interfaces (UIs) on a Linux system, specifically targeting environments where Kodi (a media center software), EmulationStation (a graphical front-end for emulators), and Xorg (the X Window System) are used. They implement functionality to ensure these UIs are not running simultaneously, prevent rapid execution, and facilitate the rotation between these applications to maintain system stability and user experience.


## Speech synthesis

 - [speech.sh](speech.sh) - reads text in a selected language using `mpg123` and Google Translate web api. Example `bash speech.sh en Welcome home!`
 - [speech_text_splitter.py] - auxiliary script to efficiently manage long text inputs by splitting them into segments that do not exceed a specified maximum length
 - [speech_en.sh](speech_en.sh) - wrapper for English 
 - [speech_en.sh](speech_en.sh) - wrapper for Polish 
 
### Prerequisites 
 - `sudo apt-get install mpg123`
 
 
## Port forwarding (use Pi as a gateway)

 - [port_forwarding.sh](port_forwarding.sh) - This script forwards TCP traffic from Raspberry Pi ports to dedicated LAN servers or devices. For example, I use an [IP web cam](https://play.google.com/store/apps/details?id=com.pas.webcam&hl=pl&pli=1) installed on an old Android 4.0 device. I prefer not to pay for online streaming services or expose the webcam to public internet access. However, my Raspberry Pi I can connect via VLAN from anywhere in the world (and the old Android device I cannot). Therefore, I set up the Pi to forward traffic from port 8282 to the webcam at `192.168.1.20:8080`.

### Prerequisites 
 - `sudo apt-get install socat` 
