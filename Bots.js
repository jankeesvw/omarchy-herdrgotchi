.pragma library

// Herdr Bots, drawn as vectors: a plain shaded cube that says everything
// with how it moves. Smooth shapes rather than pixels, so a pet the size of a
// bar icon still reads.
//
// Everything is drawn in a fixed box of W x H units with the ground at
// GROUND, and scaled to the size it is shown at. One state object says what
// the pet is doing this moment (see draw() at the bottom), and `t` in it is
// the pet's own clock in seconds, so no two pets move in step.

var W = 84
var H = 64
var GROUND = 62

var OUTLINE = "#0B0B10"
var RED = "#FF4D4D"
var GOLD = "#FFCF3F"
var PINK = "#FF6FA5"
var TEAR = "#5EC4FF"
var SNOOZE = "#EEF0F6"
var WOOD = "#B07A45"
var HOLD = "#E76F51"

// Fixed colours, so a pet reads the same on every theme and over every
// window.
var KINDS = {
  claude:   { body: "#D97757" },
  codex:    { body: "#EDEDED" },
  gemini:   { body: "#7B96F5" },
  grok:     { body: "#A3A7AD" },
  opencode: { body: "#E9C46A" },
  pi:       { body: "#7BC6A4" }
}

function kindStyle(kind, fallback) {
  return KINDS[String(kind || "")] || { body: String(fallback || "#9AA5CE") }
}

// ------------------------------------------------------------- helpers

function rrect(ctx, x, y, w, h, r) {
  r = Math.max(0, Math.min(r, w / 2, h / 2))
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.lineTo(x + w - r, y)
  ctx.arcTo(x + w, y, x + w, y + r, r)
  ctx.lineTo(x + w, y + h - r)
  ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
  ctx.lineTo(x + r, y + h)
  ctx.arcTo(x, y + h, x, y + h - r, r)
  ctx.lineTo(x, y + r)
  ctx.arcTo(x, y, x + r, y, r)
  ctx.closePath()
}

// Fill with a dark outline under it, the one thing that keeps a light pet
// visible on a white page.
function fillOutlined(ctx, color, line) {
  ctx.lineJoin = "round"
  ctx.strokeStyle = OUTLINE
  ctx.lineWidth = line || 2.4
  ctx.stroke()
  ctx.fillStyle = color
  ctx.fill()
}

// A limb: a round-capped line with an outline.
function limb(ctx, x1, y1, x2, y2, color, width) {
  width = width || 3.2
  ctx.lineCap = "round"
  ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2)
  ctx.strokeStyle = OUTLINE; ctx.lineWidth = width + 2.2; ctx.stroke()
  ctx.strokeStyle = color; ctx.lineWidth = width; ctx.stroke()
}

// An ellipse by its centre and radii. Not ctx.ellipse(): Qt's canvas takes
// a bounding box there where a browser takes a centre, and this file is
// drawn by both.
function oval(ctx, cx, cy, rx, ry) {
  ctx.save()
  ctx.translate(cx, cy)
  ctx.scale(Math.max(0.01, rx), Math.max(0.01, ry))
  ctx.beginPath()
  ctx.arc(0, 0, 1, 0, Math.PI * 2)
  ctx.restore()
}

function heartPath(ctx, x, y, s) {
  ctx.beginPath()
  ctx.moveTo(x, y + s * 0.35)
  ctx.bezierCurveTo(x, y, x - s * 0.5, y, x - s * 0.5, y + s * 0.3)
  ctx.bezierCurveTo(x - s * 0.5, y + s * 0.6, x, y + s * 0.8, x, y + s)
  ctx.bezierCurveTo(x, y + s * 0.8, x + s * 0.5, y + s * 0.6, x + s * 0.5, y + s * 0.3)
  ctx.bezierCurveTo(x + s * 0.5, y, x, y, x, y + s * 0.35)
  ctx.closePath()
}

function starPath(ctx, x, y, r) {
  ctx.beginPath()
  for (var i = 0; i < 8; i++) {
    var a = i * Math.PI / 4 - Math.PI / 2
    var rr = i % 2 === 0 ? r : r * 0.36
    ctx.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr)
  }
  ctx.closePath()
}

