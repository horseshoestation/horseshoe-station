# Horseshoe Station — Inky Frame 7.3" (Pico 2 W aboard)
# Wakes, fetches the current page image from GitHub Pages, shows it, sleeps.
# Buttons A–E fetch specific pages on demand.
#
# Setup: copy this file and secrets.py (from secrets_example.py) to the frame
# with Thonny. Uses Pimoroni's bundled MicroPython (inky_frame + pngdec).

import gc
import inky_frame
import urequests
from picographics import PicoGraphics, DISPLAY_INKY_FRAME_7 as DISPLAY
from pngdec import PNG
import secrets

SLEEP_MINUTES = 10
BUTTON_PAGES = {          # which page each front button summons
    "A": "glass",
    "B": "wind",
    "C": "week",
    "D": "glasshouse",
    "E": "almanack",
}

graphics = PicoGraphics(DISPLAY)


def fetch(path):
    url = secrets.BASE_URL.rstrip("/") + "/" + path
    r = urequests.get(url, headers={"User-Agent": "HorseshoeFrame/1.0"})
    try:
        if r.status_code != 200:
            raise OSError("HTTP %d" % r.status_code)
        data = r.content
    finally:
        r.close()
    return data


def show(png_bytes):
    png = PNG(graphics)
    png.open_RAM(png_bytes)
    png.decode(0, 0)
    graphics.update()          # ~12 s Spectra 6 refresh


def pick_target():
    # woken by a button? show that page; otherwise the rotation's current page
    for name in BUTTON_PAGES:
        if getattr(inky_frame, "button_" + name.lower()).read():
            return "page-%s.png" % BUTTON_PAGES[name]
    return "current.png"


def main():
    inky_frame.led_busy.on()
    try:
        inky_frame.pcf_to_pico_rtc()          # keep the clock honest
        target = pick_target()
        try:
            from network_manager import NetworkManager
            import uasyncio
            nm = NetworkManager(secrets.WIFI_COUNTRY, status_handler=None)
            uasyncio.get_event_loop().run_until_complete(
                nm.client(secrets.WIFI_SSID, secrets.WIFI_PSK))
        except ImportError:
            # older images: plain WLAN connect
            import network, time
            wlan = network.WLAN(network.STA_IF)
            wlan.active(True)
            wlan.connect(secrets.WIFI_SSID, secrets.WIFI_PSK)
            for _ in range(30):
                if wlan.isconnected():
                    break
                time.sleep(1)
            if not wlan.isconnected():
                raise OSError("wifi")
        gc.collect()
        show(fetch(target))
    except Exception as e:
        # leave the last page standing; blink the warn LED briefly
        print("frame error:", e)
    finally:
        inky_frame.led_busy.off()
        inky_frame.sleep_for(SLEEP_MINUTES)   # deep sleep; RTC wakes us


main()
