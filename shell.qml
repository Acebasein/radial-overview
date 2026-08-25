import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls
import "." as Radial

ShellRoot {
    Radial.Theme {
        id: theme
    }


    IpcHandler {
        target: "radialOverview"

        function open(): void {
            root.refreshClients()
            root.openOverview()
        }

        function close(): void {
            root.requestClose()
        }

        function toggle(): void {
            if (overviewWindow.visible) {
                root.requestClose()
            } else {
                root.refreshClients()
                root.openOverview()
            }
        }
    }

    PanelWindow {
        id: overviewWindow

        visible: false
        // color: "#111018"
        color: theme.background
        focusable: true

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Item {
            id: root
            anchors.fill: parent
            focus: true

            /*
             * --------------------------------------------------
             * PRESENTATION / MOTION
             * --------------------------------------------------
             *
             * V1 motion stays deliberately subtle:
             *
             *   open  -> short fade + gentle scale to 100%
             *   close -> short fade + scale down before hiding
             *
             * No rotation, bounce, or per-sector choreography.
             */

            property real presentationProgress: 0.0
            property bool closing: false
            property var pendingFocusClient: null

            opacity: presentationProgress
            scale: 0.97 + (presentationProgress * 0.03)
            transformOrigin: Item.Center

            Behavior on presentationProgress {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            function openOverview() {
                closeAnimationTimer.stop()
                pendingFocusClient = null
                closing = false

                presentationProgress = 0.0
                overviewWindow.visible = true
                forceActiveFocus()

                // Start the entrance transition after the window is visible.
                Qt.callLater(function() {
                    presentationProgress = 1.0
                })
            }

            function requestClose(clientToFocus) {
                if (!overviewWindow.visible || closing)
                    return

                if (dragActive)
                    cancelPointerInteraction()

                pendingFocusClient = clientToFocus || null

                settingsRejectTimer.stop()
                workspaceWarningTimer.stop()
                settingsRejecting = false
                workspaceWarningActive = false
                workspaceWarningIds = []
                workspaceWarningRequestedCount = 0
                settingsPreviewCount = workspaceCount
                settingsPreviewAnimation = workspaceMoveAnimation
                settingsOpen = false

                closing = true
                presentationProgress = 0.0
                closeAnimationTimer.restart()
            }

            function dispatchPendingFocus() {
                const client = pendingFocusClient
                pendingFocusClient = null

                if (!client || !client.address)
                    return

                const selector =
                    "address:" + client.address

                const dispatchExpression =
                    'hl.dsp.focus({ window = "' +
                    selector +
                    '" })'

                Quickshell.execDetached([
                    "hyprctl",
                    "dispatch",
                    dispatchExpression
                ])
            }

            Timer {
                id: closeAnimationTimer
                interval: 150
                repeat: false

                onTriggered: {
                    overviewWindow.visible = false
                    closing = false
                    dispatchPendingFocus()
                }
            }

            /*
             * --------------------------------------------------
             * V1 CONFIGURATION
             * --------------------------------------------------
             */

            property int workspaceCount: 8

            /*
             * --------------------------------------------------
             * WORKSPACE SETTINGS DIAL
             * --------------------------------------------------
             *
             * The selector mirrors the radial visual language: a
             * compact clock-like dial with five detents (6–10).
             * Eight points straight up and remains the default.
             *
             * workspaceCount is the committed/persisted value.
             * settingsPreviewCount is the hand's temporary value.
             *
             * Safe increases may preview immediately in the main
             * radial. Reductions keep the current radial visible
             * until validation succeeds, so occupied workspaces can
             * never disappear during a failed settings attempt.
             */
            property bool settingsOpen: false
            property bool settingsRejecting: false
            property int settingsPreviewCount: workspaceCount

            /*
             * Workspace-move presentation is independent of the Hyprland
             * migration engine. Kite is the default; Pizza is the second
             * selectable style. More animation choices can be appended here
             * later without touching the move logic.
             */
            property string workspaceMoveAnimation: "kite"
            property string settingsPreviewAnimation: workspaceMoveAnimation
            property string activeDeliveryAnimation: workspaceMoveAnimation

            readonly property var workspaceAnimationChoices: [
                { key: "kite",  label: "KITE",  icon: "🪁" },
                { key: "pizza", label: "PIZZA", icon: "🍕" }
            ]

            readonly property int minimumWorkspaceCount: 6
            readonly property int maximumWorkspaceCount: 10

            /*
             * Preference is stored outside the Git checkout under
             * $XDG_STATE_HOME/radial-overview/settings.json (or the
             * conventional ~/.local/state fallback). Workspace count and
             * workspace-move animation are persisted together.
             */

            /*
             * Main-ring render count. Only safe increases preview
             * before confirmation. A requested reduction leaves the
             * committed workspace ring untouched until accepted.
             */
            readonly property int displayedWorkspaceCount:
                settingsOpen
                && settingsPreviewCount >= workspaceCount
                ? settingsPreviewCount
                : workspaceCount

            /* Failed-reduction snack/highlight state. */
            property bool workspaceWarningActive: false
            property var workspaceWarningIds: []
            property int workspaceWarningRequestedCount: 0
            property var pendingWarningIds: []
            property int pendingWarningRequestedCount: 0

            onWorkspaceCountChanged: {
                if (!settingsOpen)
                    settingsPreviewCount = workspaceCount

                radialCanvas.requestPaint()
            }

            function settingsAngleForCount(count) {
                // Five positions across the upper clock arc:
                // 6=-150°, 7=-120°, 8=-90°, 9=-60°, 10=-30°.
                return (-150 + ((count - 6) * 30)) * Math.PI / 180
            }

            function animationChoiceIndex(key) {
                for (let i = 0; i < workspaceAnimationChoices.length; ++i) {
                    if (workspaceAnimationChoices[i].key === key)
                        return i
                }

                return -1
            }

            function settingsAngleForAnimationIndex(index) {
                const total = workspaceAnimationChoices.length

                if (total <= 1)
                    return Math.PI / 2

                /*
                 * Symmetrically distribute active animations across the
                 * lower 180°. As the list grows toward five items, it
                 * naturally expands toward the full lower arc.
                 */
                const expansion = Math.max(0, Math.min(3, total - 2))
                const startDegrees = 40 - expansion * (10 / 3)
                const endDegrees = 180 - startDegrees
                const step = (endDegrees - startDegrees) / (total - 1)

                return (startDegrees + index * step) * Math.PI / 180
            }

            function settingsAngleForAnimation(key) {
                return settingsAngleForAnimationIndex(
                    animationChoiceIndex(key)
                )
            }

            function nearestWorkspaceAnimationForPoint(px, py, cx, cy) {
                const angle = Math.atan2(py - cy, px - cx)
                let bestKey = workspaceMoveAnimation
                let bestDistance = 999

                for (let i = 0; i < workspaceAnimationChoices.length; ++i) {
                    const candidate = settingsAngleForAnimationIndex(i)
                    const distance = wrappedAngleDistance(angle, candidate)

                    if (distance < bestDistance) {
                        bestDistance = distance
                        bestKey = workspaceAnimationChoices[i].key
                    }
                }

                return bestKey
            }

            function previewWorkspaceAnimation(key) {
                if (settingsRejecting)
                    return

                if (animationChoiceIndex(key) < 0)
                    return

                settingsPreviewAnimation = key
            }

            function wrappedAngleDistance(a, b) {
                let diff = Math.abs(a - b)

                while (diff > Math.PI * 2)
                    diff -= Math.PI * 2

                return Math.min(diff, Math.PI * 2 - diff)
            }

            function nearestWorkspaceCountForPoint(px, py, cx, cy) {
                const angle = Math.atan2(py - cy, px - cx)
                let bestCount = workspaceCount
                let bestDistance = 999

                for (let count = minimumWorkspaceCount;
                     count <= maximumWorkspaceCount;
                     ++count) {
                    const candidate = settingsAngleForCount(count)
                    const distance = wrappedAngleDistance(angle, candidate)

                    if (distance < bestDistance) {
                        bestDistance = distance
                        bestCount = count
                    }
                }

                return bestCount
            }

            function previewWorkspaceCount(count) {
                if (settingsRejecting)
                    return

                const clamped = Math.max(
                    minimumWorkspaceCount,
                    Math.min(maximumWorkspaceCount, count)
                )

                settingsPreviewCount = clamped
                radialCanvas.requestPaint()
            }

            function occupiedWorkspaceIdsAbove(limit) {
                const occupied = ({})

                for (let i = 0; i < clients.length; ++i) {
                    const client = clients[i]

                    if (!client || !client.workspace)
                        continue

                    const id = Number(client.workspace.id)

                    /* Ignore special/non-numeric Hyprland workspaces. */
                    if (!Number.isFinite(id) || id <= limit || id <= 0)
                        continue

                    occupied[id] = true
                }

                return Object.keys(occupied)
                    .map(function(value) { return Number(value) })
                    .sort(function(a, b) { return a - b })
            }

            function formatWorkspaceList(ids) {
                if (!ids || ids.length === 0)
                    return ""

                if (ids.length === 1)
                    return String(ids[0])

                if (ids.length === 2)
                    return ids[0] + " & " + ids[1]

                return ids.slice(0, ids.length - 1).join(", ")
                    + " & " + ids[ids.length - 1]
            }

            function isWorkspaceWarning(workspaceId) {
                if (!workspaceWarningActive)
                    return false

                return workspaceWarningIds.indexOf(workspaceId) !== -1
            }

            function dismissWorkspaceWarning() {
                if (!workspaceWarningActive)
                    return

                workspaceWarningActive = false
                workspaceWarningIds = []
                workspaceWarningRequestedCount = 0
                radialCanvas.requestPaint()
            }

            function persistWorkspaceSettings() {
                const payload = JSON.stringify({
                    workspaceCount: workspaceCount,
                    workspaceMoveAnimation: workspaceMoveAnimation
                })

                Quickshell.execDetached([
                    "bash",
                    "-lc",
                    'dir="${XDG_STATE_HOME:-$HOME/.local/state}/radial-overview"; mkdir -p "$dir"; printf "%s\n" "$1" > "$dir/settings.json"',
                    "--",
                    payload
                ])
            }

            function commitWorkspaceSettings(count, animationKey) {
                const clamped = Math.max(
                    minimumWorkspaceCount,
                    Math.min(maximumWorkspaceCount, count)
                )

                const animation =
                    animationChoiceIndex(animationKey) >= 0
                    ? animationKey
                    : "kite"

                workspaceCount = clamped
                settingsPreviewCount = clamped
                workspaceMoveAnimation = animation
                settingsPreviewAnimation = animation
                persistWorkspaceSettings()
                radialCanvas.requestPaint()
            }

            function beginRejectedWorkspaceReduction(requestedCount, blockers) {
                if (settingsRejecting)
                    return

                settingsRejecting = true
                pendingWarningRequestedCount = requestedCount
                pendingWarningIds = blockers.slice(0)

                /*
                 * First tell the story visually: the hand travels
                 * smoothly back to the currently committed value.
                 * The explanation appears only after it gets there.
                 */
                settingsPreviewCount = workspaceCount
                settingsPreviewAnimation = workspaceMoveAnimation
                radialCanvas.requestPaint()
                settingsRejectTimer.restart()
            }

            function applyWorkspaceSetting() {
                if (settingsRejecting)
                    return

                const requested = settingsPreviewCount
                const requestedAnimation = settingsPreviewAnimation

                if (requested < workspaceCount) {
                    const blockers = occupiedWorkspaceIdsAbove(requested)

                    if (blockers.length > 0) {
                        beginRejectedWorkspaceReduction(
                            requested,
                            blockers
                        )
                        return
                    }
                }

                /*
                 * Runtime properties change immediately here. The Overview
                 * stays open; the very next workspace drag uses the newly
                 * selected animation. Persistence is written at the same time.
                 */
                commitWorkspaceSettings(
                    requested,
                    requestedAnimation
                )
                closeSettings()
            }

            function openSettings() {
                if (dragActive)
                    cancelPointerInteraction()

                workspaceWarningActive = false
                workspaceWarningTimer.stop()
                settingsRejecting = false
                settingsPreviewCount = workspaceCount
                settingsPreviewAnimation = workspaceMoveAnimation
                settingsOpen = true
            }

            function closeSettings() {
                if (settingsRejecting)
                    return

                settingsPreviewCount = workspaceCount
                settingsPreviewAnimation = workspaceMoveAnimation
                settingsOpen = false
                radialCanvas.requestPaint()
                forceActiveFocus()
            }

            /*
             * Load the persisted preference once. Missing/invalid files
             * simply retain the built-in default of 8.
             */
            Process {
                id: workspaceSettingsLoadProcess
                running: true

                command: [
                    "bash",
                    "-lc",
                    'file="${XDG_STATE_HOME:-$HOME/.local/state}/radial-overview/settings.json"; if [ -f "$file" ]; then cat "$file"; fi'
                ]

                stdout: StdioCollector {
                    onStreamFinished: {
                        const raw = this.text.trim()

                        if (!raw)
                            return

                        try {
                            const data = JSON.parse(raw)
                            const value = Number(data.workspaceCount)

                            if (!Number.isFinite(value))
                                return

                            const clamped = Math.max(
                                root.minimumWorkspaceCount,
                                Math.min(root.maximumWorkspaceCount, value)
                            )

                            let animation = "kite"

                            if (typeof data.workspaceMoveAnimation === "string"
                                    && root.animationChoiceIndex(
                                        data.workspaceMoveAnimation
                                    ) >= 0) {
                                animation = data.workspaceMoveAnimation
                            }

                            root.workspaceCount = clamped
                            root.settingsPreviewCount = clamped
                            root.workspaceMoveAnimation = animation
                            root.settingsPreviewAnimation = animation
                            root.activeDeliveryAnimation = animation
                            radialCanvas.requestPaint()

                            console.log(
                                "Radial Overview: settings loaded:",
                                clamped,
                                animation
                            )
                        } catch (error) {
                            console.log(
                                "Radial Overview: invalid settings JSON:",
                                error
                            )
                        }
                    }
                }
            }

            Timer {
                id: settingsRejectTimer
                interval: 380
                repeat: false

                onTriggered: {
                    root.settingsOpen = false
                    root.settingsRejecting = false

                    root.workspaceWarningRequestedCount =
                        root.pendingWarningRequestedCount

                    root.workspaceWarningIds =
                        root.pendingWarningIds.slice(0)

                    root.pendingWarningRequestedCount = 0
                    root.pendingWarningIds = []

                    root.workspaceWarningActive = true
                    root.workspaceWarningTimer.restart()
                    radialCanvas.requestPaint()
                    root.forceActiveFocus()
                }
            }

            Timer {
                id: workspaceWarningTimer
                interval: 4600
                repeat: false

                /*
                 * Bind the timer directly to the warning state.
                 * This is more robust than relying only on restart(),
                 * and guarantees every visible warning gets a timeout.
                 */
                running: root.workspaceWarningActive

                onTriggered: {
                    root.dismissWorkspaceWarning()
                }
            }

            property real centerX: width / 2
            property real centerY: height / 2

            property real hubRadius:
                Math.min(width, height) * 0.14

            property real innerOuterRadius:
                Math.min(width, height) * 0.30

            property real outerOuterRadius:
                Math.min(width, height) * 0.45

            property real windowRingRadius:
                (innerOuterRadius + outerOuterRadius) / 2

            property real outerRingThickness:
                outerOuterRadius - innerOuterRadius

            // property color accentColor: "#8b5cf6"
            // property color foregroundColor: "#ffffff"
            // property color mutedColor: "#8f8a9d"
            // property color bubbleBackground: "#1a1822"
            // property color dropHighlightColor: "#362454"
            
            property color accentColor: theme.accent
            property color foregroundColor: theme.foreground
            property color mutedColor: theme.muted
            property color bubbleBackground: theme.surface
            property color dropHighlightColor: theme.dropHighlight
            property color accentSecondaryColor: theme.accentSecondary

            /*
             * --------------------------------------------------
             * ADAPTIVE DERIVED PALETTE
             * --------------------------------------------------
             *
             * The base semantic theme stays untouched. These colors are
             * generated from it and exist only for secondary illustrations
             * such as receiving clouds and the kite destination atmosphere.
             *
             * Because these are QML bindings, they are recomputed as soon as
             * the active Omarchy/theme adapter updates its palette.
             */

            function clampColorComponent(value) {
                return Math.max(0, Math.min(1, value))
            }

            function mixThemeColors(a, b, amount, alpha) {
                const t = clampColorComponent(amount)
                const resultAlpha =
                    alpha === undefined
                    ? (
                        a.a
                        + (b.a - a.a) * t
                      )
                    : clampColorComponent(alpha)

                return Qt.rgba(
                    a.r + (b.r - a.r) * t,
                    a.g + (b.g - a.g) * t,
                    a.b + (b.b - a.b) * t,
                    resultAlpha
                )
            }

            function themeLuminance(c) {
                /*
                 * Perceptual-enough luminance for deciding whether a derived
                 * tone should travel lighter or darker than its base.
                 */
                return (
                    c.r * 0.2126
                    + c.g * 0.7152
                    + c.b * 0.0722
                )
            }

            function hueToward(hue, targetHue, amount) {
                /*
                 * Move around the shortest side of the hue wheel.
                 */
                let source = hue

                if (source < 0)
                    source = accentColor.hslHue >= 0
                        ? accentColor.hslHue
                        : targetHue

                let delta = targetHue - source

                if (delta > 0.5)
                    delta -= 1
                else if (delta < -0.5)
                    delta += 1

                let result = source + delta * amount

                while (result < 0)
                    result += 1

                while (result > 1)
                    result -= 1

                return result
            }

            function derivedThemeTone(
                base,
                blueBias,
                saturationScale,
                lightnessDelta,
                alpha
            ) {
                /*
                 * 0.60 on Qt's HSL hue wheel sits in the blue/cool region.
                 * We only bias gently toward it, retaining the character of
                 * the user's theme rather than replacing it with a fixed blue.
                 */
                const hue =
                    hueToward(
                        base.hslHue,
                        0.60,
                        blueBias
                    )

                const saturation =
                    clampColorComponent(
                        base.hslSaturation
                        * saturationScale
                    )

                const lightness =
                    clampColorComponent(
                        base.hslLightness
                        + lightnessDelta
                    )

                return Qt.hsla(
                    hue,
                    saturation,
                    lightness,
                    alpha === undefined
                    ? base.a
                    : clampColorComponent(alpha)
                )
            }

            readonly property bool derivedPaletteIsDark:
                themeLuminance(bubbleBackground) < 0.48

            /*
             * Natural cloud layers. On dark themes they travel lighter;
             * on light themes they travel darker. All preserve a softened
             * version of the active accent hue with a small cool-sky bias.
             */
            readonly property color cloudHighlightColor:
                derivedThemeTone(
                    accentSecondaryColor,
                    0.18,
                    0.56,
                    derivedPaletteIsDark ? 0.34 : -0.20,
                    1.0
                )

            readonly property color cloudBaseColor:
                derivedThemeTone(
                    accentSecondaryColor,
                    0.15,
                    0.64,
                    derivedPaletteIsDark ? 0.23 : -0.14,
                    1.0
                )

            readonly property color cloudMidColor:
                derivedThemeTone(
                    accentColor,
                    0.20,
                    0.58,
                    derivedPaletteIsDark ? 0.13 : -0.08,
                    1.0
                )

            readonly property color cloudShadowColor:
                mixThemeColors(
                    cloudMidColor,
                    bubbleBackground,
                    derivedPaletteIsDark ? 0.52 : 0.34,
                    0.96
                )

            readonly property color cloudOutlineColor:
                mixThemeColors(
                    cloudBaseColor,
                    accentSecondaryColor,
                    0.44,
                    0.90
                )

            readonly property color cloudSparkColor:
                mixThemeColors(
                    cloudHighlightColor,
                    foregroundColor,
                    derivedPaletteIsDark ? 0.36 : 0.14,
                    0.92
                )

            /*
             * Separate destination atmosphere for whole-workspace movement.
             * This is deliberately distinct from the normal window-drop
             * highlight while still being derived from the same theme.
             */
            readonly property color cloudDestinationFillColor:
                derivedThemeTone(
                    accentColor,
                    0.24,
                    0.50,
                    derivedPaletteIsDark ? 0.10 : -0.08,
                    derivedPaletteIsDark ? 0.24 : 0.18
                )


            /*
             * --------------------------------------------------
             * RADIAL DERIVED PALETTE
             * --------------------------------------------------
             *
             * Omarchy/theme colors remain the source of truth. Radial
             * Overview expands those colors into a small harmonized palette
             * with more depth and separation for illustrations.
             *
             * The important part: this is not a fixed color scheme.
             * Changing the active theme immediately regenerates every tone.
             */

            function wrapHue(value) {
                let hue = value

                while (hue < 0)
                    hue += 1

                while (hue > 1)
                    hue -= 1

                return hue
            }

            readonly property real radialPaletteBaseHue:
                accentColor.hslSaturation > 0.07
                ? accentColor.hslHue
                : (
                    accentSecondaryColor.hslSaturation > 0.07
                    ? accentSecondaryColor.hslHue
                    : 0.58
                  )

            readonly property real radialPaletteBaseSaturation:
                Math.max(
                    derivedPaletteIsDark ? 0.42 : 0.34,
                    Math.min(
                        derivedPaletteIsDark ? 0.78 : 0.68,
                        Math.max(
                            accentColor.hslSaturation,
                            accentSecondaryColor.hslSaturation
                        ) * 1.12
                    )
                )

            readonly property real radialPaletteBaseLightness:
                clampColorComponent(
                    (
                        accentColor.hslLightness
                        + accentSecondaryColor.hslLightness
                    ) / 2
                )

            function radialPaletteTone(
                hueOffset,
                saturationFactor,
                lightnessDelta,
                alpha
            ) {
                /*
                 * Small hue rotations give us distinct siblings while the
                 * shared base hue keeps the family recognizable as belonging
                 * to the current theme.
                 */
                const hue =
                    wrapHue(
                        radialPaletteBaseHue
                        + hueOffset
                    )

                const saturation =
                    clampColorComponent(
                        radialPaletteBaseSaturation
                        * saturationFactor
                    )

                const lightness =
                    clampColorComponent(
                        radialPaletteBaseLightness
                        + lightnessDelta
                    )

                return Qt.hsla(
                    hue,
                    saturation,
                    lightness,
                    alpha === undefined
                    ? 1.0
                    : clampColorComponent(alpha)
                )
            }

            /*
             * Six roles rather than four nearly-identical accents:
             *
             *   sky      — cooler / airy
             *   mint     — fresh adjacent hue
             *   sun      — warm energetic sibling
             *   berry    — richer contrasting sibling
             *   bright   — high-luminance highlight
             *   deep     — shadow / structural depth
             *
             * Hue offsets are deliberately modest; these remain descendants
             * of the active theme rather than an unrelated rainbow.
             */
            readonly property color radialSkyColor:
                radialPaletteTone(
                    0.075,
                    0.90,
                    derivedPaletteIsDark ? 0.20 : -0.10,
                    0.96
                )

            readonly property color radialMintColor:
                radialPaletteTone(
                    0.145,
                    0.84,
                    derivedPaletteIsDark ? 0.14 : -0.08,
                    0.96
                )

            readonly property color radialSunColor:
                radialPaletteTone(
                    -0.115,
                    0.96,
                    derivedPaletteIsDark ? 0.19 : -0.09,
                    0.96
                )

            readonly property color radialBerryColor:
                radialPaletteTone(
                    -0.205,
                    0.88,
                    derivedPaletteIsDark ? 0.12 : -0.12,
                    0.96
                )

            readonly property color radialBrightColor:
                radialPaletteTone(
                    0.025,
                    0.62,
                    derivedPaletteIsDark ? 0.31 : -0.18,
                    0.98
                )

            readonly property color radialDeepColor:
                radialPaletteTone(
                    -0.035,
                    0.78,
                    derivedPaletteIsDark ? -0.08 : -0.24,
                    0.98
                )

            /*
             * Harmonize the derived family back toward the actual theme
             * accent. This keeps very unusual Omarchy themes feeling native.
             */
            readonly property color kitePanelColorA:
                mixThemeColors(
                    radialSkyColor,
                    accentColor,
                    0.22,
                    0.94
                )

            readonly property color kitePanelColorB:
                mixThemeColors(
                    radialSunColor,
                    accentSecondaryColor,
                    0.17,
                    0.94
                )

            readonly property color kitePanelColorC:
                mixThemeColors(
                    radialMintColor,
                    accentColor,
                    0.16,
                    0.94
                )

            readonly property color kitePanelColorD:
                mixThemeColors(
                    radialBerryColor,
                    accentSecondaryColor,
                    0.15,
                    0.94
                )

            /*
             * A separate hanger family gives repeated applications a stable
             * identity while avoiding the "every badge is the accent color"
             * look. Same app key always hashes to the same variant.
             */
            readonly property var radialAppPalette: [
                radialSkyColor,
                radialMintColor,
                radialSunColor,
                radialBerryColor,
                radialBrightColor,
                radialDeepColor
            ]

            function appVariantIndex(appKey) {
                const key = String(appKey || "app")
                let hash = 2166136261

                for (let i = 0; i < key.length; ++i) {
                    hash ^= key.charCodeAt(i)
                    hash += (
                        (hash << 1)
                        + (hash << 4)
                        + (hash << 7)
                        + (hash << 8)
                        + (hash << 24)
                    )
                }

                return Math.abs(hash) % radialAppPalette.length
            }

            function appVariantColor(appKey) {
                const variant = appVariantIndex(appKey)
                const base = radialAppPalette[variant]

                /*
                 * Pull each hanger slightly toward the semantic surface.
                 * This produces depth while keeping application icons legible.
                 */
                return mixThemeColors(
                    base,
                    bubbleBackground,
                    derivedPaletteIsDark ? 0.16 : 0.10,
                    0.96
                )
            }

            function appVariantOutline(appKey) {
                const variant = appVariantIndex(appKey)
                const base = radialAppPalette[variant]

                return mixThemeColors(
                    base,
                    foregroundColor,
                    derivedPaletteIsDark ? 0.26 : 0.16,
                    0.98
                )
            }

            /*
             * Workspace-kite destination atmosphere. Rather than reusing the
             * normal accent overlay, tint the theme surface with a vivid but
             * related derived tone. This keeps the highlighted sector rich
             * across blue, beige, monochrome and warm themes.
             */
            readonly property color kiteDestinationAtmosphereColor:
                mixThemeColors(
                    bubbleBackground,
                    radialSkyColor,
                    derivedPaletteIsDark ? 0.42 : 0.31,
                    derivedPaletteIsDark ? 0.34 : 0.25
                )

            /*
             * The adaptive derived palette above is intentionally
             * binding-driven: no separate theme-change watcher is needed.
             * When Theme.qml changes its semantic colors, cloud and target
             * tones are recalculated automatically in the same frame.
             *
             * --------------------------------------------------
             * CLIENT DATA
             * --------------------------------------------------
             */

            property var clients: []
            property int clientRevision: 0

            /*
             * --------------------------------------------------
             * MULTI-MONITOR TOPOLOGY
             * --------------------------------------------------
             *
             * Hyprland owns normal workspaces per monitor. We only
             * surface that ownership here; Radial Overview does not
             * alter Hyprland's monitor/workspace model.
             *
             * With one connected monitor the UI remains unchanged.
             * With two or more monitors, occupied/active workspaces
             * show the owning Hyprland monitor name.
             */
            property var monitors: []
            property var hyprWorkspaces: []
            property int topologyRevision: 0

            readonly property int monitorCount:
                monitors.length

            function workspaceMonitorName(workspaceId) {
                const revision = topologyRevision

                for (let i = 0; i < hyprWorkspaces.length; ++i) {
                    const workspace = hyprWorkspaces[i]

                    if (workspace.id === workspaceId)
                        return workspace.monitor || ""
                }

                return ""
            }

            function isFocusedMonitor(monitorName) {
                const revision = topologyRevision

                if (!monitorName)
                    return false

                for (let i = 0; i < monitors.length; ++i) {
                    const monitor = monitors[i]

                    if (monitor.name === monitorName)
                        return monitor.focused === true
                }

                return false
            }

            /*
             * --------------------------------------------------
             * APPLICATION IDENTITY
             * --------------------------------------------------
             *
             * Quickshell builds its desktop-entry index
             * asynchronously. Touching applications.values
             * creates the dependency needed for lookups to
             * reevaluate when that index becomes available.
             */
            property var desktopApplications:
                DesktopEntries.applications.values

            function desktopEntryFor(client) {
                if (!client)
                    return null

                DesktopEntries.applications.values

                const candidates = [
                    client.initialClass || "",
                    client.class || ""
                ]

                for (let i = 0; i < candidates.length; ++i) {
                    const appClass = candidates[i]

                    if (!appClass)
                        continue

                    const entry =
                        DesktopEntries.heuristicLookup(appClass)

                    if (entry)
                        return entry
                }

                return null
            }

            function appIconPathFor(client) {
                const entry =
                    desktopEntryFor(client)

                let iconEntry = entry

                /*
                 * Browser-created web apps can expose a unique
                 * window class instead of the browser desktop ID.
                 * Keep the app-specific label, but inherit the
                 * browser icon when possible.
                 */
                if (!iconEntry && client) {
                    const appClass = String(
                        client.initialClass
                        || client.class
                        || ""
                    ).toLowerCase()

                    if (appClass.startsWith("brave-"))
                        iconEntry = DesktopEntries.heuristicLookup("brave-origin")
                }

                if (!iconEntry || !iconEntry.icon)
                    return ""

                const raw =
                    String(iconEntry.icon).trim()

                const iconName =
                    raw
                    .replace(/^image:\/\/icon\//, "")
                    .split("?")[0]
                    .trim()

                if (!iconName)
                    return ""

                return Quickshell.iconPath(
                    iconName,
                    "image-missing"
                )
            }

            function appDisplayNameFor(client) {
                const entry =
                    desktopEntryFor(client)

                if (entry && entry.name)
                    return entry.name

                /*
                 * For unmatched web apps, the window title is often
                 * much friendlier than the generated WM class.
                 */
                if (client && client.title) {
                    const title = String(client.title).trim()
                    const dashParts = title.split(" — ")

                    if (dashParts.length > 1)
                        return dashParts[dashParts.length - 1]

                    if (title.length > 0)
                        return title
                }

                return shortClassName(client)
            }

            function isFocusedClient(client) {
                if (!client)
                    return false

                /*
                 * hyprctl clients -j exposes focusHistoryID.
                 * The currently focused normal Hyprland client is
                 * represented by focusHistoryID === 0. The Overview
                 * itself is a layer surface, so opening it does not
                 * replace that client in the Hyprland client list.
                 */
                return client.focusHistoryID === 0
            }

            function refreshClients() {
                clientsProcess.running = false
                clientsProcess.running = true

                refreshDisplayTopology()
            }

            function refreshDisplayTopology() {
                monitorsProcess.running = false
                workspacesProcess.running = false

                monitorsProcess.running = true
                workspacesProcess.running = true
            }

            function windowCountForWorkspace(workspaceId) {
                let count = 0

                for (let i = 0; i < clients.length; ++i) {
                    const client = clients[i]

                    if (client.workspace
                            && client.workspace.id === workspaceId) {
                        count++
                    }
                }

                return count
            }

            function clientsForWorkspace(workspaceId) {
                const result = []

                for (let i = 0; i < clients.length; ++i) {
                    const client = clients[i]

                    if (client.workspace
                            && client.workspace.id === workspaceId) {
                        result.push(client)
                    }
                }

                return result
            }

            /*
             * --------------------------------------------------
             * WINDOW ACTIONS
             * --------------------------------------------------
             */

            function focusClient(client) {
                if (!client || !client.address)
                    return

                /*
                 * Focus must be dispatched while the selected client
                 * context is still current. This is the same ordering
                 * used by the known-good pre-motion implementation.
                 *
                 * We intentionally do not delay this action behind the
                 * close animation: doing so lets Hyprland restore the
                 * previously focused client when the layer disappears,
                 * which can defeat the requested cross-workspace focus.
                 */
                const selector =
                    "address:" + client.address

                const dispatchExpression =
                    'hl.dsp.focus({ window = "' +
                    selector +
                    '" })'

                Quickshell.execDetached([
                    "hyprctl",
                    "dispatch",
                    dispatchExpression
                ])

                /*
                 * Preserve the original reliable click-to-focus behavior:
                 * hide immediately after dispatching the focus request.
                 * Open/Esc motion remains available independently.
                 */
                closeAnimationTimer.stop()
                pendingFocusClient = null
                closing = false
                presentationProgress = 0.0
                overviewWindow.visible = false
            }

            function moveClientToWorkspace(client, workspaceId) {
                if (!client
                        || !client.address
                        || workspaceId <= 0) {
                    return
                }

                if (client.workspace
                        && client.workspace.id === workspaceId) {
                    return
                }

                const selector =
                    "address:" + client.address

                const dispatchExpression =
                    'hl.dsp.window.move({ workspace = "' +
                    workspaceId +
                    '", window = "' +
                    selector +
                    '", follow = false })'

                Quickshell.execDetached([
                    "hyprctl",
                    "dispatch",
                    dispatchExpression
                ])

                /*
                 * Highlight this exact bubble when it appears in its new
                 * workspace. The client refresh below causes the destination
                 * outer ring to render it with the arrival halo.
                 */
                markArrivalWindows([
                    client.address
                ])

                moveRefreshTimer.restart()
            }

            Timer {
                id: moveRefreshTimer
                interval: 220
                repeat: false

                onTriggered: {
                    root.refreshClients()
                }
            }

            /*
             * --------------------------------------------------
             * DRAG STATE
             * --------------------------------------------------
             */

            property bool dragActive: false
            property bool dropFeedbackActive: false
            property var draggedClient: null

            /*
             * --------------------------------------------------
             * NEW ARRIVAL FEEDBACK
             * --------------------------------------------------
             *
             * Store exact Hyprland window addresses, never app/class names.
             * This lets one moved Foot window glow without lighting every
             * other Foot window. Kite delivery simply registers the whole
             * captured address set.
             */
            property var arrivalWindowAddresses: []

            function normalizeWindowAddress(address) {
                return String(address || "").toLowerCase()
            }

            function isArrivalWindow(client) {
                if (!client || !client.address)
                    return false

                const address =
                    normalizeWindowAddress(client.address)

                return arrivalWindowAddresses.indexOf(address) >= 0
            }

            function markArrivalWindows(addresses) {
                const unique = []

                for (let i = 0; i < addresses.length; ++i) {
                    const address =
                        normalizeWindowAddress(addresses[i])

                    if (address.length > 0
                            && unique.indexOf(address) < 0) {
                        unique.push(address)
                    }
                }

                /*
                 * Assign a new array so QML bindings are invalidated.
                 */
                /*
                 * Persistent arrival state:
                 * keep the latest successful drop highlighted so the user
                 * has unlimited time to visually locate the new arrival(s).
                 * The next successful drop replaces this set.
                 */
                arrivalWindowAddresses = unique
            }

            function clearArrivalWindows() {
                arrivalWindowAddresses = []
            }

            property real dragX: 0
            property real dragY: 0

            property real dragStartX: 0
            property real dragStartY: 0

            property int dragTargetWorkspace: 0
            property real dragThreshold: 10

            onDragTargetWorkspaceChanged:
                radialCanvas.requestPaint()

            onDragActiveChanged:
                radialCanvas.requestPaint()

            onDropFeedbackActiveChanged:
                radialCanvas.requestPaint()

            /*
             * --------------------------------------------------
             * DROP TARGET GEOMETRY
             * --------------------------------------------------
             *
             * IMPORTANT:
             *
             * The entire radial wedge is now a drop target:
             *
             *     hubRadius → outerOuterRadius
             *
             * Therefore either the inner workspace ring OR the
             * corresponding outer window ring can receive a drop.
             */

            function workspaceAtPoint(px, py) {
                const dx = px - centerX
                const dy = py - centerY

                const radius =
                    Math.sqrt(
                        dx * dx +
                        dy * dy
                    )

                if (radius < hubRadius
                        || radius > outerOuterRadius) {
                    return 0
                }

                let angle =
                    Math.atan2(dy, dx)

                let normalized =
                    angle + Math.PI / 2

                while (normalized < 0)
                    normalized += Math.PI * 2

                while (normalized >= Math.PI * 2)
                    normalized -= Math.PI * 2

                const step =
                    (Math.PI * 2)
                    / displayedWorkspaceCount

                return Math.floor(
                    normalized / step
                ) + 1
            }

            function beginPointerInteraction(
                client,
                px,
                py
            ) {
                draggedClient = client

                dragStartX = px
                dragStartY = py

                dragX = px
                dragY = py

                dragActive = false
                dragTargetWorkspace = 0
            }

            function updatePointerInteraction(
                px,
                py
            ) {
                if (!draggedClient)
                    return

                dragX = px
                dragY = py

                if (!dragActive) {
                    const dx =
                        px - dragStartX

                    const dy =
                        py - dragStartY

                    const distance =
                        Math.sqrt(
                            dx * dx +
                            dy * dy
                        )

                    if (distance >= dragThreshold)
                        dragActive = true
                }

                if (dragActive) {
                    dragTargetWorkspace =
                        workspaceAtPoint(
                            px,
                            py
                        )
                }
            }

            function finishPointerInteraction(
                px,
                py
            ) {
                if (!draggedClient)
                    return

                const client =
                    draggedClient

                if (dragActive) {
                    const target =
                        workspaceAtPoint(
                            px,
                            py
                        )

                    if (target > 0) {
                        /*
                         * Move immediately, but keep a short-lived
                         * visual proxy at the release point. This hides
                         * the abrupt source/destination reflow while
                         * Hyprland and the client model update.
                         */
                        dragX = px
                        dragY = py
                        dragTargetWorkspace = target

                        moveClientToWorkspace(
                            client,
                            target
                        )

                        dragActive = false
                        dropFeedbackActive = true
                        dropFeedbackTimer.restart()

                        radialCanvas.requestPaint()
                        return
                    }

                    cancelPointerInteraction()
                    return
                }

                focusClient(client)

                draggedClient = null
                dragActive = false
                dropFeedbackActive = false
                dragTargetWorkspace = 0

                radialCanvas.requestPaint()
            }

            function cancelPointerInteraction() {
                draggedClient = null
                dragActive = false
                dropFeedbackActive = false
                dragTargetWorkspace = 0

                radialCanvas.requestPaint()
            }

            Timer {
                id: dropFeedbackTimer
                interval: 150
                repeat: false

                onTriggered: {
                    root.dropFeedbackActive = false
                    root.draggedClient = null
                    root.dragTargetWorkspace = 0
                    radialCanvas.requestPaint()
                }
            }

            /*
             * --------------------------------------------------
             * WORKSPACE MOVE — KITE SLICE PROTOTYPE
             * --------------------------------------------------
             *
             * Dragging an occupied workspace number lifts a ghost
             * "kite" with app-aware badges attached to its trailing string. Valid
             * destination sectors highlight and reach out with a
             * small stylized receiving arm. Releasing opens a
             * confirmation card.
             *
             * Confirming Move captures the clients that currently
             * belong to the source workspace, asks Hyprland to move
             * precisely those clients to the destination workspace,
             * then refreshes from Hyprland. Radial Overview never
             * attempts to reproduce or manage the destination layout.
             */
            property bool workspaceDragActive: false
            property bool workspaceMoveConfirmActive: false
            property bool workspaceDragAnimating: false
            property int workspaceDragSource: 0
            property int workspaceDragTarget: 0
            property int workspaceDragWindowCount: 0

            /*
             * Visual "kite toppings" captured when a workspace drag starts.
             *
             * Each real window contributes one topping. Windows belonging
             * to the same application naturally receive the same icon/name,
             * while different applications remain visually distinct.
             * We keep at most six real toppings on the slice and use a
             * compact +N bubble for any overflow.
             */
            property var workspaceDragToppings: []

            property real workspaceDragX: centerX
            property real workspaceDragY: centerY
            property real workspaceDragStartX: centerX
            property real workspaceDragStartY: centerY

            /*
             * Kite flight dynamics.
             *
             * The ghost tilts with horizontal pointer movement while a
             * lightweight flame/smoke trail points opposite the current
             * direction of travel. These are visual-only and never affect
             * the actual workspace move.
             */
            property real workspaceDragVelocityX: 0
            property real workspaceDragVelocityY: 0
            property real workspaceDragSpeed: 0
            property real workspaceDragTilt: 0
            property real workspaceTrailAngle: 0
            property real workspaceTrailPulse: 0
            property real pizzaTrailPulse: 0

            property real workspaceGhostScale: 1.0
            property real workspaceGhostOpacity: 0.0
            property real workspaceDragThreshold: 9

            onWorkspaceDragActiveChanged: radialCanvas.requestPaint()
            onWorkspaceDragTargetChanged: radialCanvas.requestPaint()
            onWorkspaceMoveConfirmActiveChanged: radialCanvas.requestPaint()

            function workspaceLabelPoint(workspaceId) {
                if (workspaceId <= 0)
                    return { x: centerX, y: centerY }

                const step = (Math.PI * 2) / displayedWorkspaceCount
                const angle = -Math.PI / 2 + ((workspaceId - 0.5) * step)
                const radius = (hubRadius + innerOuterRadius) / 2

                return {
                    x: centerX + Math.cos(angle) * radius,
                    y: centerY + Math.sin(angle) * radius
                }
            }

            function workspaceToppingsFor(workspaceId) {
                const toppings = []
                const matchingClients = []

                for (let i = 0; i < clients.length; ++i) {
                    const client = clients[i]

                    if (!client
                            || !client.workspace
                            || client.workspace.id !== workspaceId) {
                        continue
                    }

                    matchingClients.push(client)
                }

                /*
                 * Keep the kite readable. Six individual app bubbles fit
                 * comfortably on the slice. If there are more, the seventh
                 * topping becomes +N.
                 */
                const visibleCount = Math.min(6, matchingClients.length)

                for (let j = 0; j < visibleCount; ++j) {
                    const client = matchingClients[j]
                    const displayName = appDisplayNameFor(client)
                    const iconPath = appIconPathFor(client)
                    const appKey = String(
                        client.initialClass
                        || client.class
                        || displayName
                        || "app"
                    ).toLowerCase()

                    toppings.push({
                        key: appKey,
                        name: displayName,
                        icon: iconPath,
                        initial:
                            displayName && displayName.length > 0
                            ? displayName.charAt(0).toUpperCase()
                            : "?"
                    })
                }

                if (matchingClients.length > 6) {
                    toppings.push({
                        overflow: true,
                        count: matchingClients.length - 6,
                        key: "__overflow__",
                        name: "",
                        icon: "",
                        initial: ""
                    })
                }

                return toppings
            }

            function pizzaToppingPoint(index, count) {
                /*
                 * Hand-tuned topping positions that stay inside the slice.
                 * The same layout is used regardless of application identity.
                 */
                const layouts = {
                    1: [
                        { x: 0, y: 72 }
                    ],
                    2: [
                        { x: -20, y: 68 },
                        { x: 20, y: 68 }
                    ],
                    3: [
                        { x: -22, y: 62 },
                        { x: 22, y: 62 },
                        { x: 0, y: 88 }
                    ],
                    4: [
                        { x: -22, y: 59 },
                        { x: 22, y: 59 },
                        { x: -14, y: 86 },
                        { x: 14, y: 86 }
                    ],
                    5: [
                        { x: -23, y: 57 },
                        { x: 0, y: 57 },
                        { x: 23, y: 57 },
                        { x: -15, y: 85 },
                        { x: 15, y: 85 }
                    ],
                    6: [
                        { x: -23, y: 56 },
                        { x: 0, y: 56 },
                        { x: 23, y: 56 },
                        { x: -23, y: 82 },
                        { x: 0, y: 82 },
                        { x: 23, y: 82 }
                    ],
                    7: [
                        { x: -24, y: 53 },
                        { x: 0, y: 53 },
                        { x: 24, y: 53 },
                        { x: -24, y: 78 },
                        { x: 0, y: 78 },
                        { x: 24, y: 78 },
                        { x: 0, y: 103 }
                    ]
                }

                const safeCount = Math.max(1, Math.min(7, count))
                const points = layouts[safeCount]
                return points[Math.max(0, Math.min(index, points.length - 1))]
            }

            function kiteStringPoint(step, stepCount) {
                const count = Math.max(2, stepCount)
                const t = Math.max(0, Math.min(1, step / (count - 1)))

                /*
                 * Organic wind model.
                 *
                 * Instead of one symmetric sine wave, the tail combines
                 * several waves with unrelated frequencies/phases plus a
                 * one-sided gust. That makes the string feel wind-blown:
                 * imperfect, delayed and slightly unpredictable.
                 */
                const time = workspaceTrailPulse * Math.PI * 2

                const speed =
                    Math.min(workspaceDragSpeed, 18)

                const dragLean =
                    Math.max(
                        -22,
                        Math.min(
                            22,
                            -workspaceDragVelocityX * 0.82
                        )
                    ) * Math.pow(t, 1.08)

                const baseAmplitude =
                    (5.5 + speed * 0.48)
                    * (0.22 + Math.pow(t, 1.18))

                const waveA =
                    Math.sin(
                        time * 0.83
                        + t * 11.9
                        + 0.35
                    )

                const waveB =
                    0.57
                    * Math.sin(
                        time * 1.71
                        - t * 7.1
                        + 1.42
                    )

                const waveC =
                    0.31
                    * Math.sin(
                        time * 2.47
                        + t * 18.3
                        - 0.76
                    )

                /*
                 * A gust only pushes strongly in one direction for part
                 * of the cycle, deliberately breaking symmetry.
                 */
                const gustRaw =
                    Math.sin(
                        time * 0.61
                        + t * 4.7
                        + 2.15
                    )

                const gust =
                    Math.max(0, gustRaw)
                    * (2.5 + speed * 0.32)
                    * Math.pow(t, 1.55)

                /*
                 * Slight delayed counter-motion near the lower tail.
                 */
                const rebound =
                    Math.sin(
                        time * 1.13
                        - t * 13.7
                        + 0.8
                    )
                    * 2.8
                    * Math.pow(t, 1.9)

                return {
                    x:
                        78
                        + dragLean
                        + (waveA + waveB + waveC)
                          * baseAmplitude
                        + gust
                        - rebound,

                    y:
                        121
                        + t * 205
                        + Math.sin(
                            time * 0.91
                            + t * 8.4
                        )
                        * 1.8
                        * Math.pow(t, 1.25)
                }
            }

            function kiteBadgePoint(index, count) {
                /*
                 * Spread app badges along the lower 78% of the string,
                 * leaving a little breathing room immediately under the kite.
                 */
                const safeCount = Math.max(1, count)
                const t =
                    safeCount === 1
                    ? 0.58
                    : 0.28 + (index / (safeCount - 1)) * 0.64

                const steps = 24
                return kiteStringPoint(
                    Math.round(t * (steps - 1)),
                    steps
                )
            }

            function beginWorkspaceDrag(workspaceId, px, py) {
                if (settingsOpen || workspaceWarningActive || dragActive)
                    return

                const count = windowCountForWorkspace(workspaceId)
                if (count <= 0)
                    return

                workspaceDragSource = workspaceId
                workspaceDragTarget = 0
                workspaceDragWindowCount = count
                activeDeliveryAnimation = workspaceMoveAnimation
                workspaceDragToppings = workspaceToppingsFor(workspaceId)
                workspaceDragStartX = px
                workspaceDragStartY = py
                workspaceDragX = px
                workspaceDragY = py
                workspaceDragVelocityX = 0
                workspaceDragVelocityY = 0
                workspaceDragSpeed = 0
                workspaceDragTilt = 0
                workspaceTrailAngle = 0
                workspaceTrailPulse = 0
                pizzaTrailPulse = 0
                workspaceGhostScale = 1.0
                workspaceGhostOpacity = 0.0
                workspaceDragAnimating = false
                workspaceDragActive = false
                workspaceMoveConfirmActive = false
            }

            function updateWorkspaceDrag(px, py) {
                if (workspaceDragSource <= 0 || workspaceMoveConfirmActive)
                    return

                const velocityX = px - workspaceDragX
                const velocityY = py - workspaceDragY
                const speed = Math.sqrt(
                    velocityX * velocityX
                    + velocityY * velocityY
                )

                workspaceDragVelocityX = velocityX
                workspaceDragVelocityY = velocityY
                workspaceDragSpeed = speed

                /*
                 * Only change the flight heading when the pointer actually
                 * moves. This prevents the exhaust direction from jittering
                 * while the user pauses over a destination.
                 */
                if (speed > 0.35) {
                    workspaceTrailAngle =
                        Math.atan2(velocityY, velocityX)
                        * 180 / Math.PI

                    /*
                     * More pronounced than the prototype, but still restrained
                     * enough to keep app toppings readable.
                     */
                    workspaceDragTilt =
                        Math.max(
                            -19,
                            Math.min(
                                19,
                                velocityX * 1.65
                            )
                        )
                }

                workspaceDragX = px
                workspaceDragY = py

                if (!workspaceDragActive) {
                    const dx = px - workspaceDragStartX
                    const dy = py - workspaceDragStartY
                    if (Math.sqrt(dx * dx + dy * dy) >= workspaceDragThreshold) {
                        workspaceDragActive = true
                        workspaceGhostOpacity = 1.0
                    }
                }

                if (!workspaceDragActive)
                    return

                const candidate = workspaceAtPoint(px, py)
                workspaceDragTarget =
                    candidate > 0 && candidate !== workspaceDragSource
                    ? candidate
                    : 0
            }

            function finishWorkspaceDrag(px, py) {
                if (workspaceDragSource <= 0)
                    return

                if (!workspaceDragActive) {
                    resetWorkspaceDrag()
                    return
                }

                const candidate = workspaceAtPoint(px, py)
                if (candidate <= 0 || candidate === workspaceDragSource) {
                    returnWorkspaceMoveToSource()
                    return
                }

                workspaceDragTarget = candidate
                const targetPoint = workspaceLabelPoint(candidate)
                workspaceDragAnimating = true
                workspaceDragX = targetPoint.x
                workspaceDragY = targetPoint.y
                workspaceMoveConfirmActive = true
                workspaceDragActive = false
                workspaceDragTilt = 0
                workspaceDragSpeed = 0
                workspaceGhostScale = 0.92
                radialCanvas.requestPaint()
            }

            function returnWorkspaceMoveToSource() {
                if (workspaceDragSource <= 0) {
                    resetWorkspaceDrag()
                    return
                }

                const sourcePoint = workspaceLabelPoint(workspaceDragSource)
                workspaceMoveConfirmActive = false
                workspaceDragActive = false
                workspaceDragTarget = 0
                workspaceDragAnimating = true
                workspaceDragTilt = 0
                workspaceDragSpeed = 0
                workspaceGhostScale = 0.88
                workspaceDragX = sourcePoint.x
                workspaceDragY = sourcePoint.y
                workspaceReturnTimer.restart()
                radialCanvas.requestPaint()
            }

            function deliverWorkspaceMove() {
                if (!workspaceMoveConfirmActive
                        || workspaceDragSource <= 0
                        || workspaceDragTarget <= 0
                        || workspaceDragSource === workspaceDragTarget) {
                    return
                }

                /*
                 * Capture the exact clients before dispatching anything.
                 * This keeps the operation deterministic even while
                 * Hyprland's client list changes as windows migrate.
                 */
                const sourceWorkspace = workspaceDragSource
                const destinationWorkspace = workspaceDragTarget
                const addresses = []

                for (let i = 0; i < clients.length; ++i) {
                    const client = clients[i]

                    if (!client
                            || !client.address
                            || !client.workspace
                            || client.workspace.id !== sourceWorkspace) {
                        continue
                    }

                    addresses.push(String(client.address))
                }

                if (addresses.length <= 0) {
                    returnWorkspaceMoveToSource()
                    return
                }

                /*
                 * Keep the already-approved kite animation exactly as
                 * before: the destination accepts the flight while the
                 * compositor performs the real migration.
                 */
                const targetPoint = workspaceLabelPoint(destinationWorkspace)
                workspaceMoveConfirmActive = false
                workspaceDragAnimating = true
                workspaceDragX = targetPoint.x
                workspaceDragY = targetPoint.y
                workspaceGhostScale = 0.12
                workspaceGhostOpacity = 0.0
                radialCanvas.requestPaint()

                /*
                 * One compositor-side evaluation moves the captured
                 * clients. Hyprland remains responsible for arranging
                 * them inside the destination workspace.
                 */
                let expression = ""

                for (let j = 0; j < addresses.length; ++j) {
                    expression +=
                        'hl.dispatch(hl.dsp.window.move({ workspace = "' +
                        destinationWorkspace +
                        '", window = "address:' +
                        addresses[j] +
                        '", follow = false }))\n'
                }

                Quickshell.execDetached([
                    "hyprctl",
                    "eval",
                    expression
                ])

                /*
                 * Every passenger on this kite is a new arrival. Because the
                 * exact source addresses were captured before migration, all
                 * and only those destination bubbles receive the same visual
                 * arrival treatment.
                 */
                markArrivalWindows(addresses)

                workspaceAbsorbTimer.restart()
                workspaceMigrationRefreshTimer.restart()
            }

            function resetWorkspaceDrag() {
                workspaceDragActive = false
                workspaceMoveConfirmActive = false
                workspaceDragAnimating = false
                workspaceDragSource = 0
                workspaceDragTarget = 0
                workspaceDragWindowCount = 0
                workspaceDragToppings = []
                workspaceDragVelocityX = 0
                workspaceDragVelocityY = 0
                workspaceDragSpeed = 0
                workspaceDragTilt = 0
                workspaceTrailAngle = 0
                workspaceTrailPulse = 0
                pizzaTrailPulse = 0
                workspaceGhostScale = 1.0
                workspaceGhostOpacity = 0.0
                radialCanvas.requestPaint()
                forceActiveFocus()
            }

            NumberAnimation {
                id: workspaceTrailAnimation

                target: root
                property: "workspaceTrailPulse"

                running:
                    root.workspaceDragActive
                    || root.workspaceMoveConfirmActive
                    || root.workspaceDragAnimating

                loops: Animation.Infinite
                from: 0
                to: 1
                duration: 1180
                easing.type: Easing.Linear
            }

            SequentialAnimation {
                id: pizzaTrailAnimation

                running:
                    root.activeDeliveryAnimation === "pizza"
                    && root.workspaceDragActive

                loops: Animation.Infinite

                NumberAnimation {
                    target: root
                    property: "pizzaTrailPulse"
                    from: 0
                    to: 1
                    duration: 150
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    target: root
                    property: "pizzaTrailPulse"
                    from: 1
                    to: 0
                    duration: 170
                    easing.type: Easing.InOutQuad
                }
            }

            Timer {
                id: workspaceReturnTimer
                interval: 260
                repeat: false
                onTriggered: root.resetWorkspaceDrag()
            }

            Timer {
                id: workspaceAbsorbTimer
                interval: 300
                repeat: false
                onTriggered: root.resetWorkspaceDrag()
            }

            Timer {
                id: workspaceMigrationRefreshTimer
                interval: 520
                repeat: false

                onTriggered: {
                    root.refreshClients()
                }
            }

            /*
             * --------------------------------------------------
             * ADAPTIVE WINDOW GEOMETRY
             * --------------------------------------------------
             */

            function bubbleDiameter(windowCount) {
                if (windowCount <= 0)
                    return 0

                const sectorAngle =
                    (Math.PI * 2)
                    / displayedWorkspaceCount

                /*
                 * Arc available for this workspace at the center
                 * line of the window ring.
                 */
                const fullArcLength =
                    windowRingRadius
                    * sectorAngle

                /*
                 * Reserve roughly 15% for breathing room.
                 */
                const usableArcLength =
                    fullArcLength * 0.85

                /*
                 * This lets bubble size automatically shrink as
                 * the number of windows increases.
                 */
                const diameterFromArc =
                    usableArcLength
                    / windowCount
                    * 0.78

                /*
                 * Prevent a single window from becoming taller
                 * than the outer ring itself.
                 */
                const maxDiameter =
                    outerRingThickness * 0.68

                const minDiameter = 40

                return Math.max(
                    minDiameter,
                    Math.min(
                        maxDiameter,
                        diameterFromArc
                    )
                )
            }

            /*
             * Calculate the angular center of a bubble.
             *
             * Unlike our earlier fixed 12% margin, this uses the
             * bubble's actual physical radius.
             *
             * Therefore the FULL circle stays inside its sector.
             */

            function bubbleAngle(
                workspaceIndex,
                windowIndex,
                windowCount,
                diameter
            ) {
                const sectorStep =
                    (Math.PI * 2)
                    / displayedWorkspaceCount

                const sectorStart =
                    -Math.PI / 2
                    + workspaceIndex
                    * sectorStep

                const sectorEnd =
                    sectorStart
                    + sectorStep

                if (windowCount === 1) {
                    return sectorStart
                        + sectorStep / 2
                }

                /*
                 * Convert physical bubble radius to angular
                 * clearance at the window ring radius.
                 */
                const physicalMargin =
                    diameter / 2 + 5

                const ratio =
                    Math.min(
                        0.95,
                        physicalMargin
                        / windowRingRadius
                    )

                const angularMargin =
                    Math.asin(ratio)

                const firstAngle =
                    sectorStart
                    + angularMargin

                const lastAngle =
                    sectorEnd
                    - angularMargin

                if (windowCount === 2) {
                    return windowIndex === 0
                        ? firstAngle
                        : lastAngle
                }

                const usableAngle =
                    lastAngle - firstAngle

                return firstAngle
                    + (
                        usableAngle
                        * windowIndex
                        / (windowCount - 1)
                    )
            }

            /*
             * --------------------------------------------------
             * DISPLAY HELPERS
             * --------------------------------------------------
             */

            function shortClassName(client) {
                if (!client || !client.class)
                    return "Window"

                let value = client.class

                if (value.indexOf(".") !== -1) {
                    const parts =
                        value.split(".")

                    value =
                        parts[
                            parts.length - 1
                        ]
                }

                if (value.length > 16) {
                    value =
                        value.substring(
                            0,
                            15
                        )
                        + "…"
                }

                return value
            }

            function shortTitle(client) {
                if (!client || !client.title)
                    return ""

                if (client.title.length > 22) {
                    return client.title.substring(
                        0,
                        21
                    ) + "…"
                }

                return client.title
            }

            /*
             * --------------------------------------------------
             * HYPRLAND CLIENT PROCESS
             * --------------------------------------------------
             */

            Process {
                id: clientsProcess

                running: false

                command: [
                    "hyprctl",
                    "clients",
                    "-j"
                ]

                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const parsedClients =
                                JSON.parse(
                                    this.text
                                )

                            /*
                             * Replacing the array causes every
                             * workspace's outer-ring model to be
                             * rebuilt and therefore realigned.
                             */
                            root.clients =
                                parsedClients

                            root.clientRevision++

                            console.log(
                                "Radial Overview:",
                                parsedClients.length,
                                "clients loaded"
                            )
                        } catch (error) {
                            console.log(
                                "Radial Overview client parse error:",
                                error
                            )

                            root.clients = []
                            root.clientRevision++
                        }
                    }
                }
            }

            /*
             * --------------------------------------------------
             * HYPRLAND MONITOR / WORKSPACE TOPOLOGY
             * --------------------------------------------------
             */

            Process {
                id: monitorsProcess

                running: false

                command: [
                    "hyprctl",
                    "monitors",
                    "-j"
                ]

                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            root.monitors =
                                JSON.parse(this.text)

                            root.topologyRevision++
                        } catch (error) {
                            console.log(
                                "Radial Overview monitor parse error:",
                                error
                            )

                            root.monitors = []
                            root.topologyRevision++
                        }
                    }
                }
            }

            Process {
                id: workspacesProcess

                running: false

                command: [
                    "hyprctl",
                    "workspaces",
                    "-j"
                ]

                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            root.hyprWorkspaces =
                                JSON.parse(this.text)

                            root.topologyRevision++
                        } catch (error) {
                            console.log(
                                "Radial Overview workspace topology parse error:",
                                error
                            )

                            root.hyprWorkspaces = []
                            root.topologyRevision++
                        }
                    }
                }
            }

            /*
             * --------------------------------------------------
             * KEYBOARD
             * --------------------------------------------------
             */

            Keys.onEscapePressed: {
                if (root.workspaceMoveConfirmActive || root.workspaceDragActive) {
                    root.returnWorkspaceMoveToSource()
                } else if (root.settingsOpen) {
                    root.closeSettings()
                } else if (root.workspaceWarningActive) {
                    root.dismissWorkspaceWarning()
                } else if (root.dragActive) {
                    root.cancelPointerInteraction()
                } else {
                    root.requestClose()
                }
            }

            Shortcut {
                sequence: "Esc"
                context: Qt.WindowShortcut

                onActivated: {
                    if (root.workspaceMoveConfirmActive || root.workspaceDragActive) {
                        root.returnWorkspaceMoveToSource()
                    } else if (root.settingsOpen) {
                        root.closeSettings()
                    } else if (root.workspaceWarningActive) {
                        root.workspaceWarningActive = false
                        root.workspaceWarningIds = []
                        root.workspaceWarningRequestedCount = 0
                        radialCanvas.requestPaint()
                    } else if (root.dragActive) {
                        root.cancelPointerInteraction()
                    } else {
                        root.requestClose()
                    }
                }
            }

            /*
             * --------------------------------------------------
             * RADIAL GEOMETRY
             * --------------------------------------------------
             */

            Canvas {
                id: radialCanvas
                anchors.fill: parent

                onPaint: {
                    const ctx =
                        getContext("2d")

                    ctx.reset()

                    const cx =
                        root.centerX

                    const cy =
                        root.centerY

                    const hubR =
                        root.hubRadius

                    const innerR =
                        root.innerOuterRadius

                    const outerR =
                        root.outerOuterRadius

                    const count =
                        root.displayedWorkspaceCount

                    const step =
                        (Math.PI * 2)
                        / count

                    /*
                     * Highlight the ENTIRE destination wedge,
                     * including both inner and outer rings.
                     */

                    const highlightedWorkspace =
                        root.workspaceDragTarget > 0
                        ? root.workspaceDragTarget
                        : root.dragTargetWorkspace

                    if (((root.dragActive || root.dropFeedbackActive)
                            && root.dragTargetWorkspace > 0)
                            || ((root.workspaceDragActive
                                 || root.workspaceMoveConfirmActive)
                                && root.workspaceDragTarget > 0)) {

                        const targetIndex =
                            highlightedWorkspace - 1

                        const startAngle =
                            -Math.PI / 2
                            + targetIndex
                            * step

                        const endAngle =
                            startAngle
                            + step

                        ctx.fillStyle =
                            (
                                (root.workspaceDragActive
                                 || root.workspaceMoveConfirmActive)
                                && root.workspaceDragTarget > 0
                            )
                            ? root.kiteDestinationAtmosphereColor
                            : root.dropHighlightColor

                        ctx.beginPath()

                        ctx.arc(
                            cx,
                            cy,
                            outerR,
                            startAngle,
                            endAngle,
                            false
                        )

                        ctx.arc(
                            cx,
                            cy,
                            hubR,
                            endAngle,
                            startAngle,
                            true
                        )

                        ctx.closePath()
                        ctx.fill()
                    }

                    ctx.lineWidth = 2
                    ctx.strokeStyle =
                        root.accentColor

                    ctx.beginPath()
                    ctx.arc(
                        cx,
                        cy,
                        hubR,
                        0,
                        Math.PI * 2
                    )
                    ctx.stroke()

                    ctx.beginPath()
                    ctx.arc(
                        cx,
                        cy,
                        innerR,
                        0,
                        Math.PI * 2
                    )
                    ctx.stroke()

                    ctx.beginPath()
                    ctx.arc(
                        cx,
                        cy,
                        outerR,
                        0,
                        Math.PI * 2
                    )
                    ctx.stroke()

                    for (let i = 0;
                         i < count;
                         ++i) {

                        const angle =
                            -Math.PI / 2
                            + i * step

                        const x1 =
                            cx
                            + Math.cos(angle)
                            * hubR

                        const y1 =
                            cy
                            + Math.sin(angle)
                            * hubR

                        const x2 =
                            cx
                            + Math.cos(angle)
                            * outerR

                        const y2 =
                            cy
                            + Math.sin(angle)
                            * outerR

                        ctx.beginPath()

                        ctx.moveTo(
                            x1,
                            y1
                        )

                        ctx.lineTo(
                            x2,
                            y2
                        )

                        ctx.stroke()
                    }
                }

                onWidthChanged:
                    requestPaint()

                onHeightChanged:
                    requestPaint()
            }

            /*
             * --------------------------------------------------
             * INNER WORKSPACE RING
             * --------------------------------------------------
             */

            Repeater {
                model:
                    root.displayedWorkspaceCount

                Item {
                    id:
                        workspaceDelegate

                    required property int index

                    property int workspaceId:
                        index + 1

                    property int clientCount:
                        root.windowCountForWorkspace(
                            workspaceId
                        )
                        + (
                            root.clientRevision
                            * 0
                        )

                    property bool active:
                        Hyprland.focusedWorkspace
                        !== null
                        && Hyprland.focusedWorkspace.id
                        === workspaceId

                    property bool dropTarget:
                        (root.dragActive || root.dropFeedbackActive)
                        && root.dragTargetWorkspace
                        === workspaceId

                    property bool warningTarget:
                        root.isWorkspaceWarning(workspaceId)

                    property bool workspaceMoveTarget:
                        (root.workspaceDragActive || root.workspaceMoveConfirmActive)
                        && root.workspaceDragTarget === workspaceId

                    property string monitorName:
                        root.workspaceMonitorName(
                            workspaceId
                        )

                    property bool monitorFocused:
                        root.isFocusedMonitor(
                            monitorName
                        )

                    property real step:
                        (Math.PI * 2)
                        / root.displayedWorkspaceCount

                    property real angle:
                        -Math.PI / 2
                        + (
                            (index + 0.5)
                            * step
                        )

                    property real labelRadius:
                        (
                            root.hubRadius
                            + root.innerOuterRadius
                        ) / 2

                    width: 124
                    height: 92

                    scale: workspaceMoveTarget ? 1.10 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    x:
                        root.centerX
                        + Math.cos(angle)
                        * labelRadius
                        - width / 2

                    y:
                        root.centerY
                        + Math.sin(angle)
                        * labelRadius
                        - height / 2

                    Column {
                        anchors.centerIn:
                            parent

                        spacing: 3

                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 52
                            height: 38

                            Text {
                                anchors.centerIn: parent
                                text: workspaceDelegate.workspaceId

                                color:
                                    workspaceDelegate.workspaceMoveTarget
                                    ? root.accentSecondaryColor
                                    : (
                                        workspaceDelegate.warningTarget
                                        ? root.accentSecondaryColor
                                        : (
                                            workspaceDelegate.dropTarget
                                            ? root.foregroundColor
                                            : (
                                                workspaceDelegate.active
                                                ? root.accentColor
                                                : root.foregroundColor
                                            )
                                        )
                                    )

                                font.pixelSize:
                                    workspaceDelegate.workspaceMoveTarget
                                    ? 34
                                    : (
                                        workspaceDelegate.warningTarget
                                        ? 32
                                        : (workspaceDelegate.dropTarget ? 32 : 28)
                                    )
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                hoverEnabled: true
                                cursorShape:
                                    workspaceDelegate.clientCount > 0
                                    ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                    : Qt.ArrowCursor

                                onPressed: function(mouse) {
                                    if (workspaceDelegate.clientCount <= 0)
                                        return
                                    const p = mapToItem(root, mouse.x, mouse.y)
                                    root.beginWorkspaceDrag(
                                        workspaceDelegate.workspaceId, p.x, p.y)
                                }

                                onPositionChanged: function(mouse) {
                                    if (!pressed)
                                        return
                                    const p = mapToItem(root, mouse.x, mouse.y)
                                    root.updateWorkspaceDrag(p.x, p.y)
                                }

                                onReleased: function(mouse) {
                                    const p = mapToItem(root, mouse.x, mouse.y)
                                    root.finishWorkspaceDrag(p.x, p.y)
                                }

                                onCanceled: root.returnWorkspaceMoveToSource()
                            }
                        }

                        Text {
                            anchors.horizontalCenter:
                                parent.horizontalCenter

                            text:
                                workspaceDelegate.dropTarget
                                ? "Drop here"
                                : (
                                    workspaceDelegate.clientCount
                                    === 1
                                    ? "1 window"
                                    : workspaceDelegate.clientCount
                                      + " windows"
                                )

                            color:
                                workspaceDelegate.warningTarget
                                ? root.accentSecondaryColor
                                : (
                                    workspaceDelegate.dropTarget
                                    ? root.accentColor
                                    : (
                                        workspaceDelegate.active
                                        ? root.accentColor
                                        : root.mutedColor
                                    )
                                )

                            font.pixelSize: 12
                        }

                        Text {
                            anchors.horizontalCenter:
                                parent.horizontalCenter

                            visible:
                                root.monitorCount > 1
                                && workspaceDelegate.monitorName !== ""

                            text:
                                "▣ "
                                + workspaceDelegate.monitorName

                            color:
                                root.foregroundColor
                            // workspaceDelegate.monitorFocused
                                // ? root.accentColor
                                // : root.mutedColor

                            font.pixelSize: 10
                            font.bold:
                               workspaceDelegate.monitorFocused
 
                         }
                    }
                }
            }

            /*
             * --------------------------------------------------
             * OUTER WINDOW RING
             * --------------------------------------------------
             */

            Repeater {
                model:
                    root.displayedWorkspaceCount

                Item {
                    id:
                        outerWorkspace

                    required property int index

                    anchors.fill: parent

                    property int workspaceId:
                        index + 1

                    /*
                     * IMPORTANT:
                     *
                     * Referencing clientRevision inside this block
                     * guarantees workspaceClients is recalculated
                     * after every move.
                     */
                    property var workspaceClients: {
                        const revision =
                            root.clientRevision

                        return root.clientsForWorkspace(
                            workspaceId
                        )
                    }

                    property int windowCount:
                        workspaceClients.length

                    property real diameter:
                        root.bubbleDiameter(
                            windowCount
                        )

                    Repeater {
                        model:
                            outerWorkspace.workspaceClients

                        Item {
                            id:
                                bubbleDelegate

                            required property int index
                            required property var modelData

                            property var client:
                                modelData

                            property var desktopEntryDependency:
                                root.desktopApplications

                            property string appIconPath:
                                root.appIconPathFor(client)

                            property string appDisplayName:
                                root.appDisplayNameFor(client)

                            property bool focused:
                                root.isFocusedClient(client)

                            property bool tooltipReady: false

                            property real diameter:
                                outerWorkspace.diameter

                            property real angle:
                                root.bubbleAngle(
                                    outerWorkspace.index,
                                    index,
                                    outerWorkspace.windowCount,
                                    diameter
                                )

                            width:
                                diameter

                            height:
                                diameter

                            x:
                                root.centerX
                                + Math.cos(angle)
                                * root.windowRingRadius
                                - width / 2

                            y:
                                root.centerY
                                + Math.sin(angle)
                                * root.windowRingRadius
                                - height / 2

                            z:
                                bubbleMouse.containsMouse
                                ? 100
                                : 0

                            Timer {
                                id: tooltipTimer
                                interval: 400
                                repeat: false

                                onTriggered: {
                                    if (bubbleMouse.containsMouse
                                        && !root.dragActive)
                                        bubbleDelegate.tooltipReady = true
                                }
                            }

                            /*
                             * Persistent newly-dropped-window marker.
                             *
                             * No flashing or timeout: the most recent
                             * individual arrival, or all windows from the
                             * most recent kite delivery, retain this derived
                             * outer ring until another successful drop occurs.
                             */
                            Rectangle {
                                id: arrivalHalo

                                visible:
                                    root.isArrivalWindow(
                                        bubbleDelegate.client
                                    )

                                z: -2

                                x: -7
                                y: -7
                                width: parent.width + 14
                                height: parent.height + 14

                                radius: width / 2
                                color: "transparent"

                                border.width: 3
                                border.color:
                                    root.radialSunColor

                                /*
                                 * Keep it visually distinct from focus/hover
                                 * without animation.
                                 */
                                opacity: 0.96
                            }

                            Rectangle {
                                id: focusHalo

                                visible:
                                    bubbleDelegate.focused
                                    && !(
                                        root.dragActive
                                        && root.draggedClient
                                        && root.draggedClient.address
                                        === bubbleDelegate.client.address
                                    )

                                z: -1

                                x: -5
                                y: -5
                                width: parent.width + 10
                                height: parent.height + 10

                                radius: width / 2
                                color: "transparent"

                                border.width: 2
                                border.color: root.accentColor
                                opacity: 0.55

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                            }

                            Rectangle {
                                id: bubble

                                anchors.fill:
                                    parent

                                radius:
                                    width / 2

                                color:
                                    (
                                        bubbleMouse.containsMouse
                                        || bubbleDelegate.focused
                                    )
                                    ? theme.surfaceHover
                                    : root.bubbleBackground

                                border.width:
                                    (
                                        bubbleMouse.containsMouse
                                        || bubbleDelegate.focused
                                    )
                                    ? 3
                                    : 2

                                border.color:
                                    root.accentColor

                                scale:
                                    bubbleMouse.containsMouse
                                    ? 1.07
                                    : (
                                        bubbleDelegate.focused
                                        ? 1.035
                                        : 1.0
                                    )

                                opacity:
                                    (root.dragActive || root.dropFeedbackActive)
                                    && root.draggedClient
                                    && root.draggedClient.address
                                    === bubbleDelegate.client.address
                                    ? 0.35
                                    : 1.0

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 90
                                    }
                                }

                                Column {
                                    anchors.centerIn:
                                        parent

                                    width:
                                        parent.width
                                        * 0.78

                                    spacing: 2

                                    Item {
                                        anchors.horizontalCenter:
                                            parent.horizontalCenter

                                        width:
                                            Math.max(
                                                26,
                                                bubbleDelegate.diameter * 0.46
                                            )

                                        height: width

                                        Image {
                                            anchors.fill: parent
                                            source: bubbleDelegate.appIconPath
                                            visible: source.toString().length > 0
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                        }

                                        Text {
                                            anchors.centerIn: parent

                                            visible:
                                                bubbleDelegate.appIconPath.length === 0

                                            text:
                                                root.shortClassName(
                                                    bubbleDelegate.client
                                                )
                                                .charAt(0)
                                                .toUpperCase()

                                            color:
                                                root.accentColor

                                            font.pixelSize:
                                                Math.max(
                                                    14,
                                                    bubbleDelegate.diameter
                                                    * 0.27
                                                )

                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.horizontalCenter:
                                            parent.horizontalCenter

                                        width:
                                            parent.width

                                        horizontalAlignment:
                                            Text.AlignHCenter

                                        elide:
                                            Text.ElideRight

                                        visible:
                                            bubbleDelegate.diameter
                                            >= 58

                                        text:
                                            bubbleDelegate.appDisplayName

                                        color:
                                            bubbleDelegate.focused
                                            ? root.accentColor
                                            : root.foregroundColor

                                        font.pixelSize:
                                            Math.max(
                                                9,
                                                Math.min(
                                                    13,
                                                    bubbleDelegate.diameter
                                                    * 0.12
                                                )
                                            )
                                    }

                                    Text {
                                        anchors.horizontalCenter:
                                            parent.horizontalCenter

                                        width:
                                            parent.width

                                        horizontalAlignment:
                                            Text.AlignHCenter

                                        elide:
                                            Text.ElideRight

                                        visible:
                                            bubbleDelegate.diameter
                                            >= 96

                                        text:
                                            root.shortTitle(
                                                bubbleDelegate.client
                                            )

                                        color:
                                            root.mutedColor

                                        font.pixelSize: 9
                                    }
                                }

                                Rectangle {
                                    visible: bubbleDelegate.focused

                                    anchors.horizontalCenter:
                                        parent.horizontalCenter

                                    anchors.bottom:
                                        parent.bottom

                                    anchors.bottomMargin:
                                        Math.max(5, parent.height * 0.07)

                                    width:
                                        Math.max(5, parent.width * 0.07)

                                    height: width
                                    radius: width / 2
                                    color: root.accentColor
                                }

                                Rectangle {
                                    id: windowTooltip

                                    visible:
                                        bubbleDelegate.tooltipReady
                                        && bubbleMouse.containsMouse
                                        && !root.dragActive
                                        && !root.dropFeedbackActive

                                    z: 1000

                                    width:
                                        Math.min(
                                            320,
                                            Math.max(
                                                180,
                                                tooltipContent.implicitWidth + 24
                                            )
                                        )

                                    height:
                                        tooltipContent.implicitHeight + 18

                                    x: {
                                        const preferred =
                                            (bubble.width - width) / 2

                                        const minimum =
                                            -bubbleDelegate.x + 12

                                        const maximum =
                                            root.width
                                            - bubbleDelegate.x
                                            - width
                                            - 12

                                        return Math.max(
                                            minimum,
                                            Math.min(preferred, maximum)
                                        )
                                    }

                                    y:
                                        bubbleDelegate.y
                                        + bubble.height
                                        + height
                                        + 12
                                        > root.height
                                        ? -height - 10
                                        : bubble.height + 10

                                    radius: 8
                                    color: root.bubbleBackground

                                    border.width: 1
                                    border.color: root.accentColor

                                    opacity: visible ? 1.0 : 0.0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 90
                                        }
                                    }

                                    Column {
                                        id: tooltipContent

                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            margins: 12
                                        }

                                        spacing: 3

                                        Text {
                                            width: parent.width
                                            text: bubbleDelegate.appDisplayName
                                            color: root.foregroundColor
                                            font.pixelSize: 12
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            text:
                                                bubbleDelegate.client
                                                && bubbleDelegate.client.title
                                                ? String(bubbleDelegate.client.title)
                                                : ""
                                            color: root.mutedColor
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            visible: text.length > 0
                                        }
                                    }
                                }

                                MouseArea {
                                    id:
                                        bubbleMouse

                                    anchors.fill:
                                        parent

                                    acceptedButtons:
                                        Qt.LeftButton

                                    hoverEnabled: true

                                    cursorShape:
                                        root.dragActive
                                        ? Qt.ClosedHandCursor
                                        : Qt.PointingHandCursor

                                    onEntered: {
                                        bubbleDelegate.tooltipReady = false
                                        tooltipTimer.restart()
                                    }

                                    onExited: {
                                        tooltipTimer.stop()
                                        bubbleDelegate.tooltipReady = false
                                    }

                                    onPressed:
                                        function(mouse) {
                                            tooltipTimer.stop()
                                            bubbleDelegate.tooltipReady = false

                                            const point =
                                                bubbleMouse.mapToItem(
                                                    root,
                                                    mouse.x,
                                                    mouse.y
                                                )

                                            root.beginPointerInteraction(
                                                bubbleDelegate.client,
                                                point.x,
                                                point.y
                                            )
                                        }

                                    onPositionChanged:
                                        function(mouse) {

                                            if (!pressed)
                                                return

                                            const point =
                                                bubbleMouse.mapToItem(
                                                    root,
                                                    mouse.x,
                                                    mouse.y
                                                )

                                            root.updatePointerInteraction(
                                                point.x,
                                                point.y
                                            )
                                        }

                                    onReleased:
                                        function(mouse) {

                                            const point =
                                                bubbleMouse.mapToItem(
                                                    root,
                                                    mouse.x,
                                                    mouse.y
                                                )

                                            root.finishPointerInteraction(
                                                point.x,
                                                point.y
                                            )
                                        }

                                    onCanceled: {
                                        tooltipTimer.stop()
                                        bubbleDelegate.tooltipReady = false
                                        root.cancelPointerInteraction()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            /*
             * --------------------------------------------------
             * DRAG PROXY
             * --------------------------------------------------
             */

            Rectangle {
                id:
                    dragProxy

                visible:
                    (root.dragActive || root.dropFeedbackActive)
                    && root.draggedClient !== null

                z: 1000

                width: 74
                height: 74

                x:
                    root.dragX
                    - width / 2

                y:
                    root.dragY
                    - height / 2

                radius:
                    width / 2

                color:
                    theme.surfaceHover

                border.width: 3

                border.color:
                    root.accentColor

                opacity:
                    root.dropFeedbackActive
                    ? 0.0
                    : 0.92

                scale:
                    root.dropFeedbackActive
                    ? 0.82
                    : 1.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                }

                Column {
                    anchors.centerIn:
                        parent

                    width:
                        parent.width * 0.78

                    spacing: 2

                    Item {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        width: 36
                        height: 36

                        property var desktopEntryDependency:
                            root.desktopApplications

                        property string iconPath:
                            root.draggedClient
                            ? root.appIconPathFor(root.draggedClient)
                            : ""

                        Image {
                            anchors.fill: parent
                            source: parent.iconPath
                            visible: source.toString().length > 0
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }

                        Text {
                            anchors.centerIn: parent

                            visible: parent.iconPath.length === 0

                            text:
                                root.draggedClient
                                ? root.shortClassName(
                                    root.draggedClient
                                )
                                .charAt(0)
                                .toUpperCase()
                                : ""

                            color:
                                root.radialSunColor

                            font.pixelSize: 22
                            font.bold: true
                        }
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        width:
                            parent.width

                        horizontalAlignment:
                            Text.AlignHCenter

                        elide:
                            Text.ElideRight

                        text:
                            root.draggedClient
                            ? root.appDisplayNameFor(
                                root.draggedClient
                            )
                            : ""

                        color:
                            root.foregroundColor

                        font.pixelSize: 10
                    }
                }
            }

            /*
             * --------------------------------------------------
             * WORKSPACE MOVE VISUAL LAYER
             * --------------------------------------------------
             */
            Item {
                id: workspaceMoveVisualLayer
                anchors.fill: parent
                z: 930
                visible:
                    root.workspaceDragSource > 0
                    && (root.workspaceDragActive
                        || root.workspaceMoveConfirmActive
                        || root.workspaceDragAnimating)

                /*
                 * --------------------------------------------------
                 * RECEIVING CLOUDS
                 * --------------------------------------------------
                 *
                 * A valid workspace destination grows a soft cloud bank.
                 * Its palette is generated from the active theme, but uses
                 * derived lighter/darker/cooler tones so it remains visually
                 * distinct from the rest of the radial.
                 */
                Item {
                    id: receivingClouds

                    visible:
                        root.activeDeliveryAnimation === "kite"
                        && root.workspaceDragTarget > 0

                    width: 158
                    height: 88
                    z: 1

                    property real targetAngle:
                        root.workspaceDragTarget > 0
                        ? -Math.PI / 2
                          + (
                              (root.workspaceDragTarget - 0.5)
                              * (
                                  (Math.PI * 2)
                                  / root.displayedWorkspaceCount
                              )
                            )
                        : 0

                    /*
                     * Different frequencies avoid a mechanical back/forth
                     * cloud motion.
                     */
                    property real drift:
                        Math.sin(
                            root.workspaceTrailPulse
                            * Math.PI * 2
                            * 0.61
                            + root.workspaceDragTarget * 0.73
                        ) * 5.5
                        + Math.sin(
                            root.workspaceTrailPulse
                            * Math.PI * 2
                            * 1.27
                            + 1.8
                        ) * 2.0

                    property real bob:
                        Math.sin(
                            root.workspaceTrailPulse
                            * Math.PI * 2
                            * 0.83
                            + 0.8
                        ) * 2.8
                        + Math.max(
                            0,
                            Math.sin(
                                root.workspaceTrailPulse
                                * Math.PI * 2
                                * 0.39
                                + 2.1
                            )
                          ) * 1.8

                    x:
                        root.centerX
                        + Math.cos(targetAngle)
                          * (root.innerOuterRadius + 54)
                        - width / 2
                        + drift

                    y:
                        root.centerY
                        + Math.sin(targetAngle)
                          * (root.innerOuterRadius + 54)
                        - height / 2
                        + bob

                    opacity:
                        visible
                        ? 0.96
                        : 0.0

                    scale:
                        visible
                        ? (
                            1.0
                            + Math.sin(
                                root.workspaceTrailPulse
                                * Math.PI * 2
                                * 0.71
                            ) * 0.025
                          )
                        : 0.80

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 210
                            easing.type: Easing.OutBack
                        }
                    }

                    /*
                     * Soft shadow underneath gives the cloud a recognizable
                     * floating silhouette even on themes where base colors
                     * are very similar.
                     */
                    Rectangle {
                        x: 24
                        y: 60

                        width: 112
                        height: 17
                        radius: 9

                        color:
                            root.cloudShadowColor

                        opacity: 0.36

                        scale:
                            1.0
                            + Math.sin(
                                root.workspaceTrailPulse
                                * Math.PI * 2
                                * 0.54
                            ) * 0.045
                    }

                    /*
                     * Rear cloud bank.
                     */
                    Item {
                        x:
                            5
                            + Math.sin(
                                root.workspaceTrailPulse
                                * Math.PI * 2
                                * 0.49
                                + 1.2
                            ) * 2.5

                        y: 27
                        width: 108
                        height: 47
                        opacity: 0.72

                        Rectangle {
                            x: 8
                            y: 24
                            width: 91
                            height: 20
                            radius: 11

                            color:
                                root.cloudShadowColor
                        }

                        Rectangle {
                            x: 19
                            y: 12
                            width: 34
                            height: 34
                            radius: 17

                            color:
                                root.cloudMidColor
                        }

                        Rectangle {
                            x: 45
                            y: 5
                            width: 43
                            height: 43
                            radius: 22

                            color:
                                root.cloudMidColor
                        }

                        Rectangle {
                            x: 75
                            y: 16
                            width: 29
                            height: 29
                            radius: 15

                            color:
                                root.cloudShadowColor
                        }
                    }

                    /*
                     * Front cloud bank: a broad base with uneven lobes.
                     */
                    Item {
                        x:
                            34
                            + Math.sin(
                                root.workspaceTrailPulse
                                * Math.PI * 2
                                * 0.67
                                + 2.2
                            ) * 3.0

                        y:
                            9
                            + Math.cos(
                                root.workspaceTrailPulse
                                * Math.PI * 2
                                * 0.79
                            ) * 1.8

                        width: 119
                        height: 61

                        Rectangle {
                            x: 3
                            y: 34
                            width: 109
                            height: 24
                            radius: 13

                            color:
                                root.cloudBaseColor

                            border.width: 1.2
                            border.color:
                                root.cloudOutlineColor
                        }

                        Rectangle {
                            x: 10
                            y: 24
                            width: 36
                            height: 34
                            radius: 18

                            color:
                                root.cloudBaseColor

                            border.width: 1.0
                            border.color:
                                root.cloudOutlineColor
                        }

                        Rectangle {
                            x: 31
                            y: 8
                            width: 50
                            height: 50
                            radius: 25

                            color:
                                root.cloudHighlightColor

                            border.width: 1.1
                            border.color:
                                root.cloudOutlineColor
                        }

                        Rectangle {
                            x: 68
                            y: 18
                            width: 39
                            height: 40
                            radius: 20

                            color:
                                root.cloudBaseColor

                            border.width: 1.0
                            border.color:
                                root.cloudOutlineColor
                        }

                        /*
                         * Small highlight cap to make the front lobe read as
                         * softly illuminated rather than a stack of circles.
                         */
                        Rectangle {
                            x: 45
                            y: 14
                            width: 27
                            height: 11
                            radius: 6

                            color:
                                root.cloudSparkColor

                            opacity: 0.48
                        }
                    }

                    /*
                     * Two tiny drifting wisps make the cloud bank feel like
                     * weather rather than a static icon.
                     */
                    Repeater {
                        model: 2

                        Rectangle {
                            required property int index

                            width:
                                15 + index * 6

                            height:
                                6 + index * 2

                            radius:
                                height / 2

                            x:
                                116
                                + index * 13
                                + Math.sin(
                                    root.workspaceTrailPulse
                                    * Math.PI * 2
                                    * (
                                        0.73
                                        + index * 0.21
                                    )
                                    + index
                                ) * 5

                            y:
                                27
                                + index * 17
                                + Math.cos(
                                    root.workspaceTrailPulse
                                    * Math.PI * 2
                                    * 0.58
                                    + index * 1.4
                                ) * 3

                            color:
                                root.cloudHighlightColor

                            opacity:
                                0.28
                                + index * 0.11
                        }
                    }

                    /*
                     * A subtle sparkle marks the cloud as the active landing
                     * atmosphere without reusing the normal accent everywhere.
                     */
                    Rectangle {
                        x:
                            134
                            + Math.sin(
                                root.workspaceTrailPulse
                                * Math.PI * 2
                                * 1.13
                            ) * 4

                        y:
                            9
                            + Math.cos(
                                root.workspaceTrailPulse
                                * Math.PI * 2
                                * 1.47
                            ) * 3

                        width:
                            4.5
                            + Math.max(
                                0,
                                Math.sin(
                                    root.workspaceTrailPulse
                                    * Math.PI * 2
                                    * 1.91
                                )
                              ) * 2.5

                        height: width
                        radius: width / 2

                        color:
                            root.cloudSparkColor

                        opacity: 0.84
                    }
                }

                /*
                 * --------------------------------------------------
                 * PIZZA DELIVERY — ALTERNATE MOVE ANIMATION
                 * --------------------------------------------------
                 *
                 * This keeps the last approved pizza interaction as an
                 * alternate presentation style. The underlying workspace
                 * migration remains exactly the same as Kite delivery.
                 */

                Item {
                    id: pizzaReceivingArm

                    visible:
                        root.activeDeliveryAnimation === "pizza"
                        && root.workspaceDragTarget > 0

                    width: 118
                    height: 42
                    z: 1

                    property real targetAngle:
                        root.workspaceDragTarget > 0
                        ? -Math.PI / 2
                          + ((root.workspaceDragTarget - 0.5)
                             * ((Math.PI * 2) / root.displayedWorkspaceCount))
                        : 0

                    x:
                        root.centerX
                        + Math.cos(targetAngle)
                          * (root.innerOuterRadius + 34)
                        - width / 2

                    y:
                        root.centerY
                        + Math.sin(targetAngle)
                          * (root.innerOuterRadius + 34)
                        - height / 2

                    rotation:
                        targetAngle * 180 / Math.PI + 180

                    opacity:
                        visible ? 1.0 : 0.0

                    scale:
                        visible ? 1.0 : 0.78

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutBack
                        }
                    }

                    Rectangle {
                        x: 18
                        anchors.verticalCenter: parent.verticalCenter
                        width: 78
                        height: 18
                        radius: 9
                        color: root.dropHighlightColor
                        border.width: 1
                        border.color: root.accentSecondaryColor
                    }

                    Rectangle {
                        x: 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 32
                        radius: 16
                        color: root.bubbleBackground
                        border.width: 2
                        border.color: root.accentSecondaryColor

                        Repeater {
                            model: 3

                            Rectangle {
                                required property int index
                                width: 14
                                height: 5
                                radius: 3
                                color: root.accentSecondaryColor
                                x: -3 + index * 3
                                y: 5 + index * 8
                                rotation: -18 + index * 18
                            }
                        }
                    }
                }

                /* Pizza rocket exhaust — the approved flame/smoke version. */
                Item {
                    id: pizzaDragTrail

                    width: 220
                    height: 92
                    z: 2

                    x: root.workspaceDragX - 174
                    y: root.workspaceDragY - 46

                    visible:
                        root.activeDeliveryAnimation === "pizza"
                        && root.workspaceDragActive
                        && root.workspaceGhostOpacity > 0.05

                    opacity:
                        visible
                        ? Math.min(
                            0.96,
                            0.58
                            + Math.min(root.workspaceDragSpeed, 14) / 35
                          )
                        : 0

                    transform: Rotation {
                        origin.x: 174
                        origin.y: 46
                        angle: root.workspaceTrailAngle
                    }

                    Repeater {
                        model: 5

                        Rectangle {
                            required property int index

                            property real phase:
                                (root.pizzaTrailPulse
                                 + index * 0.19) % 1

                            width:
                                15
                                + index * 5
                                + phase * 6

                            height: width
                            radius: width / 2

                            x:
                                16
                                + index * 24
                                - phase * 12

                            y:
                                46
                                - height / 2
                                + Math.sin(
                                    index * 1.7
                                    + root.pizzaTrailPulse * 5.5
                                  ) * 8

                            color:
                                index % 2 === 0
                                ? "#777986"
                                : "#555866"

                            opacity:
                                0.10
                                + (1 - phase) * 0.18

                            scale:
                                0.82 + phase * 0.42
                        }
                    }

                    Rectangle {
                        x: 82 - root.pizzaTrailPulse * 7
                        y: 37 - root.pizzaTrailPulse * 2
                        width: 74 + root.pizzaTrailPulse * 14
                        height: 18 + root.pizzaTrailPulse * 3
                        radius: height / 2
                        color: "#ff5b24"
                        opacity: 0.78
                    }

                    Rectangle {
                        x: 102 - root.pizzaTrailPulse * 5
                        y: 39
                        width: 55 + root.pizzaTrailPulse * 11
                        height: 14
                        radius: 7
                        color: "#ff9d2e"
                        opacity: 0.92
                    }

                    Rectangle {
                        x: 124 - root.pizzaTrailPulse * 3
                        y: 41
                        width: 34 + root.pizzaTrailPulse * 8
                        height: 10
                        radius: 5
                        color: "#ffd166"
                        opacity: 0.98
                    }

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index
                            width: 3 + (index % 2) * 2
                            height: width
                            radius: width / 2

                            x:
                                72
                                - index * 17
                                - root.pizzaTrailPulse * (8 + index * 2)

                            y:
                                46
                                + (index % 2 === 0 ? -1 : 1)
                                  * (10 + index * 4)
                                + Math.sin(
                                    root.pizzaTrailPulse * 6
                                    + index
                                  ) * 4

                            color:
                                index % 2 === 0
                                ? "#ffd166"
                                : "#ff7a24"

                            opacity:
                                0.35
                                + (1 - root.pizzaTrailPulse) * 0.55
                        }
                    }
                }

                Item {
                    id: pizzaWorkspaceGhost

                    width: 156
                    height: 136
                    z: 3

                    visible:
                        root.activeDeliveryAnimation === "pizza"

                    x: root.workspaceDragX - width / 2
                    y: root.workspaceDragY - height / 2
                    scale: root.workspaceGhostScale
                    opacity: root.workspaceGhostOpacity

                    rotation:
                        root.workspaceDragActive
                        ? root.workspaceDragTilt
                        : 0

                    Behavior on x {
                        enabled: root.workspaceDragAnimating
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on y {
                        enabled: root.workspaceDragAnimating
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 180 }
                    }

                    Behavior on rotation {
                        NumberAnimation {
                            duration: 135
                            easing.type: Easing.OutCubic
                        }
                    }

                    Canvas {
                        anchors.fill: parent

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()

                            const cx = width / 2
                            const tipY = height - 13
                            const crustY = 26
                            const half = 57

                            ctx.fillStyle = root.bubbleBackground
                            ctx.strokeStyle = root.accentSecondaryColor
                            ctx.lineWidth = 3
                            ctx.beginPath()
                            ctx.moveTo(cx, tipY)
                            ctx.lineTo(cx - half, crustY + 13)
                            ctx.quadraticCurveTo(
                                cx,
                                crustY - 9,
                                cx + half,
                                crustY + 13
                            )
                            ctx.closePath()
                            ctx.fill()
                            ctx.stroke()

                            ctx.strokeStyle = root.radialSunColor
                            ctx.lineWidth = 9
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(cx - half + 6, crustY + 10)
                            ctx.quadraticCurveTo(
                                cx,
                                crustY - 6,
                                cx + half - 6,
                                crustY + 10
                            )
                            ctx.stroke()
                        }
                    }

                    Repeater {
                        model: root.workspaceDragToppings.length

                        Item {
                            required property int index

                            property var topping:
                                root.workspaceDragToppings[index]

                            property var point:
                                root.pizzaToppingPoint(
                                    index,
                                    root.workspaceDragToppings.length
                                )

                            width:
                                topping && topping.overflow
                                ? 25
                                : 24

                            height: width

                            x:
                                pizzaWorkspaceGhost.width / 2
                                + point.x
                                - width / 2

                            y:
                                point.y - height / 2

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2

                                color:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? root.bubbleBackground
                                    : root.appVariantColor(
                                        parent.topping
                                        ? parent.topping.key
                                        : "app"
                                      )

                                border.width:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? 2.5
                                    : 2

                                border.color:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? root.accentColor
                                    : root.appVariantOutline(
                                        parent.topping
                                        ? parent.topping.key
                                        : "app"
                                      )
                            }

                            Image {
                                anchors.centerIn: parent
                                width: parent.width - 7
                                height: width

                                source:
                                    parent.topping
                                    && !parent.topping.overflow
                                    ? parent.topping.icon
                                    : ""

                                visible:
                                    parent.topping
                                    && !parent.topping.overflow
                                    && source.toString().length > 0

                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.centerIn: parent

                                visible:
                                    parent.topping
                                    && (
                                        parent.topping.overflow
                                        || !parent.topping.icon
                                    )

                                text:
                                    !parent.topping
                                    ? ""
                                    : (
                                        parent.topping.overflow
                                        ? "+" + parent.topping.count
                                        : parent.topping.initial
                                      )

                                color:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? root.foregroundColor
                                    : root.foregroundColor

                                font.pixelSize:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? 9
                                    : 12

                                font.bold: true
                            }
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 34
                        width: 30
                        height: 30
                        radius: 15
                        color: root.accentColor
                        border.width: 2
                        border.color: root.bubbleBackground

                        Text {
                            anchors.centerIn: parent
                            text: root.workspaceDragSource
                            color: theme.background
                            font.bold: true
                            font.pixelSize: 15
                        }
                    }
                }

                /*
                 * The lifted workspace kite. Its triangular canopy keeps
                 * the same visual language as the radial workspace sector.
                 */
                Item {
                    id: kiteWorkspaceGhost

                    width: 156
                    height: 342
                    z: 3

                    visible:
                        root.activeDeliveryAnimation === "kite"

                    /*
                     * Anchor the actual kite canopy around the pointer.
                     * The long height exists only to make room for the
                     * wagging string and the app badges below it.
                     */
                    x: root.workspaceDragX - 78
                    y: root.workspaceDragY - 68

                    scale: root.workspaceGhostScale
                    opacity: root.workspaceGhostOpacity

                    rotation:
                        root.workspaceDragActive
                        ? root.workspaceDragTilt
                        : 0

                    Behavior on x {
                        enabled: root.workspaceDragAnimating

                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on y {
                        enabled: root.workspaceDragAnimating

                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                        }
                    }

                    Behavior on rotation {
                        NumberAnimation {
                            duration: 135
                            easing.type: Easing.OutCubic
                        }
                    }

                    /*
                     * --------------------------------------------------
                     * KITE CANOPY
                     * --------------------------------------------------
                     *
                     * The triangular canopy deliberately echoes one radial
                     * workspace sector. No window badges live inside it now;
                     * they ride the string below.
                     */
                    Canvas {
                        id: kiteCanopy

                        width: parent.width
                        height: 136

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()

                            const cx = width / 2
                            const tipY = height - 13
                            const topY = 26
                            const half = 57

                            /*
                             * Four playful kite panels, all theme-derived.
                             * The geometry stays aligned with our radial
                             * triangular visual language.
                             */
                            const leftTopX = cx - half
                            const rightTopX = cx + half
                            const midY = 72

                            ctx.lineWidth = 0

                            ctx.fillStyle = root.kitePanelColorA
                            ctx.beginPath()
                            ctx.moveTo(cx, tipY)
                            ctx.lineTo(leftTopX, topY + 13)
                            ctx.lineTo(cx, topY + 1)
                            ctx.lineTo(cx, midY)
                            ctx.closePath()
                            ctx.fill()

                            ctx.fillStyle = root.kitePanelColorB
                            ctx.beginPath()
                            ctx.moveTo(cx, tipY)
                            ctx.lineTo(cx, midY)
                            ctx.lineTo(cx, topY + 1)
                            ctx.lineTo(rightTopX, topY + 13)
                            ctx.closePath()
                            ctx.fill()

                            ctx.fillStyle = root.kitePanelColorC
                            ctx.beginPath()
                            ctx.moveTo(cx, tipY)
                            ctx.lineTo(leftTopX, topY + 13)
                            ctx.lineTo(cx, midY)
                            ctx.closePath()
                            ctx.fill()

                            ctx.fillStyle = root.kitePanelColorD
                            ctx.beginPath()
                            ctx.moveTo(cx, tipY)
                            ctx.lineTo(cx, midY)
                            ctx.lineTo(rightTopX, topY + 13)
                            ctx.closePath()
                            ctx.fill()

                            /*
                             * Outer kite outline.
                             */
                            ctx.strokeStyle = root.accentSecondaryColor
                            ctx.lineWidth = 3
                            ctx.beginPath()
                            ctx.moveTo(cx, tipY)
                            ctx.lineTo(leftTopX, topY + 13)
                            ctx.quadraticCurveTo(
                                cx,
                                topY - 9,
                                rightTopX,
                                topY + 13
                            )
                            ctx.closePath()
                            ctx.stroke()

                            /*
                             * Reinforced top spar.
                             */
                            ctx.strokeStyle = root.radialBrightColor
                            ctx.lineWidth = 9
                            ctx.lineCap = "round"

                            ctx.beginPath()
                            ctx.moveTo(cx - half + 6, topY + 10)
                            ctx.quadraticCurveTo(
                                cx,
                                topY - 6,
                                cx + half - 6,
                                topY + 10
                            )
                            ctx.stroke()

                            /*
                             * Two subtle kite spars make the triangle read
                             * unmistakably as a kite rather than a kite.
                             */
                            ctx.strokeStyle = root.mutedColor
                            ctx.lineWidth = 1.4
                            ctx.globalAlpha = 0.72

                            ctx.beginPath()
                            ctx.moveTo(cx - half + 6, topY + 13)
                            ctx.lineTo(cx, tipY - 2)
                            ctx.moveTo(cx + half - 6, topY + 13)
                            ctx.lineTo(cx, tipY - 2)
                            ctx.stroke()

                            ctx.globalAlpha = 1
                        }
                    }

                    /*
                     * Workspace badge on the kite canopy.
                     */
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter

                        y: 34
                        width: 30
                        height: 30
                        radius: 15

                        color: root.accentColor

                        border.width: 2
                        border.color: root.bubbleBackground

                        Text {
                            anchors.centerIn: parent

                            text:
                                root.workspaceDragSource

                            color:
                                theme.background

                            font.bold: true
                            font.pixelSize: 15
                        }
                    }

                    /*
                     * --------------------------------------------------
                     * KITE FRILLS
                     * --------------------------------------------------
                     *
                     * Short tassels on both shoulders plus a small bow at the
                     * tip. They flutter more when the drag is moving quickly.
                     */
                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index

                            property bool leftSide:
                                index < 2

                            property int localIndex:
                                index % 2

                            width:
                                20
                                + localIndex * 4

                            height: 3
                            radius: 2

                            x:
                                leftSide
                                ? 15 - localIndex * 4
                                : 121 + localIndex * 4

                            y:
                                43 + localIndex * 13

                            color:
                                index === 0
                                ? root.radialSunColor
                                : (
                                    index === 1
                                    ? root.radialBerryColor
                                    : (
                                        index === 2
                                        ? root.radialMintColor
                                        : root.radialSkyColor
                                      )
                                  )

                            rotation:
                                (leftSide ? -1 : 1)
                                * (
                                    16
                                    + localIndex * 13
                                    + Math.sin(
                                        root.workspaceTrailPulse
                                        * Math.PI * 2
                                        * (
                                            0.71
                                            + index * 0.19
                                        )
                                        + index * 1.37
                                    )
                                    * (
                                        6
                                        + Math.min(
                                            root.workspaceDragSpeed,
                                            14
                                        ) * (
                                            0.28
                                            + index * 0.07
                                        )
                                    )
                                    + Math.max(
                                        0,
                                        Math.sin(
                                            root.workspaceTrailPulse
                                            * Math.PI * 2
                                            * 0.43
                                            + index * 0.91
                                        )
                                    ) * (
                                        index % 2 === 0
                                        ? 5
                                        : -3
                                    )
                                )

                            transformOrigin:
                                leftSide
                                ? Item.Right
                                : Item.Left
                        }
                    }

                    /*
                     * Little bow at the kite tip.
                     */
                    Item {
                        x: 64
                        y: 115
                        width: 28
                        height: 19

                        Rectangle {
                            width: 13
                            height: 7
                            radius: 4

                            x: 0
                            y: 4

                            color:
                                root.accentColor

                            rotation:
                                -22
                                - Math.sin(
                                    root.workspaceTrailPulse * Math.PI * 2
                                ) * 7
                        }

                        Rectangle {
                            width: 13
                            height: 7
                            radius: 4

                            x: 15
                            y: 4

                            color:
                                root.radialBerryColor

                            rotation:
                                22
                                + Math.sin(
                                    root.workspaceTrailPulse * Math.PI * 2
                                ) * 7
                        }

                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3

                            x: 11
                            y: 5

                            color:
                                root.foregroundColor
                        }
                    }

                    /*
                     * --------------------------------------------------
                     * WAGGING STRING
                     * --------------------------------------------------
                     *
                     * We build the string from short rounded segments instead
                     * of Canvas so every segment updates continuously with the
                     * animation pulse and pointer velocity.
                     */
                    Repeater {
                        model: 23

                        Rectangle {
                            required property int index

                            property var p1:
                                root.kiteStringPoint(
                                    index,
                                    24
                                )

                            property var p2:
                                root.kiteStringPoint(
                                    index + 1,
                                    24
                                )

                            property real dx:
                                p2.x - p1.x

                            property real dy:
                                p2.y - p1.y

                            property real segmentLength:
                                Math.sqrt(
                                    dx * dx
                                    + dy * dy
                                )

                            x: p1.x
                            y: p1.y

                            width:
                                segmentLength + 1

                            height: 2.2
                            radius: 1.1

                            color:
                                index % 5 === 0
                                ? root.radialSunColor
                                : (
                                    index % 3 === 0
                                    ? root.radialSkyColor
                                    : root.radialBrightColor
                                  )

                            opacity:
                                index % 4 === 0
                                ? 0.92
                                : 0.68

                            rotation:
                                Math.atan2(dy, dx)
                                * 180 / Math.PI

                            transformOrigin:
                                Item.Left
                        }
                    }

                    /*
                     * --------------------------------------------------
                     * APP BADGES RIDING THE STRING
                     * --------------------------------------------------
                     *
                     * Same application = same badge because the icon/name is
                     * resolved from the same application identity. Different
                     * applications remain visually distinct.
                     */
                    Repeater {
                        model:
                            root.workspaceDragToppings.length

                        Item {
                            required property int index

                            property var topping:
                                root.workspaceDragToppings[index]

                            property var point:
                                root.kiteBadgePoint(
                                    index,
                                    root.workspaceDragToppings.length
                                )

                            width:
                                topping
                                && topping.overflow
                                ? 29
                                : 30

                            height: width

                            x:
                                point.x
                                - width / 2
                                + Math.sin(
                                    root.workspaceTrailPulse * Math.PI * 2
                                    + index * 1.7
                                ) * (
                                    3
                                    + Math.min(
                                        root.workspaceDragSpeed,
                                        12
                                    ) * 0.18
                                )

                            y:
                                point.y
                                - height / 2
                                + Math.cos(
                                    root.workspaceTrailPulse * Math.PI * 2
                                    + index * 1.25
                                ) * 3.5

                            rotation:
                                (
                                    Math.sin(
                                        root.workspaceTrailPulse
                                        * Math.PI * 2
                                        * (
                                            0.77
                                            + index * 0.083
                                        )
                                        + index * 1.41
                                    )
                                    + 0.38
                                      * Math.sin(
                                          root.workspaceTrailPulse
                                          * Math.PI * 2
                                          * 1.63
                                          - index * 0.72
                                      )
                                )
                                * (
                                    6
                                    + Math.min(
                                        root.workspaceDragSpeed,
                                        14
                                    ) * 0.33
                                )

                            Rectangle {
                                anchors.fill: parent

                                radius:
                                    width / 2

                                color:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? root.bubbleBackground
                                    : root.appVariantColor(
                                        parent.topping
                                        ? parent.topping.key
                                        : "app"
                                      )

                                border.width:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? 2.5
                                    : 2

                                border.color:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? root.accentColor
                                    : root.appVariantOutline(
                                        parent.topping
                                        ? parent.topping.key
                                        : "app"
                                      )
                            }

                            Image {
                                anchors.centerIn:
                                    parent

                                width:
                                    parent.width - 8

                                height:
                                    width

                                source:
                                    parent.topping
                                    && !parent.topping.overflow
                                    ? parent.topping.icon
                                    : ""

                                visible:
                                    parent.topping
                                    && !parent.topping.overflow
                                    && source.toString().length > 0

                                fillMode:
                                    Image.PreserveAspectFit

                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.centerIn:
                                    parent

                                visible:
                                    parent.topping
                                    && (
                                        parent.topping.overflow
                                        || !parent.topping.icon
                                    )

                                text:
                                    !parent.topping
                                    ? ""
                                    : (
                                        parent.topping.overflow
                                        ? "+" + parent.topping.count
                                        : parent.topping.initial
                                    )

                                color:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? root.foregroundColor
                                    : root.accentSecondaryColor

                                font.pixelSize:
                                    parent.topping
                                    && parent.topping.overflow
                                    ? 9
                                    : 12

                                font.bold: true
                            }

                            /*
                             * Tiny knot holding each app badge to the string.
                             */
                            Rectangle {
                                anchors.horizontalCenter:
                                    parent.horizontalCenter

                                y: -5
                                width: 5
                                height: 5
                                radius: 3

                                color:
                                    parent.parent.topping
                                    && !parent.parent.topping.overflow
                                    ? root.appVariantColor(
                                        parent.parent.topping.key
                                      )
                                    : root.accentColor

                                border.width: 1
                                border.color:
                                    root.foregroundColor
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: workspaceMoveConfirmCard
                z: 970
                width: Math.min(390, root.width * 0.36)
                height: 164
                radius: 22
                x: root.centerX - width / 2
                y: root.centerY - height / 2
                visible: root.workspaceMoveConfirmActive
                opacity: visible ? 1.0 : 0.0
                scale: visible ? 1.0 : 0.94
                color: root.bubbleBackground
                border.width: 1
                border.color: root.accentSecondaryColor

                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale {
                    NumberAnimation { duration: 180; easing.type: Easing.OutBack }
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 17
                    spacing: 7

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text:
                            root.activeDeliveryAnimation === "pizza"
                            ? "Deliver the whole pizza? 🍕"
                            : "Ready to let the whole crew fly? 🪁"
                        color: root.foregroundColor
                        font.pixelSize: 16
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text:
                            root.activeDeliveryAnimation === "pizza"
                            ? (
                                root.workspaceDragWindowCount
                                + (
                                    root.workspaceDragWindowCount === 1
                                    ? " window"
                                    : " windows"
                                  )
                                + "  •  Workspace "
                                + root.workspaceDragSource
                                + " → "
                                + root.workspaceDragTarget
                              )
                            : (
                                root.workspaceDragWindowCount
                                + (
                                    root.workspaceDragWindowCount === 1
                                    ? " window"
                                    : " windows"
                                  )
                                + " ready for takeoff  •  Workspace "
                                + root.workspaceDragSource
                                + " → "
                                + root.workspaceDragTarget
                              )

                        color:
                            root.accentSecondaryColor

                        font.pixelSize: 12
                        font.bold: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text:
                            root.activeDeliveryAnimation === "pizza"
                            ? "Fresh delivery incoming. 🍕"
                            : "New workspace, new skies. ✨"

                        color:
                            root.mutedColor

                        font.pixelSize: 11
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 12

                        Rectangle {
                            width: 88; height: 34; radius: 17
                            color: cancelMoveMouse.containsMouse ? theme.surfaceHover : root.bubbleBackground
                            border.width: 1; border.color: root.mutedColor
                            Text { anchors.centerIn: parent; text: "Cancel"; color: root.foregroundColor; font.pixelSize: 12 }
                            MouseArea {
                                id: cancelMoveMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.returnWorkspaceMoveToSource()
                            }
                        }

                        Rectangle {
                            width: 88; height: 34; radius: 17
                            color: letItFlyMouse.containsMouse ? root.accentColor : root.dropHighlightColor
                            border.width: 1; border.color: root.accentColor
                            Text {
                                anchors.centerIn: parent
                                text:
                                    root.activeDeliveryAnimation === "pizza"
                                    ? "Deliver 🍕"
                                    : "Let it Fly! 🪁"
                                color: root.foregroundColor
                                font.pixelSize: 12
                                font.bold: true
                            }
                            MouseArea {
                                id: letItFlyMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.deliverWorkspaceMove()
                            }
                        }
                    }
                }
            }

            /*
             * --------------------------------------------------
             * WORKSPACE REDUCTION WARNING
             * --------------------------------------------------
             *
             * Non-modal on purpose: the user needs the Overview
             * immediately so they can move the blocking windows.
             */
            MouseArea {
                id: workspaceWarningDismissArea

                anchors.fill: parent
                z: 949
                enabled: root.workspaceWarningActive
                visible: enabled
                hoverEnabled: false

                onClicked: {
                    root.dismissWorkspaceWarning()
                }
            }

            Rectangle {
                id: workspaceWarningCard

                z: 950
                width: Math.min(410, root.width * 0.38)
                height: 112
                radius: 20

                x: root.centerX - width / 2
                y: root.centerY + root.hubRadius + 18

                color: root.bubbleBackground
                border.width: 1
                border.color: root.accentSecondaryColor

                opacity:
                    root.workspaceWarningActive
                    ? 1.0
                    : 0.0

                scale:
                    root.workspaceWarningActive
                    ? 1.0
                    : 0.94

                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation {
                        duration: 170
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 190
                        easing.type: Easing.OutBack
                    }
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 5

                    Text {
                        width: parent.width
                        text: "Whoa, not so fast! 😄"
                        color: root.foregroundColor
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        text: {
                            const ids = root.workspaceWarningIds
                            const names = root.formatWorkspaceList(ids)

                            if (ids.length === 1)
                                return "Workspace " + names + " still has company."

                            return "Workspaces " + names + " still have company."
                        }
                        color: root.accentSecondaryColor
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text:
                            "Move those windows to 1–"
                            + root.workspaceWarningRequestedCount
                            + " first."

                        color: root.mutedColor
                        font.pixelSize: 12
                    }
                }
            }

            /*
             * --------------------------------------------------
             * CENTER HUB
             * --------------------------------------------------
             */

            Item {
                id: centerHub

                anchors.centerIn: parent

                width:
                    Math.max(
                        220,
                        root.hubRadius * 1.9
                    )

                height: width
                z: 700

                /*
                 * Normal overview information. The settings button
                 * lives here rather than at a screen edge so the
                 * control remains part of the radial language.
                 */
                Column {
                    id: normalHubContent

                    anchors.centerIn: parent
                    spacing: 6

                    visible: !root.settingsOpen
                    opacity: visible ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation { duration: 100 }
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text:
                            root.workspaceDragActive
                            ? (
                                root.activeDeliveryAnimation === "pizza"
                                ? "Pizza Delivery 🍕"
                                : "Kite Delivery 🪁"
                              )
                            : (root.dragActive ? "Move Window" : "Overview")

                        color:
                            root.foregroundColor

                        font.pixelSize: 30
                        font.bold: true
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text:
                            root.workspaceDragActive
                            ? (
                                root.activeDeliveryAnimation === "pizza"
                                ? (
                                    root.workspaceDragTarget > 0
                                    ? "Workspace " + root.workspaceDragTarget + " is hungry"
                                    : "Taking the whole pizza…"
                                  )
                                : (
                                    root.workspaceDragTarget > 0
                                    ? "Workspace " + root.workspaceDragTarget + " is ready"
                                    : "Take the whole crew…"
                                  )
                              )
                            : (root.dragActive
                            ? (
                                root.dragTargetWorkspace > 0
                                ? "Workspace "
                                  + root.dragTargetWorkspace
                                : "Drag onto a workspace"
                            )
                            : (
                                Hyprland.focusedWorkspace
                                !== null
                                ? "Workspace "
                                  + Hyprland.focusedWorkspace.id
                                : "No active workspace"
                            ))

                        color:
                            root.accentColor

                        font.pixelSize: 16
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text:
                            root.dragActive
                            ? "Release to move"
                            : (
                                root.clients.length
                                + (
                                    root.clients.length
                                    === 1
                                    ? " active window"
                                    : " active windows"
                                )
                            )

                        color:
                            root.mutedColor

                        font.pixelSize: 13
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text:
                            root.dragActive
                            ? "Esc cancels drag"
                            : "Esc to close"

                        color:
                            root.mutedColor

                        font.pixelSize: 13
                    }

                    Rectangle {
                        id: settingsButton

                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        visible: !root.dragActive

                        width: 34
                        height: 34
                        radius: width / 2

                        color:
                            settingsButtonMouse.containsMouse
                            ? theme.surfaceHover
                            : root.bubbleBackground

                        border.width: 1
                        border.color:
                            settingsButtonMouse.containsMouse
                            ? root.accentColor
                            : root.mutedColor

                        scale:
                            settingsButtonMouse.containsMouse
                            ? 1.08
                            : 1.0

                        Behavior on scale {
                            NumberAnimation { duration: 90 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "⚙"
                            color: root.foregroundColor
                            font.pixelSize: 17
                        }

                        MouseArea {
                            id: settingsButtonMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                root.openSettings()
                            }
                        }
                    }
                }

                /*
                 * Circular workspace-count selector. Eight is the
                 * center/default detent and points straight up.
                 *
                 * Click any number, or drag anywhere on the clock
                 * face, to move the single hand to the nearest
                 * detent. The main radial previews the sector count
                 * immediately.
                 */
                Item {
                    id: workspaceSettingsDial

                    anchors.centerIn: parent

                    width:
                        Math.min(
                            centerHub.width,
                            root.hubRadius * 1.82
                        )

                    height: width

                    visible: root.settingsOpen
                    opacity: visible ? 1.0 : 0.0
                    scale: visible ? 1.0 : 0.94

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutBack
                        }
                    }

                    property real dialRadius: width / 2
                    property real tickRadius: dialRadius * 0.76
                    property real handLength: dialRadius * 0.54

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2

                        color: root.bubbleBackground

                        border.width: 2
                        border.color: root.accentColor

                        opacity: 0.97
                    }

                    Rectangle {
                        anchors.centerIn: parent

                        width: parent.width - 16
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: root.mutedColor
                        opacity: 0.35
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 16

                        text: "WORKSPACES"
                        color: root.mutedColor
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.3
                    }

                    /* Clock ticks + directly clickable numbers. */
                    Repeater {
                        model: 5

                        Item {
                            id: workspaceChoice

                            required property int index
                            z: 6

                            property int choice: index + 6
                            property real choiceAngle:
                                root.settingsAngleForCount(choice)

                            width: 38
                            height: 38

                            x:
                                workspaceSettingsDial.width / 2
                                + Math.cos(choiceAngle)
                                * workspaceSettingsDial.tickRadius
                                - width / 2

                            y:
                                workspaceSettingsDial.height / 2
                                + Math.sin(choiceAngle)
                                * workspaceSettingsDial.tickRadius
                                - height / 2

                            Rectangle {
                                anchors.centerIn: parent

                                width:
                                    workspaceChoice.choice
                                    === root.settingsPreviewCount
                                    ? 34
                                    : 28

                                height: width
                                radius: width / 2

                                color:
                                    workspaceChoice.choice
                                    === root.settingsPreviewCount
                                    ? root.accentColor
                                    : (
                                        choiceMouse.containsMouse
                                        ? theme.surfaceHover
                                        : "transparent"
                                    )

                                border.width:
                                    workspaceChoice.choice
                                    === root.settingsPreviewCount
                                    ? 0
                                    : 1

                                border.color: root.mutedColor

                                Behavior on width {
                                    NumberAnimation { duration: 100 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: workspaceChoice.choice

                                    color:
                                        workspaceChoice.choice
                                        === root.settingsPreviewCount
                                        ? theme.background
                                        : root.foregroundColor

                                    font.pixelSize:
                                        workspaceChoice.choice
                                        === root.settingsPreviewCount
                                        ? 14
                                        : 12

                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: choiceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    if (root.settingsRejecting)
                                        return

                                    root.previewWorkspaceCount(
                                        workspaceChoice.choice
                                    )
                                }
                            }
                        }
                    }

                    /* Single clock hand. */
                    Rectangle {
                        id: workspaceHand

                        z: 3

                        x: workspaceSettingsDial.width / 2
                        y: workspaceSettingsDial.height / 2 - height / 2

                        width: workspaceSettingsDial.handLength
                        height: 3
                        radius: height / 2

                        color: root.accentSecondaryColor

                        transformOrigin: Item.Left
                        rotation:
                            -150
                            + ((root.settingsPreviewCount - 6) * 30)

                        Behavior on rotation {
                            NumberAnimation {
                                duration:
                                    root.settingsRejecting
                                    ? 360
                                    : 130

                                easing.type: Easing.OutCubic
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: width / 2
                            color: root.accentSecondaryColor
                        }
                    }

                    /* Lower 180° — workspace-move animation selector. */
                    Repeater {
                        model: root.workspaceAnimationChoices.length

                        Item {
                            id: animationChoice

                            required property int index
                            z: 7

                            property var choice:
                                root.workspaceAnimationChoices[index]

                            property real choiceAngle:
                                root.settingsAngleForAnimationIndex(index)

                            width: 46
                            height: 46

                            x:
                                workspaceSettingsDial.width / 2
                                + Math.cos(choiceAngle)
                                  * workspaceSettingsDial.tickRadius
                                - width / 2

                            y:
                                workspaceSettingsDial.height / 2
                                + Math.sin(choiceAngle)
                                  * workspaceSettingsDial.tickRadius
                                - height / 2

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top

                                width:
                                    parent.choice.key
                                    === root.settingsPreviewAnimation
                                    ? 34
                                    : 29

                                height: width
                                radius: width / 2

                                color:
                                    parent.choice.key
                                    === root.settingsPreviewAnimation
                                    ? root.radialSunColor
                                    : (
                                        animationChoiceMouse.containsMouse
                                        ? theme.surfaceHover
                                        : root.bubbleBackground
                                      )

                                border.width: 1
                                border.color:
                                    parent.choice.key
                                    === root.settingsPreviewAnimation
                                    ? root.radialBrightColor
                                    : root.mutedColor

                                Behavior on width {
                                    NumberAnimation { duration: 110 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: animationChoice.choice.icon
                                    font.pixelSize:
                                        animationChoice.choice.key
                                        === root.settingsPreviewAnimation
                                        ? 17
                                        : 14
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom

                                text: animationChoice.choice.label
                                color:
                                    animationChoice.choice.key
                                    === root.settingsPreviewAnimation
                                    ? root.foregroundColor
                                    : root.mutedColor
                                font.pixelSize: 7
                                font.bold: true
                                font.letterSpacing: 0.7
                            }

                            MouseArea {
                                id: animationChoiceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    if (!root.settingsRejecting) {
                                        root.previewWorkspaceAnimation(
                                            animationChoice.choice.key
                                        )
                                    }
                                }
                            }
                        }
                    }

                    /* Second, shorter hand for the lower animation arc. */
                    Rectangle {
                        id: animationHand

                        z: 3

                        x: workspaceSettingsDial.width / 2
                        y: workspaceSettingsDial.height / 2 - height / 2

                        width: workspaceSettingsDial.handLength * 0.83
                        height: 3
                        radius: height / 2

                        color: root.radialSunColor

                        transformOrigin: Item.Left
                        rotation:
                            root.settingsAngleForAnimation(
                                root.settingsPreviewAnimation
                            ) * 180 / Math.PI

                        Behavior on rotation {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: width / 2
                            color: root.radialSunColor
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 17
                        height: 17
                        radius: width / 2
                        color: root.accentColor
                        border.width: 3
                        border.color: root.bubbleBackground
                        z: 5
                    }

                    /*
                     * A generous pointer surface makes the hand easy
                     * to use without requiring pixel-perfect dragging.
                     */
                    MouseArea {
                        id: dialDragArea

                        anchors.fill: parent
                        z: 2

                        acceptedButtons: Qt.LeftButton
                        cursorShape:
                            pressed
                            ? Qt.ClosedHandCursor
                            : Qt.OpenHandCursor

                        function updateSelection(mouse) {
                            if (mouse.y < height / 2) {
                                const count =
                                    root.nearestWorkspaceCountForPoint(
                                        mouse.x,
                                        mouse.y,
                                        width / 2,
                                        height / 2
                                    )

                                root.previewWorkspaceCount(count)
                            } else {
                                const animation =
                                    root.nearestWorkspaceAnimationForPoint(
                                        mouse.x,
                                        mouse.y,
                                        width / 2,
                                        height / 2
                                    )

                                root.previewWorkspaceAnimation(animation)
                            }
                        }

                        onPressed: function(mouse) {
                            if (!root.settingsRejecting)
                                updateSelection(mouse)
                        }

                        onPositionChanged: function(mouse) {
                            if (pressed && !root.settingsRejecting)
                                updateSelection(mouse)
                        }
                    }

                    /* Selected value / confirmation. */
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -25

                        text: root.settingsPreviewCount
                        color: root.foregroundColor
                        font.pixelSize: 25
                        font.bold: true
                        z: 6
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -7

                        text:
                            root.settingsPreviewCount < root.workspaceCount
                            ? "validate on ✓"
                            : "workspace preview"
                        color: root.mutedColor
                        font.pixelSize: 9
                        z: 6
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 12

                        text:
                            root.settingsPreviewAnimation === "pizza"
                            ? "🍕  PIZZA"
                            : "🪁  KITE"

                        color: root.radialSunColor
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.6
                        z: 7
                    }

                    Rectangle {
                        id: settingsDoneButton

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 11

                        width: 30
                        height: 30
                        radius: width / 2

                        z: 8

                        color:
                            settingsDoneMouse.containsMouse
                            ? root.accentColor
                            : root.bubbleBackground

                        border.width: 1
                        border.color: root.accentColor

                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color:
                                settingsDoneMouse.containsMouse
                                ? theme.background
                                : root.foregroundColor
                            font.pixelSize: 15
                            font.bold: true
                        }

                        MouseArea {
                            id: settingsDoneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                root.applyWorkspaceSetting()
                            }
                        }
                    }
                }
            }
        }
    }
}
