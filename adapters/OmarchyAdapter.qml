import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
    id: adapter

    /*
     * --------------------------------------------------
     * OMARCHY THEME ADAPTER
     * --------------------------------------------------
     *
     * Omarchy replaces:
     *
     *   ~/.local/state/omarchy/current/theme/
     *
     * during a theme switch.
     *
     * Watching colors.toml directly is therefore fragile.
     *
     * Instead:
     *
     *   check stable theme.name once per second
     *              ↓
     *   theme name changed?
     *              ↓
     *   wait briefly for replacement to finish
     *              ↓
     *   read the new colors.toml
     *
     * No UI code depends on Omarchy.
     */

    readonly property string stateDir:
        Quickshell.env("HOME")
        + "/.local/state/omarchy/current"

    readonly property string themeNameFile:
        stateDir + "/theme.name"

    readonly property string colorsFile:
        stateDir + "/theme/colors.toml"

    /*
     * --------------------------------------------------
     * STATE
     * --------------------------------------------------
     */

    property bool available: false
    property bool loaded: false

    property string themeName: ""

    property int retryCount: 0
    property int maxRetries: 10

    /*
     * --------------------------------------------------
     * SEMANTIC OUTPUT
     * --------------------------------------------------
     */

    property string background: ""
    property string surface: ""
    property string surfaceHover: ""

    property string foreground: ""
    property string muted: ""

    property string accent: ""
    property string accentSecondary: ""

    property string border: ""
    property string dropHighlight: ""

    /*
     * --------------------------------------------------
     * SIMPLE TOML PARSER
     * --------------------------------------------------
     */

    function parseToml(text) {
        const result = {}
        const lines = text.split("\n")

        for (let i = 0; i < lines.length; ++i) {
            let line = lines[i].trim()

            if (line.length === 0)
                continue

            if (line.startsWith("#"))
                continue

            const separator = line.indexOf("=")

            if (separator < 0)
                continue

            const key =
                line.substring(
                    0,
                    separator
                ).trim()

            let value =
                line.substring(
                    separator + 1
                ).trim()

            /*
             * Strip matching surrounding quotes.
             */

            if (value.length >= 2) {
                const first =
                    value.charAt(0)

                const last =
                    value.charAt(
                        value.length - 1
                    )

                if (
                    (first === "\"" && last === "\"")
                    || (first === "'" && last === "'")
                ) {
                    value =
                        value.substring(
                            1,
                            value.length - 1
                        )
                }
            }

            result[key] = value
        }

        return result
    }

    /*
     * --------------------------------------------------
     * APPLY OMARCHY PALETTE
     * --------------------------------------------------
     */

    function applyPalette(text) {
        if (!text || text.trim().length === 0) {
            scheduleRetry()
            return
        }

        const colors =
            parseToml(text)

        /*
         * Require the three foundational values before
         * accepting the palette.
         */

        if (
            !colors.background
            || !colors.foreground
            || !colors.accent
        ) {
            console.log(
                "Radial Overview: Omarchy palette incomplete"
            )

            scheduleRetry()
            return
        }

        /*
         * Omarchy → Radial semantic mapping
         */

        background =
            colors.background

        surface =
            colors.dark_background
            || colors.background

        surfaceHover =
            colors.lighter_background
            || colors.background

        foreground =
            colors.foreground

        muted =
            colors.muted
            || colors.dark_foreground
            || colors.foreground

        accent =
            colors.accent

        accentSecondary =
            colors.light_foreground
            || colors.accent

        border =
            colors.accent

        dropHighlight =
            colors.selection
            || colors.accent

        available = true
        loaded = true

        retryCount = 0

        console.log(
            "Radial Overview: Omarchy adapter loaded"
        )

        console.log(
            "Radial Overview: Omarchy theme:",
            themeName
        )

        console.log(
            "Radial Overview: Omarchy accent:",
            accent
        )
    }

    /*
     * --------------------------------------------------
     * THEME-NAME CHECK
     * --------------------------------------------------
     */

    function checkThemeName() {
        if (!themeNameProcess.running)
            themeNameProcess.running = true
    }

    property Process themeNameProcess: Process {
        id: themeNameProcess

        running: false

        command: [
            "cat",
            adapter.themeNameFile
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const detectedName =
                    this.text.trim()

                if (detectedName.length === 0)
                    return

                /*
                 * Initial startup.
                 */

                if (adapter.themeName.length === 0) {
                    adapter.themeName =
                        detectedName

                    console.log(
                        "Radial Overview: detected Omarchy theme:",
                        detectedName
                    )

                    paletteDelayTimer.restart()
                    return
                }

                /*
                 * Live theme change.
                 */

                if (
                    detectedName
                    !== adapter.themeName
                ) {
                    console.log(
                        "Radial Overview: Omarchy theme changed:",
                        adapter.themeName,
                        "→",
                        detectedName
                    )

                    adapter.themeName =
                        detectedName

                    /*
                     * Do NOT mark the current palette unloaded.
                     *
                     * Keep displaying the old valid palette while
                     * Omarchy finishes replacing current/theme.
                     */

                    adapter.retryCount = 0
                    paletteDelayTimer.restart()
                }
            }
        }
    }

    /*
     * Check the tiny theme.name file once per second.
     *
     * This is deliberately the only polling in the adapter.
     * We do not poll colors.toml or Hyprland.
     */

    property Timer themeWatcher: Timer {
        interval: 1000
        repeat: true
        running: true

        onTriggered: {
            adapter.checkThemeName()
        }
    }

    /*
     * --------------------------------------------------
     * PALETTE LOAD
     * --------------------------------------------------
     */

    function loadPalette() {
        if (!paletteProcess.running)
            paletteProcess.running = true
    }

    property Process paletteProcess: Process {
        id: paletteProcess

        running: false

        command: [
            "cat",
            adapter.colorsFile
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const paletteText =
                    this.text

                if (
                    !paletteText
                    || paletteText.trim().length === 0
                ) {
                    adapter.scheduleRetry()
                    return
                }

                adapter.applyPalette(
                    paletteText
                )
            }
        }
    }

    /*
     * Give Omarchy a short period to finish replacing
     * current/theme after theme.name changes.
     */

    property Timer paletteDelayTimer: Timer {
        interval: 300
        repeat: false

        onTriggered: {
            adapter.loadPalette()
        }
    }

    /*
     * --------------------------------------------------
     * RETRY
     * --------------------------------------------------
     */

    function scheduleRetry() {
        if (retryCount >= maxRetries) {
            console.log(
                "Radial Overview: Omarchy palette unavailable after",
                maxRetries,
                "retries"
            )

            /*
             * If we have never loaded Omarchy successfully,
             * Theme.qml stays on its generic fallback.
             *
             * If we already had a valid Omarchy palette,
             * preserve it instead of flashing to fallback.
             */

            if (!available)
                loaded = false

            return
        }

        retryCount++

        console.log(
            "Radial Overview: waiting for Omarchy palette, retry",
            retryCount
        )

        paletteRetryTimer.restart()
    }

    property Timer paletteRetryTimer: Timer {
        interval: 200
        repeat: false

        onTriggered: {
            adapter.loadPalette()
        }
    }

    /*
     * --------------------------------------------------
     * INITIALIZATION
     * --------------------------------------------------
     */

    Component.onCompleted: {
        console.log(
            "Radial Overview: initializing Omarchy adapter"
        )

        checkThemeName()
    }
}
