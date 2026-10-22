# Wild Gambit — custom art assets

The working list for the custom art (generated with Gemini, converted to .tga by Claude).
Art = generated images. Code = the 3D creature model, all text (name, level, quality, type),
spike arrows' placement, owner colours, glows and animation.

Tier and quality are the same six steps (Sighted/Poor … 200 kills/Legendary): one frame per tier.

## Cards

| # | Asset | Count | Notes |
|---|---|---|---|
| 1 | Card frame by tier | 6 | Poor worn wood/iron · Common plain silver · Uncommon green-gilded · Rare sapphire silver · Epic amethyst gold · Legendary gold with dragon. More ornate each tier. Art window and text panel hollow. |
| 2 | Art-window scene by creature type | 10 | Beast, Critter, Demon, Dragonkin, Elemental, Giant, Humanoid, Mechanical, Undead, generic. Background scenery only, no creatures. |
| 3 | Scene variants | +3 per type | Optional; each creature always gets the same variant. |
| 4 | Type emblem (text panel watermark) | 10 | Single-colour, tintable. |
| 5 | Text panel | 1 | Aged parchment or slate plaque. |
| 6 | Name ribbon | 1 | Curved banner; plain enough for the elite/rare dragons. |
| 7 | Quality gem (under the ribbon) | 6 | Grey, white, green, blue, purple, orange. |
| 8 | Level crystal frame (top left) | 1 | Number drawn in code. |
| 9 | Tier badge socket (bottom left) | 1 | Tier icon goes inside. |
| 10 | Spike-total badge (bottom right) | 1 | Red drop or shield. |
| 11 | Owner tab (top edge) | 1 | Neutral grey, tinted to the owner's class colour. |
| 12 | Spike / thorn | 1 | Rotated per side. |
| 13 | Card back | 2 | Almanac-themed and wild/vine-themed. |

## Table and board

| # | Asset | Count | Notes |
|---|---|---|---|
| 14 | Board playmat | 3 | Forest glade, stone ruin, tavern table (picked in settings). |
| 15 | Board slot | 1 | Card-shaped inset/outline. |
| 16 | Board border | 1 | Nine-slice: carved roots and wood. |
| 17 | Window background ("deck" area) | 3 | Dark leather, tavern wood, mossy stone. |
| 18 | Hand rails | 1 | Tray or shelf for the hands. |
| 19 | Player portrait frame | 1 | Ornate ring with class-emblem corner slot. |
| 20 | Ability button frame | 1 | Square, ornate. |

## Results and effects

| # | Asset | Count | Notes |
|---|---|---|---|
| 21 | Result banners | 3 | Victory, Defeat, Draw — no text. |
| 22 | Soft radial glow | 1 | White, tintable. |
| 23 | Sparkle and ember particles | 2 | White. |
| 24 | Trap, shield bubble, sheep marks | 3 | Ability overlays. |

About 65 images in all (35 without scene variants). Minimum set: 1, 2, 5, 6, 7, 8, 9, 10, 13, 14, 17.

## Prompt rules (every Gemini prompt)

