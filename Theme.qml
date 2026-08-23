import Quickshell.Io
import QtQuick

QtObject {
    id: theme

    /*
     * --------------------------------------------------
     * UNIVERSAL RADIAL OVERVIEW THEME CONTRACT
     * --------------------------------------------------
     *
     * Radial Overview only consumes semantic properties.
     * The source could eventually be:
     *
     *   - custom JSON
     *   - Omarchy adapter
     *   - Noctalia adapter
     *   - DMS adapter
     *   - Stylix / Matugen / pywal adapter
     *
     * The UI itself never needs to know the source.
     */

    readonly property color background:
        palette.background

    readonly property color surface:
        palette.surface

    readonly property color surfaceHover:
        palette.surfaceHover

    readonly property color foreground:
        palette.foreground

    readonly property color muted:
        palette.muted

    readonly property color accent:
        palette.accent

    readonly property color accentSecondary:
        palette.accentSecondary

    readonly property color border:
        palette.border

    readonly property color dropHighlight:
        palette.dropHighlight


    /*
     * --------------------------------------------------
     * THEME FILE
     * --------------------------------------------------
     *
     * Qt.resolvedUrl() makes this path relative to
     * Theme.qml rather than wherever qs was launched.
     */

    property FileView themeFile: FileView {
        id: fileView

        path:
            Qt.resolvedUrl(
                "./themes/default.json"
            )

        preload: true
        watchChanges: true

        /*
         * Quickshell emits fileChanged when the file
         * changes on disk.
         *
         * reload() then causes JsonAdapter to receive
         * the new JSON values.
         */
        onFileChanged: {
            console.log(
                "Radial Overview: theme file changed"
            )

            reload()
        }

        onLoaded: {
            console.log(
                "Radial Overview: theme loaded"
            )
        }

        onLoadFailed: function(error) {
            console.log(
                "Radial Overview: theme load failed:",
                error
            )
        }


        /*
         * --------------------------------------------------
         * JSON ADAPTER
         * --------------------------------------------------
         *
         * These strings correspond directly to the keys
         * in themes/default.json.
         *
         * JsonAdapter automatically updates them whenever
         * FileView reloads the JSON.
         */

        JsonAdapter {
            id: palette

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


            /*
             * Diagnostics.
             *
             * Once we're happy with V1 we can remove these.
             */

            onAccentChanged: {
                console.log(
                    "Radial Overview: accent changed to",
                    accent
                )
            }

            onBackgroundChanged: {
                console.log(
                    "Radial Overview: background changed to",
                    background
                )
            }
        }
    }
}
