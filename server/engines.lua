-- ============================================
-- whip_autos — the engine list (engine swaps)
-- ============================================
-- Every engine an engine swap can transplant, kept in engines.json at the resource root. No native can
-- read another model's handling without spawning it, so /whiplashengines (client/dev.lua) measures
-- every model in game and sends the list here. Run it again after adding add-on cars.

local ENGINE_FILE = 'engines.json'
local SCHEMA = 1

local store = { schema = SCHEMA, engines = {} }

--- The shop's list (model, label, class, hp, torque), built once per change (of engines.json, or of the
--- hidden or sound-only classes in /whip).
local listCache = nil
Whip.onConfigChanged('Tuning.HiddenEngineClasses', function() listCache = nil end)
Whip.onConfigChanged('Tuning.SoundOnlyEngineClasses', function() listCache = nil end)

Engines = {}

--- One engine by model name, or nil (also nil for a hidden class).
---@param model string
---@return table|nil  { label, class, mass, drive = { field = value }, topSpeed, accel }
function Engines.get(model)
    if type(model) ~= 'string' then return nil end
    local e = store.engines[model:lower()]
    if not e then return nil end
    for _, c in ipairs(Config.Tuning.HiddenEngineClasses or {}) do
        if e.class == c then return nil end
    end
    return e
end

