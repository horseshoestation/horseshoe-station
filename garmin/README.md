# The Ship's Glass, on the wrist

Two Connect IQ projects for the Garmin epix (Gen 2), reading the same station
the wall frame reads:

- **`face/`** — a watch face. Time, temperature, wind, the glass and its trend,
  the Dutch scale word, and whatever warning outranks the rest.
- **`app/`** — a glance you swipe past, opening into four pages: The Glass,
  The Wind, the Deck Log, The Almanack.

`shared/` holds the palette, the feed contract and the drawing primitives, and
is on the source path of both.

## How the data gets there

The watch never touches Ambient Weather and carries no keys. The same GitHub
Action that draws the frame every ten minutes also publishes

```
https://horseshoestation.github.io/horseshoe-station/watch.json
```

— about 800 bytes, flat, already computed: see `renderer/watch_build.py` for
what every key means. The face pulls it from a background service on Connect
IQ's five-minute clock (the shortest a watch face is allowed); the glance and
the app pull it in the foreground while you are looking at them.

Because the frame renders on its own ten-minute cycle, a fresh download can
still be a ten-minute-old sky. The face reports the age of the *reading*, not
the age of the fetch, and only once it exceeds 25 minutes.

## Two palettes

The frame is six inks on cream paper. On an AMOLED watch a cream screen is a
battery bill and a lantern at 3 a.m., so the default inverts: ink-black paper,
cream letters, the four accents lifted to carry on black. **Paper mode**, in
the app's settings in Garmin Connect, reproduces the wall frame exactly.

## Building

Garmin puts device definition files behind an authenticated account, so there
is no offline build. `.github/workflows/watch.yml` does it in CI. One-time
setup:

1. On any machine with the SDK manager, run `connect-iq-sdk-manager agreement
   view` and note the acceptance hash it prints.
2. Make yourself a signing key — this is what identifies the app as yours, so
   keep it and reuse it, or every rebuild installs as a different app:

   ```sh
   openssl genrsa -out developer.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER \
     -in developer.pem -out developer_key.der -nocrypt
   base64 -w0 developer_key.der    # this string goes in the secret
   ```

3. Add four repository secrets under **Settings → Secrets and variables →
   Actions**:

   | Secret | Value |
   |---|---|
   | `GARMIN_USERNAME` | your Garmin account email |
   | `GARMIN_PASSWORD` | its password — the account must not have MFA enabled |
   | `CIQ_AGREEMENT_HASH` | the hash from step 1 |
   | `CIQ_DEVELOPER_KEY_B64` | the base64 string from step 2 |

4. **Actions → Build the watch → Run workflow.** Download the
   `horseshoe-watch` artifact when it goes green.

## Sideloading

Plug the epix in over USB. It mounts as a drive.

- `horseshoe-face.prg` → `GARMIN/Apps/`
- `horseshoe-app.prg` → `GARMIN/Apps/`

Eject, and the watch indexes them on the next wake. The face appears under
**Watch Face → Connect IQ**; the app under the app list, with its glance in the
glance loop.

Settings — paper mode — live in the Garmin Connect phone app under the app's
entry, not on the watch.

## Known edges

- The three `epix2pro*mm` products in each manifest are declared but only
  `epix2` has been built and checked. The layout is written against a 416 px
  reference and scales, so the 42 mm and 51 mm Pros should be close, but
  nobody has looked at them on glass.
- Type is set with the system fonts. The frame's EB Garamond and IM Fell
  English would need converting to Connect IQ bitmap fonts; the labels are
  letter-spaced a glyph at a time to carry some of that feeling in the
  meantime.
- A watch face gets one network fetch per five minutes at best, and Garmin
  will skip it under low battery or heavy load. The last good reading stays on
  screen when a fetch fails, rather than blanking.
