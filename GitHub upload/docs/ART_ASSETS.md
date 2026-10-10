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
- [ ] Gather_Treasure (gold): forest-floor ruins at dusk; in the right half, an iron-banded wooden chest with its lid ajar, gold coins and a single gem spilling out, a battered footlocker and a small locked strongbox beside it, candle and lantern glow; the left fades into dark mossy stonework.
- [ ] Gather_Fishing (blue): a quiet lakeshore at twilight; in the right half, a weathered wooden dock with a fishing pole and a red-and-white bobber making ripples, a wicker creel of fish, a shimmering school of fish just under the clear water, fireflies; the left fades into misty dark water.
- [ ] Gather_Skinning (leather brown): a hunter's camp at the edge of a dark pine forest; in the right half, hides and furs stretched on a wooden drying rack, a wolf pelt over a log with a skinning knife stuck in it, a campfire's orange glow; the left fades into shadowed forest.
- [ ] Gather_TooHigh (red): a forbidding mountain cliff high above; in the right half, out of reach on a far ledge, a glowing rare flower and a gleaming silver-white ore vein behind a red-orange haze, a frayed rope dangling short of them; the left is dark rock in the foreground under an ominous red sky.

## Crafting profession cards (prompts 2026-10-09)

Same family and rules as the Gathering cards above (the shared paragraph first, 4 : 1, left third dark and calm, subject in the right half), for the crafting professions on the Recipes page. Files `Media\Recipe_<Name>.tga`, 512 x 128. (Today the Recipes page's profession cards are half-width icon cards; with these pictures they would become full-width banner cards like Gathering's.)

- [ ] Recipe_Alchemy (violet and green): an alchemist's workbench by candlelight; in the right half, bubbling glass flasks and alembics in green, red and blue, a brass still with a curl of coloured vapour, dried herbs hanging from a beam, a mortar and pestle; the left fades into dark shelves of jars.
- [ ] Recipe_Blacksmithing (orange-red): a forge at night; in the right half, a glowing anvil with a red-hot blade, a hammer mid-rest, sparks, a roaring forge mouth, tongs and a quenching barrel, racks of swords and a breastplate; the left fades into soot-dark stone.
- [ ] Recipe_Enchanting (purple and blue): a quiet arcane study; in the right half, a runed copper rod over a softly glowing enchanting circle, floating motes and swirling violet dust, shimmering shards and a crystal on a velvet cloth, an open tome of sigils; the left fades into deep indigo shadow.
- [ ] Recipe_Engineering (bronze and steel): a cluttered gnomish workshop; in the right half, a half-built mechanical contraption with gears and pipes, a wrench and blasting powder kegs, a small mechanical squirrel, sparks from a soldering iron, blueprints pinned to a board; the left fades into dark machinery.
- [ ] Recipe_Leatherworking (warm tan): a tanner's workroom; in the right half, a leather jerkin and boots on a workbench, rolls of cured leather, awls, needles and thread, a stretched hide on a frame, a lantern; the left fades into shadowed timber.
- [ ] Recipe_Tailoring (soft blue and cream): a tailor's loft; in the right half, bolts of linen, wool and silk in rich colours, a spinning wheel, a half-sewn embroidered robe on a mannequin, scissors, spools of thread; the left fades into dusky drapery.
- [ ] Recipe_Cooking (warm amber): a tavern kitchen; in the right half, a cast-iron pot over a crackling hearth, a roast on a spit, fresh bread, sausages, spices and a wooden spoon on a chopping board, steam rising; the left fades into smoky dark beams.
- [ ] Recipe_FirstAid (clean white and red): a field medic's table in a canvas tent; in the right half, rolled linen and wool bandages, a small kit of salves and vials, a leather satchel stitched with a simple white leaf emblem, a lantern's warm glow; the left fades into dark canvas.
