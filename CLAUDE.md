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
  Opened by anyone rule). Files `Zomboid/Lua/TienLastSeenWhere/<save>/<key>.txt` on the server (`getFileWriter`
  makes the folders; only .txt/.ini/.cfg/.log/.json allowed). Lines: `V\t2\thoursSurvived\tcharacterName`
  (the name for the Found by sandbox option, refreshed by `ForPlayer` from the descriptor; `Store.NameOf`), then
  `P\tkey\tkind\tx\ty\tz\ttype\troom\tbuilding\tt\tBase.A=2;Base.B=1\tparents\tids\tby\ttouch` (`-` = empty).
  Version 2 added the last four (`by` = username of whoever took the snapshot, for privacy and Found by; `touch` =
  last time the owner stood next to it, see MemoryRefresh; expiry uses `max(t, touch)`): `parents` (bags only) = the keys of what holds the bag, nearest first, `|`-separated, the last one
  the top holder (`f:` floor, `o:` object, `d:` corpse, `v:` vehicle), so the gone check knows whether the bag's square
  means anything and privacy can hide a bag inside a marked container (or bag); `ids` = `Base.A=12,34;...`, the IDs of
  the items in that snapshot that were marked private when it was taken (only those; snapshots store counts, not IDs).
  Version 1 lines (10 fields) still load through a second pattern, with neither. Each record also keeps `bySquare` (square key → set of place keys), maintained by every add/remove
  (`index` / `unindex` / `drop`), for `Store.KeysAt(record, x, y, z)`. Saved every 30 s real time when dirty
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
    (`record.version`, bumped by Put/Remove/clear/expiry; own + `_world` under Opened by anyone) and the flags
    (`seeAll`, `Privacy.Version()`) are unchanged.
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
  - Gone check (`checkGone`, started every 2 s from `onTick` as the job `gone`, one `Jobs.Step` per square, so it
    shares the adaptive budget and shows in the 5-minute job stats; online players on a server, local ones in single
    player; a player still on the same tile is skipped for up to 10 s): on the 3x3 around the player (same level, which also covers arriving with Go there), places of the
    player's record and of `_world` that the server's square no longer has are forgotten: an object container whose
    key (sprite + container type) no object there yields, a corpse whose index is past the square's body count, a floor
    with no world items, a bag (top holder floor / object / corpse only) whose ID is on no world item, in no container
    of an object or corpse there (`getItemWithIDRecursiv`). Bags held by a vehicle (the square is where the vehicle
    was) and old bags with no `parents`, and vehicles (unloaded vs gone cannot be told apart), are left to
    `ForgetAfterDays`. Object-container privacy marks on those squares (`Privacy.PlaceKeysAt`) are dropped the same
    way, whoever passes: gone is a fact, not one player's memory, and a stale mark would hide a new container built
    with the same sprite on the same spot.
    Only up close on purpose: you notice it is gone by being there. Other players' records are not touched (their
    memory), so they forget it when they pass by themselves. Before this, nothing ever noticed a removed container:
    with `ForgetAfterDays` = 0 places only went when reopened empty.
  - Rules: Mine = own record; Shared (MP only) = own + faction owner/members + every safehouse the player owns or belongs
    to (records loaded by username); Explored (Opened by anyone) = own + `_world`. The Everything rule and the live scan
    of containers around the player (which also fed Explored) were removed at the user's request: a loot radar, the
    expensive part (61 x 61 tiles x 7 levels per search), and rows nobody had seen. Saved values above Explored (old
    sandbox 5, mod option index 4) clamp to Explored; the option index is normalised at `OnGameStart`. The own record is listed first and is never filtered by privacy (what you saw yourself); every other source
    goes through the privacy viewer. Summary and find both keep, per place key, the newest visible snapshot as a whole
    (an older own sighting does not bring back an item someone has since taken; a place hidden from you in `_world`
    falls back to your own older sighting).
  - Privacy commands: `privacy` (reply: my marks with label data, `enabled`, `group` = isServer, `canSeeAll`);
    `privacySet {kind, key | id, level, locator}` (reply: the same, plus `reason` when refused: full / unknown / busy /
    invalid / off); `places` (job: my remembered object, vehicle and bag places, nearest 300, 100 a message).
    A place mark needs the key in my own record (corpses and floors cannot be marked). An item mark needs the item in my
    inventory (recursive), in the container of `locator` within 10 tiles, or on / in a bag on the 3x3 floor; a bag
    becomes a place mark `b:<id>`. After an item mark the server re-snapshots that container or floor square so its ID
    is in `_world` and my record at once. Summary and find take `seeAll` (honoured only for `Privacy.CanSeeAll`); the
    summary cache key includes it and `Privacy.Version()`.
  - Place keys: `o:x,y,z:sprite:containerType`, `v:sqlId:partId`, `d:x,y,z:#objectId`, `b:bagItemId`, `f:x,y,z`.
    Corpses are keyed by `IsoDeadBody:getObjectIDAsLong()` (saved with the body, sent to clients with the chunk, so
    both sides agree; 16-bit, repeats after ~65k bodies, harmless with the tile in the key). `LSW.FindBody(square, key)`
    resolves both forms; the old `d:x,y,z:<index>` form (position in `getDeadBodys()`, which shifted when a body on the
    same tile went away) is still read, and still written when a body has no ID yet (-1: a client copy before the
    server assigned one; `Watch.Locate` sends `bodyId` and `index`, the server prefers the ID).
    Object containers are found by sprite + container type (the object index differs between client and server copies).
    `type`: container type, `partId@vehicleScript`, `corpse`, the bag's full type, nil for floors.
