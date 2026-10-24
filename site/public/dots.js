// nextshot.dev background: a grid of faint mint dots.
//
// The dots undulate slowly at rest. Under the pointer they brighten and part a
// little, a moving pointer leaves soft ripples, and a click or tap sends a ring
// across the grid. One canvas and no libraries. The animation runs at full rate
// only while something moves, slows to 20 frames per second at rest, and stops
// while the tab is hidden. People who ask for reduced motion get a still grid.
(() => {
  "use strict";
  const canvas = document.getElementById("dots");
  const ctx = canvas && canvas.getContext && canvas.getContext("2d");
  if (!ctx) return;
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");

  const GAP = 24; // CSS pixels between dots
  const SIZE = 4.2; // sprite size at rest; its bright core is about 1.6 pixels
  const BASE = 0.085; // dot opacity at rest
  const WAVE = 0.05; // extra opacity from the slow undulation
  const REACH = 170; // pointer reach, CSS pixels
  const PUSH = 7; // how far the pointer parts the dots, CSS pixels
  const SPEED = 560; // ripple speed, CSS pixels per second
  const BAND = 34; // ripple ring width, CSS pixels
  const LIFE = 2.2; // ripple life, seconds
  const LIFT = 6; // how far a ring lifts the dots outward, CSS pixels
  const MAX_RIPPLES = 10;
  const REST_MS = 700; // the pointer counts as resting after this long

  let w = 0;
  let h = 0;
  let dpr = 1;
  let gx = new Float32Array(0);
  let gy = new Float32Array(0);
  let sprite = null;
  const ripples = [];
  const ptr = { x: 0, y: 0, sx: 0, sy: 0, seen: false, energy: 0, lastMove: -1e9, trailX: 0, trailY: 0, lastTrail: 0 };
  const start = performance.now();
  let pending = false;
  let idleTimer = 0;
  let lastFrame = 0;

  // One soft dot, drawn once and stamped for every grid point.
  function makeSprite() {
    const px = Math.ceil(24 * dpr);
    const c = document.createElement("canvas");
    c.width = px;
    c.height = px;
    const g = c.getContext("2d");
    const r = px / 2;
    const grad = g.createRadialGradient(r, r, 0, r, r, r);
    grad.addColorStop(0, "rgba(214, 255, 249, 1)");
    grad.addColorStop(0.28, "rgba(143, 243, 228, 0.95)");
    grad.addColorStop(0.5, "rgba(60, 205, 190, 0.28)");
    grad.addColorStop(1, "rgba(60, 205, 190, 0)");
    g.fillStyle = grad;
    g.fillRect(0, 0, px, px);
    return c;
  }

  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = window.innerWidth;
    h = window.innerHeight;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    sprite = makeSprite();
    // A centered grid with a margin of half a gap on each side.
    const cols = Math.ceil(w / GAP) + 1;
    const rows = Math.ceil(h / GAP) + 1;
    const ox = ((w - (cols - 1) * GAP) / 2);
    const oy = ((h - (rows - 1) * GAP) / 2);
    gx = new Float32Array(cols * rows);
    gy = new Float32Array(cols * rows);
    let i = 0;
    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        gx[i] = ox + col * GAP;
        gy[i] = oy + row * GAP;
        i++;
      }
    }
  }

  function draw(t, now) {
    ctx.clearRect(0, 0, w, h);
    const reach2 = REACH * REACH;
    const near = ptr.seen && ptr.energy > 0.01;
    for (const r of ripples) {
      const age = (now - r.born) / 1000;
      r.radius = age * SPEED;
      r.fade = r.amp * (1 - age / LIFE) * (1 - age / LIFE);
    }
    for (let i = 0; i < gx.length; i++) {
      const x = gx[i];
      const y = gy[i];
      // Two slow, crossing waves make the resting grid undulate.
      let a = BASE + WAVE * (0.5 + 0.5 * Math.sin(x * 0.011 + y * 0.006 + t * 0.55) * Math.sin(y * 0.012 - x * 0.004 - t * 0.37));
      let dx = 0;
      let dy = 0;
      let boost = 0;
      if (near) {
        const ex = x - ptr.sx;
        const ey = y - ptr.sy;
        const d2 = ex * ex + ey * ey;
        if (d2 < reach2) {
          const d = Math.sqrt(d2) || 1;
          const k = 1 - d / REACH;
          const kk = k * k * ptr.energy;
          boost += kk * 0.9;
          dx += (ex / d) * PUSH * kk;
          dy += (ey / d) * PUSH * kk;
        }
      }
      for (const r of ripples) {
        const ex = x - r.x;
        const ey = y - r.y;
        const d = Math.sqrt(ex * ex + ey * ey) || 1;
        const off = (d - r.radius) / BAND;
        if (off > -3 && off < 3) {
          const band = Math.exp(-off * off) * r.fade;
          boost += band;
          dx += (ex / d) * LIFT * band;
          dy += (ey / d) * LIFT * band;
        }
      }
      a += boost * 0.42;
      if (a > 0.75) a = 0.75;
      const s = SIZE * (1 + Math.min(boost, 1.5) * 0.7);
      ctx.globalAlpha = a;
      ctx.drawImage(sprite, x + dx - s / 2, y + dy - s / 2, s, s);
    }
    ctx.globalAlpha = 1;
  }

  function frame(now) {
    pending = false;
    if (reduced.matches) return; // a frame queued before the switch to a still grid
    const dt = Math.min(0.05, (now - (lastFrame || now)) / 1000);
    lastFrame = now;
    // The drawn pointer eases toward the real one, so the dots follow smoothly.
    const ease = Math.min(1, dt * 9);
    ptr.sx += (ptr.x - ptr.sx) * ease;
    ptr.sy += (ptr.y - ptr.sy) * ease;
    const moving = now - ptr.lastMove < REST_MS;
    const target = moving ? 1 : 0;
    ptr.energy += (target - ptr.energy) * Math.min(1, dt * (moving ? 5 : 1.1));
    for (let i = ripples.length - 1; i >= 0; i--) {
      if ((now - ripples[i].born) / 1000 >= LIFE) ripples.splice(i, 1);
    }
    draw((now - start) / 1000, now);
    if (ripples.length || ptr.energy > 0.01) schedule();
    else idleTimer = window.setTimeout(schedule, 50);
  }

  function schedule() {
    window.clearTimeout(idleTimer);
    if (pending) return;
    pending = true;
    window.requestAnimationFrame(frame);
  }

  function addRipple(x, y, amp) {
    ripples.push({ x, y, amp, born: performance.now(), radius: 0, fade: amp });
    if (ripples.length > MAX_RIPPLES) ripples.shift();
  }

  function onMove(e) {
    ptr.x = e.clientX;
    ptr.y = e.clientY;
    if (!ptr.seen) {
      ptr.seen = true;
      ptr.sx = ptr.x;
      ptr.sy = ptr.y;
      ptr.trailX = ptr.x;
      ptr.trailY = ptr.y;
    }
    const now = performance.now();
    ptr.lastMove = now;
    // A moving pointer leaves a soft ripple about every 110 pixels.
    const mx = ptr.x - ptr.trailX;
    const my = ptr.y - ptr.trailY;
    if (mx * mx + my * my > 110 * 110 && now - ptr.lastTrail > 160) {
      addRipple(ptr.x, ptr.y, 0.28);
      ptr.trailX = ptr.x;
      ptr.trailY = ptr.y;
      ptr.lastTrail = now;
    }
    schedule();
  }

  function onDown(e) {
    onMove(e);
    addRipple(e.clientX, e.clientY, 1);
    schedule();
  }

  function onLeave(e) {
    if (!e.relatedTarget) ptr.lastMove = -1e9;
  }

  function onResize() {
    resize();
    if (reduced.matches) draw(0, performance.now());
    else schedule();
  }

  function setMode() {
    window.clearTimeout(idleTimer);
    ripples.length = 0;
    if (reduced.matches) {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerdown", onDown);
      ptr.energy = 0;
      draw(0, performance.now());
    } else {
      window.addEventListener("pointermove", onMove, { passive: true });
      window.addEventListener("pointerdown", onDown, { passive: true });
      schedule();
    }
  }

  resize();
  window.addEventListener("resize", onResize);
  window.addEventListener("pointerout", onLeave);
  if (reduced.addEventListener) reduced.addEventListener("change", setMode);
  setMode();
})();
