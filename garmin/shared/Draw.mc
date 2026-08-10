using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;

// The frame's visual grammar, reduced to what a 416 px circle can hold:
// letter-spaced small caps for labels, hairline rules, an antique rose, and
// traces drawn as thin unfilled lines rather than filled areas.
module Draw {

    const DIRS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                  "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];

    // ---- type -------------------------------------------------------------

    // Connect IQ has no letter-spacing, and the eyebrow labels are the whole
    // reason the frame reads as a ship's log rather than a dashboard. So we
    // set them a glyph at a time. Cheap: these strings are five to twelve
    // characters and only redraw on the minute.
    // y is the vertical CENTRE of the line, matching preview.py's "mm" anchor.
    // Connect IQ's drawText anchors at the top, and the real device fonts run
    // taller than the design guessed — on hardware that skew stacked lines on
    // top of each other. Centring here, and spacing call sites by measured
    // font heights, makes overlap impossible rather than merely unlikely.
    function spacedText(dc, x, y, font, text, extra, justify) {
        var chars = text.toUpper();
        var n = chars.length();
        if (n == 0) { return 0; }
        y = y - dc.getFontHeight(font) / 2;

        var widths = new [n];
        var total = 0;
        for (var i = 0; i < n; i += 1) {
            var g = chars.substring(i, i + 1);
            widths[i] = dc.getTextWidthInPixels(g, font);
            total += widths[i];
        }
        total += extra * (n - 1);

        var cx = x;
        if (justify == Graphics.TEXT_JUSTIFY_CENTER) {
            cx = x - total / 2;
        } else if (justify == Graphics.TEXT_JUSTIFY_RIGHT) {
            cx = x - total;
        }

        for (var i = 0; i < n; i += 1) {
            dc.drawText(cx, y, font, chars.substring(i, i + 1), Graphics.TEXT_JUSTIFY_LEFT);
            cx += widths[i] + extra;
        }
        return total;
    }

    // drawText with y as the vertical centre, like preview.py's anchor="mm".
    function textC(dc, x, y, font, text, justify) {
        dc.drawText(x, y - dc.getFontHeight(font) / 2, font, text, justify);
    }

