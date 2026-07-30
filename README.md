# Horseshoe Station — The Ship's Glass

A live weather log for 485 Horseshoe Pl, Nederland CO — drawn every ten minutes
in the cloud, hung on the wall in e-ink.

Every ten minutes a scheduled job fetches your Ambient Weather station, the NWS
Boulder forecast and alerts, air quality, and the Boulder County fire-ban
status; keeps a daily logbook (which feeds the Season's Log and Records pages);
renders the current page as an 800×480 six-ink image; and publishes it. The
Inky Frame wakes on its own clock, grabs the image, shows it, and goes back to
sleep on battery.

## One-time setup (about 10 minutes)

1. **Create the repository.** On github.com click **+ → New repository**,
   name it `horseshoe-station`, keep it **Public** (required for free Pages),
   click **Create repository**.

2. **Upload these files.** On the empty repo page click **uploading an
   existing file**, then drag in *everything inside* this folder (keep the
   folder structure — your browser will preserve it if you drag the folders
   themselves). Commit.
   - If the `.github` folder refuses to drag, create the workflow by hand:
     **Add file → Create new file**, name it `.github/workflows/render.yml`,
     paste the contents of that file from this folder, commit.

3. **Add your keys as secrets.** Repo **Settings → Secrets and variables →
   Actions → New repository secret**. Create two:
   - `AWN_API_KEY` — your Ambient Weather API key
   - `AWN_APP_KEY` — your Ambient Weather application key

4. **Turn on Pages.** Repo **Settings → Pages → Source: GitHub Actions**.

5. **Light the fire.** Repo **Actions** tab → enable workflows if prompted →
   choose **Turn the page** → **Run workflow**. In ~3 minutes the run goes
   green and your site is live at
   `https://YOURUSERNAME.github.io/horseshoe-station/`
   - `index.html` — all of today's pages, for checking from any browser
   - `current.png` — what the frame shows on its next wake
   - `dashboard.html` — the interactive phone dashboard (see below)

After that it runs itself, every ten minutes, forever. The logbook starts
growing on day one; the Season's Log wakes at 5 days, records get deeper
every month, and "this day last year" lights up in a year.

## Keeping it on time

GitHub's `schedule` event is best-effort and it does not keep a ten-minute
promise. Measured on 30 July: of roughly 620 firings requested since the repo
went up, GitHub delivered about a dozen — near two percent. Every run that did
fire succeeded in about eighty seconds. Nothing is wrong with the workflow;
the cron simply is not delivered. Off-round minutes did not help.

So the cadence comes from outside. Any free scheduler that can make an HTTPS
POST will do — [cron-job.org](https://cron-job.org) takes two minutes:

1. Make a fine-grained personal access token scoped to this repository only,
   with **Actions: Read and write**. Nothing else.
2. New cron job, every 10 minutes:

   - **URL** `https://api.github.com/repos/horseshoestation/horseshoe-station/actions/workflows/render.yml/dispatches`
   - **Method** POST
   - **Headers** `Authorization: Bearer YOUR_TOKEN`,
     `Accept: application/vnd.github+json`
   - **Body** `{"ref":"main"}`

   A success looks like HTTP 204 with an empty body.

The workflow keeps a twice-hourly cron as a backstop, so if the pinger dies the
frame goes stale by half an hour rather than by a day.

## Phone shortcut

The hosted dashboard holds **no keys** — you carry them in the link itself
(the part after `#` never leaves your phone):

```
https://YOURUSERNAME.github.io/horseshoe-station/dashboard.html#apiKey=YOURAPIKEY&appKey=YOURAPPKEY
```

Open that in Chrome, then **⋮ → Add to Home screen**. Bookmark it; don't post it.

## When the Inky Frame arrives

1. Plug it into a computer over USB. It runs Pimoroni's MicroPython already;
   install [Thonny](https://thonny.org) to talk to it.
2. Copy `frame/secrets_example.py` to the frame as `secrets.py`, filled in
   with your Wi-Fi and your Pages address.
3. Copy `frame/main.py` to the frame as `main.py`.
4. Unplug, connect the battery, hang it. It wakes every 10 minutes;
   buttons A–E summon the Glass, Wind, Week, Glasshouse, and Almanack.

## The Kindle editions

The renderer also publishes `kindle.png` — a 1236x1648 grayscale lock screen
for a jailbroken Paperwhite, four editions a day: Morning, Midday, and
Evening in the ship's-log broadsheet, and at midnight the Night Watch —
a pioneer's journal entry composed from the day's real weather, with
Nederland mining flavor in its veins. Point the online-screensaver hack at
`https://YOURUSERNAME.github.io/horseshoe-station/kindle.png`
and set its refresh to 6 hours. (Jailbreak walkthrough comes separately —
firmware 5.19.2 uses SpringBreak; do not update the Kindle's firmware.)

## The wrist

`garmin/` holds a watch face and a glance-plus-app for the epix (Gen 2), fed by
`watch.json` — the same reading the frame draws, about 800 bytes, published
beside it every ten minutes. The watch holds no keys. See `garmin/README.md`
for building and sideloading.

## The pages

| Always | Seasonal | When needed |
|---|---|---|
| The Glass (with the Dutch scale) | Fire Watch (May–Oct) | The Warning (interrupts everything) |
| The Wind | The Winter Glass (Nov–Mar) | Smoke Watch (AQI over 100) |
| The Week Ahead | | |
| The Glasshouse | | |
| The Almanack | | |
| The Season's Log | | |
| The Log of Records | | |

Data: your station via Ambient Weather · forecast & alerts NWS Boulder ·
air Open-Meteo/CAMS · fire ban Boulder County & Nederland Fire ·
sun and moon computed from first principles, as a ship's officer would.
