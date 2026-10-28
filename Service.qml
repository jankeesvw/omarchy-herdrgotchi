import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import "Bots.js" as Bots

// Herdr Bots: every agent herdr is running, as a little pet standing on the
// bottom edge of the screen with its name on a plate under it, drawn as a
// plain cube or, if you would rather, a robot. They behave like Tamagotchis.
// A busy agent is at work: the cube builds a stack or fills its sides with
// text, the robot hammers on a stone or types at a little terminal. One that
// is waiting on you rocks and flashes red, or sits in a chair in the waiting
// room, and gets worse the longer you leave it. One that finished shows off
// for at least ten minutes, and if you never look, gets bored. The ones with
// nothing to do sleep together in a pile in the corner; a click on it lists
// them all.
//
// The moments worth seeing are the changes, so every change of state gets an
// animation of its own: confetti when work finishes, a startled "?!" when an
// agent starts waiting on you, a stretch when one wakes up, and a heart and a
// yawn when you have looked after it and it goes back to sleep.
//
// An agent on a saved SSH machine has a green "SSH" tag in front of its name.
//
// Hover a pet for its name, click it to land on its pane. Pick one up and it
// hangs from a climbing hold until you put it down somewhere else; it stays
// where you left it, asleep or awake. Sleepers can be dragged out of the pile
// or out of its list the same way, and go back in when you put them back on
// the line in the corner. Point at any of them and press H, and one after
// another they drop off the screen, for a minute, out of the way of whatever
// they were standing in front of.
//
// shell.json settings (top-level plugins[] entry):
//   { "id": "jankeesvw.herdr-bots",
//     "monitor": "DP-3",      // output name; default is the one focused at start
//     "side": "right",        // "right" or "left" corner
//     "marginX": 24, "marginY": 8,
//     "scale": 1.0,           // 1.0 makes the body 26 logical pixels square
//     "look": "cube",         // "cube" or "robot"
//     "sleepers": true }      // the pile of idle agents in the corner
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: "jankeesvw.herdr-bots"

  // ------------------------------------------------------------- settings

  // Third-party plugins get no shellConfig, so the entry is read out of
  // shell.json directly, the same file the shell itself reads.
  readonly property string userConfigPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/shell.json"
  // Parsed once per change of the file rather than inside every binding: a
  // read of the file from a binding fires onLoaded mid-evaluation, which Qt
  // reports as a binding loop.
  property var entry: ({})
  FileView {
    id: userConfig
    path: root.userConfigPath
    printErrors: false
    watchChanges: true
    onFileChanged: this.reload()
    onLoaded: root.readEntry(this.text())
  }

  function readEntry(text) {
    var found = ({})
    if (text && text.length <= 256 * 1024) {
      try {
        var parsed = JSON.parse(text)
        var list = parsed && Array.isArray(parsed.plugins) ? parsed.plugins : []
        for (var i = 0; i < list.length; i++)
          if (list[i] && String(list[i].id || "") === root.pluginId) found = list[i]
      } catch (e) {}
    }
    root.entry = found
  }

  function settingInt(key, fallback, min, max) {
    var n = Number(root.entry[key] === undefined ? fallback : root.entry[key])
    if (!isFinite(n)) return fallback
    return Math.max(min, Math.min(max, Math.round(n)))
  }

  readonly property int marginX: settingInt("marginX", 24, 0, 4000)
  readonly property int marginY: settingInt("marginY", 8, 0, 4000)
  readonly property real petScale: {
    var n = Number(root.entry.scale)
    return isFinite(n) && n >= 0.5 && n <= 3 ? n : 1
  }
  readonly property bool leftSide: String(root.entry.side || "right") === "left"
  readonly property bool showSleepers: root.entry.sleepers !== false
  readonly property string petLook: String(root.entry.look || "") === "robot" ? "robot" : "cube"
  readonly property string monitorSetting: {
    var value = String(root.entry.monitor || "")
    return /^[A-Za-z0-9._-]{1,64}$/.test(value) ? value : ""
  }

  // The pets stay on the monitor that had focus when they arrived, rather
  // than following focus around.
  property string startMonitor: ""
  function latchStartMonitor() {
    if (root.startMonitor === "" && Hyprland.focusedMonitor)
      root.startMonitor = String(Hyprland.focusedMonitor.name || "")
  }
  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() { root.latchStartMonitor() }
  }
  Component.onCompleted: root.latchStartMonitor()

  readonly property var targetScreen: {
    var screens = Quickshell.screens
    var wanted = root.monitorSetting !== "" ? root.monitorSetting : root.startMonitor
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === wanted) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  property bool present: true

  // Out of the way for a minute, for whatever was underneath them: left to
  // right, each one hops and drops off the bottom of the screen, and a
  // minute later they hop back in the same order and land on their spot.
  property string duck: ""          // "", "out", "away" or "in"
  property real duckT: 0            // ms into the drop or the way back
  property var duckRanks: ({})      // key -> its place from the left
  property int duckStep: 90         // ms between one and the next
  readonly property int duckMs: 480 // one drop, or one hop back
  NumberAnimation {
    id: duckRun
    target: root
    property: "duckT"
    from: 0
    onFinished: {
      if (root.duck === "out") { root.duck = "away"; duckTimer.restart() }
      else if (root.duck === "in") root.duck = ""
    }
  }
  Timer {
    id: duckTimer
    interval: 60000
    onTriggered: root.startDuck("in")
  }
  function duckAway() {
    if (root.duck !== "" || root.dragging || root.carry !== null) return
    root.pileOpen = false
    root.hovered = null
    root.startDuck("out")
  }
  function startDuck(phase) {
    var line = root.showSleepers && root.sleepers.length > 0 ? [{ key: "pile", item: pile, slot: null }] : []
    for (var i = 0; i < petRepeater.count; i++) {
      var slot = petRepeater.itemAt(i)
      if (slot) line.push({ key: slot.key, item: slot.bodyItem, slot: slot })
    }
    line.sort(function(a, b) { return a.item.mapToItem(null, 0, 0).x - b.item.mapToItem(null, 0, 0).x })
    var ranks = ({})
    root.duckStep = Math.min(90, Math.round(1100 / Math.max(1, line.length - 1)))
    for (var j = 0; j < line.length; j++) {
      ranks[line[j].key] = j
      // Back on its spot: the same bump as being put down.
      if (phase === "in" && line[j].slot) line[j].slot.droppedAt = Date.now() + j * root.duckStep + root.duckMs
    }
    root.duckRanks = ranks
    root.duck = phase
    duckRun.stop()
    root.duckT = 0
    duckRun.to = Math.max(0, line.length - 1) * root.duckStep + root.duckMs
    duckRun.duration = duckRun.to
    duckRun.start()
  }
  // How far below its spot one is, `fall` being enough to be out of sight.
  // Both ways it is a throw: up a little first, then down past its spot or
  // back onto it.
  function duckOffset(key, fall) {
    if (root.duck === "") return 0
    if (root.duck === "away") return fall
    var t = Math.max(0, Math.min(1, (root.duckT - (root.duckRanks[key] || 0) * root.duckStep) / root.duckMs))
    var h = 10 * root.k
    if (root.duck === "out") {
      var b = 2 * h + 2 * Math.sqrt(h * h + h * fall)
      return (fall + b) * t * t - b * t
    }
    var up = 2 * (fall + h) + 2 * Math.sqrt((fall + h) * h)
    return fall - up * t + (up - fall) * t * t
  }


  // ----------------------------------------------------------------- data

  readonly property string script: {
    var raw = String(Qt.resolvedUrl("bin/herdr-bots"))
    return raw.indexOf("file://") === 0 ? decodeURIComponent(raw.slice(7)) : ""
  }

  // Awake agents, in the order they woke up, so a pet keeps its spot instead
  // of shuffling every time another one changes state. Updated in place, so
  // a pet in the middle of an animation keeps playing it across refreshes.
  ListModel { id: pets }
  property var sleepers: []
  property string sleeperSignature: ""
  property bool demo: false

  // What every agent was doing at the last refresh, which is how a change of
  // state is noticed at all. The first refresh only fills it in: a shell
  // restart is not twenty agents finishing at once.
  property var lastStatus: ({})
  property var lastSince: ({})
  property bool primed: false

  // An agent that stops working keeps asking for attention for ten minutes,
  // even once herdr counts it as seen: a glance at its tab, or having it on
  // screen while it finishes, is not looking after it. Clicking the pet is.
  readonly property int attentionSeconds: 600
  property var finishedAt: ({})      // key -> when it stopped working
  property var dismissed: ({})       // key -> clicked since it finished

  // How long each change of state plays, in seconds.
  readonly property var transitionSeconds: ({ finished: 2.6, asked: 2.0, woke: 1.6, answered: 1.4, seen: 2.2, tired: 1.8 })

  function clean(value, limit) {
    return String(value === undefined || value === null ? "" : value).replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, limit)
  }

  function awakeStatus(status) {
    return status === "working" || status === "blocked" || status === "done"
  }

  function transitionFor(before, after) {
    if (after === "done") return "finished"
    if (after === "blocked") return "asked"
    if (after === "working") return before === "blocked" ? "answered" : "woke"
    return "seen"
  }

  function indexOfPet(key) {
    for (var i = 0; i < pets.count; i++) if (pets.get(i).key === key) return i
    return -1
  }

  function applyPayload(text) {
    var payload
    try { payload = JSON.parse(String(text).slice(0, 4 * 1024 * 1024)) } catch (e) { return }
    if (!payload || payload.ok !== true || !Array.isArray(payload.agents)) {
      pets.clear()
      root.sleepers = []
      return
    }
    root.demo = payload.demo === true

    var rows = []
    var byKey = ({})
    for (var i = 0; i < payload.agents.length && i < 200; i++) {
      var a = payload.agents[i]
      if (!a) continue
      // A pane id only means something on its own server, so an agent on a
      // saved SSH machine is told apart by the machine.
      var machine = root.clean(a.machine, 64)
      var row = {
        key: (machine ? "@" + machine : root.clean(a.session, 64)) + "/" + root.clean(a.pane, 64),
        session: root.clean(a.session, 64),
        machine: machine,
        pane: root.clean(a.pane, 64),
        kind: root.clean(a.kind, 32),
        status: root.clean(a.status, 16),
        since: Number(a.since) || 0,
        name: root.clean(a.name, 120) || root.clean(a.workspace, 80) || "agent",
        workspace: root.clean(a.workspace, 80)
      }
      rows.push(row)
      byKey[row.key] = row
    }

    var previous = root.lastStatus
    var now = Date.now()

    // What herdr says, before the attention rule below changes its mind.
    var statuses = ({})
    var sinces = ({})
    var finished = ({})
    for (var f = 0; f < rows.length; f++) {
      var row0 = rows[f]
      statuses[row0.key] = row0.status
      sinces[row0.key] = row0.since
      var before = previous[row0.key]
      var at = root.finishedAt[row0.key] || 0
      if (row0.status === "working" || row0.status === "blocked") at = 0
      else if (before === "working") at = now
      else if (!at && before === "done") at = root.lastSince[row0.key] || now
      if (root.dismissed[row0.key]) at = 0
      if (!at) continue
      if (row0.status === "done") { finished[row0.key] = at; continue }
      if (now - at < root.attentionSeconds * 1000) {
        finished[row0.key] = at
        row0.status = "done"
        row0.since = at
      }
    }

    // Pets already on screen: follow their agent, or say goodbye to it.
    for (var j = pets.count - 1; j >= 0; j--) {
      var pet = pets.get(j)
      var fresh = byKey[pet.key]
      if (!fresh) { pets.remove(j); continue }           // the agent is gone
      var placed = root.placements[pet.key] !== undefined
      if (!root.awakeStatus(fresh.status) && !placed) {
        // Gone back to sleep: stays for its goodbye, then walks into the pile.
        if (!pet.leaving) {
          pets.setProperty(j, "leaving", true)
          pets.setProperty(j, "transition", root.goodbyeFor(pet.key, previous))
          pets.setProperty(j, "transitionAt", now)
        }
        continue
      }
      if (!root.awakeStatus(fresh.status)) {
        // Asleep where it was put down: it goes to bed right there.
        if (root.awakeStatus(pet.status) && !pet.leaving) {
          pets.setProperty(j, "transition", root.goodbyeFor(pet.key, previous))
          pets.setProperty(j, "transitionAt", now)
        }
        if (pet.leaving) pets.setProperty(j, "leaving", false)
      } else if (pet.status !== fresh.status || pet.leaving) {
        pets.setProperty(j, "transition", root.transitionFor(pet.leaving ? "idle" : pet.status, fresh.status))
        pets.setProperty(j, "transitionAt", now)
        pets.setProperty(j, "leaving", false)
      }
      for (var role in fresh)
        if (pet[role] !== fresh[role]) pets.setProperty(j, role, fresh[role])
    }

    // Agents that just woke up, or that are new since the last refresh.
    for (var k = 0; k < rows.length; k++) {
      var r = rows[k]
      var shown = root.awakeStatus(r.status) || root.placements[r.key] !== undefined
      if (!shown || root.indexOfPet(r.key) !== -1) continue
      var entry = {}
      for (var field in r) entry[field] = r[field]
      entry.leaving = false
      entry.transition = root.primed && root.awakeStatus(r.status) ? root.transitionFor(previous[r.key] || "idle", r.status) : ""
      entry.transitionAt = now
      pets.append(entry)
    }

    var asleep = []
    for (var m = 0; m < rows.length; m++) {
      if (root.awakeStatus(rows[m].status) || root.placements[rows[m].key] !== undefined) continue
      var at = root.indexOfPet(rows[m].key)
      if (at !== -1 && pets.get(at).leaving) continue    // still saying goodbye
      asleep.push(rows[m])
    }
    // Replaced only when something changed: a new array rebuilds every
    // sleeper in an unfolded pile, right under the pointer, and would drop
    // the one being dragged out of it.
    var signature = asleep.map(function(r) { return r.key + "|" + r.name + "|" + r.since + "|" + r.workspace }).join("\n")
    if (signature !== root.sleeperSignature && root.carry === null) {
      root.sleeperSignature = signature
      root.sleepers = asleep
    }
    root.lastStatus = statuses
    root.lastSince = sinces
    root.finishedAt = finished
    var stillDismissed = ({})
    for (var d in root.dismissed) if (statuses[d] === "done" || statuses[d] === "idle") stillDismissed[d] = true
    root.dismissed = stillDismissed
    root.primed = true
  }

  // Looked after, it says thank you as it goes to sleep; given up on, it
  // just yawns.
  function goodbyeFor(key, previous) {
    return root.dismissed[key] || (previous[key] !== undefined && previous[key] !== "idle") ? "seen" : "tired"
  }

  // A pet that has said goodbye, or a sleeper put back on the line, leaves
  // the stage and joins the pile.
  function retire(key) {
    var at = root.indexOfPet(key)
    if (at === -1 || root.placements[key] !== undefined) return
    var gone = pets.get(at)
    if (!gone.leaving && root.awakeStatus(gone.status)) return
    var row = { key: gone.key, session: gone.session, machine: gone.machine, pane: gone.pane, kind: gone.kind,
                status: "idle", since: root.awakeStatus(gone.status) ? Date.now() : gone.since,
                name: gone.name, workspace: gone.workspace }
    pets.remove(at)
    var next = root.sleepers.slice()
    next.unshift(row)
    root.sleepers = next
    root.sleeperSignature = ""
  }

  Process {
    id: listProc
    command: [root.script, "list"]
    stdout: StdioCollector { onStreamFinished: root.applyPayload(text) }
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.present && root.script !== ""
    triggeredOnStart: true
    onTriggered: if (!listProc.running) listProc.running = true
  }

  Process { id: focusProc; onExited: refreshSoon.restart() }
  Timer { id: refreshSoon; interval: 400; onTriggered: if (!listProc.running) listProc.running = true }

  // The pet you just clicked gets a heart for a moment: it was looked after.
  property string lovedKey: ""
  Timer { id: loveTimer; interval: 1800; onTriggered: root.lovedKey = "" }

  function attend(session, pane, key, machine) {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(session)) return
    if (!/^[A-Za-z0-9_-]{1,32}:[A-Za-z0-9_-]{1,32}$/.test(pane)) return
    machine = machine || ""
    if (machine !== "" && !/^[A-Za-z0-9_-]{1,64}$/.test(machine)) return
    root.lovedKey = key
    loveTimer.restart()
    if (key) {
      var next = ({})
      for (var d in root.dismissed) next[d] = true
      next[key] = true
      root.dismissed = next
    }
    if (focusProc.running) return
    focusProc.command = [root.script, "focus", session, pane].concat(machine ? [machine] : [])
    focusProc.running = true
  }

  // Who needs looking after first: whoever has waited longest for an
  // answer, then whoever finished longest ago.
  function neediest() {
    var best = null, bestRank = 9
    for (var i = 0; i < pets.count; i++) {
      var p = pets.get(i)
      if (p.leaving) continue
      var rank = p.status === "blocked" ? 0 : (p.status === "done" ? 1 : 9)
      if (rank < bestRank || (rank === bestRank && best && p.since < best.since)) {
        best = p; bestRank = rank
      }
    }
    return bestRank < 9 ? best : null
  }

  IpcHandler {
    target: "jankeesvw.herdr-bots"
    function attend(): string {
      var p = root.neediest()
      if (!p) return "nobody needs you"
      root.attend(p.session, p.pane, p.key, p.machine)
      return "ok"
    }
    function show(): string { root.present = true; return "ok" }
    function hide(): string { root.present = false; return "ok" }
    function toggle(): string { root.present = !root.present; return "ok" }
    function unfold(): string { root.pileOpen = !root.pileOpen; return "ok" }
  }

  // ---------------------------------------------------------- animation

  // One clock drives every pet, but each pet keeps its own time on it: its
  // own tempo, its own starting point, and now and then a breather while it
  // works. Three pets hammering in step look like one machine.
  property double clock: Date.now()
  Timer {
    interval: 80
    repeat: true
    running: root.present && win.visible
    onTriggered: root.clock = Date.now()
  }

  function age(since) {
    if (!since) return 0
    return Math.max(0, (root.clock - since) / 1000)
  }

  function ageText(seconds) {
    if (seconds < 60) return "just now"
    var m = Math.floor(seconds / 60)
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h " + (m % 60) + "m"
    return Math.floor(h / 24) + "d"
  }

  function statusLine(status, since) {
    var a = root.age(since)
    switch (status) {
    case "blocked": return "needs you" + (a >= 60 ? ", waiting " + root.ageText(a) : "")
    case "done": return a >= 60 ? "done " + root.ageText(a) + " ago" : "done"
    case "working": return a >= 60 ? "working for " + root.ageText(a) : "working"
    default: return a >= 60 ? "asleep for " + root.ageText(a) : "asleep"
    }
  }

  // A pet keeps the same job for as long as it lives: the hammer or the
  // terminal, picked from its pane id so it survives a shell restart.
  function toolFor(key) {
    var h = 0
    for (var i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) | 0
    return (h & 1) ? "terminal" : "hammer"
  }

  function hopEvery(s, t, period, length) {
    var p = t % period
    if (p < length) { s.pose = "hop"; s.lift = p / length }
  }

  // What a pet is doing right now, for Bots.js to draw in either look.
  function petState(p) {
    var now = root.clock
    var a = root.age(p.since)
    var s = {
      kind: p.kind, accent: String(Commons.Color.accent),
      t: p.own, tempo: 1, blink: p.blinking, look: 0, pose: "stand", arms: "down",
      emote: "", face: "working", tears: false, shake: false, mess: false, tool: "", burst: 0, lift: 0
    }

    if (p.held) { s.pose = "hang"; s.face = "whee"; return s }

    // Put down: a little bump on landing.
    var landed = (now - p.droppedAt) / 1000
    if (landed >= 0 && landed < 0.3) { s.pose = "sit"; s.face = "happy"; return s }

    if (root.lovedKey === p.key) {
      s.face = "love"; s.emote = "heart"; s.arms = "up"
      root.hopEvery(s, p.own, 0.5, 0.4)
      return s
    }

    var t = (now - p.transitionAt) / 1000
    var length = root.transitionSeconds[p.transition] || 0
    if (p.transition !== "" && t >= 0 && t < length) {
      switch (p.transition) {
      case "finished":
        // A crouch, a leap, a burst of confetti, and a little dance after.
        s.face = "happy"; s.emote = "confetti"; s.burst = Math.min(1, t / 1.8)
        s.arms = t < 1.2 ? "up" : "cheer"
        if (t < 0.25) s.pose = "sit"
        else if (t < 0.85) { s.pose = "leap"; s.lift = (t - 0.25) / 0.6 }
        else root.hopEvery(s, t - 0.85, 0.45, 0.35)
        return s
      case "asked":
        // Startled out of its work, then off to the waiting room.
        s.face = "worried"; s.emote = "alarm"
        if (t < 0.6) { s.pose = "leap"; s.lift = t / 0.6; s.arms = "up" }
        else { s.pose = "chair"; s.shake = t < 1.2 }
        return s
      case "woke":
        // Eyes open, a stretch, a hop, and to work.
        if (t < 0.5) { s.pose = "sit"; s.face = "sleep"; s.emote = "snooze" }
        else if (t < 1.1) { s.pose = "sit"; s.face = "working"; s.arms = "up"; s.blink = t < 0.6 }
        else { s.pose = "hop"; s.lift = (t - 1.1) / 0.5; s.face = "happy" }
        return s
      case "answered":
        s.face = "love"; s.emote = "heart"; s.arms = "up"
        root.hopEvery(s, t, 0.5, 0.4)
        return s
      case "seen":
        // A thank-you, a yawn, and off to bed.
        if (t < 1.1) { s.face = "love"; s.emote = "heart"; s.arms = "up"; root.hopEvery(s, t, 0.55, 0.4) }
        else { s.face = "sleep"; s.emote = "snooze"; s.pose = "sit" }
        return s
      case "tired":
        // Nobody came: a sigh, and off to bed.
        s.pose = "sit"
        if (t < 0.7) s.face = "bored"
        else { s.face = "sleep"; s.emote = "snooze" }
        return s
      }
    }

    switch (p.status) {
    case "working":
      s.tool = root.toolFor(p.key)
      s.arms = "tool"
      s.look = p.resting ? 0 : 1            // a breather: it looks up at you
      break
    case "blocked":
      // The waiting room: a chair, swinging legs, a wave now and then. After
      // a minute it starts crying, after five it cannot sit still.
      s.pose = "chair"
      s.face = "worried"
      s.emote = a >= 300 ? "bangbang" : "bang"
      s.arms = (p.own % 6) < 1.6 ? "wave" : "down"
      s.tears = a >= 60
      s.shake = a >= 300 && (p.own % 2) < 0.6
      break
    case "done":
      // Proud for a quarter of an hour, then bored, and it shows.
      if (a < 900) {
        s.face = "happy"; s.arms = "cheer"; s.emote = "sparkle"
        root.hopEvery(s, p.own, 2.2, 0.4)
      } else {
        s.face = "bored"; s.pose = "sit"; s.mess = true
      }
      break
    default:
      s.face = "sleep"; s.pose = "sit"; s.emote = "snooze"
    }
    return s
  }

  // Sizes, in logical pixels. The sprite box is Bots.W x Bots.H units.
  readonly property real k: root.petScale
  readonly property int spriteW: Math.ceil(Bots.W * root.k)
  readonly property int spriteH: Math.ceil(Bots.H * root.k)
  // A sleeper needs no room for a tool beside it.
  readonly property int sleeperW: Math.ceil(44 * root.k)
  // Where a picked-up pet's climbing hold is, inside its sprite: right
  // above the middle of the pet.
  readonly property real holdX: 23 * root.k
  readonly property real holdY: 5 * root.k
  // The name plate under an awake pet's feet, and the pet with it. A long
  // name takes as many lines as it needs, and the tallest plate sets where
  // the ground is, so they all still stand on one line.
  readonly property int plateH: Math.round(13 * root.k)
  property var plateHeights: ({})       // key -> its plate's height
  readonly property int plateRoom: {
    var most = root.plateH
    for (var key in root.plateHeights) most = Math.max(most, root.plateHeights[key])
    return most
  }
  readonly property int petH: root.spriteH + root.plateRoom + Math.round(2 * root.k)

  // The green tag in front of the name of an agent on a saved SSH machine,
  // sized to the text it stands next to.
  component SshTag: Rectangle {
    property real size: 9
    width: Math.ceil(tagText.implicitWidth + size * 0.6)
    height: Math.round(size * 1.15)
    radius: Math.round(size * 0.25)
    color: Bots.GREEN

    Text {
      id: tagText
      anchors.centerIn: parent
      text: "SSH"
      color: Bots.OUTLINE
      font.family: Style.font.family
      font.pixelSize: Math.round(parent.size * 0.72)
      font.weight: Font.Bold
    }
  }

  function notePlate(key, height) {
    var next = ({})
    for (var k in root.plateHeights) if (k !== key) next[k] = root.plateHeights[k]
    if (height > 0) next[key] = height
    root.plateHeights = next
  }

  // The pile of sleepers, and the list of them that opens above it. It
  // closes itself a while after the pointer has gone.
  property bool pileOpen: false
  Timer {
    id: foldTimer
    interval: 5000
    onTriggered: if (!listHover.hovered && root.carry === null) root.pileOpen = false
  }
  // Latest asleep first: the one you were just busy with is on top.
  readonly property var sleepersByRecent: root.sleepers.slice().sort(function(a, b) { return b.since - a.since })

  // ------------------------------------------------------- picking up

  // Where pets were put down, by agent, in window coordinates. A pet put
  // down somewhere stays there, asleep or awake, until it is put back on
  // the line in the corner.
  property var placements: ({})
  property bool dragging: false
  // From the press on, the whole output takes the pointer: Hyprland sends a
  // pointer that leaves the input region to whatever is under it, button
  // down or not, and a quick flick off the pet would never come back.
  property bool pressing: false

  // Remembers where a pet was put down, or forgets it when it went back on
  // the line in the corner, and says which.
  function placeAt(key, pointerX, pointerY) {
    var next = ({})
    for (var k in root.placements) next[k] = root.placements[k]
    // The line counts one pet further out than it reaches, on the side it
    // grows on, where a pet that rejoins it is going to stand.
    var home = habitat.mapToItem(null, 0, 0)
    var left = home.x - 20 - (root.leftSide ? 0 : root.spriteW)
    var right = home.x + habitat.width + 20 + (root.leftSide ? root.spriteW : 0)
    var nearHome = pointerX >= left && pointerX <= right
                && pointerY >= home.y - 20 && pointerY <= home.y + habitat.height + 20
    if (nearHome) delete next[key]
    else next[key] = {
      x: Math.max(0, Math.min(win.width - root.spriteW, pointerX - root.holdX)),
      y: Math.max(0, Math.min(win.height - root.petH, pointerY - root.holdY))
    }
    root.placements = next
    return !nearHome
  }

  function drop(pet, pointerX, pointerY) {
    var placed = root.placeAt(pet.key, pointerX, pointerY)
    pet.held = false
    pet.droppedAt = Date.now()
    root.dragging = false
    root.pressing = false
    // A sleeper put back on the line goes back into the pile; one put down
    // on its way there stays, once the next refresh has seen it.
    var key = pet.key
    if (!placed && !root.awakeStatus(pet.status)) Qt.callLater(function() { root.retire(key) })
    if (placed && pet.leaving) refreshSoon.restart()
  }

  // A sleeper lifted out of the pile, from the heap or from its list. It
  // hangs under the pointer until it is put down, and then becomes a pet of
  // its own on that spot, asleep.
  property var carry: null
  property real carryX: 0
  property real carryY: 0
  property string landedKey: ""

  function dragSleeper(area, mouse, pressX, pressY, row) {
    if (!area.pressed || !row) return
    if (root.carry === null) {
      if (Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) < 5) return
      root.carry = row
      root.dragging = true
      root.hovered = null
    }
    var g = area.mapToItem(null, mouse.x, mouse.y)
    root.carryX = g.x
    root.carryY = g.y
  }

  // A release that carried nothing was a click.
  function releaseSleeper(area, mouse, click) {
    if (root.carry === null) { root.pressing = false; click(); return }
    var g = area.mapToItem(null, mouse.x, mouse.y)
    root.putSleeper(g.x, g.y)
  }

  function putSleeper(pointerX, pointerY) {
    var row = root.carry
    root.carry = null
    root.dragging = false
    root.pressing = false
    if (row === null) return
    var placed = root.placeAt(row.key, pointerX, pointerY)
    if (placed) root.landedKey = row.key
    // The list closes, and the sleeper goes onto the stage, once the press
    // that carried it is over: the list row holding that press goes with it.
    Qt.callLater(function() {
      root.pileOpen = false
      if (!placed || root.indexOfPet(row.key) !== -1) return     // back on the pile
      root.sleepers = root.sleepers.filter(function(r) { return r.key !== row.key })
      root.sleeperSignature = ""
      var entry = ({})
      for (var field in row) entry[field] = row[field]
      entry.leaving = false
      entry.transition = ""
      entry.transitionAt = Date.now()
      pets.append(entry)
    })
  }

  Component {
    id: regionComponent
    Region { intersection: Intersection.Combine }
  }
  property var petRegions: []

  // ------------------------------------------------------------- window

  property var hovered: null     // { item, src, name, line }

  PanelWindow {
    id: win
    screen: root.targetScreen
    visible: root.present && root.duck !== "away" && root.targetScreen !== null && (pets.count > 0 || (root.showSleepers && root.sleepers.length > 0))

    // The surface covers the whole output and never resizes, so there is no
    // layer animation to play. The mask keeps everything but the pets, the
    // pile and the name bubble click-through, and takes the whole screen
    // only while a pet is being carried.
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "jankeesvw-herdr-bots"
    WlrLayershell.layer: WlrLayer.Top
    // Keys only while one of them is pointed at or the pile is open, so the
    // pets never take the keyboard from the window you are typing in. Held
    // through a press and a drag too: giving the keyboard back mid-drag has
    // the compositor refocus, and the refocus takes the pointer grab with it.
    WlrLayershell.keyboardFocus: root.duck === "" && (root.pileOpen || root.hovered !== null || root.pressing || root.dragging)
                                 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Item {
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_H) { root.duckAway(); event.accepted = true }
        else if (event.key === Qt.Key_Escape && root.pileOpen) { root.pileOpen = false; event.accepted = true }
      }
    }

    Region { id: pileRegion; item: pile; intersection: Intersection.Combine }
    Region {
      id: bubbleRegion
      intersection: Intersection.Combine
      x: bubble.x
      y: bubble.y
      width: bubble.visible ? bubble.width : 0
      height: bubble.visible ? bubble.height : 0
    }
    Region {
      id: carryRegion
      intersection: Intersection.Combine
      width: root.dragging || root.pressing ? win.width : 0
      height: root.dragging || root.pressing ? win.height : 0
    }
    Region {
      id: listRegion
      intersection: Intersection.Combine
      x: sleepList.x
      y: sleepList.y
      width: sleepList.visible ? sleepList.width : 0
      height: sleepList.visible ? sleepList.height : 0
    }
    mask: Region { regions: [pileRegion, bubbleRegion, carryRegion, listRegion].concat(root.petRegions) }

    Row {
      id: habitat
      layoutDirection: root.leftSide ? Qt.LeftToRight : Qt.RightToLeft
      spacing: 0
      x: root.leftSide ? root.marginX : win.width - width - root.marginX
      y: win.height - height - root.marginY
      height: root.petH

      // The pile sits in the corner, with its head count right in it; the
      // awake pets line up beside it, newest furthest out.
      Row {
        id: pile
        visible: root.showSleepers && root.sleepers.length > 0
        layoutDirection: habitat.layoutDirection
        height: root.spriteH
        transform: Translate { y: root.duckOffset("pile", win.height - habitat.y + 4) }

        readonly property string kind: {
          var counts = ({}), best = "", bestN = 0
          for (var i = 0; i < root.sleepers.length; i++) {
            var k = root.sleepers[i].kind
            counts[k] = (counts[k] || 0) + 1
            if (counts[k] > bestN) { bestN = counts[k]; best = k }
          }
          return best
        }

        function hoverPile() {
          foldTimer.stop()
          if (root.pileOpen) return
          root.hovered = { item: countBox, src: null, name: root.sleepers.length + " asleep", line: "click for the list" }
        }
        function togglePile() {
          root.pileOpen = !root.pileOpen
          root.hovered = null
        }

        Item {
          id: countBox
          width: countLabel.implicitWidth + 6 * root.k
          height: root.spriteH

          Text {
            id: countLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3 * root.k
            text: "×" + root.sleepers.length
            textFormat: Text.PlainText
            color: Bots.SNOOZE
            style: Text.Outline
            styleColor: Bots.OUTLINE
            font.family: Style.font.family
            font.pixelSize: Math.round(11 * root.k)
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: pile.hoverPile()
            onExited: {
              if (root.hovered && root.hovered.item === countBox) root.hovered = null
              if (root.pileOpen) foldTimer.restart()
            }
            onClicked: pile.togglePile()
          }
        }

        // One heap, sound asleep.
        Item {
          id: heap
          width: root.sleeperW
          height: root.spriteH

          Canvas {
            id: heapCanvas
            width: root.spriteW
            height: root.spriteH
            renderStrategy: Canvas.Cooperative
            onPaint: Bots.draw(root.petLook, getContext("2d"), width, height, {
              kind: pile.kind, accent: String(Commons.Color.accent),
              t: root.clock / 1000 * 0.8, face: "sleep", pose: "sit", emote: "snooze"
            })
            Connections {
              target: root
              function onClockChanged() { if (pile.visible) heapCanvas.requestPaint() }
            }
          }

          // A click opens the list; a drag takes the latest sleeper out.
          MouseArea {
            id: heapMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: root.carry !== null ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            property real pressX: 0
            property real pressY: 0
            onEntered: pile.hoverPile()
            onExited: {
              if (root.hovered && root.hovered.item === countBox) root.hovered = null
              if (root.pileOpen) foldTimer.restart()
            }
            onPressed: function(mouse) { heapMouse.pressX = mouse.x; heapMouse.pressY = mouse.y; root.pressing = true }
            onPositionChanged: function(mouse) {
              root.dragSleeper(heapMouse, mouse, heapMouse.pressX, heapMouse.pressY, root.sleepersByRecent[0] || null)
            }
            onReleased: function(mouse) { root.releaseSleeper(heapMouse, mouse, pile.togglePile) }
            onCanceled: root.putSleeper(root.carryX, root.carryY)
          }
        }
      }

      Repeater {
        id: petRepeater
        model: pets

        // A slot in the line; the pet itself may be standing anywhere.
        delegate: Item {
          id: pet
          required property string key
          required property string session
          required property string pane
          required property string machine
          readonly property Item bodyItem: body
          required property string kind
          required property string status
          required property double since
          required property string name
          required property string workspace
          required property string transition
          required property double transitionAt
          required property bool leaving

          readonly property var spot: root.placements[pet.key] || null
          property bool held: false
          property real holdAtX: 0          // sprite position while carried
          property real holdAtY: 0
          property double droppedAt: 0

          // Its own clock: a tempo, a starting point, and breathers.
          readonly property real tempo: 0.8 + Math.random() * 0.45
          property real own: Math.random() * 30
          property double lastTick: Date.now()
          property bool resting: false
          property double restUntil: 0
          property double blinkAt: Date.now() + 1500 + Math.random() * 4000
          readonly property bool blinking: root.clock >= blinkAt && root.clock < blinkAt + 140

          width: (spot || held) ? 0 : root.spriteW
          height: root.petH

          property var hit: null
          Component.onCompleted: {
            pet.hit = regionComponent.createObject(win, { item: body })
            root.petRegions = root.petRegions.concat([pet.hit])
            if (root.landedKey === pet.key) { pet.droppedAt = Date.now(); root.landedKey = "" }
          }
          Component.onDestruction: {
            if (root.hovered && root.hovered.item === body) root.hovered = null
            if (pet.held) root.dragging = false
            if (grab.pressed) root.pressing = false
            root.notePlate(pet.key, 0)
            var mine = pet.hit
            root.petRegions = root.petRegions.filter(function(r) { return r !== mine })
            if (mine) mine.destroy()
          }

          function tick() {
            var now = root.clock
            var dt = Math.min(0.5, Math.max(0, (now - pet.lastTick) / 1000))
            pet.lastTick = now
            if (pet.status === "working" && !pet.held) {
              if (pet.resting) { if (now >= pet.restUntil) pet.resting = false }
              else if (Math.random() < dt * 0.07) { pet.resting = true; pet.restUntil = now + 1200 + Math.random() * 2600 }
            } else {
              pet.resting = false
            }
            if (!pet.resting) pet.own += dt * pet.tempo
            if (now > pet.blinkAt + 140) pet.blinkAt = now + 2500 + Math.random() * 5000
            if (pet.leaving && !pet.held && !pet.spot && (now - pet.transitionAt) / 1000 >= root.transitionSeconds.seen) {
              var key = pet.key
              Qt.callLater(function() { root.retire(key) })
              return
            }
            canvas.requestPaint()
          }

          Connections {
            target: root
            function onClockChanged() { pet.tick() }
          }

          // The pet itself lives on the stage, not in its slot: a Row skips
          // a slot that is down to no width, and everything in it with it.
          // Following the slot by binding also moves the pet's input region
          // along when the line shifts, which a Region only notices from
          // the item's own x and y.
          Item {
            id: body
            readonly property var src: pet
            parent: stage
            width: root.spriteW
            height: root.spriteH + plate.height + Math.round(2 * root.k)
            x: pet.held ? pet.holdAtX : (pet.spot ? pet.spot.x : habitat.x + pet.x)
            y: pet.held ? pet.holdAtY : (pet.spot ? pet.spot.y : habitat.y + pet.y)
            z: pet.held ? 10 : 0
            transform: Translate { y: root.duckOffset(pet.key, win.height - body.y + 4) }

            Canvas {
              id: canvas
              width: root.spriteW
              height: root.spriteH
              renderStrategy: Canvas.Cooperative
              onPaint: Bots.draw(root.petLook, getContext("2d"), width, height, root.petState(pet))
            }

            // Its name on a plate under its feet, so you can tell them
            // apart without hovering. The edge says who is waiting on you.
            Rectangle {
              id: plate
              // Room on the first line for the SSH tag, which sits in front
              // of the name and wraps with it. Set while the name is laid out.
              readonly property int lead: pet.machine !== "" ? sshTag.width + Math.round(3 * root.k) : 0
              property real tagX: 0
              property real tagY: 0
              visible: !pet.held
              y: root.spriteH + Math.round(1 * root.k)
              height: Math.max(root.plateH, Math.ceil(plateLabel.implicitHeight) + Math.round(3 * root.k))
              onHeightChanged: root.notePlate(pet.key, height)
              Component.onCompleted: root.notePlate(pet.key, height)
              // Centred under the pet, however wide: pets stand a box apart,
              // so plates never meet. Only the edge of the screen moves it.
              width: Math.min(plate.lead + Math.ceil(plateMetrics.advanceWidth) + Math.round(8 * root.k), root.spriteW - Math.round(4 * root.k))
              x: Math.max(-body.x, Math.min(win.width - body.x - width, Math.round(root.holdX - width / 2)))
              radius: Math.round(3 * root.k)
              color: Qt.rgba(0.043, 0.043, 0.063, 0.86)
              border.width: 1
              border.color: pet.status === "blocked" ? Bots.RED
                          : pet.status === "done" ? Bots.GOLD
                          : Qt.rgba(1, 1, 1, 0.16)

              TextMetrics {
                id: plateMetrics
                font: plateLabel.font
                text: pet.name
              }

              Text {
                id: plateLabel
                anchors.centerIn: parent
                width: parent.width - Math.round(8 * root.k)
                horizontalAlignment: Text.AlignHCenter
                text: pet.name
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                lineHeight: 0.92
                color: Bots.SNOOZE
                font.family: Style.font.family
                font.pixelSize: Math.round(9 * root.k)
                font.weight: Font.Medium

                // The first line gives up room for the tag, and the two are
                // centred together.
                onLineLaidOut: function(line) {
                  if (line.number !== 0 || plate.lead === 0) return
                  line.width = width - plate.lead
                  line.x = plate.lead
                  plate.tagX = (width - plate.lead - line.implicitWidth) / 2
                  plate.tagY = line.y + line.height / 2
                }
              }

              SshTag {
                id: sshTag
                visible: pet.machine !== ""
                size: 9 * root.k
                x: Math.round(plateLabel.x + plate.tagX)
                y: Math.round(plateLabel.y + plate.tagY - height / 2)
              }
            }

            MouseArea {
              id: grab
              anchors.fill: parent
              hoverEnabled: true
              preventStealing: true
              cursorShape: pet.held ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              property real pressX: 0
              property real pressY: 0
              property bool moved: false

              onEntered: if (!root.dragging) root.hovered = { item: body, src: pet, name: pet.name, line: "" }
              onExited: if (root.hovered && root.hovered.item === body) root.hovered = null
              onPressed: function(mouse) { grab.pressX = mouse.x; grab.pressY = mouse.y; grab.moved = false; root.pressing = true }
              onPositionChanged: function(mouse) {
                if (!grab.pressed) return
                if (!grab.moved && Math.abs(mouse.x - grab.pressX) + Math.abs(mouse.y - grab.pressY) < 5) return
                var g = grab.mapToItem(null, mouse.x, mouse.y)
                if (!grab.moved) {
                  grab.moved = true
                  pet.held = true
                  root.dragging = true
                  root.hovered = null
                }
                pet.holdAtX = g.x - root.holdX
                pet.holdAtY = g.y - root.holdY
              }
              onReleased: function(mouse) {
                root.pressing = false
                if (!grab.moved) { root.attend(pet.session, pet.pane, pet.key, pet.machine); return }
                var g = grab.mapToItem(null, mouse.x, mouse.y)
                root.drop(pet, g.x, g.y)
              }
              onCanceled: {
                root.pressing = false
                if (pet.held) root.drop(pet, pet.holdAtX + root.holdX, pet.holdAtY + root.holdY)
              }
            }
          }
        }
      }
    }

    // Where the pets are drawn, over the whole output.
    Item {
      id: stage
      anchors.fill: parent

      // A sleeper on its way out of the pile.
      Canvas {
        id: carried
        visible: root.carry !== null
        x: root.carryX - root.holdX
        y: root.carryY - root.holdY
        z: 20
        width: root.spriteW
        height: root.spriteH
        renderStrategy: Canvas.Cooperative
        onPaint: {
          if (root.carry === null) return
          Bots.draw(root.petLook, getContext("2d"), width, height, {
            kind: root.carry.kind, accent: String(Commons.Color.accent),
            t: root.clock / 1000, pose: "hang", face: "whee"
          })
        }
        Connections {
          target: root
          function onClockChanged() { if (carried.visible) carried.requestPaint() }
        }
      }
    }

    // Everyone asleep, in a list that opens above the pile. A click on a
    // name goes to that agent; a drag takes it out of the pile.
    Rectangle {
      id: sleepList
      visible: root.pileOpen && pile.visible && root.sleepers.length > 0
      // Out of the way while one of its sleepers is carried off, but not
      // gone: the row being dragged holds the press.
      opacity: root.carry !== null ? 0 : 1
      readonly property real pileX: habitat.x + pile.x
      width: Style.space(300)
      height: Math.min(header.height + list.contentHeight + Style.space(12), win.height * 0.6)
      x: Math.max(Style.space(8), Math.min(win.width - width - Style.space(8),
                  root.leftSide ? pileX : pileX + pile.width - width))
      y: habitat.y - height - Style.space(6)
      radius: Style.space(6)
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1

      HoverHandler {
        id: listHover
        onHoveredChanged: hovered ? foldTimer.stop() : foldTimer.restart()
      }

      Text {
        id: header
        x: Style.space(12)
        y: Style.space(8)
        width: parent.width - Style.space(24)
        height: implicitHeight + Style.space(4)
        text: root.sleepers.length + " asleep"
        textFormat: Text.PlainText
        color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.65)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        anchors.right: header.right
        y: header.y
        text: "H hides them for a minute"
        textFormat: Text.PlainText
        color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      ListView {
        id: list
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(6)
        x: Style.space(4)
        width: parent.width - Style.space(8)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sleepList.visible ? root.sleepersByRecent : []

        delegate: Rectangle {
          id: row
          required property var modelData
          width: ListView.view.width
          height: Style.space(36)
          radius: Style.space(4)
          color: rowMouse.containsMouse
                 ? Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.09)
                 : "transparent"

          // The pet itself, asleep, cut out of its sprite box.
          readonly property real s: Style.space(24) / 40
          Item {
            id: face
            x: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(38 * row.s)
            height: Math.ceil(40 * row.s)
            clip: true
            Canvas {
              x: -Bots.sleepCrop(root.petLook).x * row.s
              y: -Bots.sleepCrop(root.petLook).y * row.s
              width: Math.ceil(Bots.W * row.s)
              height: Math.ceil(Bots.H * row.s)
              onPaint: Bots.draw(root.petLook, getContext("2d"), width, height, {
                kind: row.modelData.kind, accent: String(Commons.Color.accent),
                t: 0, face: "sleep", pose: "sit"
              })
            }
          }

          Column {
            anchors.left: face.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Item {
              width: parent.width
              height: rowName.implicitHeight

              SshTag {
                id: rowTag
                visible: row.modelData.machine !== ""
                size: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: rowName
                x: rowTag.visible ? rowTag.width + Style.space(5) : 0
                width: parent.width - x
                text: row.modelData.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Commons.Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
            Text {
              width: parent.width
              text: {
                void root.clock
                var parts = []
                if (row.modelData.workspace) parts.push(row.modelData.workspace)
                parts.push(root.statusLine("idle", row.modelData.since))
                return parts.join(" · ")
              }
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.65)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: root.carry !== null ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            property real pressX: 0
            property real pressY: 0
            onPressed: function(mouse) { rowMouse.pressX = mouse.x; rowMouse.pressY = mouse.y; root.pressing = true }
            onPositionChanged: function(mouse) { root.dragSleeper(rowMouse, mouse, rowMouse.pressX, rowMouse.pressY, row.modelData) }
            onReleased: function(mouse) {
              root.releaseSleeper(rowMouse, mouse, function() {
                root.attend(row.modelData.session, row.modelData.pane, "", row.modelData.machine)
                root.pileOpen = false
              })
            }
            onCanceled: root.putSleeper(root.carryX, root.carryY)
          }
        }
      }
    }

    // The name bubble, above whichever pet the pointer is on.
    Rectangle {
      id: bubble
      visible: root.duck === "" && !root.dragging && root.hovered !== null && root.hovered.item !== null && root.hovered.item.visible
      readonly property var target: root.hovered ? root.hovered.item : null
      readonly property point anchorPoint: {
        void root.clock
        if (!target) return Qt.point(0, 0)
        return target.mapToItem(null, Math.min(target.width, root.spriteW * 0.42), 0)
      }
      readonly property string detail: {
        void root.clock
        if (!root.hovered) return ""
        if (root.hovered.line !== "") return root.hovered.line
        var src = root.hovered.src
        if (!src) return ""
        var parts = []
        if (src.workspace) parts.push(src.workspace)
        parts.push(root.statusLine(src.status, src.since))
        return parts.join(" · ")
      }

      width: Math.min(Style.space(360), Math.max(titleText.implicitWidth, detailText.implicitWidth) + Style.space(20))
      height: column.implicitHeight + Style.space(14)
      x: Math.max(Style.space(8), Math.min(win.width - width - Style.space(8), anchorPoint.x - width / 2))
      y: Math.max(Style.space(8), anchorPoint.y + 14 * root.k - height)
      radius: Style.space(6)
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 1

      Column {
        id: column
        anchors.centerIn: parent
        width: parent.width - Style.space(20)
        spacing: Style.space(2)

        Text {
          id: titleText
          width: parent.width
          text: root.hovered ? root.hovered.name : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          id: detailText
          width: parent.width
          text: bubble.detail
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.65)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
