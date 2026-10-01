# Tien's Last Seen Where

Project Zomboid B42 mod: search for an item by name among the containers and floors the character has **seen**, then
follow an isometric arrow on the floor to it. The live code is under `Contents/mods/TienLastSeenWhere/42/`. General
engine findings (rendering, world markers, stairs, loot window, files) go in
`~/Zomboid/Workshop/ZomboidFixesB42/CLAUDE.md`; this file only holds the reasoning behind this mod.

The Lua source has no comments on purpose. Non-obvious reasoning lives here; update this file when it changes.

## Status

First full implementation, not yet run in game (a dedicated server load is the only test so far). Things to verify are
listed under "To verify".

## Files

- `shared/TienLastSeenWhere_Jobs.lua`: time slicing. There are no threads for Lua (one Kahlua state on the game's main
  thread), so long work runs as coroutines (`coroutine` is registered by `J2SEPlatform`, vanilla just never uses it).
  `Jobs.Start(name, fn)` replaces a job of that name; `Jobs.Step()` inside loops yields once the tick's budget is spent
  (checked every 25 calls); `OnTick` resumes jobs round-robin, all jobs sharing one budget, so more jobs only means slower
  results, never more load. Never yield inside a callback Java calls (`table.sort` comparators etc.) and never across
  `pairs` of a table that may get new keys meanwhile (iterate an array instead).
  - Adaptive budget: the tick interval is averaged (EMA 0.2). Server: budget 8 ms, halved (down to 1) once a second while
    jobs run and ticks average over 130 ms (healthy = 10 updates a second, ~100 ms), +1 ms after 3 healthy seconds
    (< 110 ms). Client / single player: 3 ms, strained over 50 ms a frame, healthy under 34. A slowdown logs
    `[TienLastSeenWhere] server ticks are slow ...`; every 5 min a server with job activity logs its ms/s, jobs, budget,
    tick and slowdowns. `Jobs.Stats()`, `Jobs.IsStrained()`.
- `shared/TienLastSeenWhere_Core.lua`: commands, rule / floor-rule / kind constants, sandbox getters, `ResolveRule`
  (sandbox `SearchRule` 1 = each player's choice, else forced), helpers (`Split` with gmatch, `SquareKey`,
  `BuildingKey` = building def x,y, `RoomName`), and the transport: `ToServer` = `sendClientCommand` on an MP client,
  a direct `Server.Handle` call otherwise; `ToClient` = `sendServerCommand` on a server, a direct `Client.Handle`
  otherwise (single player: `sendServerCommand` does nothing there).
- `server/TienLastSeenWhere_Store.lua`: memory per character (key = username; single player usernames are
  forename+surname, so each character differs) plus `_world` (latest snapshot of every place anyone saw, used by the
  Opened by anyone / Everything rules). Files `Zomboid/Lua/TienLastSeenWhere/<save>/<key>.txt` on the server (`getFileWriter`
  makes the folders; only .txt/.ini/.cfg/.log/.json allowed). Lines: `V\t1\thoursSurvived`, then
  `P\tkey\tkind\tx\ty\tz\ttype\troom\tbuilding\tt\tBase.A=2;Base.B=1` (`-` = empty). Saved every 30 s real time when dirty
  (checked on `EveryOneMinute`, written by a job) and on `OnSave` (at once, cancelling a running save job); records idle
  5 min are unloaded. Each record keeps `order`, an array of keys appended whenever a key becomes present, so jobs can
  walk it across yields; removed keys stay in it (skipped) and a re-added key is appended again (jobs dedupe by key); the
  save job compacts it unless the record was cleared meanwhile. Death: `OnCharacterDeath` (fires on the
  server; `OnPlayerDeath` is local-player only) resets the record; also reset when the player's hours survived are below
  the stored ones (new character missed by the event). `ForgetAfterDays` drops places on load and each save pass.
