-- ============================================
-- whip_autos — a Director car's look, put on it when the scenario makes it
-- ============================================
-- The Whiplash button in the Director's world builder (client/look.lua) keeps a LOOK on a placed car: the parts,
-- paint and tuning it comes out with. whip_core says each time the scenario makes a placed thing
-- (whip_core:run:thingMade: a run's Spawn Car, a take's car, the Always present layer, a builder's Test), with what
-- each resource keeps on it; a car with our look gets it here, in one write (TuningServer.write: the parts as its
-- appearance, the engine swap, stance, handling setup and drivetrain as our VehicleData, which client/tuning.lua puts on
-- it), as a paid Whiplash order is.

local CORE = 'whip_core'

--- A look's lines as an order's: parts checked as server/main.lua checks a basket's (a slot whip knows, an index in
--- its range), tuning cleaned as server/tuning.lua cleans it. Anything else is dropped.
---@param look table  the kept lines (shared/goals.lua ShopGoal.pack)
---@return table parts, table changes
local function orderOf(look)
    local parts, changes = {}, {}
    for _, k in ipairs(look) do
        local line = ShopGoal.unpack(k) or {}
        local slot = line.slot
        if slot == 'engine' then
            local data = line.engine ~= 'stock' and Engines.data(line.engine) or nil
            if data then changes[#changes + 1] = { key = TUNING_ENGINE_KEY, value = data } end
        elseif slot == 'stance' then
            local clean = TuningCleanStance(line.stance)
            if clean then changes[#changes + 1] = { key = TUNING_STANCE_KEY, value = clean } end
        elseif slot == 'setup' then
            local clean = TuningCleanSetup(line.setup)
            if clean then changes[#changes + 1] = { key = TUNING_SETUP_KEY, value = clean } end
        elseif slot == 'drive' then
            local clean = TuningCleanDrive(line.drive)
            if clean then changes[#changes + 1] = { key = TUNING_DRIVE_KEY, value = clean } end
        elseif slot == 18 then
            -- The turbo: a stage (1..) as tuning data with GTA's part for the sound, or Off (0), as an order fits it
            -- (server/main.lua). An index past the stages sold now is dropped.
            local index = line.index
            local s = index and index >= 1 and PowerTurbo.stages[index] or nil
            if index == 0 or s then
                parts[#parts + 1] = { slot = 18, index = index }
                changes[#changes + 1] = { key = TUNING_TURBO_KEY, value = s and { psi = s.psi } or nil }
            end
        elseif slot ~= nil and not SHOP_SERVICES[slot] then
            local index, ok = line.index, false
            if SHOP_PAINT_PROP[slot] or slot == 'tint' then
                ok = index >= 0 and index <= 255
            elseif slot == 22 then
                ok = index >= 0 and index <= #SHOP_XENON_COLOUR
            elseif slot == 20 then
                ok = index >= 0 and index <= #SHOP_SMOKE_COLOUR
            elseif ShopExtraOf(slot) then
                ok = index == 0 or index == 1   -- an extra: off or on
            elseif type(slot) == 'number' then
                ok = slot >= 0 and slot <= 49
                    and ((index >= -1 and index < 100) or (slot == 48 and ShopModelLiveryOf(index) ~= nil))
            end
            if ok then parts[#parts + 1] = { slot = slot, index = index, wheelType = line.wheelType } end
        end
    end
    return parts, changes
end

AddEventHandler('whip_core:run:thingMade', function(e)
    -- (Any resource can fire an event by this name: only whip_core's is believed.)
    if GetInvokingResource() ~= CORE or type(e) ~= 'table' or e.kind ~= 'vehicle' then return end
    local mine = type(e.data) == 'table' and e.data[GetCurrentResourceName()] or nil
    -- A random vehicle keeps a look for each of its models (looks[model]): the one it was made as.
    local looks = type(mine) == 'table' and type(mine.looks) == 'table' and mine.looks or nil
    local look = looks and type(e.model) == 'string' and looks[e.model] or nil
    if type(look) ~= 'table' then look = type(mine) == 'table' and type(mine.look) == 'table' and mine.look or nil end
    local vehicleId = tonumber(e.vehicleId)
    if not look or #look == 0 or not vehicleId then return end

    local parts, changes = orderOf(look)
    if #parts == 0 and #changes == 0 then return end
    local ok, err = TuningServer.write(vehicleId, changes, #parts > 0 and ShopPropsFromLines(parts) or {})
    if not ok then
        print(('[whip_autos] %s (#%s) could not be given its Whiplash look: %s')
            :format(tostring(e.label or e.world), tostring(vehicleId), tostring(err)))
    end
end)
