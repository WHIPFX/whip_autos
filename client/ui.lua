-- ============================================
-- whip_autos — the screen
-- ============================================
-- Glue between the NUI page (html/) and the session. The page only draws; the server re-checks every
-- price and permission when the basket is paid for.
--
-- Focus goes through whip_core's pad screen helper (Whip.padScreen, keepInput 'always'): the page gets the cursor
-- and the game still sees controls, so the camera can orbit with the right mouse button while the page is up.

local open = false

-- Has the page said it drew? main.lua's fallback exit asks. Reset on every open.
local pageShown = false

-- ============================================
-- A controller
-- ============================================
-- whip's pad reader for screens (Whip.padScreen): its presses go to the page ('pad'), which works the
-- shop the way the keys do (app.js padPress). On a pad the cursor goes and the camera is the right
-- stick's all the time (camera.lua); the mouse moving brings the cursor back. Game input stays with the
-- mouse too (the camera's orbit, the engine's throttle), except while the engine search types. The
-- session holds the world's controls off itself.
local screen = Whip.padScreen({
    buttons   = { 'up', 'down', 'left', 'right', 'a', 'b', 'x', 'y', 'rb' },   -- RB: the Standard camera button
    keepInput = 'always',
    block     = false,
    onDevice  = function(pad)
        -- On a pad the camera listens to the right stick all the time; with the mouse, only while held.
        Session.setUiHasMouse(not pad)
        SendNUIMessage({ action = 'padDevice', pad = pad })
    end,
})

--- Asks the server for the player's cash ('whip_autos:cash', server/main.lua) and sends it to the page.
--- The server also pushes every change (whip_autos:client:cash, below); this gives the first figure
--- and re-checks. One question at a time: asked again while one is out, it asks once more after.
local cashAsking, cashAgain = false, false

local function refreshCash()
    if not open then return end
    if cashAsking then cashAgain = true return end
    cashAsking = true
    CreateThread(function()
        repeat
            cashAgain = false
            local cash = tonumber((Whip.core:Callback('whip_autos:cash')))
            -- A refusal or no answer keeps the figure the page already has.
            if open and cash then SendNUIMessage({ action = 'cash', cash = cash }) end
            if cashAgain then Wait(500) end
        until not cashAgain or not open
        cashAsking = false
    end)
end

--- The palette and engine list go to the page once; the page keeps them for later visits. A change to
--- either in /whip sends them again on the next visit.
local listsSent = false
for _, path in ipairs({ 'Colours', 'PaintFamilies', 'Tuning.HiddenEngineClasses', 'Tuning.SoundOnlyEngineClasses' }) do
    Whip.onConfigChanged(path, function() listsSent = false end)
end

--- Sends the catalogue to the page and takes the cursor.
local function show()
    if open then return end
    open = true
    pageShown = false

    local msg = {
        action    = 'open',
        catalogue = Session.catalogue() or {},
        sections  = Config.Sections,
        basket    = Goals.dress(Session.basket()),
        services  = Config.Services,   -- Repair: the same for every car
        job       = Goals.model(),      -- a Director goal's checklist (client/director.lua), or none
        builder   = Session.isBuilder(),   -- setting how a Director car spawns (client/look.lua): Save, not pay
        standardCam = Session.standardCamera(),   -- the Standard camera button's state
    }
    if not listsSent then
        msg.palette = Catalogue.palette()
        msg.engines = Tuning.engineList()
        -- No engine list yet (the server did not answer): send both again next visit.
        listsSent = msg.engines ~= nil
        msg.engines = msg.engines or {}
    end
    -- Opened on a pad: no cursor from the first frame, and the page draws its pad hints.
    msg.pad = screen:open()
    SendNUIMessage(msg)

    -- With the mouse the page has the cursor, so the camera only turns while the orbit button is held;
    -- on a pad the right stick turns it all the time.
    Session.setUiHasMouse(not msg.pad)

    refreshCash()
end

--- Hides the page and gives the cursor back. Safe to call twice.
local function hide()
    if not open then return end
    open = false
    pageShown = false

    SendNUIMessage({ action = 'close' })
    screen:close()
    Session.setUiHasMouse(false)
end

UI = { show = show, hide = hide }

--- Has the page been asked to show? (UI.pageDrew says whether it actually drew.)
function UI.isOpen() return open end

--- Did the page draw and take over Backspace? main.lua's fallback exit stands down when it did, because
--- KeepInput lets key bindings fire under the page too.
---@return boolean
function UI.pageDrew() return open and pageShown end

--- Hides or shows the page's cursor while the camera has the mouse. Driven from Lua: the page never sees
--- the right mouse button.
---@param hidden boolean
function UI.setCursorHidden(hidden)
    if not open then return end
    SendNUIMessage({ action = 'cursor', hidden = hidden and true or false })
end

--- Sends the basket to the page after any change, with the goal's checklist (the basket ticks it).
local function syncBasket()
    if not open then return end
    SendNUIMessage({ action = 'basket', basket = Goals.dress(Session.basket()), job = Goals.model() })
    refreshCash()
end

--- A Director goal on a car started, ticked a row or ended (client/director.lua): the page's checklist
--- and what the job pays for follow.
function UI.jobChanged()
    if not open then return end
    SendNUIMessage({ action = 'basket', basket = Goals.dress(Session.basket()), job = Goals.model() })
end

-- ============================================
-- Callbacks from the page
-- ============================================

--- Every handler answers, even when it does nothing: an unanswered NUI callback leaves the page's
--- fetch hanging.
local function cb(name, fn)
    RegisterNUICallback(name, function(data, done)
        local ok, err = pcall(fn, data or {})
        if not ok then
            print(('[whip_autos] nui callback "%s" errored: %s'):format(name, tostring(err)))
        end
        done({})
    end)
