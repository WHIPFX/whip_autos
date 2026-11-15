/* Whiplash screen. It talks to the game through client/ui.lua (messages in, callbacks back via post). This file keeps
   the state and rules and describes each frame as a plain model; view.js turns the model into the three.js scene.
   Prices here are display only; the server charges from its own copy. */

import { createView } from './view.js';

const RES = 'whip_autos';

// A side shot of one rim from each wheel range (GTA wheel type 0-12), shown on the range's card.
const WHEEL_ART = 'img/wheels/';
const wheelArt = (c) => (c.wheelType !== undefined && c.wheelType >= 0 && c.wheelType <= 12
    ? `${WHEEL_ART}${String(c.wheelType).padStart(2, '0')}.webp` : null);

// The Cosmetics and Performance categories' art, by GTA mod slot.
const MOD_ART = { 0: 'spoiler', 1: 'bumper_f', 2: 'bumper_r', 3: 'skirts', 4: 'exhaust', 5: 'cage', 6: 'grille', 7: 'hood',
                  8: 'fender', 9: 'fender', 10: 'roof', 27: 'trim', 30: 'dials', 33: 'steering',
                  11: 'engine', 12: 'brakes', 13: 'transmission', 15: 'suspension', 16: 'armour', 18: 'turbo',
                  22: 'headlights' };
const MOD_SRC = { turbo: 'img/art/turbo.webp' };        // pictures kept elsewhere (the turbo is the shelf's)
// Where a picture needs its own place on the card (shares of the card; size x its height).
const MOD_PLACE = {
    spoiler: { x: 0.72, y: 0.68, size: 1.55 },
    bumper_f: { x: 0.72, y: 0.74, size: 1.2 }, bumper_r: { x: 0.72, y: 0.68, size: 1.2 },
    skirts: { x: 0.7, y: 0.7, size: 1.7 }, exhaust: { x: 0.72, y: 0.66, size: 1.6 },
    cage: { x: 0.74, y: 0.74, size: 1.5 }, grille: { x: 0.78, y: 0.72, size: 1.6 },
    fender: { x: 0.72, y: 0.66, size: 1.6 }, roof: { x: 0.72, y: 0.64, size: 1.6 },
    trim: { x: 0.72, y: 0.7, size: 1.55 }, dials: { x: 0.78, y: 0.76, size: 1.6 },
    engine: { x: 0.76, y: 0.7, size: 1.45 }, transmission: { x: 0.7, y: 0.68, size: 1.5 },
    brakes: { x: 0.74, y: 0.66, size: 1.22 }, suspension: { x: 0.8, y: 0.66, size: 1.45 },
    armour: { x: 0.76, y: 0.72, size: 1.3 }, headlights: { x: 0.7, y: 0.6, size: 1.35 },
};
// Parts with yellow pieces print in colour; the all-metal ones stay black and white.
const PAINTED = new Set(['spoiler', 'bumper_f', 'bumper_r', 'skirts', 'hood', 'fender', 'roof', 'headlights',
                         'cage', 'trim', 'dials', 'steering', 'engine', 'brakes', 'suspension']);
const modArt = (c) => {
    const n = MOD_ART[c.slot];
    return n ? Object.assign({ src: MOD_SRC[n] || `img/mods/${n}.webp`, color: PAINTED.has(n) }, MOD_PLACE[n] || {}) : null;
};

// The shelves' art (view.js prints it into the card). Placement as shares of the card; size x the card's height.
const SHELF_ART = {
    cosmetics:   { src: 'img/art/spanner.webp', x: 0.88, y: 0.86, size: 2.3 },   // rises from the bottom right, jaw up top
    wheels:      wheelArt({ wheelType: 0 }),
    performance: { src: 'img/art/turbo.webp', lift: 1.45 },   // the rim's placement; dark metal, brightened
    paints:      { src: 'img/art/spray.webp', x: 0.8, y: 0.88, size: 1.7, color: true },   // top leaning to the top left, nozzle up-right; runs off the bottom right; a Race Yellow can, in colour
    tuning:      { src: 'img/art/dyno.svg', x: 0.76, y: 0.5, size: 0.84, color: true },   // stock run dashed, the tuned run in yellow
};
// The Paints and Tuning categories carry their shelf's art: the spray can (the Sport rim for Wheel Colour) and the
// dyno graph. Placed for the category cards, whose name and count sit at the top.
const CAT_ART = {
    paints: { src: 'img/art/spray.webp', x: 0.86, y: 1.02, size: 1.6, color: true },
    wheelcolor: wheelArt({ wheelType: 0 }),
    tuning: { src: 'img/art/dyno.svg', x: 0.8, y: 0.68, size: 0.72, color: true },
};
const catArt = (shelf, c) => (shelf === 'paints' ? (c.key === 'wheelcolor' ? CAT_ART.wheelcolor : CAT_ART.paints)
                            : shelf === 'tuning' ? CAT_ART.tuning : null);

/* ---- state ---------------------------------------------------------------- */

let catalogue = {};   // { sectionKey: [ category, ... ] }
let sections  = [];   // [ { key, name, framing } ]
let palette   = [];   // every GTA paint [ { index, name, hex, family } ], shared by the paint targets
let services  = [];   // [ { id, name, desc, price } ]; never previewed
let basket    = [];   // [ { slot, index, wheelType, key, name, price, category, jobPays } ]
let job       = null; // a Director goal's checklist { title, rows: [ { text, state } ], pays }, or null (client/director.lua)
let cash      = null; // cash on the player, from ui.lua; null (shown as a dash) until it arrives
let engines   = [];   // [ { model, label, class, hp, torque, soundOnly } ] for the engine swap
let padOn     = false; // a controller is the device (ui.lua 'padDevice'): pad hints and rings show (padPress)
let isOpen    = false;
let builder   = false; // setting how a Director car spawns (client/look.lua): no services, no prices, Save not pay
let dev       = false; // developer mode on (ui.lua 'open', 'devMode'): the basket offers Free; the server checks again
let orbiting  = false;
let standardCam = false; // the standard camera is on: the orbit shot only, no part shots (client/camera.lua)

// Where we are:
//   []                                  front counter (Repair, Customise)
//   ['customise']                       the shelves
//   ['customise', sectionKey]           one shelf's categories
//   ['customise', sectionKey, catKey]   one category's parts
// By category key, not slot: all thirteen wheel ranges are slot 23.
let path = [];

// What is on the car now, one entry per slot: { [slot]: { key, index } }.
const previewing = {};

// The dialogs.
let basketOpen  = false;
let confirmOpen = false;

// The pad pictures ship with the page (html/img/pad, whip_core's SVGs unchanged): from another origin
// (cfx-nui-whip_core) they taint the canvases they are drawn into and WebGL refuses them, blanking every hint.
const view = createView(document.getElementById('app'), { padImg: window.WHIP_PAD_IMG || 'img/pad/' });

/* ---- talking to Lua ------------------------------------------------------- */

function post(name, data) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');

const basketTotal = () => basket.reduce((t, b) => t + (b.price || 0), 0);

/* ---- where we are ---------------------------------------------------------- */

function currentSection() {
    return sections.find((s) => s.key === path[1]) || null;
}

function currentCategory() {
    const cats = catalogue[path[1]] || [];
    return cats.find((c) => String(c.key) === String(path[2])) || null;
}

// This shelf's basket line, by key (a Sport wheel marks only the Sport shelf).
function basketEntryByKey(key) {
    return basket.find((b) => String(b.key) === String(key)) || null;
}

// A service card toggles its basket line. Never previewed: a previewed repair is a free repair.
function toggleService(id) {
    const def = services.find((s) => s.id === id);
    if (!def) return;

    if (basketEntryByKey(id)) { post('remove', { slot: id }); return; }

    post('add', {
        slot: id, index: 1, key: id,
        name: def.name, price: def.price, category: 'Service',
    });
}

// Tells Lua the open shelf and category so the camera frames it. Called after every move.
function syncFocus() {
    const cat = currentCategory();
    post('focus', {
        section: path[1] || null,
        slot: cat ? cat.slot : null,
    });
}

/* ---- the picker: paint, engines, tuning cards ----
   A column on the left; the camera moves the car to its right (sendShift). Short lists: paint by
   colour family, engines by vehicle type or search. ↑ ↓ try each row on the car, Enter or a second
   click adds it, Esc goes back. */

// Category kinds that open the picker; the rest use the rail.
const PICKER_KINDS = { paint: true, engine: true, stance: true, setup: true, drive: true };

