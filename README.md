# Kanban

A kanban board for Omarchy, running inside `omarchy-shell`. A bar widget shows
how much work is open and opens a full-screen board: columns you define, cards
you drag between them, and a detail sheet per card with notes, links, and
image attachments.

## Install

```bash
omarchy plugin add https://github.com/Chase-Fournier/chase.kanban.git --enable
```

That clones into `~/.config/omarchy/plugins/chase.kanban/`, checks the manifest
against the schema the shell enforces, and asks which bar section to put the
widget in. `omarchy plugin enable` is what marks the plugin enabled — the board
overlay loads along with the widget.

Already have the folder in place? Register it without re-cloning:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/chase.kanban
omarchy-shell shell rescanPlugins
omarchy plugin enable chase.kanban --section right
```

Update later with `omarchy plugin update chase.kanban`.

### Requirements

Omarchy with `omarchy-shell`. Everything the board needs at its core ships with
Omarchy; two conveniences lean on packages you may not have:

| Feature | Needs | If missing |
|---|---|---|
| Opening links, revealing the data folder | `xdg-utils` | Nothing opens |
| Paste an image from the clipboard | `wl-clipboard` (Omarchy base) | The board says it could not read the clipboard |
| **Browse…** file picker for images | `zenity` (`sudo pacman -S zenity`) | The board says zenity is not installed; paste a path or use the clipboard instead |

## Remove

```bash
omarchy plugin remove chase.kanban
```

That takes the widget out of `~/.config/omarchy/shell.json` and deletes the
plugin folder — the git repo upstream is untouched, and the command asks before
it does either.

**Your tasks are not deleted.** The board file lives outside the plugin folder,
so removing and reinstalling picks up exactly where you left off. To throw the
data away too:

```bash
rm -rf ~/.local/share/omarchy/kanban
```

Nothing else on the system is touched: the plugin writes only inside that one
folder, and installs no services, hooks, or files anywhere else.

## Using the board

**Open it** by clicking the bar widget, or:

```bash
omarchy-shell shell toggle chase.kanban '{}'
```

Bind that to a key in `~/.config/hypr/bindings.lua` if you want it on
`Super+K`.

| Where | Action |
|---|---|
| Bar widget, left click | Open / close the board |
| Bar widget, middle click | Open the board on a brand new task |
| Bar widget, right click | Open the board's data folder |
| Card, click | Open the task sheet |
| Card, right click | Duplicate the task |
| Card, drag | Move it to another column, or reorder it inside one |
| Card, hover | Done toggle, move left / right, delete |
| Column header `+` | Add a task to that column |
| Column header `⋮` | Column settings: name, accent, WIP limit, sort, delete |
| Board header | Search, add task, add column, board settings, close |

Keys on the board: `Esc` closes (or clears the search first), `Ctrl+N` adds a
task, `Ctrl+F` jumps to search, `Ctrl+,` opens board settings. Typing anything
else starts filtering. Inside the image viewer, `←` / `→` step through the
attachments.

## The task sheet

Title, column, priority, due date, tags, free-text details, links, and images.

- **Links** are stored as typed; a bare `example.com` gets `https://`. Clicking
  one closes the board and hands it to `xdg-open` — the board runs on the
  Wayland overlay layer, so it has to get out of the way for the browser to be
  reachable.
- **Due date** takes a typed `YYYY-MM-DD` or a click on the calendar button,
  which opens a month grid with Today and Clear.
- **Images** can be added three ways: paste a path, paste the clipboard
  (`wl-paste`, saved into `images/` next to the board file), or pick a file
  with `zenity` if it is installed. Clicking a thumbnail previews it in place rather than
  launching an external viewer.
- Edits save automatically. Text fields write back when you leave them; the
  details box saves shortly after you stop typing.

## Customising

Board settings (gear icon) cover the board name, the board's size on the
current screen, column width, compact cards, whether thumbnails / tags / due
dates show on cards, and delete confirmation.

### Size is per screen

A single percentage cannot serve two very different displays. A 3440x1440
ultrawide and a 1440x900 laptop panel (2880x1800 at scale 2) are 2.4x apart in
logical width, so the 40% that gives a comfortable 1376px board on one gives an
unusable 576px sliver on the other.

