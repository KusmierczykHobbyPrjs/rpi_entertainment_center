# Video playback performance

Why streaming stutters on a Raspberry Pi 3B, and which knob to turn.

Almost every "my Pi is too slow for video" problem is one of three things: the
wrong codec, the wrong resolution, or a bandwidth cap someone set once and
forgot. They have different fixes, and turning the wrong knob makes the picture
worse without making it smoother.

---

## The constraint

A Pi 3B/3B+ has a VideoCore IV GPU that decodes **H.264 in hardware, and
nothing else you are likely to meet**:

| Codec | Pi 3B / 3B+ | Pi 4 / 400 | Pi 5 |
|---|---|---|---|
| **H.264** | hardware, to 1080p30 | hardware, to 1080p60 | software (fast CPU) |
| **HEVC (H.265)** | **software only** | hardware, to 4Kp60 | hardware |
| **VP9** | **software only** | software only | software only |
| **AV1** | **software only** | software only | software only |
| MPEG-2, VC-1 | hardware, with a paid licence key | — | — |

"Software only" on a 1.2 GHz Cortex-A53 means roughly: fine for 480p, painful
at 720p, hopeless at 1080p. So on a Pi 3B the goal is always **H.264 at 720p or
below**, and the CPU should then be nearly idle during playback.

Two things spend CPU even when decoding is in hardware:

- **Widevine DRM.** On Linux ARM you get Widevine **L3**, which decrypts in
  software. Netflix and Disney+ therefore cost noticeably more CPU than the
  same file played locally. This is unavoidable.
- **Deinterlacing and scaling**, if the stream resolution does not match the
  screen.

---

## Where these settings live

InputStream Adaptive and ffmpeg are **add-ons**, not part of Kodi, so their
settings are not under Settings → Player. Both are here:

> Settings → **Add-ons** → **My add-ons** → **VideoPlayer InputStream**
> → *InputStream Adaptive* or *InputStream FFmpeg Direct* → **Configure**
>
> *Ustawienia → Dodatki → Moje dodatki → Strumień wejściowy odtwarzacza wideo*

Some add-ons offer a shortcut — the Netflix add-on's own settings have an entry
that opens InputStream Adaptive directly — but most do not, and the path above
always works.

Settings levels, if a setting you are looking for is not visible (the toggle is
at the bottom-left of the settings window):

| Setting | Level needed |
|---|---|
| Everything in InputStream Adaptive below | **Basic** — always visible |
| ffmpeg's **Stream selection bandwidth** | **Standard** — the default |
| Kodi's hardware acceleration toggles | **Advanced** |

---

## First, find out what is actually happening

Do not guess from CPU usage. During playback press **`o`** — Kodi overlays the
player's codec information, including the decoder actually in use.

```
Video: ff-h264 (V4L2 M2M), 1280x720          <- hardware. Good.
Video: ff-h264, 1920x1080                    <- software H.264. Fix this.
Video: ff-vp9, 1280x720                      <- software VP9. Fix this.
```

A hardware decoder is named in the line (`V4L2 M2M`, `DRM PRIME`). A bare
`ff-` name is `ffmpeg` on the CPU.

If H.264 is being decoded in software, the problem is Kodi's configuration, not
the stream:

**Settings → Player → Videos → Allow hardware acceleration** — enable the
V4L2 / DRM PRIME entries. (Set Settings level to **Advanced** or **Expert**, or
the section is hidden.)

---

## Netflix and other DRM services

### The trap: `Maximum bandwidth` is global

InputStream Adaptive's settings belong to **inputstream.adaptive**, not to the
add-on whose menu you reached them through. Setting

> **Maksymalna przepustowość (Kbps)** / *Maximum bandwidth (Kbps)* → `1000`

throttles **every** add-on that uses InputStream Adaptive — Netflix, Disney+,
TVP VOD, Polsat, and IPTV channels configured to use ISA. Tune one service with
it and you have quietly degraded all the others, in a place you will not think
to look when live TV turns soft a fortnight later.