// key: open category (null = shut); items: the list; cursor: keyboard row (-1 = none);
// reveal: scroll the cursor into view on the next draw.
const pick = { key: null, items: [], cursor: -1, reveal: false };

/* Tells Lua how far to move the car for the column: half its width as a share of the screen, measured
   from where the column stands. client/camera.lua (Cam.setScreenShift) turns the camera. */
let shiftSent = null;
function sendShift(open) {
    const s = open ? Math.round(view.columnEdge() / window.innerWidth / 2 * 1000) / 1000 : 0;
    if (s === shiftSent) return;
    shiftSent = s;
    post('layout', { shift: s });
}

// Key previews wait until the key rests (holding ↓ shouldn't repaint 30 times); clicks are instant.
let previewTimer = null;
function previewNow(data)      { clearTimeout(previewTimer); post('preview', data); }
function previewSoon(data, ms) { clearTimeout(previewTimer); previewTimer = setTimeout(() => post('preview', data), ms); }

// A second click on the same row within 400 ms adds it. Not dblclick: the first click redraws the row.
let lastClick = { id: null, t: 0 };
function secondClick(id) {
    const now = performance.now();
    const second = lastClick.id === id && now - lastClick.t < 400;
    lastClick = second ? { id: null, t: 0 } : { id, t: now };
    return second;
}

function moveCursor(i) {
    pick.cursor = i;
    pick.reveal = true;
    render();
}

// One step, stopping at the ends. From no cursor, ↓ goes to the top and ↑ to the bottom.
function stepFrom(cursor, n, d) {
    if (!n) return -1;
    if (cursor < 0) return d > 0 ? 0 : n - 1;
    return Math.max(0, Math.min(n - 1, cursor + d));
}

// Key hints. A hint is markup for view.js: [x] a key chip, *x* bold. `pad`: the same on a controller,
// as [buttons, label], shown instead while a pad is the device (padOn).
const CAM_HINT = 'hold [right mouse] to turn the camera';
const PAD_CAM = [['rs', 'camera'], [['lt', 'rt'], 'zoom']];

/* ---- paint ---- */

/* Paints grouped by colour (the finish is a tag on the row). The family comes from the name, since
   GTA's hex can mislead (Midnight Blue is near black); test order settles two-colour names ("Black
   Blue" is black, "Choco Orange" brown). Names with no colour word fall back to the hex.
   `dot`: the family's disc as a paint (kit.js FlatSwatch: Metals draws the silver sheen, Chameleon the wheel). */
const HUES = [
    { key: 'black',  name: 'Black',          dot: { hex: '#0c0d10', family: 'Classic' } },
    { key: 'grey',   name: 'Grey & Silver',  dot: { hex: '#8b919b', family: 'Metallic' } },
    { key: 'white',  name: 'White & Cream',  dot: { hex: '#f1f0ea', family: 'Classic' } },
    { key: 'red',    name: 'Red',            dot: { hex: '#b3131d', family: 'Classic' } },
    { key: 'orange', name: 'Orange',         dot: { hex: '#dc6410', family: 'Classic' } },
    { key: 'yellow', name: 'Yellow & Gold',  dot: { hex: '#e3aa00', family: 'Classic' } },
    { key: 'green',  name: 'Green',          dot: { hex: '#2e8b3a', family: 'Classic' } },
    { key: 'blue',   name: 'Blue',           dot: { hex: '#1d5fd6', family: 'Classic' } },
    { key: 'purple', name: 'Purple & Pink',  dot: { hex: '#9a2f8f', family: 'Classic' } },
    { key: 'brown',  name: 'Brown & Beige',  dot: { hex: '#7b5a39', family: 'Classic' } },
    { key: 'metal',  name: 'Chrome & Metal', dot: { hex: '#c9ced4', family: 'Metals', name: 'Chrome' } },
    { key: 'chameleon', name: 'Chameleon',   dot: { hex: '#2b6fd6', hex2: '#d1306f', family: 'Chameleon' } },
];

function hueOf(c) {
    const n = c.name.toLowerCase();
    const has = (...words) => words.some((w) => n.includes(w));
    // Colour-shift paints read as two colours at once: they get a family of their own.
    if (c.family === 'Chameleon') return 'chameleon';
    if (c.family === 'Metals') return 'metal';
    if (has('black')) return 'black';
    if (has('pink', 'purple')) return 'purple';
    if (has('white', 'cream')) return 'white';
    if (has('brown', 'beige', 'sand', ' tan', 'straw', 'honey', 'beechwood', 'choco', 'champagne', 'ivory')) return 'brown';
    if (has('orange')) return 'orange';
    if (has('red')) return 'red';
    if (has('yellow', 'gold', 'bronze')) return 'yellow';
    if (has('green', 'lime', 'olive', 'sea wash', 'foliage', 'drab')) return 'green';
    if (has('silver', 'grey', 'gray', 'graphite', 'gun metal', 'steel', 'alloy', 'anthracite')) return 'grey';
    if (has('blue')) return 'blue';
    return hueFromHex(c.hex);
}

function hueFromHex(hex) {
    const v = parseInt(String(hex).slice(1), 16) || 0;
    const r = (v >> 16 & 255) / 255, g = (v >> 8 & 255) / 255, b = (v & 255) / 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
    if (l < 0.08) return 'black';
    if (d < 0.08) return l > 0.7 ? 'white' : 'grey';
    let h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h = (h * 60 + 360) % 360;
    if (h < 15 || h >= 330) return 'red';
    if (h < 40) return l < 0.35 ? 'brown' : 'orange';
    if (h < 70) return 'yellow';
    if (h < 170) return 'green';
    if (h < 260) return 'blue';
    return 'purple';
}

// Finish tag text per family.
const FINISH = { Classic: 'Classic', Metallic: 'Metallic', Matte: 'Matte', Util: 'Utility', Worn: 'Worn', Metals: 'Metal', Chameleon: 'Chameleon' };

// A colour-shift paint's own finish, from its name: in their own group, this is what tells them apart.
function chameleonFinish(c) {
    if (/Flip$/.test(c.name)) return 'Flip';
    if (/Prismatic/.test(c.name)) return 'Prismatic';
    if (/Holographic/.test(c.name)) return 'Holographic';
    if (/^Anodized /.test(c.name)) return 'Anodized';
    return 'Pearl';
}

// The finish a swatch's tag shows.
function finishOf(c) {
    return c.family === 'Chameleon' ? chameleonFinish(c) : (FINISH[c.family] || c.family);
}

// "Metallic Torino Red" → "Torino Red"; the tag already says Metallic. Likewise "Green/Blue Flip" →
// "Green/Blue" and "Anodized Red Pearl" → "Red", the tag saying Flip or Anodized.
function shortName(c) {
    if (c.family === 'Chameleon') {
        return c.name.replace(/^Anodized /, '').replace(/ (Flip|Prismatic Pearl|Prismatic|Holographic|Pearl)$/, '') || c.name;
    }
    const first = c.name.split(' ')[0];
    const strip = first === c.family && c.family !== 'Metals' && c.name.length > first.length;
    return strip ? c.name.slice(first.length + 1) : c.name;
}

let hueLists = null;   // { family: [colour, ...] }, built once per visit
let paintHue = null;   // the family on show

function paintFamilies() {
    if (hueLists) return hueLists;
    hueLists = {};
    HUES.forEach((h) => { hueLists[h.key] = []; });
    palette.forEach((c) => hueLists[hueOf(c)].push(c));
    return hueLists;
}

function colourAt(index) {
    if (index === null || index === undefined) return null;
    return palette.find((c) => c.index === index) || null;
}

// The colour shown: the one tried on, else the basketed one.
function paintShown(cat) {
    const prev = previewing[String(cat.slot)];
    if (prev && prev.key === cat.key) return prev.index;
    const chosen = basketEntryByKey(cat.key);
    return chosen ? chosen.index : null;
}

