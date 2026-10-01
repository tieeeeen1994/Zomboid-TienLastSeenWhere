# Tien's Last Seen Where

Forgot where you saw that saw? Type an item's name and see every container and floor where your character saw it,
then follow an arrow on the floor back to it.

- **Only what you have seen.** A container counts once you have looked inside it in the loot window. Containers you never
  opened are never searched. Items lying on the floor count once they are in sight (small ones only up close, and in the
  dark only within reach), or when search mode spots them.
- **Search as you type.** Results are grouped by item, then by place: a small arrow pointing the way on screen, the
  place (counter, fridge, car trunk, corpse, floor, with the room), how far, which floor and how long ago you saw it.
- **Where to look.** Everywhere, This building, Nearby, or On me (your own bags).
- **Show** puts an arrow on the floor at your feet, aimed at the place, and marks the square. On another floor it points
  to the stairs first and shows how many floors up or down. **Go there** walks you to it and opens the loot window on
  it. **Take** picks the item up once it is within reach.
- **Memory follows the character.** It is kept on the server and forgotten when the character dies.

## Keys

- **Find an item you have seen** (Options > Key Bindings > Last Seen Where): opens the search window. Default
  `Ctrl + F`.

## Settings

Per player, in Settings > Mods:

- **Search**: What I have seen (default), Shared with my faction and safehouse, Opened by anyone, or Everything
  (all of that plus every container and floor around you right now).
- **Arrow colour**: colour and opacity of the arrows and the marker.

Sandbox (server):

- **Search rule**: each player's choice (default), or one rule for everyone.
- **Items on the floor**: in sight (default), within reach, or off.
- **Small item distance**: how close items lighter than 0.2 must be to be noticed on the floor. Default 4 tiles.
- **Forget after (days)**: forget places not seen again for this many in-game days. Default 0, never.

Build 42 only. Must be installed on the server and on every client.
