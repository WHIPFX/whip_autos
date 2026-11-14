-- ============================================
-- whip_autos power — what the client and server halves share
-- ============================================
-- The vehicle classes power works on, the turbo's boost scale, and the turbo and nitrous settings.
-- A shared script (loaded on both sides, before shared/settings.lua), so each number is written once
-- and both halves read the same one.

--- GTA's land vehicle classes with an engine, the ones top speed, shifting and nitrous touch: class
--- number → its key in Config.ShiftTimeByClass / PlainShiftTimeByClass and its name on the page. Never
--- touched: 13 bicycles, 14 boats, 15 helicopters, 16 planes, 21 trains.
PowerClasses = {
    [0] = { key = 'Compacts', label = 'Compacts' },        [1] = { key = 'Sedans', label = 'Sedans' },
    [2] = { key = 'SUVs', label = 'SUVs' },                [3] = { key = 'Coupes', label = 'Coupes' },
    [4] = { key = 'Muscle', label = 'Muscle' },            [5] = { key = 'SportsClassics', label = 'Sports classics' },
    [6] = { key = 'Sports', label = 'Sports' },            [7] = { key = 'Super', label = 'Super' },
    [8] = { key = 'Motorcycles', label = 'Motorbikes' },   [9] = { key = 'OffRoad', label = 'Off-road' },
    [10] = { key = 'Industrial', label = 'Industrial' },   [11] = { key = 'Utility', label = 'Utility' },
    [12] = { key = 'Vans', label = 'Vans' },               [17] = { key = 'Service', label = 'Service' },
    [18] = { key = 'Emergency', label = 'Emergency' },     [19] = { key = 'Military', label = 'Military' },
    [20] = { key = 'Commercial', label = 'Commercial' },   [22] = { key = 'OpenWheel', label = 'Open wheel' },
}

-- ============================================
-- The turbo and nitrous settings
-- ============================================
-- Each row below is the setting on the /whip → Settings → Autos page (shared/settings.lua) AND the
-- limits its value is read within. config.lua gives the defaults. A value there outside its row's
-- limits leaves the row off the page (whip_core prints which), so the reads below clamp it.

local function shiftLossCross(get)
    local least, most = tonumber(get('Turbo.ShiftLossMin')), tonumber(get('Turbo.ShiftLossMax'))
    if least and most and most < least then return false, 'Gear change: the most boost lost is below the least' end
    return true
end

local function spoolCross(get)
    local fastest, slowest = tonumber(get('Turbo.SpoolFastest')), tonumber(get('Turbo.SpoolSlowest'))
    if fastest and slowest and slowest < fastest then return false, 'The biggest turbo spools faster than the smallest' end
    return true
end

--- The turbo, sold at Whiplash in stages (Config.Turbo.Stages: the most boost each makes, in psi). The 'boost' stat
--- runs IDLE..MAX, which the gauge reads as PSI_LOW..PSI_HIGH (server/power/turbo.lua registers it with that
--- `display`): a stage's full boost is the level its psi reads at (levelOf).
PowerTurbo = {
    IDLE = 1.0,       -- the 'boost' stat at rest: just above vacuum
    MAX  = 100.0,     -- the top of the gauge
    PSI_LOW  = -3,    -- what the gauge reads at 0 (vacuum: off the throttle) ...
    PSI_HIGH = 30,    -- ... and at MAX
    rows = {
        { key = 'Turbo.TorquePerPsi', type = 'number', min = 0, max = 0.1, unit = '×', label = 'Torque per psi',
          help = 'Extra engine torque per psi of full boost: 0.03 is 3%, so a 15 psi turbo adds 45% and a 30 psi one 90%. 0: no extra torque; a turbo is then only GTA\'s own small turbo part and its sound.' },
        { key = 'Turbo.SpoolFastest', type = 'number', min = 0.3, max = 30, unit = 's', label = 'Spool time, smallest turbo', cross = spoolCross,
          help = 'Seconds the smallest turbo takes from no boost to full, foot flat at the limiter. At idle revs it takes about six times as long.' },
        { key = 'Turbo.SpoolSlowest', type = 'number', min = 0.3, max = 30, unit = 's', label = 'Spool time, biggest turbo', cross = spoolCross,
          help = 'The same for the biggest turbo. The ones between are spaced evenly by their psi.' },
        { key = 'Turbo.ShiftLossMin', type = 'number', min = 0, max = 90, unit = '%', label = 'Gear change: least lost', cross = shiftLossCross,
          help = 'Each gear change dumps a random share of the boost, between this and the most.' },
        { key = 'Turbo.ShiftLossMax', type = 'number', min = 0, max = 90, unit = '%', label = 'Gear change: most lost', cross = shiftLossCross,
          help = 'The most a gear change can dump, however long it takes.' },
    },
}

--- The boost level a reading of `psi` is, inside IDLE..MAX.
---@param psi number
---@return number
function PowerTurbo.levelOf(psi)
    local level = (psi - PowerTurbo.PSI_LOW) / (PowerTurbo.PSI_HIGH - PowerTurbo.PSI_LOW) * PowerTurbo.MAX
    return math.max(PowerTurbo.IDLE, math.min(PowerTurbo.MAX, level))