It is also the wrong lever. It limits **bitrate**, while the Pi's difficulty is
**pixels and decryption**. Netflix's H.264 ladder puts 720p at roughly
1750 Kbps and up, so a 1000 Kbps cap holds you a rung or two below 720p and
gives you a soft, blocky picture that is no easier to decode than a clean one.

### What to set instead

Cap the **resolution**, and cap it only for DRM:

| Setting (Netflix add-on → InputStream Adaptive settings) | Set to | Why |
|---|---|---|
| **Maksymalna przepustowość (Kbps)**<br>*Maximum bandwidth* | `0` (off) | Undo the global throttle |
| **Maksymalna rozdzielczość dla video z DRM**<br>*Maximum resolution for DRM videos* | `720p` | **DRM only** — Netflix and Disney+ are limited, live TV and IPTV are not |
| **Maksymalna rozdzielczość**<br>*Maximum resolution* | `auto` | Leave it; the DRM setting above is the targeted one |

That single DRM-scoped resolution cap is the whole fix. It gives you the best
bitrate Netflix offers *at* 720p, instead of a starved stream at an arbitrary
resolution.

> `Maximum resolution` and `Maximum resolution for DRM videos` only apply when
> **Typ wyboru strumienia** / *Stream selection type* is `default`. If you
> switch that to manual, you are choosing the stream yourself and these are
> ignored.

### The Netflix add-on's own limiter

The add-on has a second, independent cap:

> **Ustawienia → Ograniczaj rozdzielczość strumieniowania do**
> / *Limit streaming resolution to* → `HD 720p`

Use this **instead of** the ISA one only if you want a Netflix-specific limit
that does not touch Disney+. The add-on's own help text recommends trying the
InputStream Adaptive setting first, because this one removes streams from the
manifest before ISA ever sees them, which ISA does not always like.

Do not set both. Two caps interact confusingly and you will not know which one
produced the picture you are looking at.

### Codec settings: check, do not change

Netflix can serve VP9 and AV1, which a Pi 3B cannot decode in hardware. In the
add-on's expert settings these are **already off by default** — but confirm,
because a Pi 3B with VP9 enabled is unwatchable and the symptom looks like a
slow network:

| Setting | Pi 3B | Pi 4 |
|---|---|---|
| **Włącz kodek VP9** / *Enable VP9 codec* | off | off |
| **Włącz kodek HEVC** / *Enable HEVC codec* | off | on (hardware) |
| **Włącz kodek AV1** / *Enable AV1 codec* | off | off |

---

## "There is only one quality in the list"

Expected. In its default mode InputStream Adaptive presents the whole adaptive
set as a *single* stream and switches rungs itself, so Kodi's playback
**Video settings** list has nothing to offer you.

To choose by hand:

> InputStream Adaptive → **Typ wyboru strumienia** / *Stream selection type*

| Value | Behaviour |
|---|---|
| `default` | ISA picks and adapts. Honours the resolution and bandwidth caps above. |
| `manual-osd` | Every rendition appears in the playback OSD, selectable mid-film |
| `ask-quality` | Asks once, when playback starts |
| `fixed-res` | Pins one resolution |

`manual-osd` is the useful one for working out what your Pi can actually
sustain. Once you know, go back to `default` with a resolution cap — you want
adaptive switching for the evenings when the network is busy.

---

## Live TV, IPTV and TVP VOD

These add-ons often let you choose the playback engine:

> **Typ playera (bez archiwum TV)** / *Player type* → `ISA` or `ffmpeg`

| | InputStream Adaptive | ffmpeg (`inputstream.ffmpegdirect`) |
|---|---|---|
| Adaptive switching | yes — steps down when the network dips | no — one variant, chosen at open, for the whole session |
| How the variant is chosen | bandwidth estimate, then adapts | highest under **Stream selection bandwidth**, default off = no ceiling |
| Obeys the ISA settings above | **yes** | no — it has its own, below |
| Variant list in the OSD | only with `manual-osd` | never |

