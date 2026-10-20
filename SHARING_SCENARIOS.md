# Who sees whose sightings: every setup

Implemented 2026-10-20: **Should** is what the mod does now; **Now** is how it worked before.

The model: **finding is word of mouth.** A sighting reaches you only from someone who would tell you where they found
it. Whoever tells you, you know who told you. So:

- Your faction is your only group. Safehouses play no part in this mod: sharing a safehouse tells you nothing.
- While the server has factions, only faction members share, and only with their own faction. A player in no faction
  shares with nobody, as in single player: they search their own memory only.
- On a server without factions there are no groups. Without PVP everyone is on the same side, so everyone tells
  everyone. With PVP everyone is a possible rival, so nobody tells anybody.
- What reaches you is always named. "Someone" would mean being told by nobody, which cannot happen.
- A privacy mark means "I do not tell": it never hides what other people saw themselves.

Rows marked **⚠** are where **Should** differs from what the code does now. Each row is one searcher looking at a
place one other player (the finder) saw.

Terms:

- **Searcher**: the player using the search window. **Finder**: the player whose sighting is being looked at.
- **Faction mate**: in the same faction as the searcher (owner or member). Only exists while the server has factions.
- **Stranger**: anyone else, safehouse mates included.
- **Rule**: the searcher's search rule (their own choice, or forced by the sandbox Search rule).
- Server options: vanilla `PVP` and `Faction` (server settings, not sandbox).

## A. Does the finder's sighting reach the searcher?

"Latest" = under Opened by anyone the searcher gets the newest snapshot of each place, whoever took it (you hear the
most recent news, not every old account of it).

| # | Server | Finder | Rule | Now | Should |
|---|---|---|---|---|---|
| A1 | any | the searcher | any rule | yes, always (own marks never hide own sightings) | yes: you remember what you saw |
| A2 | factions on | faction mate | What I have seen | no | no: the searcher asked for their own memory only |
| A3 | factions on | faction mate | Shared | yes, unless the finder marked it "only me" | yes: your faction tells you |
| A4 | any | safehouse mate, not a faction mate | Shared | yes, unless marked "only me" | **⚠ no**: a safehouse is not a group |
| A5 | any | stranger | What I have seen | no | no |
| A6 | any | stranger | Shared | no | no |
| A7 | PVP off, factions off | stranger | Opened by anyone | yes if latest, unless marked | yes: everyone is on the same side |
| A8 | PVP on, factions off | stranger | Opened by anyone | yes if latest, unless marked | **⚠ no**: everyone is a possible rival |
| A9 | factions on (PVP on or off) | stranger, in no faction | Opened by anyone | yes if latest, unless marked | **⚠ no**: a player in no faction tells nobody |
| A10 | factions on (PVP on or off) | stranger, in another faction | Opened by anyone | yes if latest, unless marked | **⚠ no**: a faction keeps its finds to itself |
| A11 | factions on | anyone, searcher in no faction | Shared | own + safehouse mates | **⚠ own sightings only**: no faction, no one to tell you |

Under Opened by anyone a faction mate's sighting still reaches you (as in A3), like it does now when theirs is the
latest; under these rules that rule is not offered while there are factions (D2), so Shared is how you get it.

## B. How is the finder shown (Found by column)?

Only for sightings that reach the searcher (section A).

| # | Server | Finder | Now | Should |
|---|---|---|---|---|
| B1 | any | the searcher | "You" ("You (private)" when marked) | same |
| B2 | factions on | faction mate | name (username or character name, the searcher's choice) | same |
| B3 | PVP off, factions off | stranger | name | name: you know who told you |
| B4 | PVP on, factions off | stranger | name | **⚠ never happens** (A8) |
| B5 | factions on | stranger | name, or "Someone" with PVP on | **⚠ never happens** (A9, A10) |
| B6 | any | unknown (old data without a finder) | "-" | same |

"Someone" is gone for good: whatever reaches you is named. A stranger's sighting reaches you only when the server
has both PVP and factions off.

## C. Search rule on offer

| # | Server | Now | Should |
|---|---|---|---|
| C1 | PVP off, factions off | What I have seen, Shared, Opened by anyone | **⚠ What I have seen, Opened by anyone**: no factions, so Shared would find only your own sightings |
| C2 | factions on (PVP on or off) | What I have seen, Shared, Opened by anyone | **⚠ What I have seen, Shared** ("Shared with my faction"): Opened by anyone would add only old places with no known finder |
| C3 | PVP on, factions off | What I have seen, Shared, Opened by anyone | **⚠ What I have seen only**: nobody shares; the rule picker is shown disabled |
| C4 | single player | What I have seen, Opened by anyone | same: split-screen players share (E1) |
| C5 | a sandbox or saved rule that is not on offer | used as is | **⚠ the nearest one on offer**: Opened by anyone → Shared with factions, else What I have seen; Shared without factions → What I have seen |

## D. Privacy marks

A mark only hides what the marker saw; anyone else's sighting of the same thing is shared as usual. The marks follow
the group above (faction only).

| # | Server | Now | Should |
|---|---|---|---|
| D1 | factions on | "Only me" hides what you saw from your faction and safehouse | **⚠ hides it from your faction** (the only people who would get it) |
| D2 | PVP off, factions off | "Only me" hides what you saw from everyone | same: everyone else would get it otherwise |
| D3 | PVP on, factions off | "Only me" offered | **⚠ not offered**: nobody gets your sightings anyway |
| D4 | any | "My group" offered (faction and safehouse) | **⚠ not offered**: with factions it would hide nothing (only your faction gets your sightings anyway); without factions there is no group, so it would equal "Only me" |
| D5 | any, existing "My group" marks | hide from strangers | **⚠ kept and shown as "Private: my faction"**: they keep doing the same, which now changes nothing with factions and acts as "Only me" without |
| D6 | factions on | "a friend found it" notice from faction and safehouse mates | **⚠ from faction mates only** |
| D7 | factions off | same notice from safehouse mates | **⚠ no notice**: no one who would tell you |
| D8 | any, admin with "Private shown" | sees every marked sighting | same: an admin tool |

## E. Single player

| # | Setup | Now | Should |
|---|---|---|---|
| E1 | split screen, several local players | each other's sightings reach under Opened by anyone, named | same: players on one couch talk |
| E2 | one player | only own sightings exist | same |

## Not covered (say if they should matter)

- The safety system (players opting in or out of PVP one by one) and non-PVP zones: only the server-wide `PVP`
  switch counts. A player with PVP turned off on a PVP server is still treated as a possible rival.
- The server option changing mid-game: a search uses the value at the moment it runs.
