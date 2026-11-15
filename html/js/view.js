/* ============================================
   Whiplash 3D — the scene
   ============================================
   Turns app.js's model into three.js objects. The layout is a flat page's, on purpose: a rail of
   cards along the bottom, the picker as a column on the left, the tally top right, dialogs in the
   middle. What 3D adds: cards are blocks of glass in one flat row (lined up as on a page, but with
   thickness, a clear coat and a shadow) that deal in when a level opens and lift toward the cursor;
   the column stands flat beside them; keys press in; dialogs swing up over a dimmed scene. Paint swatches
   stay flat chips.

   Objects are kept by id between frames, so a state change animates instead of redrawing. */

import {
    THREE, Stage, Spring, Label, Disc, FlatSwatch, Shadow, Pointer, hit,
    glassMaterial, setFill, basicMaterial, slabGeometry, rectGeometry, ringGeometry,
    text, measure, wrap, wrapLines, roundRect, kbd, COL, FILL, NEUTRAL, H, wake, startLoop, loadFonts, afterFonts, onFrame, loopDebug,
} from './kit.js';

/* ---- layout, in D (1440p pixels) ---------------------------------------------------------------- */

const M = 52;                                  // screen margin
const CARD_W = 380, CARD_GAP = 26, PITCH = CARD_W + CARD_GAP;
const RAIL_X = 56;
const CARD_H = [308, 188, 216, 236];           // by level: counter, shelves, categories, parts
const RAIL_BOTTOM = H - 132;
const HOVER_LEAN = 0.6;                        // how far a hovered card leans to the cursor (of its full tilt)
const COL_W = 576, COL_H = H - 2 * M;
const COL_TILT = 0;                            // flat with the cards (it used to turn 7 degrees toward the car)
const ROW_W = 544;
const ORDER = { rail: 10, crumbs: 40, col: 100, tally: 150, dim: 300, dlg: 310 };

/* A card's art (wheel rims, the shelves' turbo, paint bucket and dyno sheet) is printed into the card's glass itself,
   in black and white: a picture centred at (x, y) as shares of the card, `size` times the card's height tall (its own
   aspect across), cut off at the card's edges and faded under the text side. Being the glass's own colour, it has the
   card's opacity and catches the same light. A card's `art` is a picture path (the rim placement below) or
   { src, x, y, size, lift, color } (lift: a brightness factor for dark pictures; color: print it in colour, for the
   parts painted in the palette's yellow). */
const ART = { x: 0.82, y: 0.66, size: 1.3 };
// The cards' colour: Rally Blue (the other panels keep smoked #0a0c12).
// Printed cards are a gradient, top to bottom; plain cards show the middle of it lit from within.
// Category cards (the name at the top) carry the livery: a wide and a thin yellow band across the bottom-left corner,
// [from, to] in px out from the corner along LIVERY_DIR (into the card, up and to the right).
const CARD_TOP = '#1c52b8', CARD_BOTTOM = '#0d2c74', CARD_DARK = new THREE.Color('#143f96');
const LIVERY = '#ffd200', LIVERY_BANDS = [[40, 62], [67, 72]], LIVERY_DIR = [0.57, 0.82];
const ART_GLOW = 0.95, ART_LIT = 0.15;           // a printed card: the picture's self-light and its lit share
// The cards' wallpaper: the Tuners Auto Shop's blue gorilla wall (dlc21_int_wild_gorilla_pattern_blue, the style 8
// shop's; art/wall_pattern.py keeps its darker tone as an ink mask). It is laid over the card's own blue in WALL_INK at
// WALL_ALPHA, so the card keeps its colour and the type stays readable; one tile is WALL_TILE design px across, and
// each card shows its own patch of it (picked by its name). A card filled for a try-on keeps a fainter print of it.
// Printed cards carry it in their print, under the art; plain cards on their face label, under the type.
const WALL_SRC = 'img/art/wild_pattern.webp', WALL_TILE = 680, WALL_INK = '#04103a', WALL_ALPHA = 0.42, WALL_FILL_ALPHA = 0.16;

const artCache = new Map();
function artImage(src) {
    let e = artCache.get(src);
    if (!e) {
        e = { img: new Image(), ok: false };
        artCache.set(src, e);
        e.img.src = src;
        // decoded off the main thread before its first print (drawImage would decode it there, mid-deal)
        const ready = () => { if (!e.ok) { e.ok = true; if (redrawAll) redrawAll(); } };
        e.img.decode().then(ready, () => { e.img.onload = ready; if (e.img.complete && e.img.naturalWidth) ready(); });
    }
    return e;
}

/* Every shader the shop draws with, compiled while the page loads, when no one is in the shop. Compiled on first use,
   each new kind of surface (a printed card, a clipped list row, a slider knob...) stalled the page 100-250 ms the
   first time its screen opened; in game, the browser's translation of each shader to DirectX makes it longer. One
   frame draws a stand-in of each material behind the camera (no pixels), through the real render path, so the
   compiled programs match exactly (lights, clipping, tone mapping). The stand-ins stay alive: disposing a material
   releases its program. */
const warmKeep = [];
function warmShaders(stage) {
    const planes = [new THREE.Plane(new THREE.Vector3(0, 1, 0), 1e6), new THREE.Plane(new THREE.Vector3(0, -1, 0), 1e6)];
    const tex = new THREE.CanvasTexture(document.createElement('canvas'));
    tex.colorSpace = THREE.SRGBColorSpace;
    const printed = (m) => { m.map = m.emissiveMap = tex; m.toneMapped = false; return m; };
    const mapped = (clip) => {
        const m = new THREE.MeshBasicMaterial({ map: tex, transparent: true, toneMapped: false, depthWrite: false });
        if (clip) m.clippingPlanes = clip;
        return m;
    };
    const cardPlain = glassMaterial(0.87, null, CARD_DARK);
    cardPlain.toneMapped = false;
    const mats = [
        glassMaterial(0.86), glassMaterial(0.86, planes),             // keys, the tally; the pill and type tiles in a list
        cardPlain, printed(glassMaterial(0.87, null, CARD_DARK)),      // cards plain and printed (and the column, dialogs)
        basicMaterial(0xffffff, 0.5), basicMaterial(0xffffff, 0.5, planes),
        mapped(null), mapped(planes),                                  // labels, swatches, discs, shadows, scrims
        new THREE.MeshPhysicalMaterial({ color: 0xf2f2f2, roughness: 0.22, clearcoat: 1, clearcoatRoughness: 0.05,
                                         emissive: 0x6a6a6a, clippingPlanes: planes }),                    // a slider's knob
        new THREE.MeshPhysicalMaterial({ color: 0x030406, roughness: 0.5, transparent: true, opacity: 0.85,
                                         clearcoat: 0.5 }),                                                // the search well
        new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0, depthWrite: false }), // the dialogs' dim
    ];
    const geo = new THREE.PlaneGeometry(1, 1);
    const group = new THREE.Group();
    mats.forEach((m) => {
        const o = new THREE.Mesh(geo, m);
        o.frustumCulled = false;                            // drawn though off screen: behind the camera, clipped away
        o.position.set(0, 0, stage.dist + 500);
        group.add(o);
    });
    stage.scene.add(group);
    // compiled in the background first (parallel shader compile, the page keeps running), then the one frame links
    // whatever is ready and compiles anything the background pass guessed differently
    const finish = () => {
        const t = performance.now();
        stage.render();
        stage.scene.remove(group);
        warmKeep.push(mats, geo, tex);
        wake();                                             // the next frame redraws the page as it should be
        return Math.round(performance.now() - t);
    };
    // (without the extension, compileAsync compiles in the foreground anyway: the one frame alone is cheaper)
    const r = stage.renderer;
    const parallel = r.compileAsync && r.extensions.has('KHR_parallel_shader_compile');
    return (parallel ? r.compileAsync(stage.scene, stage.camera) : Promise.resolve()).then(finish, finish);
}

// printArt's scratch canvases: the card's face on its own, and that again masked by the fade
const scratch = { under: document.createElement('canvas'), veil: document.createElement('canvas') };
function sized(canvas, w, h) {
    if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
    return canvas;
}

// The wallpaper's ink as one tinted tile (made once, when its picture has loaded): null until then.
let wallTint = null;
function wallTile() {
    if (wallTint) return wallTint;
    const e = artImage(WALL_SRC);
    if (!e.ok) return null;
    const img = e.img, t = document.createElement('canvas');
    t.width = img.naturalWidth; t.height = img.naturalHeight;
    const x = t.getContext('2d');
    x.drawImage(img, 0, 0);
    x.globalCompositeOperation = 'source-in';
    x.fillStyle = WALL_INK;
    x.fillRect(0, 0, t.width, t.height);
    return (wallTint = t);
}

/** A card's patch of the wallpaper: a number from its name (FNV-1a), the same every time. */
function wallSeed(name) {
    let h = 2166136261;
    for (const ch of String(name || '')) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
    return h >>> 0;
}

/** The wallpaper over a w x h face (design units) at `alpha`, its tile shifted by `seed`; `rounded` clips it to the
 *  card's corners (a face label is square; a print is cut by the slab itself). False until the picture has loaded. */
function drawWall(c, w, h, seed, alpha, rounded) {
    const tile = wallTile();
    if (!tile) return false;
    const p = c.createPattern(tile, 'repeat');
    const k = WALL_TILE / tile.width;
    p.setTransform(new DOMMatrix([k, 0, 0, k, -(seed % 4096) / 4096 * WALL_TILE, -((seed >>> 12) % 4096) / 4096 * WALL_TILE]));
    c.save();
    if (rounded) { roundRect(c, 0, 0, w, h, 12); c.clip(); }
    c.globalAlpha = alpha;
    c.fillStyle = p;
    c.fillRect(0, 0, w, h);
    c.restore();
    return true;
}

/** A card's face in design units (CARD_W x h): the blue gradient, the wallpaper and, on a top card, the livery bands. */
function drawFace(c, h, top, seed) {
    blueFill(c, CARD_W, h);
    drawWall(c, CARD_W, h, seed, WALL_ALPHA, false);
    // each band lies between two lines a·x + b·(h − y) = d, which meet the bottom edge at x = d / a and the left
    // edge at y = h − d / b
    if (top) drawLivery(c, CARD_W, h, 'bl');
}

/* Panels other than the cards print their face the same way: a canvas (design units) as the glass's map and its
   emissive map, so it shows at its own colours. The paint column is neutral graphite where the paints are (a coloured
   surround hides its own hue: blue paints vanish on blue), with the cards' blue only in its header band, which holds no
   colour; the dialogs take the cards' face whole. */
const PANEL = '#1e1f22', COL_HEAD = 112;
const PILL = new THREE.Color('#e9eaee');          // the paint list's "this one": a neutral light, so yellow paint shows on it

function printFace(stage, mat, holder, w, h, key, draw) {
    const s = stage.texScale;
    key = `${key}|${w}|${h}|${s}`;
    if (holder.key === key) return;
    holder.key = key;
    const W = Math.ceil(w * s), Hh = Math.ceil(h * s);
    if (!holder.canvas || holder.canvas.width !== W || holder.canvas.height !== Hh) {
        if (holder.tex) holder.tex.dispose();
        holder.canvas = document.createElement('canvas');
        holder.canvas.width = W; holder.canvas.height = Hh;
        holder.tex = new THREE.CanvasTexture(holder.canvas);
        holder.tex.colorSpace = THREE.SRGBColorSpace;
        holder.tex.anisotropy = stage.maxAniso;
    }
    const c = holder.canvas.getContext('2d');
    c.setTransform(s, 0, 0, s, 0, 0);
    c.clearRect(0, 0, w, h);
    draw(c, w, h);
    holder.tex.repeat.set(1 / w, 1 / h);               // the slab's face UVs are in its own units (as the cards')
    holder.tex.offset.set(0, 1);
    holder.tex.needsUpdate = true;
    if (mat.map !== holder.tex) { mat.map = mat.emissiveMap = holder.tex; mat.toneMapped = false; mat.needsUpdate = true; }
    mat.color.setScalar(ART_LIT);
    mat.emissive.setScalar(ART_GLOW);
    // the unlit face material (panelMaterials): the same print, as it is
    if (holder.faceMat && holder.faceMat.map !== holder.tex) { holder.faceMat.map = holder.tex; holder.faceMat.needsUpdate = true; }
    wake();
}

/** A big printed panel's materials, for a slab mesh [its faces, its sides]: the face unlit (the print as it is: the
 *  glass's lighting added next to nothing over a self-lit print, yet cost most of a frame, ~90% of the paint
 *  column's under software rendering), the sides and bevel the glass, so the edges keep their sheen. */
function panelMaterials(opacity, holder) {
    holder.faceMat = new THREE.MeshBasicMaterial({ transparent: true, opacity, toneMapped: false });
    holder.faceMat.color.setScalar(PANEL_FACE);
    return [holder.faceMat, glassMaterial(opacity)];
}
const PANEL_FACE = 1.05;                        // the unlit face's brightness: matched to the lit print it replaced (its sheen added ~5%)

/** The livery bands in a bottom corner of a w x h area: 'bl' (the cards') or 'br'; `scale` sizes them. Never along
 *  a face's top edge: the slab's side walls take their colour from the top rows of the printed face. */
function drawLivery(c, w, h, corner, scale = 1) {
    const [a, b] = LIVERY_DIR;
    c.fillStyle = LIVERY;
    for (const [d0, d1] of LIVERY_BANDS) {
        const p = [d0 * scale, d1 * scale];
        c.beginPath();
        if (corner === 'bl') {
            c.moveTo(p[0] / a, h); c.lineTo(p[1] / a, h); c.lineTo(0, h - p[1] / b); c.lineTo(0, h - p[0] / b);
        } else {
            c.moveTo(w - p[0] / a, h); c.lineTo(w - p[1] / a, h); c.lineTo(w, h - p[1] / b); c.lineTo(w, h - p[0] / b);
        }
        c.closePath();
        c.fill();
    }
}

function blueFill(c, w, h) {
    const g = c.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, CARD_TOP);
    g.addColorStop(1, CARD_BOTTOM);
    c.fillStyle = g;
    c.fillRect(0, 0, w, h);
}

const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');
const place = (o, x, y, z = 0) => { o.position.set(x, -y, z); return o; };
const lerp = (a, b, t) => a + (b - a) * t;

