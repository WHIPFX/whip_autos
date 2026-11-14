-- Tuning in the world: applies what cars have bought (VehicleData, written by server/tuning.lua). GTA replicates
-- none of it, so every client applies it to the cars it can see:
--   engine sound   every client, every car in view
--   engine power   the driver only, as a handling layer
--   stance         every client, cars within Config.Tuning.Stance.DrawRange
--   handling setup the driver only, as a handling layer
--   drivetrain     every client, every car in view
-- The shop's previews go through here too (Tuning.preview*) and win until cleared.

Tuning = {}

--- The car this player is driving (the driver's seat), or nil. Also client/power/ (loaded after this).
function AutosDrivenCar()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then return veh end
    return nil
end

local STANCE = Config.Tuning.Stance

-- Engine sound

--- [entity] = sound a shop preview is playing.
local _soundPreview = {}
--- [entity] = the model whose engine a shop preview shows on the rev dial; false = the car's own.
local _revPreview = {}
--- [entity] = the saved engine data applied here.
local _engines = {}
--- [entity] = true: this client forced a sound onto the car, so it is the one to put it back.
local _forcedSound = {}

--- Plays `sound` as this car's engine, keeping our radio station (the native resets it).
local function setEngineSound(entity, sound)
    if not DoesEntityExist(entity) or type(sound) ~= 'string' or sound == '' then return end
    local ped = PlayerPedId()
    local station = GetVehiclePedIsIn(ped, false) == entity and GetPlayerRadioStationName() or nil
    ForceUseAudioGameObject(entity, sound)
    _forcedSound[entity] = true
    if station and station ~= '' then SetVehRadioStation(entity, station) end
end

-- The Cfx-only native that names a model (tools/objectviewer.lua guards it the same way).
local archetypeFn = rawget(_G, 'GetEntityArchetypeName')

--- The car's own engine sound: its model name (not its display name, which is a text label such as
--- 'washingt'), through Config.Tuning.EngineSoundOverrides for a model whose sound has another name.
local function ownEngineSound(entity)
    local ok, name
    if archetypeFn then ok, name = pcall(archetypeFn, entity)
    else ok, name = pcall(Citizen.InvokeNative, 0x47B870F5, entity, Citizen.ResultAsString()) end
    if not ok or type(name) ~= 'string' or name == '' then
        name = GetDisplayNameFromVehicleModel(GetEntityModel(entity))
    end
    return TuningEngineSound(name:lower())
end

--- Gives a car its own engine sound back, only if this client changed it (a car never touched keeps
--- the sound the game chose, which may not be named after the model at all).
local function restoreEngineSound(entity)
    if not _forcedSound[entity] then return end
    if DoesEntityExist(entity) then setEngineSound(entity, ownEngineSound(entity)) end
    _forcedSound[entity] = nil
end

local function soundFor(entity)
    return _soundPreview[entity] or (_engines[entity] and _engines[entity].sound) or nil
end

--- The rev dial follows the engine: a swapped car's dial goes by the donor's model. whip_core works out the
--- range (Config.VehicleHud); this only says which engine. A preview wins while it lasts, as with the sound.
local function applyRevs(entity)
    local preview = _revPreview[entity]
    local model
    if preview ~= nil then model = preview or nil
    else model = _engines[entity] and _engines[entity].model or nil end
    Whip.call('SetVehicleRevRange', { entity = entity }, model)
end

-- Stance

--- [entity] = saved stance; [entity] = shop preview stance (wins while it lasts). Slider units.
local _stanced, _stancePreview = {}, {}
--- [entity] = the stance and drivetrain as saved on the car, before the limits: cleaned again when the
--- limits change in /whip.
local _stanceSaved, _driveSaved = {}, {}
--- [entity] = the car's own ride height and suspension travel, captured once.
local _defaults = {}
--- [entity] = custom rims' width, size and colliders: the game's value and ours (scaleLasting).
local _rims = {}
--- [entity] = the stance being drawn, in native units; rebuilt twice a second.
local _drawn = {}
--- [entity][wheel] = { bx, wx, br, wr }: 'follow' mode's base and written value per axis.
local _follow = {}
--- [entity] = { since, skip }: since when the game has left every wheel as we wrote it, and how many
--- frames to skip before looking again. Kept apart from _follow, whose pairs() are wheels.
local _quiet = {}
--- [entity] = { front, rear, onF, onR }: 'handling' mode's own camber and what we set.
local _handlingCamber = {}
--- Can scripts set handling camber here? nil until tried.
local handlingOk = nil

--- [entity] = { powered = { [wheel] = bool }, bias = number }: a car's own drivetrain while swapped.
local _driveOrig = {}

local function captureDefaults(entity)
    local d = _defaults[entity]
    if d then return d end
    d = {
        wheels = GetVehicleNumberOfWheels(entity), height = GetVehicleSuspensionHeight(entity),
        -- Suspension travel: how far a wheel can go up into the body and down away from it.
        upper = GetVehicleHandlingFloat(entity, 'CHandlingData', 'fSuspensionUpperLimit'),
        lower = GetVehicleHandlingFloat(entity, 'CHandlingData', 'fSuspensionLowerLimit'),
    }
    _defaults[entity] = d
    return d
