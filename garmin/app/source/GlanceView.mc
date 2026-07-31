using Toybox.Communications;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.WatchUi;

// The swipe-past summary: one line of station, one line of sky. Glances get a
// sliver of memory and a sliver of screen, so this draws from whatever is
// already in storage and only refreshes if it is looking at something stale.
(:glance)
class HorseshoeGlanceView extends WatchUi.GlanceView {

    hidden var data = null;

    function initialize() {
        WatchUi.GlanceView.initialize();
    }

    function onLayout(dc) {
        data = Feed.storedFull();
        var age = Feed.dataAgeMinutes(data);
        if (data == null || age == null || age > 12) {
            Communications.makeWebRequest(Feed.URL, null, Feed.requestOptions(), method(:onFeed));
        }
    }

    function onFeed(
        code as Lang.Number,
        payload as Null or Lang.Dictionary or Lang.String or PersistedContent.Iterator
    ) as Void {
        if (code == 200 && payload != null) {
            data = payload;
            Feed.storeFull(payload);
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        dc.clear();

        // Three rows spaced by the fonts the device actually has: the strip is
        // only ~60 px tall and guessed offsets overlapped on real hardware.
        var h = dc.getHeight();
        var pad = 4;
        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var hT = dc.getFontHeight(Graphics.FONT_TINY);

        dc.setColor(Palette.D_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, 0, Graphics.FONT_XTINY, "HORSESHOE STATION",
                    Graphics.TEXT_JUSTIFY_LEFT);

        if (data == null) {
            dc.setColor(Palette.D_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, hX, Graphics.FONT_TINY, "awaiting the glass",
                        Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }

        var line = Feed.whole(Feed.num(data, "temp")) + "°  "
                 + Draw.dirName(Feed.num(data, "dir")) + " " + Feed.whole(Feed.num(data, "wind"))
                 + "g" + Feed.whole(Feed.num(data, "gust")) + "  "
                 + Feed.twoDp(Feed.num(data, "bar"));

        var lineTop = hX - 2;
        dc.setColor(Palette.D_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, lineTop, Graphics.FONT_TINY, line, Graphics.TEXT_JUSTIFY_LEFT);

        var trend = Feed.num(data, "trend");
        var tw = Feed.num(data, "trendw");
        if (tw == null) { tw = ""; }
        var alert = Feed.num(data, "alert");
        if (alert != null) {
            dc.setColor(Palette.D_RED, Graphics.COLOR_TRANSPARENT);
            tw = alert;
        } else {
            dc.setColor(Palette.trendColorDark(trend), Graphics.COLOR_TRANSPARENT);
        }
        var thirdTop = lineTop + hT - 2;
        if (thirdTop + hX > h) { thirdTop = h - hX; }
        dc.drawText(pad, thirdTop, Graphics.FONT_XTINY, tw, Graphics.TEXT_JUSTIFY_LEFT);
    }
}