function paintPicker(cat, fresh) {
    const lists = paintFamilies();
    const chosen = basketEntryByKey(cat.key);
    const shown = paintShown(cat);
    const worn = colourAt(cat.current);

    // Open on the family of what the car shows.
    if (fresh || !paintHue) {
        const c = colourAt(shown !== null ? shown : cat.current);
        paintHue = c ? hueOf(c) : HUES[0].key;
    }
    const hue = HUES.find((h) => h.key === paintHue) || HUES[0];
    const list = lists[hue.key];

    // ---- that family's shades ----
    pick.items = list;
    pick.cursor = list.findIndex((c) => c.index === shown);

    const items = list.map((c, i) => ({
        id: 'p' + c.index,
        swatch: c,
        name: shortName(c),
        // The fitted colour shows FITTED in place of its finish.
        tag: c.index === cat.current ? 'Fitted' : finishOf(c),
        tagOn: c.index === cat.current,
        selected: c.index === shown,
        basketed: !!chosen && chosen.index === c.index,
        cursor: i === pick.cursor,
        onClick: () => {
            pick.cursor = i;
            if (secondClick('p' + c.index)) addPaint(cat);
            else tryPaint(cat, c, false);
        },
    }));

    // ---- the foot ----
    const c = colourAt(shown);
    const onCar = !!c && c.index === cat.current;
    const inBasket = !!c && !!chosen && chosen.index === c.index;

    return {
        key: cat.key, kind: 'paint',
        title: cat.name,
        sub: `${money(cat.price)} · ${palette.length} colours`,
        tools: {
            type: 'hues',
            hues: HUES.filter((h) => lists[h.key].length).map((h) => ({
                key: h.key, name: h.name, dot: h.dot,
                on: h.key === hue.key,
                // Blue pip: the family of the colour on the car.
                fitted: !!worn && hueOf(worn) === h.key,
                onClick: () => setHue(h.key),
            })),
            label: hue.name,
            count: String(list.length),
        },
        list: { type: 'rows', rows: 'paint', items, reveal: pick.reveal ? pick.cursor : -1, scrollKey: hue.key },
        foot: {
            chip: c || worn || null,
            name: c ? c.name : (worn ? worn.name : 'Pick a colour'),
            note: c ? (onCar ? 'On the car now' : inBasket ? 'In the basket' : 'Trying it on')
                    : (worn ? 'On the car now' : 'Nothing tried on yet'),
            buttons: [{
                id: 'add',
                label: onCar ? 'On the car' : inBasket ? 'In basket' : c ? `Add — ${money(cat.price)}` : 'Add',
                onClick: (c && !onCar && !inBasket) ? () => addPaint(cat) : null,
            }],
        },
        hint: {
            kb: ['[↑][↓] try on', '[←][→] colour', '[enter] add', '[esc] back', CAM_HINT],
            pad: [['dpad', '↑↓ try on · ←→ colour'], ['a', 'add'], ['b', 'back']].concat(PAD_CAM),
        },
    };
}

function tryPaint(cat, c, fromKeys) {
    previewing[String(cat.slot)] = { key: cat.key, index: c.index };
    const data = { slot: cat.slot, index: c.index };
    // On a pad at once, as a part is; the keyboard's arrows wait 90 ms.
    if (fromKeys && !padOn) previewSoon(data, 90); else previewNow(data);
    pick.reveal = fromKeys;
    render();
}

// Adds the shown colour; the colour already on the car can be tried on but not bought.
function addPaint(cat) {
    const c = colourAt(paintShown(cat));
    if (!c || c.index === cat.current) return;
    const chosen = basketEntryByKey(cat.key);
    if (chosen && chosen.index === c.index) return;
    post('add', {
        slot: cat.slot, index: c.index, key: cat.key,
        name: c.name, price: cat.price, category: cat.name,
    });
}

function setHue(key) {
    if (key === paintHue) return;
    paintHue = key;
    pick.cursor = -1;
    render();
}

// ← → cycle the families.
function stepHue(d) {
    const lists = paintFamilies();
    const keys = HUES.map((h) => h.key).filter((k) => lists[k].length);
    const i = keys.indexOf(paintHue);
    setHue(keys[(i + d + keys.length) % keys.length]);
}

function paintKey(cat, k) {
    if (k === 'ArrowDown' || k === 'ArrowUp') {
        const i = stepFrom(pick.cursor, pick.items.length, k === 'ArrowDown' ? 1 : -1);
        if (i >= 0 && i !== pick.cursor) { pick.cursor = i; tryPaint(cat, pick.items[i], true); }
        return true;
    }
    if (k === 'ArrowLeft' || k === 'ArrowRight') { stepHue(k === 'ArrowRight' ? 1 : -1); return true; }
    if (k === 'Enter') { addPaint(cat); return true; }
    return false;
}

/* ---- engines: pick a vehicle type, then an engine; or search all ---- */

const CLASS_NAMES = {
    0: 'Compacts', 1: 'Sedans', 2: 'SUVs', 3: 'Coupes', 4: 'Muscle', 5: 'Sports Classics',
    6: 'Sports', 7: 'Super', 8: 'Motorcycles', 9: 'Off-road', 10: 'Industrial', 11: 'Utility',
    12: 'Vans', 14: 'Boats', 15: 'Helicopters', 16: 'Planes', 17: 'Service', 18: 'Emergency',
    19: 'Military', 20: 'Commercial', 22: 'Open Wheel',
};
const className = (c) => CLASS_NAMES[c] || 'Other';

// Type order: fast cars first, sound-only classes last; unlisted classes go on the end.
const CLASS_ORDER = [7, 6, 5, 4, 3, 1, 0, 2, 9, 8, 22, 12, 11, 10, 20, 17, 18, 19, 14, 15, 16];

let engineView  = 'types';   // 'types', or 'list' (one type's engines)
let engineClass = null;      // the type on show
let engineQuery = '';        // non-empty searches every type
let engineSort  = 'name';    // 'name' or 'power'
let typeCursor  = -1;        // keyboard place on the types, kept while a type is open

function engineByModel(model) {
    return engines.find((e) => e.model === model) || null;
}

// "344 hp · 608 Nm" (server/engines.lua works both out), or '' when the list has no figures.
function enginePower(e) {
    if (!e || !(e.hp > 0) || !(e.torque > 0)) return '';
    return `${e.hp.toLocaleString('en-US')} hp · ${e.torque.toLocaleString('en-US')} Nm`;
}

// While the search box has focus, Lua stops passing keys to the game (else W would rev the car).
function typing(on) { post('typing', { on: !!on }); }

// The engine shown: the one tried on, else the basketed one.
function engineShown(cat) {
    const prev = previewing['engine'];
    if (prev && prev.key === cat.key) return prev.model;
    const chosen = basketEntryByKey(cat.key);
    return chosen ? chosen.engine : null;
}

function engineTypeOrder() {
    const present = new Set(engines.map((e) => e.class));
    const known = CLASS_ORDER.filter((c) => present.has(c));
    const rest = [...present].filter((c) => !CLASS_ORDER.includes(c)).sort((a, b) => a - b);
    return known.concat(rest);
}

let maxHp = 1;   // the strongest engine, for the power bars

function enginePicker(cat, fresh) {
    if (fresh) {
        engineView = 'types'; engineClass = null; engineQuery = ''; engineSort = 'name';
        typeCursor = -1;
    }
    const q = engineQuery.trim().toLowerCase();
    const viewKind = q ? 'search' : engineView;
    const chosen = basketEntryByKey(cat.key);
    const shown = engineShown(cat);

    // ---- title ----
    let title = cat.name, sub = `${money(cat.price)} · ${engines.length} engines`;
    if (viewKind === 'list') {
        const n = engines.filter((e) => e.class === engineClass).length;
        title = className(engineClass);
        sub = `${n} engines · ${money(cat.price)} to fit`;
    }

    let list;
    if (viewKind === 'types') list = engineTypes(cat);
    else {
        list = engineRows(cat, viewKind, q, chosen, shown);
        if (viewKind === 'search') sub = list.items.length === 1 ? '1 engine matches' : `${list.items.length} engines match`;
    }

    // ---- the foot ----
    const isStock = shown === 'stock';
    const eng = shown && !isStock ? engineByModel(shown) : null;
    const fitted = cat.current ? engineByModel(cat.current) : null;
    const onCar = (isStock && !cat.current) || (!!eng && eng.model === cat.current);
    const inBasket = !!shown && !!chosen && chosen.engine === shown;
    const price = isStock ? 0 : cat.price;
    let note = 'On the car now';
    if (shown && !onCar) {
        note = inBasket ? 'In the basket'
             : isStock ? 'The engine it came with'
             : eng ? [className(eng.class), enginePower(eng) || null, eng.soundOnly ? 'sound only' : null]
                         .filter(Boolean).join(' · ')
             : '';
    }

    return {
        key: cat.key, kind: 'engine', title, sub,
        tools: {
            type: 'search',
            value: engineQuery,
            placeholder: `Search ${engines.length} engines`,
            sort: viewKind === 'types' ? null : engineSort,
            onInput: (v) => { engineQuery = v; pick.cursor = -1; render(); },
            onFocus: () => typing(true),
            onBlur: () => typing(false),
            onSort: (k) => { engineSort = k; pick.cursor = -1; render(); },
        },
        list,
        foot: {
            engine: true,
            name: isStock ? 'Stock engine' : eng ? eng.label : (fitted ? fitted.label : (cat.currentLabel || 'Stock engine')),
            note,
            buttons: [
                // Back to the car's own engine; off when it already has it.
                { id: 'stock', label: 'Stock', ghost: true,
                  onClick: (isStock || (!shown && !cat.current)) ? null : () => tryEngine(cat, 'stock', false) },
                { id: 'add', label: onCar ? 'On the car' : inBasket ? 'In basket'
                       : shown ? `Add — ${price === 0 ? 'Free' : money(price)}` : 'Add',
                  onClick: (shown && !onCar && !inBasket) ? () => addEngine(cat) : null },
            ],
        },
        hint: viewKind === 'types'
            ? { kb: ['[arrows] move', '[enter] open', '[esc] back', CAM_HINT],
                pad: [['dpad', 'move'], ['a', 'open'], ['b', 'back']].concat(PAD_CAM) }
            : { kb: ['[↑][↓] try on', '[enter] add', '[esc] back', 'hold [W] to rev', CAM_HINT],
                pad: [['dpad', 'try on'], ['a', 'add'], ['x', 'stock'], ['b', 'back'], ['rt', 'hold to rev']].concat(PAD_CAM) },
    };
}

