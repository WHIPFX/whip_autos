-- ============================================
-- whip_autos power — nitrous (client)
-- ============================================
--
-- Holding Shift (A on a pad) in a car with a bottle: torque, exhaust flames, and the burn reported to
-- whip_core, which owns the stat (server/power/nitrous.lua registers it and the install).
-- Power is asked of PowerHandling (client/power/handling.lua) as torque, never written here. How strong
-- and how long a bottle lasts: Config.Nitrous, read through PowerNitrous (shared/power.lua).

--- whileHeld cadence while boosting, ms. Matches whip_core's HUD_REPAINT_MIN_MS: the gauge cannot be
--- drawn finer than that.
local BOOST_TICK_MS = 100

--- whileHeld cadence the rest of the time, ms. whip_core's sweep sleeps until its soonest watcher is
--- due, so a fast idle watcher would hold the whole sweep at its rate.
local IDLE_TICK_MS = 1000

-- All declared before the closures below: a local declared after a closure is a nil global read in it.
local boostWatcherId = nil     -- WatchVehicleStat's id, for SetVehicleStatWatchInterval; new on every registration
local keyVeh         = nil     -- the car with a bottle this player is driving (set by the watcher), else nil
local boosting       = false
local boostVeh       = nil
local lastBurnAt     = nil     -- GetGameTimer() of the last bill

-- ============================================
-- The gauge
-- ============================================
--
-- The server hears a burn up to half a second late (whip_core reports it every consume.interval), so
-- while you boost its number is behind what is really left. So the gauge shows this client's own count
-- instead, `estimate`:
--   * it starts from the server's number, and each bill takes the burn off it;
--   * it is shown from the press until the server has caught up after the release (its number comes
--     down to the estimate), or ESTIMATE_HOLD_MS after the release at the latest;
--   * while it is shown, a HIGHER number from the server is old news (it has not heard the whole burn
--     yet) and is ignored. Taking it would push the needle back up.

local ESTIMATE_HOLD_MS = 2000

local estimate  = 0   -- nitrous left, as this client counts it
local holdUntil = 0   -- after a burn: keep showing the estimate until then, unless the server catches up first

--- Is the gauge showing the estimate rather than the server's number?
---@return boolean
local function showingEstimate()
    return boosting or GetGameTimer() < holdUntil
end

--- The server's number arrived.
---@param v number
local function serverSays(v)
    if showingEstimate() then
        if v > estimate then return end          -- old news: it has not heard all of the burn
        if not boosting then holdUntil = 0 end   -- caught up: the gauge goes back to the server's number
    end
    estimate = v
end

--- Follow the stat's changes, once whip_core is ready (Whip.register).
local function RegisterClientWithWhip()
    exports.whip_core:OnVehicleStatChange('nitro', function(_, value, _, entity)
        if entity == keyVeh then serverSays(value or 0) end
    end)
end

