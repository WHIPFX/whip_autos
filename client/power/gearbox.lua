-- The gearbox computer (client). It changes gear the way a real automatic does, from how the pedal is used: a light
-- foot changes up early and lets the revs fall low, a foot flat to the floor gets GTA's own change at peak power.
--   * Aggression, 0 to 1, builds while the pedal is held down (Config.Gearbox.RiseSeconds) and fades slowly
--     (FallSeconds).
--   * Change up past the up point: EcoUpRpm for a light foot, rising to the limiter.
--   * Change down below the down point, set by aggression: foot on, EcoDownRpm up to SportDownRpm; foot off,
--     CoastDownRpm up to the foot-on point. A burst of throttle holds the gear until aggression reaches Kickdown.
--   * A change down under throttle only when the revs would land clear of the top KickdownRoom of the range.
--   * After a change up the gear is held UP_HOLD_MS, so it does not hunt.
--   * GTA is given one gear (SetVehicleHighGear 1) and the computer sets that gear's ratio to the wanted gear's
--     (SetVehicleGearRatio): overruling GTA's own box does not work, it puts a gear back within 50 ms.
--   * A change cuts torque with the old gear in, switches part way, then restores torque, over the time of GTA's own
--     change on this car (else its clutch time, scaled per kind by shift_time.lua). turbo.lua purges boost through it.
--   * The rev dial is told the gear (SetVehicleDialGear).
--   * From HandsOff aggression up it hands the car back to GTA's own box.
--   * Each change is checked: the revs move with the ratio. When they do not (twice), the computer stays off, said in F8.
-- Controller only, for now (a trigger gives pedal depth). Driver only, in the vehicles power works on (PowerClasses).
-- Ten times a second while cruising, every frame while a change is under way. GTA's revs run 0.2 at idle to 1.0.

local G = {}   -- Config.Gearbox, read within its page limits (shared/settings.lua): readConfig

--- A change down only when the revs in the lower gear stay this far under the up point (no hunting
--- between two).
local HYSTERESIS = 0.05

--- A change up only when the revs in the next gear stay this far above EcoDownRpm: never into a gear
--- that would drop the engine to idle.
local LUG_MARGIN = 0.02

--- After a change, the next is not decided for this long.
local SETTLE_MS = 400

--- The pedal this far down or less is off.
local PEDAL_OFF = 0.05

--- The pedal this far above the aggression: it is building, and the gear is held (no change down but
--- the kickdown).
local BUILDING = 0.05

--- After a change up, no change down for this long (but a kickdown, or the revs under CoastDownRpm).
local UP_HOLD_MS = 2000

--- A kickdown, done, is ready again once the aggression has fallen this far below Kickdown.
local KICK_REARM = 0.1

--- How quickly the measured climb of the revs follows them (seconds), and how long after a change of
--- ours it is not measured (the revs are moving to the new ratio).
local RISE_SMOOTH, RISE_SKIP_MS = 0.3, 200

--- Slower than this (m/s) the car is all but stopped: 1st, ready to pull away.
local STOP_SPEED = 1.5

--- A take or a change is checked this long after: the revs should have moved with the ratio. Slower than
--- VERIFY_SPEED (m/s) the revs say little (the clutch slips): not checked, and not taken under VERIFY_RPM.
local VERIFY_MS, VERIFY_SLACK, VERIFY_SPEED, VERIFY_RPM = 300, 0.06, 3.0, 0.3
local MISSES_MAX = 2
local IDLE_RPM = 0.2

--- GTA's box settled: its clutch at least this far in, and its gear unchanged this long. Before that its revs are a
--- gear change's, not the car's, so a take then is not checked, nor is a change while the clutch is out.
local CLUTCH_IN, SETTLED_MS = 0.95, 250

--- Flat out: GTA's box until the pedal comes up this far below HandsOff. Then the computer at once, before
--- GTA's own lift-off change down.
local HANDS_BACK = 0.1

