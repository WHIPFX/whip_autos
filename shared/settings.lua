-- ============================================
-- whip_autos — the settings page in /whip
-- ============================================
-- What an owner changes, on a page in /whip → Settings → Autos (Whip.configPage, whip_core's helper):
-- config.lua is the default, what an admin saves there wins, and it is written into Config on both
-- sides, so the rest of autos keeps reading Config. Everything else (the camera, the shelves, the
-- parts' mod slots, the gearbox's figures) is config.lua's alone. What autos works out from Config at
-- load is rebuilt beside it, with Whip.onConfigChanged.

local WORLD = { x = { -5000, 5000 }, y = { -7000, 8000 }, z = { -200, 2000 } }

local function price(key, label, help)
    return { key = key, type = 'int', min = 0, max = 10000000, unit = '$', label = label, help = help }
end

--- Config's value at a path ('Tuning.Stance.Height'), or nil.
local function configAt(path)
    local t = Config
    for part in path:gmatch('[^%.]+') do
        if type(t) ~= 'table' then return nil end
        t = t[part]
    end
    return t
end

local function onStep(x, step)
    local q = x / step
    return math.abs(q - math.floor(q + 0.5)) < 1e-6
end

--- How far one of Whiplash's sliders goes (Config.Tuning.Stance.Height = { min, max, step }): its lowest and
--- highest, as two fields of the card at `base`. shared/tuning.lua clamps a value then snaps it to a whole step
--- (config.lua's), so both must be whole steps, and `neutral` (no change: 0, or 100 %) one inside them, or
--- every car would be moved off it.
local function limits(base, sub, label, unit, lo, hi, neutral)
    local path = base .. '.' .. sub
    local function cross(get)
        local min, max = get(path .. '.min'), get(path .. '.max')
        local step = (configAt(path) or {}).step or 1
        if min >= max then return false, label .. ': the lowest must be below the highest' end
        if not (onStep(min, step) and onStep(max, step)) then
            return false, ('%s: the lowest and highest must be whole steps of %s'):format(label, tostring(step))
        end
        if neutral < min or neutral > max or not onStep(neutral, step) then
            return false, ('%s: %s (no change) must be in the range, on a whole step'):format(label, tostring(neutral))
        end
        return true
    end
    return {
        { key = sub .. '.min', type = 'number', min = lo, max = hi, unit = unit, label = label .. ': lowest', cross = cross },
        { key = sub .. '.max', type = 'number', min = lo, max = hi, unit = unit, label = label .. ': highest', cross = cross },
    }
end

local function rangeCross(lo, hi, what)
    return function(get)
        if get(lo) >= get(hi) then return false, what .. ': the lowest must be below the highest' end
        return true
    end
end

local function driveCross(get)
    local cap = get('Tuning.MaxDriveForce')
    if cap and cap < get('Tuning.MinDriveForce') then return false, 'The power cap is below the power floor' end
    return true
end

--- Fields one after another, as one list.
local function fields(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, f in ipairs(list) do out[#out + 1] = f end
    end
    return out
end

--- A part list's prices (Config.Cosmetics and the like): each row's name and price, and no more or fewer rows
--- than config.lua has. Its mod slots and ids are config.lua's: a new part needs code anyway.
local function priceList(key, label, help)
    local n = #(Config[key] or {})
    return {
        key = key, type = 'records', minItems = n, maxItems = n, label = label, help = help,
        fields = {
            { key = 'name', type = 'string', maxLen = 40, label = 'Name' },
            { key = 'price', type = 'int', min = 0, max = 10000000, unit = '$', label = 'Price' },
        },
    }
end

--- Rows of shared/power.lua (PowerTurbo.rows) under `base` as one card: 'Turbo.TorquePerPsi' is its field 'TorquePerPsi'.
local function card(base, label, help, rows, keys)
    local byKey = {}
    for _, r in ipairs(rows) do byKey[r.key] = r end
    local list = {}
    for _, k in ipairs(keys) do
        local f = {}
        for name, v in pairs(byKey[base .. '.' .. k]) do f[name] = v end
        f.key = k
        list[#list + 1] = f
    end
    return { key = base, type = 'record', label = label, help = help, fields = list }
end

local REALISTIC = { path = 'RealisticShifting', equals = true }

-- Each kind of vehicle's stock gear change (PowerClasses, shared/power.lua), in class order.
local shiftFields = {}
for class = 0, 22 do
    local c = PowerClasses[class]
    if c then shiftFields[#shiftFields + 1] = { key = c.key, type = 'number', min = 0.25, max = 5, unit = '×', label = c.label } end
end

Whip.configPage({ label = 'Autos', groups = {
    { label = 'The shop', settings = {
        { key = 'Shop.label', type = 'string', maxLen = 30, label = 'Name', help = 'Shown on the radial entry ("Enter Whiplash").' },
        { key = 'Shop.coords', type = 'vec3', here = true, limits = WORLD, label = 'Floor', help = 'The middle of the shop floor (the car lift). A driver on it opens the shop from the F1 wheel: Enter Whiplash.' },
        { key = 'Shop.radius', type = 'number', min = 1, max = 50, unit = 'm', label = 'Floor size', help = 'How far from the middle a car still counts as on the floor. Paying is allowed 4 m further out. Keep it small: the roller door is about 6 m from the lift.' },
        { key = 'WhoCanModify', type = 'enum', label = 'Who can modify a car',
          options = {
              { value = 'anyone', label = 'Anyone can modify any vehicle' },
              { value = 'ownerTuning', label = 'Only owners can modify performance and tuning' },
              { value = 'owner', label = 'Only owners can modify at all' },
          },
          help = 'Whoever drives a car someone owns onto the floor. Performance and tuning: the Performance shelf\'s parts and turbo, and the Tuning shelf (engine swap, stance, handling, drivetrain); anyone else can still change its looks and repair it. At all: anyone else can only repair it. A car nobody owns (a street car, a rental, a scenario\'s car) is open to whoever drives it.' },
        { key = 'Camera.followParts', type = 'bool', label = 'Camera moves to each part',
          help = 'On: opening a part (the wheels, the exhaust, the spoiler) moves the camera to that part\'s own shot. Off: the standard camera, which stays on the orbit shot and moves only when the player turns or zooms it. Each player can switch it for themselves with the Standard camera button in the shop; this is what they get until they do.' },
    } },
    { label = 'Price list', settings = {
        { key = 'Tuning', type = 'record', label = 'Tuning',
          help = 'An engine swap costs its price each time. Stance, the handling setup and the drivetrain are bought once per car; adjusting them after is free.',
          fields = {
              { key = 'EngineSwapPrice', type = 'int', min = 0, max = 10000000, unit = '$', label = 'Engine swap' },
              { key = 'StancePrice', type = 'int', min = 0, max = 10000000, unit = '$', label = 'Stance' },
              { key = 'SetupPrice', type = 'int', min = 0, max = 10000000, unit = '$', label = 'Handling setup' },
              { key = 'DrivetrainPrice', type = 'int', min = 0, max = 10000000, unit = '$', label = 'Drivetrain' },
          } },
        priceList('Cosmetics', 'Body parts', 'A slot the car has no parts for is hidden.'),
        priceList('Wheels', 'Wheels', 'A car\'s wheels, and a bike\'s rear wheel.'),
        priceList('Performance', 'Performance parts', 'Engine, brakes, transmission, suspension, armour: the price of each level.'),
        priceList('Toggles', 'On / off parts', 'Tyre smoke (sold on the Wheels shelf) and xenon lights. The Turbo row\'s price is not used: each turbo stage has its own price (config.lua, Config.Turbo.Stages).'),
        price('TyreSmokeColours.colourPrice', 'Tyre smoke colour change', 'On a car that already has tyre smoke. Fitting it costs the Tyre Smoke price (On / off parts).'),
        price('XenonColours.colourPrice', 'Xenon colour change', 'On a car that already has xenons. Fitting them costs the Xenon Lights price.'),
        price('WindowTints.price', 'Window tint', 'Any tint but stock, which is free.'),
        price('Neon.price', 'Neon kit', 'Any neon layout (front, back, sides and their mixes). Off is free. Cars only.'),
        price('Neon.colourPrice', 'Neon colour', 'Changing the neon\'s colour.'),
        price('Extras.price', 'Extra switch', 'Switching one of a car\'s extras (light bars, roof racks, covers) on or off, on the Extras shelf. Only cars with extras show the shelf.'),
        priceList('PaintTargets', 'Paint', 'What each part of the car costs to paint.'),
        priceList('PaintExtras', 'On the paint shelf', 'The livery.'),
        priceList('Services', 'Services', 'Work on the car, applied only once paid.'),
    } },
    -- Power: the turbo and nitrous (their rows and limits are in shared/power.lua), top speed and engine swaps.
    { label = 'Power', settings = {
        card('Turbo', 'Turbo', 'Turbos are sold at Whiplash in stages (config.lua Config.Turbo.Stages: the psi and price of each; reprice them freely, but never remove one or change its psi once bought). Extra engine torque per psi of full boost (0.03: a 15 psi turbo adds 45%; 0: only GTA\'s own small turbo part and its sound), and the seconds the smallest and the biggest turbo take from no boost to full, foot flat at the limiter (at idle revs about six times as long). Each gear change dumps a random share of the boost, between the least and the most.',
             PowerTurbo.rows, { 'TorquePerPsi', 'SpoolFastest', 'SpoolSlowest', 'ShiftLossMin', 'ShiftLossMax' }),
        card('Nitrous', 'Nitrous', 'The engine\'s torque while the button is held (3 is three times), the seconds of boost in a full bottle, and how long fitting one takes.',
             PowerNitrous.rows, { 'Torque', 'BottleSeconds', 'InstallSeconds' }),
        { key = 'TopSpeedBonusMph', type = 'number', min = 0, max = 200, unit = 'mph', label = 'Top speed bonus',
          help = 'Added to every car\'s and motorbike\'s top speed by making its gears longer, not by adding power: a car only reaches it if it has the power to. 0 turns it off.' },
        { key = 'Tuning.MinDriveForce', type = 'number', min = 0.01, max = 5, label = 'Swapped engine: power floor', cross = driveCross,
          help = 'A swapped engine\'s power is the donor\'s drive force × donor weight ÷ this car\'s weight, never below this.' },
        { key = 'Tuning.MaxDriveForce', type = 'number', min = 0.01, max = 5, offWhenEmpty = true, emptyLabel = 'no cap', label = 'Swapped engine: power cap', cross = driveCross,
          help = 'Never above this (0.6, say). Empty: no cap.' },
        { key = 'Gearbox.Enabled', type = 'bool', label = 'Gearbox computer',
          help = 'On: cars change gear like a real automatic. A light foot changes up early and lets the revs fall low; a foot flat to the floor gets GTA\'s own change at peak power. A controller only for now (a keyboard key is only on or off).' },
    } },
    { label = 'Shifting', settings = {
        { key = 'RealisticShifting', type = 'bool', label = 'Realistic shifting',
          help = 'Every car on the server, not only Whiplash customers. On: every kind of vehicle shifts slowly on its stock transmission (the times below), and each transmission upgrade at Whiplash makes it much quicker. Off: every kind shifts at GTA\'s own speed (config.lua PlainShiftTimeByClass, all 1), and an upgrade does only what GTA\'s own does.' },
        { key = 'ShiftTimeByClass', type = 'record', fields = shiftFields, label = 'Stock shift time by kind', shownWhen = REALISTIC,
          help = 'How long a gear change takes on each kind\'s stock transmission, against GTA\'s own: 5 is very slow, 1 is GTA\'s own, 0.25 a sequential box.' },
        { key = 'ShiftTimeByModel', type = 'map', keyPattern = '^[%w_]+$', keyWhy = 'is a model name',
          keyLabel = 'Model', each = { type = 'number', min = 0.25, max = 5, label = 'Shift time' }, label = 'Shift time by car',
          help = 'A car\'s own gear change time, by its model name (sultan, adder), instead of its kind\'s, with realistic shifting on or off. With it on, this is the stock transmission\'s, and the upgrades still make it quicker from there.' },
    } },
    { label = 'How far the sliders go', settings = {
        { key = 'Tuning.Stance', type = 'record', label = 'Stance',
          help = 'The lowest and highest each stance slider at Whiplash goes. Each must be a whole step of the slider (config.lua), with no change (0, or 100 %) inside. Suspension travel can follow ride height: its change per cm (0.04 is 4%; 0, the default, is off, as it hurts handling more than it helps), kept between its least and most, as shares of the car\'s own. Cars already stanced keep the old travel.',
          fields = fields(
              limits('Tuning.Stance', 'Height', 'Ride height', 'cm', -50, 50, 0),
              limits('Tuning.Stance', 'Track', 'Track', 'cm', -30, 30, 0),
              limits('Tuning.Stance', 'Camber', 'Camber', '°', -30, 30, 0),
              limits('Tuning.Stance', 'Width', 'Wheel width', '%', 30, 300, 100),
              limits('Tuning.Stance', 'Size', 'Wheel size', '%', 30, 400, 100),
              {
                  { key = 'Travel.perCm', type = 'number', min = 0, max = 0.2, apply = 'restart', why = 'Cars already stanced keep the old travel.',
                    label = 'Travel: change per cm' },
                  { key = 'Travel.min', type = 'number', min = 0.05, max = 5, apply = 'restart', why = 'Cars already stanced keep the old travel.',
                    label = 'Travel: least', cross = rangeCross('Tuning.Stance.Travel.min', 'Tuning.Stance.Travel.max', 'Travel') },
                  { key = 'Travel.max', type = 'number', min = 0.05, max = 5, apply = 'restart', why = 'Cars already stanced keep the old travel.',
                    label = 'Travel: most', cross = rangeCross('Tuning.Stance.Travel.min', 'Tuning.Stance.Travel.max', 'Travel') },
              }
          ) },
        { key = 'Tuning.Setup', type = 'record', label = 'Handling',
          help = 'The lowest and highest each handling slider at Whiplash goes, against the car\'s own (100 %). Each must be a whole step of the slider (config.lua), with 100 % inside.',
          fields = fields(
              limits('Tuning.Setup', 'Springs', 'Springs', '%', 5, 500, 100),
              limits('Tuning.Setup', 'Dampers', 'Dampers', '%', 5, 500, 100),
              limits('Tuning.Setup', 'AntiRoll', 'Anti-roll', '%', 0, 500, 100),
              limits('Tuning.Setup', 'Steering', 'Steering lock', '%', 20, 300, 100),
              limits('Tuning.Setup', 'Grip', 'Grip', '%', 20, 300, 100),
              limits('Tuning.Setup', 'Handbrake', 'Handbrake', '%', 5, 500, 100)
          ) },
        { key = 'Tuning.Drive', type = 'record', label = 'Drivetrain',
          help = 'How far the AWD front share slider goes: the share of the power at the front wheels, with 50 % inside.',
          fields = limits('Tuning.Drive', 'Split', 'AWD front share', '%', 1, 99, 50) },
    } },
} })
