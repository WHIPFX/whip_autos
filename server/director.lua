-- ============================================
-- whip_autos — Whiplash in the Director
-- ============================================
-- Cards for the Director (whip_core's scenario builder), through its card API (Whip.card; the car task is
-- in shared/director.lua):
--
--   Goal: Customise Vehicle   puts the run's car's driver into Whiplash with a checklist (shared/goals.lua),
--                             and goes on when a run player has paid for the work. Car lost: gone or wrecked.
--   Force Open Whiplash       puts a car's driver into Whiplash, wherever the car is.
--
-- WHO GETS WHIPLASH, for a car: its driver, when that is a player it may open for. A passenger with a
-- driver, or a player on foot: nobody. Passengers and no driver: the passenger nearest the wheel moves
-- over first (their games agree which: client/director.lua).
--
-- A GRANT is what lets a car be claimed off the shop floor (server/main.lua, whip_autos:claimDirector),
-- by the car's network id, for some players or any. A Force Open's lasts a moment and is spent by the
-- claim; a goal's lasts while the goal waits, so its players can leave Whiplash and come back (the radial's
-- Enter Whiplash works anywhere in that car).

DirectorGoals = {}

--- [netId] = { allowed = { [src] = true } | nil, untilMs = n | nil, job = callId | nil, claimedBy = src | nil }
local grants = {}

--- Goals waiting: [callId] = { id, card, vehicleId, netId, rows, pays, who, text, told, opened, endsAt, timed }.
--- callId never goes to a player's game: clients know a job by its car's network id.
local jobs = {}

local GRANT_MS = 30000       -- how long a Force Open's grant waits for the claim
local OPEN_WAIT_MS = 10000   -- how long Force Open waits for Whiplash to open before Nobody
local MAX_SEAT = 15          -- the highest passenger seat looked at

-- ============================================
-- Who gets Whiplash
-- ============================================

--- Every player's ped -> their server id.
local function playersByPed()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local ped = src and GetPlayerPed(src)
        if ped and ped ~= 0 then out[ped] = src end
    end
    return out
end

