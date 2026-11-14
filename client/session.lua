-- A visit to Whiplash, from entering to leaving: the claim on the car, network control, the basket, the camera and
-- the controls held off. Previews are networked but never saved; only the server saves, after payment. Every exit
-- puts the car back to its stored look.

Session = {}

local active     = false
local vehicle    = nil     -- entity
local vehicleId  = nil     -- whip id
local basket     = {}      -- { { slot, index, wheelType, key, name, price, category }, ... }
local catalogue  = nil
local controlLost = false
local section    = nil     -- the Config.Sections entry open, for framing
local focusSlot  = nil     -- the category open (its slot)
local frozen     = false   -- the car is held still so the throttle can rev it (Engine Swap)
local holdTurn   = 0       -- bumped by every holdStill call, so a pending hold is called off
local anywhere   = false   -- opened with /whiplash: no shop floor to stay on
local builder    = false   -- opened on the world builder's car to set how it spawns (Session.openBuilder)
local saved      = nil     -- the look Save kept, until client/look.lua takes it (Session.takeLook)

--- Starts the visit's watch loop; defined with the loop further down.
local startLoops

-- Tuning slots (TUNING_SLOTS) preview locally through client/tuning.lua, so they need no network control.

--- Paint target -> appearance field, and the services (Repair), from shared/shop.lua.
local PAINT_PROP, SERVICES = SHOP_PAINT_PROP, SHOP_SERVICES

--- How the car looked on entry, so one slot can be put back when it leaves the basket.
local originalProps = nil

--- Every slot this visit has changed on the car; Session.revertAll undoes these.
local touched = {}

--- How often network control of the car is re-taken during a visit (another client can take it).
local CONTROL_TICK_MS = 1000

-- Calls into whip_core go through Whip.core (see fxmanifest.lua); opening waits on the server.

--- Tells the player why their visit ended.
local function notify(msg)
    Whip.core:Notify(msg, 'error')
end

-- What the shop holds off (whip_core BlockControls)

--- Holds controls off for the visit; the block is removed if this resource stops.
---   move, combat, vehicleCombat, driveBy   no walking off, shooting or aiming (aim is also the orbit button)
---   look                                   the gameplay camera under ours stays still
---   radio, weaponWheel                     the scroll wheel belongs to the shop's lists
---   71, 72, 75                             accelerate, brake, exit; accelerate is let through on the Engine Swap
---                                          screen once the car is held still (holdStill)
---   73, 74, 76, 80                         a pad's buttons in a car (the pad works the shop's screen)
--- Steering and Backspace stay free.
local function blockShopControls()
    Whip.core:BlockControls('shop', {
        groups   = { 'move', 'combat', 'vehicleCombat', 'driveBy', 'look', 'radio', 'weaponWheel' },
        controls = frozen and { 72, 73, 74, 75, 76, 80 } or { 71, 72, 73, 74, 75, 76, 80 },
    })
end

--- Is the throttle the engine's right now (Engine Swap, the car held still)?
---@return boolean
function Session.revving() return frozen end

-- Network control

--- Network control of the car through TakeVehicleControl; mod natives silently do nothing without it.
---@param veh number
---@param attempts number|nil
---@return boolean
local function takeControl(veh, attempts)
    -- The world builder's copy is this game's own: nobody else has it to take.
    if builder or NetworkHasControlOfEntity(veh) then return true end
    return Whip.core:TakeVehicleControl({ entity = veh }, { attempts = attempts or 3, wait = 600 }) == true
end

-- Opening and closing

function Session.isActive()  return active end
function Session.vehicle()   return vehicle end
function Session.vehicleId() return vehicleId end
function Session.catalogue() return catalogue end

--- Could the shop open now? Natives only, as the wheel asks every time it opens. The server re-checks on the claim.
---@param anyPlace boolean|nil  /whiplash: skip the shop floor (the server checks the ACE)
---@return boolean ok, string|nil reason
function Session.canEnter(anyPlace)
    if active then return false, 'You are already in Whiplash' end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return false, 'You need to be in a vehicle' end
    if GetPedInVehicleSeat(veh, -1) ~= ped then return false, 'Only the driver can use Whiplash' end

    local shop = Config.Shop
    if not anyPlace and #(GetEntityCoords(veh) - shop.coords) > shop.radius then
        return false, 'Drive onto the shop floor first'
    end

    return true
