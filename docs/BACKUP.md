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

## Will restoring break things if versions changed?

The honest answer: **mostly no, but it depends which file, and the failure
modes differ.** A reinstall usually means newer Kodi, newer RetroPie, newer
everything — so this is worth understanding before you trust a restore.

`backup.sh` records the version of each component in the manifest, and
`restore.sh` compares them against what is installed and warns you before
touching anything.

### Safe at any version

Plain data that no software version cares about:

| | |
|---|---|
| Controller autoconfigs (`DragonRise …cfg`) | Stable RetroArch format for years |
| `es_input.cfg`, `es_settings.cfg` | Stable EmulationStation format |
| `gamelist.xml` (scraped metadata) | Plain XML |
| `sources.xml`, `favourites.xml`, `advancedsettings.xml` | Plain Kodi XML |
| IPTV playlists | Plain M3U |
| `config.sh` | This project's own |

This is exactly the set `restore.sh --safe` restores. If you want to be
cautious after a big version jump, start there.

### Migrates forward, breaks backward

**Kodi databases.** The number in the filename *is* the schema version —
`MyVideos119.db` is Kodi 19, Kodi 21 uses `MyVideos131.db`. Kodi reads an
older database and migrates it forward automatically on first start, keeping
your library and watched states.

It cannot go backwards. Restoring a Kodi 21 database onto Kodi 19 means Kodi
ignores the file and starts with an empty library. `restore.sh` detects this
and says so plainly:

```
WARNING: Archive holds Kodi schema 131 but this Kodi uses 119.
WARNING:   That is a DOWNGRADE. Kodi cannot migrate backwards - it will
WARNING:   ignore the restored library and start empty.
```

**Tvheadend config** likewise migrates forward on start.

**Kodi `guisettings.xml`** — unknown settings are ignored, missing ones take
defaults. Harmless in practice.

### The one that genuinely bites

**`emulators.cfg`** names cores by *absolute path*:

```
lr-snes9x = "/opt/retropie/emulators/retroarch/bin/retroarch
             -L /opt/retropie/libretrocores/lr-snes9x/snes9x_libretro.so ..."
```

If you reinstall RetroPie and choose a different emulator set — or a core was
renamed or dropped upstream — that path points at nothing. The symptom is a
game that refuses to launch, with no useful error anywhere.

`restore.sh` checks for this **after** restoring and lists any core that is
referenced but not installed:

```
WARNING: 3 emulator core(s) referenced by the restored configs are not
WARNING: installed on this system:
    /opt/retropie/libretrocores/lr-mupen64plus/mupen64plus_libretro.so
```

Two fixes: install the missing cores through
`sudo ~/RetroPie-Setup/retropie_setup.sh` → Manage packages, or hold a button
while launching a game to pick a different emulator, which rewrites
`emulators.cfg` for that system.

### Tied to hardware, not versions

**Bluetooth pairing keys** live under the adapter's own MAC address in
`/var/lib/bluetooth/<MAC>/`. Restoring onto the same Pi is fine; onto
different hardware the keys do not apply and every device must be paired
again. `restore.sh` compares the adapter address and tells you.

**Widevine** (`~/.kodi/cdm`) is tied to architecture and to what
`inputstreamhelper` expects. It usually survives a Kodi upgrade; if DRM
playback fails after a restore, delete `~/.kodi/cdm` and let
`inputstreamhelper` fetch a fresh copy.

### Recommended approach after a big version jump

```bash
./install.sh 00-base 10-kodi 30-retropie     # install first
bin/restore.sh <archive> --safe              # the version-independent set
# check things work, then add the rest if you want it:
bin/restore.sh <archive> --only kodi         # library and add-on settings
```

Restoring in stages costs a few minutes and makes it obvious which piece
caused a problem, rather than leaving you to guess.

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
bin/restore.sh <archive> --safe              # only version-independent files
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

1. Prints the manifest, compares the recorded component versions against
   what is installed, and warns about any drift that matters.
2. Asks for confirmation.
3. Stops any service holding the files (`kodi`, `tvheadend`, `bt-agent`,
   `pulseaudio`) so they cannot write their in-memory state back over the
   restore.
4. Extracts with `--same-owner --same-permissions`, so Bluetooth link keys
   and Tvheadend files stay usable.
5. Re-applies mode 600 to `config.sh`.
6. Warns if `config.sh` references a home directory that is not yours —
   which happens when restoring onto a different username.
7. Checks that every emulator core referenced by the restored RetroPie
   configs actually exists, and lists any that do not.
8. Restarts what it stopped.

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