--- Who Whiplash opens for in this car: { the driver }, or the passengers who may move over (each of
--- their games works out which is nearest the wheel). nil and why for nobody.
---@param ent number
---@param allowed table|nil  { [src] = true }: the players it may open for (nil: any)
---@return table|nil list, string|nil why
local function openersOf(ent, allowed)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil, 'the car is not there' end
    local byPed = playersByPed()
    local driver = GetPedInVehicleSeat(ent, -1)
    if driver ~= 0 then
        local src = byPed[driver]
        if not src then return nil, 'an NPC is driving' end
        if allowed and not allowed[src] then return nil, 'someone else is driving' end
        return { src }
    end
    local list = {}
    for seat = 0, MAX_SEAT do
        local src = byPed[GetPedInVehicleSeat(ent, seat)]
        if src and (not allowed or allowed[src]) then list[#list + 1] = src end
    end
    if #list == 0 then return nil, 'nobody is in it' end
    return list
end

--- Tells their games to open Whiplash in this car, under `grant`. A goal's grant on the car stands: it
--- already lets its players in. Answers the grant the claim will spend.
---@param ent number
---@param list table  from openersOf
---@param grant table
---@return table grant
local function sendOpen(ent, list, grant)
    local netId = NetworkGetNetworkIdFromEntity(ent)
    local had = grants[netId]
    if had and had.job and jobs[had.job] then
        grant = had
        grant.claimedBy = nil
    else
        grants[netId] = grant
    end
    for _, src in ipairs(list) do TriggerClientEvent('whip_autos:client:forceOpen', src, netId, list) end
    return grant
end

--- Is a grant still good?
local function live(g)
    return g ~= nil and (g.untilMs == nil or GetGameTimer() < g.untilMs)
end

--- The grant that lets `src` claim this car off the shop floor, and the car's network id; nil when
--- there is none. (server/main.lua's whip_autos:claimDirector.)
---@param src number
---@param vehicleId number
---@return table|nil grant, number|nil netId
function DirectorGoals.grantFor(src, vehicleId)
    local v = Whip.call('GetVehicle', vehicleId)
    local ent = type(v) == 'table' and v.entity or nil
    if not ent then return nil end
    local netId = NetworkGetNetworkIdFromEntity(ent)
    local g = grants[netId]
    if not live(g) then
        grants[netId] = nil
        return nil
    end
    if g.allowed and not g.allowed[src] then return nil end
    return g, netId
end

--- A grant was used to claim the car: a Force Open's is spent; a goal's notes that its Whiplash opened.
---@param src number
---@param g table
---@param netId number
function DirectorGoals.claimed(src, g, netId)
    g.claimedBy = src
    local job = g.job and jobs[g.job]
    if job then
        job.opened = true
    elseif grants[netId] == g then
        grants[netId] = nil
    end
end

-- ============================================
-- Goals waiting (Customise Vehicle)
-- ============================================

--- The goal as its players' games see it: the checklist (no callId).
local function clientJob(job)
    return { text = job.text, pays = job.pays, rows = job.rows }
end

--- Sends the checklist (or `false`: it is over) to the goal's players, for its car.
local function tell(job, data)
    if data == nil then data = clientJob(job) end
    for src in pairs(job.who) do TriggerClientEvent('whip_autos:client:job', src, job.netId, data) end
end

--- Takes a goal off the books: its grant and its players' checklists go. false when it already went.
local function drop(job)
    if jobs[job.id] ~= job then return false end
    jobs[job.id] = nil
    local g = grants[job.netId]
    if g and g.job == job.id then grants[job.netId] = nil end
    tell(job, false)
    return true
end

--- Ends a goal with one of its outcomes. What it showed goes first: a card that has answered is refused
--- its methods.
local function finish(job, pin, data)
    if not drop(job) then return end
    local card = job.card
    card:clearObjective()
    if job.timed then card:clock(0) end
    if pin == 'done' and data and data.source then card:record('customised', { source = data.source }) end
    Whip.answerCard(job.id, pin, data)
end

-- The goal follows its run's crew (whip_core's run events): one taken out of the run loses its checklist, its
-- grant and its free parts (who is the grant's allowed list too); one put in gets them.
AddEventHandler('whip_core:run:playerLeft', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or type(e.run) ~= 'table' then return end
    local src = tonumber(e.source)
    for _, job in pairs(jobs) do
        if job.runId == e.run.id and src and job.who[src] then
            job.who[src], job.told[src] = nil, nil
            TriggerClientEvent('whip_autos:client:job', src, job.netId, false)
        end
    end
end)
AddEventHandler('whip_core:run:playerJoined', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or type(e.run) ~= 'table' then return end
    local src = tonumber(e.source)
    for _, job in pairs(jobs) do
        if job.runId == e.run.id and src and not job.who[src] then
            job.who[src] = true
            TriggerClientEvent('whip_autos:client:job', src, job.netId, clientJob(job))
        end
    end
end)

--- The car came back under a new network id (whip put it out again): the grant and the checklists follow.
local function moveTo(job, netId)
    local g = grants[job.netId]
    if g and g.job == job.id then
        grants[job.netId] = nil
        grants[netId] = g
    end
    tell(job, false)
    job.netId = netId
    tell(job)
end

--- Once a second while the goal waits: out of time, the car lost, and Whiplash opened for a player of the
--- run who gets into it (nobody was in it when the goal began, or someone new took the wheel).
local function watch(job)
    local goneFor, wreckedFor = 0, 0
    while jobs[job.id] == job do
        Wait(1000)
        if jobs[job.id] ~= job then return end
        if job.endsAt and GetGameTimer() >= job.endsAt then return finish(job, 'outOfTime') end

        local v = Whip.call('GetVehicle', job.vehicleId)
        local ent = type(v) == 'table' and v.entity or nil
        if not ent then
            -- A few seconds' grace: whip takes a car in and puts it out again (a new owner, a claim).
            goneFor = goneFor + 1
            if goneFor >= 5 then return finish(job, 'lost') end
        elseif Whip.call('IsVehicleWrecked', job.vehicleId) == true then
            wreckedFor = wreckedFor + 1
            if wreckedFor >= 3 then return finish(job, 'lost') end
        else
            goneFor, wreckedFor = 0, 0
            local netId = NetworkGetNetworkIdFromEntity(ent)
            if netId ~= job.netId then moveTo(job, netId) end
            if not job.opened then
                local list = openersOf(ent, job.who) or {}
                -- Each player is put in once: one who left it can come back through the radial.
                local fresh = false
                for _, src in ipairs(list) do
                    if not job.told[src] then fresh = true end
                end
                if fresh then
                    for _, src in ipairs(list) do job.told[src] = true end
                    sendOpen(ent, list, grants[job.netId])
                end
            end
        end
    end
end

--- A basket was paid for on this car: the goal's rows it did are ticked (a spend row adds the order's parts); all
--- ticked, the goal is done. (server/main.lua, after the order is fitted.)
---@param vehicleId number
---@param src number
---@param lines table  the order's lines, each with its price
function DirectorGoals.purchased(vehicleId, src, lines)
    for _, job in pairs(jobs) do
        if job.vehicleId == vehicleId and job.who[src] then
            local moved = false
            for _, row in ipairs(job.rows) do
                if not row.done and row.how == 'spend' then
                    ShopGoal.spend(row, lines, true)
                    row.done, moved = row.spent >= row.min, true
                elseif not row.done then
                    for _, line in ipairs(lines) do
                        if ShopGoal.lineMeets(row, line) then
                            row.done, moved = true, true
                            break
                        end
                    end
                end
            end
            if ShopGoal.finished(job.rows) then
                finish(job, 'done', { source = src })
            elseif moved then
                tell(job)
            end
        end
    end
end

--- What a goal pays of this order: { [line index] = dollars of it }, when a goal on this car pays and the buyer is
--- one of its players (ShopGoal.cover: a spend row up to its minimum, no further). server/main.lua takes it off.
---@param vehicleId number
---@param src number
---@param lines table
---@param priceOf fun(line: table, i: integer): number
---@return table paid
function DirectorGoals.cover(vehicleId, src, lines, priceOf)
    for _, job in pairs(jobs) do
        if job.vehicleId == vehicleId and job.who[src] and job.pays == 'job' then
            return ShopGoal.cover(job.rows, lines, priceOf)
        end
    end
    return {}
end

-- ============================================
-- The cards
-- ============================================

-- ============================================
-- What a car can take: the most its parts come to
-- ============================================
-- Only a game can say which parts a model takes (client/catalogue.lua), so each Whiplash visit says what every part
-- its car takes would come to (whip_autos:server:carMost). It is kept here by the model's hash, in this resource's
-- KVP across restarts, for the goal's Check: a minimum spend a car cannot reach is warned about.

local MOST_KEY = 'most:'   -- most:<model hash> = dollars

--- What every part a model takes comes to, or nil when no Whiplash visit has said yet.
---@param model string|nil
---@return number|nil
local function mostFor(model)
    if type(model) ~= 'string' or model == '' then return nil end
    local v = GetResourceKvpInt(MOST_KEY .. tostring(GetHashKey(model) & 0xFFFFFFFF))
    return v > 0 and v or nil
end

-- ============================================
-- Goal: Customise Vehicle
-- ============================================

--- Goal: Customise Vehicle's fields: its car, words and clock, then the work: a way it must be (picked in Whiplash
--- from the card: client/look.lua autos.exactWay, one at random each run), a minimum spend on any parts, both, or
--- neither (any one part).
local function customiseProps()
    return {
        { key = 'car', kind = 'world', worldKind = 'vehicle', label = 'Car (the one this run made)', required = true },
        { key = 'text', kind = 'text', label = 'Objective (on screen)', default = 'Customise the car', maxLength = 120 },
        { key = 'pays', kind = 'select', label = 'Who pays', default = 'job',
          options = { { value = 'job', label = 'The job (the parts it asks for)' }, { value = 'player', label = 'The player' } } },
        { key = 'seconds', kind = 'duration', label = 'Time limit (seconds; empty: none)', min = 5, max = 86400 },
        { key = 'exact', kind = 'bool', label = 'Must be customised a specific way', default = false, group = 'The work',
          hint = 'With both of these off, any one part does.' },
        { key = 'ways', kind = 'entries', label = 'The ways it may be', button = 'autos.exactWay', add = 'Pick a way in Whiplash',
          max = ShopGoal.MAX_WAYS, showIf = 'exact',
          hint = 'Each a whole look picked in Whiplash: paint, parts, wheels. Several: each run asks for one of them at random.' },
        { key = 'free', kind = 'bool', label = 'Can be customised any way the player wants', default = false },
        { key = 'spend', kind = 'number', label = 'Minimum spend ($)', min = 0, max = 10000000, showIf = 'free',
          hint = 'What the parts they fit must come to, each part once. Empty: any one part.' },
    }
