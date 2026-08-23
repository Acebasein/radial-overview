# Radial Overview

A fast, radial workspace and window overview for Hyprland, built with Quickshell.

Radial Overview presents configured workspaces in an inner ring and the active
windows belonging to each workspace in an adaptive outer ring.

It is designed to provide a fast visual overview of the desktop while keeping
window navigation and workspace management simple.

## Demo

See Radial Overview in action — workspace navigation, window focus,
drag-and-drop, window-title tooltips, multi-monitor awareness, and live
Omarchy theme integration.

https://github.com/user-attachments/assets/5b701a39-057f-44fc-a34b-90fad811e74c

## Features

- Radial workspace overview
- Always-visible workspace destinations, including empty workspaces
- Adaptive window bubble sizing
- Native application icons using Quickshell DesktopEntries
- Application-name fallback when an icon cannot be resolved
- Focused-window highlighting
- Click a window to focus it
- Drag and drop windows between workspaces
- Smooth drag release transition
- Inner and outer workspace sectors act as drop targets
- Compatible with Hyprland scrolling layouts
- Multi-monitor workspace indicators
- Topology-aware multi-monitor hot corners
- Live semantic theme loading
- Automatic Omarchy theme integration
- Desktop/rice-independent theme contract
- IPC open, close, and toggle controls
- Subtle overview transitions
- Escape key closes the overview
- Optional systemd user-service integration

## Requirements

Radial Overview currently requires:

- Hyprland
- Quickshell
- `hyprctl`

For automatic startup and process supervision:

- systemd user services

The core window-management implementation is currently Hyprland-specific.

## Repository Structure

```text
radial-overview/
├── adapters/
├── integrations/
│   ├── hotcorner/
│   │   └── shell.qml
│   └── systemd/
│       ├── radial-overview.service
│       └── radial-hotcorner.service
├── themes/
│   └── default.json
├── Theme.qml
├── shell.qml
├── README.md
└── LICENSE
```

## Quick Start

Clone the repository into the Quickshell configuration directory:

```bash
mkdir -p ~/.config/quickshell
cd ~/.config/quickshell

git clone https://github.com/Acebasein/radial-overview.git
```

Start Radial Overview manually:

```bash
qs -n -d -c radial-overview
```

From another terminal, open it:

```bash
qs -c radial-overview ipc call radialOverview open
```

If the overview appears correctly, continue with the deployment instructions
below.

---

# Deployment and Configuration

## 1. Validate Radial Overview Manually

Before configuring automatic startup, verify that the core overview works:

```bash
qs -n -d -c radial-overview
```

Open the overview from another terminal:

```bash
qs -c radial-overview ipc call radialOverview open
```

Available IPC commands are:

```bash
qs -c radial-overview ipc call radialOverview open
qs -c radial-overview ipc call radialOverview close
qs -c radial-overview ipc call radialOverview toggle
```

Manual validation ensures that Quickshell and Hyprland integration are working
before systemd or hot-corner integration is introduced.

## 2. Hot-Corner Integration

Radial Overview includes an optional topology-aware hot-corner implementation.

Create the Quickshell hot-corner configuration directory:

```bash
mkdir -p ~/.config/quickshell/hotcorner
```

Symlink the repository implementation:

```bash
ln -sf \
  ~/.config/quickshell/radial-overview/integrations/hotcorner/shell.qml \
  ~/.config/quickshell/hotcorner/shell.qml
```

This keeps the repository version as the single source of truth.

### Single Monitor

On a single-monitor system, the hot corner is:

```text
Top-right
```

### Multiple Monitors

For multiple horizontally arranged monitors, Radial Overview detects the
logical monitor topology and uses the exposed outer corners.

For example:

```text
★ Laptop display                 External display ★
┌──────────────────┐           ┌──────────────────┐
│                  │           │                  │
│                  │           │                  │
└──────────────────┘           └──────────────────┘
```

The behavior becomes:

```text
Leftmost monitor  → Top-left
Rightmost monitor → Top-right
```

Interior edges are deliberately not treated as hot corners because the pointer
can cross directly into the neighboring display.

The implementation uses Hyprland monitor geometry and accounts for monitor
scaling rather than hard-coding monitor names such as `eDP-1` or `HDMI-A-1`.

## 3. Install the systemd User Services

Radial Overview includes systemd user-service definitions for automatic
startup and process supervision.

Create the user-service directory:

```bash
mkdir -p ~/.config/systemd/user
```

Symlink the service definitions:

```bash
ln -sf \
  ~/.config/quickshell/radial-overview/integrations/systemd/radial-overview.service \
  ~/.config/systemd/user/radial-overview.service

ln -sf \
  ~/.config/quickshell/radial-overview/integrations/systemd/radial-hotcorner.service \
  ~/.config/systemd/user/radial-hotcorner.service
```

Reload the user systemd configuration:

```bash
systemctl --user daemon-reload
```

## 4. Service Architecture

`radial-overview.service` is the primary service.

It starts the Radial Overview and requests the hot-corner service:

```text
radial-overview.service
        │
        ├── Radial Overview
        │
        └── Wants
              │
              ▼
        radial-hotcorner.service
```

Users therefore manage Radial Overview through **one primary service**.

The hot-corner service does not need to be enabled independently.

