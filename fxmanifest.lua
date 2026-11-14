fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whip_autos'
description 'Whiplash — a vehicle customisation shop, and bolt-on power: a turbo that spools, a nitrous bottle, every car\'s top speed and how long its gears take. The worked example of a whip satellite.'
author 'Whippy'
version '0.3.0'
whip_updates 'WHIPFX/whip_autos'   -- whip_core checks this repository's releases for a newer version

-- Power (turbo, nitrous, top speed, shift time): client/power/, server/power/, and the Power section
-- at the end of config.lua.

-- whip's satellite helper: Whip.register runs our setup once whip_core is ready. With the dependency at the bottom,
-- a whip_core restart stops whip_autos first and starts it again after, so nothing here cleans up after whip_core.
--
-- Calling whip_core: the docs' one rule (whip_core/docs.html#patterns-calling).
--   exports.whip_core:X(...)   inside a handler whip_core runs for us: Whip.register, SecureEvent/SecureCallback,
--                              WatchVehicleData, OnVehicleStatChange, AddAction callbacks, a Director card's run.
--                              A payment in a SecureEvent too, so it and what it pays for are one write.
--   Whip.core:X(...)           in our own code: a thread, a command, a key press, an NUI callback, our own events.
--                              It answers false and why where a straight call would throw (whip_core still loading).
--   Every frame                a quick export straight, behind a started check (client/power/handling.lua).
--
-- Learning from it: whip_core/docs.html#autos-patterns walks through the patterns here, file by file.
shared_script '@whip_core/lib/satellite.lua'
shared_script 'config.lua'
shared_script 'shared/shop.lua'
shared_script 'shared/tuning.lua'
shared_script 'shared/power.lua'      -- the turbo and nitrous settings and vehicle classes both power halves read
shared_script 'shared/settings.lua'   -- config.lua as a page in /whip → Settings; after config.lua and power.lua
shared_script 'shared/goals.lua'      -- what a Director goal asks of the car (Goal: Customise Vehicle)
shared_script 'shared/director.lua'   -- Force Open Whiplash, a task on a car's list in the Director

server_scripts {
    'server/main.lua',
    'server/director.lua',  -- the Director's cards (Customise Vehicle, Force Open Whiplash); main.lua calls it
    'server/engines.lua',   -- engine swap list (engines.json)
    'server/tuning.lua',    -- reads engines.lua
    'server/look.lua',      -- a Director car's Whiplash look, put on it when the scenario makes it; after tuning.lua
    'server/dev.lua',       -- developer tools, not part of the shop
    -- Power: the turbo stages (the boost stat, GTA's turbo part for the sound) and the nitrous bottle.
    'server/power/turbo.lua',
    'server/power/nitrous.lua',
}

client_scripts {
    '@whip_core/lib/cost.lua',   -- WhipCost: the stance loop and the power asks, timed by whip_core's /whipcost
    'client/boxfit.lua',    -- the camera frames through it
    'client/camera.lua',
    'client/catalogue.lua',
    'client/tuning.lua',    -- before session.lua, which previews through it
    'client/session.lua',
    'client/director.lua',  -- the Director opening Whiplash, and a goal's checklist
    'client/look.lua',      -- the world builder's Whiplash button: how a Director car spawns
    'client/ui.lua',
    'client/main.lua',
    'client/dev.lua',       -- /whiplash* developer commands, not part of the shop
    -- Power. handling.lua defines PowerHandling, which turbo and nitrous both declare their torque to.
    'client/power/handling.lua',
    'client/power/turbo.lua',
    'client/power/nitrous.lua',
    'client/power/top_speed.lua',   -- every car's top speed raised by Config.TopSpeedBonusMph (longer gearing)
    'client/power/shift_time.lua',  -- every gear change slower, per vehicle class (Config.ShiftTimeByClass)
    'client/power/gearbox.lua',     -- when it changes gear, from how hard the car is driven (Config.Gearbox)
}

ui_page 'html/index.html'

-- Only this resource's page may call its NUI callbacks (the purchase spends money).
nui_callback_strict_mode 'true'

-- The shop's page, in three.js: html/js/app.js keeps the state and the rules and talks to client/ui.lua; view.js and
-- kit.js draw it; three.module.min.js is three.js r170 (the same file whip_core's rev dial loads). One line per
-- folder: a `*` in a folder's name matches nothing.
files {
    'html/index.html',
    'html/js/*.js',
    'html/img/wheels/*.webp',
    'html/img/mods/*.webp',
    'html/img/art/*.webp',
    'html/img/art/*.svg',
    'html/img/pad/*.svg',   -- whip_core's pad pictures, copied: drawn into a canvas, they must be this page's own
    'html/fonts/*.woff2',
    'html/img/items/*.webp',   -- the nitrous bottle's picture: whip_core looks for an item's here
}

-- The WHIPLASH shop building in Burton is the separate resource whip_autos_shop (map files only). It is not in here so
-- that restarting whip_autos, or whip_core (which restarts whip_autos with it), never unloads an interior under players.

-- The colour ramps GTA's Chameleon paints (161-222) draw from are the separate resource chameleon_paint:
-- WildBrick142's Chameleon Paint [Add-On] 2.0, reuploaded unchanged, which the recipe installs in [assets]. It is the
-- author's work under the author's terms, so it ships on its own rather than in here. Without it those paints turn a
-- car black.

dependencies { 'whip_core' }
