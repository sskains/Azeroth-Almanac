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