// The types, two to a row.
function engineTypes(cat) {
    const counts = {};
    const sounds = {};
    engines.forEach((e) => {
        counts[e.class] = (counts[e.class] || 0) + 1;
        sounds[e.class] = (sounds[e.class] === undefined ? true : sounds[e.class]) && !!e.soundOnly;
    });
    const fitted = cat.current ? engineByModel(cat.current) : null;
    const order = engineTypeOrder();
    pick.items = order;
    pick.cursor = typeCursor;
    return {
        type: 'grid', scrollKey: 'types',
        reveal: pick.reveal ? pick.cursor : -1,
        items: order.map((cls, i) => ({
            id: 't' + cls,
            name: className(cls),
            count: `${counts[cls]}${sounds[cls] ? ' · sound only' : ''}`,
            // Blue pip: the type of the car's current swap.
            fitted: !!fitted && fitted.class === cls,
            cursor: i === pick.cursor,
            onClick: () => openType(cls),
        })),
    };
}

function engineRows(cat, viewKind, q, chosen, shown) {
    let list = viewKind === 'search'
        ? engines.filter((e) => e.label.toLowerCase().includes(q) || e.model.includes(q))
        : engines.filter((e) => e.class === engineClass);
    if (engineSort === 'power') {
        list = list.slice().sort((a, b) => (b.hp || 0) - (a.hp || 0) || a.label.localeCompare(b.label));
    }
    pick.items = list;

    if (!list.length) {
        pick.cursor = -1;
        return { type: 'empty', items: [], text: 'No engine by that name. Part of it is enough — "zen" finds the Zentorno.' };
    }

    pick.cursor = list.findIndex((e) => e.model === shown);
    return {
        type: 'rows', rows: 'engine',
        scrollKey: `${viewKind}|${engineClass}|${q}|${engineSort}`,
        reveal: pick.reveal ? pick.cursor : -1,
        items: list.map((e, i) => ({
            id: 'e' + e.model,
            name: e.label,
            // One tag: Fitted, else Sound only, else (in a search) its type.
            tag: e.model === cat.current ? 'Fitted' : e.soundOnly ? 'Sound only' : viewKind === 'search' ? className(e.class) : '',
            tagOn: e.model === cat.current,
            power: enginePower(e),
            hp: (e.hp || 0) / maxHp,
            selected: e.model === shown,
            basketed: !!chosen && chosen.engine === e.model,
            cursor: i === pick.cursor,
            onClick: () => {
                pick.cursor = i;
                if (secondClick('e' + e.model)) addEngine(cat);
                else tryEngine(cat, e.model, false);
            },
        })),
    };
}

function openType(cls) {
    const order = engineTypeOrder();
    typeCursor = order.indexOf(cls);
    engineView = 'list';
    engineClass = cls;
    pick.cursor = -1;
    pick.reveal = true;
    render();
}

function leaveType() {
    engineView = 'types';
    pick.reveal = true;
    render();
}

function tryEngine(cat, model, fromKeys) {
    previewing['engine'] = { key: cat.key, model };
    const data = { slot: 'engine', index: 0, engine: model };
    // Longer key delay: each swap restarts the engine sound.
    if (fromKeys) previewSoon(data, 260); else previewNow(data);
    pick.reveal = fromKeys;
    render();
}

// Adds the shown engine, unless the car already has it (or is stock and asking for stock).
function addEngine(cat) {
    const model = engineShown(cat);
    if (!model) return;
    const isStock = model === 'stock';
    const eng = isStock ? null : engineByModel(model);
    if (!isStock && !eng) return;
    if ((isStock && !cat.current) || (eng && eng.model === cat.current)) return;
    const chosen = basketEntryByKey(cat.key);
    if (chosen && chosen.engine === model) return;
    const price = isStock ? 0 : cat.price;
    post('add', {
        slot: 'engine', index: 0, key: cat.key, category: 'Engine Swap',
        name: isStock ? 'Stock engine' : eng.label, price, engine: model,
    });
}

function engineKey(cat, k) {
    const viewKind = engineQuery.trim() ? 'search' : engineView;
    if (viewKind === 'types') {
        const d = k === 'ArrowRight' ? 1 : k === 'ArrowLeft' ? -1 : k === 'ArrowDown' ? 2 : k === 'ArrowUp' ? -2 : 0;
        if (d) {
            const n = pick.items.length;
            typeCursor = typeCursor < 0 ? 0 : Math.max(0, Math.min(n - 1, typeCursor + d));
            moveCursor(typeCursor);
            return true;
        }
        if (k === 'Enter') {
            const cls = pick.items[Math.max(0, typeCursor)];
            if (cls !== undefined) openType(cls);
            return true;
        }
        return false;
    }
    if (k === 'ArrowDown' || k === 'ArrowUp') {
        const i = stepFrom(pick.cursor, pick.items.length, k === 'ArrowDown' ? 1 : -1);
        if (i >= 0 && i !== pick.cursor) { pick.cursor = i; tryEngine(cat, pick.items[i].model, true); }
        return true;
    }
    if (k === 'ArrowLeft' && viewKind === 'list') { leaveType(); return true; }
    if (k === 'Enter') { addEngine(cat); return true; }
    return false;
}

/* ---- stance, handling, drivetrain: sliders ----
   Bought once per car, then free to adjust. Stance previews live (only you see it); handling and
   drivetrain are felt on the road. */

const STANCE_FIELDS = [
    // travel: adds "· travel N%" when Config.Tuning.Stance.Travel is on.
    { key: 'height',  range: 'Height', label: 'Ride height',  unit: 'cm', hint: '+ raises', signed: true, travel: true },
    { key: 'trackF',  range: 'Track',  label: 'Front track',  unit: 'cm', hint: '+ pushes the wheels out', signed: true, axle: true },
    { key: 'trackR',  range: 'Track',  label: 'Rear track',   unit: 'cm', hint: '+ pushes the wheels out', signed: true, axle: true },
    { key: 'camberF', range: 'Camber', label: 'Front camber', unit: '°',  hint: '− tilts the tops in', signed: true, axle: true },
    { key: 'camberR', range: 'Camber', label: 'Rear camber',  unit: '°',  hint: '− tilts the tops in', signed: true, axle: true },
    { key: 'width',   range: 'Width',  label: 'Wheel width',  unit: '%',  hint: 'custom rims only', wheels: true, zero: 100 },
    { key: 'size',    range: 'Size',   label: 'Wheel size',   unit: '%',  hint: 'tyre and rim — custom rims only', wheels: true, zero: 100 },
];

// Drive layout (a choice) and AWD's front/rear split.
const DRIVE_FIELDS = [
    { key: 'layout', type: 'choice', label: 'Drive', hint: 'which wheels the engine drives',
      options: [['stock', 'Stock'], ['fwd', 'FWD'], ['rwd', 'RWD'], ['awd', 'AWD']] },
    // Reversed: drag right = more to the rear. The value kept is still the front's share.
    { key: 'front', range: 'Split', label: 'AWD split', unit: '%', hint: '← more to the front · more to the rear →',
      awdOnly: true, split: true, reverse: true, zero: 50 },
];