let epoch = 0;          // bumps when fonts or pad pictures arrive: every label redraws
let padImg = {};        // pad button pictures
let padBase = '';

function loadPadImages(base) {
    padBase = base;
    ['a', 'b', 'x', 'y', 'dpad', 'rs', 'lt', 'rt', 'rb'].forEach((n) => {
        const im = new Image();
        im.onload = () => { epoch++; if (redrawAll) redrawAll(); };
        im.src = `${base}${n}.svg`;
        padImg[n] = im;
    });
}
let redrawAll = null;

/* ---- hints ------------------------------------------------------------------------------------------
   Keyboard hints are markup: [x] a key chip, *x* bold. Pad hints are [buttons, label] pairs. Both lay
   out as units, separated by a gap or a middle dot, wrapping to `max`. */

function hintUnits(ctx, h, pad, size, style) {
    const units = [];
    if (pad) {
        (h.pad || []).forEach(([btns, label]) => {
            const list = Array.isArray(btns) ? btns : [btns];
            const ih = size * 1.55;
            const widths = list.map((b) => { const im = padImg[b]; return im && im.naturalWidth ? ih * im.naturalWidth / im.naturalHeight : ih; });
            const lw = measure(ctx, label, size, 500);
            const w = widths.reduce((a, b) => a + b + 3, 0) + 6 + lw;
            units.push({ w, draw: (x, y) => {
                let cx = x;
                list.forEach((b, i) => {
                    const im = padImg[b];
                    if (im && im.complete && im.naturalWidth) ctx.drawImage(im, cx, y - ih * 0.74, widths[i], ih);
                    cx += widths[i] + 3;
                });
                text(ctx, label, cx + 3, y, { size, weight: 500, color: style.base });
            } });
        });
        return units;
    }
    (h.kb || []).forEach((src) => {
        const toks = [];
        String(src).replace(/\[([^\]]+)\]|\*([^*]+)\*|([^[*]+)/g, (_, k, b, t) => { toks.push(k ? { k } : b ? { b } : { t }); return ''; });
        let w = 0;
        const parts = toks.map((tk) => {
            if (tk.k) { const kw = measure(ctx, tk.k, size * 0.86, 700) + size * 0.86; w += kw + 4; return { kw, ...tk }; }
            const s = tk.b || tk.t;
            const tw = measure(ctx, s, size, tk.b ? 700 : 500);
            w += tw;
            return { tw, ...tk };
        });
        units.push({ w, draw: (x, y) => {
            let cx = x;
            parts.forEach((p) => {
                if (p.k) { cx += kbd(ctx, p.k, cx, y, size * 0.86) + 4; return; }
                text(ctx, p.b || p.t, cx, y, { size, weight: p.b ? 700 : 500, color: p.b ? style.bold : style.base });
                cx += p.tw;
            });
        } });
    });
    return units;
}

/** Draws hint units, wrapping; returns the number of lines. `dots`: a middle dot between units. */
function drawHints(ctx, h, pad, { x = 0, y, max, size = 22, lineH = 40, dots = false, style }) {
    const units = hintUnits(ctx, h, pad, size, style);
    const gap = dots ? size * 1.6 : size * 0.9;
    let cx = x, cy = y, lines = 1;
    units.forEach((u, i) => {
        if (cx > x && cx + u.w > x + max) { cx = x; cy += lineH; lines++; }
        else if (i > 0 && dots) text(ctx, '·', cx - gap / 2, cy, { size, color: style.base, align: 'center' });
        u.draw(cx, cy);
        cx += u.w + gap;
    });
    return lines;
}

function hintLines(ctx, h, pad, max, size) {
    const units = hintUnits(ctx, h, pad, size, { base: '#fff', bold: '#fff' });
    const gap = size * 0.9;
    let cx = 0, lines = 1;
    units.forEach((u) => { if (cx > 0 && cx + u.w > max) { cx = 0; lines++; } cx += u.w + gap; });
    return lines;
}

/** whip's panel border (--ui-border): a faint line round a block's face, so it reads against the dark. */
function edgeLine(w, h, r, order, clip = null, opacity = 0.09) {
    const m = new THREE.Mesh(ringGeometry(w, h, r, -1, 2), basicMaterial(0xffffff, opacity, clip));
    m.renderOrder = order;
    m.position.z = 0.4;
    return m;
}

/* ---- a key: a 3D button ---------------------------------------------------------------------------- */

const KEY_STYLE = {
    // fill: the body's white; border: [colour, width]; ink text?
    outline:   { fill: 0,    border: [COL.accent, 2],                 color: COL.accent },   // a card's Add
    strong:    { fill: 1,    border: null,                            color: COL.ink },      // ... once it's in the basket
    ink:       { fill: 1,    border: ['rgba(10,12,18,0.35)', 2],      color: COL.ink },
    inkStrong: { fill: 1,    border: ['rgba(10,12,18,0.9)', 3],       color: COL.ink },
    primary:   { fill: 1,    border: null,                            color: COL.ink },
    ghost:     { fill: 0,    border: ['rgba(255,255,255,0.3)', 2],    color: COL.text },
    quiet:     { fill: 0.1,  border: null,                            color: 'rgba(255,255,255,0.82)', tint: NEUTRAL },
    hot:       { fill: 1,    border: null,                            color: COL.ink },
    seg:       { fill: 0,    border: null,                            color: COL.label },
    segOn:     { fill: 1,    border: null,                            color: COL.ink },
    off:       { fill: 0.06, border: null,                            color: 'rgba(255,255,255,0.3)', tint: NEUTRAL },
};

class Key {
    constructor(v, order, clip = null, { size = 21, spacing = 0.1, radius = 10 } = {}) {
        this.v = v;
        this.group = new THREE.Group();
        this.mat = glassMaterial(0.86, clip);
        this.body = new THREE.Mesh(slabGeometry(100, 70, radius, 5, 2.5), this.mat);
        this.body.renderOrder = order;
        this.label = new Label(v.stage, 100, 70, { order: order + 1, clip });
        this.label.mesh.position.z = 0.6;
        this.ring = new THREE.Mesh(ringGeometry(100, 70, radius, 5, 3), basicMaterial(COL.accent, 0.95, clip));
        this.ring.renderOrder = order + 1;
        this.ring.visible = false;
        this.group.add(this.body, this.label.mesh, this.ring);
        this.radius = radius; this.size = size; this.spacing = spacing;
        this.z0 = 0;
        this.tint = FILL;                        // a faint fill (quiet, off) is a neutral tint, not a pale yellow
        this.fill = new Spring(0, 520, 0, (f) => setFill(this.mat, f, this.tint));
        this.push = new Spring(0, 900, 0.2, (p) => { this.group.position.z = this.z0 - 4 * p + 3 * this.hov.v; });
        this.hov = new Spring(0, 500, 0, (h) => { this.group.position.z = this.z0 - 4 * this.push.v + 3 * h; });
        this.m = null;
        this.clip = clip;
        hit(this.body, {
            click: () => { if (this.m && this.m.onClick) this.m.onClick(); },
            hover: (on) => { this.hovered = on; this.hov.to(on && this.enabled ? 1 : 0); if (this.onHover) this.onHover(on); },
            press: (down) => { if (this.enabled) this.push.to(down ? 1 : 0); },
            clip: clip ? (p) => clip.every((pl) => pl.distanceToPoint(p) >= -0.5) : null,
            over: !!this.overlay,
        });
    }
    /** m: { label, style, onClick, w, h, focus } */
    set(m) {
        this.m = m;
        const w = m.w, h = m.h || 70;
        this.enabled = !!m.onClick;
        if (w !== this.w || h !== this.h) {
            this.w = w; this.h = h;
            this.body.geometry = slabGeometry(w, h, this.radius, 5, 2.5);
            this.label.size(w, h);
            this.ring.geometry = ringGeometry(w, h, this.radius, 5, 3);
        }
        const st = KEY_STYLE[this.enabled ? m.style : (m.style === 'segOn' || m.style === 'seg' ? m.style : 'off')] || KEY_STYLE.outline;
        this.tint = st.tint || FILL;
        this.fill.to(st.fill);
        this.ring.visible = !!m.focus;
        const size = m.size || this.size;
        this.label.draw(`${epoch}|${m.label}|${m.style}|${this.enabled}|${w}x${h}|${size}`, (c) => {
            if (st.border) {
                roundRect(c, st.border[1] / 2, st.border[1] / 2, w - st.border[1], h - st.border[1], this.radius - 1);
                c.lineWidth = st.border[1];
                c.strokeStyle = st.border[0];
                c.stroke();
            }
            text(c, m.label, w / 2, h / 2 + size * 0.36, { size, weight: 700, spacing: this.spacing, color: st.color, align: 'center', upper: m.upper !== false, max: w - 16 });
        });
    }
    at(x, y, z = 3) { this.z0 = z; place(this.group, x, y, z); return this; }
}

/* ---- a card on the rail ----------------------------------------------------------------------------- */

class Card {
    constructor(v) {
        this.v = v;
        this.pivot = new THREE.Group();          // at the card's centre: it turns and tilts about it
        this.inner = new THREE.Group();          // top-left origin inside
        this.pivot.add(this.inner);
        this.mat = glassMaterial(0.87, null, CARD_DARK);
        this.mat.toneMapped = false;                    // the Neutral curve's toe would crush graphite toward black
        this.body = new THREE.Mesh(slabGeometry(CARD_W, 236, 12, 10, 3), this.mat);
        this.body.renderOrder = ORDER.rail;
        this.shadow = new Shadow(CARD_W, 236, 0.5, ORDER.rail - 1);
        this.face = new Label(v.stage, CARD_W, 236, { order: ORDER.rail + 1 });
        this.face.mesh.position.z = 0.5;
        this.disc = new Disc(40, 'empty', ORDER.rail + 2);
        this.border = new THREE.Mesh(ringGeometry(CARD_W, 236, 12, 0, 3), basicMaterial(COL.accent, 0.95));
        this.border.renderOrder = ORDER.rail + 2;
        this.ring = new THREE.Mesh(ringGeometry(CARD_W, 236, 12, 6, 3), basicMaterial(COL.accent, 0.95));
        this.ring.renderOrder = ORDER.rail + 2;
        this.key = new Key(v, ORDER.rail + 3);
        this.key.onHover = (on) => { this.keyHover = on; this.lifted(); };
        this.edge = edgeLine(CARD_W, 236, 12, ORDER.rail + 1);
        this.inner.add(this.edge);
        this.print = null;                       // the art printed into the glass: { canvas, ctx, tex, key }
        this.inner.add(this.shadow.mesh, this.body, this.face.mesh, this.disc.mesh, this.border, this.ring, this.key.group);
        this.inner.position.set(-CARD_W / 2, 236 / 2, 0);

        this.enter = new Spring(0, 140, 0.32);
        this.exit = new Spring(0, 120, 0);
        this.lift = new Spring(0, 260, 0.15);
        this.tiltX = new Spring(0, 200); this.tiltY = new Spring(0, 200);
        this.push = new Spring(0, 900, 0.25);
        this.fillS = new Spring(0, 420, 0, (f) => this.glass(f));
        this.h = 236;
        hit(this.body, {
            click: () => { if (this.m && this.m.onOpen) this.m.onOpen(); },
            hover: (on) => { this.hover = on; this.lifted(); if (!on) { this.tiltX.to(0); this.tiltY.to(0); } },
            track: (p) => this.track(p),
            press: (d) => this.push.to(d ? 1 : 0),
        });
    }

    lifted() { this.lift.to(this.hover || this.keyHover || this.focus ? 1 : 0); }

    /** The glass's colour: the white fill, or (with art printed in) the print lighting itself: the picture is the
     *  emissive map too, so it shows at its own brightness like a backlit print instead of greyed by the scene's
     *  dim light; a little of it stays lit (diffuse) for the glass's sheen. */
    glass(f) {
        setFill(this.mat, f);
        if (this.mat.map) {
            this.mat.color.setScalar(ART_LIT);
            this.mat.emissive.setScalar(Math.min(1, ART_GLOW + 0.62 * f));
        } else {
            this.mat.emissive.copy(CARD_DARK).lerp(FILL.clone().multiplyScalar(0.62), f);
        }
    }

