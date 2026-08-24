// Pure board data. No QML types in here, so the same functions back the
// overlay, the bar widget's count, and anything scripted on top later.
//
// Every mutation takes a board and returns a *new* board: QML only
// re-evaluates a `property var` binding when the property is reassigned, so
// mutating in place would leave the UI showing yesterday's board.

var SCHEMA_VERSION = 1

var PRIORITIES = ["none", "low", "medium", "high", "urgent"]

// Column accents. Kept as an explicit palette rather than theme roles so a
// board reads as a board — the eye sorts columns by hue before it reads a
// heading. "" means "no accent, follow the theme".
var SWATCHES = ["", "#6ea8fe", "#5ecfa0", "#e8c46a", "#e08a5a", "#d16a8a", "#a98adf", "#7ec8d8"]

// ------------------------------------------------------------------ IO limits
//
// The shell is a long-lived process that outlives every board it opens, so
// anything read off disk or off the clipboard needs a ceiling. Without one a
// truncated download left at board.json, or a video frame sitting on the
// clipboard, is enough to pin the shell's memory or fill the disk.

var MAX_BOARD_BYTES = 8 * 1024 * 1024
var MAX_IMAGE_BYTES = 32 * 1024 * 1024

// How long any single read is allowed to take. Opening a path can block
// indefinitely (a FIFO waits for a writer, a stalled network mount waits
// forever); nothing here is worth hanging a bar widget over.
var IO_TIMEOUT_SECONDS = 5

// Reads board.json only if the descriptor we opened is a regular file we own
// and within the size cap.
//
// The open itself is the check that matters, so it is done with O_NOFOLLOW:
// the kernel refuses the open outright if the final component is a symlink,
// which leaves no window between testing the path and opening it. A test on
// the pathname could not do that — a path swapped to a symlink pointing at
// another file of ours after the test would be followed, and would pass every
// later check, because by then the descriptor really is a regular file we own.
// O_NONBLOCK covers the other way a pathname can misbehave: opening a FIFO
// left in place blocks until a writer shows up, and nothing here is worth
// hanging a bar widget over.
//
// Everything after the open reads that one descriptor and never the path
// again: fstat decides type, owner, and size, and the bytes come from the same
// descriptor those answers describe. perl is what gives us the open flags —
// the shell has no way to ask for them — and is a hard dependency of omarchy.
function readBoardCommand(path) {
  var script =
    'use strict; use warnings; ' +
    'use Errno qw(ENOENT ELOOP); ' +
    'use Fcntl qw(O_RDONLY O_NOFOLLOW O_NONBLOCK F_SETFL S_ISREG); ' +
    'my ($path, $max) = @ARGV; ' +
    'sub bail { print "ERR:board.json ", $_[0], "\\n"; exit 0 } ' +
    'my $fh; ' +
    'unless (sysopen($fh, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)) { ' +
    '  if ($! == ENOENT) { print "NEW:\\n"; exit 0 } ' +
    '  bail("is a symlink; refusing to read it") if $! == ELOOP; ' +
    '  bail("could not be opened"); ' +
    '} ' +
    'my @st = stat($fh) or bail("could not be inspected"); ' +
    'bail("is not a regular file; refusing to read it") unless S_ISREG($st[2]); ' +
    'bail("is not owned by you; refusing to read it") unless $st[4] == $<; ' +
    'bail(sprintf("is bigger than the %d MiB limit; refusing to read it", $max / 1048576)) if $st[7] > $max; ' +
    // O_NONBLOCK has done its job once the descriptor is known to be a regular
    // file; clearing it keeps a short read from ever looking like EOF.
    'fcntl($fh, F_SETFL, 0); ' +
    'binmode $fh; binmode STDOUT; ' +
    'print "OK:\\n"; ' +
    // Capped again on the way out rather than trusted to the size fstat saw,
    // so a file growing under us still cannot hand us more than the limit.
    'my $left = $max; ' +
    'while ($left > 0) { ' +
    '  my $n = sysread($fh, my $chunk, $left < 65536 ? $left : 65536); ' +
    '  last unless $n; ' +
    '  print $chunk; ' +
    '  $left -= $n; ' +
    '}'
  return ["timeout", String(IO_TIMEOUT_SECONDS), "perl", "-e", script,
          "--", String(path), String(MAX_BOARD_BYTES)]
}