end

--- The car's model as the run made it (a random vehicle's: the one it picked).
local function modelOf(made, v)
    local m = type(made) == 'table' and made.model or nil
    if type(m) ~= 'string' and type(v) == 'table' then m = v.model end
    return type(m) == 'string' and m or nil
end

--- Goal: Customise Vehicle starting: the checklist, the grant on the car, its objective and clock, and
--- Whiplash opened for whoever is at its wheel.
local function startGoal(card)
    local carW = card.props.car
    local made = type(carW) == 'table' and card:made(carW.id) or nil
    local vehicleId = type(made) == 'table' and made.vehicleId or nil
    local v = vehicleId and Whip.call('GetVehicle', vehicleId)
    if not (type(v) == 'table' and v.entity) then
        card:log('the car is not out in the world')
        return 'lost'
    end

    -- This run's way: one of the card's, of those picked on this model when there are any.
    local model = modelOf(made, v)
    local way = card.props.exact == true and ShopGoal.pickWay(card.props.ways, model) or nil
    if card.props.exact == true and not way then card:log('it must be a specific way, but no way is picked on the card') end
    local rows = ShopGoal.rows(card.props, way)
    local most = mostFor(model)
    local turbo = exports.whip_core:GetVehicleData(v.vehicleId, TUNING_TURBO_KEY)
    local turboIndex = TuningTurboIndex(turbo)
    local engine, _, _, drive = TuningServer.current(v.vehicleId)
    for _, row in ipairs(rows) do
        row.done = ShopGoal.propsMeet(row, v.properties, turboIndex, { engine = engine, drive = drive })
        if row.how == 'spend' and most and most < row.min then
            card:log('a %s takes %s of parts at most: a spend of %s cannot be reached', model, ShopGoal.money(most), ShopGoal.money(row.min))
        end
    end
    -- Already what they asked for: nothing to do.
    if ShopGoal.finished(rows) then return 'done' end

    local who = {}
    for _, s in ipairs(card.players or {}) do who[s] = true end
    local job = {
        id = card.callId, card = card, runId = card.runId, vehicleId = vehicleId, netId = NetworkGetNetworkIdFromEntity(v.entity),
        rows = rows, pays = card.props.pays == 'player' and 'player' or 'job', who = who, told = {},
        text = card.props.text or 'Customise the car',
    }
    jobs[job.id] = job
    grants[job.netId] = { job = job.id, allowed = who }
    tell(job)

    card:objective(job.text)
    local seconds = tonumber(card.props.seconds)
    if seconds and seconds > 0 then
        card:clock(seconds, job.text)
        job.timed, job.endsAt = true, GetGameTimer() + math.floor(seconds * 1000)
    end

    local list = openersOf(v.entity, who)
    if list then
        for _, src in ipairs(list) do job.told[src] = true end
        sendOpen(v.entity, list, grants[job.netId])
    end
    CreateThread(function() watch(job) end)
    return nil   -- answered by a purchase (DirectorGoals.purchased) or the watch
