# Snowfall ❄

Falling snow for your macOS desktop. A transparent, click-through overlay on every
display — the flakes drift down over your windows and the menu bar, and the mouse
goes straight through them.

It's one HTML canvas under the hood, so the same file also runs as a plain web page.

## Let it snow

```bash
git clone https://github.com/tejuaee/snowfall.git
cd snowfall
./snow.sh
```

That builds a tiny Swift app (no Xcode project, no dependencies) and starts the snow.
A ❄ appears in the menu bar:

- **Stop / Start Snow**
- **Light · Medium · Blizzard** — how hard it comes down
- **Quit Snowfall**

Needs macOS with the Xcode command line tools (`xcode-select --install`). The app runs
as a menu bar accessory: no Dock icon, and it never takes focus from what you're doing.

## Just the web page

Open `index.html` in a browser for a standalone night-sky version, and press
**1 / 2 / 3** to change the intensity. Hosted on GitHub Pages it works as a live demo.

## How it works

| File | What it does |
| --- | --- |
| `index.html` | The whole snow engine: a canvas, flakes with depth, sway and wandering wind. Transparent when loaded with `?overlay=1`. |
| `Snow.swift` | One borderless `NSWindow` per screen at screen-saver level, `ignoresMouseEvents`, joining all Spaces, hosting the page in a transparent `WKWebView`. |
| `snow.sh` | Builds when the source has changed, then runs. |

Each flake gets a random *depth*. Near flakes are bigger, brighter and faster; far ones
are small and faint, which is what makes the fall read as three-dimensional rather than
as dots sliding down a pane of glass. A wind value wanders every few seconds so no two
minutes of snow look alike. Flake count scales with screen area, so a 6K display gets a
real storm instead of a sprinkle.

## Notes

- Snow is drawn above normal windows. A full-screen app on its own Space stays clear.
- Screens being plugged in, unplugged or resized rebuilds the overlays automatically.

## License

MIT