// % of the car's own (100 = stock). Steering also shows degrees.
const SETUP_FIELDS = [
    { key: 'springs',   range: 'Springs',   label: 'Springs',        unit: '%', hint: '+ stiffer · − softer', zero: 100 },
    { key: 'dampers',   range: 'Dampers',   label: 'Dampers',        unit: '%', hint: '+ less bounce', zero: 100 },
    { key: 'antiroll',  range: 'AntiRoll',  label: 'Anti-roll bars', unit: '%', hint: '+ less lean in corners', zero: 100 },
    { key: 'steering',  range: 'Steering',  label: 'Steering angle', unit: '%', hint: '+ tighter turns', steer: true, zero: 100 },
    { key: 'grip',      range: 'Grip',      label: 'Tyre grip',      unit: '%', hint: '− slides more · + holds more', zero: 100 },
    { key: 'handbrake', range: 'Handbrake', label: 'Handbrake',      unit: '%', hint: '+ locks the rear harder', zero: 100 },
];

// Slider categories: fields, the data key saved, neutral values, and whether the car previews it.
const SLIDERS = {
    stance: {
        fields: STANCE_FIELDS, data: 'stance', name: 'Stance', live: true,
        neutral: () => ({ height: 0, trackF: 0, trackR: 0, camberF: 0, camberR: 0, width: 100, size: 100 }),
        note: 'Only you see it until it is saved',
    },
    setup: {
        fields: SETUP_FIELDS, data: 'setup', name: 'Handling', live: false,
        neutral: () => ({ springs: 100, dampers: 100, antiroll: 100, steering: 100, grip: 100, handbrake: 100 }),
        note: 'Felt on the road — come back to adjust it free',
    },
    drive: {
        fields: DRIVE_FIELDS, data: 'drive', name: 'Drivetrain', live: false,
        neutral: () => ({ layout: 'stock', front: 50 }),
        note: 'Felt on the road — switch it again any time, free',
    },
};

const drafts = { stance: null, setup: null, drive: null };   // unsaved slider values, kept for the visit
let stanceTimer = null;

// Field equal in both? The AWD split only counts when either side is AWD.
function sameField(f, a, b) {
    if (f.awdOnly && a.layout !== 'awd' && b.layout !== 'awd') return true;
    if (f.type === 'choice') return String(a[f.key]) === String(b[f.key]);
    return Number(a[f.key]) === Number(b[f.key]);
}
function sameValues(fields, a, b) { return fields.every((f) => sameField(f, a, b)); }

function previewStance() {
    clearTimeout(stanceTimer);
    // Throttled: not on every pixel of a drag.
    stanceTimer = setTimeout(() => post('preview', { slot: 'stance', index: 0, stance: drafts.stance }), 60);
}

// Suspension travel % at a ride height; mirrors TuningTravelFactor (shared/tuning.lua). null when off.
function travelPct(cat, height) {
    const t = (cat.ranges || {}).Travel;
    if (!t || !t.perCm) return null;
    const f = Math.max(t.min, Math.min(t.max, 1 + Number(height) * t.perCm));
    return Math.round(f * 100);
}

// Slider readout: "+2.5 cm", "−6°", "110% · 38°" (steering), plus travel on ride height.
function sliderText(f, v, cat) {
    const n = Number(v);
    if (f.split) return `Front ${n} · Rear ${100 - n}`;
    const num = f.signed && n > 0 ? `+${n}` : n < 0 ? `−${-n}` : String(n);
    let t = f.unit === 'cm' ? `${num} cm` : `${num}${f.unit}`;
    if (f.steer && cat.steerDeg) t += ` · ${Math.round(cat.steerDeg * n / 100)}°`;
    if (f.travel) {
        const pct = travelPct(cat, n);
        if (pct !== null) t += ` · travel ${pct}%`;
    }
    return t;
}

// Custom rims fitted, basketed or tried on? GTA only sizes custom rims.
function hasCustomRims(cat) {
    if (cat.customWheels) return true;
    const b = basket.find((x) => String(x.slot) === '23');
    if (b && b.index >= 0) return true;
    const p = previewing['23'];
    return !!p && p.index >= 0;
}

// This car's sliders: no per-axle stance on bikes.
function sliderFields(cat, def) {
    return def.fields.filter((f) => (f.type === 'choice' || (cat.ranges || {})[f.range]) && !(f.axle && cat.wheels < 4));
}

// A choice's label; "Stock" names the car's own layout.
function choiceText(f, v, cat) {
    const o = f.options.find((x) => x[0] === v);
    if (v === 'stock' && cat.stockLayout) return `Stock (${cat.stockLayout.toUpperCase()})`;
    return o ? o[1] : String(v);
}

function sliderPicker(cat) {
    const def = SLIDERS[cat.kind];
    const chosen = basketEntryByKey(cat.key);
    if (!drafts[cat.kind]) drafts[cat.kind] = Object.assign(def.neutral(), chosen ? chosen[def.data] : cat.current);
    const draft = drafts[cat.kind];
    const saved = Object.assign(def.neutral(), cat.current);
    const unchanged = sameValues(def.fields, draft, saved);
    const inBasket = !!chosen && !!chosen[def.data]
        && sameValues(def.fields, draft, Object.assign(def.neutral(), chosen[def.data]));
    const changes = def.fields.filter((f) => !sameField(f, draft, saved)).length;
    const rims = hasCustomRims(cat);

    const fields = sliderFields(cat, def);
    pick.items = fields;
    if (pick.cursor >= fields.length) pick.cursor = fields.length - 1;

    const items = fields.map((f, i) => {
        const base = { id: f.key, label: f.label, hint: f.hint, cursor: i === pick.cursor, onPick: () => { pick.cursor = i; } };
        // A choice is a row of keys, not a slider.
        if (f.type === 'choice') {
            return Object.assign(base, {
                type: 'choice',
                valueText: choiceText(f, draft[f.key], cat),
                options: f.options.map(([k, label]) => ({
                    k, label, on: draft[f.key] === k,
                    onClick: () => { pick.cursor = i; draft[f.key] = k; render(); },
                })),
            });
        }
        const r = cat.ranges[f.range];
        // Width/size need custom rims; the split needs AWD.
        const awdOff = !!f.awdOnly && draft.layout !== 'awd';
        const off = (!!f.wheels && !rims) || awdOff;
        // A reversed field shows (min + max − value), so dragging right lowers the value.
        const flip = (v) => (f.reverse ? r.min + r.max - Number(v) : Number(v));
        const zero = f.zero !== undefined ? f.zero : (f.signed ? 0 : r.min);
        return Object.assign(base, {
            type: 'slider',
            valueText: awdOff ? 'AWD only' : off ? 'fit custom rims first' : sliderText(f, draft[f.key], cat),
            min: r.min, max: r.max, step: r.step,
            value: flip(draft[f.key]),
            zero: Math.max(r.min, Math.min(r.max, flip(zero))),
            off,
            onInput: (v) => {
                pick.cursor = i;
                const nv = Math.round(Math.max(r.min, Math.min(r.max, flip(v))) * 1000) / 1000;
                if (nv === draft[f.key]) return;
                draft[f.key] = nv;
                if (def.live) previewStance();
                render();
            },
        });
    });

    return {
        key: cat.key, kind: cat.kind,
        title: cat.name,
        sub: cat.owned ? 'Yours — adjust it freely' : `${money(cat.price)} the first time, free after`,
        tools: null,
        list: { type: 'sliders', items, reveal: pick.reveal ? pick.cursor : -1, scrollKey: cat.key },
        foot: {
            name: unchanged ? 'As the car is' : `${changes} ${changes === 1 ? 'change' : 'changes'}`,
            note: inBasket ? 'In the basket' : unchanged ? 'Nothing to save' : def.note,
            buttons: [
                { id: 'reset', label: 'Reset', ghost: true,
                  onClick: sameValues(def.fields, draft, def.neutral()) ? null : () => {
                      drafts[cat.kind] = def.neutral();
                      if (def.live) previewStance();
                      render();
                  } },
                { id: 'save', label: unchanged ? 'No change' : inBasket ? 'In basket' : `Save — ${cat.price === 0 ? 'Free' : money(cat.price)}`,
                  onClick: (!unchanged && !inBasket) ? () => saveSliders(cat) : null },
            ],
        },
        hint: {
            kb: ['[↑][↓] choose', '[←][→] adjust', '[enter] save', '[esc] back', CAM_HINT],
            pad: [['dpad', '↑↓ choose · ←→ adjust'], ['a', 'save'], ['x', 'reset'], ['b', 'back']].concat(PAD_CAM),
        },
    };
}