    /** Prints the card's face into the glass: its gradient (with the livery on a top card), the art (greyscale unless
     *  spec.color) and a fade back to the face under the text. A plain card with no art and no livery isn't printed. */
    printArt(img, spec, h, top = false, seed = 0) {
        const s = this.v.stage.texScale;
        const key = img || top ? `${img ? img.src : ''}|${JSON.stringify(spec || null)}|${h}|${s}|${top}|${seed}|${!!wallTile()}` : null;
        if (this.print && this.print.key === key) return;
        if (!key) {
            if (this.mat.map) {
                this.mat.map = this.mat.emissiveMap = null;
                this.mat.needsUpdate = true; this.glass(this.fillS.v);
            }
            if (this.print) this.print.key = null;
            return;
        }
        const W = Math.ceil(CARD_W * s), Hh = Math.ceil(h * s);
        if (!this.print || this.print.canvas.width !== W || this.print.canvas.height !== Hh) {
            if (this.print) this.print.tex.dispose();
            const canvas = document.createElement('canvas');
            canvas.width = W; canvas.height = Hh;
            const tex = new THREE.CanvasTexture(canvas);
            tex.colorSpace = THREE.SRGBColorSpace;
            tex.anisotropy = this.v.stage.maxAniso;
            this.print = { canvas, ctx: canvas.getContext('2d'), tex, key: null };
        }
        const p = this.print, c = p.ctx;
        p.key = key;
        // the face on its own (kept to fade back to), then onto the print
        const under = sized(scratch.under, W, Hh), u = under.getContext('2d');
        u.setTransform(s, 0, 0, s, 0, 0);
        drawFace(u, h, top, seed);
        c.setTransform(1, 0, 0, 1, 0, 0);
        c.filter = 'none';
        c.clearRect(0, 0, W, Hh);
        c.drawImage(under, 0, 0);
        if (img) {
            const a = Object.assign({}, ART, spec);
            const ih = h * a.size, iw = ih * ((img.naturalWidth || 1) / (img.naturalHeight || 1));
            c.setTransform(s, 0, 0, s, 0, 0);
            const tone = a.color ? '' : 'grayscale(1) ';
            c.filter = a.lift ? `${tone}brightness(${a.lift})` : (tone.trim() || 'none');
            c.drawImage(img, CARD_W * a.x - iw / 2, h * a.y - ih / 2, iw, ih);
            c.filter = 'none';
            // the fade: the face again, through a mask that is strong under the text and gone toward the art
            const veil = sized(scratch.veil, W, Hh), v = veil.getContext('2d');
            v.setTransform(1, 0, 0, 1, 0, 0);
            v.globalCompositeOperation = 'source-over';
            v.clearRect(0, 0, W, Hh);
            v.drawImage(under, 0, 0);
            v.globalCompositeOperation = 'destination-in';
            v.setTransform(s, 0, 0, s, 0, 0);
            if (top) {
                // the text sits top-left: the fade spreads from that corner (an ellipse), so the art keeps the bottom
                const rx = CARD_W * 0.7, ry = h * 0.75;
                v.scale(1, ry / rx);
                const g = v.createRadialGradient(0, 0, 0, 0, 0, rx);
                g.addColorStop(0, 'rgba(0,0,0,0.92)');
                g.addColorStop(0.6, 'rgba(0,0,0,0.55)');
                g.addColorStop(1, 'rgba(0,0,0,0)');
                v.fillStyle = g;
                v.fillRect(0, 0, CARD_W, h * rx / ry);
            } else {
                const g = v.createLinearGradient(0, 0, CARD_W * 0.62, 0);
                g.addColorStop(0, 'rgba(0,0,0,0.92)');
                g.addColorStop(0.75, 'rgba(0,0,0,0.55)');
                g.addColorStop(1, 'rgba(0,0,0,0)');
                v.fillStyle = g;
                v.fillRect(0, 0, CARD_W, h);
            }
            v.globalCompositeOperation = 'source-over';
            c.setTransform(1, 0, 0, 1, 0, 0);
            c.drawImage(veil, 0, 0);
        }
        p.tex.needsUpdate = true;
        // the slab's front face has UVs in its own units (x 0..w, y 0..-h): map them onto the picture
        p.tex.repeat.set(1 / CARD_W, 1 / h);
        p.tex.offset.set(0, 1);
        // (cards are not tone mapped: the Neutral curve's toe crushes dark greys, black paint's whole range)
        if (this.mat.map !== p.tex) { this.mat.map = this.mat.emissiveMap = p.tex; this.mat.needsUpdate = true; }
        this.glass(this.fillS.v);
        wake();
    }

    track(p) {
        const local = this.inner.worldToLocal(p.clone());
        const fx = local.x / CARD_W - 0.5, fy = -local.y / this.h - 0.5;
        this.tiltY.to(fx * 0.12);
        this.tiltX.to(fy * 0.1);
    }

    bind(m, h, focus) {
        this.m = m;
        if (h !== this.h) {
            this.h = h;
            this.body.geometry = slabGeometry(CARD_W, h, 12, 10, 3);
            this.face.size(CARD_W, h);
            this.shadow.size(CARD_W, h);
            this.border.geometry = ringGeometry(CARD_W, h, 12, 0, 3);
            this.ring.geometry = ringGeometry(CARD_W, h, 12, 6, 3);
            this.edge.geometry = ringGeometry(CARD_W, h, 12, -1, 2);
            this.inner.position.set(-CARD_W / 2, h / 2, 0);
        }
        const filled = !!m.previewing;
        this.fillS.to(filled ? 1 : 0);
        this.edge.visible = !filled && !m.basketed;
        this.border.visible = !!m.basketed;
        this.focus = !!focus;
        this.ring.visible = this.focus;
        this.lifted();
        place(this.disc.mesh, CARD_W - 26 - 20, 24 + 20, 3);
        this.disc.set(m.basketed ? 'check' : m.nav ? 'open' : 'empty');

        // ---- the art, printed into the glass ----
        const spec = typeof m.art === 'string' ? { src: m.art } : m.art;
        const art = spec ? artImage(spec.src) : null;
        const seed = wallSeed(m.name);
        this.printArt(art && art.ok ? art.img : null, spec, h, !!m.top, seed);
        const printed = !!this.mat.map;          // else the wallpaper goes on the face label, under the type
        // The disc would sit on the tyre: only its basket tick stays on an art card.
        this.disc.mesh.visible = !m.art || !!m.basketed;

        const hasFoot = m.price !== undefined || m.add;
        if (m.add) {
            const style = filled ? (m.add.strong ? 'inkStrong' : 'ink') : (m.add.strong ? 'strong' : 'outline');
            const kw = Math.max(92, Math.ceil(measure(this.face.ctx, m.add.label, 20, 700, 0.08, true)) + 48);
            this.key.group.visible = true;
            this.key.set({ label: m.add.label, style, w: kw, h: 70, size: 20, onClick: m.onAdd, focus: false });
            this.key.at(CARD_W - 26 - kw, h - 24 - 70, 2);
        } else {
            this.key.group.visible = false;
        }

        const ink = filled;
        const cText = ink ? COL.ink : COL.text, cMid = ink ? COL.inkMid : COL.mid;
        const cLabel = ink ? COL.inkMid : COL.label, cDim = ink ? COL.inkDim : COL.dim;
        const wall = !printed && !!wallTile();
        const k = `${epoch}|${h}|${ink}|${m.kicker}|${m.name}|${m.sub}|${m.price}|${m.fitted}|${m.big}|${!!m.add}|${!!m.top}|${wall}`;
        this.face.draw(k, (c, w) => {
            const L = 28, R = 26;
            if (wall) drawWall(c, w, h, seed, ink ? WALL_FILL_ALPHA : WALL_ALPHA, true);
            if (m.kicker) text(c, m.kicker, L, 52, { size: 18, weight: 700, spacing: 0.14, color: cLabel, upper: true, max: w - L - R - 56 });
            const nameSize = m.big ? 34 : 29;
            let y;
            if (m.top) {
                y = 62;                                  // top: the name where the tag line was, clear of the disc
            } else if (hasFoot) {
                y = m.big ? 112 : 106;
            } else {
                const lines = m.sub ? Math.min(2, wrapLines(c, m.sub, w - L - R, 23, 500).length) : 0;
                y = h - 26 - lines * 31 - (lines ? 12 : 0);
            }
            const nw = text(c, m.name, L, y, { size: nameSize, weight: 700, color: cText, display: true,
                                               max: w - L - R - (m.top ? 56 : m.fitted ? 120 : 0) });
            if (m.fitted) {
                // the blue FITTED chip, after the name
                const tw = measure(c, 'FITTED', 17, 700, 0.08) + 22;
                roundRect(c, L + nw + 14, y - 26, tw, 32, 4);
                c.fillStyle = ink ? 'rgba(12,30,74,0.14)' : COL.accentLight;
                c.fill();
                text(c, 'FITTED', L + nw + 14 + tw / 2, y - 4, { size: 17, weight: 700, spacing: 0.08, color: ink ? COL.ink : COL.accent, align: 'center' });
            }
            if (m.sub) wrap(c, m.sub, L, y + 38, w - L - R, 31, 2, { size: 23, weight: 500, color: cMid });
            if (m.price !== undefined) {
                if (m.price === 0) text(c, 'Free', L, h - 24 - 24, { size: 24, weight: 700, spacing: 0.04, color: cDim });
                else text(c, money(m.price), L, h - 24 - 22, { size: 28, weight: 700, color: cText });
            }
        });
    }

    /** Places the card: `cx` its centre's x on screen (design), the rail's top `top`. */
    place(cx, top, W, railShow) {
        // Flat (the user's call): every card in one plane facing the screen, so the row lines up edge to edge. The
        // depth shows in the glass itself (its thickness, the clear coat's sheen, the shadow under it) and in the
        // hover, which lifts the card toward you with a slight lean to the cursor.
        const e = this.enter.v, x = this.exit.v, l = this.lift.v, p = this.push.v;
        const y = top + this.h / 2 + (1 - e) * 280 + x * 320 - l * 10 + (1 - railShow) * 460;
        this.pivot.position.set(cx, -y, l * 30 - p * 9 - (1 - e) * 60);
        this.pivot.rotation.set((1 - e) * -1.05 + x * 0.6 + this.tiltX.v * l * HOVER_LEAN, this.tiltY.v * l * HOVER_LEAN, 0);
        this.shadow.lift(l);
    }

    moving() {
        return [this.enter, this.exit, this.lift, this.tiltX, this.tiltY, this.push].some((s) => s.v !== s.t);
    }
}

/* ---- the rail ----------------------------------------------------------------------------------------- */

class Rail {
    constructor(v) {
        this.v = v;
        this.group = new THREE.Group();
        v.stage.root.add(this.group);
        this.cards = new Map();      // id -> Card
        this.free = [];
        this.leaving = [];
        this.key = null;
        this.items = [];
        this.scroll = new Spring(0, 220);
        this.top = new Spring(RAIL_BOTTOM - CARD_H[0], 260);
        this.show = new Spring(0, 160);
        this.scrolls = {};           // scroll per rail, so going back lands where it was
        this.focus = -1;

        // The rail's surface: the wheel and a drag scroll it.
        this.surface = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({ visible: false }));
        this.surface.position.z = -40;
        v.stage.root.add(this.surface);
        let start = 0;
        hit(this.surface, {
            wheel: (d) => this.scrollTo(this.scroll.t + d * 1.4),
            drag: {
                start: (e) => { start = this.scroll.v; this.dragX = e.clientX; },
                move: (e) => { this.scroll.set(this.clamp(start - (e.clientX - this.dragX) / v.stage.pxPerD, 80)); },
                end: () => this.scrollTo(this.scroll.v),
            },
        });
        // An empty shelf says why.
        this.empty = new Label(v.stage, 1400, 60, { order: ORDER.rail + 1 });
        v.stage.root.add(this.empty.mesh);

        // A dark gradient behind the rail, so its text reads over a bright scene.
        const c = document.createElement('canvas');
        c.width = 4; c.height = 256;
        const g = c.getContext('2d').createLinearGradient(0, 0, 0, 256);
        g.addColorStop(0, 'rgba(5,6,10,0)');
        g.addColorStop(0.3, 'rgba(5,6,10,0.5)');
        g.addColorStop(0.55, 'rgba(5,6,10,0.72)');
        g.addColorStop(1, 'rgba(5,6,10,0.9)');
        const x = c.getContext('2d');
        x.fillStyle = g;
        x.fillRect(0, 0, 4, 256);
        const tex = new THREE.CanvasTexture(c);
        tex.colorSpace = THREE.SRGBColorSpace;
        this.scrimMat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, toneMapped: false });
        this.scrim = new THREE.Mesh(new THREE.PlaneGeometry(1, 1).translate(0.5, -0.5, 0), this.scrimMat);
        this.scrim.renderOrder = ORDER.rail - 5;
        v.stage.root.add(this.scrim);
    }

    maxScroll() {
        const vw = this.v.stage.W - RAIL_X * 2;
        return Math.max(0, this.items.length * PITCH - CARD_GAP - vw);
    }
    clamp(s, give = 0) { return Math.max(-give, Math.min(this.maxScroll() + give, s)); }
    scrollTo(s) { this.scroll.to(this.clamp(s)); this.scrolls[this.key] = this.scroll.t; }
    step(dir) { this.scrollTo(this.scroll.t + dir * PITCH); }

    update(m, visible) {
        this.show.to(visible && m ? 1 : 0);
        if (!m) { this.items = this.items; return; }
        const h = CARD_H[Math.min(3, m.level)];
        if (m.key !== this.key) {
            // A new level: the old cards drop away and the new ones deal in, one after another.
            for (const c of this.cards.values()) { c.exit.to(1); this.leaving.push(c); }
            this.cards.clear();
            this.leaveScroll = this.scroll.v;
            this.key = m.key;
            this.scroll.set(this.scrolls[m.key] || 0);
            this.dealt = performance.now();
            this.top.to(RAIL_BOTTOM - h);
        }
        this.items = m.cards;
        this.h = h;
        this.focus = m.focus;
        // Keep the pad's card in view.
        if (m.focus >= 0) {
            const vw = this.v.stage.W - RAIL_X * 2;
            const x0 = m.focus * PITCH, x1 = x0 + CARD_W;
            if (x0 < this.scroll.t) this.scrollTo(x0 - 40);
            else if (x1 > this.scroll.t + vw) this.scrollTo(x1 - vw + 40);
        }
        this.scrollTo(this.scroll.t);
        this.sync();
        this.empty.draw(`${epoch}|${m.empty}`, (c) => { if (m.empty) text(c, m.empty, 4, 40, { size: 26, weight: 500, color: COL.mid }); });
    }

    /** Builds the cards in and near view, lets go of the rest. */
    sync() {
        const vw = this.v.stage.W - RAIL_X * 2;
        const first = Math.max(0, Math.floor((this.scroll.v - 600) / PITCH));
        const last = Math.min(this.items.length - 1, Math.ceil((this.scroll.v + vw + 600) / PITCH));
        const want = new Set();
        for (let i = first; i <= last; i++) want.add(this.items[i].id);
        for (const [id, c] of this.cards) {
            if (!want.has(id)) { this.cards.delete(id); c.pivot.visible = false; this.free.push(c); }
        }
        for (let i = first; i <= last; i++) {
            const it = this.items[i];
            let c = this.cards.get(it.id);
            if (!c) {
                c = this.free.pop() || new Card(this.v);
                if (!c.pivot.parent) this.group.add(c.pivot);
                c.pivot.visible = true;
                c.exit.set(0);
                c.lift.set(0);
                c.idx = i;
                // Deal-in order counts from the first card on screen.
                const since = (performance.now() - (this.dealt || 0)) / 1000;
                const delay = Math.max(0, (i - Math.max(0, Math.floor(this.scroll.v / PITCH))) * 0.045 - since);
                if (since < 0.6) { c.enter.set(0); setTimeout(() => c.enter.to(1), delay * 1000); }
                else c.enter.set(1);
                this.cards.set(it.id, c);
            }
            c.idx = i;
            c.bind(it, this.h, i === this.focus);
        }
        this.synced = this.scroll.v;
    }

    frame() {
        const W = this.v.stage.W;
        if (Math.abs(this.scroll.v - (this.synced ?? 0)) > PITCH / 2) this.sync();
        const top = this.top.v;
        const show = this.show.v;
        this.group.visible = show > 0.001;
        for (const c of this.cards.values()) c.place(RAIL_X + c.idx * PITCH + CARD_W / 2 - this.scroll.v, top, W, show);
        this.leaving = this.leaving.filter((c) => {
            c.place(RAIL_X + c.idx * PITCH + CARD_W / 2 - (this.leaveScroll ?? 0), top, W, show);
            if (c.exit.v > 0.98) { c.pivot.visible = false; c.exit.set(0); this.free.push(c); return false; }
            return true;
        });
        place(this.surface, W / 2, top + this.h / 2, -40);
        this.surface.scale.set(W, this.h + 60, 1);
        this.surface.visible = show > 0.5;
        place(this.empty.mesh, RAIL_X, top + 20, 0);
        this.empty.mesh.visible = show > 0.5;
        // the scrim: from a little over the crumbs to the bottom edge, a touch wider than the screen
        const sTop = top - 330;
        place(this.scrim, -200, sTop, -60);
        this.scrim.scale.set(W + 400, H - sTop + 200, 1);
        this.scrimMat.opacity = show;
        this.scrim.visible = show > 0.01;
    }
}