function wave(t, period) { return Math.sin(t * Math.PI * 2 / period) }

// -------------------------------------------------------------- emotes

function drawEmote(ctx, s, cx, top) {
  var t = s.t || 0
  ctx.lineJoin = "round"
  switch (s.emote) {
  case "bang":
  case "bangbang":
    var marks = s.emote === "bangbang" ? [-4, 4] : [0]
    for (var i = 0; i < marks.length; i++) {
      var bob = wave(t + i * 0.2, 0.8) * 1.2
      var x = cx + marks[i], y = top - 14 + bob
      rrect(ctx, x - 1.8, y, 3.6, 8, 1.8); fillOutlined(ctx, RED, 2)
      ctx.beginPath(); ctx.arc(x, y + 11, 1.9, 0, Math.PI * 2); fillOutlined(ctx, RED, 2)
    }
    break
  case "alarm":
    ctx.font = "bold 13px sans-serif"
    ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"
    ctx.lineWidth = 3; ctx.strokeStyle = OUTLINE; ctx.strokeText("?!", cx, top - 2)
    ctx.fillStyle = RED; ctx.fillText("?!", cx, top - 2)
    break
  case "heart":
    var hs = 8 + wave(t, 0.6) * 0.8
    heartPath(ctx, cx, top - 12 - wave(t, 1.2), hs); fillOutlined(ctx, PINK, 2)
    break
  case "sparkle":
    var tw = 0.75 + 0.25 * wave(t, 0.9)
    starPath(ctx, cx + 9, top - 8, 4.5 * tw); fillOutlined(ctx, GOLD, 1.8)
    starPath(ctx, cx - 10, top - 2, 3 * (1.75 - tw)); fillOutlined(ctx, GOLD, 1.6)
    break
  case "snooze":
    ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"
    for (var z = 0; z < 2; z++) {
      var p = ((t * 0.45) + z * 0.5) % 1
      ctx.globalAlpha = p < 0.8 ? 1 : (1 - p) * 5
      ctx.font = "bold " + (6 + z * 3 + p * 2) + "px sans-serif"
      var zx = cx + 5 + p * 8 + z * 2, zy = top - 1 - p * 12
      ctx.lineWidth = 2.4; ctx.strokeStyle = OUTLINE; ctx.strokeText("z", zx, zy)
      ctx.fillStyle = SNOOZE; ctx.fillText("z", zx, zy)
    }
    ctx.globalAlpha = 1
    break
  case "confetti":
    var b = Math.min(1, (s.burst || 0))
    var colors = [GOLD, PINK, TEAR, "#7CE38B", "#B48CFF", GOLD, TEAR, PINK, "#7CE38B", "#B48CFF"]
    for (var k = 0; k < 10; k++) {
      var a = k * Math.PI * 2 / 10 + 0.4
      var r = 4 + b * 22
      var px = cx + Math.cos(a) * r * 1.2, py = top - 6 + Math.sin(a) * r * 0.8 + b * b * 10
      ctx.save()
      ctx.globalAlpha = 1 - Math.max(0, b - 0.6) * 2.5
      ctx.translate(px, py); ctx.rotate(a + b * 6)
      ctx.fillStyle = colors[k]; ctx.fillRect(-1.6, -1, 3.2, 2)
      ctx.restore()
    }
    break
  }
}

// --------------------------------------------------------------- cubes

// A solid block, drawn in 3D and shaded, with no face. It says what it is doing by how it moves: it builds a little stack, fills its
// sides with text and turns to the next, rocks and flashes red when it needs
// you, hops and spins when it is proud, and sags when it sleeps.
var CUBE = 10                 // half an edge, in units
var CUBE_X = 23               // where its middle stands
var YAW = -0.52               // turned a little, so the front is the wide side
var TILT = 0.42               // and seen from a little above
var BLOCK = 3.2               // half an edge of the blocks it builds with

