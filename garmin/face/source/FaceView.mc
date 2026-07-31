using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

// The station, at wrist scale — mountain edition.
//
//        HORSESHOE STATION
//         .·˙˙☀˙˙·.
//        ▁▂/\▄/\▂▁▂▁          ← the Divide, sun on its true arc
//              10:42
//        THU 30 JUL · 5:58 - 20:17
//        ──────────────────
//    WIND        61°        BARO
//   WSW 11      feels 61    29.94 ↗
//    g 23
//        ─ STORM|…|SETTLED ─
//              FAIR · RISING
//        UV 9 - BURN 15 MIN        ← winter: daylight left
//
// The ridge is the Chart page's Divide; snowcaps November through April.
// Everything above the rule is the watch's own; everything below it came
// from the station on Horseshoe Place.
class HorseshoeFaceView extends WatchUi.WatchFace {

    hidden var lowPower = false;

    function initialize() {
        WatchUi.WatchFace.initialize();
    }

    function onLayout(dc) {
    }

    function onEnterSleep() {
        lowPower = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        lowPower = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Palette.paper(), Palette.paper());
        dc.clear();

        var d = Feed.stored();

        // scale the fixed 416 px design to whatever the device actually is
        var s = h / 416.0;

        drawHeading(dc, cx, s, d);
        drawTime(dc, cx, s);
        drawAlmanacLine(dc, cx, s, d);

        Draw.rule(dc, cx - (150 * s).toNumber(), cx + (150 * s).toNumber(), sy(186, s), Palette.grid());

        if (d == null) {
            dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, sy(230, s), Graphics.FONT_XTINY,
                            "Awaiting the glass", 2, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        drawDeckLog(dc, cx, s, d);
        drawGlassWord(dc, cx, s, d);
        drawFooter(dc, cx, s, d);
    }

    // vertical position from the 416 px reference design
    hidden function sy(v, s) {
        return (v * s).toNumber();
    }

