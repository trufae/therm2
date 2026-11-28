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

Therm2 pins SwiftTerm upstream `main` at `a480ce66166c9d23798580c1d4d845434b97d24a`.
`make`, `make debug`, and `make test` apply the dependency patches after resolution.
`make prepare` applies them without building. Preparation accepts a clean checkout or
one with earlier patches applied, and stops if the SwiftTerm revision or patch state is
unexpected. A direct `swift build` requires a prepared checkout.

- Horizontal scrolling shares the report budget between both axes of a diagonal gesture.
  [Feature patch](../patches/swiftterm-horizontal-scroll.patch), [review fixes](../patches/swiftterm-horizontal-scroll-review.patch)
- Foreground brightness preserves the handling of explicit underline colors on bold text.
  [Patch](../patches/swiftterm-foreground-brightness.patch)
- Truecolor output reclaims unused styles when the attribute table fills and keeps renderer
  attribute caches bounded. [Patch](../patches/swiftterm-style-arena-reclamation.patch)
- OSC 22 lets terminal programs choose a pointer shape or hide the native pointer over
  terminal text. The selected shape takes precedence over the link hover cursor.
  [OSC 22 patch](../patches/swiftterm-mouse-pointer-shapes.patch), [link cursor patch](../patches/swiftterm-link-cursor.patch)
- The local-link resolver uses the pane’s PTY directory when opening a link. Command-hover
  shows the original target, and deferred `openDefault()` calls use the directory at the
  time they run. The cursor caches the opening verdict while hovering. Numeric URLs
  such as `tel:5551234` and `vscode:123` keep their usual policy.
  [Resolver patch](../patches/swiftterm-local-links.patch), [link policy patch](../patches/swiftterm-local-link-policy.patch)

Unlimited scrollback grows the history buffer on demand instead of preallocating
a large fixed limit. Limited mode keeps 0–1,000,000 lines above the visible screen;
the default is 1,000. Changes apply to existing panes, and reducing the limit
discards the oldest excess lines. Clearing unlimited history releases the discarded rows and their storage.
[Patch](../patches/swiftterm-unlimited-scrollback.patch)

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
