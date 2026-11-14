# whip_autos (Whiplash)

Whiplash, a car customisation shop: paint, parts, wheels, stance, engine swaps and more, paid for with in-game money.
And bolt-on power: a turbo sold in stages, a nitrous bottle, every car's top speed and how long its gear changes take.
For developers it is also whip's worked example of a shop built on whip: see "Learning from whip_autos" in
whip_core's docs (`docs.html#autos-patterns`).

## Install

- **Needs:** whip_core. Nothing to add to the database.
- **Two resources:** `whip_autos` (the shop) and `whip_autos_shop` (the WHIPLASH building in Burton, map files only).
  WHIP's txAdmin recipe installs both and adds `ensure whip_autos` and `ensure whip_autos_shop` to server.cfg. If you list
  resources one by one instead:
  `ensure whip_autos` after whip_core, and `ensure whip_autos_shop`.
- **The building replaces Los Santos Customs in Burton.** It streams 12 of Rockstar's `bt1_02` files, so another map
  of that building (or one that streams those files) will clash with it.
- **Never restart `whip_autos_shop` while players are on.** An interior unloading under them crashes their games.
  Restart the whole server instead. Restarting whip_autos or whip_core is fine: the building stays.
- **Upgrading an older server:** the old Turbocharger and Wrench items are retired. Every one players still have is
  taken away (at once from everything loaded, the rest as each character, stash or car loads), logged, not refunded.
  Cars that had the turbo keep a 15 psi one.

## How players use it

- **The shop:** drive onto the car lift inside the WHIPLASH building, open the F1 wheel and pick **Enter Whiplash**.
  Only the driver can. Nothing opens by itself as a car drives in.
- **Nitrous:** the Nitrous Bottle (item `nitro`). No shop sells it out of the box: stock it in one of your shops
  (/whip → Economy → Shops) or hand it out. It is used from the inventory while sitting in the car (a short bar), then
  Shift boosts (A on a controller). Cars and motorbikes only.

## Who can modify a car

/whip → Settings → Autos → **Who can modify a car**:

- **Anyone can modify any vehicle** (the default). Whoever drives a car onto the lift can change anything on it,
  including taking off parts the owner paid for, at no cost.
- **Only owners can modify performance and tuning.** On someone else's car: looks and repairs only. The Performance
  shelf's parts and turbo, and the Tuning shelf (engine swap, stance, handling, drivetrain), are the owner's.
- **Only owners can modify at all.** Anyone else can only repair it: the shop opens with Repair and no customisation.

A car nobody owns (a street car, a rental, a scenario's car) is open to whoever drives it, whichever you pick. Work
done on one lasts only as long as that car exists; the buyer is told after paying.

## The camera

Opening a part (the wheels, the exhaust, the spoiler) moves the camera to that part's own shot. The **Standard camera**
button at the bottom right of the shop (C, or RB on a controller) switches that off for the player who presses it:
the camera stays on the orbit shot and moves only when they turn or zoom it. Their choice is kept on their own PC.
/whip → Settings → Autos → **Camera moves to each part** is what players get until they press it.

## These change every car on the server

Not only cars that visited Whiplash, and police cars too. If players say "cars feel slow", it is almost always one of
these. All three are on /whip → Settings → Autos.

| Setting | Default | Off |
|---|---|---|
| Realistic shifting (Shifting) | On: every car changes gear 1.6 to 5 times slower than GTA's own, by kind of car; each transmission upgrade at Whiplash makes it quicker | GTA's own shift times |
| Top speed bonus (Power) | 35 mph more top speed for every car and motorbike, by longer gears (a car still needs the power to reach it) | 0 |
| Gearbox computer (Power) | On, for players on a controller: changes gear like a real automatic, from how hard they drive | GTA's own gearbox |

## Settings

- **The page:** /whip → Settings → Autos: the shop's name, floor and size, who can modify a car, the prices, the turbo
  and nitrous, top speed, shifting, and how far the tuning sliders go.
- **config.lua** holds the rest (the camera, the shelves, the parts' slot numbers, the gearbox's figures) and the
  defaults for the page.
- **A value saved on the page beats config.lua.** Once a setting is saved there, changing it in config.lua does
  nothing; the page's Reset puts config.lua's value back.
- **Turbo stages** (config.lua, `Config.Turbo.Stages`): reprice them freely, but never remove a stage or change its
  psi once players have bought it. A car keeps the psi it bought, and a psi no longer in the list gives it no boost and
  no gauge (and no refund); putting it back brings those turbos back. Each stage is a whole psi from 1 to 30, no two
  the same. Keep 15 psi: older turbos were moved onto it.

## Admin tools

All need `whip.devtools` **and developer mode switched on** (`/w`).

- `/whiplash`: open the shop on the car you drive, wherever you are (or close it if it is stuck open).
- `/whiplashtune engine|stance|setup|drive|clear ...`: put tuning straight on the car you drive. Type it alone for the
  full usage.
- `/whiplashengines`: rebuild the engine swap list (`engines.json`) by measuring every vehicle in the game. Takes
  minutes; run it after adding add-on cars. A prebuilt list ships, so swaps work on a fresh install.
- **Open Whiplash** in the Object Viewer (`/w`, G on a saved car): the shop on that car.

## When something goes wrong

| What | Check |
|---|---|
| The shop won't open | The car is on the lift (Settings → Autos → Floor and Floor size) and the player is the driver. Someone else may be working on that car. |
| The shop opens with Repair only, or without the Performance and Tuning shelves | Who can modify a car: the player does not own that car. |
| Paid, but the part isn't on | The server console says `refunded` or `COULD NOT REFUND` when a fit failed after payment; /whip's activity log has every sale as "Whiplash customisation". |
| Chameleon paints come out black | On Legacy, the server must force game build 3407 or newer (`sv_enforceGameBuild`), `whip_autos/stream/` must still be there, and no other resource may stream `vehicle_paint_ramps.ytd`. (`stream_enhanced/` is the same file for GTA V Enhanced.) |
| A turbo does nothing | Its stage was removed or its psi changed (see Turbo stages), or the Turbo's torque per psi is 0 on the settings page. |
| A swapped engine sounds wrong | An add-on car whose sound is named differently from its model: add it to `Config.Tuning.EngineSoundOverrides` in config.lua. |
| Cars feel slow or shift oddly | See "These change every car on the server". |
| The engine swap list is missing cars | Run `/whiplashengines` after adding add-on cars. |

## Credits

The Chameleon paint ramps (`stream/vehicle_paint_ramps.ytd`) are WildBrick142's Chameleon Paint [Add-On] 2.0, unchanged
(https://www.gta5-mods.com/misc/chameleon-paint-add-on), with thanks to Disquse and Rockstar Games. They must never be
sold or monetised.