/* ---- the crumbs over the rail, and the hint under it ------------------------------------------------- */

class Crumbs {
    constructor(v) {
        this.v = v;
        this.group = new THREE.Group();
        v.stage.root.add(this.group);
        this.back = new Disc(52, 'back', ORDER.crumbs);
        this.label = new Label(v.stage, 1800, 60, { order: ORDER.crumbs });
        this.group.add(this.back.mesh, this.label.mesh);
        this.backHov = new Spring(1, 400, 0.2, (s) => this.back.mesh.scale.set(26 * s, 26 * s, 8));
        hit(this.back.mesh, {
            click: () => this.m && this.m.onBack(),
            hover: (on) => { this.back.set(on ? 'backOn' : 'back'); this.backHov.to(on ? 1.1 : 1); },
            press: (d) => this.backHov.to(d ? 0.92 : 1.1),
        });
        this.hint = new Label(v.stage, 2400, 50, { order: ORDER.crumbs });
        v.stage.root.add(this.hint.mesh);
    }
    update(m, rail, pad) {
        this.m = m.crumbs;
        const items = m.crumbs.items;
        this.back.mesh.visible = m.crumbs.back;
        this.label.draw(`${epoch}|${items.join('/')}|${m.crumbs.back}`, (c) => {
            let x = 0;
            items.forEach((t, i) => {
                const last = i === items.length - 1;
                x += text(c, t, x, 41, { size: 24, weight: 700, spacing: 0.14, color: last ? COL.text : 'rgba(255,255,255,0.32)', upper: true });
                if (!last) { x += 14; x += text(c, '/', x, 41, { size: 24, weight: 700, color: 'rgba(255,255,255,0.22)' }) + 14; }
            });
        });
        if (rail) {
            this.hint.draw(`${epoch}|${pad}|${JSON.stringify(rail.hint)}`, (c) => {
                drawHints(c, rail.hint, pad, { y: 34, max: 2400, size: 22, dots: true,
                    style: { base: 'rgba(255,255,255,0.36)', bold: 'rgba(255,255,255,0.78)' } });
            });
        }
    }
    frame(rail) {
        const top = rail.top.v, show = rail.show.v;
        const drop = (1 - show) * 460;
        const backOn = this.back.mesh.visible;
        place(this.back.mesh, RAIL_X + 26, top - 52 + drop, 6);
        place(this.label.mesh, RAIL_X + (backOn ? 52 + 22 : 0), top - 52 - 30 + drop, 0);
        place(this.hint.mesh, RAIL_X, H - 62 - 34 + drop, 0);
        this.group.visible = show > 0.001;
        this.hint.mesh.visible = show > 0.001;
    }
}

/* ---- the tally, top right ------------------------------------------------------------------------------ */

class Tally {
    constructor(v) {
        this.v = v;
        this.w = 300; this.h = 120;
        this.group = new THREE.Group();
        v.stage.root.add(this.group);
        this.mat = glassMaterial(0.82);
        this.body = new THREE.Mesh(slabGeometry(this.w, this.h, 18, 10, 3), this.mat);
        this.body.renderOrder = ORDER.tally;
        this.shadow = new Shadow(this.w, this.h, 0.5, ORDER.tally - 1);
        this.label = new Label(v.stage, this.w, this.h, { order: ORDER.tally + 1 });
        this.label.mesh.position.z = 0.5;
        this.group.add(this.shadow.mesh, this.body, this.label.mesh, edgeLine(this.w, this.h, 18, ORDER.tally + 1));
        this.show = new Spring(0, 200, 0.25);
        this.hov = new Spring(0, 400, 0.2);
        this.total = new Spring(0, 90, 0, () => this.draw());
        this.cashV = null;
        hit(this.body, {
            click: () => this.m && this.m.onClick(),
            hover: (on) => this.hov.to(on ? 1 : 0),
        });
    }
    update(m) {
        this.m = m.tally;
        this.show.to(m.tally.show ? 1 : 0);
        if (this.total.t !== m.tally.total) {
            // The figure rolls to the new total.
            if (!m.tally.show || this.show.v < 0.05) this.total.set(m.tally.total);
            else this.total.to(m.tally.total);
        }
        this.cashV = m.tally.cash;
        this.draw();
    }
    draw() {
        const t = Math.round(this.total.v / 10) * 10;
        const total = Math.abs(this.total.v - this.total.t) < 5 ? this.total.t : t;
        this.label.draw(`${epoch}|${total}|${this.cashV}`, (c, w) => {
            text(c, 'Total', 28, 50, { size: 20, weight: 700, spacing: 0.14, color: COL.label, upper: true });
            text(c, money(total), w - 28, 52, { size: 33, weight: 700, color: COL.accent, align: 'right' });
            text(c, 'Cash', 28, 92, { size: 20, weight: 700, spacing: 0.14, color: COL.label, upper: true });
            text(c, this.cashV === null || this.cashV === undefined ? '—' : money(this.cashV), w - 28, 93, { size: 25, weight: 600, color: COL.mid, align: 'right' });
        });
    }
    frame() {
        const W = this.v.stage.W, s = this.show.v, h = this.hov.v;
        place(this.group, W - M - this.w, M - (1 - s) * 220 - h * 4, 6 + h * 16);
        this.group.rotation.x = (1 - s) * 0.5;
        this.group.visible = s > 0.002;
        this.shadow.lift(h);
    }
}

/* ---- the Standard camera button, bottom right on the hint row ----------------------------------------------- */
/* Glass as the tally's. Its key ([C], RB on a pad), its name, and a switch that is yellow while the standard camera
   (the orbit shot only, no part shots) is on. Gone while a dialog is up. */

class CamButton {
    constructor(v) {
        this.v = v;
        this.w = 376; this.h = 72;
        this.group = new THREE.Group();
        v.stage.root.add(this.group);
        this.mat = glassMaterial(0.82);
        this.body = new THREE.Mesh(slabGeometry(this.w, this.h, 18, 10, 3), this.mat);
        this.body.renderOrder = ORDER.tally;
        this.shadow = new Shadow(this.w, this.h, 0.5, ORDER.tally - 1);
        this.label = new Label(v.stage, this.w, this.h, { order: ORDER.tally + 1 });
        this.label.mesh.position.z = 0.5;
        this.group.add(this.shadow.mesh, this.body, this.label.mesh, edgeLine(this.w, this.h, 18, ORDER.tally + 1));
        this.show = new Spring(0, 200, 0.25);
        this.hov = new Spring(0, 400, 0.2);
        this.m = null;
        hit(this.body, {
            click: () => this.m && !this.m.off && this.m.onClick(),
            hover: (on) => this.hov.to(on ? 1 : 0),
        });
    }
    update(m, pad) {
        this.m = m;
        this.show.to(m && !m.off ? 1 : 0);
        if (!m) return;
        const on = !!m.standard;
        this.label.draw(`${epoch}|${pad}|${on}`, (c, w, h) => {
            const mid = h / 2;
            let x = 24;
            const im = padImg.rb;
            if (pad && im && im.complete && im.naturalWidth) {
                const ih = 34, iw = ih * im.naturalWidth / im.naturalHeight;
                c.drawImage(im, x, mid - ih / 2, iw, ih);
                x += iw;
            } else {
                x += kbd(c, 'C', x, mid + 7, 20);
            }
            text(c, 'Standard camera', x + 14, mid + 8, { size: 22, weight: 700, color: COL.text });
            // the switch
            const tw = 52, th = 28, tx = w - 24 - tw, ty = mid - th / 2;
            roundRect(c, tx, ty, tw, th, th / 2);
            c.fillStyle = on ? COL.accent : 'rgba(255,255,255,0.16)';
            c.fill();
            c.beginPath();
            c.arc(on ? tx + tw - th / 2 : tx + th / 2, mid, th / 2 - 4, 0, Math.PI * 2);
            c.fillStyle = on ? COL.ink : 'rgba(255,255,255,0.85)';
            c.fill();
        });
    }
    frame() {
        const W = this.v.stage.W, s = this.show.v, h = this.hov.v;
        // centred on the hint line (Crumbs: its text sits about 69 up from the bottom)
        place(this.group, W - M - this.w, H - 69 - this.h / 2 + (1 - s) * 160 - h * 4, 6 + h * 16);
        this.group.visible = s > 0.002;
        this.shadow.lift(h);
    }
}

/* ---- a Director job's checklist, top right under the tally ------------------------------------------------ */
/* What a Director goal (Customise Vehicle) asks of the car: each row done (paid for), in the basket (paying does
   it) or still to do. Glass as the tally's, as tall as its rows; it slides down when the tally comes in. */

const JOB_W = 380, JOB_TOP = 104, JOB_ROW = 46, JOB_FOOT = 50;

class JobPanel {
    constructor(v, tally) {
        this.v = v; this.tally = tally;
        this.w = JOB_W; this.h = 0;
        this.group = new THREE.Group();
        v.stage.root.add(this.group);
        this.mat = glassMaterial(0.82);
        this.body = new THREE.Mesh(slabGeometry(this.w, 160, 18, 10, 3), this.mat);
        this.body.renderOrder = ORDER.tally;
        this.shadow = new Shadow(this.w, 160, 0.5, ORDER.tally - 1);
        this.label = new Label(v.stage, this.w, 160, { order: ORDER.tally + 1 });
        this.label.mesh.position.z = 0.5;
        this.edge = edgeLine(this.w, 160, 18, ORDER.tally + 1);
        this.group.add(this.shadow.mesh, this.body, this.label.mesh, this.edge);
        this.show = new Spring(0, 200, 0.25);
        this.resize(160);
    }
    /** Fits the glass to `h` (the geometries are cached by size: swapped, never disposed). */
    resize(h) {
        if (h === this.h) return;
        this.h = h;
        this.body.geometry = slabGeometry(this.w, h, 18, 10, 3);
        this.shadow.size(this.w, h);
        this.label.size(this.w, h);
        this.edge.geometry = ringGeometry(this.w, h, 18, -1, 2);
    }
    update(m) {
        const job = m.job;
        this.show.to(job ? 1 : 0);
        if (!job) return;
        const rows = job.rows;
        const done = rows.filter((r) => r.state === 'done').length;
        // Everything left is in the basket: paying finishes it.
        const ready = done < rows.length && rows.every((r) => r.state !== 'todo');
        const foot = ready ? 'Pay for the basket to finish' : job.pays ? 'The job pays for these parts' : '';
        // The objective on two lines at most; the second takes the rest, cut short.
        let title = wrapLines(this.label.ctx, job.title, this.w - 56, 28, 700, true);
        if (title.length > 2) title = [title[0], title.slice(1).join(' ')];
        const top = JOB_TOP + Math.max(0, title.length - 1) * 34;
        this.resize(top + rows.length * JOB_ROW + (foot ? JOB_FOOT : 0) + 14);
        this.label.draw(`${epoch}|${this.h}|${job.title}|${foot}|${rows.map((r) => r.state + r.text).join('/')}`, (c, w) => {
            text(c, 'The job', 28, 46, { size: 19, weight: 700, spacing: 0.14, color: COL.label, upper: true });
            text(c, `${done} / ${rows.length}`, w - 28, 46, { size: 22, weight: 700, color: COL.accent, align: 'right' });
            title.forEach((l, i) => text(c, l, 28, 84 + i * 34, { size: 28, weight: 700, color: COL.text, max: w - 56, display: true }));
            rows.forEach((r, i) => {
                const y = top + i * JOB_ROW, cx = 40, cy = y + 23;
                c.beginPath();
                c.arc(cx, cy, 11, 0, Math.PI * 2);
                if (r.state === 'done') {
                    c.fillStyle = COL.accent;
                    c.fill();
                    c.strokeStyle = COL.ink;
                    c.lineWidth = 3;
                    c.lineCap = 'round'; c.lineJoin = 'round';
                    c.beginPath();
                    c.moveTo(cx - 5, cy + 0.5); c.lineTo(cx - 1.5, cy + 4); c.lineTo(cx + 5.5, cy - 4);
                    c.stroke();
                } else {
                    c.strokeStyle = r.state === 'basket' ? COL.accent : 'rgba(255,255,255,0.35)';
                    c.lineWidth = 2.5;
                    c.stroke();
                    if (r.state === 'basket') {
                        c.beginPath();
                        c.arc(cx, cy, 4.5, 0, Math.PI * 2);
                        c.fillStyle = COL.accent;
                        c.fill();
                    }
                }
                text(c, r.text, 64, y + 31, { size: 21, weight: 600, color: r.state === 'done' ? COL.mid : COL.text, max: w - 64 - 24 });
            });
            if (foot) {
                const y = top + rows.length * JOB_ROW + 8;
                c.fillStyle = 'rgba(255,255,255,0.08)';
                c.fillRect(28, y, w - 56, 2);
                text(c, foot, 28, y + 32, { size: 19, weight: 600, color: ready ? COL.accent : COL.label, max: w - 56 });
            }
        });
    }
    frame() {
        const W = this.v.stage.W, s = this.show.v;
        // Under the tally while it is up (the tally is 120 tall).
        const below = this.tally.show.v * (this.tally.h + 18);
        place(this.group, W - M - this.w, M + below - (1 - s) * 220, 6);
        this.group.rotation.x = (1 - s) * 0.5;
        this.group.visible = s > 0.002;
    }
}