// Splits what readBoardCommand printed into a status line and the payload that
// follows it. An empty read means the command was killed by its timeout.
function parseReadResult(text) {
  var raw = String(text || "")
  if (!raw) return { status: "error", content: "", message: "the board file could not be read in time" }
  var nl = raw.indexOf("\n")
  var head = nl === -1 ? raw : raw.slice(0, nl)
  var body = nl === -1 ? "" : raw.slice(nl + 1)
  if (head === "NEW:") return { status: "new", content: "", message: "" }
  if (head === "OK:") return { status: "ok", content: body, message: "" }
  if (head.indexOf("ERR:") === 0) return { status: "error", content: "", message: head.slice(4) }
  return { status: "error", content: "", message: "the board file could not be read" }
}

// Saves whatever image is on the clipboard into imagesDir, capped. mktemp is
// what makes the destination safe: it creates the file itself with O_EXCL and
// an unguessable suffix, so the write cannot land on something pre-planted at a
// name we could have predicted, and cannot follow a symlink out of the folder.
function clipboardImageCommand(imagesDir) {
  var script =
    'set -uo pipefail; ' +
    'dir=$1; max=$2; ' +
    'if [ -L "$dir" ] || [ ! -d "$dir" ]; then printf "ERR:the images folder is missing or is not a folder\\n"; exit 0; fi; ' +
    'command -v wl-paste >/dev/null 2>&1 || { printf "ERR:wl-clipboard is not installed\\n"; exit 0; }; ' +
    'mime=$(wl-paste --list-types 2>/dev/null | grep -m1 "^image/" || true); ' +
    '[ -n "$mime" ] || { printf "ERR:no image on the clipboard\\n"; exit 0; }; ' +
    'ext=${mime#image/}; case "$ext" in jpeg) ext=jpg;; svg+xml) ext=svg;; esac; ' +
    'case "$ext" in *[!A-Za-z0-9]*) ext=bin;; "") ext=bin;; esac; ' +
    'out=$(mktemp "$dir/paste-$(date +%Y%m%d-%H%M%S)-XXXXXXXX.$ext") || ' +
    '{ printf "ERR:could not create a file for the image\\n"; exit 0; }; ' +
    // head closes the pipe at the cap, so wl-paste dies of SIGPIPE on anything
    // oversized. That is the intended stop, not a failure worth reporting.
    'wl-paste --type "$mime" 2>/dev/null | head -c "$((max + 1))" > "$out"; ' +
    'written=$(stat -c %s "$out" 2>/dev/null || echo 0); ' +
    'if [ "$written" -eq 0 ]; then rm -f "$out"; printf "ERR:the clipboard image was empty\\n"; exit 0; fi; ' +
    // One byte over the cap is how we tell "exactly at the limit" from
    // "truncated", which is why head was asked for max + 1.
    'if [ "$written" -gt "$max" ]; then rm -f "$out"; printf "ERR:that image is bigger than the %s MiB limit\\n" "$((max / 1048576))"; exit 0; fi; ' +
    'printf "OK:%s\\n" "$out"'
  return ["timeout", String(IO_TIMEOUT_SECONDS * 4), "bash", "-c", script,
          "bash", String(imagesDir), String(MAX_IMAGE_BYTES)]
}

function uid(prefix) {
  return String(prefix || "id") + "-" + Date.now().toString(36) + "-"
    + Math.floor(Math.random() * 1679616).toString(36)
}

function now() {
  return Date.now()
}

