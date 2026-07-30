using Toybox.Application;

// The frame is printed on Spectra-6 e-ink: six inks on cream paper. The epix is
// AMOLED, where cream at full screen is both a battery bill and a lantern in a
// dark bedroom. So the default inverts to ink-black paper with cream letters,
// and the four accents are lifted to carry on black. Paper mode reproduces the
// wall frame exactly, for daylight and for the pleasure of it.
//
// (:background) because the face's AppBase calls load() from onStart, and
// onStart also runs when the system spins the app up for its background
// service — an unannotated Palette would kill the service before its
// first fetch.
(:background)
module Palette {

    // dark ("Night Watch") — the default
    const D_PAPER  = 0x000000;
    const D_INK    = 0xF2EFE6;
    const D_RED    = 0xE8564A;
    const D_BLUE   = 0x6FA8DC;
    const D_GOLD   = 0xE8B93A;
    const D_GREEN  = 0x4FB878;
    const D_DIM    = 0x8A8578;
    const D_GRID   = 0x3A3730;

    // paper ("The Frame") — the Spectra-6 inks, unchanged
    const P_PAPER  = 0xF2EFE6;
    const P_INK    = 0x1A1A1A;
    const P_RED    = 0xC0392B;
    const P_BLUE   = 0x2E5F94;
    const P_GOLD   = 0xD4A017;
    const P_GREEN  = 0x2E7D4F;
    const P_DIM    = 0x6B6455;
    const P_GRID   = 0xC9C2AE;

    var paperMode = false;

    function load() {
        var v = null;
        try {
            v = Application.Properties.getValue("paperMode");
        } catch (e) {
            v = null;
        }
        paperMode = (v != null) ? v : false;
    }

    function paper() { return paperMode ? P_PAPER : D_PAPER; }
    function ink()   { return paperMode ? P_INK   : D_INK;   }
    function red()   { return paperMode ? P_RED   : D_RED;   }
    function blue()  { return paperMode ? P_BLUE  : D_BLUE;  }
    function gold()  { return paperMode ? P_GOLD  : D_GOLD;  }
    function green() { return paperMode ? P_GREEN : D_GREEN; }
    function dim()   { return paperMode ? P_DIM   : D_DIM;   }
    function grid()  { return paperMode ? P_GRID  : D_GRID;  }

    // The glance strip is drawn by the system on its own dark background, so it
    // ignores paper mode and always uses the lifted accents.
    function trendColorDark(trend) {
        if (trend == null) { return D_DIM; }
        if (trend < 0) { return D_RED; }
        if (trend > 0) { return D_BLUE; }
        return D_GOLD;
    }

    // A falling glass is the one that wants your attention, so it reads red;
    // rising is blue and calm; steady is gold and unremarkable.
    function trendColor(trend) {
        if (trend == null) { return dim(); }
        if (trend < 0) { return red(); }
        if (trend > 0) { return blue(); }
        return gold();
    }
}