    // November through April the summits wear snow and the sun rides low —
    // the same months the skis come out.
    hidden function isWinter() {
        var m = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT).month;
        return m >= 11 || m <= 4;
    }

    // Where the sun stands between today's rise and set, 0..1, or null when
    // the feed has no sun times. Night falls outside the range and sunArc
    // simply leaves the traveller off the road.
    hidden function sunFrac(d) {
        var sr = Feed.num(d, "sr");
        var ss = Feed.num(d, "ss");
        if (sr == null || ss == null || ss <= sr) { return null; }
        var now = Time.now().value();
        return (now - sr / 1000).toFloat() / ((ss - sr) / 1000).toFloat();
    }

    hidden function drawHeading(dc, cx, s, d) {
        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, sy(30, s), Graphics.FONT_XTINY,
                        "Horseshoe Station", 3, Graphics.TEXT_JUSTIFY_CENTER);
        var winter = isWinter();
        Draw.sunArc(dc, s, sunFrac(d), winter ? 58 : 46, 78,
                    Palette.grid(), Palette.gold());
        Draw.ridgeline(dc, s, 82, 1.0, Palette.ink(), winter);
    }

    hidden function drawTime(dc, cx, s) {
        var clock = System.getClockTime();
        var hour = clock.hour;
        var suffix = "";
        if (!System.getDeviceSettings().is24Hour) {
            suffix = (hour >= 12) ? "PM" : "AM";
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var text = hour.format("%02d") + ":" + clock.min.format("%02d");

        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, sy(80, s), Graphics.FONT_NUMBER_HOT, text,
                    Graphics.TEXT_JUSTIFY_CENTER);

        if (!suffix.equals("")) {
            dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + (86 * s).toNumber(), sy(92, s), Graphics.FONT_XTINY,
                        suffix, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    hidden function drawAlmanacLine(dc, cx, s, d) {
        var now = Time.Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var line = now.day_of_week.toUpper() + " " + now.day.format("%d") + " " + now.month.toUpper();

        var sr = hhmm(Feed.num(d, "sr"));
        var ss = hhmm(Feed.num(d, "ss"));
        if (sr != null && ss != null) {
            line = line + "  " + sr + " - " + ss;
        }

        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, sy(162, s), Graphics.FONT_XTINY, line, 1,
                        Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Three columns: the wind on the left, the temperature holding the middle,
    // the glass on the right — the same order the frame reads in.
    hidden function drawDeckLog(dc, cx, s, d) {
        var leftX = cx - (118 * s).toNumber();
        var rightX = cx + (118 * s).toNumber();
        var top = sy(200, s);

        // centre: the number you actually looked down for
        var temp = Feed.num(d, "temp");
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, top - (8 * s).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
                    Feed.whole(temp) + "°", Graphics.TEXT_JUSTIFY_CENTER);

        var feels = Feed.num(d, "feels");
        if (feels != null) {
            dc.setColor(Palette.red(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, top + (52 * s).toNumber(), Graphics.FONT_XTINY,
                            "feels " + Feed.whole(feels), 1, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // left: wind
        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, leftX, top, Graphics.FONT_XTINY, "Wind", 2,
                        Graphics.TEXT_JUSTIFY_CENTER);
        var dirn = Feed.num(d, "dirn");
        if (dirn == null) { dirn = "--"; }
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX, top + (18 * s).toNumber(), Graphics.FONT_TINY,
                    dirn + " " + Feed.whole(Feed.num(d, "wind")),
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Palette.red(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX, top + (44 * s).toNumber(), Graphics.FONT_XTINY,
                    "g " + Feed.whole(Feed.num(d, "gust")),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // right: the barometer and where it is going
        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, rightX, top, Graphics.FONT_XTINY, "Baro", 2,
                        Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(rightX, top + (18 * s).toNumber(), Graphics.FONT_TINY,
                    Feed.twoDp(Feed.num(d, "bar")), Graphics.TEXT_JUSTIFY_CENTER);

        var trend = Feed.num(d, "trend");
        Draw.arrow(dc, rightX, top + (52 * s).toNumber(), (26 * s).toNumber(),
                   trend, Palette.trendColor(trend));
    }

    // The condition ladder, and the pointer that says which rung we live on.
    hidden function drawGlassWord(dc, cx, s, d) {
        var seg = Feed.num(d, "dutch");
        if (seg == null) { seg = segFromWord(Feed.num(d, "dutchw")); }
        var w = (216 * s).toNumber();
        Draw.dutchScale(dc, cx - w / 2, sy(288, s), w, seg,
                        Palette.grid(), Palette.red(), Graphics.FONT_XTINY);

        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, sy(304, s), Graphics.FONT_XTINY,
                        Draw.ladderWord(seg), 3, Graphics.TEXT_JUSTIFY_CENTER);

        var tw = Feed.num(d, "trendw");
        if (tw != null) {
            dc.setColor(Palette.trendColor(Feed.num(d, "trend")), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, sy(326, s), Graphics.FONT_XTINY, tw, 2,
                            Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // A live warning outranks the fire stage, which outranks the season's own
    // line: UV and burn time above treeline in summer, daylight left on the
    // snow in winter. Rain is the fallback when nothing else has a claim.
    hidden function drawFooter(dc, cx, s, d) {
        var alert = Feed.num(d, "alert");
        var fire = Feed.num(d, "fire");
        var text = null;
        var color = Palette.dim();

        if (alert != null) {
            text = alert;
            color = Palette.red();
        } else if (fire != null) {
            text = fire;
            color = Palette.gold();
        } else if (isWinter()) {
            var ss = Feed.num(d, "ss");
            var left = (ss != null) ? (ss / 1000 - Time.now().value()) : null;
            if (left != null && left > 0) {
                var hrs = left / 3600;
                var mins = (left % 3600) / 60;
                text = "daylight " + hrs.format("%d") + " h " + mins.format("%02d") + " m left";
                color = Palette.gold();
            }
        } else {
            var uv = Feed.num(d, "uv");
            if (uv != null && uv >= 3) {
                var burn = (uv >= 11) ? 10 : (uv >= 8) ? 15 : (uv >= 6) ? 25 : 45;
                text = "UV " + Feed.whole(uv) + " - burn " + burn.format("%d") + " min";
                color = Palette.gold();
            }
        }
        if (text == null) {
            text = "rain " + Feed.twoDp(Feed.num(d, "rain")) + " in";
            color = Palette.blue();
        }

        if (text.length() > 30) { text = text.substring(0, 30); }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, sy(352, s), Graphics.FONT_XTINY, text, 1,
                        Graphics.TEXT_JUSTIFY_CENTER);

        // How old the sky is. Not how old the fetch is — the frame renders on
        // its own ten-minute clock, so a fresh download can still be stale air.
        // Suppressed in always-on, where every lit pixel is battery.
        var age = Feed.dataAgeMinutes(d);
        if (!lowPower && age != null && age > 25) {
            dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, sy(374, s), Graphics.FONT_XTINY,
                            age.format("%d") + " min old", 1, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    hidden function segFromWord(word) {
        if (word == null) { return 2; }
        if (word.equals("STORM")) { return 0; }
        if (word.equals("REGEN")) { return 1; }
        if (word.equals("VERANDERLYK")) { return 2; }
        if (word.equals("MOOI WEER")) { return 3; }
        return 4;
    }

    hidden function hhmm(ms) {
        if (ms == null) { return null; }
        var moment = new Time.Moment(ms / 1000);
        var info = Time.Gregorian.info(moment, Time.FORMAT_SHORT);
        return info.hour.format("%d") + ":" + info.min.format("%02d");
    }
}
