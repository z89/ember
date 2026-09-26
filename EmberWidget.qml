import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Ember: a night light pill for the DankBar.
//
// Everything persistent lives in DMS's own session state (SessionData.nightMode*),
// so the DMS Gamma Control settings tab, the `dms ipc call night` CLI and this
// panel all read and write the same values. Ember adds no state of its own beyond
// the two cosmetic options on its settings page.
PluginComponent {
    id: root

    // DMS split night-mode controls out of DisplayService. Older releases
    // still expose them there, so keep supporting both service layouts.
    readonly property var nightService: typeof NightModeService !== "undefined" ? NightModeService : DisplayService

    // Three user-facing modes, mapped onto the two flags DMS keeps:
    //
    //   Always on   nightModeEnabled && !nightModeAutoEnabled   hold the night temperature
    //   Scheduled   nightModeEnabled &&  nightModeAutoEnabled   neutral by day, warm by night
    //   Off        !nightModeEnabled                            display stays neutral
    readonly property bool nightActive: nightService.nightModeEnabled
    readonly property bool alwaysOn: nightActive && !SessionData.nightModeAutoEnabled
    readonly property bool scheduled: nightActive && SessionData.nightModeAutoEnabled
    // While a fade runs the UI already shows where it is heading.
    readonly property int modeIndex: fadeBusy ? fadeMode : (!nightActive ? 2 : (alwaysOn ? 0 : 1))
    readonly property bool nightShown: fadeBusy ? fadeMode !== 2 : nightActive

    readonly property int liveTemp: nightService.gammaCurrentTemp
    readonly property int nightTemp: SessionData.nightModeTemperature || 4500
    readonly property int dayTemp: SessionData.nightModeHighTemperature || 6500

    // Both sliders share one range so equal thumb positions mean equal kelvin.
    readonly property int tempMin: 2000
    readonly property int tempMax: 6500
    readonly property int tempStep: 100

    readonly property bool showTemp: pluginData.showTemperature !== undefined ? pluginData.showTemperature : true
    readonly property bool tintIcon: pluginData.tintIcon !== undefined ? pluginData.tintIcon : true

    // The instant path: flip the DMS flags and let nightService apply them.
    // setMode below walks the temperature there first so nothing snaps.
    function applyMode(index) {
        switch (index) {
        case 0:
            SessionData.setNightModeAutoEnabled(false);
            if (!nightService.nightModeEnabled)
                nightService.enableNightMode();
            break;
        case 1:
            SessionData.setNightModeAutoEnabled(true);
            if (!nightService.nightModeEnabled)
                nightService.enableNightMode();
            break;
        case 2:
            if (nightService.nightModeEnabled)
                nightService.disableNightMode();
            else
                setRampEnabled(false); // a primed ramp DMS never knew about
            break;
        }
    }

    function setMode(index) {
        if (index === modeIndex)
            return;
        if (fadeMs <= 0 || !nightService.gammaControlAvailable) {
            cancelFade();
            applyMode(index);
            return;
        }
        const from = shownKelvin();
        cancelFade();
        fadeMode = index;
        fadeBusy = true;
        switch (index) {
        case 2:
            // Cool to neutral, then let DMS drop the ramp. At 6500K that is invisible.
            fadeTemperature(from, neutralTemp, () => applyMode(2));
            break;
        case 0:
            primeRamp(() => fadeTemperature(from, nightTemp, () => applyMode(0)));
            break;
        case 1:
            // Where the schedule will hold depends on the time of day, so set the
            // schedule first and ask the daemon, then fade to that value.
            primeRamp(() => applySchedule(isDay => fadeTemperature(from, isDay ? dayTemp : nightTemp, () => applyMode(1))));
            break;
        }
    }

    // ---- live preview ------------------------------------------------------
    //
    // While a slider moves, the value is pushed straight to the gamma daemon
    // as low == high, which it renders as a constant regardless of schedule.
    // Nothing is persisted until the slider has been still for `interval`.
    // The commit goes through the SessionData setters, whose change signals
    // make nightService re-run the current mode and restore the real values.
    property int previewTemp: 0
    property int pendingNight: -1
    property int pendingDay: -1

    function previewTemperature(kelvin) {
        if (!nightActive || !nightService.gammaControlAvailable)
            return;
        if (fadeBusy)
            cancelFade(); // the slider wins; commitPending restores the mode
        previewTemp = kelvin;
        DMSService.sendRequest("wayland.gamma.setTemperature", {
            "low": kelvin,
            "high": kelvin
        }, response => {
            if (response.error)
                console.warn("Ember: preview failed:", response.error);
        });
    }

    function commitPending() {
        previewTemp = 0;
        if (pendingNight > 0) {
            SessionData.setNightModeTemperature(pendingNight);
            pendingNight = -1;
        }
        if (pendingDay > 0) {
            SessionData.setNightModeHighTemperature(pendingDay);
            pendingDay = -1;
        }
        // A setter called with an unchanged value emits nothing, so the
        // preview would stick. Re-evaluate explicitly to be sure.
        if (nightActive)
            nightService.evaluateNightMode();
    }

    Timer {
        id: commitTimer
        interval: 1200
        repeat: false
        onTriggered: root.commitPending()
    }

    // ---- fades -------------------------------------------------------------
    //
    // DMS switches the ramp on and off in one step. Ember instead walks the
    // temperature to where the next mode will hold it and only then lets DMS
    // take over, at that exact value, so the screen never jumps. Only changes
    // made through Ember fade; the gamma tab and `dms ipc call night` still snap.
    //
    // Turning on from off: the ramp is brought up flat at 6500K first (the same
    // as no ramp), then warmed. Turning off: cooled to 6500K, then dropped.
    readonly property int neutralTemp: 6500
    readonly property int fadeMs: pluginData.fadeDuration !== undefined ? pluginData.fadeDuration : 800
    property bool fadeBusy: false
    property int fadeMode: -1
    property int fadeTemp: 0
    property bool rampPrimed: false
    property real fadeFrom: 0
    property real fadeTo: 0
    property int fadeElapsed: 0
    property var fadeThen: null

    // The kelvin the screen is showing right now, as far as Ember knows.
    function shownKelvin() {
        if (fadeBusy || rampPrimed)
            return fadeTemp > 0 ? fadeTemp : neutralTemp;
        if (!nightActive)
            return neutralTemp;
        return liveTemp > 0 ? liveTemp : nightTemp;
    }

    function sendTemp(kelvin, then) {
        DMSService.sendRequest("wayland.gamma.setTemperature", {
            "low": kelvin,
            "high": kelvin
        }, response => {
            if (response.error)
                console.warn("Ember: set temperature failed:", response.error);
            if (then)
                then(!response.error);
        });
    }

    function setRampEnabled(enabled, then) {
        DMSService.sendRequest("wayland.gamma.setEnabled", {
            "enabled": enabled
        }, response => {
            if (response.error)
                console.warn("Ember: set enabled failed:", response.error);
            if (then)
                then(!response.error);
        });
    }

    // Bring the ramp up flat at neutral so its first frame matches the off
    // state, then hand over. A no-op while night light is already on.
    function primeRamp(then) {
        if (nightActive || rampPrimed) {
            then();
            return;
        }
        fadeTemp = neutralTemp;
        sendTemp(neutralTemp, ok => {
            if (!ok) {
                abortFade();
                return;
            }
            setRampEnabled(true, ok => {
                if (!ok) {
                    abortFade();
                    return;
                }
                rampPrimed = true;
                then();
            });
        });
    }

    // Push the schedule DMS is about to use, minus the temperatures (the ramp
    // is flat, low == high, so nothing on screen changes), then ask the daemon
    // whether it is day. DMS sends the same schedule again afterwards.
    function applySchedule(then) {
        const finish = () => DMSService.sendRequest("wayland.gamma.getState", null, response => then(response.error ? true : (response.result?.isDay ?? true)));
        const mode = SessionData.nightModeAutoMode || "time";
        if (mode === "time") {
            const hm = (h, m) => String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0");
            DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                "use": false
            }, () => {
                DMSService.sendRequest("wayland.gamma.setManualTimes", {
                    "sunrise": hm(SessionData.nightModeEndHour, SessionData.nightModeEndMinute),
                    "sunset": hm(SessionData.nightModeStartHour, SessionData.nightModeStartMinute),
                    "durationMinutes": SessionData.nightModeTransitionMinutes
                }, finish);
            });
            return;
        }
        DMSService.sendRequest("wayland.gamma.setManualTimes", {
            "sunrise": null,
            "sunset": null
        }, () => {
            if (SessionData.nightModeUseIPLocation) {
                DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                    "use": true
                }, finish);
            } else if (SessionData.latitude !== 0.0 && SessionData.longitude !== 0.0) {
                DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                    "use": false
                }, () => {
                    DMSService.sendRequest("wayland.gamma.setLocation", {
                        "latitude": SessionData.latitude,
                        "longitude": SessionData.longitude
                    }, finish);
                });
            } else {
                finish();
            }
        });
    }

    function fadeTemperature(from, to, then) {
        fadeFrom = from;
        fadeTo = to;
        fadeElapsed = 0;
        fadeThen = then;
        fadeTimer.restart();
    }

    Timer {
        id: fadeTimer
        interval: 33
        repeat: true
        onTriggered: root.fadeTick()
    }

    function fadeTick() {
        fadeElapsed += fadeTimer.interval;
        const t = (fadeMs <= 0 || fadeFrom === fadeTo) ? 1 : Math.min(1, fadeElapsed / fadeMs);
        const eased = 0.5 - Math.cos(t * Math.PI) / 2;
        fadeTemp = Math.round(fadeFrom + (fadeTo - fadeFrom) * eased);
        sendTemp(fadeTemp);
        if (t < 1)
            return;
        fadeTimer.stop();
        const then = fadeThen;
        fadeThen = null;
        fadeBusy = false;
        fadeMode = -1;
        rampPrimed = false;
        if (then)
            then();
    }

    // Stop a fade where it is. The screen keeps the last value sent; whatever
    // runs next starts from there (see shownKelvin).
    function cancelFade() {
        fadeTimer.stop();
        fadeThen = null;
        fadeBusy = false;
        fadeMode = -1;
    }

    // A request failed mid-fade. Drop back to the state DMS believes in.
    function abortFade() {
        cancelFade();
        if (rampPrimed && !nightActive)
            setRampEnabled(false);
        rampPrimed = false;
        if (nightActive)
            nightService.evaluateNightMode();
    }

    // ---- presentation ------------------------------------------------------

    // 0 at the day temperature, 1 at the night temperature.
    function warmthOf(kelvin) {
        if (kelvin <= 0 || dayTemp <= nightTemp)
            return 1;
        return Math.max(0, Math.min(1, (dayTemp - kelvin) / (dayTemp - nightTemp)));
    }

    readonly property real warmth: {
        if (!nightShown)
            return 0;
        if (fadeBusy)
            return warmthOf(fadeTemp);
        if (alwaysOn)
            return 1;
        return warmthOf(liveTemp);
    }

    readonly property bool fading: scheduled && warmth > 0.02 && warmth < 0.98

    readonly property color idleColor: Theme.widgetTextColor
    readonly property color warmColor: Qt.rgba(1.0, 0.72, 0.36, 1.0)
    readonly property color pillColor: {
        if (!nightShown)
            return idleColor;
        if (!tintIcon)
            return Theme.primary;
        return Qt.tint(Theme.primary, Qt.rgba(warmColor.r, warmColor.g, warmColor.b, warmth));
    }

    readonly property string pillIcon: {
        if (!nightShown)
            return "dark_mode";
        return alwaysOn ? "bedtime" : "nightlight";
    }

    function fmtTime(iso) {
        if (!iso)
            return "--:--";
        const d = new Date(iso);
        if (isNaN(d.getTime()))
            return "--:--";
        return Qt.formatTime(d, "HH:mm");
    }

    readonly property string statusLine: {
        if (!nightService.gammaControlAvailable)
            return "Gamma control unavailable";
        if (fadeBusy)
            return fadeMode === 2 ? "Cooling to neutral" : "Warming to " + fadeTo + "K";
        if (!nightActive)
            return "Off";
        if (previewTemp > 0)
            return "Previewing " + previewTemp + "K";
        if (alwaysOn)
            return "Always on, holding " + nightTemp + "K";
        if (fading)
            return "Fading, now " + liveTemp + "K";
        if (nightService.gammaIsDay)
            return "Scheduled. Daytime " + liveTemp + "K, warms to " + nightTemp + "K from " + fmtTime(nightService.gammaSunsetTime);
        return "Scheduled. Night " + liveTemp + "K, back to " + dayTemp + "K at " + fmtTime(nightService.gammaSunriseTime);
    }

    readonly property string modeHint: {
        switch (modeIndex) {
        case 0:
            return "Holding the night temperature around the clock.";
        case 1:
            return "Neutral by day. Warms from sunset " + fmtTime(nightService.gammaSunsetTime) + ", back to neutral at sunrise " + fmtTime(nightService.gammaSunriseTime) + ".";
        default:
            return "Display stays neutral. Nothing is scheduled.";
        }
    }

    // ---- bar ---------------------------------------------------------------

    // Left click opens the panel. Right click flips Always on <-> Scheduled.
    pillRightClickAction: () => root.setMode(root.alwaysOn ? 1 : 0)

    popoutWidth: 460

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.pillIcon
                filled: root.nightShown
                size: root.iconSize
                color: root.pillColor

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.showTemp && root.nightShown && (root.fadeBusy || root.liveTemp > 0)
                text: (root.fadeBusy ? root.fadeTemp : (root.previewTemp > 0 ? root.previewTemp : root.liveTemp)) + "K"
                font.pixelSize: Theme.fontSizeSmall
                color: root.pillColor
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: root.pillIcon
                filled: root.nightShown
                size: root.iconSize
                color: root.pillColor
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.showTemp && root.nightShown && (root.fadeBusy || root.liveTemp > 0)
                text: Math.round((root.fadeBusy ? root.fadeTemp : root.liveTemp) / 100) / 10 + "k"
                font.pixelSize: Theme.fontSizeSmall
                color: root.pillColor
            }
        }
    }

    // ---- panel -------------------------------------------------------------

    popoutContent: Component {
        PopoutComponent {
            headerText: "Ember"
            detailsText: root.statusLine
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledRect {
                    width: parent.width
                    height: modeCol.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: Theme.floatingWindowNestedSurface
                    border.color: Theme.outlineMedium
                    border.width: Theme.layerOutlineWidth

                    Column {
                        id: modeCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingS

                        // In single mode DankButtonGroup only emits; it never
                        // writes currentIndex itself, so this binding stays live.
                        DankButtonGroup {
                            model: ["Always on", "Scheduled", "Off"]
                            currentIndex: root.modeIndex
                            selectionMode: "single"
                            enabled: nightService.gammaControlAvailable
                            onSelectionChanged: (index, selected) => {
                                if (selected)
                                    root.setMode(index);
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: root.modeHint
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: tempCol.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: Theme.floatingWindowNestedSurface
                    border.color: Theme.outlineMedium
                    border.width: Theme.layerOutlineWidth

                    Column {
                        id: tempCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingM

                        StyledText {
                            text: "Colour temperature"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "Night  " + nightSlider.value + "K"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            DankSlider {
                                id: nightSlider
                                width: parent.width
                                minimum: root.tempMin
                                maximum: root.tempMax
                                step: root.tempStep
                                unit: "K"
                                value: root.nightTemp
                                leftIcon: "bedtime"
                                onSliderValueChanged: newValue => {
                                    root.pendingNight = newValue;
                                    root.previewTemperature(newValue);
                                    commitTimer.restart();
                                }
                                onSliderDragFinished: finalValue => {
                                    root.pendingNight = finalValue;
                                    commitTimer.restart();
                                }

                                // Dragging breaks the value binding; follow
                                // outside edits (settings tab, CLI) by hand.
                                Connections {
                                    target: SessionData
                                    function onNightModeTemperatureChanged() {
                                        if (!nightSlider.isDragging)
                                            nightSlider.value = SessionData.nightModeTemperature;
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "Day  " + daySlider.value + "K"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            DankSlider {
                                id: daySlider
                                width: parent.width
                                minimum: root.tempMin
                                maximum: root.tempMax
                                step: root.tempStep
                                unit: "K"
                                value: root.dayTemp
                                leftIcon: "wb_sunny"
                                onSliderValueChanged: newValue => {
                                    root.pendingDay = newValue;
                                    root.previewTemperature(newValue);
                                    commitTimer.restart();
                                }
                                onSliderDragFinished: finalValue => {
                                    root.pendingDay = finalValue;
                                    commitTimer.restart();
                                }

                                Connections {
                                    target: SessionData
                                    function onNightModeHighTemperatureChanged() {
                                        if (!daySlider.isDragging)
                                            daySlider.value = SessionData.nightModeHighTemperature;
                                    }
                                }
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: root.nightActive ? "Both sliders run " + root.tempMin + "K to " + root.tempMax + "K in " + root.tempStep + "K steps. Drag to see it on screen; the current mode takes back over after you let go." : "Switch to Always on or Scheduled to preview while dragging."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    text: "Right click the bar icon to flip between Always on and Scheduled."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ---- control centre ----------------------------------------------------

    ccWidgetIcon: pillIcon
    ccWidgetPrimaryText: "Ember"
    ccWidgetSecondaryText: statusLine
    ccWidgetIsActive: fadeBusy ? fadeMode === 0 : (alwaysOn || (scheduled && !nightService.gammaIsDay))
    ccWidgetIsToggle: true

    onCcWidgetToggled: root.setMode(root.alwaysOn ? 1 : 0)
}