/* ---- list rows (inside the column and the basket) ------------------------------------------------------ */

function clipTest(planes) { return (p) => planes.every((pl) => pl.distanceToPoint(p) >= -0.5); }

class RowBase {
    constructor(v, list, w, h) {
        this.v = v; this.list = list;
        this.group = new THREE.Group();
        this.bg = new THREE.Mesh(rectGeometry(w, h, 12), basicMaterial(0xffffff, 0, list.planes));
        this.bg.renderOrder = list.order + 1;
        this.bg.position.z = 1;
        this.label = new Label(v.stage, w, h, { order: list.order + 4, clip: list.planes });
        this.label.mesh.position.z = 9;
        this.ring = new THREE.Mesh(ringGeometry(w, h, 12, -1.5, 3), basicMaterial(COL.accent, 0.85, list.planes));
        this.ring.renderOrder = list.order + 5;
        this.ring.position.z = 9.5;
        this.ring.visible = false;
        this.group.add(this.bg, this.label.mesh, this.ring);
        this.hov = new Spring(0, 500, 0, (x) => { this.bg.material.opacity = this.baseBg + 0.06 * x; });
        this.baseBg = 0;
        this.w = w; this.h = h;
        hit(this.bg, {
            click: () => this.m && this.m.onClick && this.m.onClick(),
            hover: (on) => this.hov.to(on ? 1 : 0),
            clip: clipTest(list.planes),
        });
    }
    resize(w, h) {
        if (w === this.w && h === this.h) return;
        this.w = w; this.h = h;
        this.bg.geometry = rectGeometry(w, h, 12);
        this.label.size(w, h);
        this.ring.geometry = ringGeometry(w, h, 12, -1.5, 3);
    }
}

class PaintRow extends RowBase {
    constructor(v, list) {
        super(v, list, ROW_W, 60);
        this.swatch = new FlatSwatch('row', 56, 34, list.order + 6, list.planes);
        place(this.swatch.mesh, 44, 30, 10);           // over the selected row's white pill (z 7), with the text
        this.check = new Disc(28, 'check', list.order + 6, list.planes);
        place(this.check.mesh, ROW_W - 30, 30, 10);
        this.group.add(this.swatch.mesh, this.check.mesh);
    }
    bind(m) {
        this.m = m;
        this.swatch.paint(m.swatch, !!m.selected);
        this.check.mesh.visible = !!m.basketed;
        this.ring.visible = !!m.cursor && !m.selected;
        const ink = !!m.selected;
        this.label.draw(`${epoch}|${m.name}|${m.tag}|${m.tagOn}|${ink}|${m.basketed}`, (c, w, h) => {
            const right = w - 20 - (m.basketed ? 46 : 0);
            let tw = 0;
            if (m.tag) {
                tw = measure(c, m.tag, 17, 700, 0.1, true);
                if (m.tagOn) {
                    roundRect(c, right - tw - 16, h / 2 - 16, tw + 16, 30, 4);
                    c.fillStyle = ink ? 'rgba(10,12,18,0.14)' : COL.accentLight;
                    c.fill();
                    text(c, m.tag, right - 8, h / 2 + 6, { size: 17, weight: 700, spacing: 0.1, upper: true, align: 'right', color: ink ? COL.ink : COL.accent });
                    tw += 16;
                } else {
                    text(c, m.tag, right, h / 2 + 6, { size: 17, weight: 700, spacing: 0.1, upper: true, align: 'right', color: ink ? COL.inkMid : COL.label });
                }
            }
            text(c, m.name, 80, h / 2 + 9, { size: 25, weight: 600, color: ink ? COL.ink : COL.text, max: right - tw - 100 });
        });
    }
}

class EngineRow extends RowBase {
    constructor(v, list) {
        super(v, list, ROW_W, 60);
        this.check = new Disc(28, 'check', list.order + 6, list.planes);
        place(this.check.mesh, ROW_W - 30, 30, 10);
        this.group.add(this.check.mesh);
    }
    bind(m) {
        this.m = m;
        this.check.mesh.visible = !!m.basketed;
        this.ring.visible = !!m.cursor && !m.selected;
        const ink = !!m.selected;
        this.label.draw(`${epoch}|${m.name}|${m.tag}|${m.tagOn}|${m.power}|${ink}|${m.basketed}`, (c, w, h) => {
            const right = w - 20 - (m.basketed ? 46 : 0);
            const pw = m.power ? text(c, m.power, right, h / 2 + 8, { size: 21, weight: 600, align: 'right', color: ink ? COL.inkMid : COL.mid }) : 0;
            let tx = right - pw - (pw ? 16 : 0), tw = 0;
            if (m.tag) {
                tw = measure(c, m.tag, 16, 700, 0.1, true) + 14;
                roundRect(c, tx - tw, h / 2 - 14, tw, 26, 4);
                c.fillStyle = m.tagOn ? (ink ? 'rgba(10,12,18,0.14)' : COL.accentLight) : 'rgba(255,255,255,0)';
                c.fill();
                text(c, m.tag, tx - tw / 2, h / 2 + 5, { size: 16, weight: 700, spacing: 0.1, upper: true, align: 'center',
                    color: m.tagOn ? (ink ? COL.ink : COL.accent) : (ink ? COL.inkMid : COL.label) });
                tw += 12;
            }
            text(c, m.name, 24, h / 2 + 9, { size: 25, weight: 600, color: ink ? COL.ink : COL.text, max: tx - tw - 40 });
        });
    }
}

class TypeTile {
    constructor(v, list) {
        this.v = v; this.list = list;
        this.w = (ROW_W - 12) / 2; this.h = 92;
        this.group = new THREE.Group();
        this.mat = glassMaterial(0.55, list.planes);
        this.mat.color.set('#1a1d26');
        this.body = new THREE.Mesh(slabGeometry(this.w, this.h, 12, 4, 2), this.mat);
        this.body.renderOrder = list.order + 1;
        this.label = new Label(v.stage, this.w, this.h, { order: list.order + 4, clip: list.planes });
        this.label.mesh.position.z = 0.6;
        this.ring = new THREE.Mesh(ringGeometry(this.w, this.h, 12, -1.5, 3), basicMaterial(COL.accent, 0.85, list.planes));
        this.ring.renderOrder = list.order + 5;
        this.ring.position.z = 1;
        this.group.add(this.body, this.label.mesh, this.ring, edgeLine(this.w, this.h, 12, list.order + 2, list.planes, 0.07));
        this.inner = this.group;
        this.hov = new Spring(0, 420, 0.2);
        hit(this.body, {
            click: () => this.m && this.m.onClick(),
            hover: (on) => this.hov.to(on ? 1 : 0),
            clip: clipTest(list.planes),
        });
    }
    bind(m) {
        this.m = m;
        this.ring.visible = !!m.cursor;
        this.label.draw(`${epoch}|${m.name}|${m.count}|${m.fitted}`, (c, w) => {
            text(c, m.name, 22, 40, { size: 25, weight: 700, color: COL.text, max: w - 50 });
            text(c, m.count, 22, 74, { size: 21, weight: 500, color: COL.mid, max: w - 30 });
            if (m.fitted) { c.beginPath(); c.arc(w - 20, 20, 5, 0, Math.PI * 2); c.fillStyle = COL.accent; c.fill(); }
        });
    }
    zLift() { return this.hov.v * 8; }
}

class SliderRow extends RowBase {
    constructor(v, list) {
        super(v, list, ROW_W, 112);
        this.baseBg = 0.045;
        this.bg.material.opacity = this.baseBg;
        this.groove = new THREE.Mesh(rectGeometry(504, 8, 4), basicMaterial(0xffffff, 0.14, list.planes));
        this.groove.renderOrder = list.order + 2;
        this.fillBar = new THREE.Mesh(rectGeometry(1, 8, 0.01), basicMaterial(0xffffff, 0.75, list.planes));
        this.fillBar.renderOrder = list.order + 3;
        this.knobMat = new THREE.MeshPhysicalMaterial({ color: 0xf2f2f2, roughness: 0.22, clearcoat: 1, clearcoatRoughness: 0.05, emissive: 0x6a6a6a, clippingPlanes: list.planes });
        this.knob = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 20), this.knobMat);
        this.knob.scale.setScalar(16);
        this.knob.renderOrder = list.order + 6;
        place(this.groove, 20, 60, 2);
        this.group.add(this.groove, this.fillBar, this.knob);
        this.pos = new Spring(0, 900, 0, () => this.placeKnob());
        this.grabbed = new Spring(0, 500, 0.3, (g) => { this.knob.scale.setScalar(16 * (1 + 0.22 * g)); });
        // The whole row is the slider's handle: click anywhere on it, or drag.
        const u = this.bg.userData.hit;
        u.grab = true;
        u.drag = {
            start: () => { this.grabbed.to(1); if (this.m) this.m.onPick(); },
            move: (e) => this.dragTo(e),
            end: () => { this.grabbed.to(0); },
        };
        u.click = null;
    }
    dragTo(e) {
        const m = this.m;
        if (!m || m.off) return;
        const p = this.v.planePoint(e, this.group);
        if (!p) return;
        const f = Math.max(0, Math.min(1, (p.x - 20) / 504));
        const raw = m.min + f * (m.max - m.min);
        const v = Math.round(raw / m.step) * m.step;
        m.onInput(Math.round(v * 1000) / 1000);
    }
    placeKnob() {
        const m = this.m;
        if (!m) return;
        const f = (this.pos.v - m.min) / (m.max - m.min || 1);
        const z0 = (m.zero - m.min) / (m.max - m.min || 1);
        const x = 20 + 504 * f, xz = 20 + 504 * z0;
        place(this.knob, x, 64, 20);
        const a = Math.min(x, xz), b = Math.max(x, xz);
        this.fillBar.geometry = rectGeometry(Math.max(0.01, b - a), 8, 0.01);
        place(this.fillBar, a, 60, 3);
    }
    bind(m) {
        this.m = m;
        this.ring.visible = !!m.cursor;
        this.knobMat.color.set(m.off ? '#55585f' : '#f2f2f2');
        this.knobMat.emissive.set(m.off ? 0x000000 : 0x6a6a6a);
        this.fillBar.visible = !m.off;
        if (this.pos.t !== m.value) { if (this.bound) this.pos.to(m.value); else this.pos.set(m.value); }
        this.bound = true;
        this.placeKnob();
        this.label.draw(`${epoch}|${m.label}|${m.valueText}|${m.hint}|${m.off}`, (c, w) => {
            const a = m.off ? 0.4 : 1;
            c.globalAlpha = a;
            text(c, m.label, 20, 36, { size: 25, weight: 700, color: COL.text, max: 300 });
            text(c, m.valueText, w - 20, 36, { size: 24, weight: 700, color: COL.text, align: 'right' });
            text(c, m.hint, 20, 100, { size: 20, weight: 500, color: COL.label, max: w - 40 });
            c.globalAlpha = 1;
        });
    }
}

class ChoiceRow extends RowBase {
    constructor(v, list) {
        super(v, list, ROW_W, 150);
        this.baseBg = 0.045;
        this.bg.material.opacity = this.baseBg;
        this.keys = [];
        const u = this.bg.userData.hit;
        u.click = () => this.m && this.m.onPick();
    }
    bind(m) {
        this.m = m;
        this.ring.visible = !!m.cursor;
        const n = m.options.length, gap = 8, kw = (504 - gap * (n - 1)) / n;
        while (this.keys.length < n) {
            const k = new Key(this.v, this.list.order + 6, this.list.planes, { size: 19, spacing: 0.08, radius: 8 });
            this.keys.push(k);
            this.group.add(k.group);
        }
        this.keys.forEach((k, i) => {
            const o = m.options[i];
            k.group.visible = !!o;
            if (!o) return;
            k.set({ label: o.label, style: o.on ? 'segOn' : 'seg', w: kw, h: 50, onClick: o.onClick });
            k.at(20 + i * (kw + gap), 56, 8);
        });
        this.label.draw(`${epoch}|${m.label}|${m.valueText}|${m.hint}`, (c, w) => {
            text(c, m.label, 20, 36, { size: 25, weight: 700, color: COL.text });
            text(c, m.valueText, w - 20, 36, { size: 24, weight: 700, color: COL.text, align: 'right' });
            text(c, m.hint, 20, 138, { size: 20, weight: 500, color: COL.label, max: w - 40 });
        });
    }
}

class BasketRow {
    constructor(v, list) {
        this.v = v; this.list = list;
        this.w = 664; this.h = 104;
        this.group = new THREE.Group();
        this.label = new Label(v.stage, this.w, this.h, { order: list.order + 4, clip: list.planes });
        this.label.mesh.position.z = 1;
        this.drop = new Disc(40, 'cross', list.order + 5, list.planes);
        place(this.drop.mesh, this.w - 20, this.h / 2, 6);
        this.ring = new THREE.Mesh(new THREE.RingGeometry(27, 31, 40), basicMaterial(COL.accent, 0.95, list.planes));
        this.ring.renderOrder = list.order + 6;
        place(this.ring, this.w - 20, this.h / 2, 8);
        this.group.add(this.label.mesh, this.drop.mesh, this.ring);
        this.dropHov = new Spring(1, 420, 0.25, (s) => this.drop.mesh.scale.set(20 * s, 20 * s, 6.4));
        hit(this.drop.mesh, {
            click: () => this.m && this.m.onRemove(),
            hover: (on) => { this.drop.set(on ? 'crossOn' : 'cross'); this.dropHov.to(on ? 1.12 : 1); },
            press: (d) => this.dropHov.to(d ? 0.9 : 1.12),
            clip: clipTest(list.planes), over: true,
        });
    }
    bind(m, focusId) {
        this.m = m;
        this.ring.visible = focusId === 'rm:' + m.id;
        this.label.draw(`${epoch}|${m.slot}|${m.name}|${m.price}|${m.free}|${!!m.last}`, (c, w, h) => {
            text(c, m.slot, 0, 40, { size: 19, weight: 700, spacing: 0.12, color: COL.text, upper: true, max: w - 250 });
            text(c, m.name, 0, 76, { size: 28, weight: 700, color: COL.text, max: w - 250, display: true });
            // A line the Director's job pays for, in the accent.
            text(c, m.price, w - 64, 66, { size: 28, weight: 700, color: m.free ? COL.accent : COL.text, align: 'right' });
            // a line between rows; the last has the divider under the list instead
            if (!m.last) { c.fillStyle = COL.text; c.fillRect(0, h - 2, w, 2); }
        });
    }
}