end

--- A stance in slider units, converted to what the natives want for this car.
local function nativeStance(entity, s)
    local d = captureDefaults(entity)
    local n = {
        -- Drawn ride height (negative raises), unless height is physical (applyRaise) — never both.
        height = STANCE.PhysicalHeight and d.height or (d.height - (s.height or 0) / 100.0),
        heightDrawn = not STANCE.PhysicalHeight and (s.height or 0) ~= 0,
        widthPct = s.width or 100, sizePct = s.size or 100, wheelCount = d.wheels,
        travel = TuningTravelFactor(s.height),
        wheels = {},
        -- 'handling' mode sets camber per axle.
        camberF = math.rad(s.camberF or 0), camberR = math.rad(s.camberR or 0),
    }
    -- A bike gets ride height only.
    if d.wheels >= 4 then
        for i = 0, d.wheels - 1 do
            local front = i < 2
            local left = (i % 2) == 0
            local track = ((front and s.trackF or s.trackR) or 0) / 100.0
            local camber = math.rad((front and s.camberF or s.camberR) or 0)
            n.wheels[i] = { dx = left and -track or track, drot = left and camber or -camber }
        end
    end
    return n
end

-- 'handling' camber (the default): the car's own CCarHandlingData geometry, set once per car. If a game refuses it,
-- camber falls back to 'follow' (said once).

local function restoreHandlingCamber(entity)
    local saved = _handlingCamber[entity]
    if not saved then return end
    _handlingCamber[entity] = nil
    if not DoesEntityExist(entity) then return end
    pcall(SetVehicleHandlingFloat, entity, 'CCarHandlingData', 'fCamberFront', saved.front + 0.0)
    pcall(SetVehicleHandlingFloat, entity, 'CCarHandlingData', 'fCamberRear', saved.rear + 0.0)
end

local function setHandlingCamber(entity, n)
    if handlingOk == false then return end
    local saved = _handlingCamber[entity]
    if saved and saved.onF == n.camberF and saved.onR == n.camberR then return end   -- already so
    local ok, err = pcall(function()
        if not saved then
            saved = {
                front = GetVehicleHandlingFloat(entity, 'CCarHandlingData', 'fCamberFront'),
                rear  = GetVehicleHandlingFloat(entity, 'CCarHandlingData', 'fCamberRear'),
            }
            if type(saved.front) ~= 'number' or type(saved.rear) ~= 'number' then error('no camber fields on this car') end
            _handlingCamber[entity] = saved
        end
        SetVehicleHandlingFloat(entity, 'CCarHandlingData', 'fCamberFront', saved.front + n.camberF)
        SetVehicleHandlingFloat(entity, 'CCarHandlingData', 'fCamberRear', saved.rear + n.camberR)
        saved.onF, saved.onR = n.camberF, n.camberR
    end)
    if ok then handlingOk = true return end
    handlingOk = false
    _handlingCamber[entity] = nil
    print(('[whip_autos] handling camber is not available here (%s) — camber is drawn the follow way'):format(tostring(err)))
    Whip.call('Notify', 'Handling camber did not take — camber is drawn the follow way (F8 says why)', 'error', 8000)
end

-- ---- 'follow' (track, and camber in follow mode) ----

--- One axis of one wheel this frame: the stance on top of where the game put it. If it still reads what was written,
--- last frame's base is kept.
---@return number base, number write
local function follow(cur, base, written, delta)
    if written ~= nil and math.abs(cur - written) < 0.00001 then return base, base + delta end
    return cur, cur + delta
end

--- One wheel this frame. An axis that went back to 0 is handed back to the game once. Returns true when nothing
--- needed writing, which lets the loop check a settled car less often.
---@return boolean held
local function drawFollow(entity, i, w, rotate)
    local f = _follow[entity]
    if not f then f = {}; _follow[entity] = f end
    local m = f[i]
    if not m then m = {}; f[i] = m end
    local held = true

    if w.dx ~= 0 then
        local cur, wrote = GetVehicleWheelXOffset(entity, i), m.wx
        m.bx, m.wx = follow(cur, m.bx, m.wx, w.dx)
        if wrote == nil or math.abs(cur - wrote) >= 0.00001 or m.wx ~= wrote then
            SetVehicleWheelXOffset(entity, i, m.wx)
            held = false
        end
    elseif m.wx ~= nil then
        SetVehicleWheelXOffset(entity, i, m.bx)
        m.bx, m.wx = nil, nil
        held = false
    end

    local drot = rotate and w.drot or 0
    if drot ~= 0 then
        local cur, wrote = GetVehicleWheelYRotation(entity, i), m.wr
        m.br, m.wr = follow(cur, m.br, m.wr, drot)
        if wrote == nil or math.abs(cur - wrote) >= 0.00001 or m.wr ~= wrote then
            SetVehicleWheelYRotation(entity, i, m.wr)
            held = false
        end
    elseif m.wr ~= nil then
        SetVehicleWheelYRotation(entity, i, m.br)
        m.br, m.wr = nil, nil
        held = false
    end
    return held
