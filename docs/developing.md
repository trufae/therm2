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

The pinned SwiftTerm release ignores horizontal wheel deltas and lacks foreground-only
dimming and unlimited history. `make`, `make debug`, and `make test` automatically apply the patches for
[horizontal scrolling](../patches/swiftterm-horizontal-scroll.patch),
[foreground brightness](../patches/swiftterm-foreground-brightness.patch), and
[unlimited scrollback](../patches/swiftterm-unlimited-scrollback.patch) after
resolution. The preparation is idempotent and fails on an unexpected upstream revision
or conflicting edits. Use these targets; a raw `swift build` after a fresh checkout does
not apply the patches. `make prepare` applies them without building the app.

Unlimited scrollback grows the history buffer on demand instead of preallocating
a large fixed limit. Limited mode keeps 0–1,000,000 lines above the visible screen;
the default is 1,000. Changes apply to existing panes, and reducing the limit
discards the oldest excess lines. Unlimited history stays in memory for the session.

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

## Tests

`make test` checks nested split insertion/collapse, view release, focus cycling, minimum
sizes, divider limits, title sanitation, and local directory handling. It also feeds real
AppKit wheel events through SwiftTerm and checks horizontal/vertical mouse reports,
cursor-key fallback, fractional travel, gesture boundaries, modifiers, and scrollback.
Mouse focus, text-field focus preservation, and accumulated pinch zoom are covered too.
Renderer checks cover foreground-only dimming, unchanged ANSI backgrounds and selection
highlights, and restoring colors when focus changes. Preferences persistence and bundled
font registration are covered. A real PTY test checks directory inheritance without
OSC 7, matching kernel window size, and SIGWINCH delivery when a pane is split.
Rendering throughput and resident memory still need profiling on representative
workloads and displays.
