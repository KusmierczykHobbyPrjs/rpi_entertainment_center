# rpi_entertainment_center
Scripts, links and instructions of how to set up a home entertainemnt center on RaspberryPI(3b+) using Kodi and RetroPie

## Rotating UI between Kodi, EmulationStation and the default graphical environment

 - [ui_rotate.sh](ui_rotate.sh) - automates the rotation between Kodi, EmulationStation, and Xorg, starting each UI in sequence to ensure that the user can switch between different interfaces without manual intervention. The script is started at system logging from autostart.sh.
 - [stop_current_ui.sh](stop_current_ui.sh) - stops the currently running UI application among Kodi, EmulationStation, or Xorg. The script is executed by pressing a physical button (GPIO slope detection). Physical buttons are handled by [gpio_commands.sh](gpio_commands.sh) which is started at system logging from autostart.sh. 

### Why
These scripts are useful for systems that serve multiple purposes (media center, gaming station, and general computing) by managing and rotating the active UI, enhancing the user experience by simplifying the transition between different uses of the system.

### What
These scripts are designed for managing and rotating between different User Interfaces (UIs) on a Linux system, specifically targeting environments where Kodi (a media center software), EmulationStation (a graphical front-end for emulators), and Xorg (the X Window System) are used. They implement functionality to ensure these UIs are not running simultaneously, prevent rapid execution, and facilitate the rotation between these applications to maintain system stability and user experience.