end

-- Wheel width and size (custom rims only): GTA resets them whenever rims are refitted, so the game's value is re-read
-- as the base. Size also scales the tyre and rim colliders.

--- A value kept at `pct`% of the game's own. Returns the value to write, or nil. `mem` holds the
--- game's value (b..key) and ours (w..key).
local function scaleLasting(mem, key, cur, pct)
    if type(cur) ~= 'number' then return nil end
    local bk, wk = 'b' .. key, 'w' .. key
    local wrote = mem[wk]
    if wrote == nil or math.abs(cur - wrote) > 0.0005 then mem[bk] = cur end   -- the game's own value
    local base = mem[bk]
    if pct == 100 then
        -- Back to the rim's own: hand it back once.
        if wrote ~= nil then mem[wk] = nil; return base end
        return nil
    end
    local want = base * pct / 100
    mem[wk] = want
    if math.abs(cur - want) > 0.0005 then return want end
    return nil
end

--- Do the collider natives exist here? nil until tried; without them size and width are looks only.
local collidersOk = nil

local function applyColliders(entity, r, n)
    if collidersOk == false then return end
    local ok, err = pcall(function()
        r.c = r.c or {}
        for i = 0, (n.wheelCount or 4) - 1 do
            local m = r.c[i]
            if not m then m = {}; r.c[i] = m end
            local t = scaleLasting(m, 'tyre', GetVehicleWheelTireColliderSize(entity, i), n.sizePct)
            if t then SetVehicleWheelTireColliderSize(entity, i, t + 0.0) end
            local rim = scaleLasting(m, 'rim', GetVehicleWheelRimColliderSize(entity, i), n.sizePct)
            if rim then SetVehicleWheelRimColliderSize(entity, i, rim + 0.0) end
            local tw = scaleLasting(m, 'tyreW', GetVehicleWheelTireColliderWidth(entity, i), n.widthPct)
            if tw then SetVehicleWheelTireColliderWidth(entity, i, tw + 0.0) end
        end
    end)
    if ok then collidersOk = true return end
    collidersOk = false
    print(('[whip_autos] wheel colliders are not available here (%s) — wheel size is looks only'):format(tostring(err)))
end

--- Puts the rims' width, size and colliders back where we changed them.
local function restoreRims(entity)
    local r = _rims[entity]
    _rims[entity] = nil
    if not r or not DoesEntityExist(entity) then return end
    if r.wwidth ~= nil then SetVehicleWheelWidth(entity, r.bwidth + 0.0) end
    if r.wsize ~= nil then SetVehicleWheelSize(entity, r.bsize + 0.0) end
    if r.c and collidersOk then
        pcall(function()
            for i, m in pairs(r.c) do
                if m.wtyre ~= nil then SetVehicleWheelTireColliderSize(entity, i, m.btyre + 0.0) end
                if m.wrim ~= nil then SetVehicleWheelRimColliderSize(entity, i, m.brim + 0.0) end
                if m.wtyreW ~= nil then SetVehicleWheelTireColliderWidth(entity, i, m.btyreW + 0.0) end
            end
        end)
    end
end

--- Puts a car's looks back as they were before we touched them (a crash-bent wheel stays bent).
local function unstance(entity)
    local d = _defaults[entity]
    local f = _follow[entity]
    _drawn[entity] = nil
    if DoesEntityExist(entity) then
        if d then SetVehicleSuspensionHeight(entity, d.height) end
        if d and d.travelSet then
            SetVehicleHandlingFloat(entity, 'CHandlingData', 'fSuspensionUpperLimit', d.upper + 0.0)
            SetVehicleHandlingFloat(entity, 'CHandlingData', 'fSuspensionLowerLimit', d.lower + 0.0)
        end
        if f then
            for i, m in pairs(f) do
                if m.wx ~= nil then SetVehicleWheelXOffset(entity, i, m.bx) end
                if m.wr ~= nil then SetVehicleWheelYRotation(entity, i, m.br) end
            end
        end
    end
    restoreRims(entity)
    restoreHandlingCamber(entity)
    _defaults[entity] = nil
    _follow[entity] = nil
    _quiet[entity] = nil
end

--- Suspension travel scaled with ride height (Config.Tuning.Stance.Travel). Both limits by the same
--- share of the car's own; written only when it differs. Untouched cars at factor 1 are not read at all.
local function applyTravel(entity, n)
    local d = _defaults[entity]
    if not d or type(d.upper) ~= 'number' or type(d.lower) ~= 'number' then return end
    if n.travel == 1 and not d.travelSet then return end
    local up, lo = d.upper * n.travel, d.lower * n.travel
    if math.abs(GetVehicleHandlingFloat(entity, 'CHandlingData', 'fSuspensionUpperLimit') - up) > 0.0005 then
        SetVehicleHandlingFloat(entity, 'CHandlingData', 'fSuspensionUpperLimit', up + 0.0)
        d.travelSet = true
    end
    if math.abs(GetVehicleHandlingFloat(entity, 'CHandlingData', 'fSuspensionLowerLimit') - lo) > 0.0005 then
        SetVehicleHandlingFloat(entity, 'CHandlingData', 'fSuspensionLowerLimit', lo + 0.0)
        d.travelSet = true
    end
    if n.travel == 1 then d.travelSet = nil end   -- back to its own: left to the game