end

--- Adds (or changes) Goal: Customise Vehicle, with the parts Whiplash sells now.
local function registerCustomise()
    Whip.card('autos.customise', {
        category = 'goals',
        title = 'Goal: Customise Vehicle',
        desc = 'Puts the run\'s car\'s driver into Whiplash with a checklist, and goes on when a run player pays for the work: '
            .. 'a way it must be, a minimum spend, both, or any one part. Car lost: gone, blown up or sunk.',
        help = 'Whiplash opens for the car\'s driver when the goal starts (with nobody at the wheel, the passenger nearest it '
            .. 'moves over), and again for a run player who gets in later. Leaving Whiplash keeps the goal: Enter Whiplash on '
            .. 'the radial works anywhere in that car until it is done. A way is a whole look picked in Whiplash from this '
            .. 'card: every part of it is asked for. A spend counts each part once. The job paying covers what the checklist '
            .. 'asks for: a way\'s parts, and parts up to the spend.',
        outputs = { 'done', 'lost', 'outOfTime' },
        labels = { done = 'Customised', lost = 'Car lost', outOfTime = 'Out of time' },
        bad = { 'lost', 'outOfTime' },
        -- Its own time limit (seconds) is the one players see; Give up after is a backstop.
        timeout = 3600,
        test = 'run',
        props = customiseProps(),
        check = function(props, doc)
            local car
            for _, w in ipairs(type(doc) == 'table' and type(doc.world) == 'table' and doc.world or {}) do
                if w.id == props.car then car = w end
            end
            -- (A random vehicle: every one of its models.)
            local models = car and (type(car.models) == 'table' and #car.models > 0 and car.models or { car.model }) or {}
            if props.exact == true then
                local ways = type(props.ways) == 'table' and props.ways or {}
                if #ways == 0 then return 'It must be a specific way, but none is picked: Pick a way in Whiplash', 'warning' end
                for i, w in ipairs(ways) do
                    local fits = false
                    for _, m in ipairs(models) do
                        if type(w) == 'table' and type(w.model) == 'string' and w.model:lower() == tostring(m):lower() then fits = true end
                    end
                    if not fits and #models > 0 then
                        return ('Way %d was picked on a %s, which this car never is: its parts may not fit'):format(i, tostring(w.model)),
                            'warning'
                    end
                end
            end
            local spend = props.free == true and tonumber(props.spend) or 0
            if spend > 0 then
                for _, m in ipairs(models) do
                    local most = mostFor(m)
                    if most and most < spend then
                        return ('A %s takes %s of parts at most in Whiplash: a minimum spend of %s cannot be reached')
                            :format(m, ShopGoal.money(most), ShopGoal.money(spend)), 'warning'
                    end
                end
            end
            return nil
        end,
        run = startGoal,
        -- Ended without our answer (Give up after, the run ended): the grant and the checklists go. (Its
        -- objective and clock go by themselves: whip_core takes down what a card that did not answer put up.)
        onEnd = function(callId)
            local job = jobs[callId]
            if job then drop(job) end
        end,
    })
end

registerCustomise()

Whip.card('autos.forceOpen', {
    categoryTitle = 'Whiplash', color = 'violet',
    title = 'Force Open Whiplash',
    desc = 'Puts the driver of the car into Whiplash, wherever it is. A passenger with a driver, or a player on foot: nothing. '
        .. 'Passengers and no driver: the one nearest the wheel moves over first.',
    outputs = { 'opened', 'nobody' },
    labels = { opened = 'Opened', nobody = 'Nobody to open it for' },
    timeout = 20,
    test = 'run',
    props = {
        { key = 'who', kind = 'players', label = 'Who' },
    },
    run = function(card)
        local targets = type(card.props.who) == 'table' and card.props.who or {}
        local allowed = {}
        for _, s in ipairs(targets) do allowed[s] = true end

        local grant = { allowed = allowed, untilMs = GetGameTimer() + GRANT_MS }
        local watching, seen = {}, {}
        for _, s in ipairs(targets) do
            local ped = GetPlayerPed(s)
            local ent = (ped and ped ~= 0) and GetVehiclePedIsIn(ped, false) or 0
            if ent ~= 0 and not seen[ent] then
                seen[ent] = true
                local list = openersOf(ent, allowed)
                if list then watching[#watching + 1] = sendOpen(ent, list, grant) end
            end
        end
        if #watching == 0 then return 'nobody' end

        -- On once one of them has claimed the car (the claim spends the grant), or nobody in time.
        local deadline = GetGameTimer() + OPEN_WAIT_MS
        while GetGameTimer() < deadline do
            Wait(250)
            for _, g in ipairs(watching) do
                if g.claimedBy then return 'opened', { source = g.claimedBy } end
            end
        end
        return 'nobody'
    end,
})

-- ============================================
-- The car task (shared/director.lua): the owner's game asks
-- ============================================

--- 'whip_autos:server:taskOpen': the game running a car playing Force Open Whiplash. Only that game, and
--- only for a car of a run going now (a Test's too); any player in it may get Whiplash.
local function onTaskOpen(source, _, netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    if NetworkGetEntityOwner(ent) ~= source then return end
    if not exports.whip_core:GetScenarioRunOf({ netId = netId }, { tests = true }) then return end
    local list = openersOf(ent, nil)
    if list then sendOpen(ent, list, { untilMs = GetGameTimer() + GRANT_MS }) end
end

--- 'whip_autos:server:carMost': a Whiplash visit says what every part its car takes comes to (client/session.lua),
--- kept for the goal's Check (mostFor). Believed only from a player with a session open (server/main.lua), about
--- the car they sit in: any other word would write a key a time, or a wrong figure for a real car.
local function onCarMost(source, _, hash, most)
    if hash <= 0 or most <= 0 then return end
    if not AutosSessions.carOf(source) then return end
    local veh = GetVehiclePedIsIn(GetPlayerPed(source), false)
    if not veh or veh == 0 or (GetEntityModel(veh) & 0xFFFFFFFF) ~= hash then return end
    local key = MOST_KEY .. tostring(hash)
    if GetResourceKvpInt(key) ~= most then SetResourceKvpInt(key, most) end
end

Whip.register(function()
    exports.whip_core:SecureEvent('whip_autos:server:taskOpen', {
        rateLimit = 1000, burst = 3,
        params = {
            { 'netId', 'id' },
        },
    }, onTaskOpen)
    exports.whip_core:SecureEvent('whip_autos:server:carMost', {
        rateLimit = 2000, burst = 3,
        params = {
            { 'hash', 'int', 0, 4294967295 },
            { 'most', 'int', 0, 100000000 },
        },
    }, onCarMost)
end)
