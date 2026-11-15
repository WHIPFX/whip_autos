-- whip_autos configuration: prices, parts and where the shop is. The server charges from its own copy; the client
-- reads this only to show prices. Most settings are also on /whip → Settings → Autos, and a value saved there beats
-- this file (Reset puts this file's value back).

Config = {}

--- The shop floor: the car lift in the Whiplash shop building (whip_autos_shop). A driver on it opens the shop from
--- the F1 wheel. Keep the radius small: a car still driving in through the doorway (about 6 m away) should not count.
Config.Shop = {
    label   = 'Whiplash',
    coords  = vector3(-336.23, -116.73, 38.70),
    radius  = 3.0,

    -- Pink floor marker. Decoration only; when false its per-frame thread never starts.
    marker = false,
}

-- The shop on everyone's map, at the floor, named as the shop is. `show = false` leaves it off. sprite and color are
-- GTA's blip icon and colour numbers (825 is a sports car, 8 is pink).
Config.Blip = {
    show   = true,
    sprite = 825,
    color  = 8,
    scale  = 0.8,
}

--- Who may work on a car someone owns, from its driver's seat:
---   'anyone'        anyone can modify any vehicle
---   'ownerTuning'   only its owner can change performance and tuning; anyone can change looks and repair
---   'owner'         only its owner can customise it; anyone can still repair it
--- A car nobody owns is open to whoever drives it.
Config.WhoCanModify = 'anyone'

-- Camera: shots are measured from the car's own size, so one set works on every vehicle.

Config.Camera = {
    -- true: opening a part moves the camera to that part's own shot (the framings below). false: the camera stays
    -- on the orbit shot until the player moves it. Players can switch it with the shop's Camera button.
    followParts     = true,

    blendRate       = 3.0,
    pitchMin        = -12.0,
    pitchMax        = 60.0,

    -- Zoom limits are multiples of the distance that fills the frame with the car, not metres.
    zoomMin         = 0.25,
    zoomMax         = 2.20,
    zoomStep        = 0.10,

    -- Slow drift round the car after `delay` seconds without input. Off by default.
    turntable = { enabled = false, delay = 2.0, speed = 8.0 },

    -- How the camera swings in when the shop opens.
    enterTime    = 0.85,
    enterRateMin = 2.6,
    enterRateMax = 20.0,

    -- Look speed. GTA's own mouse sensitivity is already applied on top of this.
    sensitivity = 1.00,   -- the main dial
    yawSpeed    = 16.0,   -- degrees per unit of look input
    pitchSpeed  = 10.0,
    deadzone    = 0.005,
    invertX     = false,
    invertY     = false,

    --- One shot per shop area (nothing is in metres):
    ---   yaw        bearing from the car's nose: 0 directly behind, 180 dead in front
    ---   pitch      degrees above the car
    ---   distRatio  multiple of the distance that just fills the frame with the car
    ---   aim        point to look at, as a fraction of the car's box: 0,0,0 centre, y +1 nose, z +1 roof, x +1 right
    ---   aimPitch, aimYaw  degrees nudged off that point
    framings = {
        -- `default` is the shot you get on entry. Shelves use these by name (Config.Sections).
        default     = { yaw = 155.0, pitch =  1.3, distRatio = 1.28, aim = { x = 0.00, y =  0.00, z =  1.00 }, aimPitch = -8.0, fov = 40.0 },
        spoiler     = { yaw =  25.0, pitch = 18.0, distRatio = 0.75, aim = { x = 0.00, y = -0.75, z =  0.95 }, aimPitch = -3.0, fov = 36.0 },
        frontbumper = { yaw = 165.0, pitch = 16.0, distRatio = 0.70, aim = { x = 0.00, y =  0.85, z =  0.10 }, aimPitch = -3.0, fov = 36.0 },
        rearbumper  = { yaw =  10.0, pitch =  6.0, distRatio = 0.70, aim = { x = 0.00, y = -0.85, z =  0.10 }, aimPitch = -3.0, fov = 36.0 },
        sideskirt   = { yaw =  90.0, pitch =  8.0, distRatio = 0.75, aim = { x = 0.60, y =  0.00, z =  0.05 }, aimPitch = -3.0, fov = 34.0 },
        exhaust     = { yaw =  25.0, pitch = -4.0, distRatio = 0.60, aim = { x = 0.30, y = -0.85, z = -0.20 }, aimPitch = -3.0, fov = 32.0 },
        rollcage    = { yaw =  60.0, pitch = 10.0, distRatio = 0.80, aim = { x = 0.00, y =  0.05, z =  0.75 }, aimPitch = -3.0, fov = 38.0 },
        grille      = { yaw = 172.0, pitch =  5.0, distRatio = 0.65, aim = { x = 0.00, y =  0.88, z =  0.35 }, aimPitch = -3.0, fov = 34.0 },
        hood        = { yaw = 150.0, pitch = 41.0, distRatio = 0.70, aim = { x = 0.00, y =  0.45, z =  0.60 }, aimPitch = -3.0, fov = 36.0 },
        roof        = { yaw =  45.0, pitch = 44.0, distRatio = 0.85, aim = { x = 0.00, y =  0.00, z =  0.95 }, aimPitch = -3.0, fov = 38.0 },
        trim        = { yaw = 120.0, pitch =  6.0, distRatio = 0.60, aim = { x = 0.35, y =  0.30, z =  0.45 }, aimPitch = -3.0, fov = 32.0 },
        wheels      = { yaw =  62.0, pitch = -4.0, distRatio = 0.37, aim = { x = 0.55, y =  0.55, z = -0.55 }, fov = 32.0 },
        -- Paints > Wheel Colour: `wheels` from further round the front. Only the yaw differs.
        wheelpaint  = { yaw = 134.0, pitch = -4.0, distRatio = 0.37, aim = { x = 0.55, y =  0.55, z = -0.55 }, fov = 32.0 },
        livery     = { yaw =  90.0, pitch =  8.0, distRatio = 0.90, aim = { x = 0.40, y =  0.00, z =  0.35 }, aimPitch = -3.0, fov = 36.0 },
    },
    default = 'default',

    -- With the picker column open on the `default` shot, the camera swings to this yaw (the front
    -- left headlight) and stays there when the column closes. false = never swing.
    shiftedYaw = 207.0,
}

-- Shop areas: which framing each shelf uses, by mod slot. A slot not listed uses its section's framing.
Config.Areas = {
    [0]  = 'spoiler',
    [1]  = 'frontbumper',
    [2]  = 'exhaust',        -- rear bumper
    [3]  = 'sideskirt',
    [4]  = 'exhaust',
    [5]  = 'default',        -- roll cage
    [6]  = 'frontbumper',    -- grille
    [7]  = 'hood',
    [10] = 'roof',
    [20] = 'wheels',         -- tyre smoke
    [23] = 'wheels',
    [22] = 'default',        -- xenon lights: with the list open, the camera swings to the headlight
    [25] = 'rearbumper',     -- plate holder
    [26] = 'rearbumper',     -- vanity plate
    [27] = 'trim',
    [29] = 'trim',           -- dashboard
    [31] = 'trim',           -- door speakers
    [32] = 'trim',           -- seats
    [36] = 'trim',           -- speakers
    [37] = 'rearbumper',     -- trunk: the boot opens
    [39] = 'hood',           -- engine block: the bonnet opens
    [40] = 'hood',           -- air filter: the bonnet opens
    [41] = 'hood',           -- struts: the bonnet opens
    [42] = 'sideskirt',      -- arch covers
    [43] = 'roof',           -- aerials
    [45] = 'sideskirt',      -- tank
    [46] = 'sideskirt',      -- windows / left door
    [47] = 'sideskirt',      -- right door
    [48] = 'default',        -- livery
    [49] = 'roof',           -- light bar
    neon       = 'default',      -- neon layout and colour: the whole car, low, so the glow under it shows
    neoncolor  = 'default',
    -- Paint targets, by their ids.
    color1     = 'default',
    color2     = 'default',
    pearl      = 'default',
    wheelcolor = 'wheelpaint',
    interior   = 'trim',         -- into the cabin, as for the trim
    dashboard  = 'trim',
    -- Tuning categories have no entry: the camera stays where it is.
}

-- What the shop sells
-- GTA mod slots; `id` is the number SetVehicleMod takes. A slot the car has no parts for is hidden. A car that names a
-- slot itself shows its own name; these names are for the rest.

--- Slots that are a LIST of parts: pick one, or -1 for stock. 25 onwards are Benny's parts.
Config.Cosmetics = {
    { id = 0,  name = 'Spoilers',        price = 1200 },
    { id = 1,  name = 'Front Bumper',    price = 2400 },
    { id = 2,  name = 'Rear Bumper',     price = 2400 },
    { id = 3,  name = 'Side Skirts',     price = 1800 },
    { id = 4,  name = 'Exhaust',         price = 1600 },
    { id = 5,  name = 'Roll Cage',       price = 3200 },
    { id = 6,  name = 'Grille',          price = 1400 },
    { id = 7,  name = 'Hood',            price = 2600 },
    { id = 8,  name = 'Fenders',         price = 1900 },
    { id = 9,  name = 'Right Fender',    price = 1900 },
    { id = 10, name = 'Roof',            price = 2100 },
    { id = 14, name = 'Horns',           price = 900  },
    { id = 25, name = 'Plate Holder',    price = 600  },
    { id = 26, name = 'Vanity Plate',    price = 800  },
    { id = 27, name = 'Trim',            price = 900  },
    { id = 28, name = 'Ornaments',       price = 700  },
    { id = 29, name = 'Dashboard',       price = 1200 },
    { id = 30, name = 'Dials',           price = 800  },
    { id = 31, name = 'Door Speakers',   price = 900  },
    { id = 32, name = 'Seats',           price = 1600 },
    { id = 33, name = 'Steering Wheel',  price = 1100 },
    { id = 34, name = 'Shift Lever',     price = 600  },
    { id = 35, name = 'Plaques',         price = 500  },
    { id = 36, name = 'Speakers',        price = 1500 },
    { id = 37, name = 'Trunk',           price = 1800 },
    { id = 38, name = 'Hydraulics',      price = 4500 },
    { id = 39, name = 'Engine Block',    price = 3000 },
    { id = 40, name = 'Air Filter',      price = 1400 },
    { id = 41, name = 'Struts',          price = 1800 },
    { id = 42, name = 'Arch Covers',     price = 1600 },
    { id = 43, name = 'Aerials',         price = 700  },
    { id = 44, name = 'Exterior Trim',   price = 1200 },
    { id = 45, name = 'Tank',            price = 1500 },
    { id = 46, name = 'Windows',         price = 1000 },
    { id = 47, name = 'Doors',           price = 1900 },
    { id = 49, name = 'Light Bar',       price = 1200 },
}

--- Wheels. 23 is a car's wheels; 24 is a bike's rear wheel.
Config.Wheels = {
    { id = 23, name = 'Wheels',          price = 3400 },
    { id = 24, name = 'Rear Wheels',     price = 3400 },
}

--- The wheel ranges, by GTA wheel-type id. A range the car can't take is skipped.
Config.WheelCategories = {
    [0]  = 'Sport',
    [1]  = 'Muscle',
    [2]  = 'Lowrider',
    [3]  = 'SUV',
    [4]  = 'Offroad',
    [5]  = 'Tuner',
    [6]  = 'Motorcycle',
    [7]  = 'High End',
    [8]  = "Benny's Originals",
    [9]  = "Benny's Bespoke",
    [10] = 'Open Wheel',
    [11] = 'Street',
    [12] = 'Track',
}

--- Performance parts: ordinary GTA mod slots. The Turbo (slot 18) is whip's turbo, sold in stages (Config.Turbo.Stages);
--- GTA's own turbo part goes on with it, for its sound.
Config.Performance = {
    { id = 11, name = 'Engine',          price = 12000 },
    { id = 12, name = 'Brakes',          price = 8000  },
    { id = 13, name = 'Transmission',    price = 11000 },
    { id = 15, name = 'Suspension',      price = 6500  },
    { id = 16, name = 'Armour',          price = 9000  },
}

--- Slots that are on or off rather than a list. The Turbo is the exception: a list of Config.Turbo.Stages, each at its
--- own price (its price here is not used).
Config.Toggles = {
    { id = 18, name = 'Turbo',           price = 0     },
    { id = 20, name = 'Tyre Smoke',      price = 1500  },
    { id = 22, name = 'Xenon Lights',    price = 2500  },
}

--- Tyre Smoke is a list: Off, then these colours (r, g, b). Changing the colour on a car that has it costs
--- `colourPrice`. Keep White first. Pure black (0, 0, 0) is GTA's red-white-and-blue smoke.
Config.TyreSmokeColours = {
    colourPrice = 500,
    options = {
        { name = 'White',  r = 254, g = 254, b = 254 },
        { name = 'Black',  r = 1,   g = 1,   b = 1   },
        { name = 'Blue',   r = 0,   g = 150, b = 255 },
        { name = 'Yellow', r = 255, g = 255, b = 50  },
        { name = 'Orange', r = 255, g = 153, b = 51  },
        { name = 'Red',    r = 255, g = 10,  b = 10  },
        { name = 'Green',  r = 10,  g = 255, b = 10  },
        { name = 'Purple', r = 153, g = 10,  b = 153 },
        { name = 'Pink',   r = 255, g = 102, b = 178 },
        { name = 'Grey',   r = 128, g = 128, b = 128 },
        { name = 'Patriot', r = 0,  g = 0,   b = 0   },
    },
}

--- Extras: parts GTA switches on and off on some cars, shown as "Extra 1", "Extra 2"... Each switch costs this and
--- keeps the car's damage.
Config.Extras = {
    price = 500,
}

--- Xenon Lights is a list: Off, then these colours; changing the colour on a car that has xenons costs `colourPrice`.
--- `index` is GTA's colour number (255 is stock); keep Stock first.
Config.XenonColours = {
    colourPrice = 750,
    options = {
        { index = 255, name = 'Stock' },
        { index = 0,   name = 'White' },
        { index = 1,   name = 'Blue' },
        { index = 2,   name = 'Electric Blue' },
        { index = 3,   name = 'Mint Green' },
        { index = 4,   name = 'Lime Green' },
        { index = 5,   name = 'Yellow' },
        { index = 6,   name = 'Golden Shower' },
        { index = 7,   name = 'Orange' },
        { index = 8,   name = 'Red' },
        { index = 9,   name = 'Pony Pink' },
        { index = 10,  name = 'Hot Pink' },
        { index = 11,  name = 'Purple' },
        { index = 12,  name = 'Blacklight' },
    },
}

--- Neon underglow, on the Cosmetics shelf as two lists (cars only, not motorbikes). Neon Layout picks which sides glow
--- (GTA's seven layouts, or Off, which is free) for `price`; Neon Colour picks one of these colours (r, g, b) for
--- `colourPrice`.
Config.Neon = {
    price       = 3000,
    colourPrice = 750,
    colours = {
        { name = 'White',         r = 222, g = 222, b = 255 },
        { name = 'Blue',          r = 2,   g = 21,  b = 255 },
        { name = 'Electric Blue', r = 3,   g = 83,  b = 255 },
        { name = 'Mint Green',    r = 0,   g = 255, b = 140 },
        { name = 'Lime Green',    r = 94,  g = 255, b = 1   },
        { name = 'Yellow',        r = 255, g = 255, b = 0   },
        { name = 'Golden Shower', r = 255, g = 150, b = 0   },
        { name = 'Orange',        r = 255, g = 62,  b = 0   },
        { name = 'Red',           r = 255, g = 1,   b = 1   },
        { name = 'Pony Pink',     r = 255, g = 50,  b = 100 },
        { name = 'Hot Pink',      r = 255, g = 5,   b = 190 },
        { name = 'Purple',        r = 35,  g = 1,   b = 255 },
        { name = 'Blacklight',    r = 15,  g = 3,   b = 255 },
    },
}

--- Window tint: not a mod slot, so its options are listed here.
Config.WindowTints = {
    price = 1500,
    options = {
        { index = 0, name = 'None' },
        { index = 1, name = 'Pure Black' },
        { index = 2, name = 'Darksmoke' },
        { index = 3, name = 'Lightsmoke' },
        { index = 4, name = 'Stock' },
        { index = 5, name = 'Limo' },
        { index = 6, name = 'Green' },
    },
}

-- Paint: colours are saved vehicle properties, not mod slots. Each target uses a string id where a slot number would go.

Config.PaintTargets = {
    { id = 'color1',     name = 'Primary',      price = 1800, prop = 'color1'      },
    { id = 'color2',     name = 'Secondary',    price = 1400, prop = 'color2'      },
    { id = 'pearl',      name = 'Pearlescent',  price = 2200, prop = 'pearlescent' },
    { id = 'wheelcolor', name = 'Wheel Colour', price = 900,  prop = 'wheelColor'  },
    -- The cabin's trim. Every car lists it; on one whose interior GTA does not paint, it changes nothing.
    { id = 'interior',   name = 'Interior',     price = 1200, prop = 'interiorColor' },
    -- The dashboard's accent, the same way.
    { id = 'dashboard',  name = 'Dashboard',    price = 1200, prop = 'dashboardColor' },
}

--- On the paint shelf, but a real mod slot (48).
Config.PaintExtras = {
    { id = 48, name = 'Livery', price = 2800 },
}

--- The finish tag on each swatch, from the colour name's first word. Any other name is tagged Classic.
Config.PaintFamilies = {
    order = { 'Classic', 'Metallic', 'Matte', 'Util', 'Worn', 'Metals', 'Chameleon' },
    -- first word of the colour name -> heading it appears under
    map = {
        Metallic = 'Metallic',
        Matte    = 'Matte',
        Util     = 'Util',
        Worn     = 'Worn',
        Brushed  = 'Metals',
        Chrome   = 'Metals',
    },
    default = 'Classic',
}

--- Every GTA paint. Only the index is sent or saved; the hex is the swatch (hex2 a second swatch colour, drawn as a
--- gradient). `family`, when set, wins over the first word.
Config.Colours = {
    { index = 0,   name = 'Metallic Black',            hex = '#080808' },
    { index = 1,   name = 'Metallic Graphite Black',   hex = '#0F0F0F' },
    { index = 2,   name = 'Metallic Black Steel',      hex = '#1C1E21' },
    { index = 3,   name = 'Metallic Dark Silver',      hex = '#292C2E' },
    { index = 4,   name = 'Metallic Silver',           hex = '#5A5E66' },
    { index = 5,   name = 'Metallic Blue Silver',      hex = '#777C87' },
    { index = 6,   name = 'Metallic Steel Gray',       hex = '#515459' },
    { index = 7,   name = 'Metallic Shadow Silver',    hex = '#323B47' },
    { index = 8,   name = 'Metallic Stone Silver',     hex = '#333333' },
    { index = 9,   name = 'Metallic Midnight Silver',  hex = '#1F2226' },
    { index = 10,  name = 'Metallic Gun Metal',        hex = '#23292E' },
    { index = 11,  name = 'Metallic Anthracite Grey',  hex = '#121110' },
    { index = 12,  name = 'Matte Black',               hex = '#050505' },
    { index = 13,  name = 'Matte Gray',                hex = '#121212' },
    { index = 14,  name = 'Matte Light Grey',          hex = '#2F3233' },
    { index = 15,  name = 'Util Black',                hex = '#080808' },
    { index = 16,  name = 'Util Black Poly',           hex = '#121212' },
    { index = 17,  name = 'Util Dark Silver',          hex = '#202224' },
    { index = 18,  name = 'Util Silver',               hex = '#575961' },
    { index = 19,  name = 'Util Gun Metal',            hex = '#23292E' },
    { index = 20,  name = 'Util Shadow Silver',        hex = '#323B47' },
    { index = 21,  name = 'Worn Black',                hex = '#0F1012' },
    { index = 22,  name = 'Worn Graphite',             hex = '#212121' },
    { index = 23,  name = 'Worn Silver Grey',          hex = '#5B5D5E' },
    { index = 24,  name = 'Worn Silver',               hex = '#888A99' },
    { index = 25,  name = 'Worn Blue Silver',          hex = '#697187' },
    { index = 26,  name = 'Worn Shadow Silver',        hex = '#3B4654' },
    { index = 27,  name = 'Metallic Red',              hex = '#690000' },
    { index = 28,  name = 'Metallic Torino Red',       hex = '#8A0B00' },
    { index = 29,  name = 'Metallic Formula Red',      hex = '#6B0000' },
    { index = 30,  name = 'Metallic Blaze Red',        hex = '#611009' },
    { index = 31,  name = 'Metallic Graceful Red',     hex = '#4A0A0A' },
    { index = 32,  name = 'Metallic Garnet Red',       hex = '#470E0E' },
    { index = 33,  name = 'Metallic Desert Red',       hex = '#380C00' },
    { index = 34,  name = 'Metallic Cabernet Red',     hex = '#26030B' },
    { index = 35,  name = 'Metallic Candy Red',        hex = '#630012' },
    { index = 36,  name = 'Metallic Sunrise Orange',   hex = '#802800' },
    { index = 37,  name = 'Metallic Classic Gold',     hex = '#6E4F2D' },
    { index = 38,  name = 'Metallic Orange',           hex = '#BD4800' },
    { index = 39,  name = 'Matte Red',                 hex = '#780000' },
    { index = 40,  name = 'Matte Dark Red',            hex = '#360000' },
    { index = 41,  name = 'Matte Orange',              hex = '#AB3F00' },
    { index = 42,  name = 'Matte Yellow',              hex = '#DE7E00' },
    { index = 43,  name = 'Util Red',                  hex = '#520000' },
    { index = 44,  name = 'Util Bright Red',           hex = '#8C0404' },
    { index = 45,  name = 'Util Garnet Red',           hex = '#4A1000' },
    { index = 46,  name = 'Worn Red',                  hex = '#592525' },
    { index = 47,  name = 'Worn Golden Red',           hex = '#754231' },
    { index = 48,  name = 'Worn Dark Red',             hex = '#210804' },
    { index = 49,  name = 'Metallic Dark Green',       hex = '#001207' },
    { index = 50,  name = 'Metallic Racing Green',     hex = '#001A0B' },
    { index = 51,  name = 'Metallic Sea Green',        hex = '#00211E' },
    { index = 52,  name = 'Metallic Olive Green',      hex = '#1F261E' },
    { index = 53,  name = 'Metallic Green',            hex = '#003805' },
    { index = 54,  name = 'Metallic Gasoline Blue Green', hex = '#0B4145' },
    { index = 55,  name = 'Matte Lime Green',          hex = '#418503' },
    { index = 56,  name = 'Util Dark Green',           hex = '#0F1F15' },
    { index = 57,  name = 'Util Green',                hex = '#023613' },
    { index = 58,  name = 'Worn Dark Green',           hex = '#162419' },
    { index = 59,  name = 'Worn Green',                hex = '#2A3625' },
    { index = 60,  name = 'Worn Sea Wash',             hex = '#455C56' },
    { index = 61,  name = 'Metallic Midnight Blue',    hex = '#000D14' },
    { index = 62,  name = 'Metallic Dark Blue',        hex = '#001029' },
    { index = 63,  name = 'Metallic Saxony Blue',      hex = '#1C2F4F' },
    { index = 64,  name = 'Metallic Blue',             hex = '#001B57' },
    { index = 65,  name = 'Metallic Mariner Blue',     hex = '#3B4E78' },
    { index = 66,  name = 'Metallic Harbor Blue',      hex = '#272D3B' },
    { index = 67,  name = 'Metallic Diamond Blue',     hex = '#95B2DB' },
    { index = 68,  name = 'Metallic Surf Blue',        hex = '#3E627A' },
    { index = 69,  name = 'Metallic Nautical Blue',    hex = '#1C3140' },
    { index = 70,  name = 'Metallic Bright Blue',      hex = '#0055C4' },
    { index = 71,  name = 'Metallic Purple Blue',      hex = '#1A182E' },
    { index = 72,  name = 'Metallic Spinnaker Blue',   hex = '#161629' },
    { index = 73,  name = 'Metallic Ultra Blue',       hex = '#0E316D' },
    -- GTA has two Metallic Bright Blues (70 and 74); both are real paints.
    { index = 74,  name = 'Metallic Bright Blue',      hex = '#395A83' },
    { index = 75,  name = 'Util Dark Blue',            hex = '#09142E' },
    { index = 76,  name = 'Util Midnight Blue',        hex = '#0F1021' },
    { index = 77,  name = 'Util Blue',                 hex = '#152A52' },
    { index = 78,  name = 'Util Sea Foam Blue',        hex = '#324654' },
    { index = 79,  name = 'Util Lightning Blue',       hex = '#152563' },
    { index = 80,  name = 'Util Maui Blue Poly',       hex = '#223BA1' },
    { index = 81,  name = 'Util Bright Blue',          hex = '#1F1FA1' },
    { index = 82,  name = 'Matte Dark Blue',           hex = '#030E2E' },
    { index = 83,  name = 'Matte Blue',                hex = '#0F1E73' },
    { index = 84,  name = 'Matte Midnight Blue',       hex = '#001C32' },
    { index = 85,  name = 'Worn Dark Blue',            hex = '#2A3754' },
    { index = 86,  name = 'Worn Blue',                 hex = '#303C5E' },
    { index = 87,  name = 'Worn Light Blue',           hex = '#3B6796' },
    { index = 88,  name = 'Metallic Taxi Yellow',      hex = '#F5890F' },
    { index = 89,  name = 'Metallic Race Yellow',      hex = '#D9A600' },
    { index = 90,  name = 'Metallic Bronze',           hex = '#4A341B' },
    { index = 91,  name = 'Metallic Yellow Bird',      hex = '#A2A827' },
    { index = 92,  name = 'Metallic Lime',             hex = '#568F00' },
    { index = 93,  name = 'Metallic Champagne',        hex = '#57514B' },
    { index = 94,  name = 'Metallic Pueblo Beige',     hex = '#291B06' },
    { index = 95,  name = 'Metallic Dark Ivory',       hex = '#262117' },
    { index = 96,  name = 'Metallic Choco Brown',      hex = '#120D07' },
    { index = 97,  name = 'Metallic Golden Brown',     hex = '#332111' },
    { index = 98,  name = 'Metallic Light Brown',      hex = '#3D3023' },
    { index = 99,  name = 'Metallic Straw Beige',      hex = '#5E5343' },
    { index = 100, name = 'Metallic Moss Brown',       hex = '#37382B' },
    { index = 101, name = 'Metallic Bison Brown',      hex = '#221918' },
    { index = 102, name = 'Metallic Beechwood',        hex = '#575036' },
    { index = 103, name = 'Metallic Dark Beechwood',   hex = '#241309' },
    { index = 104, name = 'Metallic Choco Orange',     hex = '#3B1700' },
    { index = 105, name = 'Metallic Beach Sand',       hex = '#6E6246' },
    { index = 106, name = 'Metallic Sun Bleached Sand',hex = '#998D73' },
    { index = 107, name = 'Metallic Cream',            hex = '#CFC0A5' },
    { index = 108, name = 'Util Brown',                hex = '#1F1709' },
    { index = 109, name = 'Util Medium Brown',         hex = '#3D311D' },
    { index = 110, name = 'Util Light Brown',          hex = '#665847' },
    { index = 111, name = 'Metallic White',            hex = '#F0F0F0' },
    { index = 112, name = 'Metallic Frost White',      hex = '#B3B9C9' },
    { index = 113, name = 'Worn Honey Beige',          hex = '#615F55' },
    { index = 114, name = 'Worn Brown',                hex = '#241E1A' },
    { index = 115, name = 'Worn Dark Brown',           hex = '#171413' },
    { index = 116, name = 'Worn Straw Beige',          hex = '#3B372F' },
    { index = 117, name = 'Brushed Steel',             hex = '#3B4045' },
    { index = 118, name = 'Brushed Black Steel',       hex = '#1A1E21' },
    { index = 119, name = 'Brushed Aluminium',         hex = '#5E646B' },
    -- Chrome is stored as black in carcols; the swatch is grey so it reads as chrome.
    { index = 120, name = 'Chrome',                    hex = '#C8CCD0' },
    { index = 121, name = 'Worn Off White',            hex = '#B0B0B0' },
    { index = 122, name = 'Util Off White',            hex = '#999999' },
    { index = 123, name = 'Worn Orange',               hex = '#B56519' },
    { index = 124, name = 'Worn Light Orange',         hex = '#C45C33' },
    { index = 125, name = 'Metallic Securicor Green',  hex = '#47783C' },
    { index = 126, name = 'Worn Taxi Yellow',          hex = '#BA8425' },
    { index = 127, name = 'Police Car Blue',           hex = '#2A77A1' },
    { index = 128, name = 'Matte Green',               hex = '#243022' },
    { index = 129, name = 'Matte Brown',               hex = '#6B5F54' },
    { index = 130, name = 'Worn Bright Orange',        hex = '#C96E34' },
    { index = 131, name = 'Matte White',               hex = '#D9D9D9' },
    { index = 132, name = 'Worn White',                hex = '#F0F0F0' },
    { index = 133, name = 'Worn Olive Army Green',     hex = '#3F4228' },
    { index = 134, name = 'Pure White',                hex = '#FFFFFF' },
    { index = 135, name = 'Hot Pink',                  hex = '#B01259' },
    { index = 136, name = 'Salmon Pink',               hex = '#F69799' },
    { index = 137, name = 'Metallic Vermillion Pink',  hex = '#8F2F55' },
    { index = 138, name = 'Orange',                    hex = '#C26610' },
    { index = 139, name = 'Green',                     hex = '#69BD45' },
    { index = 140, name = 'Blue',                      hex = '#00AEEF' },
    { index = 141, name = 'Metallic Black Blue',       hex = '#000108' },
    { index = 142, name = 'Metallic Black Purple',     hex = '#050008' },
    { index = 143, name = 'Metallic Black Red',        hex = '#080000' },
    { index = 144, name = 'Hunter Green',              hex = '#565751' },
    { index = 145, name = 'Metallic Purple',           hex = '#320642' },
    { index = 146, name = 'Metallic Very Dark Blue',   hex = '#00080F' },
    { index = 147, name = 'Modshop Black',             hex = '#080808' },
    { index = 148, name = 'Matte Purple',              hex = '#320642' },
    { index = 149, name = 'Matte Dark Purple',         hex = '#050008' },
    { index = 150, name = 'Metallic Lava Red',         hex = '#6B0B00' },
    { index = 151, name = 'Matte Forest Green',        hex = '#121710' },
    { index = 152, name = 'Matte Olive Drab',          hex = '#323325' },
    { index = 153, name = 'Matte Desert Brown',        hex = '#3B352D' },
    { index = 154, name = 'Matte Desert Tan',          hex = '#706656' },
    { index = 155, name = 'Matte Foliage Green',       hex = '#2B302B' },
    { index = 156, name = 'Default Alloy',             hex = '#414347' },
    { index = 157, name = 'Epsilon Blue',              hex = '#6690B5' },
    { index = 158, name = 'MP100 Gold',                hex = '#47391B' },
    { index = 159, name = 'MP100 Gold Satin',          hex = '#47391B' },
    { index = 160, name = 'MP100 Gold Spec',           hex = '#FFD859' },

    -- Chameleon: colour-shift paints (game build 2612 and later). The two swatch colours are a guide only; the real
    -- paint shifts with the light. Their colour ramps come from the chameleon_paint resource (fxmanifest.lua).
    { index = 161, name = 'Anodized Red Pearl',          hex = '#A3141F', hex2 = '#5C0A14', family = 'Chameleon' },
    { index = 162, name = 'Anodized Burgundy Pearl',     hex = '#6B1027', hex2 = '#A3141F', family = 'Chameleon' },
    { index = 163, name = 'Anodized Purple Pearl',       hex = '#6A2C9C', hex2 = '#33134F', family = 'Chameleon' },
    { index = 164, name = 'Anodized Blue Pearl',         hex = '#1E4FB0', hex2 = '#0F275C', family = 'Chameleon' },
    { index = 165, name = 'Anodized Green Pearl',        hex = '#1C7A3C', hex2 = '#6A9A1E', family = 'Chameleon' },
    { index = 166, name = 'Anodized Lime Pearl',         hex = '#6B9E1A', hex2 = '#2F5C12', family = 'Chameleon' },
    { index = 167, name = 'Anodized Copper Pearl',       hex = '#A0552A', hex2 = '#54285E', family = 'Chameleon' },
    { index = 168, name = 'Anodized Bronze Pearl',       hex = '#8C6A35', hex2 = '#4A3519', family = 'Chameleon' },
    { index = 169, name = 'Anodized Champagne Pearl',    hex = '#BFA67A', hex2 = '#7A6443', family = 'Chameleon' },
    { index = 170, name = 'Anodized Gold Pearl',         hex = '#C2961F', hex2 = '#6E5212', family = 'Chameleon' },
    { index = 171, name = 'Green/Blue Flip',             hex = '#1F7A3A', hex2 = '#1F4FA6', family = 'Chameleon' },
    { index = 172, name = 'Green/Red Flip',              hex = '#217A38', hex2 = '#A01E28', family = 'Chameleon' },
    { index = 173, name = 'Green/Brown Flip',            hex = '#3F7A2A', hex2 = '#6B4424', family = 'Chameleon' },
    { index = 174, name = 'Green/Turquoise Flip',        hex = '#2C7A2E', hex2 = '#168783', family = 'Chameleon' },
    { index = 175, name = 'Green/Purple Flip',           hex = '#24783A', hex2 = '#5C2A8C', family = 'Chameleon' },
    { index = 176, name = 'Teal/Purple Flip',            hex = '#12706C', hex2 = '#5A2A88', family = 'Chameleon' },
    { index = 177, name = 'Turquoise/Red Flip',          hex = '#178683', hex2 = '#A01F2A', family = 'Chameleon' },
    { index = 178, name = 'Turquoise/Purple Flip',       hex = '#178683', hex2 = '#5B2A8A', family = 'Chameleon' },
    { index = 179, name = 'Cyan/Red Flip',               hex = '#1489A3', hex2 = '#A01F2A', family = 'Chameleon' },
    { index = 180, name = 'Blue/Pink Flip',              hex = '#234CA0', hex2 = '#B43F78', family = 'Chameleon' },
    { index = 181, name = 'Blue/Green Flip',             hex = '#234CA0', hex2 = '#23803E', family = 'Chameleon' },
    { index = 182, name = 'Purple/Red Flip',             hex = '#5A2A88', hex2 = '#A01E2A', family = 'Chameleon' },
    { index = 183, name = 'Purple/Green Flip',           hex = '#5C2A8A', hex2 = '#24803C', family = 'Chameleon' },
    { index = 184, name = 'Magenta/Green Flip',          hex = '#9C1F74', hex2 = '#24803C', family = 'Chameleon' },
    { index = 185, name = 'Magenta/Yellow Flip',         hex = '#9C1F74', hex2 = '#C29A1A', family = 'Chameleon' },
    { index = 186, name = 'Burgundy/Green Flip',         hex = '#6A1428', hex2 = '#24783A', family = 'Chameleon' },
    { index = 187, name = 'Magenta/Cyan Flip',           hex = '#9C1F74', hex2 = '#1489A3', family = 'Chameleon' },
    { index = 188, name = 'Copper/Purple Flip',          hex = '#A0552A', hex2 = '#5A2A88', family = 'Chameleon' },
    { index = 189, name = 'Magenta/Orange Flip',         hex = '#9C1F74', hex2 = '#C2601A', family = 'Chameleon' },
    { index = 190, name = 'Red/Orange Flip',             hex = '#A01E26', hex2 = '#C2601A', family = 'Chameleon' },
    { index = 191, name = 'Orange/Purple Flip',          hex = '#C2601A', hex2 = '#5A2A88', family = 'Chameleon' },
    { index = 192, name = 'Orange/Blue Flip',            hex = '#C2601A', hex2 = '#234CA0', family = 'Chameleon' },
    { index = 193, name = 'White/Purple Flip',           hex = '#D6D3DE', hex2 = '#5E2C8E', family = 'Chameleon' },
    { index = 194, name = 'Red Rainbow Flip',            hex = '#A01E28', hex2 = '#C29A1A', family = 'Chameleon' },
    { index = 195, name = 'Blue Rainbow Flip',           hex = '#1F3F9A', hex2 = '#8A2C7E', family = 'Chameleon' },
    { index = 196, name = 'Dark Green Pearl',            hex = '#17482C', hex2 = '#2E6A86', family = 'Chameleon' },
    { index = 197, name = 'Dark Teal Pearl',             hex = '#0F4A50', hex2 = '#2E6A96', family = 'Chameleon' },
    { index = 198, name = 'Dark Blue Pearl',             hex = '#13295E', hex2 = '#3A6AA6', family = 'Chameleon' },
    { index = 199, name = 'Dark Purple Pearl',           hex = '#36184F', hex2 = '#6A4E9C', family = 'Chameleon' },
    { index = 200, name = 'Oil Slick Pearl',             hex = '#2E1F55', hex2 = '#1F5E50', family = 'Chameleon' },
    { index = 201, name = 'Light Green Pearl',           hex = '#6E9E7C', hex2 = '#A3BE8F', family = 'Chameleon' },
    { index = 202, name = 'Light Blue Pearl',            hex = '#6C93BA', hex2 = '#94B3CF', family = 'Chameleon' },
    { index = 203, name = 'Light Purple Pearl',          hex = '#8E7AB4', hex2 = '#C092A8', family = 'Chameleon' },
    { index = 204, name = 'Light Pink Pearl',            hex = '#C08AA2', hex2 = '#D6CEC2', family = 'Chameleon' },
    { index = 205, name = 'Off White Pearl',             hex = '#D8D3C6', hex2 = '#CDBE9E', family = 'Chameleon' },
    { index = 206, name = 'Soft Pink Pearl',             hex = '#D29CB0', hex2 = '#C08AA2', family = 'Chameleon' },
    { index = 207, name = 'Pastel Yellow Pearl',         hex = '#D3C487', hex2 = '#D8D3C6', family = 'Chameleon' },
    { index = 208, name = 'Pastel Green Pearl',          hex = '#A3C497', hex2 = '#D3C487', family = 'Chameleon' },
    { index = 209, name = 'Baby Blue Pearl',             hex = '#8CB2D4', hex2 = '#A3C497', family = 'Chameleon' },
    { index = 210, name = 'Cream Pearl',                 hex = '#D8C9A2', hex2 = '#D8D3C6', family = 'Chameleon' },
    { index = 211, name = 'White Prismatic Pearl',       hex = '#D9D9DD', hex2 = '#B4A6D2', family = 'Chameleon' },
    { index = 212, name = 'Graphite Prismatic Pearl',    hex = '#3A3C42', hex2 = '#4E5F80', family = 'Chameleon' },
    { index = 213, name = 'Blue Prismatic Pearl',        hex = '#1E3E98', hex2 = '#5C2C8C', family = 'Chameleon' },
    { index = 214, name = 'Purple Prismatic Pearl',      hex = '#57268E', hex2 = '#9C2878', family = 'Chameleon' },
    { index = 215, name = 'Pink Prismatic Pearl',        hex = '#B23C7E', hex2 = '#6A2C9C', family = 'Chameleon' },
    { index = 216, name = 'Red Prismatic Pearl',         hex = '#A11A28', hex2 = '#C2601A', family = 'Chameleon' },
    { index = 217, name = 'Green Prismatic Pearl',       hex = '#1E783A', hex2 = '#167A86', family = 'Chameleon' },
    { index = 218, name = 'Black Prismatic Pearl',       hex = '#141418', hex2 = '#3A2C66', family = 'Chameleon' },
    { index = 219, name = 'Black Oil Spill Prismatic',   hex = '#141418', hex2 = '#1F5A4A', family = 'Chameleon' },
    { index = 220, name = 'Black Rainbow Prismatic',     hex = '#141418', hex2 = '#7A2448', family = 'Chameleon' },
    { index = 221, name = 'Dark Holographic',            hex = '#2B2D34', hex2 = '#5A4C7E', family = 'Chameleon' },
    { index = 222, name = 'Light Holographic',           hex = '#C8CBD2', hex2 = '#98BED2', family = 'Chameleon' },
}

-- Services: work on the car, never previewed, applied only once paid.

--- Repair is the only service. A new entry is listed and priced; what it does to the car needs code.
Config.Services = {
    {
        id    = 'repair',
        name  = 'Repair',
        desc  = 'Panels, engine, tyres, and a wash with it.',
        price = 1000,
    },
}

--- The top-level shelves, in the order shown. `framing` names a shot in Config.Camera.framings;
--- false leaves the camera where it is.
Config.Sections = {
    { key = 'cosmetics',   name = 'Cosmetics',   framing = 'default' },
    { key = 'wheels',      name = 'Wheels',      framing = 'wheels'  },
    { key = 'performance', name = 'Performance', framing = false     },
    { key = 'extras',      name = 'Extras',      framing = 'default' },   -- shown only on a car that has extras
    { key = 'paints',      name = 'Paints',      framing = 'default' },
    { key = 'tuning',      name = 'Tuning',      framing = false     },
}

-- Tuning: engine swaps, stance, handling, drivetrain. What a car buys here is saved with the car.

Config.Tuning = {
    -- Flat prices. Stance, handling and drivetrain are bought once per car, then adjusted free.
    EngineSwapPrice = 25000,
    StancePrice     = 15000,
    SetupPrice      = 15000,
    DrivetrainPrice = 20000,

    -- Swapped engine power = donor's drive force × donor's weight ÷ this car's weight.
    -- MinDriveForce is the floor; MaxDriveForce the ceiling (false = none, a number like 0.6 caps it).
    MinDriveForce = 0.10,
    MaxDriveForce = false,

    -- These classes swap the engine sound only (14 boats, 15 helicopters, 16 planes), as their power figures would
    -- make a car a rocket or a brick. Remove a class to transplant its figures anyway.
    SoundOnlyEngineClasses = { 14, 15, 16 },

    -- GTA classes left out of the engine list (empty = show all). 0 compacts, 1 sedans, 2 SUVs,
    -- 3 coupes, 4 muscle, 5 sports classics, 6 sports, 7 super, 8 motorcycles, 9 off-road,
    -- 10 industrial, 11 utility, 12 vans, 14 boats, 15 helicopters, 16 planes, 17 service,
    -- 18 emergency, 19 military, 20 commercial, 22 open wheel.
    HiddenEngineClasses = {},

    -- Engine sound by model name. For add-on cars whose sound is named differently:
    -- ['model'] = 'soundname'.
    EngineSoundOverrides = {},

    -- Stance sliders: limits and steps. The server clamps every saved value to these.
    Stance = {
        Height = { min = -16, max = 16,  step = 0.5 },   -- ride height, cm: + raises, - lowers
        Track  = { min = -5,  max = 10,  step = 0.5 },   -- per axle, cm: + pushes the wheels out
        Camber = { min = -12, max = 4,   step = 0.5 },   -- per axle, degrees: - tilts the tops in
        Width  = { min = 80,  max = 140, step = 5 },     -- wheel width, % (custom rims only — GTA's rule)
        Size   = { min = 70,  max = 250, step = 5 },     -- wheel size, % of tyre and rim (custom rims only)

        -- Ride height: false (recommended) moves the body on its wheels, shown exactly as it drives; true moves the
        -- real suspension, which settles only once driven, so the shop cannot preview it.
        PhysicalHeight = false,

        -- Suspension travel follows ride height: perCm is the change per cm (0.04 = 4%), min/max the
        -- limits as a share of the car's own. Off (perCm 0): it hurts handling more than it helps.
        Travel = { perCm = 0, min = 0.3, max = 2.0 },

        -- Stance is drawn on tuned cars within this many metres of you.
        DrawRange = 150.0,

        -- Track (and 'follow' camber) is rewritten every frame, only for cars on screen within this many metres.
        -- Lower is cheaper with many stanced cars about.
        FrameRange = 60.0,

        -- Only the nearest get that every frame: at most NearCount cars within NearRange metres. The rest within
        -- FrameRange are checked every FarEvery frames.
        NearRange = 25.0,
        NearCount = 6,
        FarEvery  = 3,

        -- A near car whose wheels GTA has left alone for a second is checked every this many frames. 1 = every
        -- frame (no visible snap), 2 = every second frame, 3 = every third.
        SettledFrames = 1,

        -- How camber is applied:
        --   'handling' (recommended) written once into the car's suspension geometry; affects grip.
        --   'follow'   set every frame on top of GTA's wheel; looks only. Used if handling is refused.
        Mode = 'handling',
    },

    -- Handling sliders, as % of the car's own value (100 = stock). The server clamps every saved value to these.
    Setup = {
        Springs   = { min = 50, max = 200, step = 5 },    -- spring stiffness: + stiffer, - softer
        Dampers   = { min = 50, max = 200, step = 5 },    -- shock absorbers: + settles quicker, less bounce
        AntiRoll  = { min = 10, max = 200, step = 5 },    -- anti-roll bars: + less body lean in corners
        Steering  = { min = 80, max = 170, step = 5 },    -- how far the front wheels turn
        Grip      = { min = 70, max = 130, step = 1 },    -- tyre grip: - slides more (drift), + holds more
        Handbrake = { min = 50, max = 250, step = 10 },   -- handbrake strength
    },

    -- Drivetrain: stock, FWD, RWD or AWD. Split is AWD's front share in % (30 = 30/70 rear-biased).
    Drive = {
        Split = { min = 30, max = 70, step = 5 },
    },
}

-- Power: the turbo, nitrous, every car's top speed, and how long a gear change takes
-- What an admin saves in /whip → Settings → Autos (Power and Shifting groups) wins over these; a number outside what
-- the page allows is kept inside the limits, with a console line. Top speed, shift times and the gearbox computer
-- change every car on the server. Each can be turned off: TopSpeedBonusMph = 0, RealisticShifting = false,
-- Gearbox.Enabled = false.

-- Turbo: sold at Whiplash (Performance → Turbo) in stages, each the most boost (psi) a turbo makes, with a price.
-- A bigger turbo is slower to build boost. Add and reprice stages freely, but never remove one or change its psi once
-- bought: a car keeps the psi it bought, and a psi no longer listed gives it no boost and no refund. Each psi is a
-- whole number from 1 to 30, no two the same. Keep 15.
Config.Turbo = {
    Stages = {
        { psi = 5,  price = 10000 },
        { psi = 10, price = 15000 },
        { psi = 15, price = 20000 },
        { psi = 20, price = 25000 },
        { psi = 25, price = 30000 },
        { psi = 30, price = 35000 },
    },
    TorquePerPsi   = 0.033,  -- extra torque per psi at full boost: 0.033 = a 15 psi turbo adds about 50%, a 30 psi one 99%
    SpoolFastest   = 0.5,    -- seconds the smallest turbo (5 psi) takes to build full boost, foot flat at the limiter
    SpoolSlowest   = 3.0,    -- and the biggest (30 psi); the ones between in a straight line. About six times as long at idle revs
    ShiftLossMin   = 20,     -- each gear change dumps between these two percent of the boost
    ShiftLossMax   = 50,
}

-- Nitrous bottle: an item fitted from the inventory while sitting in the car. Hold Shift (A on a controller) to boost.
-- Cars and motorbikes only.
Config.Nitrous = {
    Torque         = 3.0,    -- the engine's torque while boosting: 3 = three times
    BottleSeconds  = 20,     -- seconds of boost in a full bottle
    InstallSeconds = 10,     -- how long fitting one takes
}

-- Top speed: how much faster every car and motorbike can go, in mph. The gears are made longer, so a car only gets
-- there if it has the power. 0 turns it off.
Config.TopSpeedBonusMph = 35

-- Gear change time: every number below is how long a change takes (up and down) compared with GTA's own, from
-- 0.25 (a sequential box, the quickest) through 1 (GTA's own) to 5 (very slow). Bicycles, boats, helicopters, planes
-- and trains are never touched.

-- RealisticShifting: true, every kind of vehicle shifts slowly when stock (ShiftTimeByClass, below) and each
-- transmission upgrade makes it quicker. False, the kinds use PlainShiftTimeByClass and an upgrade does only what
-- GTA's own does.
Config.RealisticShifting = true

-- With realistic shifting: the fully upgraded transmission's shift time, as a share of the stock
-- one. 0.09 is about a tenth: near 0.25 for most kinds. 1 = the upgrades do only what GTA's own do.
Config.TransmissionBestShare = 0.09

-- With realistic shifting: how far each upgrade goes, from stock (0) to fully upgraded (1).
Config.TransmissionSteps = { 0.25, 0.5, 1.0 }

-- With realistic shifting: each vehicle class's stock shift time.
Config.ShiftTimeByClass = {
    Compacts       = 3.7,
    Sedans         = 2.6,
    SUVs           = 2.2,
    Coupes         = 2.4,
    Muscle         = 3.0,
    SportsClassics = 3.0,
    Sports         = 1.6,
    Super          = 2.2,
    Motorcycles    = 4.0,
    OffRoad        = 4.0,
    Industrial     = 2.6,
    Utility        = 2.6,
    Vans           = 2.5,
    Service        = 2.5,
    Emergency      = 2.8,
    Military       = 3.0,
    Commercial     = 5.0,
    OpenWheel      = 2.0,
}

-- Without realistic shifting: each kind's, whatever the transmission. 1 = GTA's own.
Config.PlainShiftTimeByClass = {
    Compacts       = 1.0,
    Sedans         = 1.0,
    SUVs           = 1.0,
    Coupes         = 1.0,
    Muscle         = 1.0,
    SportsClassics = 1.0,
    Sports         = 1.0,
    Super          = 1.0,
    Motorcycles    = 1.0,
    OffRoad        = 1.0,
    Industrial     = 1.0,
    Utility        = 1.0,
    Vans           = 1.0,
    Service        = 1.0,
    Emergency      = 1.0,
    Military       = 1.0,
    Commercial     = 1.0,
    OpenWheel      = 1.0,
}

-- One car's own shift time by model name, instead of its kind's.
--   Config.ShiftTimeByModel = { sultan = 1.5, adder = 2.5 }
Config.ShiftTimeByModel = {}

-- Gearbox computer: changes gear like a real automatic. A light foot changes up early, a foot flat to the floor gets
-- GTA's own change at peak power. It tracks your "aggression" (builds while the pedal is down, fades slowly); held
-- long enough to reach Kickdown it changes down at once. Controller only for now (a trigger gives pedal depth).
-- Revs are GTA's: 0.2 at idle, 1.0 at the limiter.
Config.Gearbox = {
    Enabled = true,
    EcoUpRpm = 0.30,       -- a light foot changes up here (about 0.4 at half aggression, the limiter with the foot flat)
    EcoDownRpm = 0.21,     -- a light foot lets the revs fall this low before changing down
    SportDownRpm = 0.55,   -- a heavy foot changes down to keep the revs this high
    CoastDownRpm = 0.21,   -- foot off, driving calmly: the revs fall this low before it changes down
    RiseSeconds = 1.0,     -- how fast the aggression builds while the pedal is down
    FallSeconds = 4.0,     -- how slowly it comes back when the pedal lifts
    Kickdown = 0.8,        -- the aggression built this high: a change down of a gear or two
    KickdownRoom = 0.10,   -- a change down under throttle must land clear of this top share of the rev range
    HandsOff = 0.92,       -- from this aggression up, GTA's own box
}

-- The engine list tool (/whiplashengines)

--- Where /whiplashengines spawns the cars it measures (60 m below, hidden, one at a time). Pick open
--- ground away from players.
Config.EngineDumpAt = vector3(-670.59, -2186.69, 5.99)