- `server/TienLastSeenWhere_Privacy.lua`: privacy marks of every player in one file, `<save>/_privacy.txt` (lines
  `M\towner\tkind\tid\tlevel\tplaceKind\tx\ty\tz\ttype\troom\tfullType\tt`), read synchronously on first use (a few
  hundred lines at most: 200 marks per player), saved every 30 s when dirty and on `OnSave`. One global file because
  filtering needs every owner's marks, online or not. Kinds: `p` = place key (`o:`, `v:`, `b:`), `i` = item ID.
  Levels 1 only me, 2 my group (faction + safehouse, MP only; single player turns 2 into 1). Indexes `byPlace`,
  `byItem` (id → owner → level) and `bySquare` (object marks by square, for the gone check). Cleared per owner by a
  `Store.clearListeners` hook, i.e. on death and on the new-character check (a dead character cannot remember for
  you; a skill journal carrying them over is a possible later feature, deferred). Marks do not follow
  `ForgetAfterDays`: a mark whose memory expired stays (Marked list: "not remembered").
  - Meaning of a mark (the user's rule): **the marker does not tell.** It filters only the marker's own sightings;
    anyone else who sees the thing owns that sighting, and it spreads by the normal rules (their faction under Shared,
    `_world` under Opened by anyone). Every snapshot carries `by` (who took it, set in `remember`), so filtering knows
    whose marks apply: a Shared source applies only its owner's marks, a `_world` entry only its `by`'s marks (none
    known, i.e. old data: every mark).
  - `Privacy.Viewer(player, seeAll)` = nil (no filter) when the option is off or `seeAll` and `CanSeeAll` (MP:
    `role:hasAdminTool()`, single player: `-debug`). `viewer:visibleItems(entry, author, floors)` = nil if the place
    key or any of its `parents` carries a mark (by `author`, or by anyone when `author` is nil) against the viewer,
    else the items minus such marked IDs of the snapshot, but never fewer of a type than a `floors` sighting of that
    place holds (capped at what this snapshot has). Floors: the viewer's own snapshot. So what you saw yourself
    stays found even when a newer snapshot hides it. Counts, not IDs, because an item marked after a sighting has no
    ID in it; the cost is that seeing katanas there also lets you see a marked katana that replaced them. A thing
    marked by several players needs every applicable mark to allow the viewer. Group membership is computed once per
    owner per search.
  - Exposure is word of mouth (the user's model: knowledge travels by people talking). `remember` calls
    `Privacy.NoteSighting(player, entry)`: for every **only me** mark on the entry's key, its `parents` or its marked
    IDs, if the finder is not the owner but is in the owner's faction / safehouse (any local player in single player),
    the mark gets `exposedT` + `exposedBy`: a friendly found it and, not knowing it was a secret, will mention it, so
    the marker learns who. A finder from another faction never talks to the marker, so nothing is recorded; a my group
    mark is already shared with exactly the people who would tell, so it is never exposed. The marker sees
    "<name> found it, <age>" on the row and "Privacy (!)" on the tab while `exposedT` is newer than `ackT`; viewing the
    Marked list sends `privacy {ack}`, which sets `ackT`. Saved with the mark (lines have 15 fields), kept when
    re-marking at another level.
  - What the marker (or anyone) knows of a place follows the search rule: under Shared only their own and their
    group's sightings, so a stranger's visit never updates it (they learn the new state by opening it again, or the gone
    check when it is gone); Opened by anyone pools everyone's sightings by design.
  - No item **type** marks on purpose: one click would hide a type from everyone's world-wide results (griefing).
    Place and item marks need the marker to have seen the place or to hold / reach the item.
  - Not covered: the marker's own snapshots from before an item was marked hold no ID, so under Shared their group can
    still learn of it from them until the marker sees the place again (old data, accepted). `_world` keeps only the
    newest snapshot per place: if the marker looked last, an older sighting by someone else is no longer in it (it
    still reaches that player's faction under Shared).
- `client/TienLastSeenWhere_WindowPrivacy.lua`: the Privacy tab (methods added to `LSW.Window`; the window builds it in
  `createChildren` when `createPrivacyChildren` exists and shows the tab only while `LSW.IsPrivacyUseful()`: option
  on and the sandbox not forcing What I have seen). Filter box, view combo (Marked private / Containers I remember /
  On me and in reach), admin tick box "Show private (admin)" (visible when the server says `canSeeAll`; sets the
  client's `seeAll`, sent with every summary and find, and refreshes the search), list, buttons Only me / My group
  (hidden in single player) / Share / Show. On me and in reach = the inventory (recursive) plus the open loot window's
  container (recursive; the Floor as floor items, others with `Watch.Locate`), rebuilt when its signature changes
  (checked every second). Containers I remember are re-requested every 15 s while shown. Refusals show as bad halo text.
- Find tab columns: Place | Where (distance + floors) | Seen | Found by | Count. The header is five
  `ISResizableButton`s between the scope combo and the list (hidden in the On me scope), placed every frame by
  `layoutHeaders` from `colWidths` (where / seen / by; Count is fixed, Place takes the rest). Where, Seen and Found by
  are dragged by their **left** edge (`resizeLeft`, like vanilla's inventory Category header) and the column to their
  left gives or takes the width (Place for Where); `maximumWidth` keeps that neighbour above its minimum. Place and
  Count get `ISButton`'s mouse move handlers so they never resize. Note `ISResizableButton.new` writes
  `minimumWidth` on the class, so it is set on each header after `new`. Clicking a header sorts the places under each
  item by it (again = reverse; default Where, nearest first; ties by distance). `drawRow` reads `window:columns(right)`,
  the same edges. Text is cut with "..." to its column (`Window.Fit`; Kahlua strings are Java strings, so `sub` never
  splits a character). Player 0's window is registered with `ISLayoutManager` ("TienLastSeenWhere"):
  `SaveLayout` / `RestoreLayout` keep position, size, column widths and sort in `layout.ini` (saved on `OnPostSave`),
  never the visibility. Found by comes from the server (`finderOf` in `findJob`): `byMe`, `by` = the name
  (`Store.NameOf`: username, or character name with FoundByName = 2) only for the viewer's faction and safehouse members
  (any local player in single player), `bySomeone` for anyone else, nothing for old `_world` lines ("-"), plus `private`
  when the viewer has a mark on the place, its parents or a marked ID of that type ("You (private)"). Anonymous on
  purpose: names of strangers would show where other players have been. Default window 720 x 540 (min 520 x 300).
- Find tab top row: the scope combo, then on the right the search rule combo (`ruleCombo`, writes the mod option with
  `Options.SetSearchRule` + `PZAPI.ModOptions:save()`; disabled with "Set by the server" when the sandbox forces a rule;
  no Shared entry in single player), with "Private shown" (admin tick box on), the spinner and "Server busy" to its
  left. Show, Go there, Take and double-click `releaseKeyboard()` (unfocus both text boxes) so movement keys move.
- Privacy tab new finds: marks that come back `fresh` are put in `window.freshKeys` (key = `LSW.MarkKey`, which is also
  `rowKey`) and stay tinted, "NEW: <name> found it, <age>" and sorted first until the player leaves the tab or closes
  the window, although the server is acknowledged at once.
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
  every 15 s. Place rows are taller than item rows (`PLACE_ROW` = row + 8 px) so their iso arrow can be big: drawn in a
  column 1.7 rows wide, one world unit long at 0.95 of the row height (a diagonal is ~1.3 rows wide), 0.6 wide, with
  `drawTextureAllPoint` in absolute coordinates. A spinner (8 dots of `media/ui/circle.png` in the arrow colour) shows while matching, a find is due or the
  server has not finished. Scopes: Everywhere, This building (same
  building def), Nearby (30 tiles), On me (live walk of the inventory, no server). Rows: item header (icon, count) and
  places (iso mini arrow, label, distance, floors, age, count). Buttons: Show, Go there, Take (enabled only when the
  container is a loot window button or the floor square is in reach), Hide arrow. Double-click = Show.
  `drawRow` clips by hand (rects cut to the visible band, text/icon/arrow only when whole inside): the list's stencil
  did not clip in game with PZ_Optimization's retained UI on (`uiRetained`/`uiRetainedChildren`, which replays a
  child's recorded draw and stencil commands; a list whose only custom drawing is `doDrawItem` is not seen as modded),
  and vanilla's skip test `y + yScroll + height < 0` draws the row ending exactly on the top edge, where every wheel
  scroll stops, so that row showed over the scope box.
- `client/TienLastSeenWhere_Actions.lua`: finding the client's copy of a place, Take (`ISInventoryTransferUtil` from a
  container, `ISGrabItemAction` from the floor), Go there (walk to the square or a free adjacent one, then open the loot
  window on it when the walk ends within 1.8 tiles, 60 s timeout).
- `client/TienLastSeenWhere_Arrow.lua` + `client/TienLastSeenWhere_Route.lua`: the floor arrow (see below).
- `client/TienLastSeenWhere_Options.lua`: per-player `PZAPI.ModOptions`: Search rule combo (index 1..4 = rules 2..5),
  arrow colour picker (`addColorPicker`, with alpha), arrow size slider (%). Names and tooltips are passed as
  translation **keys**: vanilla `MainOptions:addModOptionsPanel` runs `getText` on every name/tooltip itself, and
  `getText` of an already translated "Arrow size (%)" (not a key) crashes the options screen (see ZomboidFixesB42's
  CLAUDE.md, ModOptions).
- `client/TienLastSeenWhere_Keys.lua`: vanilla key binding `LSW Find Item`, unbound by default (the user's choice; the
  sidebar button is the main way in).
- `client/TienLastSeenWhere_Sidebar.lua`: sidebar button right under Inventory (player 0 only, like every vanilla
  sidebar button). Wraps `ISEquippedItem:initialise`: after vanilla's, every child at or below the Inventory button's
  bottom moves down by one button + 15 px (vanilla's gap is a file-local `UI_BORDER_SPACING` 10, plus 5) and the button
  goes in the gap, sized like Inventory; the ZomboidFixesB42 hotbar button and the war button follow because they are
  placed from `adminBtn` / the lowest button. Icon `media/ui/Sidebar/<w>/TienLastSeenWhere_Off|On_<w>.png` by the
  Inventory button's width (48/64/80/96/128; vanilla rebuilds the sidebar when its size option changes), On while the
  window is open. Hidden in the tutorial. The icon is our own drawing (`sidebar_icon` in `scripts/make_art.py`: a map
  pin with an eye, grey Off / orange-red with a blue iris On, outlined like the game's icons: a thin white line outside a black one, no shadow; the pin fills the height, with the whole outline 2 px of the 4x
  supersampled canvas inside the image, since outline pixels past the edge were cut off in game; the outlines are a
  round dilation, because a square `MaxFilter` made the outline round the pin's tip flat and boxy), not
  built from vanilla sidebar icons, which would repeat the Inventory and Search buttons right next to it.
- `client/TienLastSeenWhere_Debug.lua`: with `-debug`, a world context submenu to aim the arrow at a square or remove it.
- `media/sandbox-options.txt`: `SearchRule` (enum 5, default 1), `FloorRule` (enum 3: in sight / in reach / off),
  `SmallItemDistance` (default 4), `ForgetAfterDays` (default 0 = never).

## The arrow and the highlight

- `Arrow.SetTarget(playerNum, place, fullType)` (Show, Go there, double-click; a second call for the same place keeps
  the current target instead of restarting it), `Arrow.Clear`, `Arrow.GetTarget`.
- Geometry in world tiles from the player's exact position: start 0.5, length 1.0, half width 0.25, length and width
  times the player's "Arrow size" mod option (50-200 %, default 100); the four corners are
  projected with `isoToScreenX/Y` and drawn with `getRenderer():renderPoly` in `OnPreUIDraw`, so it lies flat like a
  floor tile but is drawn over characters and walls. The first version drew it in `OnPostFloorLayerDraw`, which the
  B42 renderer (`FBORenderCell`) never fires: no arrow in game.
- No floor marker any more (the vanilla grid square marker is a pulsing ellipse that faded in again on every Show).
  Instead the place itself is highlighted with `setHighlighted(playerNum, true, false)` + `setHighlightColor` in the
  arrow colour: the container's object, the corpse, the vehicle, a bag's world item (or the object holding it), or for a
  floor place the world items of that type on the square. Objects are looked up again every second (the chunk may load
  later) and the highlight is re-applied every frame (the loot window clears highlights when the mouse leaves its
  buttons). Once the loot window shows the place (its selected container's parent is one of our objects, or for a floor
  place it shows the Floor within reach of the square), the target counts as found: our highlight stops for good and
  the object vanilla now highlights is left alone. Both writing `setHighlighted`/`setHighlightColor` on the same object
  in different colours made it flicker.
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
- Performance of the 2 s sweep.
- Column header: dragging each edge, the limits, sorting by each column, widths and window size kept after a save and
  restart; the rule combo writing the mod option (check Settings > Mods afterwards) and staying disabled when forced.
- Typing in the name box, then Show: WASD must walk.
- MemoryRefresh nearby: a stash you stand next to keeps its "Seen" age but does not expire.
- Gone check: no container is forgotten while it is still there (sprite changes of a container object would read as
  gone; none known). Smash a counter, burn a crate, take a floor bag, drag a corpse away: each is forgotten on passing.
- Privacy: two players in different factions; mark a counter, a bag in it and an item in it; the other player under
  Opened by anyone must not find them until opening the counter themselves; My group with a faction mate;
  the admin tick box; marks gone after death; a marked counter smashed loses its mark. Tab layout at the default size
  (the window is now 720 x 540), ISTickBox placement on the right, the Find column header lining up with the rows
  (scroll bar shown and hidden), `ISButton:setTitle` for "Privacy (!)", exposure appearing for the marker after
  another player opens a marked container, and clearing once the Marked list is viewed.

## Decisions

- Memory lives on the server (the user's choice): the client never sends contents, only where it looked.
- The search rule is a per-player mod option; the sandbox can force one rule on everyone.
- No "highlight unopened containers"; memories never expire unless `ForgetAfterDays` is set.
- Items other players drop count once seen.
- Privacy marks are per character (reset on death), sharing levels only me / my group, admins may tick a box to see
  everything, the whole feature has a sandbox option (on by default).
- No Everything rule and no live scan (user's call); search rules are Mine / Shared / Opened by anyone.
- MemoryRefresh (sandbox, default when opened) and FoundByName (sandbox, default username) are server choices.
- Marked exact items do not show where they are (the marker knows; the Find tab finds it). Corpse keys by index stay:
  only a tile with several bodies can point at the wrong one.
- Group sharing is instant and has no range: faction / safehouse members count as always in contact (no walkie,
  no meeting up, works while offline). Proximity or radio sharing was considered and declined: the mod is meant to
  make finding things easier, not to add rules to learn. Keep new features in that spirit.
- A mark means "the marker does not tell"; others who find it share it as usual. The marker hears about it only from
  their own faction / safehouse, by name (they would mention it); never from other factions. Found by names only the
  searcher's own group.