function saveSliders(cat) {
    const def = SLIDERS[cat.kind];
    const draft = drafts[cat.kind];
    if (!draft || sameValues(def.fields, draft, Object.assign(def.neutral(), cat.current))) return;
    const line = { slot: cat.slot, index: 0, key: cat.key, category: 'Tuning', name: def.name, price: cat.price };
    line[def.data] = Object.assign({}, draft);
    post('add', line);
}

function sliderKey(cat, k) {
    const def = SLIDERS[cat.kind];
    if (k === 'ArrowDown' || k === 'ArrowUp') {
        const i = stepFrom(pick.cursor, pick.items.length, k === 'ArrowDown' ? 1 : -1);
        if (i >= 0) moveCursor(i);
        return true;
    }
    if (k === 'ArrowLeft' || k === 'ArrowRight') {
        if (pick.cursor < 0) { moveCursor(0); return true; }
        const f = pick.items[pick.cursor];
        const draft = drafts[cat.kind];
        // A choice cycles its options.
        if (f.type === 'choice') {
            const keys = f.options.map((o) => o[0]);
            const at = keys.indexOf(draft[f.key]);
            draft[f.key] = keys[(at + (k === 'ArrowRight' ? 1 : -1) + keys.length) % keys.length];
            render();
            return true;
        }
        const r = cat.ranges[f.range];
        if (f.wheels && !hasCustomRims(cat)) return true;
        if (f.awdOnly && draft.layout !== 'awd') return true;
        // → moves the slider right (down for a reversed field).
        const up = (k === 'ArrowRight') !== !!f.reverse;
        const v = Number(draft[f.key]) + (up ? r.step : -r.step);
        // Rounded so 0.5 steps don't drift to 2.4999999.
        draft[f.key] = Math.round(Math.max(r.min, Math.min(r.max, v)) * 1000) / 1000;
        if (def.live) previewStance();
        render();
        return true;
    }
    if (k === 'Enter') { saveSliders(cat); return true; }
    return false;
}

/* ---- opening and shutting the picker ---- */

function pickerModel(cat) {
    const fresh = pick.key !== cat.key;
    if (fresh) {
        pick.key = cat.key;
        pick.cursor = -1;
    }
    let m;
    if (cat.kind === 'paint') m = paintPicker(cat, fresh);
    else if (cat.kind === 'engine') m = enginePicker(cat, fresh);
    else m = sliderPicker(cat);
    m.onBack = pickerBack;
    pick.reveal = false;
    return m;
}

function closePicker() {
    if (pick.key !== null) {
        pick.key = null;
        pick.items = []; pick.cursor = -1;
        // Blur the search box, or the game's keys stay held back (typing()).
        view.blurSearch();
    }
}

// Back one step: out of a search, out of a type, then out of the category.
function pickerBack() {
    const cat = currentCategory();
    if (cat && cat.kind === 'engine') {
        if (engineQuery.trim()) {
            engineQuery = '';
            render();
            return;
        }
        if (engineView === 'list') { leaveType(); return; }
    }
    goBack();
}

function pickerKey(k) {
    const cat = currentCategory();
    if (!cat) return false;
    if (k === 'Escape') { pickerBack(); return true; }
    if (cat.kind === 'paint') return paintKey(cat, k);
    if (cat.kind === 'engine') return engineKey(cat, k);
    if (SLIDERS[cat.kind]) return sliderKey(cat, k);
    return false;
}

/* ---- a controller ----------------------------------------------------------------------------------
   client/ui.lua reads the pad and sends its presses ('pad': up down left right a b x y; `rep` while a
   direction is held; the left stick counts as the D-pad). They work the shop the way the keys do:
     the rail     ← → browse the cards (the one picked is ringed; a part is tried on as it is ringed), A opens
                  it (a part: adds it to the basket), X adds it to the basket, Y opens the basket, B goes
                  back (leaves, from the counter)
     the picker   the D-pad is the arrows, A is Enter (add / save), B is Esc (back), X the foot's other
                  button (Stock / Reset), Y the basket
     the basket   the D-pad moves between its buttons, A presses, B closes
     leaving      the D-pad moves between Stay and Leave, A presses, B stays
   The right stick turns the camera and the triggers zoom (client/camera.lua). */

const railAtByPath = {};   // the card the pad is on, per rail (path), so going back lands where it was
let dlgFocusId = null;     // the dialog button the pad is on
let lastModel = null;      // the model last drawn: the cards and buttons a press acts on

function railKey() { return path.join('/'); }

/* On a pad, whatever is highlighted is tried on at once (no delay, so fast scrolling still shows each part).
   The pickers' cursors already preview as they move; this does the same for parts on a shelf. With a mouse
   a click tries a part on. */
function padTryHighlighted() {
    if (pick.key !== null || path.length !== 3 || !lastModel || !lastModel.rail) return;
    const cards = lastModel.rail.cards;
    if (!cards.length) return;
    const card = cards[Math.min(railAtByPath[railKey()] || 0, cards.length - 1)];
    if (card && card.onHighlight) card.onHighlight();
}

function setPadMode(on) {
    const was = padOn;
    padOn = !!on;
    if (!padOn) dlgFocusId = null;
    if (isOpen) render();   // the hints and rings for the device
    // The pad picked up on a shelf of parts: try the ringed part on now, or A would add a part the player
    // never saw on the car (a shelf opened with the mouse).
    if (isOpen && padOn && !was) padTryHighlighted();
}

/* A dialog on a pad. It opens on its safe button — Keep shopping, Stay — so a press too many never pays
   or leaves: paying is a step down onto Cash or Bank. */
function padDialog(which, cmd, safe, close) {
    const btns = view.dialogButtons(which);   // [{ id, x, y, onClick }] — shown and enabled, in screen px
    const ids = btns.map((b) => b.id);
    if (!dlgFocusId || !ids.includes(dlgFocusId)) dlgFocusId = ids.includes(safe) ? safe : (ids[0] || null);
    if (cmd === 'b') { dlgFocusId = null; close(); return; }
    if (!dlgFocusId) { render(); return; }
    const at = btns.find((b) => b.id === dlgFocusId);
    if (cmd === 'a') {
        at.onClick();
        if (!view.dialogButtons(which).some((b) => b.id === dlgFocusId)) dlgFocusId = null;
        render();
        return;
    }
    if (cmd === 'up' || cmd === 'down' || cmd === 'left' || cmd === 'right') {
        // The nearest button that way from the one picked: along the direction, then off the line three times over.
        let best = null, bestScore = Infinity;
        for (const b of btns) {
            if (b === at) continue;
            const dx = b.x - at.x, dy = b.y - at.y;
            const along = cmd === 'right' ? dx : cmd === 'left' ? -dx : cmd === 'down' ? dy : -dy;
            if (along <= 1) continue;
            const off = (cmd === 'left' || cmd === 'right') ? Math.abs(dy) : Math.abs(dx);
            const s = along + off * 3;
            if (s < bestScore) { bestScore = s; best = b; }
        }
        if (best) dlgFocusId = best.id;
    }
    render();
}

const PAD_KEYS = { up: 'ArrowUp', down: 'ArrowDown', left: 'ArrowLeft', right: 'ArrowRight', a: 'Enter', b: 'Escape' };

function padPress(cmd) {
    if (!isOpen) return;
    if (confirmOpen) {
        padDialog('confirm', cmd, 'stay', () => { confirmOpen = false; render(); });
        return;
    }
    if (basketOpen) {
        padDialog('basket', cmd, 'keep', closeBasket);
        return;
    }
    if (cmd === 'y') { openBasket(); return; }
    if (cmd === 'rb') { toggleCamera(); return; }

    // The picker: its own keys.
    if (pick.key !== null) {
        if (PAD_KEYS[cmd]) { pickerKey(PAD_KEYS[cmd]); return; }
        if (cmd === 'x' && lastModel && lastModel.picker) {
            const other = lastModel.picker.foot.buttons.find((b) => b.ghost && b.onClick);
            if (other) other.onClick();
        }
        return;
    }

    // The rail.
    const cards = lastModel && lastModel.rail ? lastModel.rail.cards : [];
    const at = Math.min(railAtByPath[railKey()] || 0, Math.max(0, cards.length - 1));
    if (cmd === 'left' || cmd === 'right') {
        if (!cards.length) return;
        railAtByPath[railKey()] = Math.max(0, Math.min(cards.length - 1, at + (cmd === 'right' ? 1 : -1)));
        render();
        padTryHighlighted();   // a part, highlighted, is tried on
    } else if (cmd === 'a') {
        const onParts = path.length === 3;
        // A on a part adds it to the basket, as X does (highlighting already tried it on). A part already
        // fitted can't be bought: A tries it on.
        if (onParts && cards[at] && cards[at].onAdd) cards[at].onAdd();
        else if (cards[at]) cards[at].onOpen();
        // A on a category: its shelf of parts opens, and the part the ring lands on is tried on.
        if (!onParts) padTryHighlighted();
    } else if (cmd === 'x') {
        if (cards[at] && cards[at].onAdd) cards[at].onAdd();
    } else if (cmd === 'b') {
        if (path.length) goBack(); else requestLeave();
    }
}

