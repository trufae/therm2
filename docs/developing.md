# Developing Therm2

Requires macOS 13 or newer and Swift 6.2 or newer (Xcode 26+).

```sh
make          # optimized, ad-hoc signed build/Therm2.app
make run
make test
make dmg      # universal release app + DMG and SHA-256 checksum in build/
make install  # Copy Therm2.app into /Applications
```

Use `make debug` for a debug app bundle, then attach Xcode or LLDB to the running app.
The first build downloads dependencies; `Package.resolved` pins the resolution.
Distribution builds need your own Developer ID signature and notarization.

## Dependency patches

The pinned SwiftTerm 1.99.3 release ignores horizontal wheel deltas and lacks foreground-only
dimming and unlimited history. Its cursor-color delegate signature also prevents
OSC 12 updates from reaching the view. `make`, `make debug`, and `make test` automatically apply the patches for
[horizontal scrolling](../patches/swiftterm-horizontal-scroll.patch),
[foreground brightness](../patches/swiftterm-foreground-brightness.patch),
[unlimited scrollback](../patches/swiftterm-unlimited-scrollback.patch),
[cursor colors](../patches/swiftterm-cursor-color.patch),
[local link resolution](../patches/swiftterm-local-links.patch), and
[link hover cursors](../patches/swiftterm-link-cursor.patch) after
resolution. The preparation is idempotent and fails on an unexpected upstream revision
or conflicting edits. Use these targets; a raw `swift build` after a fresh checkout does
not apply the patches. `make prepare` applies them without building the app.

All six patches were reviewed against 1.99.3; none is fully covered upstream.
Horizontal scrolling, unlimited scrollback, cursor colors, and link hover cursors
apply unchanged. The brightness patch preserves upstream's correction that explicit
underline colors do not become bright when text is bold. The local-link patch now
runs in `checkLink`, so the new `TerminalLinkRequest` delegate receives the original
target and deferred `openDefault()` calls use the current pane directory. SwiftTerm's
path classification distinguishes `source.swift:12` from numeric URLs such as `tel:5551234`.
Upstream's OSC 7 resolution does not replace Therm2's actual PTY directory lookup,
leading-slash fallback, or resolution of relative OSC 8 targets.

Unlimited scrollback grows the history buffer on demand instead of preallocating
a large fixed limit. Limited mode keeps 0–1,000,000 lines above the visible screen;
the default is 1,000. Changes apply to existing panes, and reducing the limit
discards the oldest excess lines. Unlimited history stays in memory for the session.

Local links, including OSC 8 targets, resolve against the pane's current shell directory,
independently of the new-session directory preference. Existing absolute paths take
precedence; a missing `/patches/example.patch` also tries `patches/example.patch` under
that directory. Tilde paths and line/column suffixes are supported. Resolved files still
pass through SwiftTerm's checks before opening; URLs with schemes keep their usual behavior.
Activatable links show a pointing hand; modifier-gated links use it while Command is held.

## Metal renderer

Core Graphics is the default renderer to avoid a GPU surface and glyph atlas per pane.
To try SwiftTerm's Metal renderer, launch with `THERM2_METAL=1`:

```sh
THERM2_METAL=1 build/Therm2.app/Contents/MacOS/Therm2
```

Metal falls back to Core Graphics if initialization fails.

## Microphone

Programs running in Therm2 can request microphone access. Allow Therm2 when macOS
prompts. You can change this in System Settings → Privacy & Security → Microphone.
After installing a build with microphone support, quit and reopen Therm2 before
retrying. If a previous denial prevents a new prompt, run:

```sh
tccutil reset Microphone com.pancake.therm2
```

## Releases

```sh
./version.sh         # print the app version from Resources/Info.plist
./version.sh 0.2.0   # set X.Y.Z and increment CFBundleVersion
make dmg             # build/Therm2-0.2.0-universal.dmg and .dmg.sha256
```

Setting the current version again leaves the build number unchanged. Commit the
version change, then push a matching numeric tag (for example, `0.2.0`) to publish a
versioned GitHub Release. Release tags must start with a digit and match
`./version.sh` exactly, without a `v` prefix. CI rejects mismatched release tags.
Every branch push, pull request, and manual CI run tests the app and runs `make dmg`,
keeping the DMG and checksum as Actions artifacts for 30 days. Successful `main`
builds update the continuous prerelease. Publishing uses the built-in `GITHUB_TOKEN`.

## Icon artwork

The vector source is [`Resources/AppIcon.icon/Assets/prompt.svg`](../Resources/AppIcon.icon/Assets/prompt.svg).
The Icon Composer document's `icon.json` supplies the background and styling.

```sh
make icons
# Or use another SVG and output directory:
./scripts/generate-icons.sh path/to/prompt.svg build/custom-icons
```

The script creates the Icon Composer document, a full-size `AppIcon.icns`,
`Assets.car`, an `.iconset`, and all ten macOS PNG entries (16–1024 pixels, including
Retina sizes) in `Assets.xcassets/AppIcon.appiconset`. Output defaults to `build/icons`.
`make` and `make run` reuse these exports until an SVG or styling edit; each build
replaces only the app bundle so macOS notices the new icon. `make clean` is not needed.

## Drag and drop

File drops insert shell-quoted paths with a trailing space and honor bracketed paste.
Screenshot thumbnails and other promised files, as well as raw bitmap images, are
saved in private `Therm2-Drop-*` directories under the macOS temporary directory.
These files remain available after the pane closes, until macOS cleans temporary files.

## Tests

`make test` checks nested split insertion/collapse, view release, focus cycling, minimum
sizes, divider limits, title sanitation, and local directory handling. It also feeds real
AppKit wheel events through SwiftTerm and checks horizontal/vertical mouse reports,
cursor-key fallback, fractional travel, gesture boundaries, modifiers, and scrollback.
Mouse focus, text-field focus preservation, and accumulated pinch zoom are covered too.
Renderer checks cover text dimming and optional default background dimming at half its
strength, unchanged black and explicit ANSI backgrounds and selection highlights, and
restoring colors when focus changes. Cursor-color checks feed OSC 12 and OSC 112
through the parser and verify rendered colors and restoration without real-time animation.
Preferences persistence and bundled font registration are covered. A real PTY test checks directory inheritance without
OSC 7, matching kernel window size, and SIGWINCH delivery when a pane is split.
Link tests cover relative and leading-slash paths, absolute-path precedence, pane-local
resolution, shell directory changes, deferred link requests, source-location suffixes,
and preservation of file and URL validation. Rendering checks also exercise bold white
and explicit underline colors with dimming in both shaped and plain text paths.
Rendering throughput and resident memory still need profiling on representative
workloads and displays.