function defaultSettings() {
  return {
    boardTitle: "Kanban",
    // Board size is per screen. A single percentage cannot serve a 3440x1440
    // ultrawide and a 1440x900 laptop panel at once: 40% is a comfortable
    // 1376px on one and an unusable 576px on the other. Keyed by logical
    // resolution, so the same physical screen is recognised wherever it is
    // plugged in, and any screen with no entry sizes itself from its content.
    //   screens: { "3440x1440": { width: 46, height: 72 } }
    screens: {},
    // Pre-per-screen setting. Kept only so an existing board can hand its
    // value to whichever screen it is first opened on; see migrateLegacySize.
    boardWidth: 0,
    boardHeight: 0,
    columnWidth: 300,
    compact: false,
    showImages: true,
    showDueDates: true,
    showTags: true,
    confirmDelete: true
  }
}

function defaultBoard() {
  var board = { version: SCHEMA_VERSION, columns: [], tasks: [], settings: defaultSettings() }
  var names = ["Backlog", "Todo", "Doing", "Done"]
  for (var i = 0; i < names.length; i++) {
    board.columns.push({
      id: uid("col"),
      name: names[i],
      color: SWATCHES[i + 1] || "",
      // The last column is where work lands, so cards dropped there count as
      // finished without the user having to tick anything.
      done: i === names.length - 1,
      wip: 0,
      collapsed: false
    })
  }
  return board
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function str(value, fallback) {
  return typeof value === "string" ? value : (fallback === undefined ? "" : fallback)
}

function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function strList(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var s = str(value[i], "").trim()
    if (s) out.push(s)
  }
  return out
}

// 0 means "not set"; anything else is pinned to a usable range.
function clampPercent(value, fallback) {
  var n = Math.round(num(value, fallback))
  if (n <= 0) return 0
  return Math.max(30, Math.min(100, n))
}

function normalizeScreens(raw) {
  var out = {}
  if (!isObject(raw)) return out
  for (var key in raw) {
    var entry = raw[key]
    if (!isObject(entry)) continue
    var width = clampPercent(entry.width, 0)
    var height = clampPercent(entry.height, 0)
    if (width === 0 && height === 0) continue
    out[String(key)] = { width: width, height: height }
  }
  return out
}

function normalizeColumn(raw, index) {
  var c = isObject(raw) ? raw : {}
  return {
    id: str(c.id) || uid("col"),
    name: str(c.name) || ("Column " + (index + 1)),
    color: str(c.color),
    done: c.done === true,
    wip: Math.max(0, Math.round(num(c.wip, 0))),
    collapsed: c.collapsed === true
  }
}

function normalizeTask(raw, columnIds) {
  var t = isObject(raw) ? raw : {}
  var priority = str(t.priority, "none")
  if (PRIORITIES.indexOf(priority) === -1) priority = "none"
  var columnId = str(t.columnId)
  // A task whose column was deleted out from under it lands in the first
  // column rather than vanishing from the board with no way to get it back.
  if (columnIds.indexOf(columnId) === -1) columnId = columnIds[0] || ""
  return {
    id: str(t.id) || uid("task"),
    columnId: columnId,
    title: str(t.title, "Untitled"),
    details: str(t.details),
    priority: priority,
    tags: strList(t.tags),
    due: str(t.due),
    links: strList(t.links),
    images: strList(t.images),
    done: t.done === true,
    created: num(t.created, now()),
    updated: num(t.updated, num(t.created, now()))
  }
}

