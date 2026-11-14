-- ============================================
-- whip_autos power — turbo (server)
-- ============================================
--
-- The boost stat and its gauge, and GTA's own turbo part for the sound. A turbo is sold at Whiplash in stages
-- (Config.Turbo.Stages: the most boost each makes, in psi) and kept as the car's turbo data (TUNING_TURBO_KEY, written
-- with the order: server/main.lua, or a Director car's look: server/look.lua). The boost stat follows that data here:
-- on the car while it has a stage, off when it has none. The client simulates boost from the stage
-- (client/power/turbo.lua); the stat's `live` block is what keeps its reports honest.
--
-- A car with a turbo from before the stages (a boost stat with no stage behind it, or GTA's own turbo part on its own)
-- gets the OLD_TURBO_PSI stage; the old turbo item and its wrench are retired (RegisterWithWhip). The worker threads below are our own
-- code, so they call whip_core through Whip.call.

local BOOST_IDLE = PowerTurbo.IDLE   -- a fitted turbo at rest (shared/power.lua)

--- The stage a car with a turbo from before the stages gets: 15 psi, close to the old turbo's +50% torque.
local OLD_TURBO_PSI = 15

--- The fastest climb the server believes, boost a second: the quickest stage's flat-out spool rate
--- (PowerTurbo.fastestRise) with a tenth to spare, so an honest driver is never clamped. Only rising is capped:
--- claiming less boost cheats nobody.
local function maxSpoolRate() return PowerTurbo.fastestRise / 0.9 end

-- ============================================
-- GTA's own turbo, for the sound
-- ============================================
--
-- A car with this turbo also gets GTA's turbo part (mod 18): it plays the spool whistle and the
-- blow-off for everyone near the car, and adds a little power on top of the turbo's own torque.
-- Set through the car's stored look (SetVehicleAppearance): whip puts that back over any client's
-- ToggleVehicleMod. A Whiplash order puts it on with the stage itself (server/main.lua); this covers every other way a
-- turbo comes and goes. Only a car carrying GTA_TURBO_NOTE (put on here) has it switched off here.

--- VehicleData key, owned by whip_autos.
local GTA_TURBO_NOTE = 'turbo_mod'

--- Make GTA's turbo part follow this turbo being fitted (`on`) or pulled.
---@param vehicleId number
---@param on boolean
local function followWithGtaTurbo(vehicleId, on)
    local noted = Whip.call('GetVehicleData', vehicleId, GTA_TURBO_NOTE) == true

    if not on then
        if not noted then return end   -- not ours to take away
        local ok, err = Whip.call('SetVehicleAppearance', vehicleId, { turbo = false })
        if not ok then
            print(('[whip_autos] could not switch GTA turbo off on vehicle %d: %s'):format(vehicleId, tostring(err)))
            return
        end
        Whip.call('ClearVehicleData', vehicleId, GTA_TURBO_NOTE)
        return
    end

    local v = Whip.call('GetVehicle', vehicleId)
    if not v then return end
    -- Already on: put on with a Whiplash stage (no note), or ours.
    if type(v.properties) == 'table' and v.properties.turbo == true then return end

    -- The note first: without it a pull would leave GTA's part on.
    if not noted then
        local ok, err = Whip.call('SetVehicleData', vehicleId, GTA_TURBO_NOTE, true)
        if not ok then
            print(('[whip_autos] could not note GTA turbo on vehicle %d: %s'):format(vehicleId, tostring(err)))
            return
        end
    end
    local ok, err = Whip.call('SetVehicleAppearance', vehicleId, { turbo = true })
    if not ok then
        print(('[whip_autos] could not switch GTA turbo on for vehicle %d: %s'):format(vehicleId, tostring(err)))
    end
end

--- [vehicleId] = the latest on/off asked for, while a worker is running for that car.
local gtaTurboWanted = {}

--- One worker per car, ending on the latest ask. Two overlapping switches (each waits on the database) could finish
--- in the wrong order and leave GTA's part on with no note.
---@param vehicleId number
---@param on boolean
local function queueGtaTurbo(vehicleId, on)
    local running = gtaTurboWanted[vehicleId] ~= nil
    gtaTurboWanted[vehicleId] = on
    if running then return end
    CreateThread(function()
        while true do
            local want = gtaTurboWanted[vehicleId]
            local ok, err = pcall(followWithGtaTurbo, vehicleId, want)
            if not ok then print(('[whip_autos] GTA turbo follow errored: %s'):format(tostring(err))) end
            if gtaTurboWanted[vehicleId] == want then
                gtaTurboWanted[vehicleId] = nil
                return
            end
        end
    end)
end

-- ============================================
-- The boost stat follows the turbo data
-- ============================================

--- On the car while it has a stage that is sold, off when it has none. A stage taken out of Config.Turbo.Stages stops
--- working (no boost, no gauge) but stays on the car, and works again if that stage is put back.
---@param vehicleId number
---@param data any  the car's turbo data, nil for none
local function followTurbo(vehicleId, data)
    local has = Whip.call('HasVehicleStat', vehicleId, 'boost') == true
    if TuningTurboStage(data) then
        if not has then
            local ok, err = Whip.call('SetVehicleStat', vehicleId, 'boost', BOOST_IDLE, 'turbo:fitted')
            if not ok then print(('[whip_autos] could not put the boost gauge on vehicle %d: %s'):format(vehicleId, tostring(err))) end
        end
    elseif has then
        local ok, err = Whip.call('ClearVehicleStat', vehicleId, 'boost')
        if not ok then print(('[whip_autos] could not take the boost gauge off vehicle %d: %s'):format(vehicleId, tostring(err))) end
    end
end

--- A car with a turbo from before the stages, and no stage yet: given OLD_TURBO_PSI. Its turbo data's change then puts
--- the boost stat on (followTurbo), if it is not on already.
---@param vehicleId number
---@param why string  for the console
local function giveOldTurboAStage(vehicleId, why)
    -- (Whip.call answers false, not nil, when it fails: then nothing is given.)
    if Whip.call('GetVehicleData', vehicleId, TUNING_TURBO_KEY) ~= nil then return end
    local ok, err = Whip.call('SetVehicleData', vehicleId, TUNING_TURBO_KEY, { psi = OLD_TURBO_PSI })
    if ok then
        print(('[whip_autos] vehicle %d had %s: it now has the %d psi turbo'):format(vehicleId, why, OLD_TURBO_PSI))
    else
        print(('[whip_autos] could not give vehicle %d its %d psi turbo: %s'):format(vehicleId, OLD_TURBO_PSI, tostring(err)))
    end
end

-- ============================================
-- Registration
-- ============================================

--- The boost stat. Declared again when the stages or spool times change, since its cap is worked out from them;
--- whip_core keeps every car's value through that.
---@return boolean ok
local function registerBoostStat()
    local ok, err = exports.whip_core:RegisterVehicleStat('boost', {
        default = BOOST_IDLE,
        min     = BOOST_IDLE,
        max     = PowerTurbo.MAX,

        -- The turbo being fitted survives a restart; the boost number does not, and comes back at idle.
        persist = 'presence',

        -- whip_core enforces it: the rate cap, the driver check, a per-car cursor.
        live = {
            maxRate  = maxSpoolRate(),
            -- How often other players' gauges update (the driver's reads the simulation). 0.25 s is
            -- whip_core's floor: its sender wakes four times a second.
            interval = 0.25,
        },

        -- Read in psi, as a car's boost gauge is: vacuum (-3) off the throttle, up to 30 at the top of the gauge
        -- (PowerTurbo.PSI_LOW..PSI_HIGH). A 15 psi turbo's full boost reads 15.
        display = { unit = 'psi', range = { PowerTurbo.PSI_LOW, PowerTurbo.PSI_HIGH } },

        hud = {
            label = 'Boost',
            -- No icon: the rev dial draws its own turbo glyph (whip_core html/js/vehicle-dial.js).
            color       = '#facc15',
            order       = 6,

            -- Shown because the car has a turbo: idle is 1, so showAboveZero would put a gauge on
            -- every car.
            showWhenPresent = true,
            noCritical      = true,   -- low boost is idle, not an emergency
        },
    })
    if not ok then print(('[whip_autos] could not register the boost stat: %s'):format(tostring(err))) end
    return ok