- `server/TienLastSeenWhere_Server.lua`: commands.
  - `seenContainer` (a locator): the server resolves it to **its own** container and snapshots that (the client only says
    where it looked), within 10 tiles. Empty containers are forgotten.
  - `seenSquares` (`{x,y,z,near}` up to 300, within 45 tiles): snapshot of the square's world items. Items under 0.2 weight
    count only when `near` or within `SmallItemDistance`; otherwise previous small entries are kept (cannot tell from
    afar).
  - `summary` → every remembered type with a total count (places deduped by key), in chunks of 400 (`part`, `last`).
  - `find {types}` → per type the 40 nearest places, vehicles moved to where they are now (by `getSqlId`). Streams:
    every 300 ms the types that changed are sent (8 types a message), then a final round with every type and `last`.
  - Both run as jobs named per player (`summary:` / `find:<user>:<playerNum>`), so a new request cancels the old one.
    A find within 250 ms of the previous one waits (only the latest is kept). A summary request while one is running
    just retargets its reply; a finished summary is cached per player and reused while the records' change counters
    (`record.version`, bumped by Put/Remove/clear/expiry) are unchanged, or for 10 s under the Opened by anyone /
    Everything rules (live scan).
  - `seenContainer` / `seenSquares` are queued (at most 4000 waiting, extras dropped and counted in the log every ten
    minutes) and handled by the `ingest` job, one square or container per step.
  - Replies carry `busy` (budget lowered, or a job waiting over 3 s); the window then shows "Server busy" by the spinner.
  - Loading a character's file is a job too (`store:load:<key>`): `Store.Get` reads only the header line (hours
    survived, so the new-character check still works at once) and returns the record with `loading = true`; the rest is
    read about 2000 lines a second at the full server budget (one `string.match` per line). Meanwhile Put works (a loaded
    line never overwrites a key already present), Remove is remembered in `record.removed` so the loader skips that key,
    a clear (death, new character) stops the load and closes the reader, summary / find / floor jobs wait for it
    (`Store.WaitLoaded` → `Jobs.WaitWhile`), periodic saves skip loading records, and a forced save (`OnSave`) finishes the
    load first (`Jobs.Finish` runs a job to the end without yielding).
  - Rules: Mine = own record; Shared (MP only) = own + faction owner/members + every safehouse the player owns or belongs
    to (records loaded by username); Explored = `_world` + a live scan of explored containers; Everything = `_world` + a
    live scan of every container and floor. Live scan: 20 tiles, z ±3, cached 5 s per player, inside the job.
  - Place keys: `o:x,y,z:sprite:containerType`, `v:sqlId:partId`, `d:x,y,z:bodyIndex`, `b:bagItemId`, `f:x,y,z`.
    Object containers are found by sprite + container type (the object index differs between client and server copies).
    `type`: container type, `partId@vehicleScript`, `corpse`, the bag's full type, nil for floors.
- `client/TienLastSeenWhere_Watch.lua`: what counts as seen.
  - Loot window: wraps `ISInventoryPage.update`; the loot page counts as looked at while `isReallyVisible()` and not
    `isCollapsed` (vanilla's open/close sound test). The shown container is `inventoryPane.inventory`; a report goes
    400 ms after it or its signature (count + sum of item IDs) changes, so MP contents arriving after
    `requestServerItemsForContainer` are reported again. The Floor container reports the reachable 3x3 as `near`.
    `isExplored()` is not used: `refreshBackpacks` explores every adjacent container even while collapsed.
  - `Locate`: bag (`getContainingItem`, parent = floor square or the outer container's locator), vehicle part
    (`getVehiclePart`), corpse (`IsoDeadBody` parent, index in `getDeadBodys()`), object (square, object index, container
    index, type, sprite). Anything in the player's own inventory is skipped.
  - Floor in sight: every 2 s (a job per local player), squares within 20 tiles on the player's level with `isCanSee(playerNum)` that have world
    items (or were reported before, so removals are seen); dark squares (`getLightLevel < 0.3`) only within reach. A
    square is resent only when its signature changes or it is now seen up close.
  - Search mode: wraps `ISSearchManager:createIconsForWorldItems(square)` and reports that square as `near`.
- `client/TienLastSeenWhere_Client.lua`: requests (`request` id + `playerNum` echoed back, stale replies dropped),
  summary assembly, find parts merged per type (a new find keeps the old lists of types still wanted until replaced),
  `IsBusy` (a request with no reply part for 20 s stops counting), listeners.
- `client/TienLastSeenWhere_Window.lua`: search window. Matching is client side against the summary's types (display
  name prefix, then substring, then item tag paths), so names follow the player's language. Matching is a job
  (`window:match:<n>`) that publishes the best 40 so far every 150 ms; the `find` goes 300 ms after the final list
  changes; rows are rebuilt (`rebuildRows`, no matching) on every find part and scope change; the summary is refreshed
  every 15 s. A spinner (8 dots of `media/ui/circle.png` in the arrow colour) shows while matching, a find is due or the
  server has not finished. Scopes: Everywhere, This building (same
  building def), Nearby (30 tiles), On me (live walk of the inventory, no server). Rows: item header (icon, count) and
  places (iso mini arrow, label, distance, floors, age, count). Buttons: Show, Go there, Take (enabled only when the
  container is a loot window button or the floor square is in reach), Hide arrow. Double-click = Show.
- `client/TienLastSeenWhere_Actions.lua`: finding the client's copy of a place, Take (`ISInventoryTransferUtil` from a
  container, `ISGrabItemAction` from the floor), Go there (walk to the square or a free adjacent one, then open the loot
  window on it when the walk ends within 1.8 tiles, 60 s timeout).