function normalize(raw) {
  if (!isObject(raw)) return defaultBoard()

  var columns = []
  if (Array.isArray(raw.columns)) {
    for (var i = 0; i < raw.columns.length; i++) columns.push(normalizeColumn(raw.columns[i], i))
  }
  if (columns.length === 0) columns = defaultBoard().columns

  var columnIds = []
  for (var c = 0; c < columns.length; c++) columnIds.push(columns[c].id)

  var tasks = []
  if (Array.isArray(raw.tasks)) {
    for (var t = 0; t < raw.tasks.length; t++) tasks.push(normalizeTask(raw.tasks[t], columnIds))
  }

  var defaults = defaultSettings()
  var settings = isObject(raw.settings) ? raw.settings : {}
  var merged = {}
  for (var key in defaults) {
    merged[key] = settings[key] === undefined || settings[key] === null ? defaults[key] : settings[key]
  }
  merged.boardTitle = str(merged.boardTitle, defaults.boardTitle)
  merged.boardWidth = clampPercent(num(merged.boardWidth, 0), 0)
  merged.boardHeight = clampPercent(num(merged.boardHeight, 0), 0)
  merged.screens = normalizeScreens(merged.screens)
  merged.columnWidth = Math.max(200, Math.min(560, Math.round(num(merged.columnWidth, defaults.columnWidth))))
  merged.compact = merged.compact === true
  merged.showImages = merged.showImages !== false
  merged.showDueDates = merged.showDueDates !== false
  merged.showTags = merged.showTags !== false
  merged.confirmDelete = merged.confirmDelete !== false

  return { version: SCHEMA_VERSION, columns: columns, tasks: tasks, settings: merged }
}

function parse(raw) {
  var text = String(raw || "").trim()
  if (!text) return defaultBoard()
  try {
    return normalize(JSON.parse(text))
  } catch (e) {
    // A board we can't read is a board we must not overwrite. The caller
    // keeps the file untouched and shows an empty board instead.
    return null
  }
}

function serialize(board) {
  return JSON.stringify(normalize(board), null, 2) + "\n"
}

// ------------------------------------------------------------------ queries

function columnIndex(board, columnId) {
  for (var i = 0; i < board.columns.length; i++) if (board.columns[i].id === columnId) return i
  return -1
}

function column(board, columnId) {
  var i = columnIndex(board, columnId)
  return i === -1 ? null : board.columns[i]
}

function taskIndex(board, taskId) {
  for (var i = 0; i < board.tasks.length; i++) if (board.tasks[i].id === taskId) return i
  return -1
}

function task(board, taskId) {
  var i = taskIndex(board, taskId)
  return i === -1 ? null : board.tasks[i]
}

function matchesFilter(t, needle) {
  if (!needle) return true
  var q = needle.toLowerCase()
  if (t.title.toLowerCase().indexOf(q) !== -1) return true
  if (t.details.toLowerCase().indexOf(q) !== -1) return true
  for (var i = 0; i < t.tags.length; i++) if (t.tags[i].toLowerCase().indexOf(q) !== -1) return true
  return false
}

// Tasks keep board order inside their column, so a drop between two cards is
// a stable, explicit ordering rather than a re-sort that undoes itself.
function tasksIn(board, columnId, filterText) {
  var out = []
  for (var i = 0; i < board.tasks.length; i++) {
    var t = board.tasks[i]
    if (t.columnId !== columnId) continue
    if (!matchesFilter(t, filterText)) continue
    out.push(t)
  }
  return out
}

function countIn(board, columnId) {
  var n = 0
  for (var i = 0; i < board.tasks.length; i++) if (board.tasks[i].columnId === columnId) n++
  return n
}

function isDoneColumn(board, columnId) {
  var c = column(board, columnId)
  return !!c && c.done === true
}

// Open work = everything not sitting in a done column and not ticked off.
function openCount(board) {
  var n = 0
  for (var i = 0; i < board.tasks.length; i++) {
    var t = board.tasks[i]
    if (t.done) continue
    if (isDoneColumn(board, t.columnId)) continue
    n++
  }
  return n
}

function countInNamed(board, name) {
  var wanted = String(name || "").trim().toLowerCase()
  if (!wanted) return openCount(board)
  var n = 0
  for (var i = 0; i < board.columns.length; i++) {
    if (board.columns[i].name.toLowerCase() !== wanted) continue
    n += countIn(board, board.columns[i].id)
  }
  return n
}