var CORNERS = [[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
               [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]]
var SIDES = [
  { v: [4, 5, 6, 7], n: [0, 0, 1] },    // front
  { v: [5, 1, 2, 6], n: [1, 0, 0] },    // right
  { v: [1, 0, 3, 2], n: [0, 0, -1] },
  { v: [0, 4, 7, 3], n: [-1, 0, 0] },
  { v: [7, 6, 2, 3], n: [0, 1, 0] },    // top
  { v: [0, 1, 5, 4], n: [0, -1, 0] }
]
var LIGHT = [-0.33, 0.8, 0.5]

function hexRgb(color) {
  var c = String(color || "").replace("#", "")
  if (c.length === 8) c = c.slice(2)
  var n = parseInt(c, 16)
  if (c.length !== 6 || isNaN(n)) return [154, 165, 206]
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

// Darker below 1, toward white above it, and greyed out by `grey`.
function shade(rgb, b, grey) {
  var l = (rgb[0] * 0.3 + rgb[1] * 0.59 + rgb[2] * 0.11)
  var out = []
  for (var i = 0; i < 3; i++) {
    var c = rgb[i] + (l - rgb[i]) * (grey || 0)
    c = b <= 1 ? c * b : c + (255 - c) * (b - 1)
    out.push(Math.round(Math.max(0, Math.min(255, c))))
  }
  return "rgb(" + out[0] + "," + out[1] + "," + out[2] + ")"
}

function easeOutBack(x) { var c = 1.9; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2) }
function easeInOut(x) { return x < 0.5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2 }

// How a block sits this moment: squashed, rolled over an edge, flipped,
// turned, lifted. Points go in as corners of a -1..1 cube.
function cubeTransform(m) {
  var sy = m.squash || 1, sxz = 1 / Math.sqrt(sy)
  var cr = Math.cos(m.roll || 0), sr = Math.sin(m.roll || 0)
  var px = m.pivot || 0, py = m.pivot ? -1 : 0
  var cf = Math.cos(m.flip || 0), sf = Math.sin(m.flip || 0)
  var ya = YAW + (m.spin || 0), cy = Math.cos(ya), sy2 = Math.sin(ya)
  var ce = Math.cos(TILT), se = Math.sin(TILT)
  return function(p, isNormal) {
    var x = p[0], y = p[1], z = p[2]
    var ox = isNormal ? 0 : px, oy = isNormal ? 0 : py
    if (!isNormal) { y = (y + 1) * sy - 1; x *= sxz; z *= sxz }
    x -= ox; y -= oy
    var x1 = x * cr - y * sr, y1 = x * sr + y * cr
    x = x1 + ox; y = y1 + oy
    var y2 = y * cf - z * sf, z2 = y * sf + z * cf
    var x3 = x * cy + z2 * sy2, z3 = -x * sy2 + z2 * cy
    return [x3, y2 * ce - z3 * se, y2 * se + z3 * ce]
  }
}

// The lowest a resting cube reaches on screen, so its foot is on the ground.
var CUBE_LOW = (function() {
  var tf = cubeTransform({}), low = 0
  for (var i = 0; i < CORNERS.length; i++) low = Math.min(low, tf(CORNERS[i])[1])
  return low
})()

// Draws one block and hands back how to find a point on it.
// m: { squash, roll, pivot (-1, 0 or 1: the edge it rolls over), flip, spin,
//      lift, hangY (top corner pinned there) }
function drawBlock(ctx, m, rgb, size, cx, ground, look) {
  look = look || {}
  var tf = cubeTransform(m)
  var lift = m.lift || 0
  function toScreen(q) { return [cx + q[0] * size, ground - (q[1] - CUBE_LOW) * size - lift] }
  var pts = [], top = 1e9
  for (var i = 0; i < CORNERS.length; i++) {
    pts.push(toScreen(tf(CORNERS[i])))
    top = Math.min(top, pts[i][1])
  }
  var shiftY = m.hangY !== undefined ? m.hangY - top : 0
  if (shiftY) { for (i = 0; i < pts.length; i++) pts[i][1] += shiftY; top += shiftY }

  var seen = []
  for (i = 0; i < SIDES.length; i++) {
    var n = tf(SIDES[i].n, true)
    if (n[2] > 0.02) seen.push({ side: SIDES[i], index: i, light: n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2] })
  }
  function path(side) {
    ctx.beginPath()
    for (var k = 0; k < 4; k++) {
      var q = pts[side.v[k]]
      if (k === 0) ctx.moveTo(q[0], q[1]); else ctx.lineTo(q[0], q[1])
    }
    ctx.closePath()
  }
  ctx.lineJoin = "round"
  if (look.glow) {
    for (i = 0; i < seen.length; i++) { path(seen[i].side); ctx.strokeStyle = look.glow; ctx.lineWidth = look.glowWidth || 6; ctx.stroke() }
  }
  for (i = 0; i < seen.length; i++) { path(seen[i].side); ctx.strokeStyle = look.ink || OUTLINE; ctx.lineWidth = look.line || 2.6; ctx.stroke() }
  for (i = 0; i < seen.length; i++) {
    path(seen[i].side)
    ctx.fillStyle = shade(rgb, (0.6 + 0.5 * Math.max(0, seen[i].light)) * (look.dim || 1), look.grey)
    ctx.fill()
  }
  for (i = 0; i < seen.length; i++) {
    path(seen[i].side); ctx.strokeStyle = "rgba(0,0,0,0.22)"; ctx.lineWidth = 0.7; ctx.stroke()
  }
  return {
    top: top,
    seen: function(index) { for (var j = 0; j < seen.length; j++) if (seen[j].index === index) return true; return false },
    at: function(p) { var q = toScreen(tf(p)); q[1] += shiftY; return q }
  }
}