- `client/TienLastSeenWhere_Arrow.lua` + `client/TienLastSeenWhere_Route.lua`: the floor arrow (see below).
- `client/TienLastSeenWhere_Options.lua`: per-player `PZAPI.ModOptions`: Search rule combo (index 1..4 = rules 2..5),
  arrow colour picker (`addColorPicker`, with alpha).
- `client/TienLastSeenWhere_Keys.lua`: vanilla key binding `LSW Find Item`, unbound by default (the user's choice; the
  sidebar button is the main way in).
- `client/TienLastSeenWhere_Sidebar.lua`: sidebar button right under Inventory (player 0 only, like every vanilla
  sidebar button). Wraps `ISEquippedItem:initialise`: after vanilla's, every child at or below the Inventory button's
  bottom moves down by one button + 15 px (vanilla's gap is a file-local `UI_BORDER_SPACING` 10, plus 5) and the button
  goes in the gap, sized like Inventory; the ZomboidFixesB42 hotbar button and the war button follow because they are
  placed from `adminBtn` / the lowest button. Icon `media/ui/Sidebar/<w>/TienLastSeenWhere_Off|On_<w>.png` by the
  Inventory button's width (48/64/80/96/128; vanilla rebuilds the sidebar when its size option changes), On while the
  window is open. Hidden in the tutorial. The icon is our own drawing (`sidebar_icon` in `scripts/make_art.py`: a map
  pin with an eye, grey Off / orange-red with a blue iris On, outlined like the game's icons: a thin white line outside a black one, no shadow), not
  built from vanilla sidebar icons, which would repeat the Inventory and Search buttons right next to it.
- `client/TienLastSeenWhere_Debug.lua`: with `-debug`, a world context submenu to aim the arrow at a square or remove it.
- `media/sandbox-options.txt`: `SearchRule` (enum 5, default 1), `FloorRule` (enum 3: in sight / in reach / off),
  `SmallItemDistance` (default 4), `ForgetAfterDays` (default 0 = never).

## The arrow and the highlight

- `Arrow.SetTarget(playerNum, place, fullType)` (Show, Go there, double-click; a second call for the same place keeps
  the current target instead of restarting it), `Arrow.Clear`, `Arrow.GetTarget`.
- Geometry in world tiles from the player's exact position: start 0.6, length 1.6, half width 0.4; the four corners are
  projected with `isoToScreenX/Y` and drawn with `getRenderer():renderPoly` in `OnPreUIDraw`, so it lies flat like a
  floor tile but is drawn over characters and walls. The first version drew it in `OnPostFloorLayerDraw`, which the
  B42 renderer (`FBORenderCell`) never fires: no arrow in game.
- No floor marker any more (the vanilla grid square marker is a pulsing ellipse that faded in again on every Show).
  Instead the place itself is highlighted with `setHighlighted(playerNum, true, false)` + `setHighlightColor` in the
  arrow colour: the container's object, the corpse, the vehicle, a bag's world item (or the object holding it), or for a
  floor place the world items of that type on the square. Objects are looked up again every second (the chunk may load
  later) and the highlight is re-applied every frame (the loot window clears highlights when the mouse leaves its
  buttons).
- Another floor: `Route.Waypoint` scans 40 tiles for staircases on the player's level (going up: bottom squares) or the level
  below (going down: top squares), picks the lowest (player → entry) + (exit → target), and the arrow aims at the entry,
  re-evaluated every second and when the level changes. No staircase: faded arrow straight at the target. A "1 up" /
  "1 down" badge is drawn at the tip.
- Arrival (within 1.6 tiles, same level): the arrow hides; 8 s later the target and its highlight are cleared.

## To verify in game

- The arrow in the UI pass (zoom, walking, stairs, split screen); the object highlight on each kind of place.
- `isCanSee` really means "in sight now"; light threshold 0.3 feels right.
- MP: the first view of an unexplored container is reported again once the items arrive.
- Vehicle part names (`IGUI_VehiclePart<id>`), container titles, mini arrows in the list (absolute coordinates).
- Go there opening the loot window on the right container; Take for floor items.
- Performance of the 2 s sweep and of the server live scan.

## Decisions

- Memory lives on the server (the user's choice): the client never sends contents, only where it looked.
- The search rule is a per-player mod option; the sandbox can force one rule on everyone.
- No "highlight unopened containers"; memories never expire unless `ForgetAfterDays` is set.
- Items other players drop count once seen.
