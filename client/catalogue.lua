-- ============================================
-- whip_autos — what this car supports
-- ============================================
-- Builds the shop for one vehicle on entry: which mods this model has (only a client native can say),
-- with prices from Config. It decides what is shown, never what is charged — server/main.lua prices
-- from its own copy of Config.
--
-- A category's `key` is what the screen navigates by; its `slot` is what gets bought. They differ for
-- wheels: all thirteen wheel ranges are slot 23.

Catalogue = {}

--- Mod slots that are on/off rather than a list.
local TOGGLE_SLOTS = {}

--- Paint targets by id.
local PAINT_TARGETS = {}

--- Both built from Config, and again when an admin changes the list in /whip (shared/settings.lua).
local function buildToggles()
    TOGGLE_SLOTS = {}
    for _, t in ipairs(Config.Toggles) do TOGGLE_SLOTS[t.id] = true end
end
local function buildPaintTargets()
    PAINT_TARGETS = {}
    for _, t in ipairs(Config.PaintTargets) do PAINT_TARGETS[t.id] = t end
end
buildToggles()
buildPaintTargets()
Whip.onConfigChanged('Toggles', buildToggles)
Whip.onConfigChanged('PaintTargets', buildPaintTargets)

--- A readable name for one mod. Add-on cars often have no label text, so anything that is not real text
--- falls back to "Front Bumper 3".
---@param veh number
---@param slot number
---@param index number
---@param slotName string
---@return string
local function modName(veh, slot, index, slotName)
    local key = GetModTextLabel(veh, slot, index)
    if key then
        local text = GetLabelText(key)
        if text and text ~= '' and text ~= 'NULL' and text ~= key then
            return text
        end
    end
    return ('%s %d'):format(slotName, index + 1)
end

--- What this car calls a slot: some name their own (the Tuners cars: "Mirrors", "Splitters" in slots whose usual
--- name is something else), as a text label or, on an add-on car, as plain text. Otherwise the Config name.
---@param veh number
---@param def table  { id, name }
---@return string
local function slotName(veh, def)
    local key = GetModSlotName(veh, def.id)
    if type(key) == 'string' and key ~= '' and key ~= 'NULL' then
        local text = GetLabelText(key)
        if text and text ~= '' and text ~= 'NULL' and text ~= key then return text end
        -- Not a label: a plain name, unless it is a label name with no text (capitals, digits and underscores).
        if not key:find('^[%u%d_]+$') then return key end
    end
    return def.name
end

--- Every mod in one list-style slot, or nil when the vehicle has none (the category is then skipped).
---@param veh number
---@param def table  an entry from Config.Cosmetics / Wheels / Performance
---@return table|nil
local function listSlot(veh, def)
    local count = GetNumVehicleMods(veh, def.id)
    if not count or count <= 0 then return nil end

    local name = slotName(veh, def)
    local current = GetVehicleMod(veh, def.id)
    local items = {
        -- -1 is "no mod"; offered free so a choice can be undone before paying.
        { index = -1, name = 'Stock', price = 0, fitted = current == -1 },
    }

    for i = 0, count - 1 do
        items[#items + 1] = {
            index  = i,
            name   = modName(veh, def.id, i, name),
            price  = def.price,
            fitted = current == i,
        }
    end

    return {
        key   = tostring(def.id),
        slot  = def.id,
        name  = name,
        kind  = 'list',
        items = items,
    }
end