/* ---- the rail ---------------------------------------------------------------- */

function railModel() {
    const cards = [];
    let empty = null;

    // ---- level 0: the front counter (services, Customise, Basket) ----
    if (path.length === 0) {
        // (A repair is no part of how a car spawns.)
        if (!builder) services.forEach((s) => {
            const inBasket = !!basketEntryByKey(s.id);
            cards.push({
                id: 'svc:' + s.id, kicker: 'SERVICE', name: s.name, sub: s.desc, price: s.price,
                big: true, basketed: inBasket,
                add: { label: inBasket ? 'Remove' : 'Add', strong: inBasket },
                // Card and button both toggle.
                onOpen: () => toggleService(s.id),
                onAdd:  () => toggleService(s.id),
            });
        });

        // No shelves at all (only the car's owner may customise it: client/session.lua): the counter is Repair alone.
        if (sections.some((s) => (catalogue[s.key] || []).length > 0)) cards.push({
            id: 'customise', name: 'Customise', sub: 'Bodywork, wheels, paint, performance', big: true, nav: true,
            onOpen: () => { path = ['customise']; syncFocus(); render(); },
        });

        // Opens the basket dialog, even when empty. Setting how a car spawns, the basket is what it spawns with.
        const n = basket.length;
        cards.push({
            id: 'basket', name: builder ? 'Spawns with' : 'Basket', big: true, nav: true,
            sub: builder ? (n ? `${n} ${n === 1 ? 'part' : 'parts'} · open it to save` : 'Nothing picked yet')
                : n ? `${n} ${n === 1 ? 'item' : 'items'} · ${money(basketTotal())}` : 'Nothing in it yet',
            onOpen: openBasket,
        });
    }

    // ---- level 1: the shelves ----
    else if (path.length === 1) {
        sections.forEach((s) => {
            const cats = catalogue[s.key] || [];
            if (!cats.length) return;   // nothing this car supports — skip it entirely
            cards.push({
                id: 'sec:' + s.key, name: s.name, big: true, nav: true,
                sub: `${cats.length} ${cats.length === 1 ? 'category' : 'categories'}`,
                art: SHELF_ART[s.key] || null,
                onOpen: () => { path = ['customise', s.key]; syncFocus(); render(); },
            });
        });
        if (!cards.length) empty = 'This vehicle cannot be customised here.';
    }

    // ---- level 2: categories on a shelf ----
    else if (path.length === 2) {
        (catalogue[path[1]] || []).forEach((c) => {
            const chosen = basketEntryByKey(c.key);
            // Paint and engine counts come from the shared lists; tuning shows what is fitted.
            const count = c.kind === 'paint' ? palette.length
                        : c.kind === 'engine' ? engines.length
                        : (c.items || []).length;
            let sub = chosen ? chosen.name : `${count} ${count === 1 ? 'option' : 'options'}`;
            if (!chosen && c.kind === 'engine') sub = c.currentLabel ? `Fitted: ${c.currentLabel}` : `Stock · ${count} engines`;
            if (!chosen && SLIDERS[c.kind]) sub = c.owned ? 'Yours — adjust freely' : money(c.price);
            // No tag line: the name and count sit at the top, leaving the bottom of the card to the art.
            cards.push({
                id: 'cat:' + c.key, name: c.name, sub, nav: true, top: true, basketed: !!chosen,
                art: wheelArt(c) || modArt(c) || catArt(path[1], c),
                onOpen: () => { path = ['customise', path[1], c.key]; syncFocus(); render(); },
            });
        });
    }

    // ---- level 3: the parts ----
    else {
        const cat = currentCategory();
        const chosen = basketEntryByKey(cat.key);
        const prev   = previewing[String(cat.slot)];

        cat.items.forEach((item) => {
            const isChosen = !!chosen && chosen.index === item.index;
            // Match the shelf too: wheel ranges share slot 23 and their indexes.
            const isPreview = !!prev && prev.key === cat.key && prev.index === item.index;
            cards.push({
                id: `part:${cat.key}:${item.index}`,
                kicker: cat.name, name: item.name, price: item.price,
                basketed: isChosen, previewing: !isChosen && isPreview, fitted: !!item.fitted,
                // No Add on a fitted part: it can be previewed, not bought again.
                add: item.fitted ? null : { label: isChosen ? 'In basket' : 'Add', strong: isChosen },
                onOpen: () => {
                    previewing[String(cat.slot)] = { key: cat.key, index: item.index };
                    post('preview', { slot: cat.slot, index: item.index, wheelType: cat.wheelType });
                    render();
                },
                // On a pad the part is tried on as soon as it is highlighted (padTryHighlighted), no pause.
                onHighlight: () => {
                    previewing[String(cat.slot)] = { key: cat.key, index: item.index };
                    previewNow({ slot: cat.slot, index: item.index, wheelType: cat.wheelType });
                    render();
                },
                onAdd: item.fitted ? null : () => {
                    post('add', {
                        slot: cat.slot, index: item.index, wheelType: cat.wheelType,
                        key: cat.key, name: item.name, price: item.price, category: cat.name,
                    });
                },
            });
        });
    }

    const at = Math.min(railAtByPath[railKey()] || 0, Math.max(0, cards.length - 1));
    railAtByPath[railKey()] = at;

    // On a controller: the buttons for the picked card.
    const card = cards[at];
    const pad = [['dpad', 'browse']];
    if (path.length === 3) {
        // A part: highlighting tries it on, A adds it (X still does too, unsaid); a fitted one A can only try on.
        if (card) pad.push(['a', card.onAdd ? 'add' : 'try on']);
    } else {
        if (card) pad.push(['a', 'open']);
        if (card && card.onAdd) pad.push(['x', 'add']);
    }
    pad.push(['y', builder ? 'spawns with' : 'basket'], ['b', path.length ? 'back' : 'leave']);

    return {
        key: railKey(),
        level: path.length,
        cards,
        empty,
        focus: padOn ? at : -1,
        hint: {
            kb: ['*scroll* or *← →* to browse', 'hold *right mouse* to move the camera', '*backspace* to leave'],
            pad: pad.concat(PAD_CAM),
        },
    };
}

/* ---- each frame's model --------------------------------------------------------- */

function render() {
    if (!isOpen) { view.update({ open: false }); return; }

    // Picker categories hide the rail.
    const deep = path.length === 3 ? currentCategory() : null;
    if (path.length === 3 && !deep) { path = ['customise', path[1]]; }

    let picker = null;
    if (deep && PICKER_KINDS[deep.kind]) picker = pickerModel(deep);
    else closePicker();

    const crumbs = ['Whiplash'];
    if (path[0] === 'customise') crumbs.push('Customise');
    const sec = currentSection();
    if (sec) crumbs.push(sec.name);
    const cat = currentCategory();
    if (cat) crumbs.push(cat.name);

    const n = basket.length;
    const model = {
        open: true,
        pad: padOn,
        orbiting,
        crumbs: { items: crumbs, back: path.length > 0, onBack: goBack },
        rail: picker ? null : railModel(),
        picker,
        tally: { show: n > 0 && !builder, total: basketTotal(), cash, onClick: openBasket },
        camera: { standard: standardCam, off: basketOpen || confirmOpen, onClick: toggleCamera },
        job: job ? { title: job.title || '', rows: job.rows || [], pays: !!job.pays } : null,
        basket: {
            open: basketOpen,
            count: n,
            rows: basket.map((b) => ({
                id: 'b:' + b.slot,
                slot: b.category || (String(b.slot) === 'tint' ? 'Tint' : `Slot ${b.slot}`),
                name: b.name,
                // A line the Director's goal pays for arrives at nothing, marked (ui.lua, Goals.dress).
                price: builder ? '' : b.jobPays ? 'Job pays' : b.price === 0 ? '—' : money(b.price),
                free: !!b.jobPays,
                onRemove: () => {
                    // Lua reverts the slot (Session.revertSlot); a tuning line also drops its slider draft.
                    delete previewing[String(b.slot)];
                    if (SLIDERS[b.slot]) drafts[b.slot] = null;
                    post('remove', { slot: b.slot });
                },
            })),
            total: money(basketTotal()),
            cash: cash === null ? '—' : money(cash),
            payEnabled: !paying && n > 0,
            onCash: () => send('cash'),
            onBank: () => send('bank'),
            onFree: dev ? () => send('free') : null,   // developer mode only
            onKeep: closeBasket,
            // Setting how a car spawns: one Save, empty or not (an empty one: it spawns as it is).
            builder,
            onSave: saveLook,
            focus: basketOpen && padOn ? dlgFocusId : null,
        },
        confirm: {
            open: confirmOpen,
            builder,
            onStay: () => { confirmOpen = false; render(); },
            onLeave: () => post('close', {}),
            focus: confirmOpen && padOn ? dlgFocusId : null,
        },
    };
    lastModel = model;
    view.update(model);
    sendShift(!!picker);
}

