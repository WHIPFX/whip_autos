-- ============================================
-- whip_autos — shop lookups shared by client and server
-- ============================================
--
-- Built from Config here, so the two sides cannot build them differently, and built again in place
-- when an admin changes the list in /whip (shared/settings.lua).

--- Paint target id -> the appearance field it is stored in. The shop says 'pearl'; whip_core stores
--- 'pearlescent'. Also the test for "is this slot a colour".
SHOP_PAINT_PROP = {}

--- The services (Repair): work done to the car rather than a part fitted to it. They sit in the
--- basket like anything else, but there is nothing to preview, nothing to revert and no mod slot.
SHOP_SERVICES = {}

--- Xenon Lights (slot 22) is a list: 0 is Off, and 1.. is on in Config.XenonColours.options[n]'s colour
--- (GTA's colour number, 255 stock). 1 is Stock, so "on" from before the colours (1) still reads right.
SHOP_XENON_COLOUR = {}

--- Empties `t` and fills it from `list` again: files holding the table see the new contents.
local function refill(t, list, put)
    for k in pairs(t) do t[k] = nil end
    for i, x in ipairs(list) do put(t, i, x) end
end

--- Tyre Smoke (slot 20) the same way: 0 is Off, and 1.. is on in Config.TyreSmokeColours.options[n]'s colour, kept
--- here as { r, g, b }.
SHOP_SMOKE_COLOUR = {}

--- Neon Colour (slot 'neoncolor'): 1.. is Config.Neon.colours[n], kept here as { r, g, b }.
SHOP_NEON_COLOUR = {}

local function buildPaintProps() refill(SHOP_PAINT_PROP, Config.PaintTargets, function(t, _, x) t[x.id] = x.prop end) end
local function buildServices() refill(SHOP_SERVICES, Config.Services, function(t, _, x) t[x.id] = true end) end
local function buildXenons() refill(SHOP_XENON_COLOUR, Config.XenonColours.options, function(t, i, x) t[i] = x.index end) end
local function buildSmokes()
    refill(SHOP_SMOKE_COLOUR, Config.TyreSmokeColours.options, function(t, i, x) t[i] = { r = x.r, g = x.g, b = x.b } end)
end
local function buildNeons()
    refill(SHOP_NEON_COLOUR, Config.Neon.colours, function(t, i, x) t[i] = { r = x.r, g = x.g, b = x.b } end)
end
buildPaintProps()
buildServices()
buildXenons()
buildSmokes()
buildNeons()
Whip.onConfigChanged('PaintTargets', buildPaintProps)
Whip.onConfigChanged('Services', buildServices)
Whip.onConfigChanged('XenonColours.options', buildXenons)
Whip.onConfigChanged('TyreSmokeColours.options', buildSmokes)
Whip.onConfigChanged('Neon.colours', buildNeons)

--- Neon Layout (slot 'neon'): which of the car's four neon tubes are lit, as bits of its index: 1 left, 2 right,
--- 4 front, 8 back (GTA's sides 0 to 3). 0 is Off. These are the layouts the shop sells; any other mix a car carries
--- still reads right.
SHOP_NEON_LAYOUTS = {
    { index = 4,  name = 'Front' },
    { index = 8,  name = 'Back' },
    { index = 3,  name = 'Sides' },
    { index = 12, name = 'Front and Back' },
    { index = 7,  name = 'Front and Sides' },
    { index = 11, name = 'Back and Sides' },
    { index = 15, name = 'Front, Back and Sides' },
}

--- The Neon Layout index of a car's lit sides (whip_core stores `neonEnabled` as { left, right, front, back }).
---@param sides table|nil
---@return integer
function ShopNeonLayout(sides)
    local bits = 0
    if type(sides) == 'table' then
        for side = 0, 3 do
            if sides[side + 1] == true or sides[side + 1] == 1 then bits = bits | (1 << side) end
        end
    end
    return bits
end

--- A Neon Layout index as the sides to store: { left, right, front, back }.
---@param index integer
---@return boolean[]
function ShopNeonSides(index)
    local bits = math.tointeger(index) or 0
    local sides = {}
    for side = 0, 3 do sides[side + 1] = (bits & (1 << side)) ~= 0 end
    return sides
end

--- The Neon Colour entry a car's neon colour reads as: 0 when the list does not name it.
---@param rgb table|nil  { r, g, b }, as whip_core stores `neonColor`
---@return integer
function ShopNeonColourIndex(rgb)
    if type(rgb) ~= 'table' then return 0 end
    for i, c in ipairs(SHOP_NEON_COLOUR) do
        if c.r == rgb.r and c.g == rgb.g and c.b == rgb.b then return i end
    end
    return 0
end

--- The Livery shelf holds both kinds of livery, under slot 48. A MOD livery (the car's mod kit) is its
--- slot-48 index, -1 none. A MODEL livery (SetVehicleLivery: designs in the car's own textures, which
--- GTA's shops never sell) is SHOP_MODEL_LIVERY + its number. Fitting a model livery takes the mod livery off, so the
--- one picked is the one that shows.
SHOP_MODEL_LIVERY = 100

--- Which model livery a slot-48 index is (0 for 100), or nil when it is a mod livery.
---@param index any
---@return integer|nil
function ShopModelLiveryOf(index)
    local n = math.tointeger(tonumber(index))
    if n and n >= SHOP_MODEL_LIVERY and n < SHOP_MODEL_LIVERY * 2 then return n - SHOP_MODEL_LIVERY end
    return nil
end

--- The Extras shelf: GTA's switchable parts, 1-14 (what whip_core saves with the car), one category each.
--- Its slot is named 'extra<n>', index 0 off or 1 on, and every switch costs Config.Extras.price.
SHOP_EXTRA_LAST = 14

--- Which extra a slot is (3 for 'extra3'), or nil when it is not one.
---@param slot any
---@return integer|nil
function ShopExtraOf(slot)
    if type(slot) ~= 'string' then return nil end
    local n = math.tointeger(tonumber(slot:match('^extra(%d+)$')))
    if n and n >= 1 and n <= SHOP_EXTRA_LAST then return n end
    return nil
end

--- The Xenon Lights entry a car's xenons read as: 0 when off; a colour the list does not name is Stock.
---@param on boolean|nil
---@param colour number|nil  GTA's headlight colour
---@return integer
function ShopXenonIndex(on, colour)
    if not on then return 0 end
    for i, c in ipairs(SHOP_XENON_COLOUR) do
        if c == colour then return i end
    end
    return 1
end

--- The Tyre Smoke entry a car's smoke reads as: 0 when off; a colour the list does not name is the first (White).
---@param on boolean|nil
---@param rgb table|nil  { r, g, b }, as whip_core stores `tyreSmoke`
---@return integer
function ShopSmokeIndex(on, rgb)
    if not on then return 0 end
    if type(rgb) == 'table' then
        for i, c in ipairs(SHOP_SMOKE_COLOUR) do
            if c.r == rgb.r and c.g == rgb.g and c.b == rgb.b then return i end
        end
    end
    return 1
end

--- The Performance shelf's parts (Config.Performance: engine, brakes, transmission, suspension, armour) by mod slot.
local PERFORMANCE_SLOT = {}
local function buildPerformance() refill(PERFORMANCE_SLOT, Config.Performance, function(t, _, x) t[x.id] = true end) end
buildPerformance()
Whip.onConfigChanged('Performance', buildPerformance)

--- Is this slot performance or tuning: what only a car's owner may change under Config.WhoCanModify 'ownerTuning'?
--- The Performance shelf's parts and the turbo (18), and the Tuning shelf (engine swap, stance, handling, drivetrain).
--- Xenon lights sit on the Performance shelf but are looks.
---@param slot any
---@return boolean
function ShopIsPerformance(slot)
    return slot == 18 or PERFORMANCE_SLOT[slot] == true or TUNING_SLOTS[slot] == true
end

--- What this player may change on this car, by Config.WhoCanModify: 'all', 'looks' (no performance or tuning), or
--- 'repair' (the services only, no customisation). A car nobody owns (a street car, a scenario's car) is open to
--- whoever drives it.
---@param charId number|nil  the player's character
---@param ownerCharId number|nil  the car's owner (GetVehicle's owner.charId)
---@return string may
function ShopMayChange(charId, ownerCharId)
    local rule = Config.WhoCanModify
    if rule ~= 'ownerTuning' and rule ~= 'owner' then return 'all' end
    if ownerCharId == nil or ownerCharId == charId then return 'all' end
    if rule == 'owner' then return 'repair' end
    return 'looks'
end

--- The Window Tint entry that is Stock (Config.WindowTints): a car whose record names no tint has it.
local STOCK_TINT = 4

--- Does a car's stored look already have this part? The shop does not sell it again (server/main.lua), and a Director
--- goal that asks for it is met from the start (shared/goals.lua ShopGoal.propsMeet): one test, so a goal never asks for
--- what the shop will not sell. A mod slot or tint the record does not mention is stock.
---@param props table|nil  the car's stored appearance
---@param line table  { slot, index, wheelType? }
---@param turboIndex number|nil  the car's turbo stage (TuningTurboIndex: its data, not its look; 0 for none)
---@return boolean
function ShopFitted(props, line, turboIndex)
    local slot, index = line.slot, line.index
    if slot == 18 then return (turboIndex or 0) == index end
    if type(props) ~= 'table' then return false end

    -- A repair can always be bought.
    if SHOP_SERVICES[slot] then return false end

    if slot == 'tint' then return (props.windowTint or STOCK_TINT) == index end
    local field = SHOP_PAINT_PROP[slot]
    if field then return props[field] == index end
    if slot == 22 then return ShopXenonIndex(props.xenon, props.headlightColor) == index end
    if slot == 20 then return ShopSmokeIndex(props.smokeEnabled, props.tyreSmoke) == index end
    if slot == 'neon' then return ShopNeonLayout(props.neonEnabled) == index end
    if slot == 'neoncolor' then return ShopNeonColourIndex(props.neonColor) == index end

    -- An extra the record does not mention is not "fitted": switching it is sold.
    local extra = ShopExtraOf(slot)
    if extra then
        local e = nil   -- (not `and`: no record must not read as "off")
        if type(props.extras) == 'table' then e = props.extras[tostring(extra)] end
        return e ~= nil and e == (index == 1)
    end

    -- Wheels must match the range too.
    if line.wheelType ~= nil and props.wheelType ~= line.wheelType then return false end

    local mods = type(props.mods) == 'table' and props.mods or {}
    -- A model livery is fitted when the car wears it with no mod livery over it (SHOP_MODEL_LIVERY).
    local model = slot == 48 and ShopModelLiveryOf(index)
    if model then return props.livery == model and (mods['48'] or -1) == -1 end
    return (mods[tostring(slot)] or -1) == index
end
