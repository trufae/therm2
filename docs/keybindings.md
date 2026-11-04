# Keybindings

| Shortcut | Action |
| --- | --- |
| ⌘N / ⌘T | New window / tab |
| ⌘, | Preferences |
| ⌘D / ⇧⌘D | Split left–right / top–bottom |
| ⌘W / ⇧⌘W / ⌥⌘W | Close pane / tab / window |
| ⌘1…9 | Select tab |
| ⇧⌘[ / ⇧⌘] | Previous / next tab |
| ⌘J / ⌘K | Previous / next pane within the current tab |
| ⇧⌘H / J / K / L | Move nearest divider left / up / down / right |
| ⌘Enter | Instant fullscreen |
| ⇧⌘Enter | Maximize current pane / restore splits |
| ⇧⌘G | Toggle Ignore Notch in Fullscreen |
| ⇧⌘F | Toggle Always on Top |
| ⌘+ / ⌘− / ⌘0 | Increase / decrease / reset active pane's font |
| ⌘F | Find in active terminal |
| ⌘C / ⌘V | Copy selection / paste |

## Mouse and modifiers

Focus follows the mouse between panes in the active window. Drag the thin dividers to resize.

Option uses the native keyboard layout, including Spanish ⌥º for `\`, ⌥3 for `#`, and
dead-key accents. It is not mapped to Meta; use Escape followed by a key for terminal
Meta combinations.

Pinch over a pane to change its font size. Pinch and ⌘+/⌘− share the same 4–1024 point
range; ⌘0 restores the default size from Preferences (initially 13 points), and ⌘= also
increases the size. Pinch travel accumulates smoothly, with glyph caches rebuilt only
when the size crosses a whole-point step.

Holding a key repeats it using the system repeat rate and delay; the app disables the
macOS press-and-hold accent picker, while dead-key composition remains available.

## Titles

Tabs divide the full width equally, without scrolling. Labels start empty and combine
all nonempty terminal titles in their tab, separated by ` · `. Programs and shells can
set these titles with OSC 0 or OSC 2; the window title follows the focused terminal.

```sh
printf '\033]2;build\007'  # set this terminal's title
printf '\033]2;\007'       # clear it
```