/* ---- input ---------------------------------------------------------------- */

/* Orbiting (right mouse held) is reported by Lua: the page never sees that button. While orbiting
   the cursor hides and the wheel zooms the camera instead of scrolling the rail. */
function setOrbiting(v) {
    if (orbiting === v) return;
    orbiting = v;
    view.setOrbiting(v);
}

// Safety net: losing focus mid-orbit could leave the cursor hidden for good.
window.addEventListener('blur', () => setOrbiting(false));

// Right mouse is the camera's.
window.addEventListener('contextmenu', (e) => e.preventDefault());

/* Leaving is handled here, not by a Lua control: GTA's cancel control (177) is also right mouse,
   which orbits the camera. */
function requestLeave() {
    if (basket.length === 0) { post('close', {}); return; }
    confirmOpen = true;
    if (padOn) dlgFocusId = 'stay';   // on a pad it opens on Stay (padDialog)
    render();
}

document.addEventListener('keydown', (e) => {
    if (!isOpen) return;

    // An input keeps its keys (Backspace edits, arrows move the caret); Escape lets go of it.
    const t = e.target;
    if (t && t.tagName === 'INPUT') {
        if (e.key === 'Escape') { t.blur(); e.preventDefault(); }
        // ↓ or Enter in the engine search tries the first result.
        else if (t.classList.contains('pk-search') && (e.key === 'ArrowDown' || e.key === 'Enter')) {
            t.blur();
            const cat = currentCategory();
            const first = pick.items[0];
            if (cat && first && typeof first === 'object' && first.model) { pick.cursor = 0; tryEngine(cat, first.model, true); }
            e.preventDefault();
        }
        return;
    }

    // An open dialog owns the keys. Escape or Backspace closes the basket.
    if (basketOpen) {
        if (e.key === 'Escape' || e.key === 'Backspace') { closeBasket(); e.preventDefault(); }
        return;
    }

    if (confirmOpen) {
        if (e.key === 'Escape') { confirmOpen = false; render(); e.preventDefault(); }
        else if (e.key === 'Enter') { post('close', {}); e.preventDefault(); }
        return;
    }

    if (e.key === 'Backspace') { requestLeave(); e.preventDefault(); return; }

    // C: the Standard camera button.
    if (e.key === 'c' || e.key === 'C') { toggleCamera(); e.preventDefault(); return; }

    // The open picker takes arrows, Enter and Escape.
    if (pick.key !== null) {
        if (pickerKey(e.key)) e.preventDefault();
        return;
    }

    if (e.key === 'ArrowRight') { view.scrollRail(1); e.preventDefault(); }
    else if (e.key === 'ArrowLeft') { view.scrollRail(-1); e.preventDefault(); }
    else if (e.key === 'Escape') {
        // Up a level, or leave from the top.
        if (path.length) goBack(); else requestLeave();
        e.preventDefault();
    }
});

/* The Standard camera button: Lua keeps the player's choice and answers with the camera now ('camera'). */
function toggleCamera() {
    if (!isOpen || basketOpen || confirmOpen) return;
    post('camera', {});
}

function goBack() {
    if (!path.length) return;
    path.pop();
    // Backing out reframes the camera too.
    syncFocus();
    render();
}

/* ---- the basket dialog, and paying ------------------------------------------- */

let paying = false;   // one order at a time
let payTimer = null;

function openBasket() {
    if (!isOpen) return;
    basketOpen = true;
    if (padOn) dlgFocusId = 'keep';   // on a pad it opens on Keep shopping (padDialog)
    render();
    // Re-ask for cash (ui.lua, refreshCash).
    post('cash', {});
}

function send(method) {
    if (paying || basket.length === 0) return;
    // Latch before posting, so a second click can't send a second order.
    paying = true;
    render();
    post('checkout', { method });
    // The server always answers; if the answer is lost, unlatch after 15 s.
    clearTimeout(payTimer);
    payTimer = setTimeout(unlatchPay, 15000);
}

// Setting how a car spawns: the basket is kept on the car (ui.lua saveLook), and Whiplash closes.
function saveLook() {
    if (paying) return;
    paying = true;
    render();
    post('saveLook', {});
}

// Re-enables the pay tiles (order refused or timed out); the dialog stays open.
function unlatchPay() {
    clearTimeout(payTimer);
    paying = false;
    if (isOpen) render();
}

// Closing does not unlatch: an order in flight stays the only one.
function closeBasket() {
    basketOpen = false;
    dlgFocusId = null;
    render();
}

/* ---- messages from Lua ---------------------------------------------------- */

window.addEventListener('message', (event) => {
    const d = event.data || {};

    switch (d.action) {
        case 'open':
            catalogue = d.catalogue || {};
            sections  = d.sections || [];
            basket    = d.basket || [];
            job       = d.job || null;
            builder   = d.builder === true;
            dev       = d.dev === true;
            standardCam = d.standardCam === true;
            services  = d.services || [];
            // Palette and engines arrive on the first visit only (ui.lua, listsSent).
            if (d.palette) palette = d.palette;
            // Sorted by name: the A–Z view uses this order.
            if (d.engines) {
                engines = d.engines.slice().sort((a, b) => String(a.label).localeCompare(String(b.label)));
                maxHp = Math.max(1, ...engines.map((e) => e.hp || 0));
            }
            path = [];
            for (const k in previewing) delete previewing[k];
            drafts.stance = null; drafts.setup = null; drafts.drive = null;
            hueLists = null; paintHue = null;
            pick.key = null;
            engineQuery = '';
            // The camera starts centred; force the first draw to resend the shift.
            shiftSent = null;
            cash = null;
            // Opened on a pad: its hints and rings from the first draw (ui.lua), on the counter's first card.
            padOn = d.pad === true;
            for (const k in railAtByPath) delete railAtByPath[k];
            dlgFocusId = null;
            confirmOpen = false;
            basketOpen = false;
            clearTimeout(payTimer);
            paying = false;
            isOpen = true;
            render();
            // The page owns Backspace now; Lua's fallback exit (+whiplash_leave) stands down, or
            // both would fire and skip the unpaid-basket question.
            post('shown', {});
            break;

        case 'close':
            isOpen = false;
            confirmOpen = false;
            basketOpen = false;
            dlgFocusId = null;
            clearTimeout(payTimer);
            paying = false;
            setOrbiting(false);
            // Blur any input, or the game's keys stay held back.
            view.blurSearch();
            // Drop pending previews: the car has already been put back.
            clearTimeout(previewTimer);
            clearTimeout(stanceTimer);
            shiftSent = null;
            pick.key = null;
            render();
            break;

        case 'basket':
            basket = d.basket || [];
            job = d.job || null;   // every basket message carries the checklist as it now stands
            render();   // cards show what is already chosen
            break;

        // Developer mode switched while the shop is open (ui.lua): Free comes or goes.
        case 'devMode':
            dev = d.on === true;
            render();
            break;

        // Server's cash count (ui.lua, refreshCash).
        case 'cash':
            cash = Number.isFinite(Number(d.cash)) ? Number(d.cash) : cash;
            render();
            break;

        case 'cursor':
            setOrbiting(!!d.hidden);
            break;

        // The Standard camera button's state, after a press or a change of the server's default (ui.lua).
        case 'camera':
            standardCam = d.standard === true;
            render();
            break;

        // A controller (ui.lua): which device, and a press.
        case 'padDevice':
            setPadMode(d.pad === true);
            break;
        case 'pad':
            padPress(String(d.cmd || ''));
            break;

        // Payment refused (the notification says why): re-enable the tiles.
        case 'purchaseFailed':
            unlatchPay();
            break;
    }
});
