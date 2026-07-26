# 25-tvheadend — broadcast TV with a real tuner

**Only useful if you have TV tuner hardware.** For internet-streamed channels
use [15-kodi-iptv](15-kodi-iptv.md) instead.

```bash
./install.sh 25-tvheadend
```

**Prerequisites:** `00-base`, `10-kodi`, and a DVB tuner.

---

## Tvheadend vs. IPTV Simple

| | IPTV Simple (`15-kodi-iptv`) | Tvheadend (`25-tvheadend`) |
|---|---|---|
| Source | Internet streams | Aerial, satellite or cable |
| Hardware | None | A DVB tuner |
| Recording | No | Yes |
| Programme guide | Only if you supply XMLTV | Broadcast, automatic |
| Multiple clients | One | Several, from one tuner |
| Setup effort | Minutes | An hour, including a channel scan |

They coexist happily — run both and get internet radio alongside broadcast TV.

---

## What it installs

| Package | Purpose |
|---|---|
| `tvheadend` | The backend: talks to the tuner, scans, records, serves streams. |
| `kodi-pvr-tvheadend-hts` | The Kodi client that connects to it. |

**During `apt install` you are asked to create an administrator username and
password.** These are the credentials for the web interface — write them down.
The old notes for this project used `pi`/`pi`; pick something better if the Pi
is reachable from outside your LAN.

The installer enables and starts `tvheadend.service`.

---

## Configuration

Everything is done through the web interface, from any machine on your LAN:

```
http://<pi-ip>:9981
```

### 1. Find the tuner

> Configuration → DVB Inputs → **TV adapters**

Your tuner should be listed. Tick **Enabled**, then pick the network type
(DVB-T for terrestrial, DVB-S for satellite, DVB-C for cable).

If nothing is listed, see [troubleshooting](#troubleshooting) below.

### 2. Create a network

> Configuration → DVB Inputs → **Networks** → Add

Choose the type matching your tuner and select the **pre-defined muxes** entry
for your country and region. This tells the scanner which frequencies to try.

### 3. Scan

Assign the network to the adapter and start a scan. It takes several minutes
and finds *services* — the raw broadcast streams.

> Configuration → DVB Inputs → **Muxes** shows progress.

### 4. Map services to channels

> Configuration → DVB Inputs → **Services** → Map services → Map all

This turns the discovered services into named channels with numbers.

### 5. Connect Kodi

> Settings → Add-ons → My add-ons → PVR clients → **Tvheadend HTSP Client** →
> Configure

| Setting | Value |
|---|---|
| Hostname | `127.0.0.1` |
| HTSP port | `9982` |
| Username / password | the ones you created during install |

Enable the add-on and restart Kodi.

---

## Recording

Tvheadend records to `/home/hts/` by default, which lives on the SD card.
**Move this to a USB drive** — a couple of hours of HD recording will fill a
16 GB card and an SD card is a poor choice for sustained writes.

> Configuration → Recording → **Digital Video Recorder Profiles** →
> Recording system path

Make sure the `hts` user can write there:

```bash
sudo chown -R hts:video /mnt/usb/recordings
```

Schedule recordings from Kodi's TV guide, or from the Tvheadend web interface
under **Digital Video Recorder**.

---

## Verify

```bash
systemctl status tvheadend
ls /dev/dvb/                 # adapter0/ should exist
```

Then open `http://<pi-ip>:9981` and check the adapter appears.

---

## Troubleshooting

**No TV adapter listed**

Check the kernel saw it:

```bash
dmesg | grep -i -E "dvb|frontend|firmware"
ls /dev/dvb/
```

If `dmesg` reports missing firmware, install it:

```bash
sudo apt-get install firmware-linux-nonfree
```

Some tuners need a specific `.fw` file that is not packaged — `dmesg` names
it; download it into `/lib/firmware/` and re-plug the tuner.

**Tuners are power-hungry.** A tuner that works on a laptop may not work on a
Pi's USB port. Try a powered USB hub before concluding the tuner is faulty.

**The scan finds nothing**

- Check the aerial connection and that you chose the right region.
- Some regions need a manual mux frequency — your broadcaster publishes them.
- Terrestrial reception that is fine on a TV may be marginal for a USB tuner;
  try an amplified aerial.

**Kodi cannot connect**

- Confirm the service is running: `systemctl status tvheadend`.
- Confirm the HTSP port is open: `ss -tlnp | grep 9982`.
- Credentials must match what you set during `apt install`. Reset them in the
  web interface under Configuration → Users.

**Recordings stutter or fail**

Almost always disk I/O — SD cards are slow at sustained writes. Move the
recording path to a USB drive.

**Forgot the admin password**

Stop the service, edit `/home/hts/.hts/tvheadend/superuser`, restart:

```bash
sudo systemctl stop tvheadend
sudo nano /home/hts/.hts/tvheadend/superuser
sudo systemctl start tvheadend
```

**Logs**

```bash
sudo journalctl -u tvheadend -f
```