-- ============================================
-- Exhaust flames
-- ============================================
--
-- Drawn here, not by GTA's nitrous system: from build 3095 it finds flame points only on stock and a
-- few modkit exhausts and runs its own charge under ours, so its flames showed about a third of the
-- time (citizenfx/fivem#2482). Every client draws them itself, because the networked looped ptfx
-- native draws for its caller only on FiveM: the driver announces on/off and the server relays it to
-- players near the car (server/power/nitrous.lua). Decoration only; every call is guarded.

local FLAME_ASSET = 'veh_xs_vehicle_mods'
local FLAME_FX    = 'veh_nitrous'
local flames       = {}         -- looped effect handles on the car this client is boosting
local remoteFlames = {}         -- [netId] = { handles, entity, at }: other players' boosting cars
local REMOTE_MAX_MS   = 25000   -- a remote car's flames go out after this: covers a lost "off"
local ANNOUNCE_GAP_MS = 150     -- at most one on/off per this, matching the server's rateLimit

--- Is this bone somewhere other than the car's own origin? No exhaust sits on the root: on Enhanced
--- _GET_VEHICLE_EXHAUST_BONE can answer it, and the flames then come out of the middle of the car.
local function offRoot(veh, bone)
    if bone < 0 then return false end
    return #(GetWorldPositionOfEntityBone(veh, bone) - GetEntityCoords(veh)) > 0.1
end

local saidRoot = false   -- told F8 once that the native answered the root

-- Exhaust bone names: 'exhaust', then 'exhaust_2' to 'exhaust_32', one for each of the game's exhaust slots
-- (the native's own count is 32). A modkit's are high: on Enhanced a Dominator's three are slots 0, 17 and
-- 18, so stopping at 16 finds only the first.
local EXHAUST_NAMES = 32

--- Every exhaust bone on the car: _GET_VEHICLE_EXHAUST_BONE (b3095+, knows modkit exhausts), else the
--- stock bone names. Its axisX answer is ignored: it sends twin exhausts' flames sideways.
local function exhaustBones(veh)
    local bones, atRoot = {}, 0
    local ok = pcall(function()
        local max = Citizen.InvokeNative(0x3EE18B00CD86C54F, Citizen.ResultAsInteger())   -- _GET_VEHICLE_MAX_EXHAUST_BONE_COUNT
        for i = 0, math.min(tonumber(max) or 0, 64) - 1 do
            local found, bone = Citizen.InvokeNative(0xE728F090D538CB18, veh, i,     -- _GET_VEHICLE_EXHAUST_BONE
                Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.ReturnResultAnyway())
            if found and found ~= 0 and tonumber(bone) and bone >= 0 then
                if offRoot(veh, bone) then bones[#bones + 1] = bone else atRoot = atRoot + 1 end
            end
        end
    end)
    if ok and #bones > 0 then return bones end
    if atRoot > 0 and not saidRoot then
        saidRoot = true
        print(('[whip_autos:nitrous] the game named the car\'s root as its exhaust (%d time(s)): the flames use the exhaust bones by name'):format(atRoot))
    end
    for i = 1, EXHAUST_NAMES do
        local b = GetEntityBoneIndexByName(veh, i == 1 and 'exhaust' or ('exhaust_' .. i))
        if b ~= -1 and offRoot(veh, b) then bones[#bones + 1] = b end
    end
    return bones
end

local onEnhanced = nil   -- asked of whip_core once (GetPlatform)

--- How a bone is turned on its car, in degrees: its world rotation less the car's. 0, 0, 0 when the
--- game will not say.
local function boneTurn(veh, bone)
    local ok, b = pcall(GetEntityBoneRotation, veh, bone)
    if not ok or type(b) ~= 'vector3' then return 0.0, 0.0, 0.0 end
    local v = GetEntityRotation(veh, 2)
    local function wrap(d) return (d + 180.0) % 360.0 - 180.0 end
    return wrap(b.x - v.x), wrap(b.y - v.y), wrap(b.z - v.z)
end

--- The flames on one car, drawn on this client only.
---
--- ON ENHANCED, ON THE CAR, NOT THE BONE. A looped effect started on a vehicle bone other than its
--- root draws nowhere there (on a Dominator the exhaust bone reads 2.1 m behind the root, and its flames
--- show nothing). So the effect goes on the car itself, at that bone's place and turned as it is. Legacy
--- keeps the bone.
---@param veh number
---@return number[] handles
local function drawFlames(veh)
    local handles = {}
    if not HasNamedPtfxAssetLoaded(FLAME_ASSET) then
        RequestNamedPtfxAsset(FLAME_ASSET)   -- loaded at start; if it was dropped, the next boost has it
        return handles
    end
    if onEnhanced == nil then onEnhanced = (Whip.core:GetPlatform()) == 'enhanced' end
    pcall(function()
        for _, bone in ipairs(exhaustBones(veh)) do
            UseParticleFxAssetNextCall(FLAME_ASSET)
            local h
            if onEnhanced then
                local p = GetWorldPositionOfEntityBone(veh, bone)
                local o = GetOffsetFromEntityGivenWorldCoords(veh, p.x, p.y, p.z)
                local rx, ry, rz = boneTurn(veh, bone)
                h = StartParticleFxLoopedOnEntity(FLAME_FX, veh, o.x, o.y, o.z, rx, ry, rz, 1.0, false, false, false)
            else
                h = StartParticleFxLoopedOnEntityBone(FLAME_FX, veh,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, bone, 1.0, false, false, false)
            end
            if h and h ~= 0 then handles[#handles + 1] = h end
        end
    end)
    return handles
end

local function putOut(handles)
    for _, h in ipairs(handles) do pcall(StopParticleFxLooped, h, false) end
end

local announced, wantAnnounced, announcedAt, announceQueued = false, false, -1e9, false

--- Tell the server this car's flames are on or off: at most one message per ANNOUNCE_GAP_MS, and the
--- latest state always goes. A dropped "off" would leave the car burning on everyone else's screen.
---@param on boolean
local function announceFlames(on)
    wantAnnounced = on
    if announceQueued then return end
    local wait = ANNOUNCE_GAP_MS - (GetGameTimer() - announcedAt)
    if wait > 0 then
        announceQueued = true
        SetTimeout(wait, function()
            announceQueued = false
            announceFlames(wantAnnounced)
        end)
        return
    end
    if on == announced then return end
    announced, announcedAt = on, GetGameTimer()
    TriggerServerEvent('whip_autos:server:nitroFlames', on)
end

local function stopFlames()
    putOut(flames)
    flames = {}
    announceFlames(false)
end

local function startFlames(veh)
    putOut(flames)
    flames = drawFlames(veh)
    announceFlames(true)
end

local function putOutRemote(netId)
    local r = remoteFlames[netId]
    if not r then return end
    remoteFlames[netId] = nil
    putOut(r.handles)
end

--- Puts out remote flames whose car went or whose "off" was lost. Runs only while there are some.
local remoteWatch = false
local function watchRemote()
    if remoteWatch then return end
    remoteWatch = true
    CreateThread(function()
        while next(remoteFlames) do
            Wait(1000)
            local now = GetGameTimer()
            for netId, r in pairs(remoteFlames) do
                if not DoesEntityExist(r.entity) or now - r.at > REMOTE_MAX_MS then putOutRemote(netId) end
            end
        end
        remoteWatch = false
    end)
end

--- A player near us started or stopped a burn (relayed by the server; never our own car).
RegisterNetEvent('whip_autos:client:nitroFlames', function(netId, on)
    if type(netId) ~= 'number' then return end
    putOutRemote(netId)
    if on ~= true or not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local handles = drawFlames(veh)
    if #handles == 0 then return end
    remoteFlames[netId] = { handles = handles, entity = veh, at = GetGameTimer() }
    watchRemote()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    putOut(flames)
    for netId in pairs(remoteFlames) do putOutRemote(netId) end
end)

-- Every client loads the effect at start, to draw anyone's flames. Bounded: a build without it gives up.
CreateThread(function()
    Whip.core:LoadPtfxAsset(FLAME_ASSET, 10000)
end)

-- ============================================
-- Boost
-- ============================================

--- Bill the burn since the last bill and take it off the estimate. whip_core adds the bills up and
--- reports them on the stat's consume.interval. By real elapsed time, clamped to 0.25 s: the first bill
--- after beginBoost covers the wait for whip_core's sweep (WATCH_IDLE_MS, 200 ms), so the clamp must
--- stay above it.
---@param veh number
---@return boolean empty  the estimate has reached 0
local function billBurn(veh)
    local now  = GetGameTimer()
    local burn = PowerNitrous.burnPerSec * math.min((now - (lastBurnAt or now)) / 1000.0, 0.25)
    lastBurnAt = now
    if burn <= 0 then return estimate <= 0 end
    estimate = math.max(0.0, estimate - burn)
    -- `{ entity = veh }`: a bare number is a vehicleId on every whip vehicle export. Whip.core: billed from
    -- whip_core's watcher and from our own key's release alike (endBoost).
    Whip.core:ConsumeVehicleStat({ entity = veh }, 'nitro', burn)
    return estimate <= 0
end

--- Stop boosting, on every path out. Bills the time since the last tick, so a short tap is not free.
--- Reached from our own key and events as well as whip_core's handlers, so whip_core goes through Whip.core.
local function endBoost()
    if not boosting then return end
    boosting = false

    billBurn(boostVeh --[[@as number]])   -- set while boosting
    if boostWatcherId then
        Whip.core:SetVehicleStatWatchInterval(boostWatcherId, IDLE_TICK_MS)
    end

    -- The server has not heard the end of this burn yet: keep the estimate up (see The gauge).
    holdUntil = GetGameTimer() + ESTIMATE_HOLD_MS

    -- Dropped, not undone by hand: whip_core multiplies what is still asked, so a spooling turbo keeps its own.
    PowerHandling.clear('nitrous')

    stopFlames()
    if boostVeh and DoesEntityExist(boostVeh) then
        SetVehicleBoostActive(boostVeh, false)
    end

    boostVeh   = nil
    lastBurnAt = nil
end

--- Start boosting this car. Called from the key itself, so the power is there on the frame it goes down
--- (and from the pad action: whip_core through Whip.core, as in endBoost).
local function beginBoost(veh)
    -- Cars and motorbikes only (PowerClasses, shared/power.lua): a bottle already on a boat or bicycle
    -- does nothing.
    if boosting or not PowerClasses[GetVehicleClass(veh)] then return end
    -- Not by a dead driver: a key mapping fires through the death control lock.
    if Whip.core:IsPlayerDead() == true then return end

    -- Start from the server's number, unless the estimate is still being shown (the server is behind
    -- then). A nil answer (car not streamed) is not an empty bottle. An empty one never boosts.
    if not showingEstimate() then
        local fromServer = Whip.core:GetVehicleStat({ entity = veh }, 'nitro')
        if type(fromServer) == 'number' then estimate = fromServer end
    end
    if estimate <= 0 then return end

    boosting   = true
    boostVeh   = veh
    lastBurnAt = GetGameTimer()

    if boostWatcherId then
        Whip.core:SetVehicleStatWatchInterval(boostWatcherId, BOOST_TICK_MS)
    end

    PowerHandling.set('nitrous', veh, PowerNitrous.torque)

    SetVehicleBoostActive(veh, true)
    startFlames(veh)
end

-- A key mapping, not IsControlPressed(21): that is an on-foot control and reads false in a vehicle.
-- The mapping also appears in the player's keybind settings.
RegisterCommand('+whip_nitrous', function()
    -- Not while a screen or a placing mode owns the keys.
    if keyVeh and DoesEntityExist(keyVeh) and Whip.core:IsGameInputFree() == true then beginBoost(keyVeh) end
end, false)

RegisterCommand('-whip_nitrous', function() endBoost() end, false)
RegisterKeyMapping('+whip_nitrous', 'Nitrous Boost', 'keyboard', 'LSHIFT')

-- Death ends the boost (otherwise it runs until the key comes up or the body leaves the seat).
AddEventHandler('whip_core:player:died', function() endBoost() end)

-- ============================================
-- On a controller: A boosts
-- ============================================
--
-- A whip pad action on A in a vehicle (RegisterPadAction): whip_core reads the button, gives A to a
-- prompt in view and to LB + A first, and holds GTA's own A (a motorbike's duck) off. Players can move it
-- on the pause menu's Controller screen. Held it boosts, released it stops. Ready only while this player
-- drives a car with a bottle: otherwise A stays GTA's.
local padBoost = false   -- a boost the pad started (a keyboard boost ends on the keyboard's release)

local function RegisterPadNitrous()
    local ok, why = exports.whip_core:RegisterPadAction('nitrous', {
        label = 'Nitrous (hold)', where = 'car', slot = 'veh_a', ready = keyVeh ~= nil,
        onPress = function()
            if keyVeh and not boosting and DoesEntityExist(keyVeh) then
                beginBoost(keyVeh)
                padBoost = boosting
            end
        end,
        onRelease = function()
            if padBoost then
                padBoost = false
                endBoost()
            end
        end,
    })
    if not ok then print('[whip_autos] no Nitrous on the controller: ' .. tostring(why)) end
end

-- ============================================
-- Driving a car with a bottle in it
-- ============================================

local function RegisterBoostWatcher()
    boostWatcherId = exports.whip_core:WatchVehicleStat('nitro', {
        -- Seeds the estimate: the change handler only hears changes, and a full bottle has none.
        onStart = function(entity, value)
            keyVeh   = entity
            estimate = value or 0
            exports.whip_core:SetPadActionReady('nitrous', true)
        end,

        -- Bills while boosting. A number returned is this client's gauge reading, drawn by whip_core
        -- instead of the server's number; returning nothing hands the gauge back (see The gauge).
        whileHeld = function(entity)
            local cost = WhipCost.start()   -- /whipcost
            if boosting and billBurn(entity) then endBoost() end   -- empty: stop now, not when the server's clear lands
            WhipCost.stop('nitrous: whileHeld (billing the burn)', cost)
            if showingEstimate() then return estimate end
        end,

        -- Out of the car, car gone, or the stat cleared (clearAtMin: the bottle ran dry).
        -- whip_core drops the reading itself before calling this.
        onStop = function()
            endBoost()
            holdUntil = 0
            keyVeh = nil
            padBoost = false
            exports.whip_core:SetPadActionReady('nitrous', false)
        end,

        interval   = IDLE_TICK_MS,   -- beginBoost raises it to BOOST_TICK_MS, endBoost lowers it again
        driverOnly = true,
    })
end

Whip.register(function()
    RegisterClientWithWhip()
    RegisterPadNitrous()
    RegisterBoostWatcher()
end)
