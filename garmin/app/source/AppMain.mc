using Toybox.Application;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

// The full log. Unlike the face, this runs only while you are looking at it,
// so it fetches in the foreground and keeps the whole document — traces, rose
// and all.
class HorseshoeApp extends Application.AppBase {

    function initialize() {
        Application.AppBase.initialize();
    }

    function onStart(state) {
        Palette.load();
    }

    function onStop(state) {
    }

    function getInitialView() {
        var view = new PagesView();
        return [view, new PagesDelegate(view)];
    }

    (:glance)
    function getGlanceView() {
        return [new HorseshoeGlanceView()];
    }

    function onSettingsChanged() {
        Palette.load();
        WatchUi.requestUpdate();
    }
}

function getApp() {
    return Application.getApp();
}
