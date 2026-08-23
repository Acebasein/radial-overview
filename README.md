# Radial Overview

A fast, radial workspace and window overview for Hyprland built with Quickshell.

Radial Overview presents all configured workspaces in an inner ring and the
active windows belonging to each workspace in an adaptive outer ring.

## Features

- Radial workspace overview
- Always-visible workspace destinations, including empty workspaces
- Adaptive window bubble sizing
- Click a window to focus it
- Drag and drop windows between workspaces
- Inner and outer workspace sectors act as drop targets
- Compatible with Hyprland scrolling layouts
- Live semantic theme loading
- Desktop/rice-independent theme contract
- IPC open, close, and toggle controls
- Escape key closes the overview

## Requirements

- Hyprland
- Quickshell
- `hyprctl`

## Theme format

Themes use a small semantic JSON contract:

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

The theme system is intentionally independent of any specific shell or rice.
Adapters for environments such as Omarchy, Noctalia, DMS, Stylix, Matugen,
and custom dotfiles can map their palettes into this contract.

Run

Start Radial Overview:

qs -n -d -c radial-overview

Open it:

qs -c radial-overview ipc call radialOverview open

Toggle it:

qs -c radial-overview ipc call radialOverview toggle
Status

v1.0.0 establishes the functional core and portable theme architecture.

Future work includes application icons, automatic theme adapters, animations,
visual refinement, and packaging.

License

MIT
