using Toybox.Application;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;

// One small flat JSON, published beside the frame's own pages every ten
// minutes by the same GitHub Action. The watch holds no keys and does no
// arithmetic it can avoid — see renderer/watch_build.py for what each key is.
//
// (:background) because the face's temporal service calls URL,
// requestOptions and compact — without the annotation the compiler strips
// this module from the background image and the service dies at runtime
// with Symbol Not Found, silently, every five minutes.
(:background)
module Feed {

    const URL = "https://horseshoestation.github.io/horseshoe-station/watch.json";

    const KEY_DATA = "hs";      // the face's scalars, written by the background service
    const KEY_WHEN = "hsAt";    // when we stored them, epoch seconds
    const KEY_FULL = "hsFull";  // the whole document, written by the app in the foreground

    // The app keeps its own copy so a background delivery can never overwrite
    // the traces and the rose with a payload that never carried them.
    function storeFull(data) {
        if (data == null) { return; }
        Application.Storage.setValue(KEY_FULL, data);
        Application.Storage.setValue(KEY_WHEN, Time.now().value());
    }

    function storedFull() {
        var d = Application.Storage.getValue(KEY_FULL);
        if (d != null) { return d; }
        return Application.Storage.getValue(KEY_DATA);
    }

    // Everything the watch face draws. The full app pulls the whole document,
    // but background data has a modest ceiling and the arrays are most of the
    // bytes, so the face's service returns only these.
    const FACE_KEYS = [
        "t", "temp", "feels", "hum", "hi", "lo",
        "wind", "gust", "dirn", "maxgust",
        "bar", "trend", "trendw", "dutch", "dutchw",
        "rain", "uv", "aqi", "fire", "alert", "sr", "ss"
    ];

    function requestOptions() {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Accept" => "application/json" },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    // Copy just the scalars the face needs. Guards against a key the renderer
    // hasn't published yet, so an older watch build survives a newer feed.
    function compact(data) {
        if (data == null) { return null; }
        var out = {};
        for (var i = 0; i < FACE_KEYS.size(); i += 1) {
            var k = FACE_KEYS[i];
            if (data.hasKey(k)) { out.put(k, data.get(k)); }
        }
        return out;
    }

    function store(data) {
        if (data == null) { return; }
        Application.Storage.setValue(KEY_DATA, data);
        Application.Storage.setValue(KEY_WHEN, Time.now().value());
    }

    function stored() {
        return Application.Storage.getValue(KEY_DATA);
    }

    // Minutes since we last stored anything, or null if we never have.
    function ageMinutes() {
        var at = Application.Storage.getValue(KEY_WHEN);
        if (at == null) { return null; }
        var secs = Time.now().value() - at;
        if (secs < 0) { secs = 0; }
        return secs / 60;
    }

    // The feed itself carries the moment it was rendered. That is the number
    // worth showing: a watch that fetched two minutes ago is still looking at
    // a ten-minute-old sky.
    function dataAgeMinutes(d) {
        if (d == null || !d.hasKey("t") || d.get("t") == null) { return null; }
        var thenSec = d.get("t") / 1000;
        var secs = Time.now().value() - thenSec;
        if (secs < 0) { secs = 0; }
        return secs / 60;
    }

    function num(d, key) {
        if (d == null || !d.hasKey(key)) { return null; }
        return d.get(key);
    }

    function str(d, key) {
        var v = num(d, key);
        if (v == null) { return null; }
        return v.toString();
    }

    // Round to whole degrees/mph without dragging in a float formatter.
    function whole(v) {
        if (v == null) { return "--"; }
        if (v instanceof Lang.Number) { return v.toString(); }
        return Math.round(v).format("%d");
    }

    function oneDp(v) {
        if (v == null) { return "--"; }
        return v.format("%.1f");
    }

    function twoDp(v) {
        if (v == null) { return "--"; }
        return v.format("%.2f");
    }
}
