# 45-kdeconnect — your phone as the desktop's remote

Kore covers Kodi and a gamepad covers RetroPie. KDE Connect is the missing
remote for the desktop: touchpad, keyboard, clipboard sync and custom
commands, over your own LAN with no cloud service in between.

```bash
./install.sh 45-kdeconnect
```

**Prerequisites:** `00-base`, `40-desktop`.

---

## What it installs

| Package | Why |
|---|---|
| `kdeconnect` | The daemon and the pairing machinery. |
| `xclip` | Reads the clipboard, so `clipboard2chromium.sh` can see what your phone sent. |
| `indicator-kdeconnect` | Optional tray applet. Not packaged on every release; pairing works without it. |

It also opens TCP and UDP ports **1714–1764** in `ufw` if the firewall is
active. Without those rules, pairing silently never completes — the app sees
the Pi, requests pairing, and nothing happens.

---

## Pairing

1. Install [KDE Connect](https://kdeconnect.kde.org/) on your phone (Android
   and iOS both have it; Android has more features).
2. Make sure the phone and the Pi are on the **same network** — not a guest
   VLAN, and not a network with client isolation enabled.
3. **Switch the Pi to the Desktop UI.** KDE Connect needs a running desktop
   session; it will not pair while Kodi is on screen.
4. Open the app. The Pi appears in the device list.
5. Tap it → **Request pairing**. Accept the notification on the Pi.

Once paired you get:

- **Remote input** — the phone screen becomes a touchpad, with a keyboard
- **Clipboard sync** — send text either way
- **Notifications** — the phone's notifications appear on the Pi
- **Media control** — play/pause/skip
- **File transfer** — send files to the Pi
- **Run command** — the interesting one

---

## The "open clipboard URL" command

This is what makes the desktop worth having on a TV.

**Add the command** (from the phone, once paired):

> KDE Connect app → (your Pi) → **Run command** → Add command
>
> - **Name:** `Open clipboard URL`
> - **Command:** `bash /home/pi/rpi_entertainment_center/bin/clipboard2chromium.sh`

Use the path the installer printed — it matches wherever you cloned the
repository.

**Then, to watch something:**

1. Copy the URL on your phone.
2. KDE Connect → **Send clipboard**.
3. KDE Connect → Run command → **Open clipboard URL**.

The Pi beeps to confirm, closes any existing Chromium, and opens the link
full-screen.

This is also how you watch **Netflix or Disney+ when their Kodi add-on is
broken** — send `https://www.netflix.com` and sign in with the on-screen
keyboard, or send a direct link to what you want. Chromium on Raspberry Pi OS
includes Widevine, so DRM playback works. See
[20-kodi-addons.md](20-kodi-addons.md#the-fallback-netflix-in-the-browser).

### What the script does

```bash
bash bin/clipboard2chromium.sh
```

1. Plays the confirmation beep (`signal_action.sh`).
2. Reads the clipboard with `xclip`.
3. **Verifies it is an `http(s)` URL** and refuses anything else — a clipboard
   containing arbitrary text should not become a search or a local file open.
4. Runs `chromium_kill.sh` to close any existing window and clear the session,
   so you do not accumulate tabs or get a "restore pages?" bar that no remote
   can dismiss.
5. Opens Chromium full-screen, with error dialogues and info bars suppressed.

### Other commands worth adding

| Name | Command |
|---|---|
| Switch UI | `bash <repo>/bin/stop_current_ui.sh` |
| Next VPN country | `bash <repo>/bin/nordvpn_rotate.sh` |
| VPN status | `bash <repo>/bin/nordvpn_status.sh` |
| Close browser | `bash <repo>/bin/chromium_kill.sh` |
| Shut down | `sudo shutdown now` |
| Health check | `bash <repo>/bin/doctor.sh` |

---

## Verify

```bash
which kdeconnect-cli xclip
kdeconnect-cli --list-devices
```

Test the clipboard path from a desktop session:

```bash
echo "https://example.com" | xclip -selection clipboard
DISPLAY=:0 bash bin/clipboard2chromium.sh
```

---

## Troubleshooting

**The Pi does not appear in the app**

- The Pi must be showing the **Desktop UI**. KDE Connect needs a session.
- Both devices on the same network, no client isolation, no guest VLAN.
- Open the firewall:

  ```bash
  sudo ufw allow 1714:1764/udp
  sudo ufw allow 1714:1764/tcp
  ```

- Restart the daemon from a desktop session:

  ```bash
  killall kdeconnectd
  /usr/lib/*/libexec/kdeconnectd &
  ```

**Pairing request never arrives**

Almost always the firewall. Check with `sudo ufw status`.

**Commands run but nothing appears on screen**

KDE Connect runs commands without a `DISPLAY`. The bundled scripts set
`DISPLAY=:0` themselves; if you add your own command, do the same:

```bash
DISPLAY=:0 your-command
```

**"Clipboard is empty"**

Send the clipboard from the phone *before* running the command — they are two
separate actions in the app. On Android, clipboard sync may also need
"Display over other apps" permission for the app to read the clipboard at all.

**"Clipboard does not contain an http(s) URL"**

Working as intended — the clipboard held something other than a link. Copy the
URL again and re-send.

**Chromium opens behind the desktop, or not full-screen**

Some window managers ignore `--start-fullscreen`. Press F11 once; Chromium
remembers.

**Pairing is lost after a reboot**

Pairing is stored per desktop session user in `~/.config/kdeconnect/`. If it
keeps resetting, check that directory is writable and not being cleared.
