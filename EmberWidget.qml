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

    // Three user-facing modes, mapped onto the two flags DMS keeps:
    //
    //   Always on   nightModeEnabled && !nightModeAutoEnabled   hold the night temperature
    //   Scheduled   nightModeEnabled &&  nightModeAutoEnabled   neutral by day, warm by night
    //   Off        !nightModeEnabled                            display stays neutral
    readonly property bool nightActive: DisplayService.nightModeEnabled
    readonly property bool alwaysOn: nightActive && !SessionData.nightModeAutoEnabled
    readonly property bool scheduled: nightActive && SessionData.nightModeAutoEnabled
    readonly property int modeIndex: !nightActive ? 2 : (alwaysOn ? 0 : 1)

    readonly property int liveTemp: DisplayService.gammaCurrentTemp
    readonly property int nightTemp: SessionData.nightModeTemperature || 4500
    readonly property int dayTemp: SessionData.nightModeHighTemperature || 6500

    // Both sliders share one range so equal thumb positions mean equal kelvin.
    readonly property int tempMin: 2000
    readonly property int tempMax: 6500
    readonly property int tempStep: 100

    readonly property bool showTemp: pluginData.showTemperature !== undefined ? pluginData.showTemperature : true
    readonly property bool tintIcon: pluginData.tintIcon !== undefined ? pluginData.tintIcon : true

    function setMode(index) {
        switch (index) {
        case 0:
            SessionData.setNightModeAutoEnabled(false);
            if (!DisplayService.nightModeEnabled)
                DisplayService.enableNightMode();
            break;
        case 1:
            SessionData.setNightModeAutoEnabled(true);
            if (!DisplayService.nightModeEnabled)
                DisplayService.enableNightMode();
            break;
        case 2:
            if (DisplayService.nightModeEnabled)
                DisplayService.disableNightMode();
            break;
        }
    }

    // ---- live preview ------------------------------------------------------
    //
    // While a slider moves, the value is pushed straight to the gamma daemon
    // as low == high, which it renders as a constant regardless of schedule.
    // Nothing is persisted until the slider has been still for `interval`.
    // The commit goes through the SessionData setters, whose change signals
    // make DisplayService re-run the current mode and restore the real values.
    property int previewTemp: 0
    property int pendingNight: -1
    property int pendingDay: -1

    function previewTemperature(kelvin) {
        if (!nightActive || !DisplayService.gammaControlAvailable)
            return;
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
            DisplayService.evaluateNightMode();
    }

    Timer {
        id: commitTimer
        interval: 1200
        repeat: false
        onTriggered: root.commitPending()
    }

    // ---- presentation ------------------------------------------------------

    // 0 at the day temperature, 1 at the night temperature.
    readonly property real warmth: {
        if (!nightActive)
            return 0;
        if (alwaysOn || liveTemp <= 0 || dayTemp <= nightTemp)
            return 1;
        return Math.max(0, Math.min(1, (dayTemp - liveTemp) / (dayTemp - nightTemp)));
    }

    readonly property bool fading: scheduled && warmth > 0.02 && warmth < 0.98

    readonly property color idleColor: Theme.widgetTextColor
    readonly property color warmColor: Qt.rgba(1.0, 0.72, 0.36, 1.0)
    readonly property color pillColor: {
        if (!nightActive)
            return idleColor;
        if (!tintIcon)
            return Theme.primary;
        return Qt.tint(Theme.primary, Qt.rgba(warmColor.r, warmColor.g, warmColor.b, warmth));
    }

    readonly property string pillIcon: {
        if (!nightActive)
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
        if (!DisplayService.gammaControlAvailable)
            return "Gamma control unavailable";
        if (!nightActive)
            return "Off";
        if (previewTemp > 0)
            return "Previewing " + previewTemp + "K";
        if (alwaysOn)
            return "Always on, holding " + nightTemp + "K";
        if (fading)
            return "Fading, now " + liveTemp + "K";
        if (DisplayService.gammaIsDay)
            return "Scheduled. Daytime " + liveTemp + "K, warms to " + nightTemp + "K from " + fmtTime(DisplayService.gammaSunsetTime);
        return "Scheduled. Night " + liveTemp + "K, back to " + dayTemp + "K at " + fmtTime(DisplayService.gammaSunriseTime);
    }

    readonly property string modeHint: {
        switch (modeIndex) {
        case 0:
            return "Holding the night temperature around the clock.";
        case 1:
            return "Neutral by day. Warms from sunset " + fmtTime(DisplayService.gammaSunsetTime) + ", back to neutral at sunrise " + fmtTime(DisplayService.gammaSunriseTime) + ".";
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
                filled: root.nightActive
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
                visible: root.showTemp && root.nightActive && root.liveTemp > 0
                text: (root.previewTemp > 0 ? root.previewTemp : root.liveTemp) + "K"
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
                filled: root.nightActive
                size: root.iconSize
                color: root.pillColor
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.showTemp && root.nightActive && root.liveTemp > 0
                text: Math.round(root.liveTemp / 100) / 10 + "k"
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
                            enabled: DisplayService.gammaControlAvailable
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
    ccWidgetIsActive: alwaysOn || (scheduled && !DisplayService.gammaIsDay)
    ccWidgetIsToggle: true

    onCcWidgetToggled: root.setMode(root.alwaysOn ? 1 : 0)
}