--- The Turbo (slot 18): Off, then every stage Whiplash sells (Config.Turbo.Stages), each at its own price. The car's
--- own is its turbo data (TUNING_TURBO_KEY), not GTA's part, which only goes on with it for the sound.
local function turboSlot(veh, def)
    local data = Whip.call('GetVehicleData', { entity = veh }, TUNING_TURBO_KEY)   -- (Catalogue.build: a visit opening)
    local fitted = TuningTurboIndex(data)
    local items = { { index = 0, name = 'Off', price = 0, fitted = fitted == 0 } }
    for _, s in ipairs(PowerTurbo.stages or {}) do
        items[#items + 1] = { index = s.index, name = ('%d psi'):format(s.psi), price = s.price, fitted = fitted == s.index }
    end
    return { key = tostring(def.id), slot = def.id, name = def.name, kind = 'list', items = items }
end

--- A toggle slot (turbo, xenon) as a two-item list. GetNumVehicleMods reports 0 for toggles, so it is
--- always offered.
local function toggleSlot(veh, def)
    if def.id == 18 then return turboSlot(veh, def) end
    local on = IsToggleModOn(veh, def.id) and true or false
    return {
        key   = tostring(def.id),
        slot  = def.id,
        name  = def.name,
        kind  = 'toggle',
        items = {
            { index = 0, name = 'Off', price = 0,         fitted = not on },
            { index = 1, name = 'On',  price = def.price, fitted = on     },
        },
    }
end

--- Xenon Lights: Off, then every colour (Config.XenonColours). A colour fits xenons in it for the
--- Xenon Lights price; on a car that has xenons, a colour change costs colourPrice.
local function xenonSlot(veh, def)
    local current = ShopXenonIndex(IsToggleModOn(veh, def.id), GetVehicleHeadlightsColour(veh))
    local price = current ~= 0 and Config.XenonColours.colourPrice or def.price
    local items = { { index = 0, name = 'Off', price = 0, fitted = current == 0 } }
    for i, o in ipairs(Config.XenonColours.options) do
        items[#items + 1] = { index = i, name = o.name, price = price, fitted = current == i }
    end
    return { key = tostring(def.id), slot = def.id, name = def.name, kind = 'list', items = items }
end

--- The Livery shelf: the car's mod liveries and its model liveries in one list (SHOP_MODEL_LIVERY). Stock (no mod
--- livery) is there when the car has mod liveries; a car with only model liveries has no "none", only its designs. One
--- model livery is nothing to choose, so it takes two to list them. Nil when the car has neither.
---@param veh number
---@param def table  the Config.PaintExtras entry for slot 48
---@return table|nil
local function liverySlot(veh, def)
    local mods = GetNumVehicleMods(veh, def.id) or 0
    local models = GetVehicleLiveryCount(veh) or -1
    if models < 2 then models = 0 end
    models = math.min(models, SHOP_MODEL_LIVERY)
    if mods <= 0 and models == 0 then return nil end

    local name = slotName(veh, def)
    local mod, model = GetVehicleMod(veh, def.id), GetVehicleLivery(veh)
    local items = {}
    if mods > 0 then
        items[1] = { index = -1, name = 'Stock', price = 0, fitted = mod == -1 and models == 0 }
    end
    for i = 0, mods - 1 do
        items[#items + 1] = { index = i, name = modName(veh, def.id, i, name), price = def.price, fitted = mod == i }
    end
    for j = 0, models - 1 do
        local label = GetLiveryName(veh, j)
        local text = label and GetLabelText(label)
        if not text or text == '' or text == 'NULL' or text == label then
            text = ('%s %d'):format(name, mods + j + 1)   -- numbered on from the mod liveries
        end
        items[#items + 1] = { index = SHOP_MODEL_LIVERY + j, name = text, price = def.price, fitted = mod == -1 and model == j }
    end
    return { key = tostring(def.id), slot = def.id, name = name, kind = 'list', items = items }
end

--- Tyre Smoke: Off, then every colour (Config.TyreSmokeColours), priced as Xenon Lights are.
local function smokeSlot(veh, def)
    local r, g, b = GetVehicleTyreSmokeColor(veh)
    local current = ShopSmokeIndex(IsToggleModOn(veh, def.id), { r = r, g = g, b = b })
    local price = current ~= 0 and Config.TyreSmokeColours.colourPrice or def.price
    local items = { { index = 0, name = 'Off', price = 0, fitted = current == 0 } }
    for i, o in ipairs(Config.TyreSmokeColours.options) do
        items[#items + 1] = { index = i, name = o.name, price = price, fitted = current == i }
    end
    return { key = tostring(def.id), slot = def.id, name = def.name, kind = 'list', items = items }
end

--- The car's extras (the Extras shelf; SHOP_EXTRA_LAST in shared/shop.lua): one category each for the extras the model
--- has, Off and On, the one it does not wear costing Config.Extras.price. GTA gives them no names.
---@param veh number
---@return table[]
local function extraSlots(veh)
    local out, price = {}, (Config.Extras and Config.Extras.price) or 0
    for n = 1, SHOP_EXTRA_LAST do
        if DoesExtraExist(veh, n) then
            local on = IsVehicleExtraTurnedOn(veh, n) and true or false   -- 1 or false: never == true
            out[#out + 1] = {
                key = 'extra' .. n, slot = 'extra' .. n, name = 'Extra ' .. n, kind = 'toggle',
                items = {
                    { index = 0, name = 'Off', price = on and price or 0, fitted = not on },
                    { index = 1, name = 'On',  price = on and 0 or price, fitted = on     },
                },
            }
        end
    end
    return out
end

--- Window tint: its own native and its own fixed list.
local function tintSlot(veh)
    local current = GetVehicleWindowTint(veh)
    local items = {}
    for _, o in ipairs(Config.WindowTints.options) do
        items[#items + 1] = {
            index  = o.index,
            name   = o.name,
            price  = o.index == 4 and 0 or Config.WindowTints.price,  -- 4 is stock
            fitted = current == o.index,
        }
    end
    return { key = 'tint', slot = 'tint', name = 'Window Tint', kind = 'tint', items = items }
end

-- ============================================
-- Wheels
-- ============================================

--- Every wheel range this vehicle can take. GetNumVehicleMods(veh, 23) only answers for the current
--- wheel type, so each type is set in turn and asked; the car's own wheels are put back in the same frame.
---@param veh number
---@param def table  the Config.Wheels entry for slot 23
---@return table[]
local function wheelSlots(veh, def)
    local wasType = GetVehicleWheelType(veh)
    local wasMod  = GetVehicleMod(veh, def.id)
    local out     = {}

    for wheelType = 0, 12 do
        local name = Config.WheelCategories[wheelType]
        if name then
            SetVehicleWheelType(veh, wheelType)

            local count = GetNumVehicleMods(veh, def.id)
            if count and count > 0 then
                -- Only the range the car arrived on can have one fitted.
                local current = wheelType == wasType and wasMod or nil

                local items = {
                    { index = -1, name = 'Stock', price = 0, fitted = current == -1 },
                }
                for i = 0, count - 1 do
                    items[#items + 1] = {
                        index  = i,
                        name   = modName(veh, def.id, i, name),
                        price  = def.price,
                        fitted = current == i,
                    }
                end

                out[#out + 1] = {
                    key       = 'wheel' .. wheelType,
                    slot      = def.id,
                    wheelType = wheelType,
                    name      = name,
                    kind      = 'list',
                    items     = items,
                }
            end
        end
    end

    -- Type first: the same mod index is a different wheel under each type.
    SetVehicleWheelType(veh, wasType)
    SetVehicleMod(veh, def.id, wasMod, GetVehicleModVariation(veh, def.id))

    return out
end

-- ============================================
-- Paint
-- ============================================

--- Which colour family a paint is listed under, from the first word of its name (Config.PaintFamilies).
---@param name string
---@return string
local function paintFamily(name)
    local first = name:match('^(%S+)')
    return (first and Config.PaintFamilies.map[first]) or Config.PaintFamilies.default
end

--- Every paint the game has, built once (and again when the palette or its tags change in /whip).
--- Sent beside the catalogue rather than in each paint target: all four targets share the same colours.
local palette = nil
Whip.onConfigChanged('Colours', function() palette = nil end)
Whip.onConfigChanged('PaintFamilies', function() palette = nil end)

--- @return table  [ { index, name, hex, family }, ... ]
function Catalogue.palette()
    if palette then return palette end

    palette = {}
    for _, c in ipairs(Config.Colours) do
        palette[#palette + 1] = {
            index  = c.index,
            name   = c.name,
            hex    = c.hex,
            hex2   = c.hex2,   -- a colour-shift paint's second colour: the swatch is a gradient
            family = c.family or paintFamily(c.name),   -- a row's own family wins over its first word
        }
    end
    return palette
end

--- One paint target (primary, secondary, pearlescent, wheel colour). `kind = 'paint'` makes the page open
--- the paint picker.
---@param def table  an entry from Config.PaintTargets
---@param current number|nil  the colour index the vehicle wears for it
---@return table
local function paintSlot(def, current)
    return {
        key      = def.id,
        slot     = def.id,
        name     = def.name,
        kind     = 'paint',
        price    = def.price,
        current  = current,
        families = Config.PaintFamilies.order,
    }
end

-- ============================================
-- Building the shop
-- ============================================

--- The whole shop for one vehicle: `{ [sectionKey] = { category, ... } }`. Empty sections and
--- categories are left out.
---@param veh number
---@return table
function Catalogue.build(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return {} end

    -- Without a mod kit the game reports zero mods for every slot.
    SetVehicleModKit(veh, 0)

    local out = {}

    local function collect(key, defs)
        local cats = {}
        for _, def in ipairs(defs) do
            local cat = TOGGLE_SLOTS[def.id] and toggleSlot(veh, def) or listSlot(veh, def)
            if cat then cats[#cats + 1] = cat end
        end
        if #cats > 0 then out[key] = cats end
    end

    collect('cosmetics',   Config.Cosmetics)
    collect('performance', Config.Performance)

    -- Slot 23 split by wheel range; anything else in Config.Wheels (24, a bike's back wheel) has no range.
    local wheels = {}
    for _, def in ipairs(Config.Wheels) do
        if def.id == 23 then
            for _, cat in ipairs(wheelSlots(veh, def)) do wheels[#wheels + 1] = cat end
        else
            local cat = listSlot(veh, def)
            if cat then wheels[#wheels + 1] = cat end
        end
    end
    -- Toggles go on the performance shelf, tyre smoke on the wheels one (as GTA's own shop has it), tint on the
    -- cosmetics one.
    local perf = out.performance or {}
    for _, def in ipairs(Config.Toggles) do
        if def.id == 20 then
            wheels[#wheels + 1] = smokeSlot(veh, def)
        else
            perf[#perf + 1] = def.id == 22 and xenonSlot(veh, def) or toggleSlot(veh, def)
        end
    end
    if #perf > 0 then out.performance = perf end
    if #wheels > 0 then out.wheels = wheels end

    -- Extras: their own shelf, on a car that has any.
    local extras = extraSlots(veh)
    if #extras > 0 then out.extras = extras end

    local cosm = out.cosmetics or {}
    cosm[#cosm + 1] = tintSlot(veh)
    out.cosmetics = cosm

    -- Paint: every vehicle has colours.
    local primary, secondary = GetVehicleColours(veh)
    local pearl, wheelColour = GetVehicleExtraColours(veh)
    local currentOf = {
        color1     = primary,
        color2     = secondary,
        pearl      = pearl,
        wheelcolor = wheelColour,
        interior   = GetVehicleInteriorColour(veh),
        dashboard  = GetVehicleDashboardColour(veh),
    }

    local paints = {}
    for _, def in ipairs(Config.PaintTargets) do
        paints[#paints + 1] = paintSlot(def, currentOf[def.id])
    end

    -- Livery is listed with paint: slot 48's mod liveries and the car's model liveries together (liverySlot). Absent
    -- on a car with neither.
    for _, def in ipairs(Config.PaintExtras) do
        local cat = def.id == 48 and liverySlot(veh, def) or listSlot(veh, def)
        if cat then paints[#paints + 1] = cat end
    end

    out.paints = paints

    -- Tuning: stored as VehicleData (client/tuning.lua), not mods. Each category says what the car has now.
    local tuning = {}
    local engines = Tuning.engineList()
    if engines then
        local cur = Whip.call('GetVehicleData', { entity = veh }, TUNING_ENGINE_KEY)
        tuning[#tuning + 1] = {
            key = 'engine', slot = 'engine', kind = 'engine', name = 'Engine Swap',
            price = Config.Tuning.EngineSwapPrice,
            current = type(cur) == 'table' and cur.model or nil,
            currentLabel = type(cur) == 'table' and cur.label or nil,
            items = {},   -- the engine list goes to the page separately (ui.lua)
        }
    end
    local st = Whip.call('GetVehicleData', { entity = veh }, TUNING_STANCE_KEY)
    tuning[#tuning + 1] = {
        key = 'stance', slot = 'stance', kind = 'stance', name = 'Stance',
        -- Paid once per car; saves after that are free.
        price = type(st) == 'table' and 0 or Config.Tuning.StancePrice,
        owned = type(st) == 'table',
        current = TuningCleanStance(type(st) == 'table' and st or {}),
        ranges = Config.Tuning.Stance,
        wheels = GetVehicleNumberOfWheels(veh),
        customWheels = GetVehicleMod(veh, 23) ~= -1,
        items = {},
    }

    -- Handling: paid once like stance. steerDeg is the car's own steering angle (before any setup), so the
    -- slider can show degrees; FiveM returns degrees, a tiny value is treated as radians.
    local su = Whip.call('GetVehicleData', { entity = veh }, TUNING_SETUP_KEY)
    local lock = Whip.call('GetVehicleHandlingBase', { entity = veh }, 'fSteeringLock')
    tuning[#tuning + 1] = {
        key = 'setup', slot = 'setup', kind = 'setup', name = 'Handling',
        price = type(su) == 'table' and 0 or Config.Tuning.SetupPrice,
        owned = type(su) == 'table',
        current = TuningCleanSetup(type(su) == 'table' and su or {}),
        ranges = Config.Tuning.Setup,
        steerDeg = type(lock) == 'number' and lock > 0 and (lock < 3.2 and math.deg(lock) or lock) or nil,
        items = {},
    }

    -- Drivetrain: paid once; not offered on bikes. stockLayout names the car's own.
    if GetVehicleNumberOfWheels(veh) >= 4 then
        local dr = Whip.call('GetVehicleData', { entity = veh }, TUNING_DRIVE_KEY)
        tuning[#tuning + 1] = {
            key = 'drive', slot = 'drive', kind = 'drive', name = 'Drivetrain',
            price = type(dr) == 'table' and 0 or Config.Tuning.DrivetrainPrice,
            owned = type(dr) == 'table',
            current = TuningCleanDrive(type(dr) == 'table' and dr or {}),
            ranges = Config.Tuning.Drive,
            stockLayout = Tuning.stockDrive(veh),
            items = {},
        }
    end
    out.tuning = tuning

    return out
end

--- The shop without what only a car's owner may change (Config.WhoCanModify 'ownerTuning', ShopIsPerformance): the
--- Tuning shelf, and the Performance shelf's parts and turbo; its xenon lights are looks and stay. A shelf left empty
--- goes (the page skips it). The server refuses those slots too.
---@param cat table  Catalogue.build's
---@return table
function Catalogue.looksOnly(cat)
    local out = {}
    for key, cats in pairs(cat) do
        local kept = {}
        for _, c in ipairs(cats) do
            if not ShopIsPerformance(c.slot) then kept[#kept + 1] = c end
        end
        if #kept > 0 then out[key] = kept end
    end
    return out
end

--- What every part on show comes to, each slot once at its dearest (the wheel ranges are one slot): the most a player
--- can spend on this car's parts. A Director goal's minimum spend is checked against it (server/director.lua).
---@param cat table  Catalogue.build's
---@return integer dollars
function Catalogue.most(cat)
    local best = {}
    for _, cats in pairs(type(cat) == 'table' and cat or {}) do
        for _, c in ipairs(cats) do
            local slot = c.slot ~= nil and c.slot or c.key
            if slot ~= nil and not SHOP_SERVICES[slot] then
                local top = tonumber(c.price) or 0
                for _, it in ipairs(c.items or {}) do top = math.max(top, tonumber(it.price) or 0) end
                local k = tostring(slot)
                if top > (best[k] or 0) then best[k] = top end
            end
        end
    end
    local sum = 0
    for _, v in pairs(best) do sum = sum + v end
    return math.floor(sum)
end

-- ============================================
-- Applying one choice, for preview
-- ============================================

--- Puts one choice on the car. Nothing is saved, but mods and colours are networked, so everyone near
--- sees it — which is why every exit restores the stored look. Needs network control of the car
--- (the session holds it).
---@param veh number
---@param slot number|string  mod slot id, 'tint', or a paint target id
---@param index number
---@param wheelType number|nil  which wheel range `index` refers to; wheels only
function Catalogue.apply(veh, slot, index, wheelType)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end

    SetVehicleModKit(veh, 0)

    if slot == 'tint' then
        SetVehicleWindowTint(veh, index)
        return true
    end

    -- Each colour native sets a pair, so the other half is read back and passed through.
    if PAINT_TARGETS[slot] then
        if slot == 'interior' then
            SetVehicleInteriorColour(veh, index)   -- the cabin's trim: a native of its own
        elseif slot == 'dashboard' then
            SetVehicleDashboardColour(veh, index)  -- and the dashboard's
        elseif slot == 'color1' or slot == 'color2' then
            local primary, secondary = GetVehicleColours(veh)
            if slot == 'color1' then primary = index else secondary = index end
            SetVehicleColours(veh, primary, secondary)
        else
            local pearl, wheelColour = GetVehicleExtraColours(veh)
            if slot == 'pearl' then pearl = index else wheelColour = index end
            SetVehicleExtraColours(veh, pearl, wheelColour)
        end
        return true
    end

    -- Xenons: on in a colour (1..), or off (0). See SHOP_XENON_COLOUR.
    if slot == 22 then
        ToggleVehicleMod(veh, 22, index >= 1)
        if index >= 1 then SetVehicleHeadlightsColour(veh, SHOP_XENON_COLOUR[index] or 255) end
        return true
    end

    -- Tyre smoke the same way: on in a colour (1..), or off (0). See SHOP_SMOKE_COLOUR.
    if slot == 20 then
        ToggleVehicleMod(veh, 20, index >= 1)
        local c = index >= 1 and SHOP_SMOKE_COLOUR[index]
        if c then SetVehicleTyreSmokeColor(veh, c.r, c.g, c.b) end
        return true
    end

    -- The Turbo: any stage puts GTA's part on, for its sound in the preview (turboSlot).
    if slot == 18 then
        ToggleVehicleMod(veh, 18, index >= 1)
        return true
    end

    if TOGGLE_SLOTS[slot] then
        ---@cast slot integer -- Config.Toggles are mod slots
        ToggleVehicleMod(veh, slot, index == 1)
        return true
    end

    -- An extra: through whip_core, which keeps the car's damage (GTA's switch repairs it). With whip_core gone (this
    -- runs in the revert while it stops), the plain switch.
    local extra = ShopExtraOf(slot)
    if extra then
        local switched, why = Whip.call('SetVehicleExtras', { entity = veh }, { [extra] = index == 1 })
        if switched == false and why then SetVehicleExtra(veh, extra, index ~= 1) end
        return true
    end

    -- A model livery (SHOP_MODEL_LIVERY): the mod livery comes off so it shows.
    local model = slot == 48 and ShopModelLiveryOf(index)
    if model then
        RemoveVehicleMod(veh, 48)
        SetVehicleLivery(veh, model)
        return true
    end

    -- Wheel type before the wheel: the same index is a different wheel under each type.
    if wheelType ~= nil then
        SetVehicleWheelType(veh, wheelType)
    end

    -- The last argument keeps the car's custom tyres setting.
    ---@cast slot integer -- a mod slot: the named ones are answered above
    SetVehicleMod(veh, slot, index, GetVehicleModVariation(veh, slot))
    return true
end
