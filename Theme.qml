import Quickshell.Io
import QtQuick

import "adapters" as Adapters

QtObject {
    id: theme

    /*
     * --------------------------------------------------
     * RADIAL OVERVIEW THEME MANAGER
     * --------------------------------------------------
     *
     * Priority for V1.1:
     *
     *   1. Known environment adapter
     *   2. Generic JSON theme
     *
     * shell.qml knows nothing about the source.
     */

    readonly property string source:
        omarchy.loaded
        ? "omarchy"
        : "default"

    /*
     * --------------------------------------------------
     * OMARCHY ADAPTER
     * --------------------------------------------------
     */

    property Adapters.OmarchyAdapter omarchy:
        Adapters.OmarchyAdapter {
        }

    /*
     * --------------------------------------------------
     * GENERIC JSON FALLBACK
     * --------------------------------------------------
     */

    property FileView defaultThemeFile: FileView {
        id: defaultFile

        path:
            Qt.resolvedUrl(
                "./themes/default.json"
            )

        preload: true
        watchChanges: true

        onFileChanged: {
            console.log(
                "Radial Overview: default theme changed"
            )

            reload()
        }

        JsonAdapter {
            id: fallback

            property string background:
                "#111018"

            property string surface:
                "#1a1822"

            property string surfaceHover:
                "#24202f"

            property string foreground:
                "#ffffff"

            property string muted:
                "#8f8a9d"

            property string accent:
                "#8b5cf6"

            property string accentSecondary:
                "#c084fc"

            property string border:
                "#6d5a8f"

            property string dropHighlight:
                "#362454"
        }
    }

    /*
     * --------------------------------------------------
     * PUBLIC SEMANTIC CONTRACT
     * --------------------------------------------------
     *
     * These are the ONLY properties shell.qml consumes.
     */

    readonly property color background:
        omarchy.loaded
        ? omarchy.background
        : fallback.background

    readonly property color surface:
        omarchy.loaded
        ? omarchy.surface
        : fallback.surface

    readonly property color surfaceHover:
        omarchy.loaded
        ? omarchy.surfaceHover
        : fallback.surfaceHover

    readonly property color foreground:
        omarchy.loaded
        ? omarchy.foreground
        : fallback.foreground

    readonly property color muted:
        omarchy.loaded
        ? omarchy.muted
        : fallback.muted

    readonly property color accent:
        omarchy.loaded
        ? omarchy.accent
        : fallback.accent

    readonly property color accentSecondary:
        omarchy.loaded
        ? omarchy.accentSecondary
        : fallback.accentSecondary

    readonly property color border:
        omarchy.loaded
        ? omarchy.border
        : fallback.border

    readonly property color dropHighlight:
        omarchy.loaded
        ? omarchy.dropHighlight
        : fallback.dropHighlight

    /*
     * Diagnostics for development branch.
     */

    onSourceChanged: {
        console.log(
            "Radial Overview: theme source:",
            source
        )
    }

    onAccentChanged: {
        console.log(
            "Radial Overview: active accent:",
            accent
        )
    }
}
