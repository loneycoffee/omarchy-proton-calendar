# Proton Calendar

Omarchy's clock, with your Proton Calendar in its popup. A drop-in replacement
for `omarchy.clock`: same label, same formats, same keys, plus your events.

- **The month grid** has a dot under each day with events, one per calendar
  color. Click a day to see what is on it.
- **The agenda** lists the chosen day's events; for today, only the ones still
  to come (or running). Clicking an event opens Proton Calendar.
- **On the bar**, an event about to start is named next to the time
  (`Sunday 15:40  󰃰 in 20m · Standup`) and stays there while it runs.
- **A reminder** pops up a few minutes before each timed event.
- **Calendars** are added and removed right in the panel; each keeps its color.

Right click on the label cycles its format, middle click opens the timezone
picker, as with the stock clock.

## How it reads your calendar

Proton Calendar is end-to-end encrypted and has no API for other apps. What it
does offer, on paid plans, is a private link per calendar that serves it as an
`.ics` file:

1. Open [Proton Calendar](https://calendar.proton.me) on the web.
2. **Settings → All settings → Calendars**, pick a calendar.
3. Under **Share with anyone**, **Create link**, choose **full view**, copy it.
4. In the panel, **Add calendar**, give it a name, paste the link, `enter`.

It is read-only, and Proton says changes can take a while to show up through
these links. Anyone with a link can read that calendar, so the links are kept
in `~/.config/proton-calendar/calendars.json` (mode `0600`), never in
`shell.json`, and the expanded events in
`~/.cache/omarchy/plugins/proton-calendar/` (also yours only). Delete a link in
Proton's settings to revoke it.

## Install

```bash
omarchy plugin add https://github.com/loneycoffee/omarchy-proton-calendar.git
```

Then swap it in for the stock clock in `~/.config/omarchy/shell.json`: change
the `omarchy.clock` entry's `id` (and `bar.centerAnchor`, if it names the
clock) to `proton-calendar`. Your format settings carry over, and the file
reloads on save.

Needs `python-dateutil` (Omarchy ships it) for recurring events.

Open the panel from a keybinding with
`omarchy-shell shell toggle proton-calendar`.

## Settings

On the `proton-calendar` bar entry, besides the clock's own `format`,
`formatAlt`, `verticalFormat` and `weekStartDay`:

| Key                | Default                      | Meaning                                         |
|--------------------|------------------------------|-------------------------------------------------|
| `nextEventMinutes` | `30`                         | Name the next event on the bar this long before it (0: never) |
| `reminderMinutes`  | `10`                         | Notify this long before an event (0: never)     |
| `syncMinutes`      | `15`                         | How often to fetch the calendars                |
| `openUrl`          | `https://calendar.proton.me` | What clicking an event opens                    |

## Keys in the panel

`h`/`l` or `[`/`]` month · `j`/`k` or `{`/`}` year · `t` today · `w` week
start · `s` sync · `o` open Proton Calendar · `esc` close

## Command line

```
pcal calendars             JSON: the calendars set up (names and colors, no links)
pcal add NAME URL [COLOR]  add a calendar by its "Share with anyone" link
pcal remove NAME           forget a calendar and its cached events
pcal sync                  fetch every calendar, expand its events, cache them
pcal events                JSON: the cached events, sorted by start
pcal agenda [DAYS]         plain text: what is coming up (default 7 days)
```

Recurring events (with their exceptions and moved occurrences) are expanded
from two months back to four months ahead, in your local time zone.

## Credits

The clock label and month grid are Omarchy's own `omarchy.clock` (MIT), with
the memento mori bar left out.