const ROW_TYPES = { paint: PaintRow, engine: EngineRow, grid: TypeTile, slider: SliderRow, choice: ChoiceRow, basket: BasketRow };

/* ---- a scrolling list, clipped to its box ---------------------------------------------------------------- */

class List {
    constructor(v, parent, order, { pill = false, over = false } = {}) {
        this.v = v; this.order = order; this.over = over;
        this.group = new THREE.Group();
        parent.add(this.group);
        this.parent = parent;
        this.planes = [new THREE.Plane(), new THREE.Plane()];
        this.local = [new THREE.Plane(new THREE.Vector3(0, -1, 0), 0), new THREE.Plane(new THREE.Vector3(0, 1, 0), 0)];
        this.scroll = new Spring(0, 300);
        this.widgets = new Map();
        this.free = {};
        this.items = [];
        this.pos = [];
        this.box = { x: 0, y: 0, w: ROW_W, h: 100 };
        this.surface = new THREE.Mesh(new THREE.PlaneGeometry(1, 1).translate(0.5, -0.5, 0), new THREE.MeshBasicMaterial({ visible: false }));
        this.group.add(this.surface);
        let start = 0, y0 = 0;
        hit(this.surface, {
            wheel: (d) => this.scrollTo(this.scroll.t + d * 1.1),
            drag: {
                start: (e) => { start = this.scroll.v; y0 = e.clientY; },
                move: (e) => this.scroll.set(this.clamp(start - (e.clientY - y0) / v.stage.pxPerD, 60)),
                end: () => this.scrollTo(this.scroll.v),
            },
            over,
        });
        if (pill) {
            // The "this one": a raised block that glides to the row on the car. Neutral light (a yellow one hid
            // yellow paint), with the accent as a bar at its left end.
            this.pillMat = glassMaterial(0.97, this.planes);
            setFill(this.pillMat, 1, PILL);
            this.pill = new THREE.Mesh(slabGeometry(ROW_W, 60, 12, 4, 2.5), this.pillMat);
            this.pill.renderOrder = order + 2;
            this.pillBar = new THREE.Mesh(rectGeometry(6, 36, 3), basicMaterial(COL.accent, 1, this.planes));
            this.pillBar.renderOrder = order + 3;
            place(this.pillBar, 6, 12, 4.5);
            this.pill.add(this.pillBar);
            this.group.add(this.pill);
            this.pillY = new Spring(0, 700, 0.12);
            this.pillOn = new Spring(0, 500);
        }
        this.empty = new Label(v.stage, ROW_W, 120, { order: order + 4, clip: this.planes });
        this.group.add(this.empty.mesh);
    }

    region(x, y, w, h) {
        this.box = { x, y, w, h };
        this.local[0].constant = -y;
        this.local[1].constant = y + h;
        place(this.surface, x, y, 0.5);
        this.surface.scale.set(w, h, 1);
    }
    maxScroll() { return Math.max(0, this.contentH - this.box.h); }
    clamp(s, give = 0) { return Math.max(-give, Math.min(this.maxScroll() + give, s)); }
    scrollTo(s) { this.scroll.to(this.clamp(s)); }

    layout(list) {
        const pos = [];
        let y = 8;
        const it = list.items || [];
        if (list.type === 'grid') {
            const w = (ROW_W - 12) / 2;
            it.forEach((_, i) => pos.push({ x: (i % 2) * (w + 12), y: 8 + Math.floor(i / 2) * 104, w, h: 92, type: 'grid' }));
            y = 8 + Math.ceil(it.length / 2) * 104;
        } else if (list.type === 'sliders') {
            it.forEach((m) => { const h = m.type === 'choice' ? 150 : 112; pos.push({ x: 0, y, w: ROW_W, h, type: m.type }); y += h + 8; });
        } else if (list.type === 'basket') {
            y = 0;
            it.forEach(() => { pos.push({ x: 0, y, w: 664, h: 104, type: 'basket' }); y += 104; });
        } else if (list.type === 'rows') {
            it.forEach(() => { pos.push({ x: 0, y, w: ROW_W, h: 60, type: list.rows }); y += 64; });
        }
        this.contentH = y + 4;
        return pos;
    }

    update(list, focusId = null) {
        this.list = list;
        this.focusId = focusId;
        if (list.scrollKey !== this.scrollKey) { this.scrollKey = list.scrollKey; this.scroll.set(0); }
        this.items = list.items || [];
        this.pos = this.layout(list);
        const r = list.reveal;
        if (r >= 0 && this.pos[r]) {
            const p = this.pos[r];
            if (p.y - 8 < this.scroll.t) this.scrollTo(p.y - 8);
            else if (p.y + p.h + 8 > this.scroll.t + this.box.h) this.scrollTo(p.y + p.h + 8 - this.box.h);
        } else {
            this.scrollTo(this.scroll.t);
        }
        if (this.pill) {
            const sel = list.type === 'rows' ? this.items.findIndex((m) => m.selected) : -1;
            this.pillOn.to(sel >= 0 ? 1 : 0);
            if (sel >= 0) { if (this.pillOn.v < 0.05) this.pillY.set(this.pos[sel].y); else this.pillY.to(this.pos[sel].y); }
        }
        this.empty.draw(`${epoch}|${list.type === 'empty' ? list.text : ''}`, (c, w) => {
            if (list.type === 'empty') wrap(c, list.text, 16, 44, w - 32, 34, 3, { size: 23, weight: 500, color: list.color || COL.mid });
        });
        this.sync(true);
    }

    sync(rebind) {
        const top = this.scroll.v - 120, bot = this.scroll.v + this.box.h + 120;
        const want = new Map();
        this.pos.forEach((p, i) => { if (p.y + p.h >= top && p.y <= bot) want.set(this.items[i].id, i); });
        for (const [id, w] of this.widgets) {
            if (!want.has(id) || w.type !== this.pos[want.get(id)].type) {
                this.widgets.delete(id);
                w.group.visible = false;
                (this.free[w.type] = this.free[w.type] || []).push(w);
            }
        }
        for (const [id, i] of want) {
            const p = this.pos[i];
            let w = this.widgets.get(id);
            const fresh = !w;
            if (!w) {
                w = (this.free[p.type] || []).pop();
                if (!w) {
                    w = new ROW_TYPES[p.type](this.v, this);
                    w.type = p.type;
                    this.group.add(w.group);
                }
                w.group.visible = true;
                w.bound = false;
                this.widgets.set(id, w);
            }
            w.idx = i;
            if (fresh || rebind) w.bind(this.items[i], this.focusId);
        }
        this.synced = this.scroll.v;
    }

    frame() {
        this.group.updateWorldMatrix(true, false);
        const mw = this.parent.matrixWorld;
        this.planes[0].copy(this.local[0]).applyMatrix4(mw);
        this.planes[1].copy(this.local[1]).applyMatrix4(mw);
        if (Math.abs(this.scroll.v - this.synced) > 40) this.sync(false);
        const s = this.scroll.v, { x, y } = this.box;
        for (const w of this.widgets.values()) {
            const p = this.pos[w.idx];
            if (!p) continue;
            place(w.group, x + p.x, y + p.y - s, 2 + (w.zLift ? w.zLift() : 0));
        }
        if (this.pill) {
            place(this.pill, x, y + this.pillY.v - s, 7);
            this.pill.visible = this.pillOn.v > 0.02;
            this.pill.scale.set(1, 1, Math.max(0.01, this.pillOn.v));
        }
        place(this.empty.mesh, x, y, 4);
    }
}

/* ---- the picker column ----------------------------------------------------------------------------------- */

class Column {
    constructor(v) {
        this.v = v;
        this.group = new THREE.Group();
        v.stage.root.add(this.group);
        const o = ORDER.col;
        this.face = {};                           // its printed face (printFace): graphite under a blue header band
        const mats = panelMaterials(0.84, this.face);
        this.mat = mats[1];
        this.body = new THREE.Mesh(slabGeometry(COL_W, COL_H, 20, 14, 4), mats);
        this.body.renderOrder = o;
        this.shadow = new Shadow(COL_W, COL_H, 0.55, o - 1);
        // A solid block: the rail behind it never takes the pointer through it.
        hit(this.body, { solid: true });
        this.group.add(this.shadow.mesh, this.body, edgeLine(COL_W, COL_H, 20, o + 1));

        this.back = new Disc(52, 'back', o + 3);
        place(this.back.mesh, 32 + 26, 36 + 26, 6);
        this.backHov = new Spring(1, 400, 0.2, (s) => this.back.mesh.scale.set(26 * s, 26 * s, 8));
        hit(this.back.mesh, {
            click: () => this.m && this.m.onBack(),
            hover: (on) => { this.back.set(on ? 'backOn' : 'back'); this.backHov.to(on ? 1.1 : 1); },
            press: (d) => this.backHov.to(d ? 0.92 : 1.1),
        });
        this.title = new Label(v.stage, COL_W - 120, 110, { order: o + 2 });
        place(this.title.mesh, 108, 14, 1);
        this.group.add(this.back.mesh, this.title.mesh);

        this.div1 = this.divider(); this.div2 = this.divider();

        // ---- tools: colour families ----
        this.hues = [];
        this.hueRing = new THREE.Mesh(new THREE.TorusGeometry(1, 0.075, 12, 48), basicMaterial(0xffffff, 0.95));
        this.hueRing.renderOrder = o + 6;
        this.huePip = new THREE.Mesh(new THREE.CircleGeometry(4, 20), basicMaterial(COL.accent, 1));
        this.huePip.renderOrder = o + 6;
        this.hueLabel = new Label(v.stage, COL_W - 64, 56, { order: o + 2 });
        this.group.add(this.hueRing, this.huePip, this.hueLabel.mesh);

        // ---- tools: the engine search ----
        this.well = new THREE.Mesh(slabGeometry(300, 86, 10, 3, 2), new THREE.MeshPhysicalMaterial({ color: 0x030406, roughness: 0.5, transparent: true, opacity: 0.85, clearcoat: 0.5 }));
        this.well.renderOrder = o + 1;
        this.wellLabel = new Label(v.stage, 300, 86, { order: o + 2 });
        this.group.add(this.well, this.wellLabel.mesh);
        hit(this.well, { click: () => v.focusSearch() });
        this.seg = [new Key(v, o + 3, null, { size: 19, spacing: 0.08, radius: 8 }), new Key(v, o + 3, null, { size: 19, spacing: 0.08, radius: 8 })];
        this.seg.forEach((k) => this.group.add(k.group));

        // ---- the list ----
        this.list = new List(v, this.group, o + 2, { pill: true });

        // ---- the foot ----
        this.chip = new FlatSwatch('chip', 60, 60, o + 6);
        this.chipEmpty = new THREE.Mesh(new THREE.TorusGeometry(26, 2.4, 12, 48), basicMaterial(0xffffff, 0.3));
        this.chipEmpty.renderOrder = o + 6;
        this.now = new Label(v.stage, COL_W - 64, 110, { order: o + 2 });
        this.keys = [new Key(v, o + 3), new Key(v, o + 3)];
        this.hint = new Label(v.stage, COL_W - 64, 200, { order: o + 2 });
        this.group.add(this.chip.mesh, this.chipEmpty, this.now.mesh, this.hint.mesh);
        this.keys.forEach((k) => this.group.add(k.group));

        this.open = new Spring(0, 170, 0.18);
        this.m = null;
    }

    divider() {
        const d = new THREE.Mesh(new THREE.PlaneGeometry(COL_W, 2).translate(COL_W / 2, -1, 0), basicMaterial(0xffffff, 0.08));
        d.renderOrder = ORDER.col + 1;
        this.group.add(d);
        return d;
    }

    hueDot(i) {
        while (this.hues.length <= i) {
            const s = new FlatSwatch('dot', 32, 32, ORDER.col + 5);
            const h = { s, scale: new Spring(1, 400, 0.3, (k) => s.zoom(k)), m: null };
            hit(s.mesh, {
                click: () => h.m && h.m.onClick(),
                hover: (on) => { h.hover = on; h.scale.to(h.m && h.m.on ? 1.3 : on ? 1.15 : 1); },
            });
            this.group.add(s.mesh);
            this.hues.push(h);
        }
        return this.hues[i];
    }

