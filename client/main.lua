-- ============================================
-- whip_autos — the way in
-- ============================================
-- The floor marker, the radial entry that opens the shop, and the fallback Backspace exit.

-- ============================================
-- The shop floor
-- ============================================

--- Optional floor marker (Config.Shop.marker). The thread only exists while it is on: a Wait(0) loop
--- costs its wake even when it draws nothing. Being on the floor is checked by Session.canEnter, not here.
local markerRunning = false

local function startMarker()
    if not Config.Shop.marker or markerRunning then return end
    markerRunning = true
    CreateThread(function()
        -- Read each time round: the floor can be moved, resized or switched off in /whip.
        while Config.Shop.marker do
            local shop = Config.Shop
            local sleep = 1000
            local p = GetEntityCoords(PlayerPedId())

            if #(p - shop.coords) < 60.0 then
                sleep = 0
                DrawMarker(
                    1,                      -- cylinder
                    shop.coords.x, shop.coords.y, shop.coords.z - 0.95,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    shop.radius * 2.0, shop.radius * 2.0, 0.7,
                    240, 70, 130, 90,       -- whiplash pink
                    ---@diagnostic disable-next-line: param-type-mismatch -- no texture: nil (the natives library types them string)
                    false, false, 2, false, nil, nil, false
                )
            end

            Wait(sleep)
        end
        markerRunning = false
    end)
end

startMarker()
Whip.onConfigChanged('Shop.marker', startMarker)

-- ============================================
-- Radial entry
-- ============================================

--- Registers the radial entry with whip_core, once it is ready (Whip.register).
local function RegisterWithWhip()
    local added, why = exports.whip_core:AddAction({
        id    = 'enter',   -- an id makes re-registering a replace
        at    = { radial = true },
        label = 'Enter ' .. Config.Shop.label,
        icon  = 'turbo',
        description = 'Tune, paint and fit parts to this car',
        group = 'whip_autos',

        -- Runs every time the wheel opens, so it must not block: Session.canEnter is natives only. A car a
        -- Director goal has let them into opens anywhere (client/director.lua).
        canInteract = function()
            local ok = Session.canEnter(Goals.here())
            return ok
        end,

        -- Runs in its own thread, so Session.open may wait for the server.
        onSelect = function(ctx)
            local ok, reason = Session.open({ director = Goals.here() })
            if not ok and reason then ctx.refuse(reason) end
        end,
    })
    if not added then print('[whip_autos] could not add the wheel entry: ' .. tostring(why)) end
end

Whip.register(RegisterWithWhip)

-- The entry says the shop's name: renamed in /whip, it is added again (same id, so it replaces).
Whip.onConfigChanged('Shop.label', function()
    if Whip.isReady() then RegisterWithWhip() end
end)

-- ============================================
-- Leaving
-- ============================================

--- Fallback exit for when the page failed to load. Normally the page owns Backspace (and asks about an
--- unpaid basket), so this stands down once UI.pageDrew() is true. A key binding, not a polled control:
--- control 177 is also right mouse, which orbits the camera.
RegisterCommand('+whiplash_leave', function()
    if not Session.isActive() then return end
    if UI.pageDrew() then return end
    Session.close(false)
end, false)

--- The release half of the binding. FiveM calls `-name` on key up; without it the press falls through to
--- chat as the text "-whiplash_leave". Register both halves of every `+` binding.
RegisterCommand('-whiplash_leave', function() end, false)

RegisterKeyMapping('+whiplash_leave', 'Whiplash Autos: Leave (fallback)', 'keyboard', 'BACK')