--- A change: torque cut to SHIFT_DIP at once with the old gear still in; at SWITCH_AT of the way the new gear goes in;
--- then torque comes back. How long: GTA's own change as last timed on this car, else its clutch time,
--- CLUTCH_SECONDS ÷ fClutchChangeRateScaleUp/DownShift. Held to SHIFT_MIN..SHIFT_MAX seconds.
local SHIFT_DIP = 0.05
local SWITCH_AT = 0.4
local CLUTCH_SECONDS = 0.9
local SHIFT_MIN, SHIFT_MAX = 0.15, 3.0

--- How often the one-gear setup is looked at: a tuning change can rebuild GTA's gearbox under it.
local GUARD_MS = 500

--- How often a driver with no controller (or the switch off) is looked at again.
local IDLE_MS = 500

--- How often it looks while cruising (ten times a second). Every frame only while something quick is happening
--- (quick(), below).
local CRUISE_MS = 100

local function readConfig()
    local c = type(Config.Gearbox) == 'table' and Config.Gearbox or {}
    local function n(k, lo, hi, d)
        local v = tonumber(c[k])
        if not v then return d end
        return math.max(lo, math.min(hi, v))
    end
    G.enabled   = c.Enabled ~= false
    G.ecoUp     = n('EcoUpRpm', 0.25, 0.95, 0.30)
    G.ecoDown   = n('EcoDownRpm', 0.21, 0.6, 0.21)
    G.sportDown = n('SportDownRpm', 0.21, 0.9, 0.55)
    G.coastDown = n('CoastDownRpm', 0.21, 0.6, 0.21)
    G.rise      = n('RiseSeconds', 0.05, 5, 1.0)
    G.fall      = n('FallSeconds', 0.1, 30, 4.0)
    G.kickdown  = n('Kickdown', 0.5, 1, 0.8)
    G.room      = n('KickdownRoom', 0, 0.5, 0.10)
    G.handsOff  = n('HandsOff', 0.5, 1, 0.92)
end
readConfig()
Whip.onConfigChanged('Gearbox', readConfig)

-- The debug readout: what it decides, in F8. Off; true here turns it on.

local debugOn = false
local function say(fmt, ...)
    if debugOn then print(('[whip_autos gearbox] ' .. fmt):format(...)) end
end

-- The car's gears