1. No text, letters, numbers or logos.
2. Pieces needing transparency on flat pure magenta (#FF00FF); scenes and backgrounds fill the frame.
3. Straight on, centred, no tilt or perspective, nothing cut off.
4. Ask for 1024×1024; Claude resizes to powers of two and converts to .tga.
5. Card frames: portrait about 3:4, centred; art window and text panel solid magenta.
6. Tintable pieces (4, 11, 22, 23): greyscale only.
7. Style line first: *Hand-painted fantasy trading card game art, World of Warcraft style, rich
   painterly textures, warm lighting, ornate but readable, original design (not from any existing game).*
8. No real logos and no Blizzard/Hearthstone art.

## Geometry the art must fit (code values)

- Card 92×124 (ratio 0.74, portrait). Board slots the same shape.
- Board: 3×3 slots, 30 px gutters, 30 px margin; the painted board is sized so its inner stone sits 36 px outside the slots.
  Whole board 420×516 (portrait, about 0.81).
- New files need a full game restart (not /reload) the first time.

## Files

`AzerothAlmanac\Media\` — e.g. `Frame_3_Uncommon.tga`, `Scene_Beast_1.tga`, `Board_Glade.tga`.

## Progress

- [x] 14 Board playmat — Glade (Media\Board_Glade.tga, 0.31.1). Stone ruin and tavern table still to come.
- [x] 1 Tier frames, all six with the parchment edge (Media\Frame_1_Poor … Frame_6_Legendary.tga, 0.32.0). Layouts measured per frame by tools/art_convert.py.
- [x] 2 Creature-type scenes, all ten (Media\Scene_<Type>_1.tga, 512x256, 0.33.0). Variants: add Scene_<Type>_2 … and raise the count in SCENE_ART.
- [x] 17 Window backgrounds: Tavern (default), Leather, Stone (Media\Window_*.tga, 0.33.2); picked in Settings > Wild Gambit > Table.
- [x] 13 Card backs: Almanac (red compass, default from 0.40.2) and Wild (Media\CardBack_*.tga, 0.34.0); cards are dealt face down and turned over. Settings > Wild Gambit > Card back.
- [x] 8/9/10/15 Badges (level shield, tier socket, spike seal) and board slot (Media\Badge_*.tga, Slot_Board.tga, 0.34.2). Slot came landscape; turned upright.
- [x] 6 Name banner (Media\Banner_Name.tga, 0.34.3) and spike badge redo with long thorns.
- [x] 21/24 Result banners (Victory, Defeat, Draw) and ability marks (Trap, Shield, Sheep) (Media\Result_*.tga, Mark_*.tga, 0.35.0). 22/23 glow and sparkles stay game art (code).
- [x] 20/18 Ability frame, hand trays, pick-screen background (Media\Frame_Ability.tga, Tray_Hand.tga, Background_Pick.tga, 0.35.2). [x] 19 Portrait frame (Media\Frame_Portrait.tga, 0.35.3).
- [x] 12 Spike thorn (Media\Spike_Thorn.tga, 0.36.3); card name moved into the panel, banner/quality/type text dropped (0.36.2).
- [x] 11 Owner tab (Media\Tab_Owner.tga, greyscale, tinted per owner) and wooden button skin (Media\Button_Wood.tga) (0.37.0). 4 Type emblems dropped (the name fills the panel).
- [x] VS plaque and class rings (Media\Plaque_VS.tga, Ring_Class.tga, 0.37.1). [x] Board Ruin (Media\Board_Ruin.tga, 0.37.2; Settings > Board). [x] Board Tavern (Media\Board_Tavern.tga, 0.37.3).
- [x] Logo and turn banner (Media\Logo_WildGambit.tga, Banner_Turn.tga, 0.37.8).
- [?] Icon (docs/art_source/Icon_WildGambit.png, Gemini on magenta, 2026-10-08): three glowing cards, a gold coin, purple-flowered vines. Media\Icon_WildGambit.tga, 256 x 256: magenta keyed, the magenta-stained halo replaced by a fresh glow coloured from each card's edge, squared and centred. Replaces the 64 px logo crop.
- [?] Dungeon names as word art (#31, 2026-10-08): Media\DungeonNames_1.tga (1024 x 1024, 31 names), made by tools/wordart.py from the LifeCraft font (not shipped; Licenses\LifeCraft.txt): gold, bevelled, dark bronze outline and shadow; raids red-gold; names over 14 letters on two lines. Coordinates in Data\DungeonNames.lua. Used on the Dungeons page's cards and header and Wild Gambit's event card.
- [?] Card parchment border (#33, 2026-10-08): Media\Card_Parchment.tga (256 x 512), cut from docs/art_source/Frame_2_Common.png with `art_convert.py parchment` (the creature card's painted parchment edge, the inside clear, the gem's gap filled from beside it). Round the Dungeons page's cards and Wild Gambit's event card. 0.69.1: the outer edge worn (noise-nibbled with a few deeper tears, darkened toward the edge) and Media\Card_Shadow.tga made with it (`parchment ... shadow=Card_Shadow.tga`: the worn shape filled and blurred, 8% bigger each way). 0.69.1 also: water stains and scorch marks. Media\Card_Ruin.tga (256 x 512, `art_convert.py ruin Media/Frame_Dungeon.tga`): cracks, dirt, soot and moss on the stone only, cobwebs in the doorway's upper corners; drawn over the arch. The word art distressed (`wordart.py` DISTRESS: tarnish, grime and drips, chips, scratches; seeded by name).
- [?] Dungeon name plate (#32, docs/art_source/Plate_DungeonName.png, Gemini on magenta, 2026-10-08): Media\Plate_DungeonName.tga, 512 x 256 (`art_convert.py cut ... 512 256 fill`). Over the plaque 3 px out each way; the word art inside 84% x 70% of it (W.PLATE_INNER).
- [?] Painted icons (#43, Gemini, 2026-10-08), 256 x 256 (`art_convert.py full`): Tab_Recipes (recipe book; Recipes tab, minimap menu, spell / recipe entries), Icon_Training (lectern; trainers), Icon_Merchant (market stall; merchants), Icon_Fishing (rod, bobber, creel; fishing). Sources in docs/art_source.
- [?] Icon_Level (docs/art_source/Icon_Level.png, Gemini, 2026-10-08; the first render had words painted on it and was redone): a hero in silhouette on a rocky rise, a beam of gold light flashing up from them. Media\Icon_Level.tga, 256 x 256; level-up toasts and entries. Icon_Flight: replaced by the game's own gryphon (read off the action bar's end cap); painted mounts per faction (gryphon, wind rider, hippogryph, bat) kept as a later option (prompts in this session's notes).
- [?] Icon_Flight_Gryphon (docs/art_source/Icon_Flight_Gryphon.png, Gemini, 2026-10-08): a chunky war gryphon in a blue-and-gold harness on a stone perch, sunset. Media\Icon_Flight_Gryphon.tga, 256 x 256; flight paths for Alliance characters (W.KIND.flight.artByFaction).
- [?] Icon_Flight_WindRider (docs/art_source/Icon_Flight_WindRider.png, Gemini, 2026-10-08): a snarling wind rider with ragged bat wings and a scorpion tail on a totem perch, desert sunset. The render came with a white rounded card border: cropped off (18 px inside it) before `art_convert.py full`. Media\Icon_Flight_WindRider.tga, 256 x 256; flight paths for Horde characters.
- [x] Scene variants: Beast, Humanoid, Undead, Critter _2 (0.37.9).

## Hero and companion cards (0.41.0)

| Asset | Count | Notes |
|---|---|---|
| Hero_Crest | 1 | Shield crest with wings and laurel over the card's top edge; greyscale, tinted the class colour. |
| Scene_Hero_<Capital> | 6 | Stormwind, Ironforge (dwarves, gnomes), Darnassus, Orgrimmar (orcs, trolls), ThunderBluff, Undercity. Scenery only, 2:1. |
| Crest_<CLASS> | 9 | Round class medallions, full colour; shown when the opponent's hero can't be drawn as a model. |
| Badge_Pet | 1 | Paw badge on companion cards; greyscale, tinted. |

Switched on in QoL/WildGambit.lua `HERO_ART`. [x] All 17 delivered (0.41.1): crest 256x128 greyscale, scenes 512x256 (painted 1024x506), crests 256x256, paw 128x128 greyscale.
| Scene_Hero_ZephrasIsle | 1 | The Skyborne's home (WoW Forever race, both factions start on Zephras Isle). [x] Delivered (0.41.3). |

## Spell cards and effects (0.43.0)

[x] All delivered: Frame_Spell (256x512), Gem_Spell (greyscale, tinted), Spell_<Banish|Polymorph|Execute|DivineShield|Barkskin|Reincarnation|MindControl|PickPocket|FreezingTrap> (512x512 from 4:3), FX_<Banish|Execute|Polymorph|DivineShield|MindControl|Frost|Reincarnation> (glow on black, added as light), FX_PickPocket (keyed), Mark_Barkskin, Mark_Ankh.

- [x] Habitat scenes: Scene_Habitat_Underwater, Shore, Desert, Snow, Swamp, Cave (512x256 from 1024x506, 0.44.0).
- [x] Frozen card: FX_FrozenCard (256x512, glow on black), Mark_IceShackles (512x256, keyed) (0.45.0).
- [x] Mark_Trap redone as a frost-rimed freezing trap (0.45.2).
- [x] Badge_Favorite re-keyed (0.45.3): the magenta glow in the filigree gaps removed (kept only the gold frame and the gem, the frame's largest hole).
- [?] Journal-entry badge (docs/art_source/Badge_Journal.png, 2026-10-07): open crimson journal with molten-gold writing. Media/Badge_Journal.tga (128 x 128, magenta keyed, sparks kept; 0.68.9): the Journal page's icon, the toasts' seal, the seal on Journal entries (issue 24).
- [?] Almanac logo (docs/art_source/Logo_Almanac.png, 2026-10-07): closed crimson journal with a gold compass rose. Media/Logo_Almanac.tga (128 x 128, magenta keyed; 0.68.9): ns.ICON and the .toc IconTexture, replacing 133742 everywhere (issue 25).

## Dungeon cards (designed 2026-10-07, DESIGN section 72)

Scenery for 27 dungeons and raids comes from the game's journal art (UI-EJ-BACKGROUND-*); custom pieces (sources in docs/art_source/):
- [x] Frame_Dungeon (256x512 from 3:4, delivered 2026-10-07): carved stone archway with torches. Keyed holes in the 256x512 texture: arched art window x 55-201, y 85-322; text plaque x 55-201, y 357-447 (the art converter's printed layout doesn't apply: both holes are see-through).
- [x] FX_TorchGlow (64x64, made by Claude 2026-10-07): soft orange radial glow for the frame's flickering torches.
- [x] FX_DungeonPortal (512x512, glow on black, added as light; delivered 2026-10-07): violet and gold swirl.
- [x] Scene_Dungeon_HallOfThanes (512x512 from 1024x765, stretched; show at 4:3; delivered 2026-10-07): dwarf-king statues, molten channels.
- [x] Scene_Dungeon_RuinsOfLordaeron (512x512 from 1024x765, stretched; show at 4:3; delivered 2026-10-07): ruined capital under a green sky.
- [x] Event effects (delivered 2026-10-08, sources in docs/art_source/): FX_AntiMagicDome, FX_Bubbles, FX_Explosion, FX_FireWall, FX_Meteor (512x512, glow on black; the meteor is drawn turned round to fall down-left), FX_FireBreath, FX_FrostBreath (512x256, glow), Tile_Ice (256x256), FX_Smoke (512x512, keyed by its magenta tint), Mark_Stone (256x512, keyed), FX_Dust (512x256, keyed on its darker magenta).
- [?] Murloc Tac Toe icon (docs/art_source/MurlocTacToe_Icon.png, Gemini on magenta, 2026-10-08): a grinning murloc with Xs and Os, bubbles and fireflies. Media\MurlocTacToe_Icon.tga, 256 x 256: magenta keyed; the bubbles' see-through magenta unmixed; the fireflies' glow repainted yellow and faded with distance. Replaces the earlier murloc badge and every Murloc Tac Toe icon (window corner, minimap menu, Settings, flight prompt).

## Gathering profession cards (DESIGN 88, prompts 2026-10-09)

Six 4 : 1 banner cards on the Gathering page, in the same family as Asia's zone banners (DESIGN 84): the card draws the name, count and fold box over the left third, so that part stays calm and dark; the subject sits in the right half. Converted with `art_convert.py banner` (crops to 4 : 1) to `Media\Gather_<Name>.tga`, 512 x 128. Until a file exists the card keeps its plain tinted look; each picture should lean towards that card's tint.

Shared paragraph (first, in every prompt): *Hand-painted fantasy art, World of Warcraft style, rich painterly textures, warm lighting, original design (not from any existing game). A very wide panoramic banner, about four times wider than tall, filling the whole frame edge to edge. The left third is calm, darker and low in detail, fading into shadow; the subject and all the busy detail sit in the right half. Straight-on view. No people, no text, no letters, no numbers, no logos, no frame or border, no UI.*

- [?] Gather_Herbalism (green; delivered 2026-10-09, docs/art_source/Gather_Herbalism.png 1024 x 254 -> Media 512 x 128, on the card): a sun-dappled forest clearing; in the right half, clumps of white daisy-like flowers, silvery leafy herbs and purple-blossomed plants among ferns, a wicker gathering basket and a small curved herb sickle on a mossy stump, morning mist and shafts of golden light; the left fades into deep green shade under the trees.
- [?] Gather_Mining (copper brown; delivered 2026-10-09, docs/art_source/Gather_Mining.png 1024 x 254 -> Media 512 x 128, on the card): a rocky hillside mine mouth with timber supports; in the right half, a rich vein of copper and grey tin ore glinting in the rock face, a pickaxe leaning against it, a wooden mine cart heaped with ore, warm lantern light against cool cave dark; the left fades into dark stone.
- [?] Gather_Treasure (gold; delivered 2026-10-10, docs/art_source/Gather_Treasure.png 1024 x 254 -> Media 512 x 128, on the card): forest-floor ruins at dusk; in the right half, an iron-banded wooden chest with its lid ajar, gold coins and a single gem spilling out, a battered footlocker and a small locked strongbox beside it, candle and lantern glow; the left fades into dark mossy stonework.
- [?] Gather_Fishing (blue; delivered 2026-10-10, docs/art_source/Gather_Fishing.png 1024 x 254 -> Media 512 x 128, on the card): a quiet lakeshore at twilight; in the right half, a weathered wooden dock with a fishing pole and a red-and-white bobber making ripples, a wicker creel of fish, a shimmering school of fish just under the clear water, fireflies; the left fades into misty dark water.
- [?] Gather_Skinning (leather brown; delivered 2026-10-10, docs/art_source/Gather_Skinning.png 1024 x 254 -> Media 512 x 128, on the card): a hunter's camp at the edge of a dark pine forest; in the right half, hides and furs stretched on a wooden drying rack, a wolf pelt over a log with a skinning knife stuck in it, a campfire's orange glow; the left fades into shadowed forest.
- [?] Gather_TooHigh (red; delivered 2026-10-10, docs/art_source/Gather_TooHigh.png 1024 x 254 -> Media 512 x 128, on the card): a forbidding mountain cliff high above; in the right half, out of reach on a far ledge, a glowing rare flower and a gleaming silver-white ore vein behind a red-orange haze, a frayed rope dangling short of them; the left is dark rock in the foreground under an ominous red sky.

## Crafting profession cards (prompts 2026-10-09)

Same family and rules as the Gathering cards above (the shared paragraph first, 4 : 1, left third dark and calm, subject in the right half), for the crafting professions on the Recipes page. Files `Media\Recipe_<Name>.tga`, 512 x 128. (Since 2026-10-10 the Recipes page's profession cards are full-width banner cards like Gathering's.)

- [?] Recipe_Alchemy (violet and green; delivered 2026-10-10, docs/art_source/Recipe_Alchemy.png 1024 x 254 -> Media 512 x 128, on the card): an alchemist's workbench by candlelight; in the right half, bubbling glass flasks and alembics in green, red and blue, a brass still with a curl of coloured vapour, dried herbs hanging from a beam, a mortar and pestle; the left fades into dark shelves of jars.
- [?] Recipe_Blacksmithing (orange-red; delivered 2026-10-10, docs/art_source/Recipe_Blacksmithing.png 1024 x 254 -> Media 512 x 128, on the card): a forge at night; in the right half, a glowing anvil with a red-hot blade, a hammer mid-rest, sparks, a roaring forge mouth, tongs and a quenching barrel, racks of swords and a breastplate; the left fades into soot-dark stone.
- [?] Recipe_Enchanting (purple and blue; delivered 2026-10-10, docs/art_source/Recipe_Enchanting.png 1024 x 254 -> Media 512 x 128, on the card): a quiet arcane study; in the right half, a runed copper rod over a softly glowing enchanting circle, floating motes and swirling violet dust, shimmering shards and a crystal on a velvet cloth, an open tome of sigils; the left fades into deep indigo shadow.
- [?] Recipe_Engineering (bronze and steel; delivered 2026-10-10, docs/art_source/Recipe_Engineering.png 1024 x 254 -> Media 512 x 128, on the card): a cluttered gnomish workshop; in the right half, a half-built mechanical contraption with gears and pipes, a wrench and blasting powder kegs, a small mechanical squirrel, sparks from a soldering iron, blueprints pinned to a board; the left fades into dark machinery.
- [?] Recipe_Leatherworking (warm tan; delivered 2026-10-10, docs/art_source/Recipe_Leatherworking.png 1024 x 254 -> Media 512 x 128, on the card): a tanner's workroom; in the right half, a leather jerkin and boots on a workbench, rolls of cured leather, awls, needles and thread, a stretched hide on a frame, a lantern; the left fades into shadowed timber.
- [?] Recipe_Tailoring (soft blue and cream; delivered 2026-10-10, docs/art_source/Recipe_Tailoring.png 1024 x 254 -> Media 512 x 128, on the card): a tailor's loft; in the right half, bolts of linen, wool and silk in rich colours, a spinning wheel, a half-sewn embroidered robe on a mannequin, scissors, spools of thread; the left fades into dusky drapery.
- [?] Recipe_Cooking (warm amber; delivered 2026-10-10, docs/art_source/Recipe_Cooking.png 1024 x 254 -> Media 512 x 128, on the card): a tavern kitchen; in the right half, a cast-iron pot over a crackling hearth, a roast on a spit, fresh bread, sausages, spices and a wooden spoon on a chopping board, steam rising; the left fades into smoky dark beams.
- [?] Recipe_FirstAid (clean white and red; delivered 2026-10-10, docs/art_source/Recipe_FirstAid.png 1024 x 254 -> Media 512 x 128, on the card): a field medic's table in a canvas tent; in the right half, rolled linen and wool bandages, a small kit of salves and vials, a leather satchel stitched with a simple white leaf emblem, a lantern's warm glow; the left fades into dark canvas.

## People cards: painted icons (0.70.1, 2026-10-14)

The People tab's small cards each wear an icon that fades into the name (the Journal's and Creatures' look). Done: the nine class crests
(`Crest_<CLASS>`), Fishing (`Icon_Fishing`), Other trainers (`Icon_Training`), General goods (`Icon_Merchant`), Flight masters and
Flight paths (`Icon_Flight_Gryphon` / `Icon_Flight_WindRider`, by faction), Quest givers (`Tab_Quests`), Show all (`Tab_People`).
The rest wear the game's own spell and item icons until a painting arrives. Each is a **square painted scene, 256 x 256** (like
`Icon_Merchant`: one clear subject in a lit scene, dark edges, no text), on flat magenta; convert with `art_convert.py cut ... 256 256 fill`;
save as `Media/Icon_People_<key>.tga` and add the key to `PAINTED` in `UI/Pages/Townsfolk.lua`.

| Key | Card | Subject |
|---|---|---|
| alchemy | Alchemy | bubbling flasks, an alembic and herbs on a workbench |
| blacksmithing | Blacksmithing | an anvil, a hammer and a glowing forged blade |
| enchanting | Enchanting | a floating glowing rune over a wand and shimmering dusts |
| engineering | Engineering | brass gears, goggles and a small gnomish gadget |
| herbalism | Herbalism | a basket of herbs and flowers with a sickle |
| leatherworking | Leatherworking | stitched leather, an awl and a skinning knife |
| mining | Mining | a pickaxe, chunks of ore and a lantern in a mine |
| skinning | Skinning | a skinning knife and a pelt stretched on a rack |
| tailoring | Tailoring | a needle, bolts of cloth and spools of thread |
| cooking | Cooking | an iron pot over a fire, a ladle and ingredients |
| firstaid | First Aid | rolled linen bandages and a vial of salve on a wooden box |
| weapon | Weapon masters | a rack of swords, axes and maces |
| riding | Riding trainers | a saddle, reins and a mount in a stable yard |
| portal | Portal trainers | a swirling arcane portal arch in a mage tower |
| pet | Pet trainers | a young wolf, a hawk on a gauntlet and treats |
| inn | Innkeepers | a warm-lit tavern door, a mug, a key and a bed |
| bank | Bankers | an open vault door with gold bars and a strongbox |
| auction | Auctioneers | a gavel, a pile of coins and a ledger |
| stable | Stable masters | a stall with a saddled mount and hay |
| guild | Guild masters | a guild tabard on a banner stand, a charter and a quill |
| battle | Battlemasters | crossed blue and red banners with a war horn |
| spirit | Spirit healers | a pale winged spirit over a graveyard in soft light |
| repair | Repair | a mending hammer, a whetstone and a dented shield |
| vendor_food | Food & drink | bread, cheese, apples and a flagon on a table |
| vendor_reagents | Reagents | pouches of powders, vials of glowing dust and feathers |
| vendor_trade | Trade supplies | a crate of ingots, cloth and leather |
| vendor_ammo | Ammunition | a quiver of arrows and a pouch of shot |
| vendor_poisons | Poisons | green vials, a skull-marked bottle and a dagger |
| vendor_other | Other vendors | a market stall with assorted wares |
| mailbox | Mailboxes | a post box with letters |

## Murloc Tac Toe, the Feast of Winter Veil (prompts 2026-10-21, Shannon)

Three pieces, the same three Hallow's End has: the board, the divider between the two players'
panels, and the pile that stands beside the table. The code is in already (`SEASON_LOOK.WinterVeil`
in `QoL/MurlocTacToe.lua`), so these drop straight in under these names and nothing else changes.

**Done, 2026-10-21.** All three painted and in (`docs/art_source/MurlocTacToe_*_WinterVeil.png`,
Gemini on magenta). `tools/build_winterveil_art.py` is the converter now - it used to derive the
placeholders. The board took two goes (the first was handsome and austere); the divider and pile
came right first time, off the prompts the board's second render taught us to write.

One flaw kept on purpose: the board render has holly and fir running off the left and right edges
(186 px and 143 px of paint on the border), so those sprigs show a flat cut edge. The prompt now
ends with a margin instruction, so a re-roll fixes it; it is not worth holding the feature for.

The style line is rule 7's, word for word, even though this is a winter scene: the lighting is
steered in the body of the prompt instead, so the house style stays one line everywhere.

**Two things the board's renders taught us, which all three prompts now carry.**

1. **Ask for a margin.** The warm second board came back with its holly and fir running off the
   left and right edges - 186 px and 143 px of paint touching the border - where the first, plainer
   one had a clean margin all round. `art_convert.py board` keeps the canvas whole and only keys
   the magenta, so nothing re-crops it: a sprig cut off at the edge ships cut off. The existing
   boards all leave a margin (the mossy one is painted inside x 18-993 of 1024).
2. **These are small on screen, so ask for few, large shapes.** The board is drawn at 461 px (45%
   of its texture) and carries fine detail well. The divider is drawn at **206 x 38 px** and the
   pile at **100 x 49 px** - both about 40% - so a candy cane 20 px wide in the texture lands at
   8 px in game. Anything intricate turns to mush at that size; both prompts now ask for a handful
   of big, bold, well-separated shapes rather than a crowded garland.

### 1. Board — `Media\MurlocTacToe_Board_WinterVeil.tga` (1024 x 1024)

Convert: `python tools/build_winterveil_art.py` (all three at once); the board goes through
`art_convert.board` with the playfield measured off this render, `170,170,852,852`, not the
default - that is what darkens the nine ice panes and leaves the frame bright, so a creature
standing on one still reads.

**Second go (Shannon: "although it's nice I'd like to add some more whimsy ... whimsy and warmth").**
The first render was handsome and far too austere - a grey stone slab in blue daylight. Three things
did it: nothing in the scene gave off light, so every highlight came out blue; the knotwork rendered
as bare stone when the pond board's own is warm gold; and "dead vines and bare twigs" is a bleak
instruction. So the lantern below is the real fix (it puts warm light on the snow and something for
the cold to contrast against), the knotwork is asked for in gold, and the twigs become living
evergreen. The nine-panes paragraph is **unchanged on purpose** - it worked first time, and it is the
one thing that ruins the board if it drifts.

> Hand-painted fantasy trading card game art, World of Warcraft style, rich painterly textures,
> warm lighting, ornate but readable, original design (not from any existing game).
>
> A square game board for noughts and crosses, seen straight from above, flat on, no tilt and no
> perspective, centred, the whole board inside the frame and nothing cut off. The background
> outside the board is flat pure magenta (#FF00FF).
>
> The board is a frozen woodland pond on a cheerful midwinter evening, decked out for a feast. A
> heavy stone and timber frame runs round the outside, its carved knotwork gilded in warm gold and
> honey-coloured wood, with soft plump snow heaped on every surface that faces upwards - the top of
> the frame, the corner studs, the carved ridges. The snow is rounded and inviting rather than
> sharp.
>
> The frame is trimmed for the holiday: a swag of fresh evergreen fir, bright with red berries and
> glossy holly, loops across the top and down one side, tied with red ribbon; small gold jingle
> bells and a couple of striped candy canes are tucked into it; a little round wreath hangs at one
> corner. A small iron lantern sits on the lower left corner post with a candle burning warmly
> inside it, and a stubby candle or two stand beside it, their flames throwing a pool of golden
> light across the snow and warm glints along the gold knotwork. A tiny snow-capped toadstool or
> two still peep out at the edges. A few short icicles hang from the lower edge, catching the
> candlelight.
>
> Inside the frame is a three by three grid of nine square panes of dark blue-green ice, sunk below
> the frame like windows onto the frozen water beneath. The grid fills the middle two thirds of the
> picture, evenly spaced, separated by narrow snow-dusted stone ribs. **The nine panes must be
> dark, plain and almost empty** - faint cracks and frozen bubbles at most. Nothing may sit inside
> them: no snowflakes, no ornaments, no creatures, no bright highlights. All the detail and interest
> belongs on the frame around them.
>
> Leave a clear margin of empty magenta all the way round the board, about one twentieth of the
> picture's width: no part of the frame, the garland, the holly or any decoration may touch or run
> off the edge of the picture.
>
> Warm candlelight from the lower left spilling across the snow and the gold, with cool blue
> twilight only in the shadows and the far corners - the picture should feel snug and festive, not
> bleak. Cosy storybook Christmas mood. No text, no letters, no numbers, no logos, no people, no
> creatures, no user interface.

### 2. Divider — `Media\MurlocTacToe_Divider_WinterVeil.tga` (512 x 128, the top 94 rows used)

Convert: `python tools/build_winterveil_art.py` (all three at once).
**Not** `art_convert.py banner`, which this first said: banner writes an opaque RGB picture, for
zone art, and the divider has to keep its transparency. Nor `art_convert.py cut`, which fills the
canvas and pins the piece top-left - the garland's render is 3.84:1, so filling 512 x 128 would
draw it 51 px tall in game, where the three rules it sits between are 100 px apart and the
Hallow's End divider is 38. The tool fits it into the same 94-row band instead and centres it.

> Hand-painted fantasy trading card game art, World of Warcraft style, rich painterly textures,
> warm lighting, ornate but readable, original design (not from any existing game).
>
> A single horizontal Winter Veil garland, lying straight across the middle of the picture from the
> left edge to the right edge, seen straight on with no tilt and no perspective. Everything above
> and below the garland is flat pure magenta (#FF00FF).
>
> The garland is a rope of fresh evergreen fir, dipping very slightly in the middle, thick with
> needles. Soft plump snow lies along the top of it in rounded clumps. **Keep it bold and simple:
> about five or six large, well-separated ornaments along the whole length and no more** - big
> sprigs of holly with fat clusters of red berries, large round gold jingle bells, and generous
> bows of red ribbon with their tails hanging down. Each one should be big enough to read on its
> own; no small scattered detail, no clutter. The two ends taper away to nothing well before they
> reach the left and right edges, so the garland fades out rather than stopping abruptly.
>
> The garland is a long, low band - roughly five times wider than it is tall - and must not fill
> the height of the picture. Leave a clear band of empty magenta above and below it, and at both
> ends: nothing may touch the edge of the picture.
>
> Gilded warm gold on the bells, deep glossy green needles, rich warm red berries and ribbon,
> bright white snow - the same palette and the same crisp, saturated painterly finish as the
> matching board. Warm candlelight from the left catching the gold and the berries, cool blue only
> in the shadows under the needles; snug and festive, not bleak. Cosy storybook Christmas mood.
> No text, no letters, no numbers, no logos, no people, no creatures, no user interface.

### 3. Pile — `Media\MurlocTacToe_Pile_WinterVeil.tga` (256 x 256, the top 126 rows used)

Convert: `python tools/build_winterveil_art.py` (all three at once); it fits the pile inside its
126 rows and centres it, so nothing can cross the crop line.

> Hand-painted fantasy trading card game art, World of Warcraft style, rich painterly textures,
> warm lighting, ornate but readable, original design (not from any existing game).
>
> A small heap of wrapped Winter Veil presents sitting in a shallow drift of snow, seen straight
> on from the front at eye level, centred, nothing cut off. Everything around the heap is flat pure
> magenta (#FF00FF).
>
> **Four or five** boxes, large and simple, stacked and leaning against one another: deep warm red
> and deep forest green wrapping paper, each tied with a wide gold or cream ribbon and finished
> with a generous bow on top. Keep the shapes big and bold and the group uncrowded - no small
> boxes, no fine pattern on the paper. Snow has settled on the lids and along the ribbons, and the
> lowest boxes are half buried in the drift. One big sprig of holly with red berries rests against
> one of them.
>
> The heap is a wide, low group - about twice as wide as it is tall - with the snow drift as its
> base. Leave a clear margin of empty magenta all round it: nothing may touch the edge of the
> picture.
>
> Gilded warm gold ribbon, deep glossy red and green paper, bright white snow - the same palette
> and the same crisp, saturated painterly finish as the matching board. Warm candlelight from the
> left pooling on the snow and glinting off the gold, cool blue only in the shadows between the
> boxes; snug and festive, not bleak. Cosy storybook Christmas mood. No text, no letters, no
> numbers, no logos, no people, no creatures, no user interface.

## Winter Veil, further in (prompts 2026-10-21, Shannon)

Three more, all wired up already - each drops in under its name and nothing else changes.

- `Media\GemMatch_Board_WinterVeil.tga` - Gem Match had no seasonal dress at all; it has the hook now.
- `Media\CardBack_WinterVeil.tga` - joins Almanac and Wild in Settings > Wild Gambit > Card back.
- `Media\Window_WinterVeil.tga` - joins the four tables in Settings > Wild Gambit > Table.

The card back and the table follow the **same switch as the holiday board** ("Holiday boards"), so
during Winter Veil the whole table dresses together and your own choices come back afterwards.

The style line is rule 7's, word for word. The palette is the one the Murloc Tac Toe board settled
on - gilded warm gold, deep glossy green, warm red, bright white snow, candlelight - so all the
Winter Veil art sits together. Every one of them leaves a clear margin: nothing touching the edge.

### 4. Gem Match board — `Media\GemMatch_Board_WinterVeil.tga` (1024 x 1024)

Convert: `python tools/build_winterveil_art.py` (it lines the grid up, then darkens it)

**The grid's size is the thing to get right, and it can't be fixed afterwards.** Gem Match draws
its gems at fixed places - 139 to 895 of 1024 across, 8 cells of 94.5 px - and the board art has
to meet them, because `boardArt:SetAllPoints()` maps the texture straight onto the frame with no
fitting. The first render painted its 64 sockets only 631 px across (cells of 78.9), so every gem
would have overhung its socket by 15.6 px and the outer ones sat on the frame. Scaling the art up
the 20% needed would push the painted frame off the canvas, so there is no saving it in
conversion - hence the sentence about the grid filling three-quarters of the picture. A small
offset *is* fixable (the tool shifts and scales onto the code's grid); the wrong *size* is not.

Murloc Tac Toe's board was checked the same way and is correct: its card cells sit inside the
painted ice panes with a margin, which is what you want - the cells smaller than the painted
sockets, never larger.

> Hand-painted fantasy trading card game art, World of Warcraft style, rich painterly textures,
> warm lighting, ornate but readable, original design (not from any existing game).
>
> A square game board for a gem-matching puzzle, seen straight from above, flat on, no tilt and no
> perspective, centred, the whole board inside the frame and nothing cut off. The background
> outside the board is flat pure magenta (#FF00FF).
>
> A heavy carved oak frame, gilded with warm gold knotwork and heaped with soft plump snow on every
> surface that faces upwards, surrounds a large grid of **eight by eight** small square sockets -
> sixty-four shallow dips in dark blue-green ice, evenly spaced, separated by narrow snow-dusted
> ribs.
>
> **The grid is large.** It fills the middle three-quarters of the picture: its outer edge is about
> one seventh of the picture's width in from each side, leaving only a narrow decorated frame
> around it. The sockets are big, and the frame is slim.
>
> **The sockets must be dark, plain and empty** - faint cracks and frozen bubbles at most, nothing
> sitting in them, no gems, no ornaments, no bright highlights. All the detail belongs on the
> frame.
>
> The frame is trimmed for the holiday: a swag of fresh evergreen fir with red berries, glossy
> holly and red ribbon across the top, a few large gold jingle bells, and a small iron lantern with
> a candle burning in it on one lower corner, throwing a pool of golden light across the snow.
>
> Leave a clear margin of empty magenta all the way round the board, about one twentieth of the
> picture's width: no part of the frame or its trimmings may touch or run off the edge.
>
> Gilded warm gold, deep glossy green, warm red, bright white snow; warm candlelight with cool blue
> twilight only in the shadows; snug and festive, not bleak. Cosy storybook Christmas mood. No text,
> no letters, no numbers, no logos, no people, no creatures, no user interface.

### 5. Card back — `Media\CardBack_WinterVeil.tga` (256 x 512)

Convert: `python tools/art_convert.py cut docs/art_source/CardBack_WinterVeil.png "<Media>/CardBack_WinterVeil.tga" 256 512 fill`

**Written again 2026-10-21** (Shannon, on the first one: "it's skewed", then "I don't like the
design"). Both were my fault, and the first one need never have come up:

1. **Don't ask Gemini to paint it stretched.** The sheet is 256 x 512 and the game draws it at
   92 x 124 with no texture coordinates, so it is squashed to 0.674 of its height - which is why
   `CardBack_Almanac`'s compass sits in a tall oval on the sheet and reads as a circle in play. The
   first prompt therefore asked for a 1:2 card with everything painted half again as tall. It came
   back looking skewed because it *was* skewed. Pointless: `art_convert cut ... fill` stretches a
   picture to fill the canvas, so asking for an ordinary 3 x 4 card and letting the conversion do
   the stretch gives the same texture with none of the fighting. Judge the render as a normal card.
2. **Follow the family.** Both existing backs are the same design: a pale cream border with a thin
   gold rule and small ornaments in the corners, a deep coloured field with a faint damask, and a
   single **circular medallion** in the middle - a gold compass rose on dark red (Almanac), a
   bronze wolf's head in a jewelled ring on dark green with flowering vines (Wild). The first
   Winter Veil attempt was a huge wreath filling the whole card, which broke that pattern and
   fought its own border. This one is a medallion like the others.

The field colour is deliberately **cold blue-green**: dark red and dark green are taken by the two
backs it sits beside in the picker.

> Hand-painted fantasy trading card game art, World of Warcraft style, rich painterly textures,
> warm lighting, ornate but readable, original design (not from any existing game).
>
> The back of a playing card, upright portrait, **three units wide by four tall**, seen straight
> on, flat, no tilt and no perspective, filling the whole frame edge to edge.
>
> A pale cream border runs round the outside of the card, with a thin gold rule inside it and a
> small gold snowflake ornament in each of the four corners. Inside that is a deep, cold
> blue-green field, almost teal, covered in a faint darker damask of frost ferns - a pattern you
> notice only on looking, never bold.
>
> Centred on the field is a single **round gold medallion**, ornately carved like old metalwork:
> a six-pointed snowflake in relief, set in a raised ring. A narrow garland of dark evergreen fir
> with small red berries is wound round the outside of the ring, and a small red ribbon is tied at
> the bottom of it. A little snow rests on the top of the ring.
>
> The medallion is **perfectly round** and sits in the middle of the card with a generous margin of
> plain field all round it - it takes up about half the card's width. The whole design is
> symmetrical left to right, and reads the same upside down as the right way up, as a card back
> should. Nothing is cut off.
>
> Deep cold blue-green, antique gold, dark green, a little warm red, soft white snow; lit evenly
> from the front, rich and restrained. Cosy storybook Christmas mood. No text, no letters, no
> numbers, no logos, no people, no creatures, no user interface.

**The stag was taken** (it echoes the wolf on the Wild back and the Winter Reindeer champion) and
two were painted. The one shipped is the second, `CardBack_WinterVeil.png`: a thinner, more
irregular border that sits closer to the worn look of the other two. The first is kept beside it as
`CardBack_WinterVeil_v1-medallion.png` - a heavier cream border, nearer Almanac's weight, with a
larger snowflake roundel in each corner. To go back to it, swap the two file names and re-run
`tools/build_winterveil_art.py`; nothing else changes.

**The edge wear is the converter's job, not the prompt's.** Neither existing back is a clean
rectangle - their borders are nibbled and torn, and peak at alpha 23 and 72 along the outermost
row - so `cardback()` eats the edge in with the same soft noise and occasional deeper tear that
`art_convert.parchment` gives the dungeon card, lighter. Don't ask Gemini for tattered edges as
well: the second render painted some in and the two sit together fine, but the silhouette is what
actually matters and only the converter can cut that.

One trap worth remembering: the wear measures how far each pixel is from the nearest **clear** one,
so a card painted edge to edge has nothing to be eaten from and comes out untouched (the first run
wrote alpha 255 along the whole top row). `cardback()` insets the card by a pixel first, which is
what the other backs do too.

### 6. Table — `Media\Window_WinterVeil.tga` (1024 x 1024, and it must be SQUARE)

Convert: `python tools/art_convert.py full docs/art_source/Window_WinterVeil.png "<Media>/Window_WinterVeil.tga" 1024 1024`

**Written again 2026-10-21 after the first render.** Two things were wrong in the first version of
this prompt, both mine:

1. **It must be square.** The Wild Gambit window is 816 x 788 - as near square as makes no odds -
   and the texture is stretched straight onto it. The first render came back 1.83:1 landscape,
   which would have been drawn **1.72x taller than painted**: round bells into tall ovals.
2. **It must be dark.** `Window_Tavern.tga` averages 44/255 - a dim tavern table in low light. The
   first prompt said to paint it *brighter* than it should end up, which is backwards: the picture
   is dimmed only slightly (0.85) in code, and the players' names, scores and the board are drawn
   over it in white and gold. A bright table makes all of that hard to read.

Also worth knowing: the board and the two hand columns cover the middle of it. Only a band around
the outside is ever seen - roughly a sixth of the width down each side, a quarter across the top
and an eighth across the bottom. So the decoration belongs in that band, while the middle stays a
plain continuous surface, as the tavern table's does.

> Hand-painted fantasy trading card game art, World of Warcraft style, rich painterly textures,
> warm lighting, ornate but readable, original design (not from any existing game).
>
> **A square picture, exactly as tall as it is wide.** The top of a heavy dark wooden table seen
> straight from above, flat on, with no tilt and no perspective, filling the whole frame edge to
> edge. No border, no frame, no background around it - the table is the whole picture.
>
> It is a **dark, dim scene lit by one low candle somewhere off to the left**: deep brown timber,
> almost black in the corners, with a soft warm pool of light that never becomes bright. Think of
> an old tavern table late at night rather than a bright Christmas photograph. The wood grain,
> knots and worn edges run right across the picture, including the middle.
>
> A fine dusting of snow has settled on the table, heavier round the outside and thinning to almost
> nothing in the middle.
>
> **The middle of the picture must stay plain and quiet** - bare snow-dusted wood, no ornament, no
> props, nothing bright - because a game board is laid over it and covers it. All the decoration
> sits in a band round the **outer edge**: a few sprigs of evergreen fir and holly with red
> berries, two or three gold jingle bells, a pine cone, a short twist of red ribbon. Keep them
> sparse and tucked into the corners and edges, not crowded, and let the shadows swallow them at
> the very edge.
>
> Dark and restrained overall - deep brown wood, muted green, dark red, soft grey-white snow, a
> little dull gold, and one warm pool of candlelight. Low contrast, nothing glaring. Snug and
> festive but dim. No text, no letters, no numbers, no logos, no people, no creatures, no user
> interface.

### 7. Wild Gambit board, re-rolled — `Media\Board_WinterVeil.tga` (1024 x 1024, SQUARE)

Convert: `python tools/art_convert.py board docs/art_source/Board_WinterVeil.png "<Media>/Board_WinterVeil.tga" 1024 1024`

**Re-rolled 2026-10-22** (Shannon, in game: "the card slots are over the edge art work", and then
"doesn't look correct at the bottom either"). The painting itself is liked — keep the jovial yeti
and the stag. What is wrong is the **composition**: the four corner medallions sit *inside* the
stone panel and their heads, antlers and horns cut diagonally across all four corner card slots.

Measured on the texture: the nine slots occupy **x 240–799, y 204–846** (559 x 643), and the
largest ornament-free rectangle in the painting is only about **x 205–800, y 275–800** (595 x 525).
Wide enough, **118 px too short**. No value of `inner` in `BOARDS` (`QoL/WildGambit.lua`) can fix
that: making the grid fit vertically means drawing the art ~876 px tall instead of 688, which
stretches the heads to about 1.4:1 and pushes the top and bottom rune beams ~95 px outside the
window, where they are simply lost.

The other four boards (Glade, Ruin, Tavern, Hallow's End) all give the grid roughly **628 x 706**
of clear panel. That is the target, and it is the one thing the first prompt never said.

> Hand-painted fantasy trading card game art, World of Warcraft style, rich painterly textures,
> warm lighting, ornate but readable, original design (not from any existing game).
>
> **A square picture, exactly as tall as it is wide**, seen straight on, flat, with no tilt and no
> perspective, filling the whole frame edge to edge.
>
> A heavy carved stone game board for a card game. A broad stone border runs round the outside,
> banded with aged copper straps and carved with glowing pale-blue runes, dusted with snow and hung
> with small icicles, sprigs of dark evergreen fir and holly with red berries.
>
> At each of the four corners of the border sits a round carved medallion holding an animal's head,
> looking out at you, cheerful and friendly: a **shaggy white-furred yeti with curling horns and a
> broad good-natured grin** at the top left and again at the bottom right, and a **warm brown stag
> with spreading antlers and a kind face** at the top right and again at the bottom left. They are
> jovial and storybook, never fierce.
>
> **The middle of the board is one large, plain, empty rectangle of flat grey stone** — taller than
> it is wide, about five parts wide to six parts tall — with only faint cracks and a little frost
> across it. It takes up the middle two thirds of the picture, and it is completely bare: no
> ornament, no carving, no snow drifts, no runes, nothing laid on it. Playing cards are dealt onto
> this panel and must not cover anything.
>
> **Every decoration stays outside that middle rectangle, on the stone border.** This matters more
> than anything else in the picture: the four animal heads sit on the border and face outward, and
> **no horn, no antler, no fur, no holly, no berry, no icicle and no ribbon may cross into the
> middle rectangle at any point, least of all at its four corners.** The corners of the middle
> rectangle must be clean, empty stone. Keep the medallions small enough to sit wholly within the
> border's width.
>
> Cold grey stone, aged copper, pale glacier blue runes, dark evergreen, deep red berries, soft
> white snow, warm cream antler and horn. Lit evenly, rich and restrained, snug and festive. No
> text, no letters, no numbers, no logos, no people, no user interface.

**When it comes back**, check the clear panel before anything else: it wants to be about **640 x
720** of the 1024 square, roughly x 190–830, y 150–870, with all four corners bare. Then set
`BOARDS.WinterVeil.inner` in `QoL/WildGambit.lua` to those edges as fractions of 1024 —
`{ 190/1024, 150/1024, 830/1024, 870/1024 }` if it lands on the numbers above. (The present entry
divides x by **841** where every other board divides by 825; that was measured hastily and should
not be copied.)

### 8. Gem Match board, re-rolled — `Media\GemMatch_Board_WinterVeil.tga` (1024 x 1024, SQUARE)

Convert: `python tools/art_convert.py board docs/art_source/GemMatch_Board_WinterVeil.png "<Media>/GemMatch_Board_WinterVeil.tga" 1024 1024`
— and if the grid lands where this prompt asks, **that is the whole conversion**: no scaling, no
offset, nothing cropped. Delete `GEM_PAINTED` from `tools/build_winterveil_art.py` when it does.

**Re-rolled 2026-10-22** (Shannon, in game: "the cropping on the top especially... too clean
looking, losing some of the texture, making it look too flat").

What actually happened, measured: the first painting's socket grid was about a tenth too small and
sat low in the frame, so the conversion had to enlarge it 1.100 x 1.124 and shift it up to put the
sockets under the gems. That pushes the painting off the canvas unevenly — **75 px lost from the
top** against 47 left, 55 right and 52 bottom — and the garland and bells live in exactly those top
75 px. That is the cropping.

The flatness is **not** lost sharpness, which is worth knowing before anyone sharpens anything: the
shipped board measures 9.29 of fine detail against the ordinary Gem Match board's 4.78, so it is
already nearly twice as crisp as the one beside it. Enlarging cost 10% (10.31 → 9.29). What reads
as flat is the cropped garland plus an ice field plainer than the ordinary board's carved knotwork.
So: put the garland back by not cropping it, and give the ice more to look at.

**The one thing that must be right.** The game draws the gems in a fixed place: an 8 x 8 grid
filling **x 139–895, y 129–885** of the 1024 square — **756 px square, each cell 94.5 px**, with a
frame of about **135 px** around it. Match that and nothing is scaled or cropped.

> Hand-painted fantasy game art, World of Warcraft style, rich painterly textures, warm lighting,
> ornate but readable, original design (not from any existing game).
>
> **A square picture, exactly as tall as it is wide**, seen straight from above, flat, with no tilt
> and no perspective, filling the whole frame edge to edge.
>
> A frozen pond set in a broad frame of carved golden oak, decorated for midwinter: a garland of
> dark evergreen fir with red berries and gold jingle bells lying along the top of the frame, and a
> lit brass lantern resting against the bottom right corner of the frame.
>
> Set into the ice is a grid of **exactly eight rows and eight columns** of identical square
> sockets — sixty-four in all — like a chocolate box or an ice cube tray, each one a shallow square
> hollow with a slightly darker floor, divided from its neighbours by narrow raised ribs of pale
> ice. Every socket is the same size and perfectly square, the rows and columns are straight and
> evenly spaced, and the whole grid is square overall.
>
> **The grid of sockets fills the middle of the picture**, taking up about three quarters of its
> width and three quarters of its height, centred, leaving an even border of carved frame about an
> eighth of the picture's width on every side — the same width at the top as at the bottom.
>
> The ice itself is rich and worth looking at: deep blue-green under the surface, with frost ferns,
> trapped bubbles, fine hairline cracks catching the light, and a cold sheen across it. **But keep
> all of that inside the sockets and the ribs** — the garland, the bells and the lantern stay on
> the wooden frame and must never reach over any socket, because a gem is drawn in every one.
>
> Deep blue-green ice, warm golden oak, dark evergreen, deep red berries, antique gold, one small
> warm lantern flame. Rich and painterly, cosy midwinter. No text, no letters, no numbers, no
> logos, no people, no creatures, no user interface.

**When it comes back**, count the sockets down one column and across one row before anything else.
Do not scan for the ribs: the cracks painted into the ice break one rib scan into a dozen false
columns and the frame's inner shadow reads as another — that is how the first one was miscounted as
8 x 9 and a row was cut out of it by mistake. Counting the dark socket runs, averaged down a column
and across a row, gave a clean 8 x 8 first time.
