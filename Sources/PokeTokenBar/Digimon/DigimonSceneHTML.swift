/// The animated pet scene, shared by the popover and the desktop pet (WKWebView + canvas).
/// Ported from the DigiTokenTest prototype. No artwork lives here: the app sends each sprite as a
/// data URI after downloading it from Wikimon (`DigimonSceneHub`). Bugs, attacks, coins and
/// particles are simple shapes drawn in code.
///
/// Messages to the app (`window.webkit.messageHandlers.app`):
///   {cmd: 'ready'} · {cmd: 'bugDefeated'} · {cmd: 'petRect', x, y, w, h} (desk only)
/// Calls from the app: app.sprite(key, uri) · app.apply({key, line, stage, sleeping, lang}) · app.cmd({type, ...})
enum DigimonSceneHTML {
    static let page = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
:root{--scene-top:#e8f0fb;--scene-bot:#f8f4ea;--ground:#ebe3cf}
@media (prefers-color-scheme: dark){:root{--scene-top:#1f2735;--scene-bot:#26272c;--ground:#2f3035}}
*{box-sizing:border-box}
html,body{margin:0;height:100%;overflow:hidden;background:transparent;-webkit-user-select:none;user-select:none;cursor:default}
body.popover{background:linear-gradient(to bottom,var(--scene-top),var(--scene-bot) 80%,var(--ground) 80%,var(--ground))}
canvas{position:fixed;inset:0;display:block}
</style>
</head>
<body>
<canvas id="cv"></canvas>
<script>
const VIEW = window.SCENE_MODE === 'desk' ? 'desk' : 'popover';
document.body.classList.add(VIEW);
const DPR = Math.max(1, Math.round(window.devicePixelRatio || 1));
const rand = (a, b) => a + Math.random() * (b - a);
const easeIO = p => -(Math.cos(Math.PI * p) - 1) / 2;
const TAU = Math.PI * 2;
const mq = window.matchMedia('(prefers-color-scheme: dark)');
const isDark = () => mq.matches;
const assets = {};
const waiting = {};
let COIN = null;
let S = {key: null, line: 'agumon', stage: 0, sleeping: false, lang: 'ko', mood: null};
// Mood from the app: 'sleepy' in the small hours, 'sick' while a usage limit is full.
const moodSlow = () => S.mood === 'sick' ? .45 : S.mood === 'sleepy' ? .55 : 1;

// Move names: Korean from the official Korean Digimon reference (digimon.net/reference_ko; Agumon
// keeps 꼬마 불꽃 from its reference text and the Korean dub), English from the Japanese originals
// (digimon.net/reference_en, or Wikimon where reference_en uses a dub name). Checked 2026-11-10.
// The kind picks one of the drawn attack shapes; an optional tint gives the move its own colors. Species without an entry use a plain attack.
const MOVES = {
\#(DigimonMovesData.js)
};
const moveOf = key => {
  const m = MOVES[key];
  if (m) return {name: S.lang === 'ko' ? m.ko : m.en, kind: m.kind, tint: m.tint};
  return {name: S.lang === 'ko' ? '공격' : 'Attack', kind: 'fire'};
};
// Colors per attack shape (center -> outside)
const PAL = {
  fire_agumon: ['#fff6c2', '#ffb53b', '#e8461e'], fire_gabumon: ['#eaffff', '#79d6ff', '#2a6fe0'],
  fire_piyomon: ['#fff1f6', '#ff8fb8', '#e0457a'], fire_tentomon: ['#ffffe0', '#f4f05a', '#7cc23a'],
  fire_vmon: ['#f2efff', '#a597ff', '#5b45d6'], fire_guilmon: ['#fff2d6', '#ff7a3d', '#c92a1a'],
  missile: ['#fff3c4', '#ffb53b', '#e0452c'],
  gaia: ['#fff3c4', '#ff8a2a', '#c92a1a'],
  claw: ['#ffffff', '#c9f1ff', '#6fb7ff'],
  ice: ['#ffffff', '#c7f3ff', '#59b4ff'],
  bind: ['#f6e9ff', '#b685e8', '#5e3a8f'],
  melee: ['#ffffff', '#ffe28a', '#f2a03a'],
  beam: ['#ffffff', '#a8ecff', '#3a9ee8'],
  electric: ['#ffffff', '#fff27a', '#f0b400'],
  gas: ['#f3e6ff', '#b58ad8', '#6c4a8f'],
  wave: ['#ffffff', '#c9f0ff', '#5fb8e6'],
  wind: ['#ffffff', '#bfe9dc', '#4f9c84'],
  water: ['#ffffff', '#9fdcff', '#2f86d6'],
  light: ['#ffffff', '#fff3b0', '#f2c94c'],
  swarm: ['#9a8fb0', '#4d4560', '#1f1a2b'],
  heart: ['#ffffff', '#ff9fc8', '#e0457a'],
  quake: ['#f4e2c0', '#b08a5a', '#6b4f30'],
  // Tints: a move's own colors for a shape (smoke is gray, pollen yellow, fox spirits gold ...).
  tint_smoke: ['#ffffff', '#d6d9de', '#8a8f98'],
  tint_dark: ['#9a8fb0', '#4d4560', '#1f1a2b'],
  tint_pollen: ['#fffbe0', '#f6e27a', '#d9a93a'],
  tint_heat: ['#fff3e0', '#ffbd80', '#e0743a'],
  tint_psychic: ['#ffffff', '#f0c9ff', '#a45fd6'],
  tint_petal: ['#fff0f6', '#ffc0d8', '#e07aa6'],
  tint_dust: ['#fff8ec', '#e6d3b3', '#b39a73'],
  tint_spirit: ['#ffffff', '#fff1c9', '#e6c36f'],
  tint_metal: ['#ffffff', '#c8ccd4', '#6e7480'],
  tint_leaf: ['#eaffd8', '#9fd36b', '#4e8f3a'],
};
// Fire colors for a line: its own (PAL.fire_<line>), else made from its egg color: a light core, the
// egg color, a darker rim. A dark egg (Gabumon (Black)) is lightened so the fire still glows; a gray or
// dull dark egg (Agumon (Black)'s brown-gray) keeps the usual fire, which would look like smoke.
const firePals = {};
function linePal(line) {
  if (PAL['fire_' + line]) return PAL['fire_' + line];
  if (!line || line !== S.line || !/^[0-9a-fA-F]{6}$/.test(S.lineColor || '')) return null;
  if (firePals[S.lineColor]) return firePals[S.lineColor];
  const rgb = [0, 2, 4].map(i => parseInt(S.lineColor.slice(i, i + 2), 16));
  const lum = (.299 * rgb[0] + .587 * rgb[1] + .114 * rgb[2]) / 255;
  const sat = (Math.max(...rgb) - Math.min(...rgb)) / Math.max(1, Math.max(...rgb));
  if (sat < .2 || (sat < .3 && lum < .4)) return null;   // gray or dull-dark; a bright pastel keeps its color
  const mix = (c, to, k) => c.map(v => Math.round(v + (to - v) * k));
  const mid = lum < .3 ? mix(rgb, 255, .35) : rgb;
  const hex = c => '#' + c.map(v => v.toString(16).padStart(2, '0')).join('');
  return (firePals[S.lineColor] = [hex(mix(mid, 255, .78)), hex(mid), hex(mix(mid, 0, .38))]);
}
const HEART = ['.##.##.', '#######', '#######', '.#####.', '..###..', '...#...'];
// Shapes without muzzle sparks or a generic trail (they draw their own).
const SOFT = ['bind', 'melee', 'gas', 'wave', 'wind', 'water', 'light', 'swarm', 'heart', 'quake'];
// Attacks grow with the stage of whoever makes them: Child (and babies) 1x, Adult 1.3x, Perfect 1.7x,
// Ultimate 2.1x. Gaia Force, already the biggest, grows half as much. Each shape scales its own
// lengths and thicknesses (whole pixels), so it stays crisp instead of a blurred zoom.
const sizeOf = stage => stage <= 3 ? 1 : stage === 4 ? 1.3 : stage === 5 ? 1.7 : 2.1;
const gaiaSize = z => 1 + (z - 1) * .5;
const wpx = (n, z) => Math.max(1, Math.round(n * z));   // n whole pixels at size z
// Heavy hits from a Perfect or an Ultimate shake the scene a little.
const HEAVY = ['fire', 'gaia', 'claw', 'ice', 'melee', 'beam', 'electric'];
// Timing per attack shape: [charge, release, recover] (ms)
const TIMING = {fire: [240, 100, 360], missile: [260, 100, 380], gaia: [560, 120, 420], claw: [200, 120, 380], ice: [260, 160, 380], bind: [240, 140, 420],
                melee: [200, 170, 360], beam: [380, 260, 380], electric: [260, 160, 380],
                gas: [260, 140, 380], wave: [240, 140, 380], wind: [260, 160, 380], water: [260, 180, 380],
                light: [300, 140, 380], swarm: [280, 140, 380], heart: [220, 140, 380], quake: [300, 160, 420]};
// Bug enemy drawn in code (11x8, two leg frames)
const BUG = [[
  "...k...k...",
  "....k.k....",
  "..kkkkkkk..",
  ".kwkpppkwk.",
  ".kppprpppk.",
  ".kpprpprpk.",
  "..kpppppk..",
  ".k.k...k.k."], [
  "...k...k...",
  "....k.k....",
  "..kkkkkkk..",
  ".kwkpppkwk.",
  ".kppprpppk.",
  ".kpprpprpk.",
  "..kpppppk..",
  "k..k...k..k"]];
const BUG_C = {k: '#2a2233', w: '#ffffff', p: '#8e5bd6', r: '#ff5a6a'};

function makeCoin() {
  const c = document.createElement('canvas'); c.width = c.height = 12;
  const x = c.getContext('2d'), im = x.createImageData(12, 12);
  for (let py = 0; py < 12; py++) for (let px = 0; px < 12; px++) {
    const d = Math.hypot(px - 5.5, py - 5.5); if (d > 5.9) continue;
    let col = d > 4.9 ? [107, 67, 0] : d > 3.9 ? [215, 149, 31] : [245, 185, 58];
    if (d <= 3.9 && px + py < 8 && d > 1.5) col = [255, 240, 176];
    if (d <= 3.9 && (px === 5 || px === 6) && py >= 3 && py <= 8) col = [215, 149, 31];
    const i = (py * 12 + px) * 4; im.data[i] = col[0]; im.data[i + 1] = col[1]; im.data[i + 2] = col[2]; im.data[i + 3] = 255;
  }
  x.putImageData(im, 0, 0); return c;
}
function silhouette(src, color) {
  const c = document.createElement('canvas'); c.width = c.height = 64;
  const x = c.getContext('2d'); x.drawImage(src, 0, 0); x.globalCompositeOperation = 'source-in'; x.fillStyle = color; x.fillRect(0, 0, 64, 64); return c;
}
function bboxOf(cv) {
  const d = cv.getContext('2d').getImageData(0, 0, 64, 64).data; let l = 64, t = 64, r = 0, b = 0;
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) if (d[(y * 64 + x) * 4 + 3] > 0) { l = Math.min(l, x); t = Math.min(t, y); r = Math.max(r, x + 1); b = Math.max(b, y + 1); }
  if (r <= l) return {l: 24, t: 40, r: 40, b: 64};
  return {l, t, r, b};
}
function whenAsset(key, fn) { if (assets[key]) fn(); else (waiting[key] = waiting[key] || []).push(fn); }
async function addSprite(key, src) {
  if (assets[key]) return;
  const im = await new Promise(res => { const i = new Image(); i.onload = () => res(i); i.onerror = () => res(null); i.src = src; });
  if (!im || assets[key]) return;
  const img = document.createElement('canvas'); img.width = img.height = 64;
  const x = img.getContext('2d'); x.imageSmoothingEnabled = false; x.drawImage(im, 0, 0, 64, 64);
  assets[key] = {img, sil: [silhouette(img, '#262a36'), silhouette(img, '#f1f3fa'), silhouette(img, '#5b7fd6')], bb: bboxOf(img)};
  const fns = waiting[key] || []; delete waiting[key];
  fns.forEach(f => f());
}

class Pet {
  constructor(cv, o) {
    this.cv = cv; this.ctx = cv.getContext('2d'); Object.assign(this, o);
    this.y = 0; this.facing = -1; this.flipX = 1;
    this.sx = 1; this.sy = 1; this.lean = 0; this.breath = 0; this.sway = 0; this.rot = 0;
    this.parts = []; this.zs = []; this.chip = null; this.flash = 0; this.dim = 0; this.excl = 0;
    this.shots = []; this.booms = []; this.bug = null; this.bugIn = rand(8000, 20000);
    this.note = null; this.working = false;   // coding agent: lasting bubble, "busy" dots
    this.resize(); this.x = this.center(); this.enter('idle', {dur: 900});
  }
  canAct() { return ['idle', 'walk', 'turn', 'stretch', 'alert'].includes(this.state); }
  attack() {
    if (this.isEgg()) { if (this.canAct() || this.state === 'wobble') this.enter('wobble', {dur: 700}); return; }
    if (!this.canAct() && this.state !== 'hop' && this.state !== 'eat') return;
    this.chip = null;
    if (this.bug && !this.bug.dead) this.facing = (this.bug.x + 5) < (this.x + 32) ? -1 : 1;
    const atk = moveOf(this.key);
    this.callout = {text: atk.name + '!', t: 0, life: 1500};
    this.enter('attack', {kind: atk.kind, name: atk.name});
  }
  // One move's projectile from a Digimon at x (box b, facing f, lifted by lift). Bug attacks and
  // battles both use it, so a move looks the same everywhere.
  shotFrom(kind, x, b, f, line, n = 0, lift = 0, lean = 0, tint = null, stage = S.stage) {
    // The size follows the stage of whoever fires (a battle foe passes its own).
    const gy = this.ground() - lift, h = b.b - b.t, st = Math.max(1, stage - 2), z = sizeOf(stage);
    let mx = (f < 0 ? x + b.l : x + b.r) + lean, my = gy - h * .66;
    let speed = 110 + st * 12, r = 3.6 * z, pal = linePal(line) || PAL.fire_agumon;
    // A missile starts slow and speeds up.
    if (kind === 'missile') { my = gy - h * (.5 - n * .12); speed = 110; r = 3 * z; pal = PAL.missile; }
    // Gaia Force forms over the head, kept inside the scene for a tall Digimon.
    if (kind === 'gaia') { r = 9 * gaiaSize(z); mx = x + (b.l + b.r) / 2 + f * 4; my = Math.max(r + 1, gy - h - r); speed = 95; pal = PAL.gaia; }
    if (kind === 'claw') { my = gy - h * .5; speed = 170; r = 6 * z; pal = PAL.claw; }
    if (kind === 'ice') { speed = 135; r = 5 * z; pal = PAL.ice; }
    if (kind === 'bind') { my = gy - h * .55; speed = 210; r = 2.5 * z; pal = PAL.bind; }
    // A punch or charge: a fast shock ahead of the lunge, an impact star where it lands.
    if (kind === 'melee') { my = gy - h * .5; speed = 300; r = 5 * z; pal = PAL.melee; }
    // A beam and a bolt: a line from where they start to their tip, which stays a moment on a hit.
    if (kind === 'beam') { my = gy - h * .62; speed = 460; r = 3 * z; pal = linePal(line) || PAL.beam; }
    if (kind === 'electric') { my = gy - h * .6; speed = 520; r = 3 * z; pal = PAL.electric; }
    // A drifting cloud, rings of a sound or a mind, a small tornado on the ground, a water jet,
    // a twinkling light, a flock, a heart, a crack running along the ground.
    if (kind === 'gas') { my = gy - h * .55; speed = 95; r = 4 * z; pal = PAL.gas; }
    if (kind === 'wave') { my = gy - h * .6; speed = 170; r = 5 * z; pal = PAL.wave; }
    if (kind === 'wind') { mx = x + (b.l + b.r) / 2 + f * (b.r - b.l) * .45; my = gy - 11 + lift; speed = 125; r = 7 * z; pal = PAL.wind; }
    if (kind === 'water') { my = gy - h * .6; speed = 330; r = 3 * z; pal = PAL.water; }
    if (kind === 'light') { my = gy - h * .7; speed = 160; r = 4 * z; pal = PAL.light; }
    if (kind === 'swarm') { my = gy - h * .6; speed = 140; r = 6 * z; pal = PAL.swarm; }
    if (kind === 'heart') { my = gy - h * .6; speed = 130; r = 4 * z; pal = PAL.heart; }
    if (kind === 'quake') { mx = x + (b.l + b.r) / 2 + f * (b.r - b.l) * .45; my = gy - 2 + lift; speed = 170; r = 5 * z; pal = PAL.quake; }
    if (tint && PAL['tint_' + tint]) pal = PAL['tint_' + tint];
    return {kind, x: mx, y: my, ox: mx, oy: my, vx: f * speed, vy: 0, r, pal, t: 0, size: z};
  }
  fire(kind, n = 0) {
    const s = this.shotFrom(kind, this.x, this.bb(), this.facing, S.line, n, this.y, this.lean, moveOf(this.key).tint), f = this.facing;
    const g = this.bug, F = this.fight;
    if (F && F.pending) {
      // A battle: the shot flies at the foe and lands as the app decided.
      const fb = assets[F.foe].bb;
      Object.assign(s, {duel: true, mine: true, hit: F.pending.hit, tx: F.fx + (fb.l + fb.r) / 2, body: fb});
      this.aimAtBody(s);
    } else if (g && !g.dead && Math.sign(g.x + 5 - s.x) === f && kind !== 'wind' && kind !== 'quake') {
      s.vy = (this.ground() - 4 - s.y) / (Math.abs(g.x + 5 - s.x) / Math.abs(s.vx));
    }
    this.shots.push(s);
    if (kind === 'missile') this.booms.push({x: s.x, y: s.y, t: 0, r: 2.6 * s.size, pal: PAL.missile, life: 170});   // launch flash
    if (!SOFT.includes(kind)) for (let i = 0; i < Math.round(6 * s.size); i++) this.parts.push({x: s.x, y: s.y, vx: f * rand(10, 40) * s.size, vy: rand(-25, 10), t: 0, life: rand(250, 450), c: s.pal[1], s: wpx(.8, s.size)});
  }
  // In a battle a shot flies at the middle of the other Digimon's body, the way it aims at a bug.
  // Flying level from where it starts, a tall Digimon's shot passed over a short foe's head and
  // Gaia Force (formed over the head) burst in the air. A tornado and a quake run along the ground.
  aimAtBody(s) {
    if (!s.body || s.kind === 'wind' || s.kind === 'quake') return;
    s.ty = this.ground() - (s.body.b - s.body.t) * .5;
    s.vy = (s.ty - s.y) / Math.max(.05, Math.abs(s.tx - s.x) / Math.abs(s.vx));
  }
  boom(x, y, s) {
    if (s.kind === 'gaia') this.flash = Math.max(this.flash, .45);
    if (s.kind === 'electric' || s.kind === 'light') this.flash = Math.max(this.flash, .22);
    if (s.kind === 'quake') this.shake = 260;
    if ((s.size || 1) >= 1.7 && HEAVY.includes(s.kind)) this.shake = Math.max(this.shake || 0, 140);
    if (s.kind === 'missile') {
      const k = s.size || 1;
      this.flash = Math.max(this.flash, .08 * k);
      if (k >= 1.7) this.shake = Math.max(this.shake || 0, 200);   // a Perfect's or Ultimate's missile shakes the scene
      for (let i = 0; i < 8 * k; i++) { const a = rand(0, TAU), sp = rand(25, 70) * k; this.parts.push({x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 20, t: 0, life: rand(300, 650), c: Math.random() < .5 ? '#5b616c' : '#ffb53b', s: Math.random() < .5 ? 2 : 1}); }
    }
    // A binding move coils around the target instead of bursting, sized to the target's body.
    const body = s.body, coil = s.kind === 'bind' && body
      ? {y: this.ground() - (body.b - body.t) * .48, rx: (body.r - body.l) * .42, gap: (body.b - body.t) * .17} : {};
    this.booms.push(Object.assign({x, y, t: 0, r: s.r * (s.kind === 'gaia' ? 1.3 : 1), pal: s.pal, kind: s.kind,
                                   life: ({bind: 650, melee: 300, gas: 760, wind: 460, quake: 480, light: 440, swarm: 460, heart: 520, missile: 600}[s.kind]) || 320,
                                   size: s.size || 1}, coil));
    const z = s.size || 1, n = Math.round(12 * z);
    if (!['gas', 'wave', 'wind', 'heart', 'swarm'].includes(s.kind)) for (let i = 0; i < n; i++) { const a = TAU * i / n, sp = rand(20, 55) * z; this.parts.push({x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 8, t: 0, life: rand(300, 600), c: s.pal[i % 3], s: Math.random() < .4 ? wpx(2, z) : wpx(1, z)}); }
  }
  // Now and then a big bug: twice the size, slower, takes three hits and counts as three.
  spawnBug() {
    const fromLeft = Math.random() < .5, big = Math.random() < 1 / 6, sc = big ? 2 : 1;
    this.bug = {x: fromLeft ? -11 * sc - 1 : this.worldW + 1, dir: fromLeft ? 1 : -1, t: 0, dead: false, noticed: false,
                big, sc, hp: big ? 3 : 1, hit: 0};
  }
  // One flier of a flock: two flapping wings and a body, `z` times as big.
  drawFlier(c, x, y, up, pal, z = 1) {
    const W = wpx(3, z), w = wpx(2, z), T = wpx(1, z), u = up * T;
    c.fillStyle = pal[2];
    c.fillRect(x - W - w + T, y - T - u, W, T); c.fillRect(x - w, y - u, w, T);
    c.fillRect(x + w, y - T - u, W, T); c.fillRect(x + T, y - u, w, T);
    c.fillStyle = pal[1]; c.fillRect(x - T, y - T, 2 * T, 2 * T);
  }
  drawHeart(c, x, y, pal, k = 1) {
    const hx = Math.round(x - 3.5 * k), hy = Math.round(y - 3 * k);
    HEART.forEach((row, r) => [...row].forEach((v, col) => {
      if (v === '#') { c.fillStyle = r === 1 && col === 1 ? pal[0] : (r > 2 ? pal[2] : pal[1]); c.fillRect(hx + col * k, hy + r * k, k, k); }
    }));
  }
  pixLine(c, x0, y0, x1, y1, w, col) {
    const n = Math.max(1, Math.ceil(Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)))), o = Math.floor(w / 2);
    c.fillStyle = col;
    for (let i = 0; i <= n; i++) c.fillRect(Math.round(x0 + (x1 - x0) * i / n) - o, Math.round(y0 + (y1 - y0) * i / n) - o, w, w);
  }
  pixBall(c, x, y, r, col) {
    c.fillStyle = col; const R = Math.ceil(r), cx = Math.round(x), cy = Math.round(y);
    for (let dy = -R; dy <= R; dy++) { if (Math.abs(dy) > r) continue; const w = Math.floor(Math.sqrt(r * r - dy * dy)); c.fillRect(cx - w, cy + dy, w * 2 + 1, 1); }
  }
  isEgg(k = this.key) { return k.startsWith('egg_'); }
  bb() { return assets[this.key].bb; }
  center() { const b = this.bb(); return this.worldW / 2 - (b.l + b.r) / 2; }
  ground() { return this.worldH - (this.desk ? 4 : 9); }
  resize() {
    this.scale = 2;
    this.cssW = window.innerWidth || 320; this.cssH = window.innerHeight || 168;
    this.worldW = this.cssW / this.scale; this.worldH = this.cssH / this.scale;
    this.cv.style.width = this.cssW + 'px'; this.cv.style.height = this.cssH + 'px';
    this.cv.width = Math.round(this.cssW * DPR); this.cv.height = Math.round(this.cssH * DPR);
    if (this.x !== undefined) this.clampX();
  }
  clampX() { const b = this.bb(); this.x = Math.max(-b.l + 2, Math.min(this.worldW - b.r - 2, this.x)); }
  enter(s, d = {}) { this.state = s; this.t = 0; this.d = d; if (s === 'idle' && !d.dur) d.dur = rand(1400, 3400); }
  next() {
    const r = Math.random();
    if (this.isEgg()) { r < .45 ? this.enter('wobble', {dur: 900}) : this.enter('idle'); return; }
    if (S.mood && Math.random() < .2) {
      const sleepy = S.mood === 'sleepy', ko = S.lang === 'ko';
      this.callout = {text: sleepy ? (ko ? '하암…' : 'Yawn…') : (ko ? '으으…' : 'Ugh…'), t: 0, life: 1400};
      this.enter(sleepy ? 'stretch' : 'idle', {dur: sleepy ? 1400 : 1800});
      return;
    }
    // Staying in place (Settings): no walks; once a battle or a Jogress moved it, it walks back to the middle.
    if (S.still && Math.abs(this.x - this.center()) > 3) { this.startWalk(this.center()); return; }
    const walk = S.still ? 0 : (this.desk ? .58 : .5) * (S.mood ? .45 : 1);
    if (r < walk) this.startWalk();
    else if (r < walk + .17) { this.facing = -this.facing; this.enter('idle', {dur: rand(900, 1800)}); }
    else if (r < walk + .29) this.enter('stretch', {dur: 1100});
    else if (r < walk + .38) this.enter('hop', {h: this.hopH});
    else this.enter('idle');
  }
  startWalk(to) {
    const b = this.bb(), minX = -b.l + 2, maxX = this.worldW - b.r - 2;
    if (maxX - minX < 8) { this.enter('idle'); return; }
    let tx = this.x;
    if (to !== undefined) tx = Math.max(minX, Math.min(maxX, to));
    else for (let i = 0; i < 10; i++) { tx = rand(minX, maxX); if (Math.abs(tx - this.x) >= Math.min(30, (maxX - minX) / 2)) break; }
    const dir = Math.sign(tx - this.x) || 1;
    if (dir !== this.facing) { this.facing = dir; this.enter('turn', {tx, dir}); }
    else this.enter('walk', {x0: this.x, tx, dir});
  }
  sparkle(cx, cy, n) {
    for (let i = 0; i < n; i++) {
      const a = TAU * i / n + rand(-.3, .3), sp = rand(22, 50);
      this.parts.push({x: cx, y: cy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 10, t: 0, life: rand(600, 1000), c: Math.random() < .5 ? '#ffffff' : '#ffd84a', s: Math.random() < .5 ? 2 : 1});
    }
  }
  // ---- commands ----
  feed() {
    if (this.state === 'evolve' || this.state === 'held' || this.chip) return;
    const b = this.bb(); let side = this.facing;
    const front = s => s < 0 ? this.x + b.l - 14 : this.x + b.r + 2;
    let fx = front(side);
    if (fx < 2 || fx > this.worldW - 14) { side = -side; fx = front(side); }
    fx = Math.max(2, Math.min(this.worldW - 14, fx));
    this.facing = side;
    this.chip = {x: fx, y: -14, vy: 0, landed: false, bites: 0, fromRight: side < 0, shrink: 0};
    this.enter('eat', {});
  }
  sleep() { if (this.state === 'evolve' || this.state === 'sleep') return; this.chip = null; this.enter('sleep', {zacc: 700}); }
  wake() { if (this.state !== 'sleep') return; this.excl = 750; this.enter('hop', {h: this.hopH * .7, dur: 480}); }
  jump() { if (this.state === 'evolve' || this.state === 'sleep') return; this.chip = null; this.enter('hop', {h: this.hopH}); }
  notice() { if (this.state === 'evolve' || this.state === 'held') return; if (this.state === 'sleep') { this.wake(); return; } this.excl = 700; this.jump(); }
  // A coding agent finished: a double hop with sparkles (an egg wobbles instead).
  cheer() {
    if (this.state === 'evolve' || this.state === 'held') return;
    this.chip = null;
    const b = this.bb();
    this.sparkle(this.x + (b.l + b.r) / 2, this.ground() - 64 + b.t + 4, 12);
    if (this.isEgg()) { this.enter('wobble', {dur: 900}); return; }
    this.enter('hop', {h: this.hopH * 1.2, dur: 560, then: () => this.enter('hop', {h: this.hopH * .6, dur: 420})});
  }
  // Graduation: a big hop, a burst of sparkles and a send-off before it becomes an egg again.
  graduate() {
    if (this.state === 'evolve') return;
    this.chip = null; this.bug = null; this.note = null;
    this.callout = {text: S.lang === 'ko' ? '졸업 축하해요!' : 'Graduated!', t: 0, life: 1700};
    const b = this.bb(), cx = this.x + (b.l + b.r) / 2, cy = this.ground() - 64 + (b.t + b.b) / 2;
    this.sparkle(cx, cy, 26); this.flash = Math.max(this.flash, .5);
    if (this.state === 'sleep') this.dim = 0;
    this.enter('hop', {h: this.hopH * 1.5, dur: 700, then: () => this.enter('hop', {h: this.hopH * .8, dur: 520})});
  }
  setAgent(a) {
    this.working = !!a.working; this.note = a.bubble || null;
    if (a.react === 'done') this.cheer();
    else if (a.react === 'waiting') this.notice();
  }
  grab() { if (this.state === 'evolve') return; this.chip = null; this.excl = 600; this.enter('held', {s: 0, v: 0}); }
  dragMove(dx) { if (this.state === 'held') this.d.v += dx * .004; }
  drop() { if (this.state === 'held') this.enter('hop', {h: 3, dur: 420}); }
  evolve(to) {
    if (this.state === 'evolve') { this.d.to = to; return; }
    if (this.key === to) return;
    this.chip = null; this.zs = [];
    if (this.isEgg(to)) this.bug = null;
    this.enter('evolve', {from: this.key, to, show: false, acc: 0, swapped: false});
  }
  setNow(key) { if (!assets[key] || this.key === key) return; this.key = key; this.clampX(); }
  // ---- battle (decided by the app; this only plays it) ----
  duel(c) {
    if (this.isEgg() || !assets[c.foe]) return;
    this.bug = null; this.chip = null; this.callout = null; this.note = null;
    const W = this.worldW, onLeft = this.x + 32 < W / 2;
    this.x = onLeft ? W * .25 - 32 : W * .75 - 32; this.clampX();
    this.facing = onLeft ? 1 : -1;
    this.fight = {foe: c.foe, stage: c.foeStage || S.stage, rounds: c.rounds || [], won: !!c.won, i: 0, t: -650, fx: onLeft ? W * .75 - 32 : W * .25 - 32,
                  dir: onLeft ? -1 : 1, alpha: 0, hurt: 0, foeHurt: 0, lunge: 0, done: 0, pending: null};
    this.enter('duel', {});
  }
  updateDuel(dt) {
    const F = this.fight;
    F.t += dt; F.alpha = F.done > 1900 ? Math.max(0, F.alpha - dt / 450) : Math.min(1, F.alpha + dt / 350);
    F.hurt = Math.max(0, F.hurt - dt); F.foeHurt = Math.max(0, F.foeHurt - dt); F.lunge = Math.max(0, (F.lunge || 0) - dt);
    if (F.done) {
      F.done += dt;
      if (F.won && F.done < 900) this.y = Math.abs(Math.sin(F.done / 900 * Math.PI * 2)) * 8;
      if (F.done > 2500) { this.fight = null; if (S.sleeping) this.sleep(); else this.enter('idle', {dur: 900}); }
      return;
    }
    if (F.t < 0) return;
    if (F.i < F.rounds.length) {
      const r = F.rounds[F.i++];
      F.t = -850;
      if (r.a === 'me') {
        // The pet's own attack (wind-up, the move's shape); `fire` aims it at the foe.
        const atk = moveOf(this.key);
        F.pending = {hit: !!r.hit};
        this.callout = {text: atk.name + '!', t: 0, life: 800};
        this.enter('attack', {kind: atk.kind, name: atk.name});
      } else {
        const fb = assets[F.foe].bb, mb = this.bb();
        const fm = moveOf(F.foe), s = this.shotFrom(fm.kind, F.fx, fb, F.dir, '', 0, 0, 0, fm.tint, F.stage);
        Object.assign(s, {duel: true, mine: false, hit: !!r.hit, tx: this.x + (mb.l + mb.r) / 2, body: mb});
        this.aimAtBody(s);
        this.shots.push(s);
        if (fm.kind === 'missile') {
          const s2 = this.shotFrom('missile', F.fx, fb, F.dir, '', 1, 0, 0, fm.tint, F.stage);
          Object.assign(s2, {duel: true, mine: false, hit: !!r.hit, tx: s.tx, body: mb, x: s2.x - F.dir * 14 * s2.size});
          this.aimAtBody(s2);
          this.shots.push(s2);
          this.booms.push({x: s.x, y: s.y, t: 0, r: 2.6 * s.size, pal: PAL.missile, life: 170});
        }
        F.lunge = 260;
      }
    } else if (!this.shots.some(s => s.duel)) {
      const ko = S.lang === 'ko';
      F.done = 1;
      this.callout = {text: F.won ? (ko ? '이겼다!' : 'Won!') : (ko ? '졌다…' : 'Lost…'), t: 0, life: 2300};
    }
  }
  // ---- Jogress (merged with a friend's Digimon; the app sends the evolution right after) ----
  merge(c) {
    if (this.isEgg() || !assets[c.partner]) return;
    this.bug = null; this.chip = null; this.note = null; this.shots = [];
    const W = this.worldW, onLeft = this.x + 32 < W / 2;
    this.x = onLeft ? W * .25 - 32 : W * .75 - 32; this.clampX();
    this.facing = onLeft ? 1 : -1;
    this.fight = {foe: c.partner, merge: true, fx: onLeft ? W * .75 - 32 : W * .25 - 32, dir: onLeft ? -1 : 1,
                  alpha: 0, hurt: 0, foeHurt: 0, lunge: 0, done: 0, won: false, rounds: [], white: false};
    this.callout = {text: S.lang === 'ko' ? '합체 진화!' : 'Jogress!', t: 0, life: 1900};
    this.enter('merge', {x0: this.x, fx0: this.fight.fx});
  }
  updateMerge(dt) {
    const F = this.fight, d = this.d, t = this.t;
    if (!F) { this.enter('idle', {dur: 600}); return; }
    // The friend's Digimon fades in, both walk to the middle, glow white faster and faster, then one flash.
    F.alpha = Math.min(1, t / 400);
    const mid = this.worldW / 2 - 32, k = Math.min(1, Math.max(0, (t - 450) / 900)), e = k * k * (3 - 2 * k);
    this.x = d.x0 + (mid - this.facing * 9 - d.x0) * e;
    F.fx = d.fx0 + (mid + this.facing * 9 - d.fx0) * e;
    if (k > 0 && k < 1) this.y = Math.abs(Math.sin(t / 85)) * 2;
    if (t > 1350) {
      const iv = Math.max(35, 190 - (t - 1350) / 4);
      F.white = d.white = Math.floor((t - 1350) / iv) % 2 === 0;
    }
    if (t > 2000 && !d.flashed) {
      d.flashed = true; this.flash = 1; this.fight = null; d.white = false;
      const b = this.bb(); this.sparkle(this.x + (b.l + b.r) / 2, this.ground() - 64 + (b.t + b.b) / 2, 24);
    }
    if (t > 2300) this.enter('idle', {dur: 1200});   // the evolution comes from the app
  }
  drawFoe(c, gy, dark) {
    const F = this.fight, A = assets[F.foe];
    if (!A) return;
    const bb = A.bb, cx = F.fx + (bb.l + bb.r) / 2, lost = F.done && F.won;
    c.globalAlpha = F.alpha;
    c.fillStyle = this.desk ? 'rgba(0,0,0,.22)' : (dark ? 'rgba(0,0,0,.35)' : 'rgba(60,50,30,.13)');
    c.beginPath(); c.ellipse(cx, gy + .5, (bb.r - bb.l) * .39, this.desk ? 2 : 2.4, 0, 0, TAU); c.fill();
    const flash = F.foeHurt > 0 && Math.floor(F.foeHurt / 80) % 2 === 0;
    c.save(); c.translate(cx + F.dir * 2 * Math.sin(Math.PI * (F.lunge || 0) / 260), gy); c.scale(F.dir === 1 ? -1 : 1, lost ? .92 : 1);
    // Merging flickers in silhouette like an evolution (dark on a light scene, light on a dark one).
    const img = F.white ? A.sil[(dark && !this.desk) ? 1 : 0] : flash ? A.sil[1] : A.img;
    c.drawImage(img, -(bb.l + bb.r) / 2, -bb.b, 64, 64);
    c.restore();
    c.globalAlpha = 1;
  }
  // ---- update ----
  update(dt) {
    dt = Math.min(dt, 50);
    const T = performance.now();
    this.t += dt;
    this.sx = 1; this.sy = 1; this.lean = 0; this.y = 0; this.breath = 0; this.sway = 0; this.rot = 0;
    const target = this.facing === -1 ? 1 : -1, fstep = dt / 90;
    this.flipX = this.flipX < target ? Math.min(target, this.flipX + fstep) : Math.max(target, this.flipX - fstep);
    if (this.state !== 'sleep') this.dim = Math.max(0, this.dim - dt / 500);
    if (this.flash > 0) this.flash = Math.max(0, this.flash - dt / 550);
    if (this.shake > 0) this.shake -= dt;
    if (this.excl > 0) this.excl -= dt;
    this.zs = this.zs.filter(z => (z.t += dt) < z.life);
    if (this.fight && this.state !== 'duel' && this.state !== 'attack' && this.state !== 'merge') this.fight = null;   // interrupted (sleep, evolution, ...)
    if (S.mood === 'sleepy' && this.state !== 'sleep' && this.state !== 'evolve') {
      this.moodT = (this.moodT || 0) + dt;
      if (this.moodT > 4200) {
        this.moodT = 0; const b = this.bb();
        this.zs.push({x: this.facing < 0 ? this.x + b.l + 2 : this.x + b.r - 7, y: this.ground() - 64 + b.t - 4, t: 0, life: 2200, dir: this.facing});
      }
    }
    this.parts = this.parts.filter(p => { p.t += dt; p.x += p.vx * dt / 1000; p.y += p.vy * dt / 1000; p.vy += 60 * dt / 1000; return p.t < p.life; });
    this.shots = this.shots.filter(s => {
      if (s.hold !== undefined) { s.t += dt; s.hold -= dt; return s.hold > 0; }   // a landed beam or bolt lingers
      s.t += dt; s.x += s.vx * dt / 1000; s.y += s.vy * dt / 1000;
      const back = -Math.sign(s.vx);
      if (s.kind === 'missile') {
        // Speeds up, so it steers to its target every frame: the other Digimon's body or a bug.
        const k = s.size || 1, sp = Math.min(300, Math.abs(s.vx) + 300 * dt / 1000);
        s.vx = (Math.sign(s.vx) || 1) * sp;
        const g = this.bug;
        if (s.duel && s.ty !== undefined) s.vy = (s.ty - s.y) / Math.max(.06, Math.abs(s.tx - s.x) / sp);
        else if (!s.duel && g && !g.dead) s.vy = (this.ground() - 4 * g.sc - s.y) / Math.max(.06, Math.abs(g.x + 5 * g.sc - s.x) / sp);
        // A thick smoke trail with sparks from the exhaust.
        const tail = s.x + back * 5 * k;
        for (let i = 0; i < Math.ceil(k * 1.5); i++) this.parts.push({x: tail + back * rand(0, 3 * k), y: s.y + rand(-k, k), vx: back * rand(3, 10), vy: rand(-10, -2), t: 0, life: rand(380, 700), c: Math.random() < .5 ? '#d5d9df' : '#9aa0aa', s: Math.random() < .5 ? Math.round(2 * k) : Math.round(1.5 * k) || 1});
        if (Math.random() < .5) this.parts.push({x: tail, y: s.y, vx: back * rand(10, 25), vy: rand(-6, 6), t: 0, life: rand(120, 220), c: Math.random() < .5 ? '#ffb53b' : '#fff3c4', s: 1});
      } else if (s.kind === 'ice') {
        for (let i = 0; i < 2; i++) this.parts.push({x: s.x + back * rand(0, s.r * 1.5), y: s.y + rand(-s.r, s.r), vx: s.vx * .1, vy: rand(-6, 6), t: 0, life: rand(250, 500), c: Math.random() < .5 ? '#ffffff' : '#c7f3ff', s: Math.random() < .5 ? wpx(2, s.size || 1) : wpx(1, s.size || 1)});
      } else if (s.kind === 'light') {
        const z = s.size || 1;
        for (let i = 0; i < 2; i++) if (Math.random() < .8) this.parts.push({x: s.x + back * rand(2, 8) * z, y: s.y + rand(-4, 4) * z, vx: back * rand(4, 14), vy: rand(-8, 8), t: 0, life: rand(300, 550), c: [s.pal[2], s.pal[1], s.pal[0]][Math.floor(rand(0, 3))], s: Math.random() < .4 ? wpx(2, z) : wpx(1, z)});
      } else if (s.kind !== 'claw' && s.kind !== 'beam' && s.kind !== 'electric' && !SOFT.includes(s.kind)) {
        for (let i = 0; i < (s.kind === 'gaia' ? 2 : 1) * Math.round(s.size || 1); i++) if (Math.random() < .75) this.parts.push({x: s.x + back * s.r * .7 + rand(-1, 1), y: s.y + rand(-s.r * .5, s.r * .5), vx: -s.vx * .05, vy: rand(-14, -4), t: 0, life: rand(200, 380), c: s.pal[Math.random() < .5 ? 1 : 2], s: wpx(.8, s.size || 1)});
      }
      if (s.duel) {
        if (!s.done && (s.vx > 0 ? s.x >= s.tx : s.x <= s.tx)) {
          s.done = true;
          if (s.hit) {
            this.boom(s.x, s.y, s);
            if (this.fight) { if (s.mine) this.fight.foeHurt = 520; else this.fight.hurt = 520; }
            if (s.kind === 'beam' || s.kind === 'electric' || s.kind === 'water') { s.hold = 220; return true; }
            return false;
          }
          if (s.kind === 'bind' || s.kind === 'melee') return false;   // a missed tendril or punch is gone
        }
        return s.x > -12 && s.x < this.worldW + 12;
      }
      if (s.kind === 'bind' && Math.abs(s.x - s.ox) > 120) return false;   // out of reach
      const g = this.bug;
      if (g && !g.dead && Math.hypot(s.x - (g.x + 5.5 * g.sc), s.y - (this.ground() - 4 * g.sc)) < s.r + 6 * g.sc) {
        this.boom(s.x, s.y, s);
        g.hp -= 1; g.hit = 220;
        if (g.hp <= 0) { g.dead = true; g.t = 0; post({cmd: 'bugDefeated', count: g.big ? 3 : 1}); }
        else g.x -= g.dir * 6;   // knocked back, still coming
        if (s.kind === 'beam' || s.kind === 'electric' || s.kind === 'water') { s.hold = 220; return true; }
        return false;
      }
      if (s.x < 3 || s.x > this.worldW - 3 || s.y > this.ground()) { this.boom(s.x, Math.min(s.y, this.ground() - 2), s); return false; }
      return true;
    });
    this.booms = this.booms.filter(b => (b.t += dt) < (b.life || 320));
    if (this.callout && (this.callout.t += dt) > this.callout.life) this.callout = null;
    if (this.bug) {
      const g = this.bug; g.t += dt;
      if (g.hit > 0) g.hit -= dt;
      if (g.dead) { if (g.t > 300) this.bug = null; }
      else if (this.state !== 'held') {
        g.x += g.dir * (g.big ? 9 : 14) * dt / 1000;
        const b = this.bb(), petL = this.x + b.l, petR = this.x + b.r, w = 11 * g.sc;
        if (g.dir > 0 && g.x + w > petL - 4 && g.x < petR) g.x = petL - 4 - w;
        if (g.dir < 0 && g.x < petR + 4 && g.x + w > petL) g.x = petR + 4;
      }
    } else if (!this.isEgg() && this.canAct() && this.state !== 'alert') {
      this.bugIn -= dt;
      if (this.bugIn <= 0) { this.spawnBug(); this.bugIn = this.desk ? rand(40000, 110000) : rand(25000, 60000); }
    }
    const g0 = this.bug;
    if (g0 && !g0.dead && !g0.noticed && g0.x > -4 && g0.x < this.worldW - 7 && this.canAct() && this.state !== 'alert' && !this.isEgg()) {
      g0.noticed = true; this.excl = 600; this.facing = (g0.x + 5) < (this.x + 32) ? -1 : 1; this.enter('alert', {});
    }
    const d = this.d;
    const idleBreath = () => { this.breath = .03 * (.5 + .5 * Math.sin(TAU * T / 1900)); this.sway = .6 * Math.sin(TAU * T / 3700); };
    switch (this.state) {
      case 'duel': idleBreath(); this.updateDuel(dt); break;
      case 'merge': idleBreath(); this.updateMerge(dt); break;
      case 'idle':
        idleBreath();
        if (this.bug && !this.bug.dead && this.bug.noticed && this.t > 350) { this.attack(); break; }
        if (this.t >= d.dur) this.next();
        break;
      case 'alert': idleBreath(); if (this.t >= 550) this.attack(); break;
      case 'attack': {
        const t = this.t, f = this.facing, k = d.kind, [w, s1, rc] = TIMING[k] || TIMING.fire, t1 = w, t2 = w + s1;
        if (t < t1) {
          const p = t / w;
          if (k === 'gaia') { this.sy = 1 + .08 * p; this.sx = 1 - .04 * p; this.y = 1.5 * p; }
          else if (k === 'claw') { this.sy = 1 - .1 * p; this.sx = 1 + .06 * p; this.lean = -f * 1.2 * p; }
          else if (k === 'melee') { this.sy = 1 - .1 * p; this.sx = 1 + .05 * p; this.lean = -f * 3 * p; }
          else if (k === 'beam') { this.sy = 1 + .05 * p; this.sx = 1 - .03 * p; this.lean = -f * .8 * p; }
          else { this.lean = -f * 1.4 * p; this.sway = 1.6 * p; this.sy = 1 - .08 * p; this.sx = 1 + .05 * p; }
        } else if (t < t2) {
          const p = (t - t1) / s1;
          if (k === 'claw') { this.lean = f * (-1.2 + 7 * p); this.sx = 1.08; this.sy = .96; }
          else if (k === 'melee') { this.lean = f * (-3 + 17 * Math.sin(Math.PI / 2 * p)); this.sx = 1.1; this.sy = .94; }
          else if (k === 'beam') { this.lean = f * -1.5 * p; this.sy = 1.04; }
          else if (k === 'gaia') { this.lean = f * 2.5 * p; this.sway = -3 * p; this.sy = 1.08 - .12 * p; this.y = 1.5 * (1 - p); }
          else { this.lean = f * (-1.4 + 3.6 * p); this.sway = 1.6 - 4 * p; this.sy = .92 + .12 * p; this.sx = 1.05 - .07 * p; }
          if (!d.fired) { d.fired = true; d.ft = t; this.fire(k, 0); }
        } else if (t < t2 + rc) {
          const e = 1 - easeIO((t - t2) / rc);
          this.lean = f * (k === 'claw' ? 5.8 : k === 'melee' ? 14 : 2.2) * e; this.sway = (k === 'claw' || k === 'melee' ? 0 : -2.4) * e; this.sy = 1 + .04 * e;
        } else if (this.fight) { this.fight.pending = null; this.enter('duel', {}); }
        else this.enter('idle', {dur: rand(700, 1500)});
        if (k === 'missile' && d.fired && !d.fired2 && t - d.ft >= 130) { d.fired2 = true; this.fire('missile', 1); }
        break; }
      case 'wobble': { const p = this.t / d.dur; this.rot = .16 * Math.sin(this.t / 70) * (1 - p); if (p >= 1) this.enter('idle'); break; }
      case 'stretch': { const p = Math.min(1, this.t / d.dur); this.breath = .03 + .13 * Math.sin(Math.PI * p); this.sx = 1 - .03 * Math.sin(Math.PI * p); if (p >= 1) this.enter('idle', {dur: rand(900, 2000)}); break; }
      case 'turn': idleBreath(); if (this.t >= 260) this.enter('walk', {x0: this.x, tx: d.tx, dir: d.dir}); break;
      case 'walk': {
        if (!d.dur) d.dur = Math.abs(d.tx - d.x0) / (this.speed * moodSlow()) * 1000 + 400;
        const p = Math.min(1, this.t / d.dur); this.x = d.x0 + (d.tx - d.x0) * easeIO(p);
        const ph = (this.t % 320) / 320, lift = Math.sin(Math.PI * ph), moving = Math.min(1, Math.sin(Math.PI * p) * 3);
        this.y = 1.6 * lift * moving;
        this.sy = 1 - .035 * (1 - lift) * moving; this.sx = 1 / this.sy;
        this.sway = -1.6 * Math.min(1, moving * .85); this.breath = .02;
        if (p >= 1) this.enter('idle', {dur: rand(600, 1800)});
        break; }
      case 'hop': {
        const dur = d.dur || 560, h = d.h || this.hopH, t = this.t, a = 110, l = 110, air = dur - a - l;
        if (t < a) { this.sy = .86; this.sx = 1.1; }
        else if (t < a + air) { const p = (t - a) / air; this.y = h * Math.sin(Math.PI * p); const st = p < .45 ? 1.07 : 1; this.sy = st; this.sx = 1 / st; }
        else if (t < dur) { this.sy = .88; this.sx = 1.08; }
        else { const then = d.then; this.enter('idle', {dur: rand(900, 2000)}); if (then) then(); }
        break; }
      case 'held': {
        const k = .00025, c = .006;
        d.v += (-k * d.s - c * d.v) * dt; d.s += d.v * dt; d.s = Math.max(-9, Math.min(9, d.s));
        this.y = 3; this.sy = 1.05; this.sx = .97;
        this.sway = d.s + .6 * Math.sin(this.t / 90); this.lean = -this.sway;
        break; }
      case 'sleep': {
        this.dim = Math.min(1, this.dim + dt / 700);
        this.breath = .06 * (.5 + .5 * Math.sin(TAU * T / 2800)); this.sy = .97;
        d.zacc += dt;
        if (this.t > 500 && d.zacc >= 1200) {
          d.zacc = 0; const b = this.bb();
          const hx = this.facing < 0 ? this.x + b.l + 2 : this.x + b.r - 7;
          this.zs.push({x: hx, y: this.ground() - 64 + b.t - 6, t: 0, life: 2800, dir: this.facing});
        }
        break; }
      case 'eat': {
        const ch = this.chip; if (!ch) { this.enter('idle'); break; }
        if (!ch.landed) {
          ch.vy += 260 * dt / 1000; ch.y += ch.vy * dt / 1000;
          const g = this.ground() - 12;
          if (ch.y >= g) { ch.y = g; if (ch.vy > 45) ch.vy = -ch.vy * .32; else { ch.landed = true; ch.vy = 0; d.ct = this.t; } }
          idleBreath(); break;
        }
        const k = this.t - d.ct;
        if (this.isEgg()) {
          if (k < 650) { ch.shrink = k / 650; this.rot = .1 * Math.sin(k / 45); }
          else { this.chip = null; this.sparkle(ch.x + 6, ch.y + 6, 10); this.enter('wobble', {dur: 700}); }
          break;
        }
        const bite = 420, n = Math.floor(k / bite), kk = k % bite;
        if (n >= 3) { this.chip = null; this.enter('hop', {h: this.hopH * .6, dur: 460, then: () => this.enter('hop', {h: this.hopH * .4, dur: 380})}); break; }
        const dip = kk < 160 ? Math.sin(Math.PI * kk / 160) : 0;
        this.lean = 1.6 * dip * this.facing; this.sway = -2.4 * dip; this.sy = 1 - .04 * dip; this.breath = .02;
        ch.bites = n + (kk >= 160 ? 1 : 0);
        break; }
      case 'evolve': {
        const T1 = 1600;
        if (this.t < T1) {
          const iv = 260 - 220 * (this.t / T1); d.acc += dt; if (d.acc >= iv) { d.acc = 0; d.show = !d.show; }
          const pulse = 1 + .05 * Math.sin(this.t / 50) * (this.t / T1); this.sx = pulse; this.sy = pulse;
        } else if (!d.swapped) {
          d.swapped = true; this.key = d.to; this.clampX(); this.flash = 1;
          const b = this.bb(); this.sparkle(this.x + (b.l + b.r) / 2, this.ground() - 64 + (b.t + b.b) / 2, 18);
        } else if (this.t > T1 + 600) {
          this.enter('hop', {h: this.hopH});
          if (S.sleeping) this.d.then = () => this.sleep();
        }
        break; }
    }
  }
  // ---- draw ----
  blit(c, img, bb, ox) {
    const bot = bb.b, Ht = Math.max(1, bot - bb.t), breath = this.breath, sway = this.sway;
    if (!breath && !sway) { c.drawImage(img, ox, -bot, 64, 64); return; }
    for (let r = bb.t; r < bot; r++) {
      const h0 = bot - r, h1 = bot - r - 1;
      const Y0 = -(h0 + breath * h0 * h0 / Ht), Y1 = -(h1 + breath * h1 * h1 / Ht);
      const f = (h0 - .5) / Ht;
      c.drawImage(img, 0, r, 64, 1, ox + sway * f * f, Y0, 64, Y1 - Y0);
    }
  }
  draw() {
    const c = this.ctx, s = this.scale * DPR, W = this.worldW, H = this.worldH, dark = isDark(), desk = this.desk;
    c.setTransform(1, 0, 0, 1, 0, 0); c.clearRect(0, 0, this.cv.width, this.cv.height);
    c.setTransform(s, 0, 0, s, 0, 0); c.imageSmoothingEnabled = false;
    if (this.shake > 0) c.translate(Math.round(rand(-1, 1)), Math.round(rand(-1, 1)));   // a quake shakes the scene
    const evolving = this.state === 'evolve' && !this.d.swapped;
    let A = assets[this.key], img = A.img;
    if (evolving) { A = assets[this.d.show ? this.d.to : this.d.from] || A; img = A.sil[(dark && !desk) ? 1 : 0]; }
    const bb = A.bb, gy = this.ground(), cx = this.x + (bb.l + bb.r) / 2 + this.lean, hgt = bb.b - bb.t;

    const sw = (bb.r - bb.l) * .78 * (1 - Math.min(this.y, 16) / 16 * .5);
    c.fillStyle = desk ? 'rgba(0,0,0,.22)' : (dark ? 'rgba(0,0,0,.35)' : 'rgba(60,50,30,.13)');
    c.beginPath(); c.ellipse(cx, gy + .5, sw / 2, desk ? 2 : 2.4, 0, 0, TAU); c.fill();
    const glow = desk ? Math.max(evolving ? .55 : 0, this.flash) : 0;
    if (glow > 0) {
      const gcy = gy - this.y - hgt / 2, rad = Math.max(bb.r - bb.l, hgt) * .9;
      const g = c.createRadialGradient(cx, gcy, 0, cx, gcy, rad);
      g.addColorStop(0, `rgba(255,252,235,${glow})`); g.addColorStop(1, 'rgba(255,252,235,0)');
      c.fillStyle = g; c.fillRect(cx - rad, gcy - rad, rad * 2, rad * 2);
    }
    if (this.bug && !this.bug.dead) {
      const g = this.bug, k = g.sc, bx = Math.round(g.x), by = Math.round(gy - 7 * k);
      c.fillStyle = desk ? 'rgba(0,0,0,.2)' : 'rgba(60,50,30,.12)';
      c.beginPath(); c.ellipse(bx + 5.5 * k, gy + .5, 5 * k, 1.4 * k, 0, 0, TAU); c.fill();
      const flash = g.hit > 0 && Math.floor(g.hit / 55) % 2 === 0;
      BUG[Math.floor(g.t / (g.big ? 200 : 140)) % 2].forEach((row, r) => [...row].forEach((v, col) => {
        if (v !== '.') { c.fillStyle = flash ? '#ffffff' : BUG_C[v]; c.fillRect(bx + col * k, by + r * k, k, k); }
      }));
    }
    if (this.chip) {
      const ch = this.chip, rem = Math.min(12, ch.bites * 4);
      c.save();
      if (ch.shrink) { const k = 1 - ch.shrink; c.translate(ch.x + 6, ch.y + 6); c.scale(k, k); c.translate(-ch.x - 6, -ch.y - 6); }
      if (rem < 12) { if (ch.fromRight) c.drawImage(COIN, 0, 0, 12 - rem, 12, ch.x, ch.y, 12 - rem, 12); else c.drawImage(COIN, rem, 0, 12 - rem, 12, ch.x + rem, ch.y, 12 - rem, 12); }
      c.restore();
    }
    if (this.fight && this.fight.hurt > 0 && Math.floor(this.fight.hurt / 80) % 2 === 0 && !evolving) img = A.sil[1];
    if (this.state === 'merge' && this.d.white) img = A.sil[(dark && !desk) ? 1 : 0];
    c.save();
    c.translate(cx, gy - this.y);
    if (this.rot) c.rotate(this.rot);
    c.scale(this.flipX * this.sx, this.sy);
    this.blit(c, img, bb, -(bb.l + bb.r) / 2);
    if (desk && this.dim > 0 && !evolving) { c.globalAlpha = .35 * this.dim; this.blit(c, A.sil[0], bb, -(bb.l + bb.r) / 2); c.globalAlpha = 1; }
    if (S.mood === 'sick' && !evolving && A.sil[2]) { c.globalAlpha = .22; this.blit(c, A.sil[2], bb, -(bb.l + bb.r) / 2); c.globalAlpha = 1; }
    c.restore();
    if (this.fight) this.drawFoe(c, gy, dark);
    if (S.mood === 'sick' && !evolving && this.state !== 'sleep') {
      // A sweat drop beside the head.
      const sx = Math.round(cx + (bb.r - bb.l) / 2 * (this.facing < 0 ? -1 : 1) * .6), sy = Math.round(gy - this.y - hgt + 3 + Math.sin(performance.now() / 260));
      c.fillStyle = '#8fd0ff'; c.fillRect(sx, sy, 2, 2); c.fillRect(sx, sy + 2, 2, 1); c.fillStyle = '#ffffff'; c.fillRect(sx, sy, 1, 1);
    }

    if (!desk && this.dim > 0) { c.fillStyle = `rgba(12,16,34,${.38 * this.dim})`; c.fillRect(0, 0, W, H); }
    if (this.state === 'attack' && this.d.kind === 'beam' && !this.d.fired) {
      // Light gathers in front of the mouth before the beam.
      const p = Math.min(1, this.t / TIMING.beam[0]), r = (1 + 3.5 * p + Math.sin(this.t / 25) * .5 * p) * sizeOf(S.stage);
      const pal = linePal(S.line) || PAL.beam, bx = this.facing < 0 ? this.x + bb.l + this.lean : this.x + bb.r + this.lean;
      const by = gy - this.y - hgt * .62;
      this.pixBall(c, bx, by, r, pal[2]); this.pixBall(c, bx, by, r * .6, pal[1]); this.pixBall(c, bx, by, r * .3, pal[0]);
    }
    if (this.state === 'attack' && this.d.kind === 'gaia' && !this.d.fired) {
      const g = gaiaSize(sizeOf(S.stage)), p = easeIO(Math.min(1, this.t / TIMING.gaia[0])), r = (9 * p + Math.sin(this.t / 30) * .5 * p) * g;
      const bx = cx + this.facing * 4, by = Math.max(9 * g + 1, gy - this.y - hgt - 9 * g);
      if (r > .8) { this.pixBall(c, bx, by, r, PAL.gaia[2]); this.pixBall(c, bx, by, r * .7, PAL.gaia[1]); this.pixBall(c, bx, by, r * .35, PAL.gaia[0]); }
    }
    for (const s of this.shots) {
      const back = -Math.sign(s.vx), z = s.size || 1;
      if (s.kind === 'missile') {
        // A rocket that scales with the stage: flickering exhaust, fins, a body with a highlight, a red nose.
        const k = s.size || 1, L = Math.round(8 * k), H = Math.max(2, Math.round(2.4 * k)), F = Math.round((3 + Math.random() * 3) * k);
        c.save(); c.translate(Math.round(s.x), Math.round(s.y)); c.rotate(Math.atan2(s.vy, s.vx));
        c.fillStyle = '#ffb53b'; c.fillRect(-L / 2 - F, -Math.ceil(H / 3), F, Math.ceil(H * .66));
        c.fillStyle = '#fff3c4'; c.fillRect(-L / 2 - Math.ceil(F / 2), -Math.ceil(H / 6), Math.ceil(F / 2), Math.max(1, Math.ceil(H / 3)));
        c.fillStyle = '#5b616c'; c.fillRect(-L / 2, -H / 2 - Math.round(k), Math.max(1, Math.round(2 * k)), H + 2 * Math.round(k));
        c.fillStyle = '#9aa0aa'; c.fillRect(-L / 2, -H / 2, L, H);
        c.fillStyle = '#d5dae2'; c.fillRect(-L / 2, -H / 2, L, Math.max(1, Math.round(H * .4)));
        c.fillStyle = '#e0452c'; c.fillRect(L / 2, -H / 2, Math.max(1, Math.round(2 * k)), H);
        c.fillRect(L / 2 + Math.max(1, Math.round(2 * k)), -Math.ceil(H / 4), Math.max(1, Math.round(k)), Math.max(1, Math.ceil(H / 2)));
        c.restore();
      } else if (s.kind === 'claw') {
        const n = Math.round(10 * z), T = wpx(1, z);
        for (let i = -1; i <= 1; i++) for (let k = 0; k < n; k++) {
          const cx0 = Math.round(s.x + i * 3 * z * -back + back * (k - n / 2) * .45 + Math.sin(k / (n - 1) * Math.PI) * -back * 1.2 * z), cy0 = Math.round(s.y - 7 * z + k * 1.4);
          c.fillStyle = s.pal[2]; c.fillRect(cx0 + back * T, cy0, T, T);
          c.fillStyle = s.pal[0]; c.fillRect(cx0, cy0, T, T);
        }
      } else if (s.kind === 'gas') {
        // A drifting cloud: puffs that swell as it travels.
        const R = s.r + 2.5 * z * Math.min(1, s.t / 500);
        c.globalAlpha = .85;
        for (let i = 0; i < 4; i++) {
          const a = i * TAU / 4 + s.t / 260, px = s.x + Math.cos(a) * R * .8, py = s.y + Math.sin(a) * R * .5;
          this.pixBall(c, px, py, R * .7, s.pal[2]); this.pixBall(c, px, py, R * .5, s.pal[1]);
        }
        this.pixBall(c, s.x, s.y, R * .45, s.pal[0]);
        c.globalAlpha = 1;
      } else if (s.kind === 'wave') {
        // Rings of a sound (or a mind's power) opening as they fly.
        const dir = Math.sign(s.vx) || 1;
        const D = wpx(2, z);
        for (let i = 0; i < 3; i++) {
          const R = (5 + i * 4 + Math.min(5, s.t / 100)) * z, cx0 = s.x - dir * i * 5 * z;
          c.fillStyle = i === 0 ? s.pal[2] : s.pal[1];
          for (let a = -1.1; a <= 1.1; a += .08 / z) c.fillRect(Math.round(cx0 + dir * Math.cos(a) * R * .55), Math.round(s.y + Math.sin(a) * R), D, D);
        }
      } else if (s.kind === 'wind') {
        // A small tornado: spinning streaks in a funnel, wide at the top.
        // Its foot stays on the ground; it grows taller and wider.
        for (let k = 0; k < 12; k++) {
          const w = (2 + k * 1.3) * z, yy = s.y + 9 - k * 2 * z;
          for (let j = 0; j < 4; j++) {
            const a = s.t / 60 + j * TAU / 4 + k * .5;
            c.fillStyle = Math.sin(a) > 0 ? s.pal[1] : s.pal[2];
            c.fillRect(Math.round(s.x + Math.cos(a) * w), Math.round(yy), wpx(3, z), wpx(2, z));
          }
        }
      } else if (s.kind === 'water') {
        // A jet from the mouth with droplets along it; it stays a moment where it lands.
        const fade = s.hold !== undefined ? Math.max(0, s.hold / 220) : 1, len = Math.abs(s.x - s.ox), dir = Math.sign(s.x - s.ox) || 1;
        c.globalAlpha = fade;
        this.pixLine(c, s.ox, s.oy, s.x, s.y, wpx(3, z), s.pal[2]); this.pixLine(c, s.ox, s.oy, s.x, s.y, wpx(1, z), s.pal[1]);
        c.fillStyle = s.pal[0];
        for (let i = 4; i < len; i += 7) c.fillRect(Math.round(s.ox + dir * i), Math.round(s.oy + (s.y - s.oy) * i / (len || 1) - 2 * z + Math.sin(i + s.t / 40) * z), wpx(1, z), wpx(1, z));
        this.pixBall(c, s.x, s.y, 2.4 * z, s.pal[1]);
        c.globalAlpha = 1;
      } else if (s.kind === 'light') {
        // A twinkling star; its glitter is left behind in update.
        const tw = (5 + Math.sin(s.t / 45) * 2) * z, T = wpx(.8, z), o = Math.floor(T / 2);
        c.fillStyle = s.pal[2];
        c.fillRect(Math.round(s.x - tw), Math.round(s.y) - o, Math.round(tw * 2 + 1), T);
        c.fillRect(Math.round(s.x) - o, Math.round(s.y - tw), T, Math.round(tw * 2 + 1));
        c.fillStyle = s.pal[1];
        c.fillRect(Math.round(s.x - tw * .5), Math.round(s.y - tw * .5), T, T); c.fillRect(Math.round(s.x + tw * .5), Math.round(s.y + tw * .5), T, T);
        c.fillRect(Math.round(s.x - tw * .5), Math.round(s.y + tw * .5), T, T); c.fillRect(Math.round(s.x + tw * .5), Math.round(s.y - tw * .5), T, T);
        this.pixBall(c, s.x, s.y, 2.4 * z, s.pal[1]); this.pixBall(c, s.x, s.y, 1.3 * z, s.pal[0]);
      } else if (s.kind === 'swarm') {
        // A flock: small fliers flapping around the group's center.
        // A bigger Digimon's flock is bigger and has more fliers.
        const n = 6 + Math.round((z - 1) * 5);
        for (let i = 0; i < n; i++) {
          const a = i * 2.4 + s.t / 180, fx = Math.round(s.x + Math.cos(a) * (4 + (i % 3) * 3) * z), fy = Math.round(s.y + Math.sin(a * 1.3) * 6 * z);
          this.drawFlier(c, fx, fy, Math.floor(s.t / 90 + i) % 2, s.pal, z);
        }
      } else if (s.kind === 'heart') {
        this.drawHeart(c, s.x, s.y + Math.sin(s.t / 90) * 1.5 * z, s.pal, wpx(2, z));
      } else if (s.kind === 'quake') {
        // A crack running along the ground with rocks hopping at its tip.
        const dir = Math.sign(s.x - s.ox) || 1, len = Math.abs(s.x - s.ox);
        const T = wpx(1, z), R = wpx(2, z);
        c.fillStyle = s.pal[2];
        for (let i = 0; i < len; i += 2) c.fillRect(Math.round(s.ox + dir * i), Math.round(s.y + ((i / 2) % 2 ? T : 0)), 2, T);
        for (let k = 0; k < 3; k++) {
          const hop = Math.abs(Math.sin(s.t / 90 + k)) * 5 * z;
          c.fillStyle = k ? s.pal[1] : s.pal[0];
          c.fillRect(Math.round(s.x - dir * k * 3 * z), Math.round(s.y - R - hop), R, R);
        }
      } else if (s.kind === 'beam') {
        const fade = s.hold !== undefined ? Math.max(0, s.hold / 220) : 1;
        c.globalAlpha = fade;
        this.pixLine(c, s.ox, s.oy, s.x, s.y, wpx(5, z), s.pal[2]);
        this.pixLine(c, s.ox, s.oy, s.x, s.y, wpx(3, z), s.pal[1]);
        this.pixLine(c, s.ox, s.oy, s.x, s.y, wpx(1, z), s.pal[0]);
        this.pixBall(c, s.ox, s.oy, 3.2 * z, s.pal[1]); this.pixBall(c, s.ox, s.oy, 1.6 * z, s.pal[0]);
        c.globalAlpha = 1;
      } else if (s.kind === 'electric') {
        // A jagged bolt, new zigzags every frame so it flickers.
        const dx = s.x - s.ox, dy = s.y - s.oy, len = Math.hypot(dx, dy) || 1, nx = -dy / len, ny = dx / len;
        const pts = [[s.ox, s.oy]];
        for (let i = 6; i < len - 3; i += 6) { const j = rand(-4, 4) * z; pts.push([s.ox + dx * i / len + nx * j, s.oy + dy * i / len + ny * j]); }
        pts.push([s.x, s.y]);
        c.globalAlpha = s.hold !== undefined ? Math.max(0, s.hold / 220) : 1;
        for (let i = 1; i < pts.length; i++) {
          this.pixLine(c, pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], wpx(3, z), s.pal[2]);
          this.pixLine(c, pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], wpx(1, z), s.pal[0]);
        }
        c.globalAlpha = 1;
      } else if (s.kind === 'melee') {
        // The shock of a punch or charge, with speed lines behind it.
        const back = -Math.sign(s.vx) || -1;
        const L = Math.round(7 * z), T = wpx(1, z);
        c.fillStyle = s.pal[1];
        for (let k = -1; k <= 1; k++) c.fillRect(Math.round(s.x + back * (5 + Math.abs(k) * 3) * z - (back < 0 ? L : 0)), Math.round(s.y + k * 3 * z), L, T);
        this.pixBall(c, s.x, s.y, 2.6 * z, s.pal[2]); this.pixBall(c, s.x, s.y, 1.4 * z, s.pal[0]);
      } else if (s.kind === 'bind') {
        // A wavy tendril from where it was thrown to its tip.
        const dir = Math.sign(s.vx) || 1, len = Math.abs(s.x - s.ox);
        const wave = i => Math.sin(i / (4.5 * z) - s.t / 55) * 2.4 * z * Math.min(1, i / 8), T = wpx(1, z);
        for (let i = 0; i <= len; i++) {
          const tx = Math.round(s.ox + dir * i), ty = Math.round(s.oy + (s.y - s.oy) * i / (len || 1) + wave(i));
          c.fillStyle = s.pal[2]; c.fillRect(tx, ty - T, 1, 2 * T + 1);
          c.fillStyle = s.pal[1]; c.fillRect(tx, ty, 1, T);
        }
        this.pixBall(c, s.x, s.y + wave(len), 2.4 * z, s.pal[2]); this.pixBall(c, s.x, s.y + wave(len), 1.2 * z, s.pal[0]);
      } else if (s.kind === 'ice') {
        const r = s.r;
        c.fillStyle = s.pal[2]; for (let dy = -r; dy <= r; dy++) { const w = Math.round((r - Math.abs(dy)) * 1.6); c.fillRect(Math.round(s.x - w), Math.round(s.y + dy), w * 2 + 1, 1); }
        const ri = r - 2 * z;
        c.fillStyle = s.pal[1]; for (let dy = -ri; dy <= ri; dy++) { const w = Math.round((ri - Math.abs(dy)) * 1.6); c.fillRect(Math.round(s.x - w), Math.round(s.y + dy), w * 2 + 1, 1); }
        c.fillStyle = s.pal[0]; c.fillRect(Math.round(s.x - back * z), Math.round(s.y - z), wpx(2, z), wpx(2, z));
      } else {
        const r = s.r + Math.sin(s.t / 40) * (s.kind === 'gaia' ? .8 : .4);
        this.pixBall(c, s.x + back * r * .8, s.y, r * .75, s.pal[2]);
        this.pixBall(c, s.x, s.y, r, s.pal[2]);
        this.pixBall(c, s.x, s.y, r * .72, s.pal[1]);
        this.pixBall(c, s.x - back * r * .15, s.y, r * .4, s.pal[0]);
      }
    }
    for (const b of this.booms) {
      const bp = b.t / (b.life || 320), z = b.size || 1;
      if (b.kind === 'missile') {
        // A fireball that swells fast, then smoke rolling up and out.
        const k = b.size || 1, R = (3 + 7 * Math.min(1, bp * 3)) * k;
        if (bp < .55) {
          c.globalAlpha = 1 - bp / .55;
          this.pixBall(c, b.x, b.y, R, '#e0452c'); this.pixBall(c, b.x, b.y, R * .72, '#ffb53b'); this.pixBall(c, b.x, b.y, R * .4, '#fff3c4');
        }
        c.globalAlpha = Math.max(0, .75 * (1 - bp));
        for (let i = 0; i < 6; i++) {
          const a = i * TAU / 6 + .4, d = R * (.55 + bp * .9);
          this.pixBall(c, b.x + Math.cos(a) * d, b.y + Math.sin(a) * d * .6 - bp * 7 * k, (1.5 + 2.5 * bp) * k, i % 2 ? '#d5d9df' : '#9aa0aa');
        }
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'gas') {
        // The cloud wraps the target, spreads and thins out.
        const R = (5 + 8 * Math.min(1, bp * 2)) * z;
        c.globalAlpha = .8 * (1 - bp);
        for (let i = 0; i < 6; i++) {
          const a = i * TAU / 6 + bp * 2, px = b.x + Math.cos(a) * R * .7, py = b.y + Math.sin(a) * R * .4;
          this.pixBall(c, px, py, R * .45, b.pal[2]); this.pixBall(c, px, py, R * .3, b.pal[1]);
        }
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'wave') {
        c.globalAlpha = 1 - bp;
        for (let k = 0; k < 2; k++) {
          const R = (4 + 12 * Math.min(1, bp * 1.6 + k * .3)) * z;
          c.fillStyle = k ? b.pal[1] : b.pal[2];
          for (let a = 0; a < TAU; a += .12 / z) c.fillRect(Math.round(b.x + Math.cos(a) * R), Math.round(b.y + Math.sin(a) * R * .8), wpx(2, z), wpx(2, z));
        }
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'wind') {
        c.globalAlpha = 1 - bp;
        for (let j = 0; j < 4; j++) {
          const a0 = j * TAU / 4 + bp * 6;
          c.fillStyle = j % 2 ? b.pal[1] : b.pal[2];
          for (let i = 0; i < 8; i++) { const a = a0 + i * .25, R = (3 + i * 1.2 + bp * 8) * z; c.fillRect(Math.round(b.x + Math.cos(a) * R), Math.round(b.y + Math.sin(a) * R * .6), wpx(1, z), wpx(1, z)); }
        }
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'water') {
        c.globalAlpha = 1 - bp;
        for (let i = 0; i < 7; i++) {
          const a = Math.PI + i * Math.PI / 6, R = (3 + 10 * bp) * z;
          c.fillStyle = i % 2 ? b.pal[0] : b.pal[1];
          c.fillRect(Math.round(b.x + Math.cos(a) * R), Math.round(b.y + Math.sin(a) * R + 12 * bp * bp * z), wpx(2, z), wpx(2, z));
        }
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'light') {
        const R = (5 + 14 * Math.min(1, bp * 2)) * z, T = wpx(.8, z);
        c.globalAlpha = 1 - bp;
        for (let a = 0; a < 8; a++) {
          const ang = a * TAU / 8;
          c.fillStyle = a % 2 ? b.pal[1] : b.pal[0];
          for (let i = 2; i < R * (a % 2 ? .6 : 1); i++) c.fillRect(Math.round(b.x + Math.cos(ang) * i), Math.round(b.y + Math.sin(ang) * i), T, T);
        }
        this.pixBall(c, b.x, b.y, (3 * (1 - bp) + 1) * z, b.pal[0]);
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'swarm') {
        c.globalAlpha = 1 - bp;
        for (let i = 0; i < 6 + Math.round((z - 1) * 5); i++) {
          const a = i * TAU / (6 + Math.round((z - 1) * 5)) + .3, R = (3 + 16 * bp) * z;
          this.drawFlier(c, Math.round(b.x + Math.cos(a) * R), Math.round(b.y + Math.sin(a) * R * .7 - 6 * bp * z), 0, b.pal, z);
        }
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'heart') {
        c.globalAlpha = 1 - bp;
        for (let k = -1; k <= 1; k++) this.drawHeart(c, b.x + k * 6 * z, b.y - (4 + bp * 12 + Math.abs(k) * 2) * z, b.pal, wpx(1, z));
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'quake') {
        // Rocks thrown up from the ground, and the crack under the target.
        const gy0 = this.ground();
        c.globalAlpha = 1 - bp * bp;
        for (let i = 0; i < 5; i++) {
          // A bigger quake throws rocks higher and wider (the same arc, `z` times as big).
          const t = bp * .48, rx = b.x + (i - 2) * 9 * t * z, ry = gy0 - 2 + ((-38 - (i % 2) * 14) * t + 140 * t * t) * z;
          c.fillStyle = i % 2 ? b.pal[1] : b.pal[2]; c.fillRect(Math.round(rx), Math.round(Math.min(ry, gy0 - 1)), wpx(2, z), wpx(2, z));
        }
        c.fillStyle = b.pal[2];
        for (let i = -8 * z; i <= 8 * z; i += 2) c.fillRect(Math.round(b.x + i), gy0 - 1 + ((Math.round(i / 2)) % 2 ? 1 : 0), 2, 1);
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'melee') {
        // An impact star: eight spikes, long and short, flung out and fading.
        const p = b.t / b.life, R = (4 + 10 * Math.min(1, p * 2.4)) * z, T = wpx(1, z), C = wpx(3, z);
        c.globalAlpha = 1 - p * p;
        for (let a = 0; a < 8; a++) {
          const ang = a * TAU / 8 + .2, len = a % 2 ? R * .55 : R;
          for (let i = 2; i < len; i++) {
            c.fillStyle = i < len * .5 ? b.pal[0] : b.pal[1];
            c.fillRect(Math.round(b.x + Math.cos(ang) * i), Math.round(b.y + Math.sin(ang) * i), T, T);
          }
        }
        c.fillStyle = b.pal[0]; c.fillRect(Math.round(b.x) - Math.floor(C / 2), Math.round(b.y) - Math.floor(C / 2), C, C);
        c.globalAlpha = 1;
        continue;
      }
      if (b.kind === 'bind') {
        // Three loops wound around the target, tightening, then fading.
        const p = b.t / b.life, squeeze = 1 - .25 * Math.min(1, p * 3);
        c.globalAlpha = p < .7 ? 1 : (1 - p) / .3;
        const rx0 = b.rx || 9, gap = b.gap || 5;
        for (let k = -1; k <= 1; k++) {
          const rx = (rx0 - Math.abs(k) * rx0 * .2) * squeeze, ry = Math.max(2.2, rx0 * .18), cy = b.y + k * gap;
          for (let a = 0; a < TAU; a += Math.min(.2, 1.2 / rx)) {
            c.fillStyle = Math.sin(a) > 0 ? b.pal[1] : b.pal[2];
            c.fillRect(Math.round(b.x + Math.cos(a) * rx), Math.round(cy + Math.sin(a) * ry), 1, 1);
          }
        }
        c.globalAlpha = 1;
        continue;
      }
      const p = b.t / 320, R = b.r * (1 + 1.8 * p);
      c.globalAlpha = 1 - p;
      this.pixBall(c, b.x, b.y, R, b.pal[2]); this.pixBall(c, b.x, b.y, R * .65, b.pal[1]); this.pixBall(c, b.x, b.y, R * .3, b.pal[0]);
      c.globalAlpha = 1;
    }
    for (const z of this.zs) {
      const p = z.t / z.life, u = 1 + p * .6, zx = z.x + z.dir * 6 * p, zy = z.y - 12 * p;
      const glyph = (ox, oy) => { c.fillRect(zx + ox, zy + oy, 5 * u, u); c.fillRect(zx + ox + 3 * u, zy + oy + u, u, u); c.fillRect(zx + ox + 2 * u, zy + oy + 2 * u, u, u); c.fillRect(zx + ox + u, zy + oy + 3 * u, u, u); c.fillRect(zx + ox, zy + oy + 4 * u, 5 * u, u); };
      c.globalAlpha = 1 - p;
      if (desk) { c.fillStyle = 'rgba(0,0,0,.45)'; glyph(.5, .5); c.fillStyle = '#ffffff'; }
      else c.fillStyle = dark ? '#dfe3ee' : '#3a3f52';
      glyph(0, 0);
    }
    c.globalAlpha = 1;
    if (this.excl > 0) {
      const ex = Math.round(cx), ey = Math.round(gy - this.y - hgt - 12);
      if (desk) { c.fillStyle = 'rgba(0,0,0,.45)'; c.fillRect(ex - .5, ey + .5, 2, 6); c.fillRect(ex - .5, ey + 8.5, 2, 2); }
      c.fillStyle = '#e0452c'; c.fillRect(ex - 1, ey, 2, 6); c.fillRect(ex - 1, ey + 8, 2, 2);
    }
    for (const p of this.parts) { c.globalAlpha = 1 - p.t / p.life; c.fillStyle = p.c; c.fillRect(p.x, p.y, p.s, p.s); }
    c.globalAlpha = 1;
    if (!desk && this.flash > 0) { c.fillStyle = `rgba(255,255,250,${this.flash})`; c.fillRect(0, 0, W, H); }
    if (this.callout) this.drawCallout(c, cx, gy - this.y - hgt, dark);
    else if (this.note) this.drawNote(c, cx, gy - this.y - hgt, dark);
    else if (this.working && this.state !== 'sleep') this.drawBusy(c, cx, gy - this.y - hgt - 9, dark);
  }
  // Three dots over the head while a coding agent works; one at a time is lit.
  drawBusy(c, x, y, dark) {
    const lit = Math.floor(performance.now() / 320) % 3, desk = this.desk;
    for (let i = 0; i < 3; i++) {
      const dx = Math.round(x) - 5 + i * 4, dy = Math.round(y);
      if (desk) { c.fillStyle = 'rgba(0,0,0,.45)'; c.fillRect(dx + .5, dy + .5, 2, 2); }
      c.fillStyle = i === lit ? (desk || !dark ? '#ffffff' : '#f1f2f5') : (desk || !dark ? 'rgba(255,255,255,.55)' : 'rgba(241,242,245,.4)');
      if (!desk && !dark) c.fillStyle = i === lit ? '#3a3f52' : 'rgba(58,63,82,.35)';
      c.fillRect(dx, dy, 2, 2);
    }
  }
  // A lasting bubble for a coding agent (waiting for input, or done). Shortened to fit the view.
  drawNote(c, headX, headY, dark) {
    const sc = this.scale, desk = this.desk, light = desk || !dark, fs = 12;
    c.setTransform(DPR, 0, 0, DPR, 0, 0);
    c.font = `600 ${fs}px -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, sans-serif`;
    let text = this.note;
    const maxW = this.cssW - 26;
    if (c.measureText(text).width > maxW) {
      while (text.length > 1 && c.measureText(text + '…').width > maxW) text = text.slice(0, -1);
      text += '…';
    }
    const bw = c.measureText(text).width + 18, bh = fs + 10, ax = headX * sc;
    const bx = Math.max(4, Math.min(this.cssW - bw - 4, ax - bw / 2)), by = Math.max(2, (headY - 6) * sc - bh - 8);
    const tx = Math.max(bx + 12, Math.min(bx + bw - 12, ax));
    c.save();
    c.fillStyle = light ? '#ffffff' : '#2c2d33'; c.strokeStyle = light ? 'rgba(0,0,0,.18)' : 'rgba(255,255,255,.16)'; c.lineWidth = 1;
    c.beginPath(); c.roundRect(bx, by, bw, bh, 8); c.fill(); c.stroke();
    c.beginPath(); c.moveTo(tx - 5, by + bh - 1); c.lineTo(tx, by + bh + 6); c.lineTo(tx + 5, by + bh - 1); c.closePath(); c.fill();
    c.beginPath(); c.moveTo(tx - 5, by + bh); c.lineTo(tx, by + bh + 6); c.lineTo(tx + 5, by + bh); c.stroke();
    c.fillStyle = light ? '#1c1d21' : '#f1f2f5'; c.textAlign = 'center'; c.textBaseline = 'middle';
    c.fillText(text, bx + bw / 2, by + bh / 2 + .5);
    c.restore();
  }
  drawCallout(c, headX, headY, dark) {
    const co = this.callout, p = co.t / co.life, sc = this.scale, desk = this.desk;
    const pop = co.t < 160 ? .55 + .5 * Math.sin(Math.PI / 2 * co.t / 160) : (co.t < 240 ? 1.05 - .05 * (co.t - 160) / 80 : 1);
    const alpha = p > .8 ? (1 - p) / .2 : 1;
    const light = desk || !dark, fs = desk ? 13 : 12.5;
    c.setTransform(DPR, 0, 0, DPR, 0, 0);
    c.font = `700 ${fs}px -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, sans-serif`;
    const bw = c.measureText(co.text).width + 18, bh = fs + 10;
    const ax = headX * sc;
    const bx = Math.max(4, Math.min(this.cssW - bw - 4, ax - bw / 2)), by = Math.max(2, (headY - 6) * sc - bh - 8);
    const tx = Math.max(bx + 12, Math.min(bx + bw - 12, ax));
    c.save(); c.globalAlpha = alpha;
    c.translate(tx, by + bh); c.scale(pop, pop); c.translate(-tx, -(by + bh));
    c.fillStyle = light ? '#ffffff' : '#2c2d33'; c.strokeStyle = light ? 'rgba(0,0,0,.18)' : 'rgba(255,255,255,.16)'; c.lineWidth = 1;
    c.beginPath(); c.roundRect(bx, by, bw, bh, bh / 2); c.fill(); c.stroke();
    c.beginPath(); c.moveTo(tx - 5, by + bh - 1); c.lineTo(tx, by + bh + 6); c.lineTo(tx + 5, by + bh - 1); c.closePath(); c.fill();
    c.beginPath(); c.moveTo(tx - 5, by + bh); c.lineTo(tx, by + bh + 6); c.lineTo(tx + 5, by + bh); c.stroke();
    c.fillStyle = light ? '#1c1d21' : '#f1f2f5'; c.textAlign = 'center'; c.textBaseline = 'middle';
    c.fillText(co.text, bx + bw / 2, by + bh / 2 + .5);
    c.restore();
  }
}