function allTags(board) {
  var seen = {}
  var out = []
  for (var i = 0; i < board.tasks.length; i++) {
    var tags = board.tasks[i].tags
    for (var j = 0; j < tags.length; j++) {
      var key = tags[j].toLowerCase()
      if (seen[key]) continue
      seen[key] = true
      out.push(tags[j])
    }
  }
  return out.sort()
}

// --------------------------------------------------------------- mutations

function addColumn(board, name) {
  var next = clone(board)
  next.columns.push(normalizeColumn({
    name: String(name || "").trim() || "New column",
    color: SWATCHES[(next.columns.length % (SWATCHES.length - 1)) + 1]
  }, next.columns.length))
  return next
}

function updateColumn(board, columnId, patch) {
  var next = clone(board)
  var i = columnIndex(next, columnId)
  if (i === -1) return board
  for (var key in patch) next.columns[i][key] = patch[key]
  next.columns[i] = normalizeColumn(next.columns[i], i)
  return next
}

// Deleting a column takes its cards with it unless a fallback is given, in
// which case they move there. The board always keeps at least one column;
// with none, there is nowhere for a new task to go.
function removeColumn(board, columnId, moveToColumnId) {
  if (board.columns.length <= 1) return board
  var next = clone(board)
  var i = columnIndex(next, columnId)
  if (i === -1) return board
  next.columns.splice(i, 1)

  var kept = []
  for (var t = 0; t < next.tasks.length; t++) {
    var entry = next.tasks[t]
    if (entry.columnId !== columnId) { kept.push(entry); continue }
    if (moveToColumnId && columnIndex(next, moveToColumnId) !== -1) {
      entry.columnId = moveToColumnId
      entry.updated = now()
      kept.push(entry)
    }
  }
  next.tasks = kept
  return next
}

function moveColumn(board, columnId, delta) {
  var next = clone(board)
  var i = columnIndex(next, columnId)
  if (i === -1) return board
  var target = i + delta
  if (target < 0 || target >= next.columns.length) return board
  var moved = next.columns.splice(i, 1)[0]
  next.columns.splice(target, 0, moved)
  return next
}

function addTask(board, columnId, fields) {
  var next = clone(board)
  if (columnIndex(next, columnId) === -1) columnId = next.columns[0].id
  var created = normalizeTask({
    columnId: columnId,
    title: (fields && fields.title) || "",
    details: (fields && fields.details) || "",
    priority: (fields && fields.priority) || "none",
    created: now(),
    updated: now()
  }, [columnId])
  created.title = String(created.title).trim() || "Untitled task"
  // Adding straight into a done column is recording finished work, so it
  // lands the same way a card dragged there would.
  if (isDoneColumn(next, columnId)) created.done = true
  next.tasks.push(created)
  return { board: next, id: created.id }
}

function updateTask(board, taskId, patch) {
  var next = clone(board)
  var i = taskIndex(next, taskId)
  if (i === -1) return board
  for (var key in patch) next.tasks[i][key] = patch[key]
  next.tasks[i].updated = now()
  next.tasks[i] = normalizeTask(next.tasks[i], columnIdList(next))
  return next
}

function columnIdList(board) {
  var ids = []
  for (var i = 0; i < board.columns.length; i++) ids.push(board.columns[i].id)
  return ids
}

function removeTask(board, taskId) {
  var next = clone(board)
  var i = taskIndex(next, taskId)
  if (i === -1) return board
  next.tasks.splice(i, 1)
  return next
}

function duplicateTask(board, taskId) {
  var next = clone(board)
  var i = taskIndex(next, taskId)
  if (i === -1) return { board: board, id: "" }
  var copy = clone(next.tasks[i])
  copy.id = uid("task")
  copy.title = copy.title + " (copy)"
  copy.created = now()
  copy.updated = now()
  next.tasks.splice(i + 1, 0, copy)
  return { board: next, id: copy.id }
}