    // A label above a value, the way every cell on the frame is set.
    function stack(dc, x, y, label, labelColor, value, valueColor, labelFont, valueFont) {
        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        spacedText(dc, x, y, labelFont, label, 2, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + dc.getFontHeight(labelFont) - 2, valueFont, value,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---- rules ------------------------------------------------------------

    function rule(dc, x0, x1, y, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x0, y, x1, y);
    }

    // The frame separates blocks with a rule broken by a small diamond.
    function ornament(dc, cx, y, halfWidth, lineColor, markColor) {
        dc.setColor(lineColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cx - halfWidth, y, cx - 7, y);
        dc.drawLine(cx + 7, y, cx + halfWidth, y);
        dc.setColor(markColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, y - 3], [cx + 3, y], [cx, y + 3], [cx - 3, y]]);
    }

    // ---- the mountains ----------------------------------------------------

    // The condition ladder: the same five pressure cuts the frame's Dutch
    // scale reads, spoken the way the high country says them.
    const LADDER = ["STORM", "UNSETTLED", "SHIFTING", "FAIR", "SETTLED"];

    function ladderWord(seg) {
        if (seg == null || seg < 0 || seg > 4) { return "SHIFTING"; }
        return LADDER[seg];
    }

    // The Divide's profile, echoing the Chart page: the Arapahos' double
    // summit left of centre, Neva's shoulder, the long fall to the canyon.
    // 416 px reference coordinates; 82 is the valley floor.
    const RIDGE = [[58, 82], [84, 74], [104, 60], [116, 67], [132, 54],
                   [144, 62], [166, 70], [190, 64], [212, 72], [242, 66],
                   [268, 75], [300, 71], [330, 78], [358, 82]];

    // baseY sits the valley floor; amp compresses the relief (1.0 = full).
    // snow fills the two big summits, for the months that earn it.
    function ridgeline(dc, s, baseY, amp, color, snow) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var px = null;
        var py = null;
        for (var i = 0; i < RIDGE.size(); i += 1) {
            var x = (RIDGE[i][0] * s).toNumber();
            var y = ((baseY - (82 - RIDGE[i][1]) * amp) * s).toNumber();
            if (px != null) { dc.drawLine(px, py, x, y); }
            px = x;
            py = y;
        }
        if (snow) {
            // apex index, left shoulder, right shoulder
            var caps = [[2, 1, 3], [4, 3, 5]];
            for (var c = 0; c < 2; c += 1) {
                var a = RIDGE[caps[c][0]];
                var l = RIDGE[caps[c][1]];
                var r = RIDGE[caps[c][2]];
                var pts = new [3];
                pts[0] = [((l[0] + (a[0] - l[0]) * 0.45) * s).toNumber(),
                          ((baseY - (82 - (l[1] + (a[1] - l[1]) * 0.45)) * amp) * s).toNumber()];
                pts[1] = [(a[0] * s).toNumber(),
                          ((baseY - (82 - a[1]) * amp) * s).toNumber()];
                pts[2] = [((r[0] + (a[0] - r[0]) * 0.45) * s).toNumber(),
                          ((baseY - (82 - (r[1] + (a[1] - r[1]) * 0.45)) * amp) * s).toNumber()];
                dc.fillPolygon(pts);
            }
        }
    }

    // The sun's travel from rise to set, dotted, with the sun at frac along
    // it. frac outside 0..1 (or null) means night: draw the road, not the
    // traveller.
    function sunArc(dc, s, frac, peakY, baseY, dotColor, sunColor) {
        var x0 = (84 * s).toNumber();
        var x1 = (332 * s).toNumber();
        var steps = 39;
        dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i <= steps; i += 3) {
            var t = i.toFloat() / steps;
            var x = x0 + ((x1 - x0) * t).toNumber();
            var y = ((baseY - (baseY - peakY) * Math.sin(t * Math.PI)) * s).toNumber();
            dc.fillCircle(x, y, 1);
        }
        if (frac != null && frac >= 0.0 && frac <= 1.0) {
            var sx = x0 + ((x1 - x0) * frac).toNumber();
            var sy2 = ((baseY - (baseY - peakY) * Math.sin(frac * Math.PI)) * s).toNumber();
            dc.setColor(sunColor, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(sx, sy2, (5 * s).toNumber());
        }
    }

    // ---- the glass --------------------------------------------------------

    function trendArrow(trend) {
        if (trend == null) { return "-"; }
        if (trend >= 2)  { return "^"; }
        if (trend == 1)  { return "/"; }
        if (trend == -1) { return "\\"; }
        if (trend <= -2) { return "v"; }
        return "-";
    }

    // A drawn arrow beats a glyph: the system fonts have no clean diagonal.
    function arrow(dc, cx, cy, size, trend, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var h = size / 2;
        if (trend == null || trend == 0) {
            dc.drawLine(cx - h, cy, cx + h, cy);
            dc.fillPolygon([[cx + h, cy], [cx + h - 5, cy - 4], [cx + h - 5, cy + 4]]);
            return;
        }
        // steep for "fast", shallow for the ordinary case
        var rise = (trend == 2 || trend == -2) ? h : h * 3 / 5;
        var dy = (trend > 0) ? -rise : rise;
        dc.drawLine(cx - h, cy - dy, cx + h, cy + dy);
        var tipx = cx + h;
        var tipy = cy + dy;
        if (trend > 0) {
            dc.fillPolygon([[tipx, tipy], [tipx - 7, tipy + 2], [tipx - 2, tipy + 7]]);
        } else {
            dc.fillPolygon([[tipx, tipy], [tipx - 7, tipy - 2], [tipx - 2, tipy - 7]]);
        }
    }

    // The condition scale, with the current segment picked out by a pointer.
    // pointerUp puts the marker above the line (pointing down at it), which
    // frees the ground beneath for the word — the face needs every row.
    function dutchScale(dc, x, y, w, seg, inkColor, redColor, font, pointerUp) {
        var n = 5;
        var step = w / n;
        dc.setColor(inkColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x, y, x + w, y);
        for (var i = 0; i <= n; i += 1) {
            var tx = x + i * step;
            dc.drawLine(tx, y - 4, tx, y + 4);
        }
        // Only the live word is set; five words across will not fit a 416 px
        // circle, and the neighbours add nothing at a wrist glance anyway.
        if (seg == null) { seg = 2; }
        var cx = x + seg * step + step / 2;
        dc.setColor(redColor, Graphics.COLOR_TRANSPARENT);
        if (pointerUp) {
            dc.fillPolygon([[cx, y - 5], [cx + 5, y - 12], [cx - 5, y - 12]]);
        } else {
            dc.fillPolygon([[cx, y + 5], [cx + 5, y + 12], [cx - 5, y + 12]]);
        }
    }

    // ---- traces -----------------------------------------------------------

    // A thin polyline in a box. Returns [min, max] so the caller can label the
    // axis with the numbers actually drawn rather than a guess.
    // series is typed so the checker knows the indexing below is an Array read;
    // it arrives from the JSON feed as Any.
    function trace(dc, series as Lang.Array<Lang.Number>?, x, y, w, h, color, penWidth) {
        if (series == null || series.size() < 2) { return null; }
        var lo = series[0];
        var hi = series[0];
        // watch_build.py carries the last known value across gaps, so the
        // series is dense by contract and needs no null guard here.
        for (var i = 1; i < series.size(); i += 1) {
            var v = series[i];
            if (v < lo) { lo = v; }
            if (v > hi) { hi = v; }
        }
        var span = hi - lo;
        if (span == 0) { span = 1; }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(penWidth);
        var n = series.size();
        var px = null;
        var py = null;
        for (var i = 0; i < n; i += 1) {
            var v = series[i];
            var cx = x + (w * i) / (n - 1);
            var cy = y + h - ((v - lo) * h) / span;
            if (px != null) { dc.drawLine(px, py, cx, cy); }
            px = cx;
            py = cy;
        }
        return [lo, hi];
    }

    // ---- the rose ---------------------------------------------------------

    function polarX(cx, r, deg) { return cx + r * Math.sin(deg * Math.PI / 180.0); }
    function polarY(cy, r, deg) { return cy - r * Math.cos(deg * Math.PI / 180.0); }

    // Sixteen petals, each scaled by its share of the last 48 hours, with the
    // live wind laid over as a single filled needle.
    function rose(dc, cx, cy, radius, shares as Lang.Array<Lang.Number>?, liveDir,
                  ringColor, petalColor, needleColor) {
        dc.setColor(ringColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, radius);
        dc.drawCircle(cx, cy, radius / 2);

        // cardinals, so the rose can be read without a legend
        for (var i = 0; i < 4; i += 1) {
            var a = i * 90;
            dc.drawLine(polarX(cx, radius - 6, a), polarY(cy, radius - 6, a),
                        polarX(cx, radius, a), polarY(cy, radius, a));
        }

        if (shares != null && shares.size() == 16) {
            var top = 1;
            for (var i = 0; i < 16; i += 1) {
                if (shares[i] > top) { top = shares[i]; }
            }
            dc.setColor(petalColor, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < 16; i += 1) {
                if (shares[i] <= 0) { continue; }
                var len = (radius - 4) * shares[i] / top;
                if (len < 3) { continue; }
                var a = i * 22.5;
                var tipx = polarX(cx, len, a);
                var tipy = polarY(cy, len, a);
                var lx = polarX(cx, len / 4, a - 9);
                var ly = polarY(cy, len / 4, a - 9);
                var rx = polarX(cx, len / 4, a + 9);
                var ry = polarY(cy, len / 4, a + 9);
                dc.fillPolygon([[cx, cy], [lx, ly], [tipx, tipy], [rx, ry]]);
            }
        }

        if (liveDir != null) {
            dc.setColor(needleColor, Graphics.COLOR_TRANSPARENT);
            var a = liveDir;
            var tx = polarX(cx, radius - 2, a);
            var ty = polarY(cy, radius - 2, a);
            var bx1 = polarX(cx, 6, a + 90);
            var by1 = polarY(cy, 6, a + 90);
            var bx2 = polarX(cx, 6, a - 90);
            var by2 = polarY(cy, 6, a - 90);
            dc.fillPolygon([[tx, ty], [bx1, by1], [bx2, by2]]);
        }
    }

    function dirName(deg) {
        if (deg == null) { return "--"; }
        var i = Math.round(deg / 22.5).toNumber() % 16;
        if (i < 0) { i += 16; }
        return DIRS[i];
    }
}