// ---------- bridge ----------
const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.app;
const post = m => { if (native) native.postMessage(m); };
const cv = document.getElementById('cv');
let pet = null;

function startPet() {
  if (pet || !S.key || !assets[S.key]) return;
  pet = new Pet(cv, {desk: VIEW === 'desk', hopH: 14, speed: VIEW === 'desk' ? 26 : 30, key: S.key});
  if (S.sleeping) pet.sleep();
  if (S.agent) pet.setAgent(Object.assign({}, S.agent, {react: null}));
}

window.app = {
  sprite(key, uri) { addSprite(key, uri).then(startPet); },
  apply(s) {
    S = Object.assign({}, S, s);
    if (!pet) { startPet(); return; }
    if (pet.state !== 'evolve') pet.setNow(S.key);
    if (S.sleeping) pet.sleep(); else pet.wake();
  },
  cmd(c) {
    if (c.type === 'evolve') { whenAsset(c.key, () => { if (pet) pet.evolve(c.key); }); return; }
    if (c.type === 'battle') { whenAsset(c.foe, () => { if (pet) pet.duel(c); }); return; }
    if (c.type === 'jogress') { whenAsset(c.partner, () => { if (pet) pet.merge(c); }); return; }
    // Agent state is kept, so a pet created later (sprite still loading) shows it too.
    if (c.type === 'agent') { S.agent = c; if (pet) pet.setAgent(c); return; }
    if (!pet) return;
    if (c.type === 'feed') { if (pet.state === 'sleep') pet.wake(); setTimeout(() => pet.feed(), pet.state === 'hop' ? 500 : 0); }
    else if (c.type === 'jump') pet.jump();
    else if (c.type === 'notice') pet.notice();
    else if (c.type === 'graduate') pet.graduate();

    else if (c.type === 'attack') pet.attack();
    else if (c.type === 'grab') pet.grab();
    else if (c.type === 'drag') pet.dragMove(c.dx || 0);
    else if (c.type === 'drop') pet.drop();
  },
};

