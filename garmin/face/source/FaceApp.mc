using Toybox.Application;
using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

// The face itself never reaches the network. A background service wakes on the
// system's five-minute clock — the shortest interval Connect IQ allows a watch
// face — pulls the feed the frame already publishes, and hands back only the
// scalars the face draws.
(:background)
class HorseshoeService extends System.ServiceDelegate {

    function initialize() {
        System.ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        Communications.makeWebRequest(Feed.URL, null, Feed.requestOptions(), method(:onFeed));
    }

    // The signature has to match Communications' callback type exactly, or the
    // type checker rejects the method reference at the call site.
    function onFeed(
        code as Lang.Number,
        data as Null or Lang.Dictionary or Lang.String or PersistedContent.Iterator
    ) as Void {
        if (code == 200 && data != null) {
            Background.exit(Feed.compact(data));
        } else {
            // Handing back null leaves the last good reading in place; a dead
            // wifi should not blank the glass.
            Background.exit(null);
        }
    }
}

(:background)
class HorseshoeFaceApp extends Application.AppBase {

    function initialize() {
        Application.AppBase.initialize();
    }

    function onStart(state) {
        Palette.load();
        scheduleFetch();
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [new HorseshoeFaceView()];
    }

    function getServiceDelegate() {
        return [new HorseshoeService()];
    }

    // Called when the settings page changes paper mode.
    function onSettingsChanged() {
        Palette.load();
        WatchUi.requestUpdate();
    }

    function onBackgroundData(data) {
        if (data != null) {
            Feed.store(data);
        }
        scheduleFetch();
        WatchUi.requestUpdate();
    }

    // Re-arm after every delivery; a temporal event is consumed when it fires.
    function scheduleFetch() {
        if (!(Toybox has :Background)) { return; }
        try {
            var due = Background.getTemporalEventRegisteredTime();
            if (due == null) {
                Background.registerForTemporalEvent(new Time.Duration(300));
            }
        } catch (e) {
            // Some builds reject a five-minute request when another app already
            // holds the slot. Nothing to do but keep showing the last reading.
        }
    }
}