    update(p, pad) {
        this.open.to(p ? 1 : 0);
        if (!p) return;
        this.m = p;
        const ep = epoch;
        printFace(this.v.stage, this.mat, this.face, COL_W, COL_H, 'col', (c, w, h) => {
            c.fillStyle = PANEL;
            c.fillRect(0, 0, w, h);
            blueFill(c, w, COL_HEAD);
            drawLivery(c, w, COL_HEAD, 'br', 0.8);
        });
        this.title.draw(`${ep}|${p.title}|${p.sub}`, (c, w) => {
            text(c, p.title, 0, 50, { size: 32, weight: 700, color: COL.text, max: w, display: true });
            text(c, p.sub, 0, 86, { size: 22, weight: 500, color: COL.mid, max: w });
        });

        // ---- tools ----
        const t = p.tools;
        // booleans, not undefined: three.js only hides an object whose visible is exactly false (with no tools the
        // search well showed at the column's top-left)
        const hues = !!t && t.type === 'hues', search = !!t && t.type === 'search';
        let listTop = 124;
        this.hues.forEach((h, i) => { h.s.mesh.visible = hues && i < t.hues.length; });
        this.hueRing.visible = false;
        this.huePip.visible = false;
        this.hueLabel.mesh.visible = hues;
        if (hues) {
            const n = t.hues.length, span = COL_W - 64 - 32, step = span / Math.max(1, n - 1);
            t.hues.forEach((hm, i) => {
                const h = this.hueDot(i);
                h.m = hm;
                h.s.paint(hm.dot);
                const x = 32 + 16 + i * step;
                place(h.s.mesh, x, 148, 3);
                h.scale.to(hm.on ? 1.3 : h.hover ? 1.15 : 1);
                if (hm.on) { this.hueRing.visible = true; place(this.hueRing, x, 148, 4); this.hueRing.scale.setScalar(27); }
                if (hm.fitted) { this.huePip.visible = true; place(this.huePip, x, 182, 4); }
            });
            this.hueLabel.draw(`${ep}|${t.label}|${t.count}`, (c, w) => {
                text(c, t.label, 0, 38, { size: 26, weight: 700, color: COL.text, display: true });
                text(c, t.count, w, 38, { size: 22, weight: 600, color: COL.label, align: 'right' });
            });
            place(this.hueLabel.mesh, 32, 194, 1);
            listTop = 276;
        }
        this.well.visible = this.wellLabel.mesh.visible = search;
        this.seg.forEach((k) => { k.group.visible = search && !!t.sort; });
        if (search) {
            const sortW = t.sort ? 186 + 12 : 0;
            const ww = COL_W - 64 - sortW;
            this.well.geometry = slabGeometry(ww, 86, 10, 3, 2);
            place(this.well, 32, 124, -1);
            this.wellLabel.size(ww, 86);
            place(this.wellLabel.mesh, 32, 124, 0.5);
            const focused = this.v.searchFocused();
            const val = focused ? this.v.searchValue() : t.value;
            this.wellLabel.draw(`${ep}|${val}|${focused}|${t.placeholder}|${ww}`, (c, w, h) => {
                const tw = val ? text(c, val, 22, h / 2 + 9, { size: 25, weight: 500, color: COL.text, max: w - 44 }) :
                    (focused ? 0 : text(c, t.placeholder, 22, h / 2 + 9, { size: 25, weight: 500, color: 'rgba(255,255,255,0.38)', max: w - 44 }));
                if (focused) { c.fillStyle = COL.text; c.fillRect(22 + (val ? tw : 0) + 2, h / 2 - 16, 2.5, 32); }
                roundRect(c, 1, 1, w - 2, h - 2, 9);
                c.lineWidth = 2;
                c.strokeStyle = focused ? 'rgba(255,255,255,0.45)' : 'rgba(255,255,255,0.1)';
                c.stroke();
            });
            if (t.sort) {
                [['name', 'A–Z', 76], ['power', 'Power', 110]].forEach(([k, label, w], i) => {
                    this.seg[i].set({ label, style: t.sort === k ? 'segOn' : 'seg', w, h: 86, onClick: () => t.onSort(k) });
                    this.seg[i].at(COL_W - 32 - 186 + (i ? 76 : 0), 124, 1);
                });
            }
            listTop = 240;
        }
        this.v.setSearchModel(search ? t : null);
        place(this.div1, 0, listTop - 14, 0.4);

        // ---- the foot ----
        const f = p.foot;
        const hintMax = COL_W - 64;
        const lines = hintLines(this.hint.ctx, p.hint, pad, hintMax, 21);
        const footH = 32 + 96 + 28 + 90 + 38 + lines * 40 + 20;
        const footTop = COL_H - footH;
        place(this.div2, 0, footTop, 0.4);
        const chipShown = f.chip !== undefined;
        this.chip.mesh.visible = chipShown && !!f.chip;
        this.chipEmpty.visible = chipShown && !f.chip;
        if (chipShown) {
            this.chip.paint(f.chip);
            place(this.chip.mesh, 32 + 30, footTop + 32 + 46, 3);
            place(this.chipEmpty, 32 + 30, footTop + 32 + 46, 4);
        }
        const nx = chipShown ? 32 + 60 + 24 : 32;
        this.now.size(COL_W - 32 - nx, 110);
        place(this.now.mesh, nx, footTop + 28, 1);
        this.now.draw(`${ep}|${f.name}|${f.note}|${nx}`, (c, w) => {
            text(c, f.name, 0, 40, { size: 27, weight: 700, color: COL.text, max: w, display: true });
            text(c, f.note, 0, 82, { size: 22, weight: 500, color: COL.mid, max: w });
        });
        const btns = f.buttons;
        const ky = footTop + 32 + 96 + 28;
        if (btns.length === 1) {
            this.keys[0].group.visible = true; this.keys[1].group.visible = false;
            this.keys[0].set({ label: btns[0].label, style: btns[0].onClick ? 'primary' : 'off', w: COL_W - 64, h: 90, size: 22, onClick: btns[0].onClick });
            this.keys[0].at(32, ky, 2);
        } else {
            const gw = f.engine ? 208 : 192;
            btns.forEach((b, i) => {
                const k = this.keys[i];
                k.group.visible = true;
                const w = i === 0 ? gw : COL_W - 64 - gw - 16;
                k.set({ label: b.label, style: b.ghost ? 'ghost' : 'primary', w, h: 90, size: 22, onClick: b.onClick });
                k.at(32 + (i === 0 ? 0 : gw + 16), ky, 2);
            });
        }
        this.hint.draw(`${ep}|${pad}|${JSON.stringify(p.hint)}`, (c) => {
            drawHints(c, p.hint, pad, { y: 30, max: hintMax, size: 21, lineH: 40, style: { base: COL.label, bold: COL.text } });
        });
        place(this.hint.mesh, 32, ky + 90 + 12, 1);

        // ---- the list, between the tools and the foot ----
        this.list.region(16, listTop, ROW_W, footTop - listTop - 10);
        this.list.update(p.list);
    }

    frame() {
        const o = this.open.v;
        place(this.group, M - (1 - o) * 760, M, -(1 - o) * 120);
        this.group.rotation.y = COL_TILT + (1 - o) * 0.5;
        this.group.visible = o > 0.002;
        if (this.group.visible) this.list.frame();
    }

    /** Where the column's right edge stands on screen once open, in px. */
    edge() {
        const g = new THREE.Object3D();
        this.v.stage.root.add(g);
        place(g, M, M, 0);
        g.rotation.y = COL_TILT;
        g.updateWorldMatrix(true, false);
        const s = this.v.stage.toScreen(g, COL_W, 0, 0);
        this.v.stage.root.remove(g);
        return s.x;
    }
}

/* ---- dialogs ----------------------------------------------------------------------------------------- */

const DLG_WALL_SEED = wallSeed('Basket');

class Dialog {
    constructor(v, w) {
        this.v = v; this.w = w; this.h = 400;
        this.pivot = new THREE.Group();
        this.inner = new THREE.Group();
        this.pivot.add(this.inner);
        v.over.add(this.pivot);
        const o = ORDER.dlg;
        this.face = {};                           // its printed face: the cards' blue, their livery bottom left
        const mats = panelMaterials(0.94, this.face);
        this.mat = mats[1];
        this.body = new THREE.Mesh(slabGeometry(w, 400, 20, 14, 4), mats);
        this.body.renderOrder = o;
        this.shadow = new Shadow(w, 400, 0.7, o - 1);
        hit(this.body, { solid: true, over: true });
        this.inner.add(this.shadow.mesh, this.body);
        this.open = new Spring(0, 230, 0.3);
        this.edge = edgeLine(w, 400, 20, o + 1);
        this.inner.add(this.edge);
    }
    size(h) {
        if (h !== this.h) {
            this.h = h;
            this.body.geometry = slabGeometry(this.w, h, 20, 14, 4);
            this.shadow.size(this.w, h);
            this.edge.geometry = ringGeometry(this.w, h, 20, -1, 2);
        }
        // the cards' face: their blue, the wallpaper (one patch, as on a card) and the livery
        printFace(this.v.stage, this.mat, this.face, this.w, this.h, `dlg|${!!wallTile()}`, (c, w, hh) => {
            blueFill(c, w, hh);
            drawWall(c, w, hh, DLG_WALL_SEED, WALL_ALPHA, false);
            drawLivery(c, w, hh, 'bl', 0.8);
        });
    }
    key(order) {
        const k = new Key(this.v, order);
        k.body.userData.hit.over = true;
        this.inner.add(k.group);
        return k;
    }
    frame() {
        const o = this.open.v, W = this.v.stage.W;
        this.pivot.visible = o > 0.002;
        this.pivot.position.set(W / 2, -H / 2 + (1 - o) * 90, -(1 - o) * 220);
        this.pivot.rotation.x = (1 - o) * -0.42;
        this.inner.position.set(-this.w / 2, this.h / 2, 0);
    }
}

class BasketDialog extends Dialog {
    constructor(v) {
        super(v, 760);
        const o = ORDER.dlg;
        this.head = new Label(v.stage, 760 - 96, 70, { order: o + 2 });
        this.sums = new Label(v.stage, 760 - 96, 300, { order: o + 2 });
        this.padHint = new Label(v.stage, 760 - 96, 50, { order: o + 2 });
        this.inner.add(this.head.mesh, this.sums.mesh, this.padHint.mesh);
        this.divs = [0, 1].map(() => {
            const d = new THREE.Mesh(new THREE.PlaneGeometry(760 - 96, 2).translate((760 - 96) / 2, -1, 0), basicMaterial(0xffffff, 0.93));
            d.renderOrder = o + 1;
            this.inner.add(d);
            return d;
        });
        this.rows = new List(v, this.inner, o + 2, { over: true });
        this.tiles = [this.payTile('cash'), this.payTile('bank')];
        // Setting how a Director car spawns: one tile, Save, where the two pay tiles go.
        this.saveTile = this.payTile('save');
        // Developer mode: Free, on Keep shopping's row (the dialog is as tall as the screen with a full basket).
        this.freeTile = this.payTile('free', 760 - 96 - 290 - 20, 90);
        this.keep = this.key(o + 3);
    }
    payTile(kind, w = (760 - 96 - 20) / 2, h = 148) {
        const o = ORDER.dlg;
        const t = { group: new THREE.Group(), mat: glassMaterial(0.6), w, h };
        t.mat.color.set('#081a45');                    // deep navy, set into the blue dialog
        t.body = new THREE.Mesh(slabGeometry(w, h, 14, 6, 3), t.mat);
        t.body.renderOrder = o + 1;
        t.label = new Label(this.v.stage, w, h, { order: o + 2 });
        t.label.mesh.position.z = 0.6;
        t.ring = new THREE.Mesh(ringGeometry(w, h, 14, 6, 3), basicMaterial(COL.accent, 0.95));
        t.ring.renderOrder = o + 2;
        t.group.add(t.body, t.label.mesh, t.ring, edgeLine(w, h, 14, o + 2, null, 0.11));
        t.hov = new Spring(0, 420, 0.2, (x) => { t.group.position.z = 2 + x * 10 - t.push.v * 6; });
        t.push = new Spring(0, 900, 0.2, (x) => { t.group.position.z = 2 + t.hov.v * 10 - x * 6; });
        hit(t.body, {
            click: () => t.enabled && t.onClick(),
            hover: (on) => t.hov.to(on && t.enabled ? 1 : 0),
            press: (d) => t.enabled && t.push.to(d ? 1 : 0),
            over: true,
        });
        t.draw = (enabled) => t.label.draw(`${epoch}|${kind}|${enabled}`, (c, cw, ch) => {
            c.globalAlpha = enabled ? 1 : 0.4;
            // the badge disc with whip's glyph
            const cx = 50, cy = ch / 2;
            c.beginPath(); c.arc(cx, cy, 30, 0, Math.PI * 2);
            c.fillStyle = 'rgba(10,12,18,0.6)'; c.fill();
            c.lineWidth = 3.5; c.strokeStyle = 'rgba(255,255,255,0.6)'; c.stroke();
            c.strokeStyle = 'rgba(255,255,255,0.92)'; c.lineWidth = 3.4; c.lineCap = 'round'; c.lineJoin = 'round';
            c.beginPath();
            if (kind === 'cash') {
                roundRect(c, cx - 14, cy - 9, 28, 18, 2.5); c.stroke();
                c.beginPath(); c.arc(cx, cy, 4, 0, Math.PI * 2);
            } else if (kind === 'save') {
                c.moveTo(cx - 12, cy + 1); c.lineTo(cx - 4, cy + 9); c.lineTo(cx + 13, cy - 9);
            } else if (kind === 'free') {
                // </>: developer mode
                c.moveTo(cx - 7, cy - 10); c.lineTo(cx - 16, cy); c.lineTo(cx - 7, cy + 10);
                c.moveTo(cx + 7, cy - 10); c.lineTo(cx + 16, cy); c.lineTo(cx + 7, cy + 10);
                c.moveTo(cx + 3, cy - 13); c.lineTo(cx - 3, cy + 13);
            } else {
                c.moveTo(cx - 15, cy - 5); c.lineTo(cx, cy - 14); c.lineTo(cx + 15, cy - 5);
                c.moveTo(cx - 9, cy - 1); c.lineTo(cx - 9, cy + 10);
                c.moveTo(cx, cy - 1); c.lineTo(cx, cy + 10);
                c.moveTo(cx + 9, cy - 1); c.lineTo(cx + 9, cy + 10);
                c.moveTo(cx - 14, cy + 14); c.lineTo(cx + 14, cy + 14);
            }
            c.stroke();
            const words = { cash: ['Cash', 'From your pockets'], bank: ['Bank', 'Your default account'],
                            save: ['Save', 'The car spawns like this'],
                            free: ['Free', 'Developer mode'] }[kind];
            text(c, words[0], 100, cy - 10, { size: 28, weight: 700, color: COL.text, display: true });
            wrap(c, words[1], 100, cy + 24, cw - 116, 26, 2, { size: 21, weight: 500, color: COL.text });
            c.globalAlpha = 1;
        });
        this.inner.add(t.group);
        return t;
    }

