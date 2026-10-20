# Clock — a system-time plugin for Tern

A live system clock in Tern's tab bar. 12-hour or 24-hour, optional seconds,
in one of four positions, chosen from a picker and remembered for good.

## Install

```
tern plugin link ~/ai/projects/tern_time
```

(or `tern plugin install ~/ai/projects/tern_time` for a copy). Reloads live;
remove with `tern plugin remove clock`.

## Use

- **Click the clock** (in the bar, or the segment in the status line) to open
  its settings picker: format, position, seconds.
- Palette: **Clock: settings…**, **Clock: toggle 12h / 24h**, **Clock: change
  position** (cycles all four).

Settings live in the plugin's `kv.json` and apply to every open window.

## Positions

| Position | Where |
| --- | --- |
| Centered | middle of the tab bar |
| Far left | leading end of the tab bar, tabs and session buttons shift clear |
| Beside the window buttons | trailing end, just left of Tern's minimize button (right of the tool icons when the system draws the title bar) |
| Status line | a segment in the bottom status line |

The clock is a status-line segment (`tern.chrome.status`) lifted into the tab
bar by the plugin's own stylesheet, so it uses only documented plugin APIs;
tabs, session switcher and window buttons get padding around it and never
collide. With vertical tab rails the segment stays in the status line, where
it reads best.

## Notes

- Time is the machine's local time (`os.date` in the plugin VM; the window
  follows the daemon host's zone and DST).
- Redraws are driven by one timer per window, armed to the next wall-clock
  second (with seconds) or minute (without); no polling between.
- The web tab runs no plugin window VM, so the clock shows in desktop windows;
  a headless `tern serve` session shows it once a desktop window attaches.
- The clock rides on the status line's segment host, so loading it turns
  Settings → **Show status line** on; that is the only setting it touches.

```
plugin.toml        manifest (window-only plugin + one style sheet)
window.luau        the plugin: formatter, CSS, picker, scheduler
styles/clock.css   in-flow segment style (reaches the web tab)
types/tern.d.luau  Luau definitions for luau-lsp (from `tern plugin types`)
```