end

--- What every part this car takes comes to, told to the server (a Director goal's Check uses it).
local function sayMost(veh)
    local most = Catalogue.most(catalogue --[[@as table]])   -- built just before
    if most > 0 then TriggerServerEvent('whip_autos:server:carMost', GetEntityModel(veh) & 0xFFFFFFFF, most) end
end

--- Starts a visit: claims the car on the server, takes control, then sets up the page, camera and controls. Must run
--- in a thread (it waits on the server).
---@param opts table|nil  { anywhere = true } for /whiplash; { director = true }: the Director let them in
---@return boolean ok, string|nil reason
function Session.open(opts)
    local director = type(opts) == 'table' and opts.director == true
    local anyPlace = director or (type(opts) == 'table' and opts.anywhere == true)
    local ok, reason = Session.canEnter(anyPlace)
    if not ok then return false, reason end

    if not Whip.isReady() then return false, 'The framework is restarting — try again in a moment' end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    -- Adopts a street car the server has never seen.
    local vId, whyNot = Whip.core:ResolveVehicle(veh)
    if not vId then return false, whyNot or 'This vehicle cannot be modified' end

    -- The claim stops two players previewing on one car and lets the server restore it if this client vanishes.
    -- claimAnywhere (/whiplash) is for whip.devtools only, claimDirector for a car the Director let them into.
    local name = director and 'whip_autos:claimDirector' or anyPlace and 'whip_autos:claimAnywhere' or 'whip_autos:claim'
    local claimed, answer = Whip.core:Callback(name, vId)
    if not claimed then
        return false, answer or (director and 'Whiplash would not open here'
            or anyPlace and '/whiplash is a dev tool (whip.devtools, with developer mode on in /w)'
            or 'The shop would not take this vehicle')
    end
    local looksOnly, repairOnly = answer == 'looks', answer == 'repair'

    if not takeControl(veh) then
        TriggerServerEvent('whip_autos:server:release', vId)
        return false, 'Could not get control of the vehicle — try again'
    end

    active, vehicle, vehicleId = true, veh, vId
    anywhere = anyPlace
    basket, controlLost, section = {}, false, nil
    touched = {}
    catalogue = Catalogue.build(veh)
    sayMost(veh)   -- what the car takes, before the owner's shelves come off
    if repairOnly then
        catalogue = {}   -- no shelves: the counter keeps its services (Repair), and the page drops Customise
        Whip.core:Notify('Only its owner can customise this car: repairs only', 'info', 6000)
    elseif looksOnly then
        catalogue = Catalogue.looksOnly(catalogue)
        Whip.core:Notify('Only its owner can change this car\'s performance and tuning', 'info', 6000)
    end

    -- Taken after control and before any preview, so it is how the car arrived.
    originalProps = Whip.core:GetVehicleProperties({ entity = veh }) or nil   -- { entity = } because a bare number is a vehicleId

    -- Holds the car's stored look: if this resource stops before close(), whip puts it back.
    Whip.core:HoldVehicleAppearance(vId, true)

    -- whip's HUD, chat and prompts stand down for the shop's screen.
    Whip.core:SetScreenOpen(true, 'session')

    if UI and UI.setOpen then UI.setOpen(true) end   -- ui.lua loads after this file

    blockShopControls()

    Session.applyCameraChoice()   -- the standard camera or the part shots, before the camera starts
    Cam.start(veh, Config.Camera.default)
    startLoops()
    return true
end

-- The world builder's car

--- Opens Whiplash on this game's own copy of a Director car (client/look.lua): no claim and nothing bought. The page's
--- Save keeps the basket (Session.saveLook).
---@param veh number     a car only this game has
---@param lines table    its look so far, as basket lines
---@return boolean ok, string|nil reason
function Session.openBuilder(veh, lines)
    if active then return false, 'You are already in Whiplash' end
    if not veh or not DoesEntityExist(veh) then return false, 'The car is not there' end

    active, vehicle, vehicleId = true, veh, nil
    anywhere, builder, saved = true, true, nil
    basket, controlLost, section = {}, false, nil
    touched = {}
    catalogue = Catalogue.build(veh)
    sayMost(veh)
    originalProps = Whip.core:GetVehicleProperties({ entity = veh }) or nil

    for _, line in ipairs(lines or {}) do
        Session.preview(line.slot, line.index, line.wheelType, { engine = line.engine, stance = line.stance })
        Session.addToBasket(line)
    end

    Whip.core:SetScreenOpen(true, 'session')
    if UI and UI.setOpen then UI.setOpen(true) end
    blockShopControls()
    Session.applyCameraChoice()
    Cam.start(veh, Config.Camera.default)
    startLoops()
    return true
end

--- Is this visit the world builder's, setting how a car spawns?
function Session.isBuilder() return active and builder end

--- The page's Save: the basket as the car's look keeps it (ShopGoal.pack), and the visit ends.
function Session.saveLook()
    if not active or not builder then return end
    local out = {}
    for _, line in ipairs(basket) do
        local k = #out < ShopGoal.MAX_STANDARD and ShopGoal.pack(line, true) or nil
        if k then out[#out + 1] = k end
    end
    saved = out
    Session.close(true)
end

--- The look the last builder's visit saved, once; nil when it was left without saving.
---@return table|nil
function Session.takeLook()
    local s = saved
    saved = nil
    return s
end

--- Holds the car still for Engine Swap (so the throttle revs it), or lets it go. A frozen car's bonnet jumps, so
--- letting go is immediate and holding waits until the bonnet has stopped, at most 1.5 s.
---@param want boolean
local function holdStill(want)
    holdTurn = holdTurn + 1
    if not want then
        local was = frozen
        if frozen and vehicle and DoesEntityExist(vehicle) then FreezeEntityPosition(vehicle, false) end
        frozen = false
        if was then blockShopControls() end   -- throttle blocked again
        return
    end
    if frozen then return end

    local turn, veh = holdTurn, vehicle
    if not veh then return end
    CreateThread(function()
        local deadline, last = GetGameTimer() + 1500, -1.0
        while GetGameTimer() < deadline do
            Wait(100)
            if turn ~= holdTurn then return end
            local ratio = GetVehicleDoorAngleRatio(veh, 4)
            if ratio > 0.3 and math.abs(ratio - last) < 0.01 then break end   -- open, and still
            last = ratio
        end
        if turn ~= holdTurn or not active or veh ~= vehicle or not DoesEntityExist(veh) then return end
        FreezeEntityPosition(veh, true)
        frozen = true
        blockShopControls()   -- the throttle may rev it now
    end)
end

--- The engine bay's parts open the bonnet and the trunk's the boot while picked. The boot is shut again only if this opened it.
local BONNET_SLOTS = { [39] = true, [40] = true, [41] = true }
local BOOT_SLOTS = { [37] = true }
local bootOpened = false

--- Xenon colours only show with the headlights on: forced on while Xenon Lights is open, then handed back (0).
local lightsForced = false
local function lightsForXenons(want)
    if not vehicle or not DoesEntityExist(vehicle) then lightsForced = false return end
    if want and not lightsForced then
        local _, on = GetVehicleLightsState(vehicle)
        if on == 1 or on == true then return end   -- 1 or 0, and 0 is truthy in Lua
        SetVehicleLights(vehicle, 2)
        lightsForced = true
    elseif not want and lightsForced then
        SetVehicleLights(vehicle, 0)
        lightsForced = false
    end
end

--- Undoes everything a visit left behind. Every exit runs this, so it uses natives and Whip.core only.
---@param revert boolean  take the previewed parts back off
local function teardownLocal(revert)
    -- Let go first, so the car is never left frozen.
    holdStill(false)

    -- While we still hold control, so the parts come off for everyone.
    if revert then Session.revertAll() end

    -- (The appearance hold is released in close(); on the ugly exits whip releases it itself.)

    if vehicle and DoesEntityExist(vehicle) then
        SetVehicleDoorShut(vehicle, 4, false)
        if bootOpened then SetVehicleDoorShut(vehicle, 5, false) end
        -- Tuning previews always come off. Guarded: the controls, camera and page below must come back regardless.
        local ok, err = pcall(Tuning.clearPreviews, vehicle)
        if not ok then print(('[whip_autos] could not drop the tuning previews: %s'):format(tostring(err))) end
    end
    lightsForXenons(false)
    bootOpened = false
    focusSlot = nil

    -- If this resource is the one stopping, whip_core sweeps the block itself.
    Whip.core:UnblockControls('shop')

    Cam.stop()

    active, vehicle, vehicleId, anywhere, builder = false, nil, nil, false, false
    basket, catalogue, controlLost = {}, nil, false
    section, originalProps, touched = nil, nil, {}

    -- The page comes down here because every exit passes here; after the state is cleared.
    if UI and UI.setOpen then UI.setOpen(false) end
end

--- Leaves. `purchased`: the server has already saved the basket, so bought slots stay and other previews come off.
---@param purchased boolean|nil
function Session.close(purchased)
    if not active then return end

    local vId = vehicleId

    if purchased then
        for _, line in ipairs(basket) do touched[line.slot] = nil end
    end
    teardownLocal(true)

    -- After the revert, so whip's report on release describes the car as it now is.
    if vId then Whip.core:HoldVehicleAppearance(vId, false) end
    Whip.core:SetScreenOpen(false, 'session')

    -- Sent after a purchase too (the server has already ended it): one exit path.
    if vId then
        TriggerServerEvent('whip_autos:server:release', vId)
    end
end

-- The basket

function Session.basket() return basket end

--- Tries a choice on the car without buying it.
---@param slot number|string
---@param index number
---@param wheelType number|nil  which wheel range `index` refers to; wheels only
---@param tune table|nil  a tuning choice: { engine = model|'stock' } or { stance = {...} }
function Session.preview(slot, index, wheelType, tune)
    if not active or not vehicle then return false end

    -- A previewed repair would be a free repair.
    if SERVICES[slot] then return false end

    -- Tuning previews are local (client/tuning.lua): no control needed.
    if TUNING_SLOTS[slot] then
        tune = type(tune) == 'table' and tune or {}
        if slot == 'engine' then
            local model = type(tune.engine) == 'string' and tune.engine or nil
            if not model then return false end
            if model == 'stock' then Tuning.previewStockEngine(vehicle)
            else Tuning.previewEngine(vehicle, TuningEngineSound(model), model) end   -- the model: the rev dial's
        elseif slot == 'setup' or slot == 'drive' then
            -- Handling and drivetrain can only be felt on the road: nothing to preview.
            return true
        else
            if type(tune.stance) ~= 'table' then return false end
            Tuning.previewStance(vehicle, tune.stance)
        end
        touched[slot] = true
        return true
    end

    if not takeControl(vehicle, 1) then
        controlLost = true
        return false
    end
    controlLost = false

    -- Noted whether or not it is bought: previewing changed the car.
    touched[slot] = true

    -- The Livery shelf has both kinds (SHOP_MODEL_LIVERY): trying one puts the other back, so only the pick shows.
    if slot == 48 and not ShopModelLiveryOf(index) and originalProps and (originalProps.livery or -1) >= 0 then
        SetVehicleLivery(vehicle, originalProps.livery)
    end

    return Catalogue.apply(vehicle, slot, index, wheelType)
end

--- Adds a choice to the basket, replacing whatever that slot had (one line per slot; all wheel ranges share slot 23).
---@param line table  { slot, index, wheelType, key, name, price, category }
function Session.addToBasket(line)
    if not active or type(line) ~= 'table' then return false end
    if line.slot == nil or line.index == nil then return false end

    for i = #basket, 1, -1 do
        if basket[i].slot == line.slot then table.remove(basket, i) end
    end

    basket[#basket + 1] = {
        slot      = line.slot,
        index     = line.index,
        wheelType = line.wheelType,
        key       = line.key,
        name      = line.name,
        price     = line.price,
        category  = line.category,
        -- A tuning line carries its choice instead of an index.
        engine    = TUNING_SLOTS[line.slot] and type(line.engine) == 'string' and line.engine or nil,
        stance    = TUNING_SLOTS[line.slot] and type(line.stance) == 'table' and line.stance or nil,
        setup     = TUNING_SLOTS[line.slot] and type(line.setup) == 'table' and line.setup or nil,
        drive     = TUNING_SLOTS[line.slot] and type(line.drive) == 'table' and line.drive or nil,
    }
    return true
end

function Session.removeFromBasket(slot)
    for i = #basket, 1, -1 do
        if basket[i].slot == slot then table.remove(basket, i) end
    end
end

--- Puts one slot back to how the car arrived, from the entry snapshot. Works during teardown too.
---@param slot number|string
function Session.revertSlot(slot)
    if not vehicle or not originalProps then return end

    -- Services are never applied before payment.
    if SERVICES[slot] then return end

    -- Tuning: drop the preview; what the car has saved shows again.
    if slot == 'engine' then Tuning.previewEngine(vehicle, nil) return end
    if slot == 'stance' then Tuning.previewStance(vehicle, nil) return end
    if slot == 'setup' or slot == 'drive' then return end   -- never previewed

    if slot == 'tint' then
        Catalogue.apply(vehicle, 'tint', originalProps.windowTint or 0)
        return
    end

    -- Paint: 0 is a real colour, so a missing field is left alone rather than painted black.
    local prop = PAINT_PROP[slot]
    if prop then
        local was = originalProps[prop]
        if was ~= nil then Catalogue.apply(vehicle, slot, was) end
        return
    end

    -- Toggles are stored as named fields, not in `mods`.
    if slot == 18 then
        Catalogue.apply(vehicle, 18, originalProps.turbo and 1 or 0)
        return
    end
    if slot == 22 then
        Catalogue.apply(vehicle, 22, ShopXenonIndex(originalProps.xenon, originalProps.headlightColor))
        -- The colour too, xenons or not, or a previewed colour is reported on release as a change.
        SetVehicleHeadlightsColour(vehicle, originalProps.headlightColor or 255)
        return
    end
    if slot == 20 then
        Catalogue.apply(vehicle, 20, ShopSmokeIndex(originalProps.smokeEnabled, originalProps.tyreSmoke))
        -- The colour too, as for the xenons: a previewed colour left on is reported as a change.
        local c = originalProps.tyreSmoke
        if type(c) == 'table' then SetVehicleTyreSmokeColor(vehicle, c.r or 255, c.g or 255, c.b or 255) end
        return
    end

    -- An extra: as the car came in (left alone when that was not recorded).
    local extra = ShopExtraOf(slot)
    if extra then
        local was = nil   -- (not `and ... or nil`: an extra that was off is false)
        if type(originalProps.extras) == 'table' then was = originalProps.extras[tostring(extra)] end
        if was ~= nil then Catalogue.apply(vehicle, slot, was and 1 or 0) end
        return
    end

    -- A missing mod is stock (-1).
    local mods = originalProps.mods or {}

    -- Livery: the model livery too, which a model livery's preview changed (SHOP_MODEL_LIVERY).
    if slot == 48 then
        if (originalProps.livery or -1) >= 0 then SetVehicleLivery(vehicle, originalProps.livery) end
        Catalogue.apply(vehicle, 48, mods['48'] or -1)
        return
    end

    -- Wheels need their range back too, or the index fits a different wheel.
    local wheelType = nil
    if slot == 23 then wheelType = originalProps.wheelType end

    Catalogue.apply(vehicle, slot, mods[tostring(slot)] or -1, wheelType)
end

--- Puts every touched slot back. Natives only (it runs while this resource stops); takes control first.
---@return boolean
function Session.revertAll()
    if not vehicle or not DoesEntityExist(vehicle) or not originalProps then return false end
    if next(touched) == nil then return true end

    if not takeControl(vehicle, 2) then
        notify('Could not put the parts back — the server will')
        return false
    end

    -- One slot failing must not stop the rest, nor the way out (teardownLocal).
    for slot in pairs(touched) do
        local ok, err = pcall(Session.revertSlot, slot)
        if not ok then print(('[whip_autos] could not put slot %s back: %s'):format(tostring(slot), tostring(err))) end
    end
    touched = {}
    return true
end

--- Repairs the car after the server says the repair was paid for. Client natives, so it needs control.
---@return boolean
function Session.repair()
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    if not takeControl(vehicle, 2) then return false end

    SetVehicleFixed(vehicle)
    SetVehicleDeformationFixed(vehicle)
    SetVehicleUndriveable(vehicle, false)

    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)

    -- SetVehicleFixed does not always fix the tyres.
    for wheel = 0, 7 do
        SetVehicleTyreFixed(vehicle, wheel)
    end

    return true
end

--- Frames what is open: a category with a Config.Areas shot gets it; otherwise its shelf's framing, unless that is
--- false (camera stays).
local function frameFocus()
    local area = (focusSlot ~= nil) and Config.Areas[focusSlot] or nil
    local shelf = section and section.framing
    if area then
        Cam.setFraming(area)
    elseif shelf ~= false then
        Cam.setFraming(shelf or Config.Camera.default)
    end
end

--- What the player is looking at: frames the camera and opens or shuts the bonnet (up for Performance and Engine Swap).
---@param s table|nil          an entry from Config.Sections, or nil at the top level
---@param slot number|string|nil  the open category's slot
function Session.setFocus(s, slot)
    if not active then return end
    section = s
    focusSlot = slot

    frameFocus()

    if vehicle and DoesEntityExist(vehicle) then
        -- Engine Swap holds the car still so it can be revved; let go before the bonnet moves.
        local engineScreen = slot == 'engine'
        if not engineScreen then holdStill(false) end

        if (s and s.key == 'performance') or engineScreen or BONNET_SLOTS[slot] then
            SetVehicleDoorOpen(vehicle, 4, false, false)
        else
            SetVehicleDoorShut(vehicle, 4, false)
        end
        if BOOT_SLOTS[slot] then
            SetVehicleDoorOpen(vehicle, 5, false, false)
            bootOpened = true
        elseif bootOpened then
            SetVehicleDoorShut(vehicle, 5, false)
            bootOpened = false
        end

        if engineScreen then holdStill(true) end
        lightsForXenons(slot == 22)
    end
end

function Session.section() return section end

-- The standard camera: Config.Camera.followParts is the server's default; a player's own choice is kept on their PC (KVP).
local CAMERA_KVP = 'whip_autos:camera'

--- Is this player's camera the standard one (the orbit shot only)?
---@return boolean
function Session.standardCamera()
    local own = GetResourceKvpString(CAMERA_KVP)
    if own == 'standard' then return true end
    if own == 'parts' then return false end
    return Config.Camera.followParts == false
end

--- Puts the camera on this player's choice: at a visit's start, after the button, and when the default changes.
---@return boolean standard  the camera now
function Session.applyCameraChoice()
    local on = Session.standardCamera()
    local was = Cam.isStandard()
    Cam.setStandard(on)
    if was and not on and active then frameFocus() end
    return on
end

--- The page's Standard camera button: the other camera, kept as this player's own choice.
---@return boolean standard  the camera now
function Session.toggleStandardCamera()
    SetResourceKvp(CAMERA_KVP, Session.standardCamera() and 'parts' or 'standard')
    return Session.applyCameraChoice()
end

-- Keeping the visit honest

--- Bumped by every open, so a watch loop from an ended visit stops.
local loopTurn = 0

--- Once a second during a visit: the car exists, the player is in it and alive, it is on the floor, and control is
--- held. Anything else ends the visit.
---@param turn number
local function watchSession(turn)
    while active and turn == loopTurn do
        if not vehicle or not DoesEntityExist(vehicle) then
            notify('The vehicle is gone')
            Session.close(false)
            return
        end

        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) ~= vehicle then
            notify('You left the vehicle')
            Session.close(false)
            return
        end

        -- A dead ped still counts as in the seat. No message: being shot is its own.
        if IsEntityDead(ped) then
            Session.close(false)
            return
        end

        -- Pushed or towed off the floor, with 8 m of margin. A /whiplash visit has no floor.
        if not anywhere and #(GetEntityCoords(vehicle) - Config.Shop.coords) > Config.Shop.radius + 8.0 then
            notify('The vehicle left the shop floor')
            Session.close(false)
            return
        end

        -- Re-take control; previews silently stop working without it.
        if not NetworkHasControlOfEntity(vehicle) then
            if not takeControl(vehicle, 1) then
                if not controlLost then
                    controlLost = true
                    notify('Lost control of the vehicle — changes may not apply')
                end
            else
                controlLost = false
            end
        end

        Wait(CONTROL_TICK_MS)
    end
end

--- The page took or released the cursor. While it has it, the camera only turns while the orbit button is held.
---@param v boolean
function Session.setUiHasMouse(v)
    Cam.setMouseShared(v)
end

-- The page hides its cursor while the camera has the mouse (the page never sees the right mouse button).
Cam.onInputChange(function(listening)
    if UI and UI.setCursorHidden then UI.setCursorHidden(listening) end
end)

--- Starts the visit's watch loop. Controls are held by whip_core, so this is the only loop of our own.
startLoops = function()
    loopTurn = loopTurn + 1
    local turn = loopTurn
    CreateThread(function() watchSession(turn) end)
end

-- Exits nobody chose

--- This resource stopping: put the car back now (the server restores it too, but later).
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active then
        teardownLocal(true)
    end
end)