end

--- Everything this file declares to whip_core, once it is ready (Whip.register); declaring the same thing twice is
--- safe.
local function RegisterWithWhip()
    if not registerBoostStat() then return end

    -- GTA's part follows every way a turbo comes and goes (a stage bought or taken off, a Director look, an admin
    -- tool); `now` also walks the cars that already carry one. Live boost reports land here too, so anything but the
    -- stat arriving (`previous == nil`, as `now` passes it) or going returns at once. Off to a thread: this runs inside
    -- whip_core's stat write, and the appearance and data writes wait on the database.
    exports.whip_core:OnVehicleStatChange('boost', function(vehicleId, _, previous, cleared)
        if not cleared and previous ~= nil then return end
        queueGtaTurbo(vehicleId, not cleared)
        -- A boost stat with no stage behind it is a bolt-on turbo from before the stages: given one.
        if not cleared then
            CreateThread(function() giveOldTurboAStage(vehicleId, 'a bolted-on turbo') end)
        end
    end, { now = true })

    -- The boost stat follows the turbo data, and `now` brings every car that has a stage into line at start.
    exports.whip_core:OnVehicleDataChange(TUNING_TURBO_KEY, function(c)
        CreateThread(function() followTurbo(c.vehicleId, (not c.cleared) and c.value or nil) end)
    end, { table = true, now = true })

    -- The old turbo item and its wrench, both gone: a turbo is bought at Whiplash now. Every one players still have is
    -- taken out of their pockets, stashes, boots and off the ground, logged, not refunded. Kept retired here for good:
    -- a retirement holds only while this resource makes it, and a stash or a character not loaded since still has some.
    for item, why in pairs({ turbo = 'Turbos are sold at Whiplash now, in stages', wrench = 'The wrench is no longer used' }) do
        local retired, retireWhy = exports.whip_core:RetireItem(item, why)
        if not retired then print(('[whip_autos] could not retire the old %s item: %s'):format(item, tostring(retireWhy))) end
    end

    print('[whip_autos] turbo system loaded')
end

-- Runs once whip_core is ready, whichever of the two starts first.
Whip.register(RegisterWithWhip)

-- A car with GTA's on/off turbo part from before the stages (bought at Whiplash, no bolt-on): given a stage as it
-- comes into the world, before anyone drives it. (Only whip_core's announcement is believed.)
AddEventHandler('whip_core:vehicle:spawned', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    local vehicleId = tonumber(e.vehicleId)
    if not vehicleId then return end
    CreateThread(function()
        local v = Whip.call('GetVehicle', vehicleId)
        if not v or type(v.properties) ~= 'table' or v.properties.turbo ~= true then return end
        -- GTA's part put on by a bolt-on turbo carries the note; that car is given its stage by the boost stat above.
        if Whip.call('GetVehicleData', vehicleId, GTA_TURBO_NOTE) == true then return end
        giveOldTurboAStage(vehicleId, "GTA's turbo part from Whiplash")
    end)
end)

-- New stages or spool times in config or /whip → Settings move the cap with them (shared/power.lua has read them).
Whip.onConfigChanged('Turbo', function()
    if GetResourceState('whip_core') == 'started' then registerBoostStat() end
end)
