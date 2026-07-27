# 95-weather — spoken weather reports

Reads the current conditions from OpenWeatherMap and speaks them in the same
language as the rest of the system. Bind it to a button and you get a weather
report without a screen.

```bash
./install.sh 95-weather
```

**Prerequisites:** `00-base`, and `90-speech` if you want it spoken aloud.
Needs a free OpenWeatherMap API key.

---

## Getting an API key

1. Sign up at <https://openweathermap.org/api> — the free tier is generous
   (60 calls/minute) and needs no payment details.
2. Copy the key from your account page.
3. Put it in `config.sh`:

   ```bash
   export OPENWEATHER_API_KEY="your-key-here"
   ```

**A brand new key can take up to a couple of hours to activate.** Until then
every request comes back `401`. If you have just created one and it does not
work, wait rather than debug.

The key belongs in `config.sh`, which is git-ignored — never in a script.

---

## Configuration

```bash
export REC_WEATHER_LOCATION="auto"
export REC_WEATHER_UNITS="metric"
```

The spoken language comes from `SPEECH_LANG`, so there is nothing extra to
set — the forecast wording and the greeting both follow it.

### `REC_WEATHER_LOCATION`

Three accepted forms:

| Value | Meaning |
|---|---|
| `"auto"` | Detect the location from this machine's public IP address |
| `"Helsinki"` | A city name |
| `"Cambridge,GB"` | City plus country code — there are several Cambridges |
| `"60.17,24.94"` | Explicit `latitude,longitude`, always unambiguous |

> ### "auto" follows your VPN
>
> IP geolocation reports where your traffic **leaves the internet**, not where
> the Pi is. When the VPN tunnel is up that is the exit node — so with
> `NORDVPN_COUNTRIES="xx pl fi uk"` the reported weather changes country every
> time you press the VPN button.
>
> That is occasionally amusing and rarely what you want. **If you use the VPN,
> set a fixed city or coordinates.** `doctor.sh weather` warns when it sees
> `auto` combined with a live tunnel.

Geolocation uses [ip-api.com](http://ip-api.com/), which needs no key.

### `REC_WEATHER_UNITS`

`metric` for Celsius (default), `imperial` for Fahrenheit.

---

## Usage

```bash
python3 bin/weather.py                    # print the report
python3 bin/weather.py Helsinki           # override the location once
python3 bin/weather.py "60.17,24.94"      # explicit coordinates
python3 bin/weather.py --lang en          # override the language

bash bin/say_weather.sh                   # speak it
bash bin/say_weather.sh Helsinki          # speak it for somewhere else
```

`weather.py` prints the sentence on **stdout** and its diagnostics on
**stderr**, so it composes cleanly:

```bash
bash bin/speech.sh "$(python3 bin/weather.py)"
```

### Bind it to a button

Add to `REC_GPIO_BUTTONS` in `config.sh`:

```bash
"5:bash $REC_BIN/say_weather.sh"
```

### From Kodi

It is already in the Shell Script Launcher menu as **Weather**. Re-run
`./install.sh 20-kodi-addons` after updating to refresh the menu file.

---

## Languages

OpenWeatherMap returns the description already translated, so only the
surrounding sentence needs handling. `bin/weather.py` carries templates for:

| `SPEECH_LANG` | Example |
|---|---|
| `pl` | *bezchmurnie. Temperatura 3 stopnie, odczuwalna 1 stopień.* |
| `en` | *clear sky. Temperature 3 degrees, feels like 1.* |
| `de` | *klarer Himmel. Temperatur 3 Grad, gefühlt 1 Grad.* |
| `fi` | *selkeää. Lämpötila 3 astetta, tuntuu kuin 1 astetta.* |

Any other language falls back to a neutral `description. 3°, 1°.`, which the
speech synthesiser reads correctly in every language it supports.

Polish declines *stopień* by the last digit of the number
(1 *stopień*, 2–4 *stopnie*, 5+ *stopni*, with the 12–14 exception), so it has
a small helper. To add a language, extend the `TEMPLATES` dictionary in
`bin/weather.py`.

---

## Verify

```bash
./bin/doctor.sh weather
python3 bin/weather.py
```

---

## This is not Kodi's weather

Kodi has its own weather section, provided by a Kodi add-on and shown on
screen. This module is separate: it **speaks** the forecast, so you can hear it
without a screen, and shares no code or configuration with Kodi's display.

Both can be used at once. If Kodi's weather shows squares (□) instead of
characters, that is a font issue in the skin — see
[10-kodi.md](10-kodi.md#troubleshooting).

---

## Troubleshooting

**"OPENWEATHER_API_KEY is not set"**

Add it to `config.sh` and re-run. See above.

**"OpenWeatherMap rejected the API key (401)"**

- A new key takes up to a couple of hours to activate — wait.
- Check for a stray space or quote in `config.sh`.
- Confirm the key is active on your OpenWeatherMap account page.

**"Location not found"**

City names are ambiguous. Add a country code (`"Cambridge,GB"`) or use
coordinates (`"52.20,0.12"`), which always work.

**The weather is for the wrong country**

`REC_WEATHER_LOCATION="auto"` with the VPN connected — see the warning above.
Set a fixed location.

**"Could not reach the weather service"**

No internet, or DNS is still settling after a VPN change. Check with
`ping -c1 1.1.1.1`.

**It prints but does not speak**

Install the speech module and test it on its own:

```bash
./install.sh 90-speech
bash bin/speech.sh "test"
```

**The report is spoken in the wrong language**

Both the greeting and the forecast follow `SPEECH_LANG` in `config.sh`.
Override for one run with `python3 bin/weather.py --lang en`.
