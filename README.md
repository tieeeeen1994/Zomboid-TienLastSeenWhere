# Tien's Last Seen Where

Forgot where you saw that hammer? Type an item's name and see every container and floor where your character saw it,
then follow an arrow on the floor back to it.

- **Only what you have seen.** A container counts once you have looked inside it in the loot window. Containers you never
  opened are never searched. Items lying on the floor count once they are in sight (small ones only up close, and in the
  dark only within reach), or when search mode spots them.
- **Search as you type.** Results are grouped by item, then by place, in columns you can resize and sort by: a small arrow pointing the way on
  screen, the place (counter, fridge, car trunk, corpse, floor, with the room), how far and which floor, how long ago
  it was seen, who found it (you, a faction or safehouse member by name, or "Someone") and how many.
- **Where to look.** Everywhere, This building, Nearby, or On me (your own bags).
- **Show** puts an arrow on the floor at your feet, aimed at the place, and highlights the container (or the items on the floor) in the arrow colour. On another floor it points
  to the stairs first and shows how many floors up or down. **Go there** walks you to it and opens the loot window on
  it. **Take** picks the item up once it is within reach.
- **Memory follows the character.** It is kept on the server and forgotten when the character dies.
- **Privacy.** In the window's Privacy tab, mark a container you remember, or an item you carry or can reach, as
  private to you or to your faction and safehouse. What you saw of it is then left out of other players' searches.
  Anyone else who sees it for themselves remembers it and shares it as usual. A marked bag hides everything in it.
  If someone from your own faction or safehouse finds it, they mention it: the Privacy tab shows "Privacy (!)" and
  the mark says who and when. Other factions never tell you. Marks are
  forgotten when your character dies. Admins can tick a box to see private things anyway.
- **Gone is gone.** Walk past a container, corpse, bag or floor spot you remember and it is no longer there (smashed,
  burnt, moved, picked up): it is forgotten.

## Opening the search

- The **magnifier button** on the left sidebar, right under Inventory, opens and closes the search window.
- **Find an item you have seen** (Options > Key Bindings > Last Seen Where) does the same from the keyboard. Not bound by
  default.

## Settings

Per player, in Settings > Mods:

- **Search**: What I have seen (default), Shared with my faction and safehouse, or Opened by anyone. Also in the
  search window.
- **Arrow colour**: colour and opacity of the arrows; the highlight uses the colour.

Sandbox (server):

- **Search rule**: each player's choice (default), or one rule for everyone.
- **Items on the floor**: in sight (default), within reach, or off.
- **Small item distance**: how close items lighter than 0.2 must be to be noticed on the floor. Default 4 tiles.
- **Forget after (days)**: forget places not seen again for this many in-game days. Default 0, never.
- **Privacy**: lets players mark containers and items private. On by default.
- **Keep memories fresh**: with Forget after (days) set, a container's clock restarts when it is opened (default), or
  also when you stand next to it.
- **Found by shows**: usernames (default) or character names.

Build 42 only. Must be installed on the server and on every client.