    update(b, pad) {
        this.open.to(b.open ? 1 : 0);
        this.m = b;
        const n = b.rows.length;
        const P = 48, IW = 760 - 2 * P;
        const rowsH = n ? Math.min(6, n) * 104 : 150;
        let y = 34;
        this.head.draw(`${epoch}|${b.count}|${b.builder}`, (c, w) => {
            text(c, b.builder ? 'Spawns with' : 'Basket', 0, 46, { size: 22, weight: 700, spacing: 0.16, color: COL.text, upper: true });
            const s = String(b.count);
            const bw = Math.max(40, measure(c, s, 22, 700) + 18);
            c.fillStyle = COL.accent;
            roundRect(c, w - bw, 18, bw, 40, 6);
            c.fill();
            text(c, s, w - bw / 2, 46, { size: 22, weight: 700, color: COL.ink, align: 'center' });
        });
        place(this.head.mesh, P, y, 1);
        y += 82;
        place(this.divs[0], P, y, 0.5);
        y += 10;
        this.rows.region(P, y, IW, rowsH);
        this.rows.update(n ? { type: 'basket', items: b.rows.map((r, i) => (i === n - 1 ? Object.assign({}, r, { last: true }) : r)), scrollKey: 'basket' }
            : { type: 'empty', items: [], color: COL.text, text: b.builder ? 'Nothing picked yet. Add parts from Customise: saved empty, the car spawns as it is.'
                : 'Nothing in here yet. Add parts from Customise, or a repair.' }, b.focus);
        y += rowsH + 6;
        place(this.divs[1], P, y, 0.5);
        y += 10;
        this.sums.draw(`${epoch}|${b.total}|${b.cash}|${b.builder}`, (c, w) => {
            if (b.builder) {
                wrap(c, 'When the scenario makes this car, it comes out with these parts and this tuning.',
                    0, 60, w, 40, 3, { size: 26, weight: 500, color: COL.text });
                return;
            }
            text(c, 'Total', 0, 76, { size: 22, weight: 700, spacing: 0.12, color: COL.text, upper: true });
            text(c, b.total, w, 84, { size: 54, weight: 700, spacing: -0.008, color: COL.accent, align: 'right' });
            text(c, 'Cash on you', 0, 140, { size: 22, weight: 700, spacing: 0.12, color: COL.text, upper: true });
            text(c, b.cash, w, 140, { size: 26, weight: 600, color: COL.text, align: 'right' });
            wrap(c, 'The parts are fitted and saved the moment this goes through.', 0, 208, w, 40, 2, { size: 26, weight: 500, color: COL.text });
        });
        place(this.sums.mesh, P, y, 1);
        y += b.builder ? 170 : 290;
        const tw = (IW - 20) / 2;
        [[b.onCash, 'cash'], [b.onBank, 'bank']].forEach(([fn, id], i) => {
            const t = this.tiles[i];
            t.enabled = b.payEnabled && !b.builder;
            t.group.visible = !b.builder;
            t.onClick = fn;
            t.id = id;
            t.draw(b.payEnabled);
            t.ring.visible = b.focus === id;
            place(t.group, P + i * (tw + 20), y, 2);
            t.y = y; t.x = P + i * (tw + 20);
        });
        const s = this.saveTile;
        s.enabled = b.builder && !!b.onSave;
        s.group.visible = !!b.builder;
        s.onClick = b.onSave;
        s.id = 'save';
        s.draw(true);
        s.ring.visible = b.focus === 'save';
        place(s.group, P, y, 2);
        y += 148 + 34;
        const f = this.freeTile;
        f.group.visible = !b.builder && !!b.onFree;
        f.enabled = f.group.visible && b.payEnabled;
        f.onClick = b.onFree;
        f.id = 'free';
        f.draw(b.payEnabled);
        f.ring.visible = b.focus === 'free';
        place(f.group, P, y, 2);
        const kw = 290;
        this.keep.set({ label: b.builder ? 'Keep editing' : 'Keep shopping', style: 'quiet', w: kw, h: 90, size: 22, onClick: b.onKeep, focus: b.focus === 'keep' });
        this.keep.at(760 - P - kw, y, 2);
        this.keepY = y;
        y += 90;
        this.padHint.mesh.visible = pad;
        if (pad) {
            this.padHint.draw(`${epoch}|pad`, (c) => drawHints(c, { pad: [['dpad', 'choose'], ['a', 'select'], ['b', 'close']] }, true,
                { y: 34, max: IW, size: 21, style: { base: COL.text, bold: COL.text } }));
            place(this.padHint.mesh, P, y + 14, 1);
            y += 64;
        }
        this.size(y + 40);
    }

    buttons() {
        const b = this.m;
        if (!b || !b.open) return [];
        const out = [];
        const st = this.v.stage;
        for (const w of this.rows.widgets.values()) {
            if (!(w instanceof BasketRow) || !w.m) continue;
            const s = st.toScreen(w.group, w.w - 20, w.h / 2, 6);
            out.push({ id: 'rm:' + w.m.id, x: s.x, y: s.y, onClick: w.m.onRemove });
        }
        if (b.builder) {
            const s = st.toScreen(this.saveTile.group, 161, 74, 0);
            out.push({ id: 'save', x: s.x, y: s.y, onClick: this.saveTile.onClick });
        } else if (b.payEnabled) {
            this.tiles.forEach((t) => {
                const s = st.toScreen(t.group, 161, 74, 0);
                out.push({ id: t.id, x: s.x, y: s.y, onClick: t.onClick });
            });
            const f = this.freeTile;
            if (f.group.visible) {
                const s = st.toScreen(f.group, f.w / 2, f.h / 2, 0);
                out.push({ id: 'free', x: s.x, y: s.y, onClick: f.onClick });
            }
        }
        const s = st.toScreen(this.keep.group, 145, 45, 0);
        out.push({ id: 'keep', x: s.x, y: s.y, onClick: b.onKeep });
        return out;
    }
}

class ConfirmDialog extends Dialog {
    constructor(v) {
        super(v, 760);
        const o = ORDER.dlg;
        this.label = new Label(v.stage, 760 - 96, 160, { order: o + 2 });
        this.padHint = new Label(v.stage, 760 - 96, 50, { order: o + 2 });
        this.inner.add(this.label.mesh, this.padHint.mesh);
        this.stay = this.key(o + 3);
        this.leave = this.key(o + 3);
    }
    update(m, pad) {
        this.open.to(m.open ? 1 : 0);
        this.m = m;
        const P = 48;
        this.label.draw(`${epoch}|${m.builder}`, (c, w) => {
            text(c, m.builder ? 'Leave without saving?' : 'Leave without paying?', 0, 48, { size: 34, weight: 700, color: COL.text, display: true });
            wrap(c, m.builder ? 'The car keeps the look it had before.' : 'Everything you have fitted comes back off. Nothing has been charged.',
                0, 100, w, 38, 2, { size: 26, weight: 500, color: COL.mid });
        });
        place(this.label.mesh, P, 40, 1);
        let y = 40 + 160 + 20;
        this.stay.set({ label: 'Stay', style: 'quiet', w: 170, h: 84, size: 22, onClick: m.onStay, focus: m.focus === 'stay' });
        this.leave.set({ label: 'Leave', style: 'hot', w: 170, h: 84, size: 22, onClick: m.onLeave, focus: m.focus === 'leave' });
        this.leave.at(760 - P - 170, y, 2);
        this.stay.at(760 - P - 170 - 16 - 170, y, 2);
        y += 84;
        this.padHint.mesh.visible = pad;
        if (pad) {
            this.padHint.draw(`${epoch}|pad`, (c) => drawHints(c, { pad: [['dpad', 'choose'], ['a', 'select'], ['b', 'stay']] }, true,
                { y: 34, max: 664, size: 21, style: { base: COL.label, bold: COL.text } }));
            place(this.padHint.mesh, P, y + 14, 1);
            y += 64;
        }
        this.size(y + 40);
    }
    buttons() {
        const m = this.m;
        if (!m || !m.open) return [];
        const st = this.v.stage;
        const a = st.toScreen(this.stay.group, 85, 42, 0), b = st.toScreen(this.leave.group, 85, 42, 0);
        return [{ id: 'stay', x: a.x, y: a.y, onClick: m.onStay }, { id: 'leave', x: b.x, y: b.y, onClick: m.onLeave }];
    }
}

/* ---- the view ------------------------------------------------------------------------------------------------ */

export function createView(host, opts = {}) {
    const stage = new Stage(host);
    const v = { stage };

    // Dialogs draw in a second pass over a cleared depth buffer, so nothing in the scene can poke through.
    v.overScene = new THREE.Scene();
    v.overScene.environment = stage.scene.environment;
    v.overScene.add(stage.scene.children.find((c) => c.isDirectionalLight).clone());
    v.over = new THREE.Group();
    v.overScene.add(v.over);
    const dimMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0, depthWrite: false, depthTest: false });
    const dim = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), dimMat);
    dim.renderOrder = ORDER.dim;
    dim.position.z = -60;
    v.over.add(dim);
    hit(dim, { solid: true, over: true, click: () => { if (v.model && v.model.basket.open) v.model.basket.onKeep(); } });
    const dimS = new Spring(0, 200);

    stage.render = () => {
        const r = stage.renderer;
        r.autoClear = false;
        r.clear();
        r.render(stage.scene, stage.camera);
        if (dimS.v > 0.002 || basketDlg.open.v > 0.002 || confirmDlg.open.v > 0.002) {
            v.over.position.copy(stage.root.position);
            r.clearDepth();
            r.render(v.overScene, stage.camera);
        }
    };

    // The engine search types into a real input (off screen), so the keyboard, IME and Backspace behave.
    const search = document.createElement('input');
    search.className = 'pk-search';
    search.type = 'text';
    search.spellcheck = false;
    search.setAttribute('aria-label', 'Search engines');
    host.appendChild(search);
    let searchModel = null;
    search.addEventListener('focus', () => { if (searchModel) searchModel.onFocus(); redraw(); });
    search.addEventListener('blur', () => { if (searchModel) searchModel.onBlur(); redraw(); });
    search.addEventListener('input', () => { if (searchModel) searchModel.onInput(search.value); });
    v.focusSearch = () => search.focus();
    v.searchFocused = () => document.activeElement === search;
    v.searchValue = () => search.value;
    v.setSearchModel = (t) => {
        searchModel = t;
        if (t && document.activeElement !== search && search.value !== t.value) search.value = t.value;
        if (!t && document.activeElement === search) search.blur();
    };

    // A pointer ray against a widget's own plane, in its design coordinates (sliders).
    const ray = new THREE.Raycaster(), ndc = new THREE.Vector2(), pl = new THREE.Plane(), hitP = new THREE.Vector3();
    v.planePoint = (e, obj) => {
        ndc.set((e.clientX / window.innerWidth) * 2 - 1, -(e.clientY / window.innerHeight) * 2 + 1);
        ray.setFromCamera(ndc, stage.camera);
        obj.updateWorldMatrix(true, false);
        const n = new THREE.Vector3(0, 0, 1).transformDirection(obj.matrixWorld);
        pl.setFromNormalAndCoplanarPoint(n, new THREE.Vector3().setFromMatrixPosition(obj.matrixWorld));
        if (!ray.ray.intersectPlane(pl, hitP)) return null;
        const p = obj.worldToLocal(hitP.clone());
        return { x: p.x, y: -p.y };
    };

    loadPadImages(opts.padImg || 'img/pad/');

    const rail = new Rail(v);
    const crumbs = new Crumbs(v);
    const tally = new Tally(v);
    const camBtn = new CamButton(v);
    const jobPanel = new JobPanel(v, tally);
    const column = new Column(v);
    const basketDlg = new BasketDialog(v);
    const confirmDlg = new ConfirmDialog(v);
    const pointer = new Pointer(stage);

    // The whole shop eases in and out with the page.
    const shown = new Spring(0, 160);

    onFrame(() => {
        const W = stage.W;
        dim.scale.set(W * 2, H * 2, 1);
        dim.position.set(W / 2, -H / 2, -60);
        dimMat.opacity = 0.5 * dimS.v;
        dim.visible = dimS.v > 0.01;
        v.over.position.copy(stage.root.position);
        rail.frame();
        crumbs.frame(rail);
        tally.frame();
        camBtn.frame();
        jobPanel.frame();
        column.frame();
        basketDlg.frame();
        confirmDlg.frame();
        basketDlg.rows.frame();
        const live = shown.v > 0.002;
        stage.root.visible = live;
        v.over.visible = live;
        // Closed: the canvas itself is hidden, so the browser has nothing of the shop to composite over the game
        const vis = live ? 'visible' : 'hidden';
        if (stage.canvas.style.visibility !== vis) stage.canvas.style.visibility = vis;
        return false;
    });

    function redraw() { if (v.model) update(v.model); }
    redrawAll = () => redraw();
    afterFonts(() => { epoch++; redraw(); });
    loadFonts();
    startLoop(stage);
    setTimeout(() => {
        const t = performance.now();
        warmShaders(stage).then((blockMs) => {
            // for the tests: how long the warm-up took in all, and how long of it held the page
            if (window.__whiplash3d) Object.assign(window.__whiplash3d, { warmMs: Math.round(performance.now() - t), warmBlockMs: blockMs });
        });
    }, 0);
    stage.onResize = () => { epoch++; redraw(); };

    function update(m) {
        v.model = m;
        if (!m.open) {
            shown.to(0);
            rail.update(null, false);
            column.update(null, false);
            tally.update({ tally: { show: false, total: 0, cash: null } });
            camBtn.update(null, false);
            jobPanel.update({ job: null });
            basketDlg.open.to(0);
            confirmDlg.open.to(0);
            dimS.to(0);
            rail.key = null;
            wake();
            return;
        }
        shown.to(1);
        document.body.classList.toggle('pad', !!m.pad);
        rail.update(m.rail, !m.picker);
        crumbs.update(m, m.rail, m.pad);
        tally.update(m);
        camBtn.update(m.camera, m.pad);
        jobPanel.update(m);
        column.update(m.picker, m.pad);
        basketDlg.update(m.basket, m.pad);
        confirmDlg.update(m.confirm, m.pad);
        dimS.to(m.basket.open || m.confirm.open ? 1 : 0);
        pointer.modal = m.basket.open || m.confirm.open;
        wake();
    }

    // For the preview's tests: the scene's parts, to find where things are on screen.
    window.__whiplash3d = { stage, rail, column, basketDlg, confirmDlg, tally, camBtn, jobPanel, crumbs, loop: loopDebug };

    return {
        update,
        setOrbiting(on) { document.body.classList.toggle('orbiting', !!on); },
        scrollRail(dir) { rail.step(dir); },
        columnEdge() { return column.edge(); },
        dialogButtons(which) { return which === 'confirm' ? confirmDlg.buttons() : basketDlg.buttons(); },
        blurSearch() { if (document.activeElement === search) search.blur(); },
    };
}