// A flat shadow the shape of the block's foot, smaller as it goes up.
function blockShadow(ctx, m, size, cx, ground) {
  var tf = cubeTransform({ spin: m.spin })
  var lift = m.lift || 0
  var k = Math.max(0.4, 1 - lift * 0.035)
  ctx.beginPath()
  var foot = [0, 1, 5, 4]
  for (var i = 0; i < 4; i++) {
    var q = tf(CORNERS[foot[i]])
    var x = cx + q[0] * size * k, y = ground - (q[1] - CUBE_LOW) * size * k + 0.6
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
  }
  ctx.closePath()
  ctx.fillStyle = "rgba(0,0,0," + (0.24 * k) + ")"
  ctx.fill()
}

// Lines of text on the front, typed a key at a time, `done` 0..1 of the way.
function typeOnFront(ctx, block, done, t) {
  var lines = [1.0, 0.7, 1.25, 0.5, 0.95]
  var total = 0
  for (var i = 0; i < lines.length; i++) total += lines[i]
  var typed = done * total
  ctx.fillStyle = "rgba(11,11,16,0.72)"
  function quad(u0, u1, v, h) {
    var a = block.at([u0, v - h, 1]), b = block.at([u1, v - h, 1])
    var c = block.at([u1, v + h, 1]), d = block.at([u0, v + h, 1])
    ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.lineTo(c[0], c[1]); ctx.lineTo(d[0], d[1]); ctx.closePath(); ctx.fill()
  }
  for (i = 0; i < lines.length; i++) {
    var len = Math.max(0, Math.min(lines[i], typed))
    typed -= lines[i]
    var u0 = -0.72 + (i % 2) * 0.2, v = 0.58 - i * 0.29
    if (len > 0) quad(u0, u0 + len, v, 0.065)
    if (typed < 0) {
      if (Math.floor(t * 3) % 2 === 0) quad(u0 + len + 0.04, u0 + len + 0.13, v, 0.1)
      break
    }
  }
}

