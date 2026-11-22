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
- **Snowball Mode** — roll snowballs and build snowmen (Escape to leave)
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

## Accessibility

- **Reduce Motion** (System Settings → Accessibility → Display) halves the flakes, calms
  the wind and lowers the frame rate. It still snows; it stops being constant movement.
- The settings window is entirely keyboard-operable, with focus rings, live values and
  each control tied to the sentence that explains it. It follows increased contrast and
  reduced transparency too.
- The ❄ in the menu bar announces itself to VoiceOver, and the menu reads as three
  groups rather than a dozen flat items.
- Snowball Mode says on screen what it is and carries a **Leave** button, because a mode
  that swallows clicks should never be hard to get out of. Escape and a double click
  work as well.
- Rolling a snowball is the same gesture with a mouse, a trackpad or a finger.

## How it works

| File | What it does |
| --- | --- |
| `index.html` | The whole snow engine: a canvas, flakes with depth, sway and wandering wind. Transparent when loaded with `?overlay=1`. |
| `Snow.swift` | One borderless `NSWindow` per screen at screen-saver level, `ignoresMouseEvents`, joining all Spaces, hosting the page in a transparent `WKWebView`. |
| `snow.sh` | `start` builds when the source has changed, then runs; `stop` ends it. |
| `settings.html` | The settings window: depth, auto-plough, speed, size, direction, buttons. |
| `Saver.swift` | `Snowfall.saver`: the same snow as a `ScreenSaverView`, drawn natively with Core Graphics, for the idle and lock screen. |
| `install-saver.sh` | Builds the saver bundle and installs it to `~/Library/Screen Savers`. |
| `ci/check.sh` | Pre-push check: builds both, parses the engine, verifies the page hooks, loads the saver and asserts it draws. |

Flakes fall under gravity against air resistance — `v' = g − (g/terminal²)·v²` — so they
accelerate out of the sky and level off at a terminal velocity that depends on their size,
and the wind is a force they lag behind rather than a number added to their position.

Lying snow is drawn as grains, not as a flat colour: a speckle tile repeated over every
surface, a body that cools toward blue with depth, a lit crest where it meets the air,
and the odd facet catching the light. The nearest flakes are drawn as six-armed crystals
turning as they fall, while the distant ones stay dots.

Each flake gets a random *depth*. Near flakes are bigger, brighter and faster; far ones
are small and faint, which is what makes the fall read as three-dimensional rather than
as dots sliding down a pane of glass. A wind value wanders every few seconds so no two
minutes of snow look alike. Flake count scales with screen area, so a 6K display gets a
real storm instead of a sprinkle.

## Snow that piles up, and a plough

Flakes land on the ground rather than at the bottom edge, and what lands stays: a height
map across the screen that builds into a drift over your Dock, over the top edge of every
window, and over your desktop widgets. Lying snow creeps toward
its neighbours and anything steeper than a 20° face slumps, so the surface reads as long
shallow curves rather than spikes.

**How fast it builds is how hard it is snowing** — Light, Medium or Blizzard in the ❄
menu. A blizzard buries the screen in a couple of hours; Light takes all night.

Everything else is in the ❄ menu → **Snow Settings…**, measured against your screen
rather than in pixels:

| Setting | What it does |
| --- | --- |
| **Snow lies on the ground** | Whether it piles up at all |
| **Deepest it gets** | 5% to 100% of the screen — at 100% the snow may cover everything |
| **Plough by itself** | Sends the truck out at a depth you pick, or only when you ask |
| **Plough speed** | How many seconds it takes to cross the screen |
| **Truck size** | 3% to 15% of screen height |
| **Comes from** | Alternating sides, always the left, or always the right |

The plough scrapes to bare screen — no crust left behind — and **carries what it takes**:
the snow rolls along in front of the blade as a long low bank, capped at about blade
height, and whatever will not fit is thrown off the blade in lumps that arc away under
gravity. When the truck leaves the edge it takes the bank with it, and the snow starts
over on a clean screen. Send it from the ❄ menu (**Send the Plough**), from the settings
window, or press **P** on the web demo.

The drift is written to disk every minute and restored per screen when the app starts, so
an evening of snow survives a quit or a reboot.

## Snow on your windows

Snow does not only land on the desktop: the top edge of every window and every desktop
widget is a ledge it can lie on, so a Safari window picks up a white line along its title bar that thickens as the
night goes on. The height map is keyed to the window, not to a position, so the snow
**rides along when you drag the window**, and an edge covered by a window in front of it
collects nothing.

Full-screen windows are left alone: they have no visible top edge, so snow lying on one
would be snow lying on nothing.

Window geometry comes from `CGWindowList`, which needs no permission — only window
*titles* are privileged, and Snowfall never asks for them. The list is refreshed twice a
second.

## Snowballs and snowmen

❄ menu → **Snowball Mode**. Click any snow and drag sideways — the drift along the bottom,
or the snow lying on a window or a widget. The ball picks up the depth it sweeps, growing
by the area it takes and leaving a clean track behind it, and it stays on the surface it
started from. Let one go over a window ledge deep enough to hold it and it rests there. Let go and it
rests where it lands — or on top of the ball below it. Stack two and the top one gets coal
eyes, a carrot and a smile, and the one underneath gets buttons. Grab a ball again to pick
it up and move it.

The overlay has to stop being click-through to hear a mouse at all, so while this mode is
on it swallows every click on your desktop. **Escape** leaves it, as does the menu item.

Balls obey the same gravity as the flakes: they fall when you let go rather than appear
on the ground, and nothing stays in the air — plough the ground out from under a snowman,
or pick up the ball it was standing on, and what was on top comes down.

A snowman moves as one piece: take hold of any part of it and the whole stack comes with
you. Let it go from high enough and it lands harder than packed snow can survive, and
bursts back into a mound on the ground.

The plough takes any snowman standing in its way.

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
