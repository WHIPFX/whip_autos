-- ============================================
-- whip_autos power — torque asks, and layers on the driven car
-- ============================================
-- Turbo and nitrous ask whip_core for TORQUE (SetVehiclePower, whip_core client/vehicle_handling.lua):
-- a multiplier each, and the car gets the product. Not gearing: scaling fInitialDriveMaxFlatVel
-- stretches the gears as boost builds and the car drives like a CVT. The physics decide top speed.

--- An ask is sent only when it moved 1% (the turbo's 3%: it asks up to eight times a second, and an analog throttle
--- nudges its boost on nearly every tick), is the same twice running (so a settled boost lands exactly), or is back to
--- 1.0. Each ask is a crossing into whip_core.
local ASK_STEP = 0.01
local ASK_STEP_FOR = { turbo = 0.03 }

local current = nil   -- the car the asks are on
local ref = nil       -- { entity = current }, made once a car
local asked = {}      -- [key] = multiplier last sent
local prev = {}       -- [key] = multiplier asked on the previous call, sent or not
local core = exports.whip_core   -- one look-up of the resource (each `exports.whip_core` makes it anew); a restart of
                                 -- whip_core is followed by it, as by a fresh one

--- The ask itself, made once (not a new function each ask), with the export looked up inside the caller's pcall.
local function askPower(key, multiplier) return core:SetVehiclePower(ref --[[@as WhipVehicleRef]], key, multiplier) end

PowerHandling = {}

--- Ask for this much torque on this vehicle; 1.0 is the engine as it is.
---@param key string         who is asking, one per feature ('turbo')
---@param veh number
---@param multiplier number  1.25 is a quarter more torque
function PowerHandling.set(key, veh, multiplier)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    multiplier = multiplier or 1.0

    -- whip_core drops the old car's asks when the first ask lands on a new one.
    if current ~= veh then
        current, ref = veh, { entity = veh }
        asked, prev = {}, {}
    end

    local settled = prev[key] == multiplier   -- read before it moves on
    prev[key] = multiplier
    local last = asked[key]
    if last == multiplier then return end
    local moved = last == nil or math.abs(last - multiplier) >= (ASK_STEP_FOR[key] or ASK_STEP)
    if not (moved or settled or multiplier == 1.0) then return end

    -- The docs' rule for code that runs this often (turbo's tick, eight times a second): a quick export straight,
    -- behind a started check. The pcall gives the rest of Whip.call's safety without its look-up per call.
    if GetResourceState('whip_core') ~= 'started' then return end
    local cost = WhipCost.start()   -- /whipcost
    local called, ok = pcall(askPower, key, multiplier)
    WhipCost.stop('power: a torque ask to whip_core (SetVehiclePower, with the crossing)', cost)
    if called and ok then asked[key] = multiplier end
end

--- Stop asking. The car is back to its own torque once nothing asks.
---@param key string
function PowerHandling.clear(key)
    prev[key] = nil
    if not asked[key] then return end
    asked[key] = nil
    Whip.call('ClearVehiclePower', key)
    if next(asked) == nil then current = nil end
end

--- A whip_core handling layer kept on the car this player drives: on when they take the wheel, off on
--- any other seat or out of the car. top_speed.lua, shift_time.lua.
---
--- By whip_core's seat events, not WatchVehicleData's driverOnly (client/tuning.lua): these layers go on every car
--- driven, not only on cars carrying some data, so there is no data to watch.
---@param layer string                      the layer's name
---@param label string                      names it in the console when whip_core refuses it
---@param spec fun(veh: number): table|nil  the layer for this car, or nil for none
---@param onDrive fun(veh: number|nil)|nil  told after every change of car (nil: not driving)
---@return table  { apply = fn(veh), refresh = fn() }: refresh re-reads the driven car (a setting changed)
function PowerHandling.driverLayer(layer, label, spec, onDrive)
    local on = nil   -- the car the layer is on

    local function clear()
        if not on then return end
        on = nil
        exports.whip_core:ClearVehicleHandlingLayer(layer)
    end

    local function apply(veh)
        local s = veh and veh ~= 0 and DoesEntityExist(veh) and spec(veh) or nil
        if not s then clear() return end
        local ok, why = exports.whip_core:SetVehicleHandlingLayer({ entity = veh }, layer, s)
        -- Sent twice when it scales: whip_core writes a scaled field only once it moves 5%, or when the
        -- same is asked twice running, so a small change (2 to 2.05) lands only on the repeat.
        if ok and s.scale then ok, why = exports.whip_core:SetVehicleHandlingLayer({ entity = veh }, layer, s) end
        if ok then on = veh return end
        on = nil
        print(('[whip_autos] %s: %s'):format(label, tostring(why)))
    end

    local function drive(veh)
        apply(veh)
        if onDrive then onDrive(veh) end
    end

    AddEventHandler('whip_core:vehicle:entered', function(d)
        if type(d) == 'table' then drive(d.seat == -1 and d.entity or nil) end
    end)
    AddEventHandler('whip_core:vehicle:exited', function() drive(nil) end)
    -- Once whip_core is ready: the car this player is already driving.
    Whip.register(function() on = nil; drive(AutosDrivenCar()) end)

    return { apply = apply, refresh = function() drive(AutosDrivenCar()) end }
end