end

--- The parts that stay put once set: ride height, travel, and on custom rims width and size. Written
--- when they differ, twice a second.
local function applyLasting(entity, n)
    if math.abs(GetVehicleSuspensionHeight(entity) - n.height) > 0.001 then
        SetVehicleSuspensionHeight(entity, n.height)
    end
    applyTravel(entity, n)
    if GetVehicleMod(entity, 23) == -1 then return end              -- custom rims only
    local r = _rims[entity]
    if not r then
        if n.widthPct == 100 and n.sizePct == 100 then return end   -- nothing asked, nothing touched
        r = {}
        _rims[entity] = r
    end
    local w = scaleLasting(r, 'width', GetVehicleWheelWidth(entity), n.widthPct)
    if w then SetVehicleWheelWidth(entity, w + 0.0) end
    local sz = scaleLasting(r, 'size', GetVehicleWheelSize(entity), n.sizePct)
    if sz then SetVehicleWheelSize(entity, sz + 0.0) end
    applyColliders(entity, r, n)
end

--- The stance a car shows now: the preview, else what it has saved.
local function stanceFor(entity)
    return _stancePreview[entity] or _stanced[entity]
end

--- Is camber drawn per wheel every frame? Only in 'follow' mode, or if the handling was refused.
local function camberPerFrame()
    return STANCE.Mode ~= 'handling' or handlingOk == false
end

--- Does any car in range need the every-frame pass? (refreshDrawn)
local framesNeeded = false