### Reading the stream entry in Video settings

**Neither engine gives you a list of renditions to pick from** — that is worth
knowing before you go hunting for one. Kodi's playback *Video settings* shows a
single video stream either way, because both engines hand Kodi one decoded
stream and keep the variant choice to themselves.

What changes is the **description** of that single entry: its resolution and
codec are those of whichever variant the engine picked. So if switching from
ISA to ffmpeg changed what that line says, you have learned something concrete
— the channel offers more than one variant, and the two engines chose
differently. A higher figure under ffmpeg means ISA was under-selecting, which
points straight back at the initial-bandwidth estimate above.

To enumerate the renditions properly, use ISA with `manual-osd`. ffmpeg has no
equivalent.

### ffmpeg's own bandwidth ceiling

```
Ustawienia → Przepustowość wyboru strumienia   (Stream selection bandwidth)
```

Default **off**, so ffmpeg takes the highest variant the channel offers. On a
Pi 3B that can be more than the hardware can decode — a 1080p50 broadcast will
stutter where 720p would not.

If ffmpeg now picks something too heavy, this is the knob: around `3500` keeps
you at 720p on most Polish broadcasters. Unlike ISA's cap it is scoped to
`inputstream.ffmpegdirect` alone, so it cannot surprise you elsewhere.

### Live TV starts low under ISA and stays there

The usual cause is not a cap you set — it is an ISA **default**:

> **Automatycznie określa początkową przepustowość**
> / *Auto determines initial bandwidth* — default **on**

ISA estimates your bandwidth from the very first download and picks a rung to
start on. Upstream's own help text admits the estimate "may not be accurate"
and says: *if the video quality at the start of playback is too low, try
disabling it*.

Live streams are the worst case for this. Segments are short, the first fetch
is often a tiny init segment or comes from a warm edge cache, and there is no
long buffer to climb out of a bad guess with — so it lands on a low rung and
sits there for the whole session. Video on demand usually recovers; live
usually does not.

| Setting | Set to |
|---|---|
| **Automatycznie określa początkową przepustowość**<br>*Auto determines initial bandwidth* | off |
| **Początkowa przepustowość (Kbps)**<br>*Initial bandwidth (Kbps)* | `4000` (the default), or higher on a fast wired link |

This also explains why ffmpeg often looks better on live TV: it does not
estimate anything, it just plays a variant from the master playlist — usually
the top one.

