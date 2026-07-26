# 90-speech — spoken messages and the action beep

The Pi is normally driven with no shell in sight, so anything that reports
state has to be audible.

```bash
./install.sh 90-speech
```

**Prerequisites:** `00-base`. Install this **before** `70-nordvpn` if you want
spoken VPN announcements.

---

## Why speech

Two problems, both solved by making the Pi talk:

**You cannot see errors.** The screen is showing a film. "The VPN dropped" has
no way to reach you visually.

**Actions have latency.** Reconnecting the VPN or switching UI takes several
seconds. Without immediate feedback the button feels broken and gets pressed
again — which is why `signal_action.sh` beeps the instant a command is
accepted, separately from whatever the command then does.

---

## How it works

`speech.sh` uses Google Translate's public text-to-speech endpoint. No API
key, no account, no local voice data.

That last point matters: offline engines that sound acceptable (Festival with
good voices, Pico) are too slow on a Pi 3B, and the fast ones (`espeak`) are
unpleasant to listen to. Sending a short string over the network and playing
back the returned MP3 is both faster and better sounding — at the cost of
needing an internet connection.

The endpoint rejects long strings, so `speech_text_splitter.py` breaks the
text into segments of at most 150 characters — first at sentence boundaries,
then at commas, then at spaces — and each is fetched and played in order.

**It checks for connectivity first.** Without that check, every message issued
while the network was still coming up produced a page of resolver errors and
no sound at all.

---

## Usage

```bash
bash bin/speech.sh "Welcome home"          # uses SPEECH_LANG
bash bin/speech.sh pl "Dzien dobry"        # explicit language
bash bin/speech.sh fi "Hei"
```

Supported languages are the ISO 639-1 codes Google Translate accepts: `en`,
`pl`, `fi`, `de`, `fr`, `es`, `it`, `ru`, `uk`, `ja`, `zh` and many more.

### The action beep

```bash
bash bin/signal_action.sh
```

Called by everything triggered from a button or a phone. Configure it:

```bash
export ACTION_SOUND="signal_action.mp3"    # bare name -> assets/sounds/
export ACTION_SOUND="/path/to/your.mp3"    # or an absolute path
export ACTION_SOUND=""                     # disable beeps
```

---

## Configuration

```bash
export VOLUME=30
export ACTION_SOUND="signal_action.mp3"
export SPEECH_LANG="en"
```

`VOLUME` is a percentage applied by the player itself, **independently of the
system mixer**. Turning it down quietens announcements without quietening
films. 30 is a good default: audible over a film, not startling at night.

---

## What uses it

| Caller | Says |
|---|---|
| `nordvpn_monitor.sh` | Every VPN connection change, including drops |
| `nordvpn_status.sh` | The current status, on demand |
| `stop_current_ui.sh` | Beeps to confirm a UI switch |
| `nordvpn_rotate.sh` | Beeps to confirm a VPN change |
| `clipboard2chromium.sh` | Beeps to confirm the URL was received |

---

## Verify

```bash
./bin/doctor.sh audio
```

Manually:

```bash
bash bin/speech.sh "testing one two three"
bash bin/signal_action.sh
aplay -l                      # list sound cards
```

---

## Troubleshooting

**No sound at all**

Check a card exists:

```bash
aplay -l
```

If nothing is listed, audio is probably routed to HDMI with nothing connected,
or the audio overlay is disabled. Force the output:

```bash
sudo raspi-config     # System Options -> Audio -> HDMI (or Headphones)
```

Check nothing is muted — `MM` under a channel in `alsamixer` means muted;
press `M` to unmute.

Test the sound path independently of this project:

```bash
speaker-test -t sine -f 440 -c 2 -l 1
```

**Speech says nothing but the beep works**

The beep is a local file; speech needs the network. Check connectivity:

```bash
ping -c1 1.1.1.1
curl -sI "http://translate.google.com" | head -1
```

`speech.sh` deliberately exits quietly when offline rather than emitting
resolver errors — run it from a terminal to see the warning.

**"mpg123 is not installed"**

```bash
sudo apt-get install mpg123
```

**Speech is too quiet or too loud**

Adjust `VOLUME` in `config.sh` (0–100). If it is already 100 and still quiet,
raise the system mixer with `alsamixer`.

**Speech is cut off mid-sentence**

The splitter breaks text at 150 characters. Very long single words with no
spaces can still overflow — shorten the message.

**Wrong language or accent**

Pass the code explicitly: `bash bin/speech.sh pl "tekst"`, or change
`SPEECH_LANG` in `config.sh`.

**Speech works over SSH but not from a button**

The button listener may have no audio access. Check group membership:

```bash
id -nG | grep audio
sudo usermod -a -G audio $USER    # then log out and back in
```

**Google's endpoint stops working**

It is an undocumented public endpoint and could change. If it does, replace
the `mpg123` call in `bin/speech.sh` with a local engine:

```bash
sudo apt-get install espeak-ng
espeak-ng -v en "text"
```

Quality is much worse, but it works offline — which for a status announcement
may be the better trade.