end

--- The shelf and category on screen, for the camera and the bonnet (Session.setFocus).
cb('focus', function(data)
    if not Session.isActive() then return end

    local section = nil
    if data.section then
        for _, s in ipairs(Config.Sections) do
            if s.key == data.section then
                section = s
                break
            end
        end
    end

    Session.setFocus(section, data.slot)
end)

cb('preview', function(data)
    if not Session.isActive() then return end
    if data.slot == nil or data.index == nil then return end

    -- A tuning choice rides along: an engine's model, or a stance.
    if not Session.preview(data.slot, data.index, data.wheelType, { engine = data.engine, stance = data.stance }) then
        Whip.core:Notify('Could not fit that right now', 'error')
    end
end)

cb('add', function(data)
    if not Session.isActive() then return end
    if data.slot == nil or data.index == nil then return end

    Session.addToBasket(data)
    syncBasket()
end)

cb('remove', function(data)
    if not Session.isActive() then return end
    if data.slot == nil then return end

    -- Taking something out of the basket also takes it off the car.
    Session.revertSlot(data.slot)
    Session.removeFromBasket(data.slot)
    syncBasket()
end)

--- The page asked to leave, having already asked about an unpaid basket itself (two NUI frames cannot
--- both hold focus, so whip_core's Confirm is not used here).
cb('close', function()
    Session.close(false)
end)

--- The basket card opened: re-check the cash figure.
cb('cash', function()
    refreshCash()
end)

--- The page drew and owns Backspace from here (UI.pageDrew).
cb('shown', function()
    if open then pageShown = true end
end)

--- The Standard camera button (a click, C, or RB on a pad): the other camera, kept as this player's choice.
cb('camera', function()
    if not Session.isActive() then return end
    SendNUIMessage({ action = 'camera', standard = Session.toggleStandardCamera() })
end)

-- The server's default changed in /whip: a player with no choice of their own follows it at once.
Whip.onConfigChanged('Camera.followParts', function()
    if not Session.isActive() then return end
    local standard = Session.applyCameraChoice()
    if open then SendNUIMessage({ action = 'camera', standard = standard }) end
end)

--- The picker column opened or closed: how far to move the car on screen, as a share of the screen's
--- width (Cam.setScreenShift).
cb('layout', function(data)
    if not Session.isActive() then return end
    Cam.setScreenShift(tonumber(data.shift) or 0.0)
end)

--- The engine search box took or released the keyboard. While typing, game input is held back so keys
--- do not rev the engine or open chat. Ignored after close.
cb('typing', function(data)
    if not open then return end
    screen:typing(data.on == true)
end)

--- Pays for the basket. Sends slots, indices and tuning choices only: the server rebuilds and prices the
--- order itself (server/main.lua, server/tuning.lua). wheelType matters: slot 23 is a different wheel per range.
cb('checkout', function(data)
    if not Session.isActive() or Session.isBuilder() then return end

    local basket = Session.basket()
    if #basket == 0 then return end

    local method = data.method
    if method ~= 'cash' and method ~= 'bank' then return end

    local lines = {}
    for _, b in ipairs(basket) do
        lines[#lines + 1] = {
            slot = b.slot, index = b.index, wheelType = b.wheelType,
            engine = b.engine, stance = b.stance, setup = b.setup, drive = b.drive,
        }
    end

    -- The total as shown (the lines a Director goal pays for at nothing): the server never charges more
    -- (a price changed in /whip mid-visit).
    local shown = 0
    for _, b in ipairs(Goals.dress(basket)) do shown = shown + (b.price or 0) end
    TriggerServerEvent('whip_autos:server:purchase', Session.vehicleId(), method, lines, shown)
end)

--- The world builder's Save: the basket is how the car spawns (client/look.lua takes it).
cb('saveLook', function()
    if Session.isBuilder() then Session.saveLook() end
end)

--- The player's cash moved while the shop is open (server/main.lua, cashMoved).
RegisterNetEvent('whip_autos:client:cash', function(cash)
    cash = tonumber(cash)
    if open and cash then SendNUIMessage({ action = 'cash', cash = cash }) end
end)

--- The purchase result. On success the server has already saved the car, so the session closes without
--- reverting. A refusal was already shown by whip; here it only unlatches the pay buttons.
RegisterNetEvent('whip_autos:client:purchaseResult', function(ok, err, total, repairing)
    if not Session.isActive() then return end

    if not ok then
        SendNUIMessage({ action = 'purchaseFailed', reason = err })
        refreshCash()
        return
    end

    -- Before the close, which lets go of the car. Said out loud if it fails: the money is already taken.
    if repairing and not Session.repair() then
        Whip.core:Notify('The repair could not be applied — tell an admin', 'error')
    end

    -- Nothing to pay: the job paid, or only parts came off.
    if (tonumber(total) or 0) > 0 then
        Whip.core:Notify(('Paid $%s — enjoy the car'):format(total), 'success')
    else
        Whip.core:Notify('Fitted. Enjoy the car', 'success')
    end
    Session.close(true)
end)

-- ============================================
-- Following the session
-- ============================================

--- Opens or closes the page to match the session. session.lua calls it where a visit starts and in
--- teardownLocal, which every exit runs through. Safe to call any number of times.
---@param shouldBeOpen boolean
function UI.setOpen(shouldBeOpen)
    shouldBeOpen = shouldBeOpen and true or false
    if shouldBeOpen == open then return end
    if shouldBeOpen then show() else hide() end
end

-- (Stopping with the page up: Whip.padScreen gives the cursor back.)