--- What an engine swap to `model` stores on the car (shared/tuning.lua's shape), or nil.
function Engines.data(model)
    local e = Engines.get(model)
    if not e then return nil end
    model = model:lower()
    return TuningEngineData(model, e, TuningEngineSound(model))
end

--- An engine's horsepower and torque (Nm), worked out from its handling: GTA keeps neither. Torque is
--- the community's reading of drive force (GTAMods wiki: fInitialDriveForce = wheel torque Nm ÷ weight kg),
--- so drive force × the donor's weight, which an engine swap carries over (TuningEngineSet). Horsepower
--- is that torque pushing (× g × 0.9, the top gear) at 80% of the top-gear redline speed
--- (fInitialDriveMaxFlatVel × 1.2 ÷ 0.9 km/h), where GTA's flat torque curve starts to fall.
--- nil, nil when engines.json lacks a figure.
---@return integer|nil hp, integer|nil torque
local function power(e)
    local drive = type(e.drive) == 'table' and e.drive or {}
    local force, flatVel, mass = tonumber(drive.fInitialDriveForce), tonumber(drive.fInitialDriveMaxFlatVel), tonumber(e.mass)
    if not force or not flatVel or not mass then return nil, nil end
    local torque = force * mass
    local metresPerSecond = 0.8 * flatVel * 1.2 / 0.9 / 3.6
    local watts = torque * 9.81 * 0.9 * metresPerSecond
    return math.floor(watts / 745.7 + 0.5), math.floor(torque + 0.5)
end

--- Every engine the shop lists, sorted by label.
function Engines.list()
    if listCache then return listCache end
    local hidden = {}
    for _, c in ipairs(Config.Tuning.HiddenEngineClasses or {}) do hidden[c] = true end
    local out = {}
    for model, e in pairs(store.engines) do
        if not hidden[e.class] then
            local hp, torque = power(e)
            out[#out + 1] = { model = model, label = e.label, class = e.class, hp = hp, torque = torque,
                              soundOnly = TuningSoundOnlyClass(e.class) or nil }
        end
    end
    table.sort(out, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.model < b.model
    end)
    listCache = out
    return out
end

local function load()
    local raw = LoadResourceFile(GetCurrentResourceName(), ENGINE_FILE)
    if not raw or raw == '' then
        Whip.startProblem('there is no engines.json, so engine swaps have nothing to offer: run /whiplashengines in game to build the engine list')
        return
    end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' or type(data.engines) ~= 'table' then
        Whip.startProblem('engines.json cannot be read, so engine swaps have nothing to offer: run /whiplashengines in game to build it again')
        return
    end
    store.engines = data.engines
    store.builtAt, store.builtBy = data.builtAt, data.builtBy
    listCache = nil
end

local function save()
    store.schema = SCHEMA
    local ok, encoded = pcall(json.encode, store, { indent = true })
    if not ok or type(encoded) ~= 'string' then encoded = json.encode(store) end
    return SaveResourceFile(GetCurrentResourceName(), ENGINE_FILE, encoded, #encoded)
end

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then load() end
end)

-- ============================================
-- One measured engine, checked before it is kept
-- ============================================

local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end

--- A measured entry from the client, cleaned, or nil when any part is not what the tool produces.
local function cleanEntry(e)
    if type(e) ~= 'table' or type(e.model) ~= 'string' then return nil end
    local model = e.model:lower()
    if not model:match('^[%w_%-]+$') or #model > 40 then return nil end
    if type(e.drive) ~= 'table' or not finite(e.mass) or e.mass <= 0 then return nil end
    local drive = {}
    for _, field in ipairs(TUNING_ENGINE_FIELDS) do
        if not finite(e.drive[field]) then return nil end
        drive[field] = e.drive[field]
    end
    if drive.fInitialDriveForce <= 0 then return nil end     -- no engine (a trailer)
    return model, {
        label = type(e.label) == 'string' and e.label:sub(1, 60) or model,
        class = math.floor(tonumber(e.class) or -1),
        mass = e.mass,
        drive = drive,
        topSpeed = finite(e.topSpeed) and math.floor(e.topSpeed + 0.5) or nil,
        accel = finite(e.accel) and e.accel or nil,
    }
end

-- ============================================
-- Registering with whip_core
-- ============================================

--- [source] = { run, total, got = { [index] = true }, engines, count }: a dump arriving in chunks.
local _dumps = {}

local function RegisterWithWhip()
    --- The shop's engine list (about 60 KB): for a player in Whiplash (server/main.lua), or a Director builder opening
    --- it on the world builder's car (client/look.lua), which has no session. Each game asks once and keeps it.
    exports.whip_core:SecureCallback('whip_autos:engineList', {
        rateLimit = 2000,
    }, function(source)
        if not AutosSessions.carOf(source) and exports.whip_core:HasPermission(source, 'director.build') ~= true then
            return nil
        end
        return Engines.list()
    end)

    --- One engine's swap as a car stores it (Engines.data), or nil: a Director car's look on a copy this game drives
    --- itself (client/look.lua, a take's recording), which has no VehicleData to carry it.
    exports.whip_core:SecureCallback('whip_autos:engineData', {
        rateLimit = 500,
        params = { { 'model', 'string', 64 } },
    }, function(_, _, model)
        return Engines.data(model)
    end)

    --- May this player run /whiplashengines? Asked before minutes of spawning cars.
    exports.whip_core:SecureCallback('whip_autos:engineDumpAllowed', {
        ace = 'whip.devtools',
        requirePlayer = false,
        rateLimit = 1000,
    }, function()
        return true
    end)

    --- One chunk of a dump: { run, index, total, entries }. The list is replaced only when every chunk
    --- of the run has arrived, so a dump that dies half way leaves the old list. A new run starts over.
    exports.whip_core:SecureEvent('whip_autos:server:engineDumpChunk', {
        ace = 'whip.devtools',
        requirePlayer = false,
        rateLimit = 100,
        burst = 10,
        params = { { 'chunk', 'any' } },
    }, function(source, _, chunk)
        if type(chunk) ~= 'table' or type(chunk.entries) ~= 'table' then return end
        local index, total = math.floor(tonumber(chunk.index) or 0), math.floor(tonumber(chunk.total) or 0)
        if index < 1 or total < 1 or index > total or total > 1000 then return end
        local run = tostring(chunk.run or '')

        local d = _dumps[source]
        if not d or d.run ~= run or d.total ~= total then
            d = { run = run, total = total, got = {}, engines = {}, count = 0 }
            _dumps[source] = d
        end
        for _, raw in ipairs(chunk.entries) do
            local model, entry = cleanEntry(raw)
            if model and not d.engines[model] then
                d.engines[model] = entry
                d.count = d.count + 1
            end
        end
        d.got[index] = true

        for i = 1, total do
            if not d.got[i] then return end
        end

        -- Every chunk is in: replace the list.
        _dumps[source] = nil
        store.engines = d.engines
        store.builtAt = os.date('%Y-%m-%d %H:%M:%S')
        store.builtBy = GetPlayerName(source)
        listCache = nil
        local ok = save()
        print(('[whip_autos] engine list %s: %d engines, by %s')
            :format(ok and 'written' or 'FAILED to write', d.count, tostring(store.builtBy)))
        TriggerClientEvent('whip_autos:client:engineDumpSaved', source, ok and true or false, d.count)
    end)
end

AddEventHandler('playerDropped', function() _dumps[source] = nil end)

Whip.register(RegisterWithWhip)
