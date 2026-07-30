# Horseshoe Station — orientation for a cold start

If you are an assistant picking this project up with no memory of it, read this
first. Chat sessions do not carry over; this file does.

## What this is

A live weather log for a private Ambient Weather station at Nederland, Colorado
(39.9693, -105.4951, about 8,370 ft), written in the voice of a ship's log. It
publishes to several surfaces at once, all from one ten-minute GitHub Action.

## The pieces

| Path | What it is |
|---|---|
| `renderer/build.py` | The cloud renderer. Fetches the station, NWS Boulder, air quality and the Boulder County fire ban; keeps the logbook; renders each page; stages `site/`. `MOCK=1` runs it with synthetic data and no network. |
| `renderer/render.html` | The frame's pages, drawn in a headless Chromium at 800×480 and quantised to the Spectra-6 e-ink palette. |
| `renderer/dashboard.html` | The phone dashboard. Holds no keys — they ride in the URL fragment. |
| `renderer/kindle_build.py` | Four grayscale editions a day for a jailbroken Paperwhite lock screen. |
| `renderer/watch_build.py` | `site/watch.json`, the compact feed the Garmin watch reads. |
| `renderer/voice.py` | The prose voice — the Night Watch journal entries. |
| `frame/main.py` | MicroPython for the Inky Frame. Wakes on its own clock, fetches the PNG, sleeps. |
| `garmin/` | Watch face and app for the epix (Gen 2). See `garmin/README.md`. |
| `data/logbook.json` | Daily hi/lo/gust/rain/rh_min, committed by the Action. Feeds the Season's Log and the Records page. |

## Data sources

- **The station** — Ambient Weather, MAC `34:5F:45:66:8E:40`, via
  `rt.ambientweather.net/v1/devices`. Keys are repository secrets
  `AWN_API_KEY` and `AWN_APP_KEY` and appear nowhere else.
- Forecast and alerts — NWS Boulder (`api.weather.gov`), no key.
- Air quality — Open-Meteo CAMS, no key.
- Neighbouring peaks and towns for The Chart — Open-Meteo, no key.
- Fire ban — scraped from Boulder County and Nederland Fire.
- Sun and moon — computed, not fetched.

## Conventions worth keeping

- Pages have names, not labels: The Glass, The Wind, The Week Ahead, The
  Glasshouse, The Almanack, The Season's Log, The Log of Records, Fire Watch,
  Smoke Watch, The Chart, The Warning.
- The palette is fixed by the e-ink hardware: ink `#1A1A1A`, paper `#F2EFE6`,
  red `#C0392B`, blue `#2E5F94`, gold `#D4A017`, green `#2E7D4F`. Six inks,
  no more. Surfaces that are not e-ink may invert it but must not add to it.
- Type is EB Garamond and IM Fell English wherever a font can be chosen.
- The barometer is "the glass" and its scale carries the old Dutch words:
  STORM, REGEN, VERANDERLYK, MOOI WEER, BESTENDIG.
- Nothing on any surface holds an API key except the GitHub Action.

## Testing without the network

```sh
MOCK=1 python renderer/build.py
```

Synthetic but plausible data, no API calls, renders the full page set.
