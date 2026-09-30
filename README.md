# Dual Clock

A second time zone for the Omarchy bar, meant to sit beside the stock clock:
the stock widget owns local time, this one owns the other zone — US Central
by default, any IANA zone by configuration.

## Install

```bash
omarchy plugin add https://github.com/kbohara315/Dual-Clock.git --enable
omarchy bar move kshitij.dual-clock --section center
```

## Use

| Action | Effect |
|---|---|
| Left click | Searchable time zone picker (full IANA list; renames only this widget, never the system) |
| Right click | Walk the time-format ring |
| Middle click | Copy local + second-zone time, with a confirmation notification |

## Settings

| Key | Default | Meaning |
|---|---|---|
| `timezone` | `America/Chicago` | IANA zone id; invalid values fall back to the default |
| `format` | `HH:mm` | Horizontal-bar time format |
| `verticalFormat` | `HH\nmm` | Stacked format for a vertical bar |
| `label` | `` (zone abbreviation) | Custom suffix, e.g. a stable `CST` that never becomes `CDT` |

Change them in the widget settings; every choice is written back to
`shell.json`. A hand-edited zone that is not a real zone never reaches the
clock — the label falls back instead of blanking.

## Command line

```bash
omarchy-shell kshitij.dual-clock refresh
omarchy-shell kshitij.dual-clock cycleFormat
omarchy-shell kshitij.dual-clock cycleTimezone
omarchy-shell kshitij.dual-clock pickTimezone
omarchy-shell kshitij.dual-clock copy
```

## Remove

```bash
omarchy plugin remove kshitij.dual-clock
```

## Dependencies

Only what Omarchy already ships: `date`, `timedatectl`,
`omarchy-menu-select` (zone picker), `omarchy-clipboard-paste-text`,
`omarchy-notification-send`. No daemons, no packages.

## How it works

`BarWidget.qml` renders; `Model.js` holds the pure zone math (unit-tested —
`node Model.js`). The UTC offset comes from one `date` call per 10 minutes
(no transition tables, so DST flips land at most a minute late) plus a
refresh whenever the zone changes. A failed lookup keeps the last good
reading instead of blanking the clock.