So each screen keeps its own width and height, keyed by logical resolution and
stored under `settings.screens` in `board.json`:

```json
"screens": { "3440x1440": { "width": 46, "height": 72 } }
```

A screen with no entry sizes itself from its content — wide enough for the
columns it has to show, capped so it never reaches the edges. That is usually
right without touching anything, which is why the sliders start out marked
`auto`. Moving either slider pins that screen; **Fit automatically** hands it
back. Adjusting one screen never touches another.

The board also opens on the output Hyprland has focused, so the size that
applies is the size for the screen you are actually looking at.
Column settings cover the name, one of eight accents, a WIP limit that turns
the count red when exceeded, a "finished work" flag that marks dropped cards
done, collapsing the column to a strip, and a one-shot sort by priority, due
date, title, or age.

The bar widget takes three settings in `~/.config/omarchy/shell.json`:

```json
{ "id": "chase.kanban", "icon": "", "showCount": true, "countColumn": "" }
```

`countColumn` blank counts every unfinished task; set it to a column name to
count just that one.

## Data

Everything lives in one file:

```
~/.local/share/omarchy/kanban/board.json    tasks, columns, board settings
~/.local/share/omarchy/kanban/images/       images pasted from the clipboard
```

It is plain JSON and safe to edit by hand or keep in git — the board re-reads
it every time it opens. If the file will not parse, the board opens empty and
refuses to save over it, so a typo is recoverable.

Nothing under `~/.local/share/omarchy/kanban/` is removed when the plugin is
uninstalled; see [Remove](#remove).

### What the board refuses to read

The shell is long-lived, so the board treats its own data folder as untrusted
input rather than as something it wrote. Before reading `board.json` it checks
the descriptor it is about to read from — not just the path — and refuses if it
is a symlink, is not a regular file, is not owned by you, or is over **8 MiB**.
A refusal shows in the board header and holds every save, exactly like a parse
error does, so the file on disk is never overwritten by a board that could not
read it.

Clipboard images are capped at **32 MiB** and land on a name `mktemp` picks, so
an oversized paste cannot fill the disk and a write cannot be redirected onto a
file planted at a name worth guessing.

## Scripting

```bash
omarchy-shell kanban open
omarchy-shell kanban close
omarchy-shell kanban toggle
omarchy-shell kanban add "Renew the domain"   # prints the new task id
omarchy-shell kanban count                    # open tasks
omarchy-shell kanban settings
```

The overlay also takes a payload when summoned directly:

```bash
omarchy-shell shell summon chase.kanban '{"newTask":true}'
omarchy-shell shell summon chase.kanban '{"task":"task-abc123"}'
omarchy-shell shell summon chase.kanban '{"settings":true}'
```

## Working on the plugin

| File | What it is |
|---|---|
| `Model.js` | All board data. Pure functions, no QML — every mutation returns a new board |
| `Board.qml` | The overlay: state, file IO, actions, header, lanes, and the modals |
| `BoardColumn.qml` | One lane: header, card stack, drop target |
| `TaskCard.qml` | One card, including the drag behaviour |
| `TaskDialog.qml` | The task sheet |
| `ColumnDialog.qml` | Column settings |
| `SettingsDialog.qml` | Board settings |
| `ImageViewer.qml` | In-place attachment preview |
| `Select.qml` | Dropdown with a settable height and no reopen-on-click race |
| `DatePicker.qml` | Due-date field: typed input plus a calendar popup |
| `CardAction.qml`, `FieldLabel.qml`, `TextArea.qml` | Small shared pieces |

`Select.qml` exists instead of `qs.Ui.Dropdown` because that one derives its
height from a shared token a form cannot override, and clicking its trigger
while the list is open reopens the list rather than closing it — the popup's
close policy dismisses on press, then the click handler sees a closed popup.

Editing `Board.qml` hot-reloads. Editing the **other** QML files often does
not: the engine caches those types by URL, and a plugin rescan does not
invalidate them. Run `omarchy restart shell` after touching them, otherwise you
will be looking at the previous version and wondering why nothing changed.

## License

MIT — see [LICENSE](LICENSE).
