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
let S = {key: null, line: 'agumon', stage: 0, sleeping: false, lang: 'ko'};

// Move names: Korean from the official Korean Digimon reference (digimon.net/reference_ko),
// English from the Japanese originals. Species without an entry use a plain attack.
const MOVES = {
  agumon: {ko: '꼬마 불꽃', en: 'Baby Flame', kind: 'fire'},
  greymon: {ko: '메가파이어', en: 'Mega Flame', kind: 'fire'},
  metalgreymon: {ko: '기가 디스트로이어', en: 'Giga Destroyer', kind: 'missile'},
  wargreymon: {ko: '가이아 포스', en: 'Gaia Force', kind: 'gaia'},
  gabumon: {ko: '쁘띠 파이어', en: 'Petit Fire', kind: 'fire'},
  garurumon: {ko: '푸른화염포', en: 'Fox Fire', kind: 'fire'},
  weregarurumon: {ko: '카이저 네일', en: 'Kaiser Nail', kind: 'claw'},
  metalgarurumon: {ko: '코큐토스 브레스', en: 'Cocytus Breath', kind: 'ice'},
};
const moveOf = key => {
  const m = MOVES[key];
  if (m) return {name: S.lang === 'ko' ? m.ko : m.en, kind: m.kind};
  return {name: S.lang === 'ko' ? '공격' : 'Attack', kind: 'fire'};
};
// Colors per attack shape (center -> outside)
const PAL = {
  fire_agumon: ['#fff6c2', '#ffb53b', '#e8461e'], fire_gabumon: ['#eaffff', '#79d6ff', '#2a6fe0'],
  missile: ['#fff3c4', '#ffb53b', '#e0452c'],
  gaia: ['#fff3c4', '#ff8a2a', '#c92a1a'],
  claw: ['#ffffff', '#c9f1ff', '#6fb7ff'],
  ice: ['#ffffff', '#c7f3ff', '#59b4ff'],
};
// Timing per attack shape: [charge, release, recover] (ms)
const TIMING = {fire: [240, 100, 360], missile: [260, 100, 380], gaia: [560, 120, 420], claw: [200, 120, 380], ice: [260, 160, 380]};
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
  assets[key] = {img, sil: [silhouette(img, '#262a36'), silhouette(img, '#f1f3fa')], bb: bboxOf(img)};
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
  fire(kind, n = 0) {
    const b = this.bb(), f = this.facing, h = b.b - b.t, st = Math.max(1, S.stage - 2);
    let mx = (f < 0 ? this.x + b.l : this.x + b.r) + this.lean, my = this.ground() - this.y - h * .66;
    let speed = 110 + st * 12, r = 2.6 + st, pal = PAL['fire_' + S.line] || PAL.fire_agumon;
    if (kind === 'missile') { my = this.ground() - this.y - h * (.5 - n * .12); speed = 150; r = 3; pal = PAL.missile; }
    if (kind === 'gaia') { mx = this.x + (b.l + b.r) / 2 + f * 4; my = this.ground() - this.y - h - 9; speed = 95; r = 9; pal = PAL.gaia; }
    if (kind === 'claw') { my = this.ground() - this.y - h * .5; speed = 170; r = 6; pal = PAL.claw; }
    if (kind === 'ice') { speed = 135; r = 5; pal = PAL.ice; }
    const vx = f * speed;
    let vy = 0;
    const g = this.bug;
    if (g && !g.dead && Math.sign(g.x + 5 - mx) === f) vy = (this.ground() - 4 - my) / (Math.abs(g.x + 5 - mx) / Math.abs(vx));
    this.shots.push({kind, x: mx, y: my, vx, vy, r, pal, t: 0});
    for (let i = 0; i < 6; i++) this.parts.push({x: mx, y: my, vx: f * rand(10, 40), vy: rand(-25, 10), t: 0, life: rand(250, 450), c: pal[1], s: 1});
  }
  boom(x, y, s) {
    if (s.kind === 'gaia') this.flash = Math.max(this.flash, .45);
    this.booms.push({x, y, t: 0, r: s.r * (s.kind === 'gaia' ? 1.3 : 1), pal: s.pal});
    for (let i = 0; i < 12; i++) { const a = TAU * i / 12, sp = rand(20, 55); this.parts.push({x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 8, t: 0, life: rand(300, 600), c: s.pal[i % 3], s: Math.random() < .4 ? 2 : 1}); }
  }
  spawnBug() {
    const fromLeft = Math.random() < .5;
    this.bug = {x: fromLeft ? -12 : this.worldW + 1, dir: fromLeft ? 1 : -1, t: 0, dead: false, noticed: false};
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
    const walk = this.desk ? .58 : .5;
    if (r < walk) this.startWalk();
    else if (r < walk + .17) { this.facing = -this.facing; this.enter('idle', {dur: rand(900, 1800)}); }
    else if (r < walk + .29) this.enter('stretch', {dur: 1100});
    else if (r < walk + .38) this.enter('hop', {h: this.hopH});
    else this.enter('idle');
  }
  startWalk() {
    const b = this.bb(), minX = -b.l + 2, maxX = this.worldW - b.r - 2;
    if (maxX - minX < 8) { this.enter('idle'); return; }
    let tx = this.x;
    for (let i = 0; i < 10; i++) { tx = rand(minX, maxX); if (Math.abs(tx - this.x) >= Math.min(30, (maxX - minX) / 2)) break; }
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
    if (this.excl > 0) this.excl -= dt;
    this.zs = this.zs.filter(z => (z.t += dt) < z.life);
    this.parts = this.parts.filter(p => { p.t += dt; p.x += p.vx * dt / 1000; p.y += p.vy * dt / 1000; p.vy += 60 * dt / 1000; return p.t < p.life; });
    this.shots = this.shots.filter(s => {
      s.t += dt; s.x += s.vx * dt / 1000; s.y += s.vy * dt / 1000;
      const back = -Math.sign(s.vx);
      if (s.kind === 'missile') {
        if (Math.random() < .9) this.parts.push({x: s.x + back * 5, y: s.y + rand(-.5, .5), vx: back * rand(4, 12), vy: rand(-8, -2), t: 0, life: rand(300, 550), c: Math.random() < .3 ? '#ffb53b' : (Math.random() < .5 ? '#c8ccd4' : '#9aa0aa'), s: Math.random() < .5 ? 2 : 1});
      } else if (s.kind === 'ice') {
        for (let i = 0; i < 2; i++) this.parts.push({x: s.x + back * rand(0, s.r * 1.5), y: s.y + rand(-s.r, s.r), vx: s.vx * .1, vy: rand(-6, 6), t: 0, life: rand(250, 500), c: Math.random() < .5 ? '#ffffff' : '#c7f3ff', s: Math.random() < .5 ? 2 : 1});
      } else if (s.kind !== 'claw') {
        for (let i = 0; i < (s.kind === 'gaia' ? 2 : 1); i++) if (Math.random() < .75) this.parts.push({x: s.x + back * s.r * .7 + rand(-1, 1), y: s.y + rand(-s.r * .5, s.r * .5), vx: -s.vx * .05, vy: rand(-14, -4), t: 0, life: rand(200, 380), c: s.pal[Math.random() < .5 ? 1 : 2], s: 1});
      }
      const g = this.bug;
      if (g && !g.dead && Math.hypot(s.x - (g.x + 5.5), s.y - (this.ground() - 4)) < s.r + 6) {
        this.boom(s.x, s.y, s); g.dead = true; g.t = 0; post({cmd: 'bugDefeated'}); return false;
      }
      if (s.x < 3 || s.x > this.worldW - 3 || s.y > this.ground()) { this.boom(s.x, Math.min(s.y, this.ground() - 2), s); return false; }
      return true;
    });
    this.booms = this.booms.filter(b => (b.t += dt) < 320);
    if (this.callout && (this.callout.t += dt) > this.callout.life) this.callout = null;
    if (this.bug) {
      const g = this.bug; g.t += dt;
      if (g.dead) { if (g.t > 300) this.bug = null; }
      else if (this.state !== 'held') {
        g.x += g.dir * 14 * dt / 1000;
        const b = this.bb(), petL = this.x + b.l, petR = this.x + b.r;
        if (g.dir > 0 && g.x + 11 > petL - 4 && g.x < petR) g.x = petL - 15;
        if (g.dir < 0 && g.x < petR + 4 && g.x + 11 > petL) g.x = petR + 4;
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
          else { this.lean = -f * 1.4 * p; this.sway = 1.6 * p; this.sy = 1 - .08 * p; this.sx = 1 + .05 * p; }
        } else if (t < t2) {
          const p = (t - t1) / s1;
          if (k === 'claw') { this.lean = f * (-1.2 + 7 * p); this.sx = 1.08; this.sy = .96; }
          else if (k === 'gaia') { this.lean = f * 2.5 * p; this.sway = -3 * p; this.sy = 1.08 - .12 * p; this.y = 1.5 * (1 - p); }
          else { this.lean = f * (-1.4 + 3.6 * p); this.sway = 1.6 - 4 * p; this.sy = .92 + .12 * p; this.sx = 1.05 - .07 * p; }
          if (!d.fired) { d.fired = true; d.ft = t; this.fire(k, 0); }
        } else if (t < t2 + rc) {
          const e = 1 - easeIO((t - t2) / rc);
          this.lean = f * (k === 'claw' ? 5.8 : 2.2) * e; this.sway = (k === 'claw' ? 0 : -2.4) * e; this.sy = 1 + .04 * e;
        } else this.enter('idle', {dur: rand(700, 1500)});
        if (k === 'missile' && d.fired && !d.fired2 && t - d.ft >= 130) { d.fired2 = true; this.fire('missile', 1); }
        break; }
      case 'wobble': { const p = this.t / d.dur; this.rot = .16 * Math.sin(this.t / 70) * (1 - p); if (p >= 1) this.enter('idle'); break; }
      case 'stretch': { const p = Math.min(1, this.t / d.dur); this.breath = .03 + .13 * Math.sin(Math.PI * p); this.sx = 1 - .03 * Math.sin(Math.PI * p); if (p >= 1) this.enter('idle', {dur: rand(900, 2000)}); break; }
      case 'turn': idleBreath(); if (this.t >= 260) this.enter('walk', {x0: this.x, tx: d.tx, dir: d.dir}); break;
      case 'walk': {
        if (!d.dur) d.dur = Math.abs(d.tx - d.x0) / this.speed * 1000 + 400;
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
      const g = this.bug, bx = Math.round(g.x), by = Math.round(gy - 7);
      c.fillStyle = desk ? 'rgba(0,0,0,.2)' : 'rgba(60,50,30,.12)';
      c.beginPath(); c.ellipse(bx + 5.5, gy + .5, 5, 1.4, 0, 0, TAU); c.fill();
      BUG[Math.floor(g.t / 140) % 2].forEach((row, r) => [...row].forEach((v, col) => { if (v !== '.') { c.fillStyle = BUG_C[v]; c.fillRect(bx + col, by + r, 1, 1); } }));
    }
    if (this.chip) {
      const ch = this.chip, rem = Math.min(12, ch.bites * 4);
      c.save();
      if (ch.shrink) { const k = 1 - ch.shrink; c.translate(ch.x + 6, ch.y + 6); c.scale(k, k); c.translate(-ch.x - 6, -ch.y - 6); }
      if (rem < 12) { if (ch.fromRight) c.drawImage(COIN, 0, 0, 12 - rem, 12, ch.x, ch.y, 12 - rem, 12); else c.drawImage(COIN, rem, 0, 12 - rem, 12, ch.x + rem, ch.y, 12 - rem, 12); }
      c.restore();
    }
    c.save();
    c.translate(cx, gy - this.y);
    if (this.rot) c.rotate(this.rot);
    c.scale(this.flipX * this.sx, this.sy);
    this.blit(c, img, bb, -(bb.l + bb.r) / 2);
    if (desk && this.dim > 0 && !evolving) { c.globalAlpha = .35 * this.dim; this.blit(c, A.sil[0], bb, -(bb.l + bb.r) / 2); c.globalAlpha = 1; }
    c.restore();

    if (!desk && this.dim > 0) { c.fillStyle = `rgba(12,16,34,${.38 * this.dim})`; c.fillRect(0, 0, W, H); }
    if (this.state === 'attack' && this.d.kind === 'gaia' && !this.d.fired) {
      const p = easeIO(Math.min(1, this.t / TIMING.gaia[0])), r = 9 * p + Math.sin(this.t / 30) * .5 * p;
      const bx = cx + this.facing * 4, by = gy - this.y - hgt - 9;
      if (r > .8) { this.pixBall(c, bx, by, r, PAL.gaia[2]); this.pixBall(c, bx, by, r * .7, PAL.gaia[1]); this.pixBall(c, bx, by, r * .35, PAL.gaia[0]); }
    }
    for (const s of this.shots) {
      const back = -Math.sign(s.vx);
      if (s.kind === 'missile') {
        c.save(); c.translate(s.x, s.y); c.rotate(Math.atan2(s.vy, s.vx));
        c.fillStyle = '#ffb53b'; c.fillRect(-6, -.5, 2, 1);
        c.fillStyle = '#5b616c'; c.fillRect(-4, -1.5, 1, 3);
        c.fillStyle = '#d5dae2'; c.fillRect(-4, -1, 6, 2);
        c.fillStyle = '#e0452c'; c.fillRect(2, -1, 2, 2);
        c.restore();
      } else if (s.kind === 'claw') {
        for (let i = -1; i <= 1; i++) for (let k = 0; k < 10; k++) {
          const px = Math.round(s.x + i * 3 * -back + back * (k - 5) * .45 + Math.sin(k / 9 * Math.PI) * -back * 1.2), py = Math.round(s.y - 7 + k * 1.4);
          c.fillStyle = s.pal[2]; c.fillRect(px + back, py, 1, 1);
          c.fillStyle = s.pal[0]; c.fillRect(px, py, 1, 1);
        }
      } else if (s.kind === 'ice') {
        const r = s.r;
        c.fillStyle = s.pal[2]; for (let dy = -r; dy <= r; dy++) { const w = Math.round((r - Math.abs(dy)) * 1.6); c.fillRect(Math.round(s.x - w), Math.round(s.y + dy), w * 2 + 1, 1); }
        c.fillStyle = s.pal[1]; for (let dy = -(r - 2); dy <= r - 2; dy++) { const w = Math.round((r - 2 - Math.abs(dy)) * 1.6); c.fillRect(Math.round(s.x - w), Math.round(s.y + dy), w * 2 + 1, 1); }
        c.fillStyle = s.pal[0]; c.fillRect(Math.round(s.x - back), Math.round(s.y - 1), 2, 2);
      } else {
        const r = s.r + Math.sin(s.t / 40) * (s.kind === 'gaia' ? .8 : .4);
        this.pixBall(c, s.x + back * r * .8, s.y, r * .75, s.pal[2]);
        this.pixBall(c, s.x, s.y, r, s.pal[2]);
        this.pixBall(c, s.x, s.y, r * .72, s.pal[1]);
        this.pixBall(c, s.x - back * r * .15, s.y, r * .4, s.pal[0]);
      }
    }
    for (const b of this.booms) {
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
    if (!pet) return;
    if (c.type === 'feed') { if (pet.state === 'sleep') pet.wake(); setTimeout(() => pet.feed(), pet.state === 'hop' ? 500 : 0); }
    else if (c.type === 'jump') pet.jump();
    else if (c.type === 'notice') pet.notice();
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