// Move a task to a column, optionally landing it before the card currently
// sitting at `beforeTaskId`. Both the drag-and-drop path and the keyboard
// "move left/right" path funnel through here so ordering behaves the same.
function moveTask(board, taskId, columnId, beforeTaskId) {
  var next = clone(board)
  var i = taskIndex(next, taskId)
  if (i === -1) return board
  if (columnIndex(next, columnId) === -1) return board

  var moved = next.tasks.splice(i, 1)[0]
  moved.columnId = columnId
  moved.updated = now()
  if (isDoneColumn(next, columnId)) moved.done = true
  else if (moved.done) moved.done = false

  var at = next.tasks.length
  if (beforeTaskId) {
    var b = taskIndex(next, beforeTaskId)
    if (b !== -1) at = b
  }
  next.tasks.splice(at, 0, moved)
  return next
}

function shiftTask(board, taskId, delta) {
  var t = task(board, taskId)
  if (!t) return board
  var i = columnIndex(board, t.columnId)
  var target = i + delta
  if (target < 0 || target >= board.columns.length) return board
  return moveTask(board, taskId, board.columns[target].id, "")
}

// Reorder within a column: move `taskId` one slot up or down among the cards
// that share its column, leaving other columns' ordering untouched.
function reorderTask(board, taskId, delta) {
  var t = task(board, taskId)
  if (!t) return board
  var siblings = []
  for (var i = 0; i < board.tasks.length; i++) {
    if (board.tasks[i].columnId === t.columnId) siblings.push(board.tasks[i].id)
  }
  var pos = siblings.indexOf(taskId)
  var target = pos + delta
  if (pos === -1 || target < 0 || target >= siblings.length) return board
  return moveTask(board, taskId, t.columnId,
    delta > 0 ? (siblings[target + 1] || "") : siblings[target])
}

// One-shot reorder of a single column. Unlike a display-order toggle this
// rewrites the stored order, so a later drag still means what it looks like.
function sortColumn(board, columnId, mode) {
  var next = clone(board)
  var mine = []
  var rest = []
  for (var i = 0; i < next.tasks.length; i++) {
    if (next.tasks[i].columnId === columnId) mine.push(next.tasks[i])
    else rest.push(next.tasks[i])
  }
  if (mine.length < 2) return board

  if (mode === "priority") {
    mine.sort(function(a, b) {
      var pa = PRIORITIES.indexOf(a.priority)
      var pb = PRIORITIES.indexOf(b.priority)
      if (pa !== pb) return pb - pa
      return a.created - b.created
    })
  } else if (mode === "due") {
    // Undated tasks sink; a board sorted by date should show the dated work.
    mine.sort(function(a, b) {
      var da = a.due || "9999-99-99"
      var db = b.due || "9999-99-99"
      if (da !== db) return da < db ? -1 : 1
      return a.created - b.created
    })
  } else if (mode === "title") {
    mine.sort(function(a, b) { return a.title.toLowerCase() < b.title.toLowerCase() ? -1 : 1 })
  } else if (mode === "created") {
    mine.sort(function(a, b) { return a.created - b.created })
  } else {
    return board
  }

  next.tasks = rest.concat(mine)
  return next
}

function clearColumn(board, columnId) {
  var next = clone(board)
  var kept = []
  for (var i = 0; i < next.tasks.length; i++) {
    if (next.tasks[i].columnId !== columnId) kept.push(next.tasks[i])
  }
  next.tasks = kept
  return next
}

// Everything ticked off or sitting in a done column, dropped in one go.
function archiveDone(board) {
  var next = clone(board)
  var kept = []
  for (var i = 0; i < next.tasks.length; i++) {
    var t = next.tasks[i]
    if (t.done || isDoneColumn(next, t.columnId)) continue
    kept.push(t)
  }
  if (kept.length === next.tasks.length) return board
  next.tasks = kept
  return next
}