If `radial-hotcorner.service` was previously enabled manually, disable its
independent autostart:

```bash
systemctl --user disable radial-hotcorner.service
```

## 5. Enable Radial Overview

Enable and start the primary service:

```bash
systemctl --user enable --now radial-overview.service
```

Verify both components:

```bash
systemctl --user is-active radial-overview.service
systemctl --user is-active radial-hotcorner.service
```

Expected output:

```text
active
active
```

## 6. Service Management

Restart Radial Overview:

```bash
systemctl --user restart radial-overview.service
```

Start it:

```bash
systemctl --user start radial-overview.service
```

Stop it:

```bash
systemctl --user stop radial-overview.service
```

Check service status:

```bash
systemctl --user status radial-overview.service
systemctl --user status radial-hotcorner.service
```

View Radial Overview logs:

```bash
journalctl --user -u radial-overview.service -f
```

View hot-corner logs:

```bash
journalctl --user -u radial-hotcorner.service -f
```

For normal operation, users should manage `radial-overview.service` rather
than manually starting Quickshell processes.

---

# Multi-Monitor Support

Radial Overview reads Hyprland's workspace and monitor topology.

When more than one monitor is connected, workspace sectors display the
Hyprland monitor name associated with that workspace.

For example:

```text
       1
    2 windows
     ▣ eDP-1
```

and:

```text
       5
     1 window
   ▣ HDMI-A-1
```

The focused monitor receives a subtle visual distinction.

Radial Overview does not attempt to override Hyprland's workspace-to-monitor
model.

A Hyprland workspace belongs to one monitor at a time. Moving a workspace or
its windows between displays therefore follows normal Hyprland behavior.

The overview itself opens on the display from which it is invoked.

---

# Theme System

Radial Overview uses a small semantic theme contract rather than depending on
the color format of a particular desktop environment or rice.

The default theme is stored in:

```text
themes/default.json
```

The semantic contract includes:

```json
{
  "background": "#111018",
  "surface": "#1a1822",
  "surfaceHover": "#24202f",
  "foreground": "#ffffff",
  "muted": "#8f8a9d",
  "accent": "#8b5cf6",
  "accentSecondary": "#c084fc",
  "border": "#6d5a8f",
  "dropHighlight": "#362454"
}
```

The UI consumes these semantic properties rather than environment-specific
theme values.

This allows adapters for different environments to map their native palette
into the Radial Overview theme contract.

## Omarchy Adapter

When running under Omarchy, Radial Overview can automatically read the active
Omarchy palette from:

```text
~/.local/state/omarchy/current/theme/colors.toml
```

The Omarchy adapter maps those colors into the Radial Overview semantic theme.

If an Omarchy theme is changed while Radial Overview is running, the adapter
detects the change and updates the active palette.

If the Omarchy theme is unavailable, Radial Overview automatically falls back
to:

```text
themes/default.json
```

The adapter architecture is intended to allow additional integrations in the
future without coupling the core UI to a specific desktop environment.

---

# Optional Hyprland Keybind

Radial Overview can also be invoked from a Hyprland keybind.

The command is:

```bash
qs -c radial-overview ipc call radialOverview toggle
```

For users who prefer deterministic opening rather than toggle behavior:

```bash
qs -c radial-overview ipc call radialOverview open
```

The exact Hyprland configuration file used for the keybind depends on the
user's Hyprland setup.

---

# Updating

If the repository was cloned into:

```text
~/.config/quickshell/radial-overview
```

update it with:

```bash
cd ~/.config/quickshell/radial-overview
git pull --ff-only
```

Because the hot-corner and systemd unit files are symlinked to the repository,
updates to those files are automatically reflected in their installed
locations.

If systemd service definitions changed during an update, run:

```bash
systemctl --user daemon-reload
systemctl --user restart radial-overview.service
```

---

# Troubleshooting

## Overview Does Not Start

Check:

```bash
systemctl --user status radial-overview.service
```

Then inspect the log:

```bash
journalctl --user -u radial-overview.service -n 100
```

The overview can also be started directly for debugging:

```bash
qs -n -d -c radial-overview
```

## Hot Corner Does Not Work

Check:

```bash
systemctl --user status radial-hotcorner.service
```

View its log:

```bash
journalctl --user -u radial-hotcorner.service -n 100
```

On multi-monitor systems, remember that only exposed desktop corners are used.

For two side-by-side displays this normally means:

```text
Left display  → Top-left
Right display → Top-right
```

## Theme Falls Back to Default

Run Radial Overview in debug mode:

```bash
qs -n -d -c radial-overview
```

Theme diagnostics will indicate whether an environment adapter was loaded or
whether the default theme was selected.

---

# Development Status

Radial Overview currently includes:

- Functional radial workspace navigation
- Adaptive window bubbles
- Native application icons
- Focused-window indication
- Drag-and-drop workspace movement
- Drag-release visual smoothing
- Multi-monitor workspace awareness
- Topology-aware hot corners
- Live Omarchy theme integration
- Portable semantic theme architecture
- systemd user-service integration

The project is currently undergoing production validation before its next
release.

## Planned

- Window-title tooltips
- Additional theme adapters
- Broader environment testing
- Packaging and installation improvements

---

# License

MIT