--- Has GTA put back a lasting part (the drawn ride height, or a custom rim's size or width)? GTA resets the ride
--- height whenever the transmission is rebuilt. That happens to the driven car at any handling write (checked on the
--- per-frame pass) and to a car whose drivetrain swap is applied here; every other car is put back by refreshDrawn.
local function lastingMoved(entity, n)
    if n.heightDrawn and math.abs(GetVehicleSuspensionHeight(entity) - n.height) > 0.001 then return true end
    local r = _rims[entity]
    if r then
        if r.wsize ~= nil and math.abs(GetVehicleWheelSize(entity) - r.wsize) > 0.0005 then return true end
        if r.wwidth ~= nil and math.abs(GetVehicleWheelWidth(entity) - r.wwidth) > 0.0005 then return true end
    end
    return false
end

--- Does this car need the every-frame pass? Track, 'follow' camber, or a wheel still to hand back — and, on the car
--- this player drives, a drawn ride height or resized rims, for lastingMoved.
local function needsFrames(entity, n, rotate)
    for _, w in pairs(n.wheels) do
        if w.dx ~= 0 or (rotate and w.drot ~= 0) then return true end
    end
    for _, m in pairs(_follow[entity] or {}) do
        if m.wx ~= nil or m.wr ~= nil then return true end
    end
    if not n.driven then return false end
    if n.heightDrawn then return true end
    local r = _rims[entity]
    if r and (r.wsize ~= nil or r.wwidth ~= nil) then return true end
    return false
end

--- Finds the stanced cars in range, applies their lasting parts, and decides whether any needs the
--- every-frame pass.
local function refreshDrawn()
    local me = GetEntityCoords(PlayerPedId())
    local range2 = (STANCE.DrawRange or 150.0) ^ 2
    local frameRange2 = (STANCE.FrameRange or 60.0) ^ 2
    local seen = {}
    for entity in pairs(_stanced) do seen[entity] = true end
    for entity in pairs(_stancePreview) do seen[entity] = true end
    for entity in pairs(seen) do
        local s = stanceFor(entity)
        if s and DoesEntityExist(entity) then
            local p = GetEntityCoords(entity)
            local dx, dy, dz = p.x - me.x, p.y - me.y, p.z - me.z
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 <= range2 then
                local n = nativeStance(entity, s)
                applyLasting(entity, n)
                if STANCE.Mode == 'handling' then setHandlingCamber(entity, n) end
                n.near = d2 <= frameRange2   -- close enough for the every-frame pass (FrameRange)
                n.d2 = d2
                _drawn[entity] = n
            else
                _drawn[entity] = nil
            end
        else
            _drawn[entity] = nil
        end
    end

    local rotate = camberPerFrame()
    local mine = AutosDrivenCar()
    local list = {}   -- the cars for the every-frame pass
    for entity, n in pairs(_drawn) do
        n.driven = entity == mine
        n.frames = needsFrames(entity, n, rotate)
        if n.frames and n.near then list[#list + 1] = entity end
    end
    framesNeeded = #list > 0   -- only far ones, or none: the loop can sleep

    -- Who gets every frame: the car this player drives, then the nearest up to NearCount within NearRange. The rest
    -- are looked at every FarEvery frames, each starting on a different frame so they never all land on one.
    table.sort(list, function(a, b) return _drawn[a].d2 < _drawn[b].d2 end)
    local nearRange2 = (STANCE.NearRange or 25.0) ^ 2
    local nearCount = math.max(1, math.floor(tonumber(STANCE.NearCount) or 6))
    local farEvery = math.max(1, math.floor(tonumber(STANCE.FarEvery) or 3))
    local near = 0
    for i, entity in ipairs(list) do
        local n = _drawn[entity]
        if n.driven or (near < nearCount and n.d2 <= nearRange2) then
            near = near + 1
            n.every = nil   -- every frame (SettledFrames once settled)
        else
            n.every = farEvery
        end
        local q = _quiet[entity]
        if not q then q = { since = nil, skip = 0 }; _quiet[entity] = q end
        if n.every and q.every ~= n.every then q.skip = i % n.every end
        q.every = n.every
    end
end

--- Drops cars that no longer exist (handles get reused). onLost normally does this; this catches the rest.
local function forgetGone()
    for _, t in ipairs({ _defaults, _stanced, _stancePreview, _soundPreview, _revPreview, _engines, _forcedSound,
                         _follow, _quiet, _handlingCamber, _rims, _driveOrig, _stanceSaved, _driveSaved }) do
        for entity in pairs(t) do
            if not DoesEntityExist(entity) then t[entity] = nil end
        end
    end
end

-- The one loop for every tuned car in the world: refresh twice a second, per frame only while a car in
-- range needs it, five times a second while the shop previews a stance, sweep every five seconds.
CreateThread(function()
    local lastRefresh, lastSweep = 0, 0
    while true do
        local now = GetGameTimer()
        if now - lastRefresh >= 500 then
            local cost = WhipCost.start()   -- /whipcost (whip_core's lib/cost.lua)
            refreshDrawn()
            WhipCost.stop('stance: which cars to draw (2 a second)', cost)
            lastRefresh = now
        end
        if now - lastSweep >= 5000 then
            forgetGone()
            lastSweep = now
        end
        if not framesNeeded then
            Wait(next(_stancePreview) and 200 or 500)
        else
            -- Only cars within FrameRange and on screen. The near ones (the driven car and the nearest NearCount
            -- within NearRange) are looked at every frame; once settled, every Stance.SettledFrames frames. The
            -- rest every FarEvery frames. GTA resets the offsets only occasionally, which is why skipping works.
            local cost = WhipCost.start()
            local rotate = camberPerFrame()
            local every = math.max(1, math.floor(tonumber(STANCE.SettledFrames) or 1))
            for entity, n in pairs(_drawn) do
                if n.frames and n.near then
                    local q = _quiet[entity]
                    if not q then q = { since = nil, skip = 0 }; _quiet[entity] = q end
                    if q.skip > 0 then
                        -- A skipped frame asks the game nothing, not even whether the car still exists:
                        -- nothing here touches it until the next look, which asks first.
                        q.skip = q.skip - 1
                    elseif not DoesEntityExist(entity) then
                        _drawn[entity] = nil   -- its _quiet entry goes in forgetGone's sweep
                    else
                        if IsEntityOnScreen(entity) then
                            local held = true
                            -- The ride height and rims of the car this player drives, put back the frame GTA
                            -- resets them (lastingMoved).
                            if n.driven and lastingMoved(entity, n) then
                                applyLasting(entity, n)
                                held = false
                            end
                            for i, w in pairs(n.wheels) do
                                if not drawFollow(entity, i, w, rotate) then held = false end
                            end
                            if held then q.since = q.since or now else q.since = nil end
                        end
                        if n.every then
                            q.skip = n.every - 1
                        else
                            q.skip = (q.since and now - q.since >= 1000) and (every - 1) or 0
                        end
                    end
                end
            end
            WhipCost.stop('stance: the wheels, each frame (stanced cars near and on screen)', cost)
            Wait(0)
        end
    end
end)

-- Getting in or out puts the car's ride height back (the transmission is rebuilt as handling layers change), so
-- refreshDrawn marks the driven car at once and it is watched every frame for a moment after.
local SEAT_WATCH_MS = 1500
local function watchSeatChange(entity)
    refreshDrawn()
    if not entity or entity == 0 then return end
    CreateThread(function()
        local untilAt = GetGameTimer() + SEAT_WATCH_MS
        while GetGameTimer() < untilAt do
            local n = _drawn[entity]
            if not n or not DoesEntityExist(entity) then return end
            if lastingMoved(entity, n) then applyLasting(entity, n) end
            Wait(0)
        end
    end)
end
AddEventHandler('whip_core:vehicle:entered', function(d) if type(d) == 'table' then watchSeatChange(d.entity) end end)
AddEventHandler('whip_core:vehicle:exited', function(d) if type(d) == 'table' then watchSeatChange(d.entity) end end)

--- Switches how camber is drawn, redrawing every stanced car.
---@param mode string  'handling' | 'follow'
function Tuning.setStanceMode(mode)
    for entity in pairs(_defaults) do unstance(entity) end
    STANCE.Mode = mode
    if mode == 'handling' then handlingOk = nil end   -- ask again
    refreshDrawn()
end

-- Changed in /whip: Config already holds the new mode, so each car is put back the old way first.
Whip.onConfigChanged('Tuning.Stance.Mode', function(mode, old)
    STANCE.Mode = old
    Tuning.setStanceMode(mode)
end)

-- Drivetrain: applied on every client to every car in view, written directly per car (handling layers hold the driven
-- car only). GTA needs both the per-wheel "powered" flags and fDriveBiasFront, written in handling.meta form (0 RWD,
-- 1 FWD, between = AWD front share).

local driveOk = nil     -- do the wheel natives exist here? nil until tried

--- fDriveBiasFront and which axles are driven, for a drivetrain.
local function driveValues(d)
    if d.layout == 'fwd' then return 1.0, true, false end
    if d.layout == 'rwd' then return 0.0, false, true end
    return (d.front or 50) / 100, true, true
end

--- Makes a drive change take: rebuild the transmission and refit its mod as itself.
--- 0.0, not 1.0: ModifyVehicleTopSpeed's argument is a top speed change in percent (and it adjusts drag).
local function refreshDrive(entity)
    ModifyVehicleTopSpeed(entity, 0.0)
    SetVehicleModKit(entity, 0)
    SetVehicleMod(entity, 13, GetVehicleMod(entity, 13), false)
    -- The rebuild puts GTA's ride height back: drawn again now, not at the next refresh (lastingMoved).
    local n = _drawn[entity]
    if n then applyLasting(entity, n) end
end

--- Puts the car's own drivetrain back. Natives only, so every exit can run it.
local function restoreDriveLocal(entity)
    local o = _driveOrig[entity]
    _driveOrig[entity] = nil
    if not o or not DoesEntityExist(entity) then return end
    for i, p in pairs(o.powered) do pcall(SetVehicleWheelIsPowered, entity, i, p) end
    if o.bias then SetVehicleHandlingFloat(entity, 'CHandlingData', 'fDriveBiasFront', o.bias + 0.0) end
    refreshDrive(entity)
end

--- Applies a car's drivetrain on this client; 'stock' or nothing means its own.
local function applyDrive(entity, value)
    restoreDriveLocal(entity)                                       -- always from its own values
    local d = type(value) == 'table' and TuningCleanDrive(value) or nil
    if not d or d.layout == 'stock' or driveOk == false or not DoesEntityExist(entity) then return end
    local wheels = GetVehicleNumberOfWheels(entity)
    if wheels < 4 then return end                                   -- a bike has one of each
    local bias, frontOn, rearOn = driveValues(d)

    local o = { powered = {}, bias = GetVehicleHandlingFloat(entity, 'CHandlingData', 'fDriveBiasFront') }
    local ok, err = pcall(function()
        for i = 0, wheels - 1 do o.powered[i] = GetVehicleWheelIsPowered(entity, i) end
        -- Wheels 0-1 are the front axle; the rest are driven with the rear.
        for i = 0, wheels - 1 do
            SetVehicleWheelIsPowered(entity, i, (i < 2 and frontOn) or (i >= 2 and rearOn))
        end
    end)
    if not ok then
        driveOk = false
        print(('[whip_autos] this game has no wheel drive natives (%s) — drivetrain swaps do nothing'):format(tostring(err)))
        return
    end
    driveOk = true
    _driveOrig[entity] = o

    SetVehicleHandlingFloat(entity, 'CHandlingData', 'fDriveBiasFront', bias + 0.0)
    refreshDrive(entity)
end

--- The car's own drivetrain ('fwd', 'rwd', 'awd' or nil), from its powered wheels before any swap.
function Tuning.stockDrive(entity)
    if not DoesEntityExist(entity) then return nil end
    local o = _driveOrig[entity]
    local frontOn, rearOn = false, false
    local ok = pcall(function()
        for i = 0, GetVehicleNumberOfWheels(entity) - 1 do
            local p
            if o then p = o.powered[i] else p = GetVehicleWheelIsPowered(entity, i) end
            if p and i < 2 then frontOn = true elseif p then rearOn = true end
        end
    end)
    if not ok then return nil end
    if frontOn and rearOn then return 'awd' end
    if frontOn then return 'fwd' end
    if rearOn then return 'rwd' end
    return nil
end

-- The shop's engine list

--- { model, label, class, hp, torque, soundOnly } per engine, fetched once from the server, and again
--- after the hidden or sound-only classes change in /whip.
local _engineList = nil
Whip.onConfigChanged('Tuning.HiddenEngineClasses', function() _engineList = nil end)
Whip.onConfigChanged('Tuning.SoundOnlyEngineClasses', function() _engineList = nil end)

--- The engine list, fetched the first time. Waits on the server; Session.open may.
function Tuning.engineList()
    if _engineList then return _engineList end
    local list = Whip.call('Callback', 'whip_autos:engineList')
    if type(list) == 'table' and #list > 0 then _engineList = list end
    return _engineList
end

-- The shop's previews

--- Plays an engine on this car for the shop, and shows it on the rev dial; nil goes back to what the car has saved.
---@param sound string|nil
---@param model string|false|nil  the engine's model for the dial (false: the car's own); left out, the sound's name
function Tuning.previewEngine(entity, sound, model)
    _soundPreview[entity] = sound
    if sound == nil then _revPreview[entity] = nil
    elseif model ~= nil then _revPreview[entity] = model
    else _revPreview[entity] = sound end
    local s = soundFor(entity)
    if s then setEngineSound(entity, s) else restoreEngineSound(entity) end
    applyRevs(entity)
end

--- Plays the car's own engine, even when it has a swap saved.
function Tuning.previewStockEngine(entity)
    if not DoesEntityExist(entity) then return end
    Tuning.previewEngine(entity, ownEngineSound(entity), false)
end

--- Physical ride height (Config.Tuning.Stance.PhysicalHeight): a handling layer on the car this player drives. Off by
--- default, then it only clears the layer. Never on top of the drawn height.
local function applyRaise(entity, height)
    Whip.call('ClearVehicleHandlingLayer', 'stance')   -- first, so the base does not include our raise
    if not STANCE.PhysicalHeight or not height or height == 0 then return end
    if not DoesEntityExist(entity) or GetPedInVehicleSeat(entity, -1) ~= PlayerPedId() then return end
    local base = Whip.call('GetVehicleHandlingBase', { entity = entity }, 'fSuspensionRaise')
    if type(base) ~= 'number' then return end
    Whip.call('SetVehicleHandlingLayer', { entity = entity }, 'stance', {
        set = { fSuspensionRaise = base + height / 100.0 },
    })
    ActivatePhysics(entity)
end

--- Shows a stance on this car for the shop (slider units); nil goes back to what the car has saved.
function Tuning.previewStance(entity, stance)
    _stancePreview[entity] = stance and TuningCleanStance(stance) or nil
    if not stanceFor(entity) then unstance(entity) end
    refreshDrawn()
    local s = stanceFor(entity)
    applyRaise(entity, s and s.height or nil)
end

--- A stance drawn on a car only this game has (the world builder's copy of a Director car: client/look.lua): no
--- physical raise (that is the driven car's), and nothing saved. nil lets it go.
function Tuning.drawStance(entity, stance)
    _stancePreview[entity] = stance and TuningCleanStance(stance) or nil
    if not stanceFor(entity) then unstance(entity) end
    refreshDrawn()
end

--- Drops every preview on this car.
function Tuning.clearPreviews(entity)
    if _soundPreview[entity] then Tuning.previewEngine(entity, nil) end
    if _stancePreview[entity] then Tuning.previewStance(entity, nil) end
end

-- A Director copy the player drives
-- A take is recorded in a car of this game's own (client/look.lua). It has no VehicleData, so what the watchers below
-- put on a bought car is put on it here from its look; engine power, handling setup and ride height only while the
-- player is at its wheel.

local _worn = {}   -- [entity] = true while a copy wears a look

---@param w table  { engine = engine data (Engines.data), stance, setup, drive = each cleaned } (any may be nil)
function Tuning.wearCopy(entity, w)
    if _worn[entity] or not DoesEntityExist(entity) or type(w) ~= 'table' then return end
    _worn[entity] = true
    if w.engine then
        _engines[entity] = w.engine
        local s = soundFor(entity)
        if s then setEngineSound(entity, s) end
        applyRevs(entity)
    end
    if w.drive then _driveSaved[entity] = w.drive; applyDrive(entity, w.drive) end
    -- A poll, not WatchVehicleData's driverOnly: the copy has no VehicleData for a watcher to see. Our own thread,
    -- so whip_core through Whip.call.
    CreateThread(function()
        local on = false
        local function off()
            Whip.call('ClearVehicleHandlingLayer', 'engine')
            Whip.call('ClearVehicleHandlingLayer', 'setup')
            Whip.call('ClearVehicleHandlingLayer', 'stance')
            on = false
        end
        while DoesEntityExist(entity) do
            local driving = AutosDrivenCar() == entity
            if driving and not on then
                on = true
                local set = w.engine and TuningEngineSet(w.engine, GetVehicleHandlingFloat(entity, 'CHandlingData', 'fMass')) or nil
                if set then Whip.call('SetVehicleHandlingLayer', { entity = entity }, 'engine', { set = set }) end
                local scale = w.setup and TuningSetupScale(w.setup) or nil
                if scale and next(scale) then Whip.call('SetVehicleHandlingLayer', { entity = entity }, 'setup', { scale = scale }) end
                applyRaise(entity, w.stance and w.stance.height or nil)
            elseif on and not driving then
                off()
            end
            Wait(250)
        end
        if on then off() end
        _worn[entity] = nil
    end)
end

-- Told by whip_core

local function RegisterWithWhip()
    -- Engine sound, every car in view with a swap.
    -- And the rev dial: every car in view, so the dial of whoever gets in follows the swap (applyRevs).
    exports.whip_core:WatchVehicleData(TUNING_ENGINE_KEY, {
        id = 'engineSound',
        onGained = function(entity, value)
            _engines[entity] = value
            local s = soundFor(entity)
            if s then setEngineSound(entity, s) end
            applyRevs(entity)
        end,
        onChanged = function(entity, value)
            _engines[entity] = value
            local s = soundFor(entity)
            if s then setEngineSound(entity, s) end
            applyRevs(entity)
        end,
        onLost = function(entity)
            _engines[entity] = nil
            if not _soundPreview[entity] then restoreEngineSound(entity) end
            applyRevs(entity)
        end,
    })

    -- Engine power, the car this player drives: a handling layer. driverOnly follows a car's data (onStart as they
    -- take its wheel, onStop as they leave it).
    exports.whip_core:WatchVehicleData(TUNING_ENGINE_KEY, {
        id = 'enginePower',
        driverOnly = true,
        onStart = function(entity, value)
            local set = TuningEngineSet(value, GetVehicleHandlingFloat(entity, 'CHandlingData', 'fMass'))
            if set then exports.whip_core:SetVehicleHandlingLayer({ entity = entity }, 'engine', { set = set }) end
        end,
        onStop = function()
            exports.whip_core:ClearVehicleHandlingLayer('engine')
        end,
    })

    -- Stance looks, every car in view with a stance (drawn by the loop above).
    exports.whip_core:WatchVehicleData(TUNING_STANCE_KEY, {
        id = 'stanceLooks',
        onGained = function(entity, value) _stanceSaved[entity], _stanced[entity] = value, TuningCleanStance(value) end,
        onChanged = function(entity, value) _stanceSaved[entity], _stanced[entity] = value, TuningCleanStance(value) end,
        onLost = function(entity)
            _stanceSaved[entity], _stanced[entity] = nil, nil
            if not _stancePreview[entity] then unstance(entity) end
        end,
    })

    -- Handling setup, the car this player drives: a layer scaling the car's own values.
    exports.whip_core:WatchVehicleData(TUNING_SETUP_KEY, {
        id = 'setup',
        driverOnly = true,
        onStart = function(entity, value)
            local scale = TuningSetupScale(TuningCleanSetup(value))
            if next(scale) then
                exports.whip_core:SetVehicleHandlingLayer({ entity = entity }, 'setup', { scale = scale })
            end
        end,
        onStop = function()
            exports.whip_core:ClearVehicleHandlingLayer('setup')
        end,
    })

    -- Drivetrain, every car in view with one.
    exports.whip_core:WatchVehicleData(TUNING_DRIVE_KEY, {
        id = 'drive',
        onGained = function(entity, value) _driveSaved[entity] = value; applyDrive(entity, value) end,
        onChanged = function(entity, value) _driveSaved[entity] = value; applyDrive(entity, value) end,
        onLost = function(entity) _driveSaved[entity] = nil; restoreDriveLocal(entity) end,
    })

    -- Physical ride height, the car this player drives (applyRaise). A shop preview wins.
    exports.whip_core:WatchVehicleData(TUNING_STANCE_KEY, {
        id = 'stanceHeight',
        driverOnly = true,
        onStart = function(entity, value)
            local s = _stancePreview[entity] or TuningCleanStance(value)
            applyRaise(entity, s and s.height or nil)
        end,
        onStop = function()
            exports.whip_core:ClearVehicleHandlingLayer('stance')
        end,
    })
end

Whip.register(RegisterWithWhip)

-- Limits changed in /whip: cars in view are cleaned against the new limits, and the driven car gets its setup and
-- engine layers again.

Whip.onConfigChanged('Tuning.Stance', function()
    for entity, value in pairs(_stanceSaved) do _stanced[entity] = TuningCleanStance(value) end
end)

Whip.onConfigChanged('Tuning.Drive', function()
    for entity, value in pairs(_driveSaved) do applyDrive(entity, value) end
end)

Whip.onConfigChanged('Tuning.Setup', function()
    local veh = AutosDrivenCar()
    local value = veh and exports.whip_core:GetVehicleData({ entity = veh }, TUNING_SETUP_KEY)
    if type(value) ~= 'table' then return end
    local scale = TuningSetupScale(TuningCleanSetup(value))
    if next(scale) then
        exports.whip_core:SetVehicleHandlingLayer({ entity = veh }, 'setup', { scale = scale })
    else
        exports.whip_core:ClearVehicleHandlingLayer('setup')
    end
end)

local function reapplyEngine()
    local veh = AutosDrivenCar()
    local value = veh and exports.whip_core:GetVehicleData({ entity = veh }, TUNING_ENGINE_KEY)
    if not veh or type(value) ~= 'table' then return end
    local set = TuningEngineSet(value, GetVehicleHandlingFloat(veh, 'CHandlingData', 'fMass'))
    if set then exports.whip_core:SetVehicleHandlingLayer({ entity = veh }, 'engine', { set = set }) end
end
Whip.onConfigChanged('Tuning.MinDriveForce', reapplyEngine)
Whip.onConfigChanged('Tuning.MaxDriveForce', reapplyEngine)

-- This resource stopping (whip_core stopping stops it first): the looks, sounds and drivetrains go back; whip_core
-- puts its handling layers back itself.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for entity in pairs(_defaults) do unstance(entity) end
    for entity in pairs(_forcedSound) do restoreEngineSound(entity) end
    for entity in pairs(_driveOrig) do restoreDriveLocal(entity) end
end)