// Building: a crouch, a hop, a thump, and a new block on the stack beside
// it. At four the stack goes poof and it starts over.
function builderMotion(s, m) {
  var t = (s.t || 0) * 0.9
  var c = Math.floor(t), p = t - c
  var stack = { count: c % 4, pop: -1, poof: -1 }
  if (s.look === 0) { stack.count = c % 4; return stack }    // a breather
  if (p < 0.15) m.squash = 1 - 0.15 * Math.sin(p / 0.15 * Math.PI / 2)
  else if (p < 0.55) {
    var q = (p - 0.15) / 0.4
    m.lift = 6 * Math.sin(Math.PI * q)
    m.squash = 0.85 + 0.27 * Math.sin(Math.PI * q)
    m.roll = -0.14 * Math.sin(Math.PI * q); m.pivot = 0
  }
  else if (p < 0.72) m.squash = 0.85 + 0.15 * (p - 0.55) / 0.17
  if (p >= 0.55) { stack.count += 1; stack.pop = (p - 0.55) / 0.15 }
  if (c % 4 === 0 && c > 0 && p < 0.3) stack.poof = p / 0.3
  stack.dust = p >= 0.55 && p < 0.85 ? (p - 0.55) / 0.3 : -1
  return stack
}

function drawStack(ctx, stack, rgb) {
  var x = CUBE_X + 27
  var rise = 2 * BLOCK * Math.cos(TILT)
  if (stack.poof >= 0) {
    ctx.globalAlpha = 1 - stack.poof
    for (var j = 0; j < 4; j++)
      drawBlock(ctx, { spin: j % 2 ? 0.16 : -0.1, squash: 1 }, rgb, BLOCK * (1 - stack.poof * 0.6), x, GROUND - j * rise * (1 - stack.poof * 0.6))
    ctx.globalAlpha = 1
    ctx.fillStyle = "rgba(235,238,245," + (0.7 * (1 - stack.poof)) + ")"
    for (j = 0; j < 5; j++) {
      var a = j * 1.3, r = 4 + stack.poof * 9
      ctx.beginPath(); ctx.arc(x + Math.cos(a) * r, GROUND - 10 + Math.sin(a) * r * 0.7, 2.4 * (1 - stack.poof * 0.5), 0, Math.PI * 2); ctx.fill()
    }
    return
  }
  for (var i = 0; i < stack.count; i++) {
    var newest = i === stack.count - 1 && stack.pop >= 0 && stack.pop < 1
    var k = newest ? Math.min(1.15, easeOutBack(Math.min(1, stack.pop))) : 1
    var drop = newest ? (1 - Math.min(1, stack.pop * 1.4)) * 5 : 0
    drawBlock(ctx, { spin: i % 2 ? 0.16 : -0.1, lift: drop }, rgb, BLOCK * k, x, GROUND - i * rise)
  }
}

function dustPuffs(ctx, d, cx) {
  if (d < 0) return
  ctx.fillStyle = "rgba(235,238,245," + (0.75 * (1 - d)) + ")"
  for (var side = -1; side <= 1; side += 2) {
    ctx.beginPath(); ctx.arc(cx + side * (12 + d * 7), GROUND - 1.5 - d * 2, 1.6 + d * 1.6, 0, Math.PI * 2); ctx.fill()
  }
}

// Typing: it fills its front with text, and when the side is full it gives
// itself a quarter turn, with a little hop, to a clean one.
function typistMotion(s, m) {
  var period = 4.4
  var t = s.t || 0
  var f = t % period
  var typing = period - 0.95
  var turnAt = period - 0.55
  if (f > turnAt && s.look !== 0) {
    var q = (f - turnAt) / 0.55
    m.spin = -Math.PI / 2 * easeOutBack(q)
    m.lift = 2.2 * Math.sin(Math.PI * Math.min(1, q * 1.4))
    return 1
  }
  return Math.min(1, f / typing)
}

