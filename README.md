# Cozy Valley

An original farming & life-simulation game for Roblox, built entirely on
Linux with [Rojo](https://rojo.space) 7.7.1 and Luau. No Roblox Studio
required for development.

## Development workflow (Arch Linux)

Everything runs from this folder. The only required tool is `rojo`.

```bash
# Compile the whole project into a place file (build validation):
rojo build -o CozyValley.rbxlx

# Watch mode — push file changes to a running Studio session (optional,
# only needed if you later open the place in Studio elsewhere):
rojo serve
```

`rojo build` succeeding is the project's baseline correctness gate: it
verifies the Rojo mapping, script classes, and that every `.luau` file is
syntactically valid Lua/Luau (parse errors fail the build).

Optional local tooling (not required, not installed by default):
`stylua` for formatting, `luau-analyze`/Lune for static typing and
headless tests. If installed later, drop configs next to this README.

Version control is plain local Git with the private GitHub remote
(`origin`). The working procedure is: edit files here, `rojo build` to
validate, then commit small focused changes and `git push` when a
milestone step is reviewed. Never rewrite pushed history without an
explicit decision to do so.

```bash
git status                 # always check before committing
git add <paths>            # stage only intended files (never dot-files)
git diff --cached          # verify staged content
git commit -m "M<n>: <summary>"
git push                   # keep origin/main up to date after approval
```

## Architecture

```
default.project.json        Rojo mapping (edit service trees here)
src/
  shared/                   -> ReplicatedStorage.Shared (ModuleScripts)
    Config/                 Plain data tables (constants, seasons)
    Modules/                Shared logic (Remotes wrapper)
  server/                   -> ServerScriptService.Server (Script)
    init.server.luau        Thin entry point -> Init.luau
    Init.luau               Bootstrap: remotes -> ordered services
    Services/               Server modules with Name + Start()
  client/                   -> StarterPlayerScripts.Client (LocalScript)
    init.client.luau        Thin entry point -> Init.luau
    Init.luau               Bootstrap: shared -> remotes -> controllers
    Controllers/            Client modules with Name + Start()
```

Rules of thumb:

- **Server is authoritative.** Clients request; servers decide and replicate.
- **All networking goes through one folder**: `ReplicatedStorage.CozyRemotes`,
  created at boot by `src/shared/Modules/Remotes.luau`. Register new remotes
  in its `SPECS` table — do not scatter `FindFirstChild("SomeRemote")` calls.
- **New backend feature = a Service module** added to
  `src/server/Services/init.luau` (bootstrap logic in `src/server/Init.luau`) in dependency order.
- **New frontend feature = a Controller module** added to
  `src/client/Controllers/init.luau`.
- **Config is data-only** under `src/shared/Config/`; logic never lives there.

## Initialization order

1. Server boot (`init.server.luau`) creates `CozyRemotes` and all registered
   remotes, then starts services (`PingService`, `PlayerService`,
   `FarmService`).
2. Client boot (`init.client.luau`) waits for replication, initializes the
   `Remotes` wrapper, then starts controllers (`HUDController`,
   `FarmController`).
3. Each service/controller starts inside `pcall` so one failure cannot kill
   the whole boot.

## Milestones

- [x] **M1 Foundation** — architecture, bootstraps, Remotes wrapper, config,
  placeholder HUD, player spawn service
- [x] **M2 Farming** — server-authoritative soil plots, planting,
  watering, time-based growth, harvesting; debug keybindings until
  the M3 hotbar
- [ ] M3 Inventory — items, stacking, hotbar, selection
- [ ] M4 World — farm/town environment, interactables, day-night cycle
- [ ] M5 NPCs — dialogue, schedules, friendship
- [ ] M6 Systems — fishing, mining, crafting, cooking, weather, seasons
- [ ] M7 Polish — UI, audio, animation, performance, saving

## Farming (Milestone 2)

`src/server/Services/FarmService.luau` owns all farm state; clients only
send intent. Key pieces:

- **Plots**: a fixed grid (`Farming.Grid` in
  `src/shared/Modules/Farming.luau`) of server-built tiles under
  `Workspace.Farm.Plots`, keyed `"x,y"`.
- **Actions**: one `FarmAction` remote carries `Till | Plant | Water |
  Harvest`; the server validates type, grid bounds, reach, occupancy,
  seed id, season and maturity before anything changes, then broadcasts
  the resulting plot state on `FarmSync`. Per-player feedback via
  `FarmResult`; full state pull via `GetFarmSnapshot` for late joiners.
- **Growth**: a single heartbeat accumulates game minutes per crop
  (season multiplier from `Seasons.luau`, watered bonus vs dry penalty
  from `Crops.luau`). No per-crop tasks. Stage math lives in the shared
  `Farming` module so client rendering always agrees with the server.
- **Config**: crops in `src/shared/Config/Crops.luau`, items in
  `src/shared/Config/Items.luau` (extended by Milestone 3).
- **Debug controls** (until the hotbar exists): keys `1` hoe, `2` seeds,
  `3` watering can, `4` harvest, `E` use on the hovered tile. Planting
  uses a placeholder turnip seed and grants no items yet — both wired
  to real inventory in Milestone 3.

The farming clock inside `FarmService` is a minimal internal game clock
(minutes/day/year + season). Milestone 4's TimeService will replace it
behind the same interface.

## Validating without Studio

- `rojo build` must exit 0 (syntax + mapping check).
- Runtime behaviour (remote round-trips, spawn placement, HUD text) can only
  be truly verified in a Roblox runtime; until a headless runner (e.g. Lune)
  is adopted, treat those paths as reviewed-but-untested and say so.
