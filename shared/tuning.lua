-- ============================================
-- whip_autos — tuning constants and helpers, shared by client and server
-- ============================================
-- Fixed facts both sides must agree on. Settings live in Config.Tuning (config.lua).

--- The VehicleData keys a tuned car carries (whip_core VehicleData, owned by this resource).
TUNING_ENGINE_KEY = 'engine'
TUNING_STANCE_KEY = 'stance'
TUNING_SETUP_KEY  = 'setup'
TUNING_DRIVE_KEY  = 'drive'

--- The turbo fitted: { psi = <a Config.Turbo.Stages psi> }, absent for none. Bought on the Performance shelf as mod
--- slot 18 (index 1.. = the stages in order, 0 = none) but kept here, with the tuning, so the stage is written with
--- the payment and every client reads it (client/power/turbo.lua). The boost stat follows it (server/power/turbo.lua).
TUNING_TURBO_KEY  = 'turbo'

--- The Tuning shelf's basket slots, one per key above. They carry a choice instead of a mod index and
--- are priced by server/tuning.lua.
TUNING_SLOTS = { engine = true, stance = true, setup = true, drive = true }

--- The turbo stage a car's turbo data is (PowerTurbo.stage), or nil for none or a stage no longer sold.
---@param data any  the car's TUNING_TURBO_KEY value
---@return table|nil
function TuningTurboStage(data)
    return type(data) == 'table' and PowerTurbo.stage(data.psi) or nil
end

--- The shop's index for a car's turbo: its stage's place in Config.Turbo.Stages, or 0 for none.
---@param data any  the car's TUNING_TURBO_KEY value
---@return number
function TuningTurboIndex(data)
    local s = TuningTurboStage(data)
    return s and s.index or 0
end

--- Drivetrain layouts: the car's own, front, rear or all-wheel drive.
TUNING_DRIVE_LAYOUTS = { stock = true, fwd = true, rwd = true, awd = true }

--- The drivetrain's saved fields: the layout, and AWD's front share in % (Config.Tuning.Drive.Split).
TUNING_DRIVE_FIELDS = {
    { key = 'layout' },
    { key = 'front', range = 'Split' },
}

--- The handling fields an engine swap moves (engine and gearbox only). /whiplashengines reads these;
--- the swap writes these.
TUNING_ENGINE_FIELDS = {
    'fInitialDriveForce', 'fDriveInertia', 'nInitialDriveGears',
    'fClutchChangeRateScaleUpShift', 'fClutchChangeRateScaleDownShift', 'fInitialDriveMaxFlatVel',
}

--- The stance fields, each with the Config.Tuning.Stance range it is held to.
TUNING_STANCE_FIELDS = {
    { key = 'height',  range = 'Height' },
    { key = 'trackF',  range = 'Track' },
    { key = 'trackR',  range = 'Track' },
    { key = 'camberF', range = 'Camber' },
    { key = 'camberR', range = 'Camber' },
    { key = 'width',   range = 'Width' },
    { key = 'size',    range = 'Size' },
}

--- The handling setup's fields: each a % of the car's own (100 = stock), its Config.Tuning.Setup range,
--- and the CHandlingData fields it multiplies. Applied as a whip_core handling layer for the driver.
TUNING_SETUP_FIELDS = {
    { key = 'springs',   range = 'Springs',   fields = { 'fSuspensionForce' } },
    { key = 'dampers',   range = 'Dampers',   fields = { 'fSuspensionCompDamp', 'fSuspensionReboundDamp' } },
    { key = 'antiroll',  range = 'AntiRoll',  fields = { 'fAntiRollBarForce' } },
    { key = 'steering',  range = 'Steering',  fields = { 'fSteeringLock' } },
    { key = 'grip',      range = 'Grip',      fields = { 'fTractionCurveMax', 'fTractionCurveMin' } },
    { key = 'handbrake', range = 'Handbrake', fields = { 'fHandBrakeForce' } },
}

local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end

--- Cleans one saved block: each value clamped to its range and snapped to its step; missing = neutral.
local function cleanFields(t, fields, ranges, neutral, what)
    if type(t) ~= 'table' then return nil, what .. ' must be a table' end
    local out = { v = 1 }
    for _, f in ipairs(fields) do
        local r = ranges[f.range]
        local v = t[f.key]
        if v == nil then v = neutral(f.key) end
        if not finite(v) then return nil, ('%s must be a number'):format(f.key) end
        v = math.max(r.min, math.min(r.max, v))
        v = math.floor(v / r.step + 0.5) * r.step
        out[f.key] = v
    end
    return out
end

