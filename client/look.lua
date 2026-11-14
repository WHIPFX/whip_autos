-- ============================================
-- whip_autos — how a Director car spawns, set in the world builder
-- ============================================
-- The Whiplash button beside Configure and Remove when a car is selected in the Director's world builder
-- (Whip.directorButton, the bubble only). Pressed, the Director steps aside and Whiplash opens on a copy of the car:
-- the builder fits parts, paint and tuning as a player would, and Save keeps them on the car in the scenario as its
-- LOOK. Whenever the scenario makes that car (a run's Spawn Car, a take's car, Always present, a Test), it comes
-- out wearing it (server/look.lua). No goal reads it: it is just the car.
--
-- The copy is this game's only (never networked: nobody else sees it or what is tried on it) and goes when Whiplash
-- closes; nothing is bought or saved on the server. The builder sits in it while Whiplash is open and is put back
-- where they stood after.
--
-- The world builder's own copy of the car wears the look too (whip_core:director:builderCopy, below), so the builder
-- sees the car a run makes.

local MODEL_WAIT_MS = 5000
local GROUND_WAIT_MS = 3000

local function notify(text, kind) Whip.call('Notify', text, kind or 'info') end

local function fade(out)
    if out then DoScreenFadeOut(250) else DoScreenFadeIn(250) end
    local deadline = GetGameTimer() + 1000
    while (out and not IsScreenFadedOut() or not out and not IsScreenFadedIn()) and GetGameTimer() < deadline do Wait(0) end
end

--- The car's model loaded, as its hash, or nil.
local function loadModel(model)
    local hash = type(model) == 'number' and model or (type(model) == 'string' and joaat(model) or nil)
    if not hash or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + MODEL_WAIT_MS
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
    return HasModelLoaded(hash) and hash or nil
end