--- Whether the game has the gear natives (FiveM's own). Missing on a build: the computer stays off,
--- said once.
local gearsOk = type(GetVehicleCurrentGear) == 'function' and type(GetVehicleNextGear) == 'function'
    and type(SetVehicleNextGear) == 'function' and type(SetVehicleCurrentGear) == 'function'
    and type(GetVehicleHighGear) == 'function' and type(SetVehicleHighGear) == 'function'
    and type(GetVehicleGearRatio) == 'function' and type(SetVehicleGearRatio) == 'function'
if not gearsOk then print('[whip_autos] the gearbox computer is off: this game has no gear natives') end

--- Is GTA's clutch out (a change of its own still biting)? False when the game cannot say.
local clutchOk = type(GetVehicleClutch) == 'function'
local function clutchOut(veh)
    if not clutchOk then return false end
    local c = GetVehicleClutch(veh)
    return type(c) == 'number' and c < CLUTCH_IN
end

---@class WhipAutosGearCar
---@field veh number
---@field high number
---@field ratio number[]
---@field want number
---@field applied number|nil

--- The car the computer drives, on one gear: { veh, high, ratio = { [gear] = GTA's ratio }, want, applied }. `high`
--- and `ratio` are the car's own, put back when handed back; `want` is the gear driven, `applied` the gear whose ratio
--- gear 1 has now. nil: GTA's own box.
---@type WhipAutosGearCar|nil
local car = nil

--- The car's gearbox as GTA has it: its gears and their ratios. nil, why when it cannot be driven.
local function readGearbox(veh, high)
    high = high or GetVehicleHighGear(veh)
    if type(high) ~= 'number' or high < 2 then return nil, 'it has one gear' end
    local ratio = {}
    for g = 1, high do
        local r = GetVehicleGearRatio(veh, g)
        if type(r) ~= 'number' or r <= 0 then return nil, ('gear %d has no ratio'):format(g) end
        ratio[g] = r
    end
    return { high = high, ratio = ratio }
end

--- The rev dial shows `gear` (nil: the game's again).
local function showGear(veh, gear)
    if GetResourceState('whip_core') ~= 'started' then return end
    pcall(function() exports.whip_core:SetVehicleDialGear({ entity = veh }, gear) end)
end

--- Gear 1 gets the ratio of the gear wanted, if it has not already.
local function applyRatio()
    ---@cast car -nil
    if car.applied == car.want then return end
    SetVehicleGearRatio(car.veh, 1, car.ratio[car.want] + 0.0)
    car.applied = car.want
end

-- Deciding

---@class WhipAutosGearShift
---@field up boolean
---@field from number
---@field to number
---@field at number
---@field seconds number
---@field switchAt number
---@field switched boolean

local aggression = 0.0
local kickArmed = true -- the next time the aggression builds to Kickdown, a kickdown
local handsOff = false
local changedAt = -1e9 -- when the gear last changed
local upAt = -1e9      -- when it last changed up
local check = nil      -- a change being checked: { from, to, factor, rpm, speed, at }: did the revs move with it?
local missed = 0       -- changes running whose revs did not move
local off = false      -- this car does not drive by its ratio: the computer stays off it
---@type WhipAutosGearShift|nil
local shift = nil      -- a change under way: { up, from, to, at, seconds, switchAt, switched }
local seen = {}        -- GTA's own changes on this car, timed: seen.up / seen.down = { seconds, switchAt }
local gtaShift = nil   -- one of GTA's own under way, being timed: { at, gear, up, switchedAt }
local guardAt = -1e9
local gtaGear, gtaNext, gtaSince = -1, -1, -1e9   -- GTA's gear and next as last seen, and since when
local recheck = false  -- a check failed: the next take waits for GTA's box to settle, so it is checked
local rise, lastRpm = 0.0, nil   -- how fast the revs are climbing in this gear (a second, smoothed), and last frame's
local lastSpeed = 0.0  -- m/s at the last look

--- The up point: the pedal counts at once, the aggression once built. Cubed, so it stays near EcoUpRpm through a
--- calm drive and climbs to the limiter driven hard.
local function upRpm(pedal)
    local level = math.max(pedal, aggression)
    return G.ecoUp + (1.0 - G.ecoUp) * level * level * level
end

--- The down point, from the aggression alone: foot on, EcoDownRpm calm to SportDownRpm hard; foot off,
--- CoastDownRpm calm (the gear held) to the foot-on point hard (engine braking).
local function downRpm(pedal)
    local a2 = aggression * aggression
    local on = G.ecoDown + (G.sportDown - G.ecoDown) * a2
    if pedal > PEDAL_OFF then return on end
    -- By the aggression itself, not squared: it fades while the car slows, and braking into a corner
    -- after a hard run should still change down.
    return G.coastDown + (math.max(on, G.coastDown) - G.coastDown) * aggression
end

--- The torque cut of a change, gone.
local function endShift()
    if shift then PowerHandling.clear('gearbox') end
    shift = nil
end

--- The car back to GTA's own box, as it was. Safe at any time, with or without a car.
local function giveBack(why)
    if not car then return end
    local c = car
    car = nil
    endShift()
    check = nil
    if DoesEntityExist(c.veh) then
        pcall(function()
            SetVehicleGearRatio(c.veh, 1, c.ratio[1] + 0.0)
            SetVehicleHighGear(c.veh, c.high)
            -- Going forward, from the gear it was really in: GTA's box goes on from there.
            if GetVehicleCurrentGear(c.veh) >= 1 then
                SetVehicleNextGear(c.veh, c.want)
                SetVehicleCurrentGear(c.veh, c.want)
            end
        end)
        showGear(c.veh, nil)
    end
    say('GTA\'s own box again (%s)', why)
end

local function reset()
    giveBack('a new start')
    aggression, kickArmed, handsOff = 0.0, true, false
    changedAt, upAt, check, missed, off, shift, guardAt = -1e9, -1e9, nil, 0, false, nil, -1e9
    gtaGear, gtaNext, gtaSince, recheck = -1, -1, -1e9, false
    rise, lastRpm, lastSpeed = 0.0, nil, 0.0
    seen, gtaShift = {}, nil
end

--- Take the car from GTA's box, in the gear it is in. False when it cannot be driven (said once; the
--- computer stays off it). `settled`: GTA's box was not changing gear, so the take can be checked.
local function take(veh, gear, rpm, speed, now, settled)
    local box, why = readGearbox(veh)
    if not box then
        off = true
        say('not driving this car: %s', why)
        return false
    end
    car = { veh = veh, high = box.high, ratio = box.ratio, want = math.max(1, math.min(box.high, gear)), applied = nil }
    SetVehicleHighGear(veh, 1)
    SetVehicleNextGear(veh, 1)
    SetVehicleCurrentGear(veh, 1)
    applyRatio()
    showGear(veh, car.want)
    changedAt = now
    rise, lastRpm = 0.0, nil
    check = settled and { from = car.want, to = car.want, factor = 1.0, rpm = rpm, speed = speed, at = now } or nil
    say('driving it, from %d (of %d)%s', car.want, car.high, settled and '' or ' (GTA was still changing gear: not checked)')
    return true
end

--- How long a change takes on this car, and how far through it the new gear goes in.
---@return number seconds, number switchAt  0..1
local function shiftTiming(veh, up)
    local t = seen[up and 'up' or 'down']
    if t then return t.seconds, t.switchAt end
    local rate = GetVehicleHandlingFloat(veh, 'CHandlingData', up and 'fClutchChangeRateScaleUpShift' or 'fClutchChangeRateScaleDownShift')
    local seconds = (type(rate) == 'number' and rate > 0) and CLUTCH_SECONDS / rate or 0.5
    return math.max(SHIFT_MIN, math.min(SHIFT_MAX, seconds)), SWITCH_AT
end

--- Time GTA's own changes while its box drives (flat out): from its clutch going out to back in. Starting the car
--- moving is not one.
local function timeGtaShift(veh, gear, nextGear, now)
    local out = gear ~= nextGear or clutchOut(veh)
    if not gtaShift then
        if out and gear >= 1 and nextGear >= 1 then gtaShift = { at = now, gear = gear, up = nextGear > gear } end
        return
    end
    if not gtaShift.switchedAt and gear ~= gtaShift.gear and gear >= 1 then
        gtaShift.switchedAt, gtaShift.up = now, gear > gtaShift.gear
    end
    if out then return end
    local s = gtaShift
    gtaShift = nil
    if not s.switchedAt then return end
    local seconds = (now - s.at) / 1000.0
    if seconds < SHIFT_MIN or seconds > SHIFT_MAX then return end
    local key = s.up and 'up' or 'down'
    seen[key] = { seconds = seconds, switchAt = (s.switchedAt - s.at) / (now - s.at) }
    say('GTA\'s own change %s timed: %.2f s, the gear in at %.0f%% (the computer\'s go the same)',
        key, seconds, seen[key].switchAt * 100)
end

--- Where a change down from gear `from` to `to` would leave the revs once it is done: they go on
--- climbing while it changes (this car's down change time, at the climb seen in this gear).
local function landing(veh, rpm, from, to)
    ---@cast car -nil
    return (rpm + math.max(0.0, rise) * (shiftTiming(veh, false))) * car.ratio[to] / car.ratio[from]
end

--- The highest a change down under throttle may land: the top KickdownRoom of the rev range is left clear, or it
--- would hit the limiter and change straight back up.
local function roomTop() return 1.0 - G.room * (1.0 - IDLE_RPM) end

--- Change to gear `to`, for `why`: the torque cut now, the new gear in part way (changeStep).
local function change(to, now, _, _, why, ...)
    ---@cast car -nil
    say(why, ...)
    local from = car.want
    car.want, changedAt = to, now
    local up = to > from
    local seconds, switchAt = shiftTiming(car.veh, up)
    shift = { up = up, from = from, to = to, at = now, seconds = seconds, switchAt = switchAt, switched = false }
end

--- A change under way, this frame: the new gear goes in at its point (and is checked from there), and
--- the torque, cut until then, comes back over the rest.
local function changeStep(veh, now, rpm, speed)
    ---@cast car -nil
    ---@cast shift -nil
    local t = (now - shift.at) / 1000.0 / shift.seconds
    if not shift.switched and t >= shift.switchAt then
        shift.switched = true
        applyRatio()
        showGear(veh, car.want)
        local factor = car.ratio[shift.to] / car.ratio[shift.from]
        check = { from = shift.from, to = shift.to, factor = factor, rpm = rpm, speed = speed, at = now }
        changedAt = now
        -- The climb goes on in the new gear, scaled by it (the revs per mph move with the ratio).
        rise, lastRpm = rise * factor, nil
    end
    if t >= 1.0 then
        endShift()
    elseif not shift.switched then
        PowerHandling.set('gearbox', veh, SHIFT_DIP)
    else
        PowerHandling.set('gearbox', veh, SHIFT_DIP + (1.0 - SHIFT_DIP) * (t - shift.switchAt) / math.max(0.01, 1.0 - shift.switchAt))
    end
end

--- The one-gear setup still as it was left? A tuning change (a swap's gear count, a top speed commit)
--- can rebuild GTA's gearbox: read it again as the car's own, and drive it again.
local function guard(veh)
    ---@cast car -nil
    local high = GetVehicleHighGear(veh)
    local r1 = GetVehicleGearRatio(veh, 1)
    local ours = type(r1) == 'number' and math.abs(r1 - car.ratio[car.applied or 1]) < 0.0005
    if high == 1 and ours then return true end
    -- Our ratio still in gear 1 means only the gear count moved: gear 1's own ratio is the one kept.
    local box, why = readGearbox(veh, high ~= 1 and high or car.high)
    if box and ours then box.ratio[1] = car.ratio[1] end
    if not box then
        giveBack('its gearbox changed: ' .. why)
        off = true
        return false
    end
    car.high, car.ratio, car.applied = box.high, box.ratio, nil
    car.want = math.min(car.want, car.high)
    SetVehicleHighGear(veh, 1)
    applyRatio()
    say('its gearbox was rebuilt (a tuning change?): driving it again, %d gears', car.high)
    return true
end

--- One frame of driving.
---@param veh number
---@param now number  ms
---@param dt number   seconds
local function frame(veh, now, dt)
    local pedal = GetControlNormal(0, 71)   -- INPUT_VEH_ACCELERATE: the trigger, 0 to 1

    -- How hard: built while the pedal is down, slow to fade.
    local rate = pedal > aggression and G.rise or G.fall
    -- Exact for any gap between looks (a frame, or CRUISE_MS): the same build whatever the cadence.
    aggression = aggression + (pedal - aggression) * (1.0 - math.exp(-dt / rate))

    -- Kickdown: the aggression built up to it (a burst of throttle that lifts before then changes nothing).
    local kick = false
    if kickArmed and aggression >= G.kickdown then
        kick, kickArmed = true, false
    elseif not kickArmed and aggression < G.kickdown - KICK_REARM then
        kickArmed = true
    end

    local gear, nextGear = GetVehicleCurrentGear(veh), GetVehicleNextGear(veh)
    local rpm = GetVehicleCurrentRpm(veh)
    local speed = GetEntitySpeed(veh)
    lastSpeed = speed
    if gear ~= gtaGear or nextGear ~= gtaNext then gtaGear, gtaNext, gtaSince = gear, nextGear, now end
    if car then gtaShift = nil else timeGtaShift(veh, gear, nextGear, now) end

    if off then return end

    -- Flat out (not the kickdown's own frame: it picks the gear first): GTA's own box, until the foot
    -- comes up off the floor.
    local nowHandsOff = aggression >= G.handsOff and pedal >= G.handsOff - HANDS_BACK
    if nowHandsOff ~= handsOff then
        handsOff = nowHandsOff
        say(handsOff and 'flat out (aggression %.2f)' or 'off the floor (aggression %.2f, pedal %.2f)', aggression, pedal)
    end
    if handsOff and not kick then
        giveBack('flat out')
        return
    end

    if not car then
        -- Take it going forward, not between gears, and fast enough for the revs to show it worked. Taken at once,
        -- before GTA's box changes down; checked only when GTA's box had settled.
        if gear < 1 or gear ~= nextGear or speed < VERIFY_SPEED or rpm < VERIFY_RPM then return end
        local settled = now - gtaSince >= SETTLED_MS and not clutchOut(veh)
        if recheck and not settled then return end   -- after a check that failed, only a take that can be checked
        recheck = false
        if not take(veh, gear, rpm, speed, now, settled) then return end
    end
    ---@cast car -nil -- driving it now (or take() above would have returned)

    if now - guardAt >= GUARD_MS then
        guardAt = now
        if not guard(veh) then return end
    end

    -- A change under way: the new gear in at its point, the torque back over the rest.
    if shift then changeStep(veh, now, rpm, speed) end

    -- Reversing: GTA's reverse gear, the computer's 1st ready for going forward again.
    if gear < 1 then
        endShift()
        if car.want ~= 1 then
            car.want = 1
            applyRatio()
            showGear(veh, 1)
        end
        check = nil
        return
    end
    if gear ~= 1 or nextGear ~= 1 then
        SetVehicleNextGear(veh, 1)
        SetVehicleCurrentGear(veh, 1)
    end

    -- A take or a change, checked: the revs moved with the ratio. If not, back to GTA's box; twice running means this
    -- game does not drive by the ratio, and the car stays GTA's.
    if check and now - check.at >= VERIFY_MS then
        local c = check
        check = nil
        if speed >= VERIFY_SPEED and c.speed >= VERIFY_SPEED and not clutchOut(veh) then
            -- The revs above idle go with speed × ratio: where they would be had nothing changed, and
            -- where the new ratio puts them.
            local sr = speed / c.speed
            local same = IDLE_RPM + (c.rpm - IDLE_RPM) * sr
            local moved = math.min(1.0, IDLE_RPM + (c.rpm - IDLE_RPM) * c.factor * sr)
            local bad
            if c.factor == 1.0 then
                bad = math.abs(rpm - same) > math.max(VERIFY_SLACK, 0.25 * (c.rpm - IDLE_RPM))
            else
                -- Only when the two are far enough apart to tell: closer to unchanged than to moved.
                bad = math.abs(moved - same) >= VERIFY_SLACK and math.abs(rpm - same) < math.abs(rpm - moved)
            end
            if bad then
                missed = missed + 1
                say('the revs did not follow %d -> %d (%.2f; %.2f expected, %.2f had it not changed)', c.from, c.to, rpm, moved, same)
                giveBack('the revs did not follow')
                recheck = true
                if missed >= MISSES_MAX then
                    off = true
                    print('[whip_autos] the gearbox computer is off for this car: the revs did not follow its gear')
                end
                return
            end
            missed = 0
        end
    end

    -- How fast the revs climb in this gear: not while a change of ours moves them to the new ratio.
    if lastRpm and now - changedAt >= RISE_SKIP_MS then
        rise = rise + ((rpm - lastRpm) / math.max(dt, 0.001) - rise) * (1.0 - math.exp(-dt / RISE_SMOOTH))
    end
    lastRpm = rpm

    local want = car.want
    if shift then
        -- Nothing new decided while a change is under way (the old gear may still be in); a kickdown
        -- due waits for it.
        if kick then kickArmed = true end
    elseif kick and want > 1 then
        -- Down a gear or two, as far as there is room; GTA's own box from flat out.
        local to = want
        for g = want - 1, math.max(1, want - 2), -1 do
            if landing(veh, rpm, want, g) <= roomTop() then to = g else break end
        end
        if to < want then
            change(to, now, rpm, speed, 'kickdown %d -> %d at %.2f rpm, lands about %.2f (aggression %.2f, pedal %.2f)',
                want, to, rpm, landing(veh, rpm, want, to), aggression, pedal)
        else
            say('kickdown: no room in %d (lands about %.2f, room under %.2f): the gear held',
                want - 1, landing(veh, rpm, want, want - 1), roomTop())
        end
    elseif now - changedAt >= SETTLE_MS then
        local up, down = upRpm(pedal), downRpm(pedal)
        -- The gear held: while the pedal is going down (until the aggression builds to a kickdown), and
        -- for a while after a change up. Never under CoastDownRpm.
        local held = pedal > aggression + BUILDING or now - upAt < UP_HOLD_MS
        if want > 1 and speed < STOP_SPEED then
            change(1, now, rpm, speed, 'all but stopped: 1st')
            ---@cast shift -nil -- change() made it
            shift.switchAt = 0.0   -- in at once: pulling away again starts in 1st
        elseif pedal > PEDAL_OFF and want < car.high and rpm >= up
            and rpm * car.ratio[want + 1] / car.ratio[want] >= G.ecoDown + LUG_MARGIN then
            change(want + 1, now, rpm, speed, 'up %d -> %d at %.2f rpm (up point %.2f, pedal %.2f, aggression %.2f)',
                want, want + 1, rpm, up, pedal, aggression)
            upAt = now
        elseif want > 1 and (rpm < G.coastDown or (not held and rpm < down))
            and rpm * car.ratio[want - 1] / car.ratio[want] < up - HYSTERESIS
            and (pedal <= PEDAL_OFF or landing(veh, rpm, want, want - 1) <= roomTop()) then
            change(want - 1, now, rpm, speed, 'down %d -> %d at %.2f rpm (down point %.2f, pedal %.2f, aggression %.2f)',
                want, want - 1, rpm, rpm < G.coastDown and G.coastDown or down, pedal, aggression)
        end
    end
end

--- For turbo.lua: is a change under way on this car? nil when the computer is not driving it; else shifting, and whether up.
---@param veh number
---@return boolean|nil shifting, boolean up
function GearboxShift(veh)
    if not car or car.veh ~= veh then return nil, false end
    return shift ~= nil, shift ~= nil and shift.up or false
end

-- While driving

--- Something quick happening, so the next look is the next frame: a change under way, or GTA's box with the car
--- moving. Otherwise CRUISE_MS.
local function quick()
    if off then return false end
    return shift ~= nil or (car == nil and lastSpeed >= VERIFY_SPEED)
end

local driving = nil   -- the car this player drives (a kind power works on), or nil
local turn = 0        -- bumped by every start, so an older loop stops

-- A pad is in the player's hands: asked once whip_core is up, then whip_core says when it changes.
local onPad = false
AddEventHandler('whip_core:pad:deviceChanged', function(d) onPad = type(d) == 'table' and d.pad == true end)

local function usable()
    return gearsOk and G.enabled and onPad
end

--- Follow the car this player now drives (nil: none).
local function drive(veh)
    turn = turn + 1
    reset()
    driving = (veh and veh ~= 0 and gearsOk and PowerClasses[GetVehicleClass(veh)]) and veh or nil
    if not driving then return end
    local me, drivenCar = turn, driving
    CreateThread(function()
        local last = GetGameTimer()
        local checkedAt, ok = -IDLE_MS, false
        while me == turn and driving == drivenCar and DoesEntityExist(drivenCar) and GetResourceState('whip_core') == 'started' do
            local now = GetGameTimer()
            if now - checkedAt >= IDLE_MS then
                checkedAt = now
                local was = ok
                ok = usable()
                if was and not ok then reset() end
            end
            if ok then
                local fine, err = pcall(frame, drivenCar, now, math.min(0.5, (now - last) / 1000.0))
                if not fine then
                    print(('[whip_autos] the gearbox computer is off for this car: %s'):format(tostring(err)))
                    giveBack('an error')
                    off = true
                end
                last = now
                Wait(quick() and 0 or CRUISE_MS)
            else
                last = now
                Wait(IDLE_MS)
            end
        end
        if me == turn then giveBack('the car is gone') end
    end)
end

-- By whip_core's seat events, as PowerHandling.driverLayer is (client/power/handling.lua): every car driven.
AddEventHandler('whip_core:vehicle:entered', function(d)
    if type(d) == 'table' then drive(d.seat == -1 and d.entity or nil) end
end)
AddEventHandler('whip_core:vehicle:exited', function() drive(nil) end)
Whip.register(function()
    onPad = Whip.call('IsControllerActive') == true
    drive(AutosDrivenCar())
end)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then giveBack('whip_autos stopping') end
end)
