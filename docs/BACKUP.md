# Backup and restore

Everything a reinstall would otherwise lose, in one archive.

```bash
bin/backup.sh              # settings only - seconds, ~10 MB
bin/backup.sh --list       # show what would go in, and how big
bin/restore.sh <archive>   # put it back
```

---

## Two tiers, and why

| Tier | Contents | Size | Could you recreate it? |
|---|---|---|---|
| **settings** (default) | Controller mappings, emulator configs, scraped gamelists, Kodi library and add-on settings, `config.sh`, Bluetooth pairings, Widevine | ~10 MB | Only with real effort |
| **content** (`--with-content`) | ROMs, BIOS images, web server files | Gigabytes | Yes, if you kept the originals |

The split matters because the small tier is the valuable one. Re-copying ROMs
is tedious; recreating a hand-tuned controller mapping is worse.

### What is in the settings tier

| Path | Why it matters |
|---|---|
| `/opt/retropie/configs` | Emulator settings, `retroarch.cfg`, **controller autoconfigs** |
| `~/.kodi/userdata` | Library database, favourites, sources, add-on settings, the Netflix auth key |
| `~/.kodi/cdm` | The active Widevine module — re-obtaining it is failure-prone |
| `config.sh` | Your VPN token, API key, button map, forwards |
| `~/.local/share/rec-iptv` | IPTV playlists, including channels you added |
| `/etc/bluetooth/main.conf`, `/var/lib/bluetooth` | Device class **and pairing keys** — without these every phone re-pairs |
| `/etc/systemd/system/*.service` | The units the modules install |
| `/usr/local/etc/no-ip2.conf` | Dynamic DNS credentials |
| `/home/hts/.hts` | Tvheadend channels, EPG config, users |

### What is deliberately excluded

Regenerable bulk, which would otherwise dominate the archive:

- Kodi thumbnail cache and `Textures*.db`
- `inputstreamhelper/backup` — copies of every superseded Widevine (27 MB on
  a typical system; the active one is kept separately)
- `plugin.video.torrest/bin` — a 10 MB binary the add-on re-downloads
- Add-on HTTP and metadata caches (`*_cache.sqlite`, `nf_cache.sqlite3`) —
  stale caches cause more trouble after a restore than they save
- RetroArch assets, shaders, overlays and cores — shipped by the distribution
- Scraped artwork (`downloaded_images`) — re-scrapeable, and large

Excluding these took a real backup from 28 MB to 8.3 MB.

---

## Before a reinstall

```bash
bin/backup.sh                      # settings
scp pi@rpi:~/rec-backups/rec-backup-settings-*.tar.gz .
```

ROMs are usually too big to want inside the archive. Copy them separately:

```bash
rsync -av --info=progress2 pi@rpi:~/RetroPie/roms/ ./roms-backup/
rsync -av pi@rpi:~/RetroPie/BIOS/ ./bios-backup/
```

Or take everything in one go with `bin/backup.sh --with-content`, if you have
somewhere to put several gigabytes.

> **The archive contains `config.sh`,** so it holds your VPN token and API
> keys. `backup.sh` sets it to mode 600 for that reason. Do not put it in a
> shared folder or a git repository.

---

## After a reinstall

**Order matters.** Install the modules *first*, then restore:

```bash
./install.sh 00-base 10-kodi 30-retropie      # whatever you want
bin/restore.sh rec-backup-settings-*.tar.gz
bin/doctor.sh
sudo reboot
```

Restoring first does not work: RetroPie's own setup recreates
`/opt/retropie/configs`, and the module installers rewrite `config.sh`. Both
would overwrite what you just put back.

### Restoring only part of it

```bash
bin/restore.sh <archive> --only retropie     # emulator + controller configs
bin/restore.sh <archive> --only kodi         # Kodi library and add-on settings
bin/restore.sh <archive> --only config       # just config.sh
bin/restore.sh <archive> --only bluetooth    # pairings and adapter settings
bin/restore.sh <archive> --only tvheadend
bin/restore.sh <archive> --only noip
bin/restore.sh <archive> --only content      # ROMs, BIOS, web files
```

Useful when only one thing broke — restoring a Kodi library should not put
back a stale VPN config.

### Inspecting an archive without touching anything

```bash
bin/restore.sh <archive> --list
```

Prints the manifest — when it was made, on which host, from which repository
commit, and what it holds.

---

## What restore does

1. Prints the manifest and asks for confirmation.
2. Stops any service holding the files (`kodi`, `tvheadend`, `bt-agent`,
   `pulseaudio`) so they cannot write their in-memory state back over the
   restore.
3. Extracts with `--same-owner --same-permissions`, so Bluetooth link keys
   and Tvheadend files stay usable.
4. Re-applies mode 600 to `config.sh`.
5. Warns if `config.sh` references a home directory that is not yours —
   which happens when restoring onto a different username.
6. Restarts what it stopped.

Reboot afterwards: Bluetooth pairings and restored units only take full
effect on a fresh start.

---

## Keeping backups automatically

Weekly, via cron:

```bash
crontab -e
```

```cron
0 4 * * 0 /home/pi/rpi_entertainment_center/bin/backup.sh >/dev/null 2>&1
```

Old archives are not pruned — they are small, but clear them out occasionally:

```bash
ls -t ~/rec-backups/*.tar.gz | tail -n +5 | xargs -r rm
```

Keeping them only on the Pi defeats the purpose. Copy them to another machine,
or write straight to a USB drive:

```bash
bin/backup.sh /mnt/usb
```

---

## Troubleshooting

**"Nothing to back up"**

Nothing is installed yet, or the paths do not exist. Check with
`bin/backup.sh --list`.

**The archive is much larger than expected**

Something new is storing bulk under `~/.kodi/userdata`. Find it:

```bash
tar tvzf <archive> | sort -k3 -n -r | head -20
```

Then add an exclude to `bin/backup.sh`.

**Restore says "Nothing matching --only"**

That tier was not in the archive — a settings backup contains no ROMs. Check
with `--list`.

**Permission errors during restore**

`restore.sh` uses `sudo` for the system paths. Run it as your normal user, not
under `sudo` — it handles the escalation itself.

**RetroPie shows no games after a restore**

Restore puts back configs and gamelists, not ROMs. If you took a settings
backup, copy the ROMs separately.

**Controller mapping still wrong after a restore**

Check the autoconfig file came back:

```bash
ls /opt/retropie/configs/all/retroarch/autoconfig/
```

If EmulationStation still asks to configure input, its own mapping lives in
`/opt/retropie/configs/all/emulationstation/es_input.cfg` — confirm that is
present too, then restart EmulationStation.
