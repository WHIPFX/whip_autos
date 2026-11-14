-- ============================================
-- whip_autos — the Director opening Whiplash, and a goal's checklist
-- ============================================
-- The server (server/director.lua) works out who in a car gets Whiplash and lets them claim it off the
-- shop floor. Here: the open itself (moving over to the wheel first when nobody drives), and a goal's
-- checklist (shared/goals.lua) for the shop's screen, which client/ui.lua sends to the page.

Goals = {}

--- [netId] = the goal's checklist on that car: { text, pays, rows }.
local byNet = {}

--- Each passenger seat's bone. A seat without one goes by where its passenger sits.
local SEAT_BONE = {
    [0] = 'seat_pside_f', [1] = 'seat_dside_r', [2] = 'seat_pside_r', [3] = 'seat_dside_r1', [4] = 'seat_pside_r1',
    [5] = 'seat_dside_r2', [6] = 'seat_pside_r2', [7] = 'seat_dside_r3', [8] = 'seat_pside_r3',
}

--- Where the driver's seat is: a car's, else a bike's; nil when the model has neither bone.
local function wheelOf(veh)
    for _, name in ipairs({ 'seat_dside_f', 'seat_f' }) do
        local bone = GetEntityBoneIndexByName(veh, name)
        if bone ~= -1 then return GetWorldPositionOfEntityBone(veh, bone) end
    end
    return nil
end

local function seatPos(veh, seat, ped)
    local name = SEAT_BONE[seat]
    local bone = name and GetEntityBoneIndexByName(veh, name) or -1
    if bone ~= -1 then return GetWorldPositionOfEntityBone(veh, bone) end
    return GetEntityCoords(ped)
end

--- Which of these players (server ids) is nearest the driver's seat. Each of their games asks, and they
--- agree: seat positions are the car's own, and a near tie goes to the lower seat. With no driver's seat
--- bone, the lowest seat.
---@param veh number
---@param candidates table
---@return number|nil serverId
local function nearestToWheel(veh, candidates)
    local want = {}
    for _, id in ipairs(candidates) do want[tonumber(id) or -1] = true end
    local wheel = wheelOf(veh)
    local best, bestD
    for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and IsPedAPlayer(ped) then
            local id = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
            if want[id] then
                local d = wheel and #(seatPos(veh, seat, ped) - wheel) or seat
                -- Seats go in order, so a later one wins only when clearly nearer.
                if not best or d < bestD - 0.05 then best, bestD = id, d end
            end
        end
    end
    return best
end

--- The server's Force Open (a card, a task, or a goal starting): this car's driver opens Whiplash. With
--- nobody at the wheel, the passenger nearest it moves over first; everyone else does nothing.
---@param netId any  the car's network id (checked here)
---@param candidates table  the players told (server ids)
RegisterNetEvent('whip_autos:client:forceOpen', function(netId, candidates)
    CreateThread(function()
        if Session.isActive() then return end
        netId = tonumber(netId)
        if not netId or not NetworkDoesEntityExistWithNetworkId(netId) then return end
        local veh, ped = NetToVeh(netId), PlayerPedId()
        if veh == 0 or GetVehiclePedIsIn(ped, false) ~= veh or IsEntityDead(ped) then return end

        if GetPedInVehicleSeat(veh, -1) ~= ped then
            if GetPedInVehicleSeat(veh, -1) ~= 0 then return end   -- somebody has the wheel
            local me = GetPlayerServerId(PlayerId())
            if nearestToWheel(veh, type(candidates) == 'table' and candidates or {}) ~= me then return end
            TaskWarpPedIntoVehicle(ped, veh, -1)
            local deadline = GetGameTimer() + 1500
            while GetPedInVehicleSeat(veh, -1) ~= ped and GetGameTimer() < deadline do Wait(50) end
            if GetPedInVehicleSeat(veh, -1) ~= ped then return end
        end

        local ok, why = Session.open({ director = true })
        if not ok and why then Whip.core:Notify(why, 'error') end
    end)
end)

-- ============================================
-- A goal's checklist
-- ============================================

--- A goal on a car started, ticked a row, or ended (`false`).
RegisterNetEvent('whip_autos:client:job', function(netId, job)
    netId = tonumber(netId)
    if not netId then return end
    byNet[netId] = type(job) == 'table' and job or nil
    if UI and UI.jobChanged then UI.jobChanged() end   -- ui.lua loads after this file
end)

--- The goal's checklist on this car, or nil.
---@param veh number|nil
---@return table|nil
function Goals.of(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) or not NetworkGetEntityIsNetworked(veh) then return nil end
    return byNet[VehToNet(veh)]
end

--- Is the car they are driving one a goal has let them into? Enter Whiplash on the radial then works
--- anywhere (client/main.lua). Natives and a lookup: the radial asks every time it opens.
---@return boolean
function Goals.here()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return false end
    return Goals.of(veh) ~= nil
end

--- The visit's goal, or nil.
local function visitGoal()
    return Session.isActive() and Goals.of(Session.vehicle()) or nil
end

--- The basket as the page shows it: what the goal pays taken off each line, one it pays in full marked jobPays (at
--- nothing). The server works out the same for itself when it charges (ShopGoal.cover).
---@param basket table
---@return table
function Goals.dress(basket)
    local job = visitGoal()
    if not job or job.pays ~= 'job' then return basket end
    local paid = ShopGoal.cover(job.rows, basket, function(l) return l.price end)
    local out = {}
    for i, line in ipairs(basket) do
        if paid[i] then
            local c = {}
            for k, v in pairs(line) do c[k] = v end
            c.price = math.max(0, (tonumber(line.price) or 0) - paid[i])
            c.jobPays = c.price == 0 or nil
            out[i] = c
        else
            out[i] = line
        end
    end
    return out
end

--- The checklist for the page, or nil with no goal: each row done (paid for already), in the basket
--- (paying does it), or still to do.
---@return table|nil
function Goals.model()
    local job = visitGoal()
    if not job then return nil end
    local basket = Session.basket()
    local rows = {}
    for i, row in ipairs(job.rows or {}) do
        local state = row.done and 'done' or 'todo'
        if not row.done and row.how == 'spend' then
            -- (The spend: what was paid for already and the basket come to it.)
            if ShopGoal.spend(row, basket) >= row.min then state = 'basket' end
        elseif not row.done then
            for _, line in ipairs(basket) do
                if ShopGoal.lineMeets(row, line) then
                    state = 'basket'
                    break
                end
            end
        end
        rows[i] = { text = row.text, state = state }
    end
    return { title = job.text, rows = rows, pays = job.pays == 'job' }
end
