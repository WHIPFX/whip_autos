# whip_autos

Whiplash, the car customisation shop for [WHIP](https://github.com/WHIPFX/txAdmin-recipe). Players drive onto the
lift, try parts on and pay in cash or by bank. It also adds turbos, a nitrous bottle, and top speed and gear-change
settings for every car on the server.

The shop building in Burton is a separate resource, [whip_autos_shop](https://github.com/WHIPFX/whip_autos_shop).

## Features

- **Looks.** Body parts (Benny's included), wheels from 13 ranges, tyre smoke, xenon lights, window tint, extras,
  liveries, and every GTA paint, the colour-shifting Chameleon paints included.
- **Performance.** Engine, brakes, transmission, suspension and armour upgrades, and a turbo sold in stages from
  5 to 30 psi.
- **Tuning.** Engine swaps from other vehicles, stance (ride height, track, camber, wheel size and width),
  handling (springs, dampers, anti-roll, steering lock, grip, handbrake) and drivetrain (FWD, RWD or AWD).
- **Try before you buy.** Parts go on the car as the player browses. Leaving without paying puts the car back.
- **Repairs.** Panels, engine and tyres, with a wash.
- **Nitrous.** A Nitrous Bottle item, fitted from the inventory in a car or on a motorbike.
- **Every car.** A top speed bonus, gear changes timed by class that transmission upgrades make quicker, and a
  gearbox computer that shifts like an automatic for players on a controller.
- **Ownership rules.** Let anyone work on any car, or keep performance and tuning, or everything but repairs, to the
  car's owner.
- **Safe payments.** The server prices every order from its own config and refunds the payment if fitting fails.
- **Director.** A goal card that asks a player to customise a car, a card that opens Whiplash for them, and a
  Whiplash look for scenario cars.
- **Controller support** throughout the shop.

## Requirements

- `whip_core`.
- [whip_autos_shop](https://github.com/WHIPFX/whip_autos_shop) for the shop building. Without it, move the shop floor
  in the settings.

## Installation

WHIP's txAdmin recipe installs it, with whip_autos_shop.

By hand, put `whip_autos` and `whip_autos_shop` in your `resources` folder and add these lines to `server.cfg`,
after `ensure whip_core`:

```cfg
ensure whip_autos
ensure whip_autos_shop
```

There's no SQL to import.

**Updating:** if you've run `/whiplashengines`, copy `engines.json` out before you replace the folder.

## For players

Drive onto the lift inside Whiplash, open the **F1** wheel and pick **Enter Whiplash**. Only the driver can.

| Key | Controller | Does |
| --- | --- | --- |
| **Scroll** or **← →** | D-pad | Browse |
| Hold **right mouse** | Right stick | Turn the camera |
| **C** | **RB** | Standard camera: stays on the car instead of moving to each part |
| **Esc** | **B** | Back |
| **Backspace** | | Leave the shop |

**Nitrous:** use a Nitrous Bottle from the inventory while sitting in the car. Then hold **Shift** (**A** on a
controller) to boost. Players can rebind Shift in GTA's **Settings > Key Bindings > FiveM**.

## Configuration

Most settings are on **/whip > Settings > Autos**: the shop's name and floor, who can modify a car, every price, the
turbo and nitrous, top speed, shifting, and how far the tuning sliders go. `config.lua` holds their defaults and the
rest: camera shots, shelves, mod slots and the gearbox's figures. A value saved in game wins over `config.lua`;
**Reset** goes back to it.

Three settings change every car on the server, police cars included. If players say cars feel slow, check these
first:

| Setting | Default | Does |
| --- | --- | --- |
| Top speed bonus | 35 mph | Lengthens the gearing of every car and motorbike. A car still needs the power to reach it. 0 turns it off. |
| Realistic shifting | On | Stock gear changes take 1.6 to 5 times GTA's time, by class. Each transmission upgrade makes them quicker. |
| Gearbox computer | On | Shifts like an automatic, from how hard the player drives. Controller only. |

**Turbo stages** are `Config.Turbo.Stages` in `config.lua`. Reprice them freely, but don't remove a stage or change
its psi once players have bought it: a car keeps the psi it paid for, and a psi missing from the list gives no boost.

**Engine sounds:** an add-on car whose sound is named differently from its model goes in
`Config.Tuning.EngineSoundOverrides`.

The nitrous bottle is the item `nitro`. No shop sells it until you stock it in one.

## Admin tools

These need `whip.devtools` with developer mode on in `/w`.

| Command | Does |
| --- | --- |
| `/whiplash` | Opens the shop on the car you're driving, wherever you are. Again closes it. |
| `/whiplashtune` | Puts an engine, stance, handling setup or drivetrain on the car you're driving, free. Type it alone for the usage. |
| `/whiplashengines` | Rebuilds the engine swap list (`engines.json`) by measuring every vehicle in the game. Run it after adding add-on cars; it takes a few minutes. |

The Object Viewer (`/w`, **G** on a saved car) has **Open Whiplash**, which opens the shop on that car.

## Troubleshooting

| Problem | Check |
| --- | --- |
| The shop won't open | The car is on the lift (**Floor** and **Floor size**) and the player is driving it. Someone else may be working on it. |
| Only Repair, or no Performance and Tuning | **Who can modify a car**: the player doesn't own it. |
| Paid, but the part isn't on | The server console prints `refunded` or `COULD NOT REFUND`. The activity log lists each sale as "Whiplash customisation". |
| Chameleon paints come out black | Another resource streams `vehicle_paint_ramps.ytd`, or whip_autos' `stream/` folder is missing. |
| A turbo does nothing | Its psi is missing from `Config.Turbo.Stages`, or **Torque per psi** is 0. |
| The engine list is missing add-on cars | Run `/whiplashengines`. |

## For developers

whip_autos is WHIP's worked example of a shop that takes money for work on a car. **Learning from whip_autos** in
WHIP's docs (`whip_core/docs.html`) walks through it file by file.

The turbo's boost and the nitrous bottle are the vehicle stats `boost` and `nitro`. Read or react to them with
whip_core's vehicle stat exports (**Hearing a stat change: OnVehicleStatChange** in the docs). On the server,
`exports.whip_autos:GetOpenSessions()` lists who is in the shop.

## License

whip_autos is licensed under the GNU LGPL 3.0; see `COPYING.LESSER`, and `COPYING` for the GPL 3.0 it builds on.
`NOTICE.md` says what the licence doesn't cover, including three.js (MIT) and the Inter and Rajdhani fonts (SIL Open
Font License 1.1); `whip_core`'s `NOTICE.md` is the full list.

The Chameleon paint ramps (`vehicle_paint_ramps.ytd` in `stream/` and `stream_enhanced/`) are WildBrick142's
[Chameleon Paint [Add-On] 2.0](https://www.gta5-mods.com/misc/chameleon-paint-add-on), unchanged, with thanks to
Disquse and Rockstar Games. Their author's terms say they must never be sold or monetised, so a paid bundle must leave
this file out.