--- A random vehicle (the world builder's first Vehicles tile: thing.models, its models) keeps a look for each model,
--- data.looks[model]; any other car one look, data.look.
local function lookOf(thing)
    local data = type(thing.data) == 'table' and thing.data or {}
    if type(thing.models) == 'table' then
        local looks = type(data.looks) == 'table' and data.looks or {}
        return type(looks[thing.model]) == 'table' and looks[thing.model] or nil
    end
    return type(data.look) == 'table' and data.look or nil
end

--- Whiplash on a copy of a car, until it closes: the look saved, or nil when it was left without saving (or could
--- not open).
---@param model string|number|nil  its name or hash (nil: it cannot open)
---@param c table  where the car is placed: { x, y, z, heading }
---@param kept table|nil  its look so far (kept lines)
---@return table|nil look
local function edit(model, c, kept)
    if Session.isActive() then notify('Whiplash is open already', 'error') return nil end
    local hash = type(c) == 'table' and loadModel(model) or nil
    if not hash then
        notify('Whiplash cannot open on this car (its model did not load)', 'error')
        return nil
    end

    local ped = PlayerPedId()
    local backAt, backHeading = GetEntityCoords(ped), GetEntityHeading(ped)
    local veh, look

    -- Whatever happens in between, the copy goes and they are put back.
    local ok, err = pcall(function()
        fade(true)
        -- Where the car was placed: a car fits there, and the world is loaded round it.
        SetEntityCoords(ped, c.x + 0.0, c.y + 0.0, c.z + 1.0, false, false, false, false)
        RequestCollisionAtCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
        local deadline = GetGameTimer() + GROUND_WAIT_MS
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(50) end

        veh = CreateVehicle(hash, c.x + 0.0, c.y + 0.0, c.z + 0.0, (tonumber(c.heading) or 0.0) + 0.0, false, false)
        SetModelAsNoLongerNeeded(hash)
        if not veh or veh == 0 then error('the car could not be made') end
        SetVehicleOnGroundProperly(veh)
        SetVehicleEngineOn(veh, true, true, false)
        TaskWarpPedIntoVehicle(ped, veh, -1)
        deadline = GetGameTimer() + 1500
        while GetPedInVehicleSeat(veh, -1) ~= ped and GetGameTimer() < deadline do Wait(50) end

        -- Its look so far, on the car and in the basket.
        local lines = {}
        for _, k in ipairs(kept or {}) do
            local line = ShopGoal.unpack(k)
            if line then lines[#lines + 1] = line end
        end
        fade(false)

        local opened, why = Session.openBuilder(veh, lines)
        if not opened then error(why or 'Whiplash would not open') end
        while Session.isActive() do Wait(100) end
        look = Session.takeLook()
    end)

    fade(true)
    -- Out of the copy first (the move takes them out of the seat), then it goes.
    if veh and GetVehiclePedIsIn(ped, false) == veh then ClearPedTasksImmediately(ped) end
    SetEntityCoords(ped, backAt.x, backAt.y, backAt.z, false, false, false, false)
    SetEntityHeading(ped, backHeading)
    if veh and DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end
    fade(false)

    if not ok then
        notify('Whiplash: ' .. tostring(err), 'error')
        return nil
    end
    return look
end

Whip.directorButton('autos.look', {
    label = 'Whiplash',
    icon = 'turbo',
    kinds = { 'vehicle' },
    where = 'bubble',
    takesOver = true,
    hint = 'Customise how this car spawns: the parts, paint and tuning it comes out with whenever the scenario makes it.',
    press = function(thing)
        local look = edit(thing.model, thing.coords, lookOf(thing))
        if look then
            -- Saved empty: it spawns as it is (what else this resource kept on it stays). A random vehicle's: this
            -- model's look.
            local data = type(thing.data) == 'table' and thing.data or {}
            local name = thing.label
            if type(thing.models) == 'table' then
                data.looks = type(data.looks) == 'table' and data.looks or {}
                data.looks[thing.model] = #look > 0 and look or nil
                if not next(data.looks) then data.looks = nil end
                name = ('%s (%s)'):format(thing.label, thing.model)
            else
                data.look = #look > 0 and look or nil
            end
            local done, why = thing:save(next(data) and data or nil)
            if done then
                notify(#look > 0 and ('%s spawns with %d part%s now'):format(name, #look, #look == 1 and '' or 's')
                    or (name .. ' spawns as it is now'), 'success')
            else
                notify('Could not keep the look: ' .. tostring(why), 'error')
            end
        end
        thing:back()
    end,
})

-- ============================================
-- The world builder's copy, in its look
-- ============================================
-- whip_core makes a copy of each of the scenario's cars in the world builder (this game's only) and says so, with what
-- we keep on it: the copy is dressed in its look as Whiplash fits it. Parts, paint, wheels and stance; an engine swap,
-- a handling setup and a drivetrain do not show on a parked car. A random vehicle's copy wears the look of the model it
-- shows (made again with each). A take's copies say so too (recording one, Watch it): the car the player records in is
-- `driven`, and gets the rest of the look as a run's car has it (wearDriven), so it drives as that car would.

local NOT_SEEN = { engine = true, setup = true, drive = true }
local stanced = {}   -- [copy] = true: copies with a stance drawn on them, let go of once each is gone
local watching = false

--- The stances on copies that are gone, let go of (every two seconds while there are any).
local function watchStanced()
    if watching then return end
    watching = true
    CreateThread(function()
        while next(stanced) do
            Wait(2000)
            for veh in pairs(stanced) do
                if not DoesEntityExist(veh) then
                    stanced[veh] = nil
                    Tuning.drawStance(veh, nil)
                end
            end
        end
        watching = false
    end)
end

--- The copy the player drives: what changes how it goes, as server/look.lua puts it on a run's car (the engine swap,
--- the handling setup, the drivetrain, the stance's ride height), through Tuning.wearCopy. Waits on the server for the
--- engine's figures (they are its own: server/engines.lua).
local function wearDriven(veh, look)
    CreateThread(function()
        local w = {}
        for _, k in ipairs(look) do
            local line = ShopGoal.unpack(k) or {}
            local slot = line.slot
            if slot == 'engine' and type(line.engine) == 'string' and line.engine ~= 'stock' then
                local data = Whip.call('Callback', 'whip_autos:engineData', line.engine)
                if type(data) == 'table' then w.engine = data end
            elseif slot == 'stance' then w.stance = TuningCleanStance(line.stance)
            elseif slot == 'setup' then w.setup = TuningCleanSetup(line.setup)
            elseif slot == 'drive' then w.drive = TuningCleanDrive(line.drive)
            end
        end
        if next(w) and DoesEntityExist(veh) then Tuning.wearCopy(veh, w) end
    end)
end

AddEventHandler('whip_core:director:builderCopy', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' or e.kind ~= 'vehicle' then return end
    local veh = math.tointeger(e.entity)
    if not veh or not DoesEntityExist(veh) or not IsEntityAVehicle(veh) then return end
    local data = type(e.data) == 'table' and type(e.data[GetCurrentResourceName()]) == 'table' and e.data[GetCurrentResourceName()] or {}
    local look = type(data.looks) == 'table' and type(e.model) == 'string' and data.looks[e.model] or nil
    if type(look) ~= 'table' then look = data.look end
    if type(look) ~= 'table' then return end
    for _, k in ipairs(look) do
        local line = ShopGoal.unpack(k)
        if line and line.slot == 'stance' then
            Tuning.drawStance(veh, line.stance)
            stanced[veh] = true
            watchStanced()
        elseif line and not NOT_SEEN[line.slot] then
            Catalogue.apply(veh, line.slot, line.index, line.wheelType)
        end
    end
    if e.driven == true then wearDriven(veh, look) end
end)

-- A copy of a networked car another game drives (whip_core's Experimental recorded drives sync: a take played on this
-- game's own copy): what we draw on a car from its VehicleData drawn on the copy too, its stance and its engine's sound.
-- Its parts and paint whip_core copied already.
AddEventHandler('whip_core:vehicle:copied', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    local copy, of = math.tointeger(e.entity), math.tointeger(e.of)
    if not copy or not of or not DoesEntityExist(copy) or not DoesEntityExist(of) then return end
    local stance = exports.whip_core:GetVehicleData({ entity = of }, TUNING_STANCE_KEY)
    if type(stance) == 'table' then
        Tuning.drawStance(copy, stance)
        stanced[copy] = true
        watchStanced()
    end
    local engine = exports.whip_core:GetVehicleData({ entity = of }, TUNING_ENGINE_KEY)
    if type(engine) == 'table' and type(engine.sound) == 'string' then Tuning.previewEngine(copy, engine.sound, engine.model) end
end)

-- ============================================
-- A way a Customise Vehicle goal asks for, picked on its card
-- ============================================
-- The goal's "The ways it may be" list (server/director.lua, an entries field): Pick a way in Whiplash adds one, Change
-- picks one again. The same copy of the goal's car as above; Save keeps the basket as that way (shared/goals.lua
-- ShopGoal.way: no sliders, its words for the card's row, the model it was picked on). A random vehicle's way is picked
-- on the first of its models no way is picked on yet (on the first, once each has one).

--- The model a new way is picked on: the car's, or a random vehicle's first without a way yet.
local function wayModel(car, ways)
    local list = type(car.models) == 'table' and #car.models > 0 and car.models or { car.model }
    local has = {}
    for _, w in ipairs(type(ways) == 'table' and ways or {}) do
        if type(w) == 'table' and type(w.model) == 'string' then has[w.model:lower()] = true end
    end
    for _, m in ipairs(list) do
        if type(m) == 'string' and not has[m:lower()] then return m end
    end
    return list[1]
end

Whip.directorButton('autos.exactWay', {
    label = 'Pick in Whiplash',
    icon = 'turbo',
    kinds = { 'card' },
    where = 'page',
    takesOver = true,
    hint = 'Whiplash on the goal\'s car: fit the way it must be, and Save.',
    press = function(thing)
        local card = type(thing.card) == 'table' and thing.card or {}
        local car = type(card.world) == 'table' and card.world.car or nil
        if type(car) ~= 'table' or type(car.model) ~= 'string' or car.model == '' then
            notify('Pick the goal\'s car first (Car, on the card)', 'error')
            thing:back()
            return
        end
        local was = type(card.value) == 'table' and card.value or nil
        local model = was and type(was.model) == 'string' and was.model or wayModel(car, card.props and card.props.ways)
        local look = edit(model, car.coords, was and was.look or nil)
        if look then
            local way = ShopGoal.way(look, model)
            if way then
                local done, why = thing:save(way)
                if done then notify(('A way on a %s: %d part%s'):format(model, #way.look, #way.look == 1 and '' or 's'), 'success')
                else notify('Could not keep the way: ' .. tostring(why), 'error') end
            else
                notify('Nothing picked: no way kept', 'info')
            end
        end
        thing:back()
    end,
})
