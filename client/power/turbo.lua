-- ============================================
-- whip_autos power — turbo (client)
-- ============================================
--
-- The boost simulation while this player drives a car with a turbo. A turbo is a stage bought at Whiplash (the car's
-- turbo data, TUNING_TURBO_KEY: { psi }), and each stage has its own full boost, spool time and torque
-- (PowerTurbo.stage, from Config.Turbo): a 5 psi turbo builds in about a second, a 30 psi one in five, for more power.
-- Boost is asked of PowerHandling as torque only (client/power/handling.lua), so top speed is the physics'. The
-- throttle (load) sets the target; revs only set how fast it spools, so load alone builds boost, just slower. Lifting
-- off dumps it, easing off trims it, a gear change purges part.

-- The numbers to tune (the stages, torque per psi, spool times, how much a gear change dumps) are Config.Turbo, read
-- through PowerTurbo (shared/power.lua): the server's cap on boost follows the same numbers. The ones below shape how
-- it feels.
local BOOST_MAX  = PowerTurbo.MAX
local BOOST_IDLE = PowerTurbo.IDLE

--- Spool rate: the stage's spoolPeak × the throttle × (SPOOL_FLOOR + the rest × revs²), GTA rpm being
--- 0.2 at idle and 1.0 at the limiter. So about six times slower at idle than at the limiter.
local SPOOL_FLOOR = 0.12

--- Lifting off: the blow-off valve dumps the lot in a third of a second.
local BLOWOFF_RATE = BOOST_MAX / 0.3

--- Easing off (throttle down, but less): the wastegate trims boost to the new target.
local SETTLE_RATE = BOOST_MAX / 1.0

--- A foot this far down or less is off the throttle.
local THROTTLE_OFF = 0.05

--- Shift length is measured, not taken from the clutch (GTA's clutch time is far longer than the car
--- really shifts): the next shift the same way on this car purges over the last one's time. The first
--- each way uses the guess, and takes the rest of its share if it ends early. Clamped to 0.1..5 s.
local SHIFT_SECONDS_GUESS = 0.4
local SHIFT_SECONDS_MIN, SHIFT_SECONDS_MAX = 0.1, 5.0

