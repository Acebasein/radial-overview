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
            /*
             * --------------------------------------------------
             * CLIENT DATA
             * --------------------------------------------------
             */

            property var clients: []
            property int clientRevision: 0

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
                    / workspaceCount

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
                        moveClientToWorkspace(
                            client,
                            target
                        )
                    }
                } else {
                    focusClient(client)
                }

                draggedClient = null
                dragActive = false
                dragTargetWorkspace = 0

                radialCanvas.requestPaint()
            }

            function cancelPointerInteraction() {
                draggedClient = null
                dragActive = false
                dragTargetWorkspace = 0

                radialCanvas.requestPaint()
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
                    / workspaceCount

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
                    / workspaceCount

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
             * KEYBOARD
             * --------------------------------------------------
             */

            Keys.onEscapePressed: {
                if (root.dragActive) {
                    root.cancelPointerInteraction()
                } else {
                    root.requestClose()
                }
            }

            Shortcut {
                sequence: "Esc"
                context: Qt.WindowShortcut

                onActivated: {
                    if (root.dragActive) {
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
                        root.workspaceCount

                    const step =
                        (Math.PI * 2)
                        / count

                    /*
                     * Highlight the ENTIRE destination wedge,
                     * including both inner and outer rings.
                     */

                    if (root.dragActive
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
                    root.workspaceCount

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
                        root.dragActive
                        && root.dragTargetWorkspace
                        === workspaceId

                    property real step:
                        (Math.PI * 2)
                        / root.workspaceCount

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

                    width: 110
                    height: 72

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
                                workspaceDelegate.dropTarget
                                ? root.foregroundColor
                                : (
                                    workspaceDelegate.active
                                    ? root.accentColor
                                    : root.foregroundColor
                                )

                            font.pixelSize:
                                workspaceDelegate.dropTarget
                                ? 32
                                : 28

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
                                workspaceDelegate.dropTarget
                                ? root.accentColor
                                : (
                                    workspaceDelegate.active
                                    ? root.accentColor
                                    : root.mutedColor
                                )

                            font.pixelSize: 12
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
                    root.workspaceCount

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
                                    root.dragActive
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

                                    onPressed:
                                        function(mouse) {
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
                    root.dragActive
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

                opacity: 0.92

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
             * CENTER HUB
             * --------------------------------------------------
             */

            Column {
                anchors.centerIn:
                    parent

                spacing: 6

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
            }
        }
    }
}