-- whip_autos server: decides who may work on which car (sessions) and takes the money. Sessions exist because the
-- client can vanish mid-preview, leaving networked parts nobody paid for; the server puts the car back.

--- Open sessions: [vehicleId] = { source, charId, startedAt, anywhere }. One per car, one car per player.
local sessions = {}

--- Read by the other server files (server/director.lua: a Whiplash visit's word is believed only during one).
AutosSessions = {}

--- The car `source` has a session open on now (its vehicleId), or nil.
---@return number|nil
function AutosSessions.carOf(source)
    for vehicleId, s in pairs(sessions) do
        if s.source == source then return vehicleId end
    end
    return nil
end

--- Puts a car back to its stored look (RestoreVehicleAppearance), which every abnormal ending needs. A car that no
--- longer exists is fine.
---@param vehicleId number
local function restore(vehicleId)
    if not Whip.core:GetVehicle(vehicleId) then return end

    local ok, err = Whip.core:RestoreVehicleAppearance(vehicleId)
    if not ok then
        print(('[whip_autos] could not restore vehicle #%s: %s')
            :format(tostring(vehicleId), tostring(err)))
    end
end

--- Ends a session and puts the car back.
---@param vehicleId number
local function endSession(vehicleId)
    if not sessions[vehicleId] then return end
    sessions[vehicleId] = nil
    restore(vehicleId)
end

--- Is the session's owner still driving that car? A session is only real while they are.
---@param vehicleId number
---@param s table
---@return boolean
local function holderPresent(vehicleId, s)
    return exports.whip_core:IsPlayerDrivingVehicle(s.source, vehicleId) == true
end

-- Claiming a car

--- 'whip_autos:claim': start a session. Refuses a car someone else is working on with `false, 'why'`. Taken, it
--- answers `true, may` (Config.WhoCanModify): 'all'; 'looks' when only the owner may change performance and tuning;
--- 'repair' when only the owner may customise at all. onPurchase refuses what they may not buy anyway. `director`:
--- opened by a Director card or task, which lets it off the floor.
local function onClaim(source, player, vehicleId, anywhere, director)
    local def = exports.whip_core:GetVehicle(vehicleId)
    if not def then return false, 'That vehicle is gone' end

    -- Checked here, not taken from the client.
    if not exports.whip_core:IsPlayerDrivingVehicle(source, vehicleId) then
        return false, 'Only the driver can use Whiplash'
    end

    local may = ShopMayChange(player.charId, def.owner and def.owner.charId)

    -- One car per player: a session left behind without a clean release ends now.
    for otherId, other in pairs(sessions) do
        if other.source == source and otherId ~= vehicleId then
            endSession(otherId)
        end
    end

    local existing = sessions[vehicleId]
    if existing and existing.source ~= source then
        -- Another player's claim only counts while they are still in the seat.
        if holderPresent(vehicleId, existing) then
            return false, 'Somebody is already working on this vehicle'
        end
        endSession(vehicleId)
    end

    sessions[vehicleId] = {
        source    = source,
        charId    = player.charId,
        startedAt = os.time(),
        -- Opened with /whiplash or by the Director: its floor is wherever the car is (SHOP_NEAR).
        anywhere  = anywhere == true or nil,
        director  = director == true or nil,
    }
    return true, may
end

--- 'whip_autos:server:release': the player left. After a purchase the session is already gone.
local function onRelease(source, _, vehicleId)
    local s = sessions[vehicleId]
    if not s or s.source ~= source then return end

    endSession(vehicleId)
end

-- Paying

--- Every priced slot, from the same Config the client reads. The client only labels with it; this
--- charges with it, so a player editing their copy changes nothing.
local priceBySlot = {}

--- The paints the palette lists, as a set of GTA's paint numbers.
local VALID_COLOUR = {}

--- The tint values that exist, as a set (GTA's indices, not list positions).
local VALID_TINT = {}

--- Built from Config, and again when an admin changes a list or price in /whip (shared/settings.lua).
local function buildLookups()
    priceBySlot, VALID_COLOUR, VALID_TINT = {}, {}, {}
    for _, list in ipairs({ Config.Cosmetics, Config.Wheels, Config.Performance, Config.Toggles,
                            Config.PaintTargets, Config.PaintExtras, Config.Services }) do
        for _, def in ipairs(list) do priceBySlot[def.id] = def.price end
    end
    priceBySlot['tint'] = Config.WindowTints.price
    -- The Extras shelf: 'extra1' to 'extra14', every switch one price (shared/shop.lua ShopExtraOf).
    for n = 1, SHOP_EXTRA_LAST do priceBySlot['extra' .. n] = (Config.Extras and Config.Extras.price) or 0 end
    for _, c in ipairs(Config.Colours) do VALID_COLOUR[c.index] = true end
    for _, o in ipairs(Config.WindowTints.options) do VALID_TINT[o.index] = true end
end
buildLookups()
for _, path in ipairs({ 'Cosmetics', 'Wheels', 'Performance', 'Toggles', 'PaintTargets', 'PaintExtras',
                        'Services', 'WindowTints', 'Colours', 'Extras' }) do
    Whip.onConfigChanged(path, buildLookups)
end

--- Paint target -> stored field (shared/shop.lua); also the test for "is this slot a colour".
local PAINT_PROP = SHOP_PAINT_PROP

--- Services (Repair), from shared/shop.lua: no index, no mod slot.
local SERVICES = SHOP_SERVICES

--- Highest wheel type GTA has.
local MAX_WHEEL_TYPE = 12

--- What one basket line costs. Stock (taking a part off) is always free.
---@param slot number|string
---@param index number
---@param props table|nil  the car's stored appearance (xenons: a colour change on fitted ones is cheaper)
---@return number
local function priceOf(slot, index, props)
    if index == -1 then return 0 end                          -- no part fitted
    if slot == 'tint' and index == 4 then return 0 end        -- stock glass
    if slot == 18 then                                        -- the turbo: each stage its own price, off free
        local s = PowerTurbo.stages[index]
        return s and s.price or 0
    end
    if slot == 22 then                                        -- xenons: off is free; see SHOP_XENON_COLOUR
        if index == 0 then return 0 end
        if type(props) == 'table' and props.xenon then return Config.XenonColours.colourPrice end
    end
    if slot == 20 then                                        -- tyre smoke the same way; see SHOP_SMOKE_COLOUR
        if index == 0 then return 0 end
        if type(props) == 'table' and props.smokeEnabled then return Config.TyreSmokeColours.colourPrice end
    end
    return priceBySlot[slot] or 0
end

-- Money goes through whip_core's ChargePlayer / RefundPlayer (in onPurchase), never by hand.

--- Turns a validated basket into the appearance to store, from slots and indices only.
---@param basket table
---@return table props
local function propsFromBasket(basket)
    local props = { mods = {} }

    for _, line in ipairs(basket) do
        local slot, index = line.slot, line.index

        if line.tuning then
            -- Stored as VehicleData by TuningServer.write, not appearance.
        elseif SERVICES[slot] then
            -- The wash half of a repair is stored appearance (dirt); the repair itself is done by the
            -- client (purchaseResult's `repairing`).
            props.dirtLevel = 0.0
        elseif slot == 'tint' then
            props.windowTint = index
        elseif PAINT_PROP[slot] then
            props[PAINT_PROP[slot]] = index
        elseif slot == 18 then
            props.turbo = index >= 1   -- GTA's part, for the sound, with any stage (the stage itself is tuning data)
        elseif slot == 22 then
            props.xenon = index >= 1
            if index >= 1 then props.headlightColor = SHOP_XENON_COLOUR[index] end
        elseif slot == 20 then
            props.smokeEnabled = index >= 1
            local c = index >= 1 and SHOP_SMOKE_COLOUR[index]
            if c then props.tyreSmoke = { r = c.r, g = c.g, b = c.b } end
        elseif ShopExtraOf(slot) then
            -- Merged into the car's own by SetVehicleAppearance: the other extras stay as they are.
            props.extras = props.extras or {}
            props.extras[tostring(ShopExtraOf(slot))] = index == 1
        elseif slot == 48 and ShopModelLiveryOf(index) then
            -- A model livery, with the mod livery off so it shows (SHOP_MODEL_LIVERY).
            props.livery = ShopModelLiveryOf(index)
            props.mods['48'] = -1
        else
            props.mods[tostring(slot)] = index

            -- A wheel index only means something with its range, so wheel lines store wheelType.
            if line.wheelType and (slot == 23 or slot == 24) then props.wheelType = line.wheelType end
        end
    end

    return props
end

--- The same, for a Director car's look (server/look.lua): its lines checked there.
function ShopPropsFromLines(lines)
    return propsFromBasket(lines)
end

--- 'whip_autos:server:purchase': re-prices the basket from scratch, charges, writes tuning and parts in
--- one write, and refunds if it fails. A refusal is `false, 'why'` (whip shows it); purchaseResult tells the page.
local function onPurchase(source, player, vehicleId, method, basket, shown)
    local function fail(msg)
        TriggerClientEvent('whip_autos:client:purchaseResult', source, false, msg)
        return false, msg
    end

    -- The basket's shape was checked by the 'list' param; what each line means is checked here.
    if #basket == 0 then return fail('Nothing in the basket') end

    -- The session is the permission: this player claimed this car and has not left it.
    local s = sessions[vehicleId]
    if not s or s.source ~= source then return fail('You are not working on that vehicle') end

    if not exports.whip_core:IsPlayerDrivingVehicle(source, vehicleId) then
        return fail('You must stay in the vehicle')
    end

    local def = exports.whip_core:GetVehicle(vehicleId)
    if not def then return fail('That vehicle is gone') end

    -- Asked again, not kept from the claim: the car may have changed hands, or the rule in /whip, since.
    local may = ShopMayChange(player.charId, def.owner and def.owner.charId)
    local looksOnly, repairOnly = may == 'looks', may == 'repair'

    -- One line per slot; a repeat is dropped.
    local seen, lines, total = {}, {}, 0
    -- Tuning lines are priced by server/tuning.lua and stored as VehicleData.
    local tuningChanges = {}
    -- The turbo the car has now (its stage's place in Config.Turbo.Stages, 0 for none): the Turbo line (slot 18) is a
    -- stage, kept as tuning data rather than in the look.
    local turbo = exports.whip_core:GetVehicleData(vehicleId, TUNING_TURBO_KEY)
    local turboIndex = TuningTurboIndex(turbo)
    for _, line in ipairs(basket) do
        local slot  = line.slot
        local index = tonumber(line.index)

        -- Only the owner's to change: the page never offers it, so only a modified game sends it.
        if (repairOnly and not SERVICES[slot]) or (looksOnly and ShopIsPerformance(tonumber(slot) or slot)) then
            print(('[whip_autos] char %s asked for slot %s on a car only its owner may change that way — dropped')
                :format(tostring(player.charId), tostring(slot)))
            goto nextLine
        end

        if TUNING_SLOTS[slot] and not seen[slot] then
            local price, change = TuningServer.price(vehicleId, line)
            if price == nil then
                print(('[whip_autos] char %s tuning line %s refused: %s'):format(tostring(player.charId), slot, tostring(change)))
            elseif change == nil then
                print(('[whip_autos] char %s asked for the %s the car already has — dropped'):format(tostring(player.charId), slot))
            else
                seen[slot] = true
                total = total + price
                tuningChanges[#tuningChanges + 1] = change
                -- What a Director goal reads off it (shared/goals.lua): the engine fitted, the drivetrain chosen.
                lines[#lines + 1] = {
                    slot = slot, tuning = true, price = price,
                    engine = slot == 'engine' and line.engine:lower() or nil,
                    layout = slot == 'drive' and type(change.value) == 'table' and change.value.layout or nil,
                }
            end
            goto nextLine
        end

        -- 'tint' and the paint targets are named slots; anything else must be a mod slot number.
        if priceBySlot[slot] == nil then slot = tonumber(slot) end

        local ok = slot ~= nil and index ~= nil and priceBySlot[slot] ~= nil
            and not seen[tostring(slot)]

        -- Each kind has its own valid range; an out-of-range index would be stored and re-applied.
        if ok then
            ---@cast index -nil -- ok: checked above
            if SERVICES[slot] then
                index = 1   -- a service is bought or not; the index is pinned
            elseif PAINT_PROP[slot] then
                ok = VALID_COLOUR[math.floor(index)] == true
            elseif slot == 'tint' then
                ok = VALID_TINT[index] == true
            elseif slot == 18 then
                ok = index >= 0 and index <= #PowerTurbo.stages    -- Off, or one of the turbo stages
            elseif slot == 22 then
                ok = index >= 0 and index <= #SHOP_XENON_COLOUR   -- Off, or one of the colours
            elseif slot == 20 then
                ok = index >= 0 and index <= #SHOP_SMOKE_COLOUR   -- the same for tyre smoke
            elseif ShopExtraOf(slot) then
                ok = index == 0 or index == 1                      -- an extra: off or on
            else
                ok = type(slot) == 'number' and slot >= 0 and slot <= 49
                    and ((index >= -1 and index < 100) or (slot == 48 and ShopModelLiveryOf(index) ~= nil))
            end
        end

        -- wheelType is optional, valid only on wheel lines (slot 23/24) and only within range.
        local wheelType = tonumber(line.wheelType)
        if ok and wheelType ~= nil then
            wheelType = math.floor(wheelType)
            ok = wheelType >= 0 and wheelType <= MAX_WHEEL_TYPE
            if ok and slot ~= 23 and slot ~= 24 then ok = false end
        end

        if ok then
            ---@cast slot -nil -- ok: both checked above
            ---@cast index -nil
            index = math.floor(index)

            -- Already on the car (its STORED look, not the entity, which is wearing the preview): dropped, so the rest of
            -- the basket still goes through.
            if ShopFitted(def.properties, { slot = slot, index = index, wheelType = wheelType }, turboIndex) then
                print(('[whip_autos] char %s tried to buy slot %s index %d, already fitted — dropped')
                    :format(tostring(player.charId), tostring(slot), index))
            else
                seen[tostring(slot)] = true
                local price = priceOf(slot, index, def.properties)
                total = total + price
                lines[#lines + 1] = { slot = slot, index = index, wheelType = wheelType, price = price }
                -- A turbo stage is written as tuning data with the rest of the order (GTA's part goes on with it, in
                -- the look); Off clears it. The boost stat follows the data (server/power/turbo.lua).
                if slot == 18 then
                    local stage = PowerTurbo.stages[index]
                    tuningChanges[#tuningChanges + 1] = { key = TUNING_TURBO_KEY, value = stage and { psi = stage.psi } or nil }
                end
            end
        end
        ::nextLine::
    end

    -- The repair half only a client can do (Session.repair).
    local repairing = false
    for _, l in ipairs(lines) do
        if l.slot == 'repair' then repairing = true end
    end

    if #lines == 0 then return fail('Nothing in the basket') end

    -- A Director goal on this car pays for the parts it asks for, up to its spend (server/director.lua): what it
    -- pays of each line comes off
    local paid = DirectorGoals.cover(vehicleId, source, lines, function(l) return l.price end)
    for i, l in ipairs(lines) do
        if paid[i] then total = total - math.min(l.price, paid[i]) end
    end

    -- Never more than the page showed: a price raised in /whip while they were here is refused, not
    -- charged. Less is fine (a line already on the car is dropped above). -1: a page that sent none.
    if shown >= 0 and total > shown then
        return fail('The prices changed while you were here. Leave and come back to see them.')
    end

    -- Paid before fitted: a failed fit is refunded. The payment is held and lands with the fitting write, so a crash
    -- between paying and fitting keeps neither.
    local receipt
    if total > 0 then
        local payErr
        receipt, payErr = exports.whip_core:ChargePlayer(source, total, {
            method = method == 'bank' and 'bank' or 'cash',
            reason = 'Whiplash customisation',
        })
        if not receipt then return fail(payErr or 'Payment failed') end
    end

    -- The parts and the tuning in ONE write, with the payment: all of it or none.
    local hasParts = false
    for _, l in ipairs(lines) do
        if not l.tuning then hasParts = true end
    end
    -- A tuning-only order sends no parts: the stored look is written back as it is.
    local ok, err = TuningServer.write(vehicleId, tuningChanges, hasParts and propsFromBasket(lines) or {})
    if not ok then
        if not receipt then return fail('Something went wrong fitting that') end
        local refunded = exports.whip_core:RefundPlayer(receipt)

        print(('[whip_autos] %s $%d to %s — the order\'s write failed: %s')
            :format(refunded and 'refunded' or 'COULD NOT REFUND', total, tostring(player.charId), tostring(err)))
        if not refunded then
            return fail('Something went wrong fitting that, and the refund failed — tell an admin')
        end
        return fail('Something went wrong fitting that — you have been refunded')
    end

    -- A repair clears the damage whip keeps on the car, or its next spawn puts it back. The car itself
    -- is fixed by the client (Session.repair).
    if repairing then
        local cleared, clearErr = exports.whip_core:ClearVehicleDamage(vehicleId)
        if not cleared then
            print(('[whip_autos] repaired #%s but could not clear its kept damage: %s')
                :format(tostring(vehicleId), tostring(clearErr)))
        end
    end

    -- A car with no saved record keeps the work only while it exists; the buyer is told.
    if def.session then
        exports.whip_core:NotifyPlayer(source, 'This car is not yours to keep: the work lasts as long as the car does', 'info', 8000)
    end

    -- Ended without a restore: the stored look is now what is on the car.
    sessions[vehicleId] = nil

    -- (No print of the sale: ChargePlayer logs it in whip's activity log.)

    -- A Director goal's checklist ticks off what this order did (and may be done).
    DirectorGoals.purchased(vehicleId, source, lines)

    -- The repair flag rides on the result, so it arrives before the client lets go of the car.
    TriggerClientEvent('whip_autos:client:purchaseResult', source, true, nil, total, repairing)
end

-- Registering with whip_core: SecureEvent/SecureCallback live inside whip_core, so they are declared in
-- RegisterWithWhip, which Whip.register runs once whip_core is ready.

--- Claims and purchases must be made on the shop floor (its radius + 4 m). A /whiplash session's floor is wherever
--- its car is, for the whip.devtools player who opened it; a session the Director opened has the same floor.
local SHOP_NEAR = {
    at = function(src, _, vehicleId)
        local s = vehicleId and sessions[vehicleId]
        -- HasDevTools, not the ACE: whip.devtools counts only with developer mode on (/w).
        if s and s.anywhere and s.source == src and (s.director or exports.whip_core:HasDevTools(src) == true) then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then return GetEntityCoords(ped) end
        end
        return Config.Shop.coords.x, Config.Shop.coords.y, Config.Shop.coords.z
    end,
    -- Asked at each call, so a floor resized in /whip counts at once.
    range   = function() return (Config.Shop.radius or 6.0) + 4.0 end,
    message = 'Drive onto the Whiplash floor first',
}

local function RegisterWithWhip()
    exports.whip_core:SecureCallback('whip_autos:claim', {
        rateLimit = 1000,
        near      = SHOP_NEAR,
        params = {
            { 'vehicleId', 'id' },   -- refused, not clamped, when it is not a valid id
        },
    }, onClaim)

    -- /whiplash: the same claim without the floor, whip.devtools only.
    exports.whip_core:SecureCallback('whip_autos:claimAnywhere', {
        ace       = 'whip.devtools',
        rateLimit = 1000,
        params = {
            { 'vehicleId', 'id' },
        },
    }, function(source, player, vehicleId)
        return onClaim(source, player, vehicleId, true)
    end)

    -- A Director card or task opened it for them (server/director.lua): the same claim without the floor,
    -- for a car the Director has let them into.
    exports.whip_core:SecureCallback('whip_autos:claimDirector', {
        rateLimit = 1000,
        params = {
            { 'vehicleId', 'id' },
        },
    }, function(source, player, vehicleId)
        local grant, netId = DirectorGoals.grantFor(source, vehicleId)
        if not grant then return false, 'Whiplash can only be opened on the shop floor' end
        ---@cast netId -nil -- it comes with the grant
        local ok, why = onClaim(source, player, vehicleId, true, true)
        if ok then DirectorGoals.claimed(source, grant, netId) end
        return ok, why
    end)

    exports.whip_core:SecureEvent('whip_autos:server:release', {
        whileDead = true,   -- dying mid-visit must still free the car
        -- A refused release leaves the car claimed, so it gets a burst.
        rateLimit = 500, burst = 3,
        params = {
            { 'vehicleId', 'id' },
        },
    }, onRelease)

    exports.whip_core:SecureEvent('whip_autos:server:purchase', {
        -- burst 2: paying by bank right after cash was refused is not eaten by the cooldown.
        rateLimit = 3000, burst = 2,
        near      = SHOP_NEAR,
        -- A refusal before onPurchase runs (cooldown, distance, bad param) still answers the page.
        onReject = function(src, why)
            TriggerClientEvent('whip_autos:client:purchaseResult', src, false, tostring(why))
        end,
        params = {
            { 'vehicleId', 'id' },
            { 'method', 'enum', { 'cash', 'bank' } },
            -- At most 40 lines. `index` is refused, not clamped ('id', from -1 = stock); `slot` and
            -- `wheelType` are checked in onPurchase; the tuning fields by server/tuning.lua.
            { 'basket', 'list', {
                { 'slot',      'any' },
                { 'index',     'id', -1, 255 },
                { 'wheelType', 'any' },
                { 'engine',    'any' },
                { 'stance',    'any' },
                { 'setup',     'any' },
                { 'drive',     'any' },
            }, 40 },
            { 'shown', 'int', 0, 1000000000, -1 },
        },
    }, onPurchase)

    -- The player's cash for the basket bubble: the first figure on open, and re-checks. Every change is
    -- also pushed as it happens (cashMoved). A refusal just keeps the page's last figure.
    exports.whip_core:SecureCallback('whip_autos:cash', {
        rateLimit = 500, burst = 2,
    }, function(source)
        return (exports.whip_core:GetPlayerCash(source))
    end)
end

Whip.register(RegisterWithWhip)

-- Endings nobody chose

--- The player disconnected: put their car back.
AddEventHandler('playerDropped', function()
    local src = source
    for vehicleId, s in pairs(sessions) do
        if s.source == src then
            endSession(vehicleId)
        end
    end
end)

--- This resource stopping: put every car back while the sessions are still known.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        for vehicleId in pairs(sessions) do
            restore(vehicleId)
        end
        sessions = {}
    end
end)

--- A session ends when its owner leaves the driver's seat (whip_core's vehicle events). Usually the
--- client's own release gets there first.
---@param e table  { source, vehicleId, seat }
local function leftTheWheel(e)
    local s = sessions[e.vehicleId]
    if not s or s.source ~= e.source then return end
    endSession(e.vehicleId)
end

-- These whip_core events are believed from anyone: a forged one can only end a visit early, which puts the car back,
-- or push a wrong cash figure to the page.
AddEventHandler('whip_core:vehicle:exited', leftTheWheel)

AddEventHandler('whip_core:vehicle:entered', function(e)
    -- Moved to another seat in the same car.
    if e.seat ~= -1 then leftTheWheel(e) end
end)

--- A shopper's cash moved (whip_core's item events, any route): push the new count to their page.
---@param e table  { source, item, amount, count, reason, by }
local function cashMoved(e)
    if e.item ~= 'cash' then return end
    for _, s in pairs(sessions) do
        if s.source == e.source then
            TriggerClientEvent('whip_autos:client:cash', e.source, e.count)
            return
        end
    end
end

AddEventHandler('whip_core:item:added', cashMoved)
AddEventHandler('whip_core:item:removed', cashMoved)

--- Who is in the shop now, for admin tools.
exports('GetOpenSessions', function()
    local out = {}
    for vehicleId, s in pairs(sessions) do
        out[#out + 1] = {
            vehicleId = vehicleId,
            source    = s.source,
            charId    = s.charId,
            startedAt = s.startedAt,
        }
    end
    return out
end)

-- One line in the console once everything has registered: started, or what went wrong.
Whip.sayStarted()
