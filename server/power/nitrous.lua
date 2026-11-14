-- ============================================
-- whip_autos power — nitrous (server)
-- ============================================
--
-- The bottle: an item, the 'nitro' vehicle stat and a timed install. whip_core owns the burn-down:
-- the client reports what it used with ConsumeVehicleStat, and `consume` below caps and bills it.
-- The client half is client/power/nitrous.lua. How long a bottle lasts and how long fitting takes:
-- Config.Nitrous, read through PowerNitrous (shared/power.lua), the same numbers the client burns by.

--- Nitrous fits cars and motorbikes only: the classes in PowerClasses (shared/power.lua), the
--- ones the client boosts. Entity types allowed: a bicycle is a 'bike' too, so the class decides when
--- the vehicle catalogue knows the model.
local NITRO_TYPES = { automobile = true, bike = true }

--- The whip car this player sits in, if a bottle can go in it.
---@param source number
---@return number|false vehicleId, string|nil why  a sentence for the player
local function carForBottle(source)
    local vehicleId, why = exports.whip_core:GetPlayerVehicle(source)
    if not vehicleId then return false, why end
    -- class is from the vehicle catalogue and nil for a model it does not know; vehType always answers.
    local v = exports.whip_core:GetVehicle(vehicleId)
    if not v then return false, 'Could not find that car' end
    local class = tonumber(v.class)
    if (class and not PowerClasses[class]) or not NITRO_TYPES[v.vehType] then
        return false, 'Nitrous only fits cars and motorbikes'
    end
    if exports.whip_core:HasVehicleStat(vehicleId, 'nitro') then
        return false, 'This car already has nitrous'
    end
    return vehicleId
end

-- ---- Exhaust flames ----
--
-- The driver says when a burn starts and stops; this passes it to the players near the car, who each
-- draw the flames (the networked ptfx native draws for its caller only). Never back to the driver.

local FLAME_RANGE = 300.0   -- metres from the car, flat

--- [source] = netId of the car whose flames this player lit, so the "off" (and a drop mid-burn)
--- reaches that car even after its driver got out.
local _flaming = {}

local function relayFlames(src, netId, on)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end   -- gone: each client drops it
    -- Whip.call: playerDropped calls this too, outside anything whip_core runs.
    local near = Whip.call('GetPlayersInRange', GetEntityCoords(veh), FLAME_RANGE)
    if type(near) ~= 'table' then return end
    for _, target in ipairs(near) do
        if target ~= src then TriggerClientEvent('whip_autos:client:nitroFlames', target, netId, on) end
    end
end

local function flamesOff(src)
    local netId = _flaming[src]
    if not netId then return end
    _flaming[src] = nil
    relayFlames(src, netId, false)
end

AddEventHandler('playerDropped', function() flamesOff(source) end)

--- The nitro stat: on every vehicle, present on none. A car has nitrous when it holds a value, which
--- fitting sets and clearAtMin takes away; showAboveZero keeps the gauge off every other car. Declared
--- again when Config.Nitrous changes, since the burn cap is worked out from it.
---@return boolean ok
local function registerNitroStat()
    local ok, err = exports.whip_core:RegisterVehicleStat('nitro', {
        default = 0,
        min     = 0,
        max     = PowerNitrous.BOTTLE,
        persist = true,    -- a fitted bottle survives a restart

        -- whip_core owns the report event, the driver check and the wall-clock cap.
        consume = {
            maxRate    = PowerNitrous.burnPerSec,   -- per second, what the client burns; anything above is refused
            driverOnly = true,                      -- a passenger cannot drain the bottle
            clearAtMin = true,                      -- empty means no bottle: the stat comes off the car
            interval   = 0.5,                       -- seconds between the client's reports while boosting
        },

        -- No icon: the dial draws its own nitro glyph (whip_core html/js/vehicle-dial.js, ICONS).
        hud = {
            label         = 'Nitrous',
            color         = '#60a5fa',
            order         = 4,
            showAboveZero = true,
            noCritical    = true,
        },
    })
    if not ok then print(('[whip_autos] could not register the nitro stat: %s'):format(tostring(err))) end
    return ok
end

--- Using a bottle fits it. A table, so whip_core runs the install: the bar (timed by the server), takes
--- the bottle, then onComplete. The car is the one the server sees the player in, never the client's
--- word. Declared again when Config.Nitrous changes (the bar's length).
local function registerInstall()
    exports.whip_core:RegisterUseHandler('nitro', {
        label    = 'Installing nitrous...',
        duration = PowerNitrous.installMs,
        reason   = 'fitted to a car',
        -- Fitted from the seat, so getting out stops it: the bar ends, the bottle stays yours.
        cancelOnExit = true,

        -- Before the bar, so it does not run for nothing.
        canUse = function(source)
            local vehicleId, why = carForBottle(source)
            if not vehicleId then return false, why end
            return true
        end,

        -- After the bar, the bottle taken. Asked again: ten seconds is time to change cars.
        -- `false, 'why'` gives the bottle back.
        onComplete = function(source)
            local vehicleId, why = carForBottle(source)
            if not vehicleId then return false, why end

            local fitted, fitErr = exports.whip_core:SetVehicleStat(vehicleId, 'nitro', PowerNitrous.BOTTLE, 'whip_autos:nitrous')
            if not fitted then
                print(('[whip_autos] nitrous install on vehicle %d failed: %s'):format(vehicleId, tostring(fitErr)))
                return false, 'Could not fit the bottle'
            end

            exports.whip_core:NotifyPlayer(source, 'Nitrous installed', 'success')
        end,
    })
end

local function RegisterWithWhip()
    if not registerNitroStat() then return end

    exports.whip_core:RegisterItem('nitro', {
        name     = 'Nitrous Bottle',
        desc     = 'Bolts into a car or motorbike. Hold the boost for a few seconds of very poor decisions.',
        weight   = 2.0,
        type     = 'consumable',
        stack    = true,
        maxStack = 5,
        usable   = true,
        cooldown = 3,
        prop     = 'p_s_scuba_tank_s',   -- the nearest thing GTA has to a bottle; checked against its object list
    })

    registerInstall()

    -- Flames on (a burn started) or off. Declared here, with the rest, once whip_core is ready. The
    -- client sends at most one per 150 ms and always its latest state, so this limit never eats an "off".
    exports.whip_core:SecureEvent('whip_autos:server:nitroFlames', {
        rateLimit = 150,
        burst     = 4,
        sheet     = 'light',   -- the handler reads no player sheet: the full one is copied across for nothing
        params    = { { 'on', 'bool' } },
    }, function(source, _, on)
        if not on then flamesOff(source) return end
        -- On: only the driver of a whip car carrying nitrous, as the server sees them.
        local vehicleId = exports.whip_core:GetPlayerVehicle(source, { driver = true })
        if not vehicleId or not exports.whip_core:HasVehicleStat(vehicleId, 'nitro') then return end
        local netId = NetworkGetNetworkIdFromEntity(GetVehiclePedIsIn(GetPlayerPed(source), false))
        if _flaming[source] and _flaming[source] ~= netId then flamesOff(source) end
        _flaming[source] = netId
        relayFlames(source, netId, true)
    end)

    print('[whip_autos] nitrous ready — item, vehicle stat and gauge registered')
end

Whip.register(RegisterWithWhip)

-- A change to Config.Nitrous in /whip → Settings: the burn cap and the install bar follow it
-- (shared/power.lua has read the new numbers by now).
Whip.onConfigChanged('Nitrous', function()
    if GetResourceState('whip_core') ~= 'started' then return end
    if registerNitroStat() then registerInstall() end
end)
