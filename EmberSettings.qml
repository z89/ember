import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "ember"

    StyledText {
        width: parent.width
        text: "Ember"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Left click the bar icon to open the panel. Right click flips between Always on and Scheduled. Temperatures and the schedule are DMS night mode settings, so the Gamma Control tab shows the same values."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showTemperature"
        label: "Show temperature"
        description: "Print the live colour temperature next to the icon while night light is on"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "tintIcon"
        label: "Warm tint"
        description: "Shade the icon towards amber as the display warms, instead of the accent colour"
        defaultValue: true
    }
}