--- A stance in slider units (cm, degrees, %). Neutral is 0, or 100 for wheel width and size.
---@param t table
---@return table|nil stance, string|nil why
function TuningCleanStance(t)
    return cleanFields(t, TUNING_STANCE_FIELDS, Config.Tuning.Stance,
        function(key) return (key == 'width' or key == 'size') and 100 or 0 end, 'stance')
end

--- A handling setup, each field a %. Neutral is 100.
---@param t table
---@return table|nil setup, string|nil why
function TuningCleanSetup(t)
    return cleanFields(t, TUNING_SETUP_FIELDS, Config.Tuning.Setup, function() return 100 end, 'setup')
end

--- A drivetrain `{ layout, front }`. Missing layout is 'stock', missing front is 50; front is kept for
--- every layout so AWD comes back as it was left.
---@param t table
---@return table|nil drive, string|nil why
function TuningCleanDrive(t)
    if type(t) ~= 'table' then return nil, 'drive must be a table' end
    local layout = t.layout == nil and 'stock' or t.layout
    if not TUNING_DRIVE_LAYOUTS[layout] then return nil, 'layout must be stock, fwd, rwd or awd' end
    local r = Config.Tuning.Drive.Split
    local front = t.front == nil and 50 or t.front
    if not finite(front) then return nil, 'front must be a number' end
    front = math.max(r.min, math.min(r.max, front))
    front = math.floor(front / r.step + 0.5) * r.step
    return { v = 1, layout = layout, front = front }
end

--- The handling layer's scale for a setup: { field = factor } for every field off 100%.
---@param setup table|nil  a cleaned setup (nil: an empty scale)
---@return table scale
function TuningSetupScale(setup)
    local scale = {}
    if type(setup) ~= 'table' then return scale end
    for _, f in ipairs(TUNING_SETUP_FIELDS) do
        local pct = setup[f.key]
        if finite(pct) and pct ~= 100 then
            for _, field in ipairs(f.fields) do scale[field] = pct / 100 end
        end
    end
    return scale
end

--- Suspension travel at a ride height of `height` cm, as a share of the car's own
--- (Config.Tuning.Stance.Travel; 1 when it is off). app.js's travelPct shows the same number.
---@param height number|nil  cm, + raises
---@return number
function TuningTravelFactor(height)
    local t = Config.Tuning.Stance.Travel or {}
    local perCm = tonumber(t.perCm) or 0
    if perCm == 0 then return 1 end   -- off: least and most do not apply either (as app.js's travelPct)
    local f = 1 + (tonumber(height) or 0) * perCm
    return math.max(t.min or 0.3, math.min(t.max or 2.0, f))
end

--- The sound an engine plays: its model name, unless Config.Tuning.EngineSoundOverrides names another.
---@param model string
---@return string
function TuningEngineSound(model)
    local overrides = Config.Tuning.EngineSoundOverrides or {}
    return overrides[model] or model
end

--- Is this vehicle class's engine sound-only (Config.Tuning.SoundOnlyEngineClasses)?
function TuningSoundOnlyClass(class)
    for _, c in ipairs(Config.Tuning.SoundOnlyEngineClasses or {}) do
        if c == class then return true end
    end
    return false
end

--- What an engine swap stores on the car, from one engines.json entry: the donor's figures and weight.
---@param model string
---@param entry table  from server/engines.lua
---@param sound string
function TuningEngineData(model, entry, sound)
    local drive = {}
    for _, field in ipairs(TUNING_ENGINE_FIELDS) do drive[field] = entry.drive[field] end
    return {
        v = 1, model = model, label = entry.label, sound = sound,
        mass = entry.mass, drive = drive,
        soundOnly = TuningSoundOnlyClass(entry.class) or nil,
    }
end

--- The handling an engine swap sets on a car weighing `mass`: the donor's figures, drive force scaled by
--- donor weight ÷ this car's weight, floored at Config.Tuning.MinDriveForce (and capped at MaxDriveForce
--- when set). nil for a sound-only engine or incomplete data.
---@param data table  the 'engine' VehicleData
---@param mass number  this car's fMass
---@return table|nil  { field = value }
function TuningEngineSet(data, mass)
    if type(data) ~= 'table' or data.soundOnly or type(data.drive) ~= 'table' then return nil end
    if not finite(mass) or mass <= 0 or not finite(data.mass) or data.mass <= 0 then return nil end
    local set = {}
    for _, field in ipairs(TUNING_ENGINE_FIELDS) do
        if not finite(data.drive[field]) then return nil end
        set[field] = data.drive[field]
    end
    local force = set.fInitialDriveForce * data.mass / mass
    local ceiling = tonumber(Config.Tuning.MaxDriveForce)
    if ceiling then force = math.min(ceiling, force) end
    set.fInitialDriveForce = math.max(Config.Tuning.MinDriveForce, force)
    return set
end