// s: { kind, accent, t (seconds, the pet's own clock),
//      pose: stand|hop|leap|sit|chair|hang, face, look, tears, shake,
//      arms: down|wave|up|cheer|tool, emote, burst (0..1), tool,
//      lift (0..1, how far through a hop) }
function draw(ctx, width, height, s) {
  ctx.clearRect(0, 0, width, height)
  ctx.save()
  ctx.scale(width / W, height / H)

  var style = kindStyle(s.kind, s.accent)
  var rgb = hexRgb(style.body)
  var t = s.t || 0
  var m = { squash: 1, roll: 0, pivot: 0, flip: 0, spin: 0, lift: 0 }
  var look = {}
  var lift = s.lift || 0
  var stack = null, typed = -1

  if (s.pose === "hang") {
    // Picked up: hanging by a corner on a cord from a climbing hold, well
    // under the pointer so the hand does not hide it, turning slowly.
    var hy = 5, cord = 25
    ctx.save()
    ctx.translate(CUBE_X, hy)
    ctx.rotate(wave(t, 1.4) * 0.14)
    ctx.translate(-CUBE_X, -hy)
    limb(ctx, CUBE_X, hy, CUBE_X, hy + cord + 1, WOOD, 1.2)
    oval(ctx, CUBE_X, hy, 7, 4); fillOutlined(ctx, HOLD, 2)
    m.roll = Math.PI / 4; m.flip = -0.6155; m.spin = t * 1.6; m.hangY = hy + cord
    drawBlock(ctx, m, rgb, CUBE * 0.92, CUBE_X, GROUND)
    ctx.restore()
    ctx.restore()
    return
  }

  switch (s.pose) {
  case "hop":
  case "leap":
    var high = s.pose === "leap" ? 13 : 5
    m.lift = high * Math.sin(Math.PI * lift)
    m.squash = lift < 0.12 || lift > 0.88 ? 0.86 : 1 + (s.pose === "leap" ? 0.14 : 0.08) * Math.sin(Math.PI * lift)
    if (s.face === "happy" && s.pose === "leap") m.spin = -Math.PI * 2 * easeInOut(lift)
    else if (s.face === "happy") m.spin = -Math.PI / 2 * easeInOut(lift)
    else if (s.face === "love") { m.roll = 0.16 * Math.sin(Math.PI * 2 * lift) }
    break
  case "sit":
    if (s.face === "sleep") { m.squash = 0.8 + 0.025 * wave(t, 3.4); look.dim = 0.78; look.grey = 0.35 }
    else if (s.arms === "up") m.squash = 1.14
    else if (s.face === "bored") { m.squash = 0.92; m.roll = 0.2; m.pivot = -1; look.dim = 0.88; look.grey = 0.2 }
    else m.squash = 0.8
    break
  case "chair":
    // Waiting for you: rocking from edge to edge, now and then jumping.
    var rock = wave(t, 1.1) * (s.shake ? 0.22 : 0.12)
    m.roll = rock; m.pivot = rock > 0 ? -1 : 1
    if (s.arms === "wave") {
      var w = (t % 6) / 1.6
      m.lift = 4.5 * Math.abs(Math.sin(Math.PI * 2 * w)); m.roll = 0
      m.squash = m.lift < 0.6 ? 0.88 : 1.06
    }
    break
  }
  if (s.face === "worried") {
    var pulse = 0.5 + 0.5 * wave(t, s.tears ? 0.6 : 1.1)
    look.ink = "rgb(" + Math.round(11 + 244 * pulse) + "," + Math.round(11 + 66 * pulse) + "," + Math.round(16 + 61 * pulse) + ")"
    look.glow = "rgba(255,77,77," + (0.18 + 0.3 * pulse) + ")"
  }
  if (s.pose === "stand" && s.tool === "hammer") stack = builderMotion(s, m)
  else if (s.pose === "stand" && s.tool === "terminal") typed = typistMotion(s, m)
  if (s.shake) m.roll += wave(t, 0.12) * 0.03

  blockShadow(ctx, m, CUBE, CUBE_X, GROUND)
  if (stack) drawStack(ctx, stack, rgb)
  var block = drawBlock(ctx, m, rgb, CUBE, CUBE_X, GROUND, look)
  if (typed >= 0 && block.seen(0)) typeOnFront(ctx, block, typed, t)
  if (stack) dustPuffs(ctx, stack.dust, CUBE_X)

  drawEmote(ctx, s, CUBE_X, block.top - 1)
  ctx.restore()
}

// Where a sleeping pet sits in its box, to cut it out for the list.
var SLEEP_CROP = { x: 4, y: 30 }