**Before changing anything, find out whether a better stream exists.** Set
`Typ wyboru strumienia` to `manual-osd` and look at the list during playback.
If 576p is the only entry, that is what the channel broadcasts and no setting
will improve it. (This is the only way to see the list — see
[below](#reading-the-stream-entry-in-video-settings).)

If ISA is still worse after that, ffmpeg is a perfectly reasonable choice for
live TV — you lose the ability to step down gracefully, so a congested network
shows up as buffering rather than a softer picture.

Note that the player-type setting lives in each add-on, so TVP, Polsat and
Player.pl are configured separately. The ISA settings above are shared by all
of them.

---

## Video falls behind the audio

Distinct from stutter, and it has two quite different causes. The codec overlay
(`o`) separates them — look at the **dropped / skipped frames** counters:

| Overlay | Cause | Fix |
|---|---|---|
| Dropped frames climbing steadily | The Pi cannot decode this stream in real time and is falling behind | Give it a smaller stream — see below |
| Dropped frames near zero | Not a decoding problem. A clock mismatch, or the stream's own timestamps | Refresh rate, below |

### If frames are being dropped

The variant is too heavy. On a Pi 3B the usual culprit is a **1080i50 or
1080p50** broadcast: hardware H.264 decode tops out around 1080p30, and Polish
television is 50 Hz, so an HD channel is roughly double what the chip can do —
and interlaced content costs deinterlacing on top.

- **ffmpeg:** set *Stream selection bandwidth* to about `3500`, which picks a
  720p variant on most Polish broadcasters.
- **ISA:** it should step down on its own; if it does not, cap *Maximum
  resolution* at `720p`. (Note that is the general one, not the DRM one.)

### If frames are not being dropped

Then the decoder is keeping up and the picture is drifting for another reason.
The most common on a Pi is a **frame-rate mismatch**: Polish broadcast is 25 or
50 Hz, an HDMI display usually runs at 60 Hz, and Kodi then has to invent or
discard a frame every sixth one.

> Settings → Player → Videos → **Adjust display refresh rate** → `On start / stop`
>
> *Dostosuj częstotliwość odświeżania ekranu*

This switches the output to 50 Hz for 50 Hz content and back afterwards, which
removes the mismatch entirely. It is the single most useful playback setting on
a Pi driving a TV, and it is off by default.

Check your TV actually accepts 50 Hz — most do; a few PC monitors do not.

If drift persists after that, it is the stream itself. ffmpeg plays live HLS
with no adaptive correction, so a broadcaster whose timestamps drift will drift
on your screen. Switching that channel back to ISA is the answer, once its
initial-bandwidth estimate has been fixed above.

---

## Recommended starting point for a Pi 3B

```
Kodi   → Player → Videos → hardware acceleration       enabled
Kodi   → Player → Videos → Adjust display refresh rate On start/stop
ISA    → Stream selection type                         default
ISA    → Maximum bandwidth (Kbps)                      0
ISA    → Maximum resolution for DRM videos             720p
ISA    → Maximum resolution                            auto
ISA    → Auto determines initial bandwidth             off      (live TV)
ISA    → Initial bandwidth (Kbps)                      4000
Netflix→ VP9 / HEVC / AV1 codecs                       off
Netflix→ Limit streaming resolution to                 --  (ISA handles it)
TVP    → Player type                                   try ISA first
ffmpeg → Stream selection bandwidth                    off, or ~3500 if it
                                                       picks more than the Pi
                                                       can decode
```

Then play something and press `o`. If it says `ff-h264 (V4L2 M2M)` and the CPU
is quiet, you are done.

`./bin/doctor.sh kodi` warns if a low global bandwidth cap is in place, since
it is invisible from inside the add-on that appears to be misbehaving.

---

## What does not help

- **Overclocking.** Decoding runs on the GPU block; the CPU is not the limit
  once hardware decode is working. Overclocking a Pi that is already thermally
  throttling makes things worse. Check with `vcgencmd get_throttled` — anything
  other than `0x0` means power or heat is your real problem, and no add-on
  setting will fix it.
- **Raising `gpu_mem`, probably.** This is genuinely worth understanding rather
  than copying. On the old firmware graphics stack the decoder's buffers came
  out of the fixed `gpu_mem` split, and raising it to 128 or 256 was standard
  advice. Raspberry Pi OS has defaulted to the KMS driver (`dtoverlay=vc4-kms-v3d`)
  since Bullseye, and Kodi decodes through V4L2 rather than the old OMX path.
  Most of the guides recommending `gpu_mem=256` predate that. If you have it
  set, try the default and see whether anything changes — memory handed to the
  GPU is memory a 1 GB Pi does not have for Kodi.
- **Raising the buffer.** Buffering settings fix *network* stutter. If the
  picture is smooth but slow, or tears, buffering is not involved.
- **A lower resolution than 720p, on a whim.** If 720p H.264 in hardware still
  stutters, something else is wrong — check the decoder line and
  `vcgencmd get_throttled` before dropping to 480p.

---

## See also

- [10-kodi.md](10-kodi.md) — Kodi itself
- [20-kodi-addons.md](20-kodi-addons.md) — Netflix, Disney+ and the DRM add-ons
- [15-kodi-iptv.md](15-kodi-iptv.md) — IPTV playlists
- [HARDWARE.md](HARDWARE.md) — power supply and cooling, which matter more than
  any of the above if you are throttling