COIN = makeCoin();
if (VIEW === 'popover') cv.addEventListener('click', () => { if (!pet) return; if (pet.state === 'sleep') pet.wake(); else pet.attack(); });
window.addEventListener('resize', () => { if (pet) pet.resize(); });
// About 30 frames a second is plenty for pixel art and halves the work of a 60 Hz loop.
let last = performance.now(), lastRect = null, lastRectT = 0;
function loop(now) {
  requestAnimationFrame(loop);
  if (!pet || now - last < 30) return;
  const dt = now - last; last = now;
  pet.update(dt); pet.draw();
  if (VIEW === 'desk' && now - lastRectT > 100) {
    // Where the pet is, so the app can let clicks through everywhere else (top-left origin, pt).
    const b = assets[pet.key].bb, sc = pet.scale, w = b.r - b.l, h = b.b - b.t;
    const r = {x: (pet.x + b.l) * sc, y: (pet.ground() - pet.y - h) * sc, w: w * sc, h: (h + pet.y + 3) * sc};
    if (!lastRect || Math.abs(r.x - lastRect.x) + Math.abs(r.y - lastRect.y) + Math.abs(r.w - lastRect.w) + Math.abs(r.h - lastRect.h) > 1) {
      post({cmd: 'petRect', ...r}); lastRect = r; lastRectT = now;
    }
  }
}
requestAnimationFrame(loop);
post({cmd: 'ready'});
</script>
</body>
</html>
"""#
}
