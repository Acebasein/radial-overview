import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root

    /*
     * --------------------------------------------------
     * RADIAL OVERVIEW — TOPOLOGY-AWARE HOT CORNERS
     * --------------------------------------------------
     *
     * Rules:
     *
     * Single monitor:
     *   → top-right
     *
     * Multiple horizontal monitors:
     *   → leftmost exposed display gets top-left
     *   → rightmost exposed display gets top-right
     *   → displays between them get no hot corner
     *
     * Monitor ownership is derived from Hyprland's actual
     * logical geometry:
     *
     *     logicalWidth  = width  / scale
     *     logicalHeight = height / scale
     *
     * This avoids hard-coding names such as eDP-1 or HDMI-A-1.
     */

    property var monitors: []
    property int topologyRevision: 0

    /*
     * A small tolerance is useful because monitor coordinates
     * are logical values and may occasionally involve rounding.
     */
    property real edgeTolerance: 2.0


    /*
     * --------------------------------------------------
     * MONITOR TOPOLOGY
     * --------------------------------------------------
     */

    function refreshTopology() {
        if (!monitorProcess.running)
            monitorProcess.running = true
    }

    function logicalWidth(monitor) {
        if (!monitor)
            return 0

        const scale =
            monitor.scale && monitor.scale > 0
            ? monitor.scale
            : 1

        return monitor.width / scale
    }

    function logicalHeight(monitor) {
        if (!monitor)
            return 0

        const scale =
            monitor.scale && monitor.scale > 0
            ? monitor.scale
            : 1

        return monitor.height / scale
    }

    function monitorByName(name) {
        const revision = topologyRevision

        for (let i = 0; i < monitors.length; ++i) {
            if (monitors[i].name === name)
                return monitors[i]
        }

        return null
    }

    function verticalRangesOverlap(a, b) {
        const aTop =
            a.y

        const aBottom =
            a.y + logicalHeight(a)

        const bTop =
            b.y

        const bBottom =
            b.y + logicalHeight(b)

        return (
            aTop < bBottom - edgeTolerance
            && bTop < aBottom - edgeTolerance
        )
    }

    /*
     * Is this monitor's LEFT edge touching another monitor?
     */

    function hasLeftNeighbor(monitor) {
        if (!monitor)
            return false

        const leftEdge =
            monitor.x

        for (let i = 0; i < monitors.length; ++i) {
            const other =
                monitors[i]

            if (other.name === monitor.name)
                continue

            const otherRight =
                other.x
                + logicalWidth(other)

            if (
                Math.abs(otherRight - leftEdge)
                <= edgeTolerance
                && verticalRangesOverlap(
                    monitor,
                    other
                )
            ) {
                return true
            }
        }

        return false
    }

    /*
     * Is this monitor's RIGHT edge touching another monitor?
     */

    function hasRightNeighbor(monitor) {
        if (!monitor)
            return false

        const rightEdge =
            monitor.x
            + logicalWidth(monitor)

        for (let i = 0; i < monitors.length; ++i) {
            const other =
                monitors[i]

            if (other.name === monitor.name)
                continue

            if (
                Math.abs(other.x - rightEdge)
                <= edgeTolerance
                && verticalRangesOverlap(
                    monitor,
                    other
                )
            ) {
                return true
            }
        }

        return false
    }


    /*
     * --------------------------------------------------
     * HOT-CORNER DECISION
     * --------------------------------------------------
     *
     * Return:
     *
     *   "left"
     *   "right"
     *   ""
     */

    function cornerForScreen(screenName) {
        const revision = topologyRevision

        const monitor =
            monitorByName(screenName)

        if (!monitor)
            return ""

        /*
         * Traditional single-monitor behavior.
         */
        if (monitors.length <= 1)
            return "right"

        const leftExposed =
            !hasLeftNeighbor(monitor)

        const rightExposed =
            !hasRightNeighbor(monitor)

        /*
         * Normal leftmost monitor.
         */
        if (
            leftExposed
            && !rightExposed
        ) {
            return "left"
        }

        /*
         * Normal rightmost monitor.
         */
        if (
            rightExposed
            && !leftExposed
        ) {
            return "right"
        }

        /*
         * Isolated monitor or monitor separated by gaps.
         *
         * Preserve conventional top-right behavior.
         */
        if (
            leftExposed
            && rightExposed
        ) {
            return "right"
        }

        /*
         * Interior monitor.
         *
         * Both horizontal edges lead into neighboring displays,
         * therefore neither top corner is reliably reachable.
         */
        return ""
    }


    /*
     * --------------------------------------------------
     * OPEN RADIAL OVERVIEW
     * --------------------------------------------------
     */

    function openOverview() {
        Quickshell.execDetached([
            "qs",
            "-c",
            "radial-overview",
            "ipc",
            "call",
            "radialOverview",
            "open"
        ])
    }


    /*
     * --------------------------------------------------
     * HYPRLAND MONITOR DATA
     * --------------------------------------------------
     */

    property Process monitorProcess: Process {
        id: monitorProcess

        running: false

        command: [
            "hyprctl",
            "monitors",
            "-j"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed =
                        JSON.parse(
                            this.text
                        )

                    root.monitors =
                        parsed

                    root.topologyRevision++

                    console.log(
                        "Radial Overview hotcorner:",
                        parsed.length,
                        "monitors detected"
                    )

                    for (
                        let i = 0;
                        i < parsed.length;
                        ++i
                    ) {
                        const monitor =
                            parsed[i]

                        console.log(
                            "Hotcorner:",
                            monitor.name,
                            "→",
                            root.cornerForScreen(
                                monitor.name
                            )
                        )
                    }

                } catch (error) {
                    console.log(
                        "Radial Overview hotcorner:",
                        "failed to parse monitor topology:",
                        error
                    )

                    root.monitors = []
                    root.topologyRevision++
                }
            }
        }
    }


    /*
     * Refresh periodically so monitor hotplug, disconnect,
     * scale changes, and rearrangement are picked up without
     * restarting the hot-corner configuration.
     *
     * This is intentionally low-frequency.
     */

    property Timer topologyTimer: Timer {
        interval: 3000
        repeat: true
        running: true

        onTriggered: {
            root.refreshTopology()
        }
    }


    Component.onCompleted: {
        root.refreshTopology()
    }


    /*
     * --------------------------------------------------
     * ONE OPTIONAL HOT CORNER PER SCREEN
     * --------------------------------------------------
     */

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: cornerWindow

            required property var modelData

            screen:
                modelData

            property string corner:
                root.cornerForScreen(
                    modelData.name
                )

            visible:
                corner !== ""

            anchors {
                top: true

                left:
                    cornerWindow.corner
                    === "left"

                right:
                    cornerWindow.corner
                    === "right"
            }

            /*
             * Small enough to stay invisible, but large enough
             * to hit reliably at the physical desktop boundary.
             */
            implicitWidth: 8
            implicitHeight: 8

            color: "transparent"

            MouseArea {
                anchors.fill:
                    parent

                hoverEnabled: true

                onEntered: {
                    root.openOverview()
                }
            }
        }
    }
}
