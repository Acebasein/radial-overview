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
            readonly property int minimumWorkspaceCount: 6
            readonly property int maximumWorkspaceCount: 10

            /*
             * Preference is stored outside the Git checkout under
             * $XDG_STATE_HOME/radial-overview/settings.json (or the
             * conventional ~/.local/state fallback).
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

            function persistWorkspaceCount() {
                const payload = JSON.stringify({
                    workspaceCount: workspaceCount
                })

                Quickshell.execDetached([
                    "bash",
                    "-lc",
                    'dir="${XDG_STATE_HOME:-$HOME/.local/state}/radial-overview"; mkdir -p "$dir"; printf "%s\n" "$1" > "$dir/settings.json"',
                    "--",
                    payload
                ])
            }

            function commitWorkspaceCount(count) {
                const clamped = Math.max(
                    minimumWorkspaceCount,
                    Math.min(maximumWorkspaceCount, count)
                )

                workspaceCount = clamped
                settingsPreviewCount = clamped
                persistWorkspaceCount()
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
                radialCanvas.requestPaint()
                settingsRejectTimer.restart()
            }

            function applyWorkspaceSetting() {
                if (settingsRejecting)
                    return

                const requested = settingsPreviewCount

                if (requested === workspaceCount) {
                    closeSettings()
                    return
                }

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

                commitWorkspaceCount(requested)
                closeSettings()
            }

            function openSettings() {
                if (dragActive)
                    cancelPointerInteraction()

                workspaceWarningActive = false
                workspaceWarningTimer.stop()
                settingsRejecting = false
                settingsPreviewCount = workspaceCount
                settingsOpen = true
            }

            function closeSettings() {
                if (settingsRejecting)
                    return

                settingsPreviewCount = workspaceCount
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

                            root.workspaceCount = clamped
                            root.settingsPreviewCount = clamped
                            radialCanvas.requestPaint()

                            console.log(
                                "Radial Overview: workspace count loaded:",
                                clamped
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
                if (root.settingsOpen) {
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
                    if (root.settingsOpen) {
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

                    if ((root.dragActive || root.dropFeedbackActive)
                            && root.dragTargetWorkspace > 0) {

                        const targetIndex =
                            root.dragTargetWorkspace - 1

                        const startAngle =
                            -Math.PI / 2
                            + targetIndex
                            * step

                        const endAngle =
                            startAngle
                            + step

                        ctx.fillStyle =
                            root.dropHighlightColor

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

                        Text {
                            anchors.horizontalCenter:
                                parent.horizontalCenter

                            text:
                                workspaceDelegate.workspaceId

                            color:
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

                            font.pixelSize:
                                workspaceDelegate.warningTarget
                                ? 32
                                : (
                                    workspaceDelegate.dropTarget
                                    ? 32
                                    : 28
                                )

                            font.bold: true
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
                                root.accentColor

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
                            root.dragActive
                            ? "Move Window"
                            : "Overview"

                        color:
                            root.foregroundColor

                        font.pixelSize: 30
                        font.bold: true
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text:
                            root.dragActive
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
                            )

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
                            const count =
                                root.nearestWorkspaceCountForPoint(
                                    mouse.x,
                                    mouse.y,
                                    width / 2,
                                    height / 2
                                )

                            root.previewWorkspaceCount(count)
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
                        anchors.verticalCenterOffset: 31

                        text: root.settingsPreviewCount
                        color: root.foregroundColor
                        font.pixelSize: 25
                        font.bold: true
                        z: 6
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 53

                        text:
                            root.settingsPreviewCount < root.workspaceCount
                            ? "validate on ✓"
                            : "workspace preview"
                        color: root.mutedColor
                        font.pixelSize: 9
                        z: 6
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
