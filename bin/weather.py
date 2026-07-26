#!/usr/bin/env python3
"""Print the current weather as a sentence, ready to be spoken.

Reads its settings from config.sh (via the environment):

    OPENWEATHER_API_KEY     required - free key from openweathermap.org
    REC_WEATHER_LOCATION    "auto", a city name, or "lat,lon"
    REC_WEATHER_UNITS       "metric" (default) or "imperial"
    SPEECH_LANG             language for the description and the sentence

Usage:
    weather.py                    use the configured location and language
    weather.py Helsinki           override the location for this run
    weather.py --lang en          override the language
    weather.py "60.17,24.94"      explicit coordinates

Output is a single line on stdout, so it can be piped straight into speech:

    bash speech.sh "$(python3 weather.py)"

See docs/95-weather.md.
"""

import json
import os
import pathlib
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

WEATHER_URL = "https://api.openweathermap.org/data/2.5/weather"
GEOLOCATE_URL = "http://ip-api.com/json/"
TIMEOUT = 10

# Settings this script takes from config.sh.
CONFIG_KEYS = (
    "OPENWEATHER_API_KEY",
    "REC_WEATHER_LOCATION",
    "REC_WEATHER_UNITS",
    "SPEECH_LANG",
)


def load_config_defaults():
    """Fill in any setting not already in the environment from config.sh.

    When this script is called from say_weather.sh the values are already
    exported, and this does nothing. Run directly - `python3 weather.py` -
    nothing has sourced config.sh, so we ask bash to do it and read the
    results back. Letting bash parse its own config file avoids
    reimplementing quoting rules here, and keeps config.sh the single place
    settings live.
    """
    missing = [k for k in CONFIG_KEYS if k not in os.environ]
    if not missing:
        return

    config = pathlib.Path(__file__).resolve().parent.parent / "config.sh"
    if not config.is_file():
        return

    # NUL-separated so a value containing spaces or newlines survives intact.
    script = f'source "{config}" >/dev/null 2>&1; ' + "".join(
        f'printf "%s\\0" "${{{key}-}}"; ' for key in missing
    )
    try:
        result = subprocess.run(
            ["bash", "-c", script],
            capture_output=True, text=True, timeout=10, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return

    values = result.stdout.split("\0")
    for key, value in zip(missing, values):
        if value:
            os.environ[key] = value


def fetch_json(url):
    """GET a URL and parse the JSON body."""
    with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8"))


def locate_by_ip():
    """Work out where we are from the public IP address.

    NOTE: this reports where the *traffic leaves the internet*, which is the
    VPN exit node when the tunnel is up. On this system the VPN rotates
    between countries, so "auto" will happily report the weather in whichever
    country you are currently tunnelling through. Set REC_WEATHER_LOCATION to
    a fixed city if that matters to you - see docs/95-weather.md.
    """
    data = fetch_json(GEOLOCATE_URL)
    if data.get("status") != "success":
        raise RuntimeError(data.get("message", "IP geolocation failed"))
    return data["lat"], data["lon"], data.get("city", "")


def build_query(location, api_key, units, lang):
    """Turn a location setting into a full OpenWeatherMap request URL."""
    params = {"appid": api_key, "units": units, "lang": lang}

    if location.strip().lower() == "auto":
        lat, lon, city = locate_by_ip()
        print(f"[weather] Detected location: {city or f'{lat},{lon}'}",
              file=sys.stderr)
        params["lat"], params["lon"] = lat, lon
    elif "," in location and all(
        part.strip().replace(".", "", 1).lstrip("-").isdigit()
        for part in location.split(",", 1)
    ):
        # Coordinates: "60.17,24.94"
        lat, lon = (part.strip() for part in location.split(",", 1))
        params["lat"], params["lon"] = lat, lon
    else:
        params["q"] = location

    return f"{WEATHER_URL}?{urllib.parse.urlencode(params)}"


def polish_degrees(value):
    """Polish declines 'stopień' by the last digit of the number."""
    value = abs(round(value))
    if value == 1:
        return "stopień"
    if value % 100 not in (12, 13, 14) and value % 10 in (2, 3, 4):
        return "stopnie"
    return "stopni"


# One sentence template per language. OpenWeatherMap already returns the
# description translated, so only the surrounding words need handling here.
# Anything not listed falls back to DEFAULT_TEMPLATE.
TEMPLATES = {
    "pl": lambda d, t, f: (
        f"{d}. Temperatura {t} {polish_degrees(t)}, "
        f"odczuwalna {f} {polish_degrees(f)}."
    ),
    "en": lambda d, t, f: (
        f"{d}. Temperature {t} degrees, feels like {f}."
    ),
    "de": lambda d, t, f: (
        f"{d}. Temperatur {t} Grad, gefühlt {f} Grad."
    ),
    "fi": lambda d, t, f: (
        f"{d}. Lämpötila {t} astetta, tuntuu kuin {f} astetta."
    ),
}


def DEFAULT_TEMPLATE(desc, temp, feels):
    """Language-neutral fallback: readable, and speakable in any language."""
    return f"{desc}. {temp}°, {feels}°."


def format_message(data, lang):
    desc = data["weather"][0]["description"]
    temp = round(data["main"]["temp"])
    feels = round(data["main"]["feels_like"])
    template = TEMPLATES.get(lang, DEFAULT_TEMPLATE)
    return template(desc, temp, feels)


def main(argv):
    load_config_defaults()

    lang = os.environ.get("SPEECH_LANG", "en")
    location = os.environ.get("REC_WEATHER_LOCATION", "auto")
    units = os.environ.get("REC_WEATHER_UNITS", "metric")
    api_key = os.environ.get("OPENWEATHER_API_KEY", "").strip()

    args = list(argv)
    if "--lang" in args:
        i = args.index("--lang")
        try:
            lang = args[i + 1]
        except IndexError:
            print("[weather] --lang needs a value", file=sys.stderr)
            return 2
        del args[i:i + 2]
    if args:
        location = " ".join(args)

    if not api_key:
        print(
            "[weather] OPENWEATHER_API_KEY is not set.\n"
            "          Get a free key at https://openweathermap.org/api\n"
            "          then put it in config.sh. See docs/95-weather.md.",
            file=sys.stderr,
        )
        return 1

    try:
        url = build_query(location, api_key, units, lang)
        data = fetch_json(url)
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            print("[weather] OpenWeatherMap rejected the API key (401).\n"
                  "          A new key can take up to a couple of hours to "
                  "activate.", file=sys.stderr)
        elif exc.code == 404:
            print(f"[weather] Location not found: {location}", file=sys.stderr)
        else:
            print(f"[weather] HTTP error {exc.code}: {exc.reason}",
                  file=sys.stderr)
        return 1
    except urllib.error.URLError as exc:
        # No network. Callers speak the result, so failing quietly beats
        # emitting a stack trace nobody will ever see.
        print(f"[weather] Could not reach the weather service: {exc.reason}",
              file=sys.stderr)
        return 1
    except (KeyError, ValueError, RuntimeError) as exc:
        print(f"[weather] Unexpected response: {exc}", file=sys.stderr)
        return 1

    sys.stdout.write(format_message(data, lang))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