end

--- The stage sold at `psi`, or nil: { index, psi, price, top (its full-boost level), spool (seconds), spoolPeak (boost a
--- second, flat out at the limiter), gain (extra torque at full boost) }. Worked out by read() below.
---@param psi any
---@return table|nil
function PowerTurbo.stage(psi)
    psi = tonumber(psi)
    if not psi then return nil end
    for _, s in ipairs(PowerTurbo.stages or {}) do
        if s.psi == psi then return s end
    end
    return nil
end

PowerNitrous = {
    BOTTLE = 100.0,   -- the 'nitro' stat in a full bottle (server/power/nitrous.lua registers it)
    rows = {
        { key = 'Nitrous.Torque', type = 'number', min = 1, max = 10, unit = '×', label = 'Torque while boosting',
          help = 'The engine\'s torque while the button is held: 3 is three times.' },
        { key = 'Nitrous.BottleSeconds', type = 'number', min = 2, max = 120, unit = 's', label = 'Bottle lasts',
          help = 'Seconds of boost in a full bottle.' },
        { key = 'Nitrous.InstallSeconds', type = 'number', min = 1, max = 60, unit = 's', label = 'Time to fit',
          help = 'How long fitting a bottle takes, sitting in the car.' },
    },
}

local ROW = {}
for _, r in ipairs(PowerTurbo.rows) do ROW[r.key] = r end
for _, r in ipairs(PowerNitrous.rows) do ROW[r.key] = r end

--- A setting's value (config.lua's, or what an admin saved), inside its row's limits; `fallback` when
--- it is not a number.
local function setting(key, fallback)
    local group, name = key:match('^(%w+)%.(%w+)$')
    local t = type(Config[group]) == 'table' and Config[group] or {}
    local v = tonumber(t[name])
    if not v or v ~= v then return fallback end
    local row = ROW[key]
    return math.max(row.min, math.min(row.max, v))
end

--- Config.Turbo.Stages, checked: whole psi from 1 to PSI_HIGH, each once, a price of 0 or more, smallest first. A row
--- that is not one is left out, with a line in the console.
local function readStages()
    local list, seen = {}, {}
    local src = type(Config.Turbo) == 'table' and type(Config.Turbo.Stages) == 'table' and Config.Turbo.Stages or {}
    for i, s in ipairs(src) do
        local psi = type(s) == 'table' and tonumber(s.psi) or nil
        local price = type(s) == 'table' and tonumber(s.price) or nil
        if psi and psi == math.floor(psi) and psi >= 1 and psi <= PowerTurbo.PSI_HIGH and price and price >= 0 and not seen[psi] then
            seen[psi] = true
            list[#list + 1] = { psi = psi, price = math.floor(price) }
        else
            Whip.startProblem('Config.Turbo.Stages[%d] is not { psi = 1-%d, price = 0 or more }, or repeats a psi: left out',
                i, PowerTurbo.PSI_HIGH)
        end
    end
    table.sort(list, function(a, b) return a.psi < b.psi end)
    return list
end

--- Fills in the values the power files read: PowerTurbo.stages and the rest. Again on any change.
local function read()
    -- Each stage's numbers. Spool time runs from SpoolFastest (the smallest turbo) to SpoolSlowest (the biggest),
    -- spaced by psi; boost a second is its full level over that, flat out at the limiter (client/power/turbo.lua
    -- scales it down by the revs). fastestRise: the quickest any stage climbs, the server's cap on boost reports.
    local perPsi  = setting('Turbo.TorquePerPsi', 0.033)
    local fastest = setting('Turbo.SpoolFastest', 0.5)
    local slowest = math.max(fastest, setting('Turbo.SpoolSlowest', 3.0))
    local stages  = readStages()
    local lo = stages[1] and stages[1].psi
    local hi = stages[#stages] and stages[#stages].psi
    PowerTurbo.fastestRise = 1.0
    for i, s in ipairs(stages) do
        s.index     = i
        s.top       = PowerTurbo.levelOf(s.psi)
        s.spool     = (hi > lo) and fastest + (s.psi - lo) / (hi - lo) * (slowest - fastest) or fastest
        s.spoolPeak = (s.top - PowerTurbo.IDLE) / s.spool
        s.gain      = perPsi * s.psi
        PowerTurbo.fastestRise = math.max(PowerTurbo.fastestRise, s.spoolPeak)
    end
    PowerTurbo.stages = stages

    PowerTurbo.lossMin    = setting('Turbo.ShiftLossMin', 20) / 100
    PowerTurbo.lossMax    = math.max(PowerTurbo.lossMin, setting('Turbo.ShiftLossMax', 50) / 100)

    PowerNitrous.torque     = setting('Nitrous.Torque', 3.0)
    PowerNitrous.burnPerSec = PowerNitrous.BOTTLE / setting('Nitrous.BottleSeconds', 20)
    PowerNitrous.installMs  = setting('Nitrous.InstallSeconds', 10) * 1000
end
read()
Whip.onConfigChanged('Turbo', read)
Whip.onConfigChanged('Nitrous', read)
