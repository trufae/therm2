# Therm2

<img src="docs/AppIcon.png" width="128" alt="Therm2 app icon">

A small, native macOS terminal. No web view, no telemetry, no clutter.

**[Download the latest release →](https://github.com/trufae/therm2/releases)** — DMGs for Intel and Apple Silicon, macOS 13+. The [continuous prerelease](https://github.com/trufae/therm2/releases/tag/continuous) tracks `main`. Ad-hoc signed, not notarized.

Therm2 checks for a different GitHub release version at startup and offers to open the
releases page. Disable “Check for updates on startup” in Preferences to turn this off.

## Features

- Tabs, nested splits, instant fullscreen
- Maximize a pane without killing its session
- Dark background with optional glassy window: real Liquid Glass behind the text on macOS 26 and later
- Steady cursor, focus follows the mouse, inactive panes dim
- Find, copy/paste, ⌘+/⌘− to zoom
- Drop files, folders, screenshots, or images to insert shell-quoted paths
- Pinch to resize the font right in the terminal
- Native preferences: colors, font, border margin, glassy window, dimming, start directory
- Bundled retro fonts, registered for this app only
- New tabs and splits inherit the active shell's directory
- Run a command with `Therm2 -e command [args...]`

## Run a command

Launch the app's executable with `-e`, like `xterm -e`:

```sh
/Applications/Therm2.app/Contents/MacOS/Therm2 -e top
build/Therm2.app/Contents/MacOS/Therm2 -e ssh user@host
```

The command runs in the caller's working directory, using its `PATH`. Everything
after `-e` is passed directly to the command. For pipes, redirections, or other
shell syntax, explicitly run a shell:

```sh
/Applications/Therm2.app/Contents/MacOS/Therm2 -e /bin/sh -c 'ls -la | less'
```

The pane closes when the command exits. An instance launched with `-e` quits when
its last window closes. Additional tabs, splits, and windows start your normal
login shell. Launching without `-e` keeps the usual behavior.

You can also use `open -na Therm2 --args -e top` to launch a separate instance;
invoke the executable directly when the caller's directory and environment matter.

## Design

- One SwiftTerm view and PTY per pane; the `NSSplitView` tree *is* the layout
- Inactive tabs detach from the window but keep running, rendering suspended
- Core Graphics by default, Metal opt-in
- SwiftTerm is the only dependency
- No telemetry, update checks, session restore, profiles, or background services
- Configurable scrollback: a line limit (1,000 by default) or unlimited history

## Docs

- [Keybindings](docs/keybindings.md)
- [Building and developing](docs/developing.md)

## Credits

- **pancake** — author of Therm2
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by **Miguel de Icaza** — terminal engine
- Original [Therm](https://github.com/trufae/Therm) — icon and inspiration

## License

MIT; see [COPYING](COPYING).
