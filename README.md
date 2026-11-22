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
- **Send the Plough** · **Clear the Snow** · **Snow Settings…**
- **Ease Off on Battery** — on by default, see below
- **Quit Snowfall**

Stop it again any time with `./snow.sh stop`. Your intensity choice is remembered.

Needs macOS with the Xcode command line tools (`xcode-select --install`). The app runs
as a menu bar accessory: no Dock icon, and it never takes focus from what you're doing.

## Just the web page

Open `index.html` in a browser for a standalone night-sky version, and press
**1 / 2 / 3** to change the intensity. Hosted on GitHub Pages it works as a live demo.

## Snow on the lock screen

```bash
./install-saver.sh
```

Then **System Settings → Screen Saver → Other → Snowfall**, and under **Lock Screen**
set *Start Screen Saver when inactive*. The snow now comes down whenever the Mac is
idle or locked.

Worth being straight about why it is a screen saver and not just the overlay: the lock
screen is drawn by `loginwindow` in its own session, above every window a normal
application is allowed to create. Nothing a user app does will paint over it. What macOS
*does* run on an idle or locked Mac is the selected screen saver, so `Snowfall.saver` is
a second, native implementation of the same engine for exactly that surface.

Two consequences:

- The password prompt itself — after you press a key and the saver exits — shows your
  wallpaper, not snow. That one is not reachable.
- The saver is unsigned, so macOS may want you to allow it the first time.

## How it works

| File | What it does |
| --- | --- |
| `index.html` | The whole snow engine: a canvas, flakes with depth, sway and wandering wind. Transparent when loaded with `?overlay=1`. |
| `Snow.swift` | One borderless `NSWindow` per screen at screen-saver level, `ignoresMouseEvents`, joining all Spaces, hosting the page in a transparent `WKWebView`. |
| `snow.sh` | `start` builds when the source has changed, then runs; `stop` ends it. |
| `settings.html` | The settings window: drift time, plough speed, size, direction, and the buttons. |
| `Saver.swift` | `Snowfall.saver`: the same snow as a `ScreenSaverView`, drawn natively with Core Graphics, for the idle and lock screen. |
| `install-saver.sh` | Builds the saver bundle and installs it to `~/Library/Screen Savers`. |
| `ci/check.sh` | Pre-push check: builds both, parses the engine, verifies the page hooks, loads the saver and asserts it draws. |

Flakes fall under gravity against air resistance — `v' = g − (g/terminal²)·v²` — so they
accelerate out of the sky and level off at a terminal velocity that depends on their size,
and the wind is a force they lag behind rather than a number added to their position.

Each flake gets a random *depth*. Near flakes are bigger, brighter and faster; far ones
are small and faint, which is what makes the fall read as three-dimensional rather than
as dots sliding down a pane of glass. A wind value wanders every few seconds so no two
minutes of snow look alike. Flake count scales with screen area, so a 6K display gets a
real storm instead of a sprinkle.

## Snow that piles up, and a plough

Flakes land on the ground rather than at the bottom of the screen, and what lands stays:
a height map across the screen that builds into a drift along the bottom edge, over your
Dock. It holds a 38° face — snow's actual angle of repose — and anything steeper slumps
onto its neighbour.

How long a full drift takes is yours to choose, from the ❄ menu → **Snow Settings…**:

| Setting | What it does |
| --- | --- |
| **Snow settles** | Never, or a full drift in 5 minutes, 15 minutes, an hour, 4 hours, 12 hours |
| **Plough by itself** | Sends the truck out once the drift reaches a depth you pick |
| **Plough speed** | 80–600 px/s |
| **Truck size** | 0.6× to 2× |
| **Comes from** | Alternating sides, always the left, or always the right |

"A full drift" is the bottom quarter of the screen. Rather than a fixed depth per flake —
which would mean something different on every screen and at every intensity — the engine
counts how many flakes actually land per second and solves for what each one is worth, so
the time you pick is the time it takes.

The plough scrapes the drift down to a thin crust and **carries what it takes**: the snow
rides in front of the blade as a bank that grows across the screen, slumping as it goes,
and leaves with the truck. Send it from the ❄ menu (**Send the Plough**), from the
settings window, or press **P** on the web demo.

The drift is written to disk every minute and restored per screen when the app starts, so
an evening of snow survives a quit or a reboot.

## Battery

Decorative snow has no business draining a laptop, so the overlay gives up work
wherever the work cannot be seen:

- **30 fps, not 120.** The loop is timer-driven, so the process wakes about thirty
  times a second instead of once per display refresh only to discard most frames.
- **A few draw calls per frame.** Flakes are grouped into five fixed opacities and each
  group is one path and one fill, rather than three canvas state changes per flake.
- **Fewer pixels.** The canvas is capped at 1.5x, not full Retina scale — invisible on
  dots two pixels wide, and well under half the backing store on a 5K display.
- **Nothing at all when hidden.** Window occlusion, display sleep and screen lock stop
  the loop dead. Snow behind a full-screen app costs nothing.
- **Easing off on battery.** Unplugged or in Low Power Mode it drops to 20 fps, 1x
  pixels and 55% of the flakes. It is still snowing; it just stops costing much.
- **No disk.** WebKit runs with a non-persistent data store, so the overlay never
  writes a cache or a cookie.

Measured on an Apple silicon MacBook, one display, Medium, on battery — CPU time of the
app plus its WebKit process sampled over 30 seconds:

| | CPU |
| --- | --- |
| before these changes | 10.1% |
| now | 6.0% |

That is one sample on one machine, not a benchmark suite: expect the shape of the
result (roughly a 40% cut, and zero while hidden) rather than the exact figure.
Reproduce it with `measure.sh`-style sampling of `ps -o cputime`.

## Notes

- Snow is drawn above normal windows. A full-screen app on its own Space stays clear —
  and the snow for that screen pauses while you are over there.
- Screens being plugged in, unplugged or resized rebuilds the overlays automatically.
- Occlusion is a noisy signal — switching window, app or Space reports the overlay
  covered for a moment — so the overlay waits two seconds and re-checks before pausing,
  and resumes immediately. Frames are driven by a timer with a watchdog, because
  `requestAnimationFrame` does not fire while WebKit considers the page hidden.

## License

MIT