function doneCount(board) {
  var n = 0
  for (var i = 0; i < board.tasks.length; i++) {
    var t = board.tasks[i]
    if (t.done || isDoneColumn(board, t.columnId)) n++
  }
  return n
}

// ----------------------------------------------------------- screen sizes

function screenSize(board, key) {
  var screens = board.settings.screens
  var entry = key && isObject(screens) ? screens[key] : null
  return isObject(entry) ? entry : null
}

function setScreenSize(board, key, patch) {
  if (!key) return board
  var next = clone(board)
  if (!isObject(next.settings.screens)) next.settings.screens = {}
  var entry = isObject(next.settings.screens[key]) ? next.settings.screens[key] : { width: 0, height: 0 }
  if (patch.width !== undefined) entry.width = clampPercent(patch.width, 0)
  if (patch.height !== undefined) entry.height = clampPercent(patch.height, 0)
  next.settings.screens[key] = entry
  return next
}

// Drop a screen's override so it goes back to sizing itself from its content.
function clearScreenSize(board, key) {
  if (!key || !screenSize(board, key)) return board
  var next = clone(board)
  delete next.settings.screens[key]
  return next
}

function hasScreenSizes(board) {
  var screens = board.settings.screens
  if (!isObject(screens)) return false
  for (var key in screens) return true
  return false
}

// A board saved before sizes went per-screen has one percentage that was
// tuned on whichever screen the user was looking at. Hand it to the screen
// the board opens on — the odds are that is the one — and let every other
// screen start from its content instead of inheriting a number chosen for a
// display it has nothing in common with.
function migrateLegacySize(board, key) {
  if (!key || hasScreenSizes(board)) return board
  var width = clampPercent(board.settings.boardWidth, 0)
  var height = clampPercent(board.settings.boardHeight, 0)
  if (width === 0 && height === 0) return board
  var next = setScreenSize(board, key, { width: width, height: height })
  next.settings.boardWidth = 0
  next.settings.boardHeight = 0
  return next
}

function updateSettings(board, patch) {
  var next = clone(board)
  for (var key in patch) next.settings[key] = patch[key]
  return normalize(next)
}

// ----------------------------------------------------------------- helpers

function parseTags(text) {
  var parts = String(text || "").split(",")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var tag = parts[i].trim()
    if (tag && out.indexOf(tag) === -1) out.push(tag)
  }
  return out
}

function tagsText(tags) {
  return Array.isArray(tags) ? tags.join(", ") : ""
}

function isImagePath(value) {
  return /\.(png|jpe?g|gif|webp|bmp|svg|avif)$/i.test(String(value || ""))
}

function normalizeLink(value) {
  var link = String(value || "").trim()
  if (!link) return ""
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(link)) return link
  if (link.charAt(0) === "/" || link.charAt(0) === "~") return link
  return "https://" + link
}

function linkLabel(value) {
  var link = String(value || "")
  var stripped = link.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "")
  return stripped.length > 58 ? stripped.slice(0, 57) + "…" : stripped
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts[parts.length - 1] || String(path || "")
}

// Due dates are plain YYYY-MM-DD strings so the file stays diffable and the
// field stays typeable. Anything unparseable is simply not overdue.
function dueState(value) {
  var text = String(value || "").trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return "none"
  var due = new Date(text + "T23:59:59")
  if (isNaN(due.getTime())) return "none"
  var today = new Date()
  var endOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 23, 59, 59)
  if (due.getTime() < endOfToday.getTime() - 86400000) return "overdue"
  if (due.getTime() <= endOfToday.getTime()) return "today"
  if (due.getTime() <= endOfToday.getTime() + 3 * 86400000) return "soon"
  return "later"
}

function dueLabel(value) {
  var text = String(value || "").trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return text
  var parts = text.split("-")
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var month = months[Math.max(0, Math.min(11, parseInt(parts[1], 10) - 1))]
  return month + " " + parseInt(parts[2], 10)
}