--- Simulation cadence in ms (the watcher's `interval`): eight times a second. Each tick is up to two crossings between
--- resources (whip_core into this, the torque ask back), about 20 KB of FiveM's own work a tick, so not faster. Slower
--- lags the pedal: at 150 the delay was felt in the car once, and five a second (200) was felt too (Josh, 11 Nov).
--- The integration runs on `dt`, real elapsed time (whip_core clamps only a stall: 0.25 s, or twice the interval).
local TICK_MS = 125

--- How often the car's stage is read again while driving, in ms: a stage bought or changed at Whiplash while in the
--- car takes over this soon. (Read on every tick, it would be an export crossing on every tick.)
local STAGE_READ_MS = 2000

--- How far boost must move before the gauge is told (1% of the bar). whip_core repaints the capsule on
--- any change, and an analog trigger never lets boost settle. Idle and full skip it, so they are exact.
local BOOST_DISPLAY_DEADBAND = 1.0

-- ============================================
-- The simulation
-- ============================================
-- WatchVehicleStat drives it: onStart when this player starts driving a car with a turbo, whileHeld
-- every TICK_MS while they do, onStop when they stop (out of the car, turbo taken off, car gone).

--- Live boost for the car being driven, unrounded. The server only sees it rounded.
local boost = BOOST_IDLE

--- What the gauge was last given (displayReading).
local shownBoost = BOOST_IDLE

--- The level last reported to whip_core (what the server holds); -1 makes the next tick report.
local lastSentLevel = -1

--- The level at rest. simulate skips ticks only once this has been reported.
local IDLE_LEVEL = math.floor(BOOST_IDLE + 0.5)

--- This car's stage (PowerTurbo.stage) and when it was last read; nil when it has none that is sold.
local stage, stageReadAt = nil, -STAGE_READ_MS

--- The shift being watched: the gear last seen, whether a shift is under way, and its purge: rate
--- (boost units a second), starting boost, share it must take, direction, and time so far.
local lastGear   = nil
local inShift    = false
local shiftVent  = 0.0
local shiftFrom  = BOOST_IDLE
local shiftLoss  = 0.0
local shiftUp    = true
local shiftTimer = 0.0

--- How long this car's last shift each way lasted, in seconds; nil until one is seen.
local shiftSeen = { up = nil, down = nil }

--- Back to rest, for a new car or none. lastSentLevel = -1 so the first tick on the next car reports
--- idle instead of taking simulate's early-out, and nobody keeps seeing the last driver's boost.
local function reset()
    boost, shownBoost = BOOST_IDLE, BOOST_IDLE
    lastSentLevel = -1
    lastGear, inShift = nil, false
    shiftSeen.up, shiftSeen.down = nil, nil
    stage, stageReadAt = nil, -STAGE_READ_MS
end

--- The car's stage, read again every STAGE_READ_MS. `{ entity = veh }`: a bare number is a vehicleId on whip's exports.
local function stageOf(veh)
    local now = GetGameTimer()
    if now - stageReadAt >= STAGE_READ_MS then
        stageReadAt = now
        local data = exports.whip_core:GetVehicleData({ entity = veh }, TUNING_TURBO_KEY)   -- (in whip_core's watcher)
        stage = TuningTurboStage(data)
    end
    return stage
end

--- The torque multiplier a boost level is worth on this stage: 1.0 at idle, 1 + its gain at its full boost.
---@param s table  the stage
---@param level number IDLE..its top
local function torqueFor(s, level)
    if s.top <= BOOST_IDLE then return 1.0 end
    return 1.0 + s.gain * math.max(0, level - BOOST_IDLE) / (s.top - BOOST_IDLE)
end

--- Is a gear change under way? GTA names the gear it is changing to while it changes (current ~= next);
--- a shift shorter than a tick shows as the gear number having moved. Reverse (0) does not count.
--- While the gearbox computer drives (gearbox.lua), GTA's gear stays 1: its own changes are asked of it.
---@return boolean shifting, boolean up
local function gearChange(veh)
    local computerShifting, computerUp = nil, false
    if GearboxShift then computerShifting, computerUp = GearboxShift(veh) end
    if computerShifting ~= nil then
        lastGear = nil
        return computerShifting, computerUp
    end
    local gear, nextGear = GetVehicleCurrentGear(veh), GetVehicleNextGear(veh)
    local was = lastGear
    lastGear = gear
    if gear < 1 or nextGear < 1 or (was ~= nil and was < 1) then return false, false end
    -- The number moving counts only for a shift not already seen under way: one that was seen has
    -- just finished, and must not purge a tick longer.
    local moved = was ~= nil and gear ~= was and not inShift
    local up = nextGear > gear or (nextGear == gear and moved and gear > was)
    return gear ~= nextGear or moved, up
end

--- The purge for a shift starting now: its rate (boost units a second) and the share it takes, a
--- random share (PowerTurbo.lossMin..lossMax) of the boost above idle, over this car's last shift that way.
---@return number vent, number loss
local function shiftPurgeRate(up)
    local loss = PowerTurbo.lossMin + math.random() * (PowerTurbo.lossMax - PowerTurbo.lossMin)
    local seconds = shiftSeen[up and 'up' or 'down'] or SHIFT_SECONDS_GUESS
    seconds = math.max(SHIFT_SECONDS_MIN, math.min(SHIFT_SECONDS_MAX, seconds))
    return (boost - BOOST_IDLE) * loss / seconds, loss
end

--- The least boost this shift may leave: PowerTurbo.lossMax gone, however long it runs.
local function shiftFloor()
    return BOOST_IDLE + (shiftFrom - BOOST_IDLE) * (1.0 - PowerTurbo.lossMax)
end

--- Is another player in this car? Only a passenger reads the server's copy of boost (the driver's own
--- gauge reads `boost`, displayReading), so it is reported only while one sits there: each report is a
--- server event. Alone, the server's copy rests at idle.
local function othersInside(veh)
    local me = PlayerPedId()
    for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and ped ~= me and IsPedAPlayer(ped) then return true end
    end
    return false
end

--- One step of boost.
---@param dt number  real seconds since the last tick, clamped by whip_core
local function simulate(veh, dt)
    -- No stage that is sold (taken out of Config.Turbo.Stages): no boost and no torque, the gauge at rest.
    local s = stageOf(veh)
    if not s then
        if boost > BOOST_IDLE or lastSentLevel ~= IDLE_LEVEL then
            boost = BOOST_IDLE
            PowerHandling.set('turbo', veh, 1.0)
            lastSentLevel = IDLE_LEVEL
            exports.whip_core:ReportVehicleStat({ entity = veh }, 'boost', IDLE_LEVEL)
        end
        return
    end

    -- The control, not a vehicle native: this runs only for the local driver. `dt`, not GetFrameTime:
    -- that is one rendered frame, and would spool ~12x too slowly at this cadence.
    local throttle = GetControlNormal(0, 71)   -- INPUT_VEH_ACCELERATE

    -- At rest, foot off, idle already reported: nothing would change.
    if boost <= BOOST_IDLE and throttle <= 0.01 and lastSentLevel == IDLE_LEVEL then
        lastGear, inShift = nil, false   -- the gear is not read at rest, so the next read is no shift
        return
    end

    local shifting, up = gearChange(veh)
    if shifting and not inShift then
        shiftFrom, shiftUp, shiftTimer = boost, up, 0.0
        shiftVent, shiftLoss = 0.0, 0.0
        if boost > BOOST_IDLE then shiftVent, shiftLoss = shiftPurgeRate(up) end
    elseif inShift and not shifting then
        -- Over: timed for the next shift this way, and its share taken in full if it ended before the
        -- purge got there (the first shift each way, on the guess).
        shiftSeen[shiftUp and 'up' or 'down'] = math.max(SHIFT_SECONDS_MIN, math.min(SHIFT_SECONDS_MAX, shiftTimer))
        if shiftVent > 0 then
            local owed = BOOST_IDLE + (shiftFrom - BOOST_IDLE) * (1.0 - shiftLoss)
            if boost > owed then boost = owed end
        end
    end
    if shifting then shiftTimer = shiftTimer + dt end
    inShift = shifting

    if throttle <= THROTTLE_OFF or not GetIsVehicleEngineRunning(veh) then
        boost = boost - BLOWOFF_RATE * dt                             -- the blow-off valve
    elseif shifting then
        if shiftVent > 0 then boost = math.max(shiftFloor(), boost - shiftVent * dt) end
    else
        -- The load sets the target, up to this stage's full boost; the revs and the load set how fast it spools
        -- (turbo lag), at this stage's rate: a bigger turbo builds slower.
        local rpm = GetVehicleCurrentRpm(veh)
        local target = BOOST_IDLE + (s.top - BOOST_IDLE) * throttle
        if boost < target then
            local rate = s.spoolPeak * throttle * (SPOOL_FLOOR + (1.0 - SPOOL_FLOOR) * rpm * rpm)
            boost = math.min(target, boost + rate * dt)
        elseif boost > target then
            boost = math.max(target, boost - SETTLE_RATE * dt)        -- the wastegate trims it
        end
    end

    if boost < BOOST_IDLE then boost = BOOST_IDLE end
    if boost > s.top then boost = s.top end

    -- Every tick, unrounded: PowerHandling.set skips asks that moved too little for that key.
    PowerHandling.set('turbo', veh, torqueFor(s, boost))

    -- ReportVehicleStat only stores the value; whip_core sends the newest at the stat's live interval.
    -- With nobody else in the car it is idle (sent once), so a passenger getting in is sent the real
    -- level at once and one getting out puts it back to rest.
    local level = othersInside(veh) and math.floor(boost + 0.5) or IDLE_LEVEL
    if level ~= lastSentLevel then
        lastSentLevel = level
        exports.whip_core:ReportVehicleStat({ entity = veh }, 'boost', level)
    end
end

--- The driver's gauge reading, returned from whileHeld: whip_core draws it on this player's capsule
--- instead of waiting for the server's copy. Passengers see the replicated stat.
local function displayReading()
    local top = stage and stage.top or BOOST_MAX
    if boost <= BOOST_IDLE or boost >= top
        or math.abs(boost - shownBoost) >= BOOST_DISPLAY_DEADBAND then
        shownBoost = boost
    end
    return shownBoost
end

--- The watcher lives in whip_core's tables, so it is declared once whip_core is ready (Whip.register).
local function RegisterWithWhip()
    exports.whip_core:WatchVehicleStat('boost', {
        onStart = function()
            reset()
        end,

        -- Returns the gauge reading. WhipCost times this side only; whip_core times the crossing.
        whileHeld = function(entity, _, dt)
            local cost = WhipCost.start()
            simulate(entity, dt)
            WhipCost.stop('turbo: whileHeld (the simulation, without the crossing)', cost)
            return displayReading()
        end,

        -- Out of the car, handed over, turbo taken off, car gone.
        onStop = function()
            PowerHandling.clear('turbo')
            reset()
        end,

        interval   = TICK_MS,
        driverOnly = true,   -- the throttle read is this player's, and only the driver sets the torque
    })
end

-- No onResourceStop: whip_core sweeps a stopped resource's torque asks.

-- Runs once whip_core is ready, whichever of the two starts first.
Whip.register(RegisterWithWhip)
