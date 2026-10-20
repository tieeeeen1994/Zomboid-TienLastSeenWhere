# Tien's Last Seen Where

Forgot where you saw that hammer? Type an item's name and see every container and floor where your character saw it,
then follow an arrow on the floor back to it.

- **Only what you have seen.** A container counts once you have looked inside it in the loot window. Containers you never
  opened are never searched, and a padlocked crate counts only for someone who can open it (key in hand), as in the
  loot window; the mod never lists, marks or takes from a container locked to you. Items lying on the floor count once they are in sight (small ones only up close, and in the
  dark only within reach), or when search mode spots them.
- **Search as you type.** Results are grouped by item, then by place, in columns you can resize and sort by: a small
  arrow pointing the way on screen, the place (counter, fridge, car trunk, corpse, floor, with the room), how far and
  which floor, how long ago it was seen, who found it (you, or the other player by name, as username or character
  name: a choice at the bottom of the window, or in the mod options) and how many. The window remembers its size, position and columns.
- **Where to look.** Everywhere, This building, Nearby, or On me (your own bags).
- **Show** puts an arrow on the floor at your feet, aimed at the place, and highlights the container (or the items on the floor) in the arrow colour. On another floor it points
  to the stairs first and shows how many floors up or down. **Go there** walks you to it and opens the loot window on
  it. **Take** picks the item up once it is within reach.
- **Memory follows the character.** It is kept on the server and forgotten when the character dies.
- **Who shares with whom.** Finding works like word of mouth: you only learn from players who would tell you.
  - Factions on: only faction members share, and only with their own faction. A player in no faction shares with
    nobody.
  - PVP and factions off: everyone shares with everyone.
  - PVP on, factions off: nobody shares.
  - Safehouses never count. The search window only offers the search rules the server allows, and whoever told you
    is always named.
- **Privacy.** Right-click a container (in the world or its loot window button) or an item and pick Privacy, or use
  the window's Privacy tab (containers around you, containers you remember, what you marked), to mark it private to
  you; a container can be marked even while it is empty. What you saw of it is then left out of other players'
  searches.
  Anyone else who sees it for themselves remembers it and shares it as usual. A marked bag hides everything in it.
  Your own private things show as "You (private)" in your results.
  If someone from your own faction finds it, they mention it: the Privacy tab shows "Privacy (!)" and the mark says
  who and when. Other factions never tell you. Privacy is not offered where nobody shares. Marks are
  forgotten when your character dies. Admins can tick a box to see private things anyway.
- **Manage (admins).** A Manage tab lists every player who remembers something. Pick one to see what they remember,
  then make them forget an item everywhere, at single places, or everything. Only their own memory by default; tick
  "Also from shared knowledge" to also remove what they saw last from what Opened by anyone finds. Their privacy
  marks are kept, and seeing something again brings it back.
- **Gone is gone.** Walk past a container, corpse, bag or floor spot you remember and it is no longer there (smashed,
  burnt, moved, picked up): it is forgotten.

## What changed in 3.0.0

| | Before | Now |
|---|---|---|
| Who shares | Opened by anyone pooled every player's sightings for everyone | Word of mouth: with factions on, only faction members share, with their own faction. With PVP and factions off, everyone shares. With PVP on and factions off, nobody shares |
| Safehouses | Safehouse members shared like faction members | Safehouses never count |
| Found by | Strangers could show as "Someone" | Whoever told you is always named |
| Search rules | All three always offered | Only the rules the server allows; a rule it does not allow becomes the nearest one it does |
| Privacy marks | Only me or My group | Only me. Old My group marks show as "Private: my faction". Privacy is hidden where nobody shares |
| Arrow to another floor | Doors counted as walls when picking a staircase, and the pick never changed until you changed floor | Doors count as open, and the staircase is picked again after you walk 20 tiles |

## Opening the search

- The **magnifier button** on the left sidebar, right under Inventory, opens and closes the search window.
- **Find an item you have seen** (Options > Key Bindings > Last Seen Where) does the same from the keyboard. Not bound by
  default.

## Settings

Per player, in Settings > Mods:

- **Search**: What I have seen (default), Shared with my faction, or Opened by anyone, as far as the server allows
  (see Who shares with whom). Also in the search window.
- **Found by shows**: the server's setting (default), username or character name. Also at the bottom of the search
  window.
- **Arrow colour**: colour and opacity of the arrows; the highlight uses the colour.
- **Arrow size**: length and width of the arrow on the floor, 50 to 200 %.

Sandbox (server):

- **Search rule**: each player's choice (default), or one rule for everyone. A rule the server's PVP and Faction
  settings do not allow becomes the nearest one they do.
- **Items on the floor**: in sight (default), within reach, or off.
- **Small item distance**: how close items lighter than 0.2 must be to be noticed on the floor. Default 4 tiles.
- **Forget after (days)**: forget places not seen again for this many in-game days. Default 0, never.
- **Privacy**: lets players mark containers and items private. On by default.
- **Keep memories fresh**: with Forget after (days) set, a container's clock restarts when it is opened (default), or
  also when you stand next to it.
- **Found by shows**: usernames (default) or character names. Each player can pick their own.

Build 42 only. Must be installed on the server and on every client.
