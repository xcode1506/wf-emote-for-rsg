==================================================

	--= WF-EMOTE =--  (author: Hugo)

=================================================

Standalone emote & animation resource for RedM.
No escrow-locked code — everything here is editable.

=================================================

			--FEATURES--

=================================================

- Full emote book (634 entries): greetings, gestures, reactions, taunts,
  dances, stances/posing, sitting, injured, jobs, police, trading, smoking,
  washing, saloon, music, scenarios, props (holding hammer /
  cotton basket / baby ...), attached prop emotes (tray, newspaper, fiddle,
  toolbox, baby, basket, fan, parasol, book, candle, tea, champagne, apple)
  and custom female poses.
- Menu rendered by the resource's **own NUI page** (`ui/index.html`) — no
  external menu resource required. Torn-paper western book: tall dark sheet on
  the left with WESTFURY / EMOTES / "Express Yourself" branding, a six-tab
  strip (All, General, Dance, Sit, Social, Action), scrolling emote rows with
  PNG icons and favourites stars, an `x / y` page indicator and a footer that
  shows the highlighted emote. The right side stays untouched so the live 3D
  clone performs there without covering the scene.
- **3D preview**: while browsing, a local clone of your character performs
  the animation at the right of the screen — you see it before selecting.
  Selecting plays it on your real character.
- Full scrolling lists, Stop entry at the top, X stops everything.
- **Shared emotes** — play together with another player (reference mechanism:
  rpemotes shared emotes). Stand next to another player, pick one:
  `shared_handshake` (Handshake), `shared_hug` (Hug), `shared_cheer`
  (Celebrate), `shared_dance` (pair dance, initiator leads / partner
  follows), `shared_hostage` (grab / victim). Both players automatically face
  each other and play their role animation. Available in the menu under
  **Emotes → Shared**, or `/e shared_handshake`.
- **Native RDR2 UI audio** on both surfaces: the emote book and the world
  interaction picker play the game's own frontend sounds (open, close,
  navigate, accept, deny) via `PlaySoundFrontend`, and stay silent while the
  list is just being laid out. All pairs are configurable per surface.
- Favourites per character saved in MySQL (table `wf_emotes`, oxmysql).
- **World interactions** (`wf-interact`, ported from awz_interactions —
  original by kibook / AxeelWarZ): walk near a chair, bench, bed, piano,
  bath, bucket... and a prompt appears — press **J** to open the picker
  (with scenario preview of your character), Enter to start, X to stop.
  Every nearby action is merged into one flat scrollable list (no category
  headers). Bathing cleans blood/dirt. The picker uses the same torn-paper
  book styling as the emote menu.

=================================================

			--INSTALLATION--

=================================================

1. Copy the `wf-emote` folder to your server resources.
2. Ensure order in server.cfg:

```cfg
ensure oxmysql
ensure <your framework>
ensure wf-emote
```

3. Done — the menu needs no extra resource or item-image install.

=================================================

			--USAGE--

=================================================

| Action              | How                                            |
|---------------------|------------------------------------------------|
| Open the menu       | **F7**, `/wfemotes`, `/poses`                  |
| Navigate            | **↑ / ↓** arrows or mouse wheel, **Enter** or click to select |
| Switch tab          | **← / →** arrows (or click a tab)              |
| Toggle favourite    | **F** on a highlighted emote, or `/wfefav <command>` |
| Back / close        | **Backspace** or **Esc**                       |
| Play                | pick from the menu, or `/e <command>`          |
| Upper body only     | `/e <command> upper`                           |
| Stop                | **X** (unified), `/e c`, or the menu Stop row  |
| Browsing preview    | automatic while highlighting an animation      |
| World interactions  | prompt near usable objects, **J** opens picker |
| Interaction list    | one flat scroll: wheel or **↑ / ↓**, click or **Enter** to start |

All settings in `config.lua` under the `WF` table (open key, stop key,
commands, preview distance/camera/alpha, clip blend defaults). The book's
native UI sounds live in `WF.Sound` (open/close/nav/accept/deny, `enabled = false`
to mute). World interaction settings live in `wf_interact_config.lua` under the
`WFInteract` table; the picker's native UI sounds are in `WFInteract.Sound`
(same layout, set `enabled = false` to mute).
The book's overall size is a single knob: `--em-scale` in `ui/style.css`
(0.78 by default; lower it to shrink the whole panel proportionally).

=================================================

			--CREDITS--

=================================================

- Animation data based on: sirevlc RP overhaul emote commands, fks-animations
  (GPL-3.0, Fonkas), rm_30-custom-female-pose (RedMorrow), and
  femga/rdr3_discoveries (scenario lists, KIT emote list).
  Solo/shared dance and prop emote data: kibook/redm-emotes and
  deadyen_emotes (prop offsets researched by @cocomonksky).
- Menu UI: original NUI built for this resource. Emote book art (torn paper,
  grain, fonts) comes from the Westfury UI asset pack; the emote icons were
  generated for this resource as PNGs (`ui/assets/icons`). No external menu
  library is used.
- 3D preview technique inspired by awz_interactions (AxeelWarZ /
  kibook redm-interactions).
- World interaction picker (`wf-interact`) is a renamed, stripped-down port
  of awz_interactions (AxeelWarZ), itself based on kibook/redm-interactions —
  original scenario/interaction data and the object-detection approach belong
  to those authors.
- Native UI sound names and sound-set pairs: community frontend-sound lists,
  notably Nowimps8/RedM-info (`FrontEndSounds.lua`); the in-game satchel UI
  (Senexis/RedM-Native-Satchel) was used as a behaviour reference for when
  open/close/select feedback should fire.
- Thanks to everyone in the RedM modding community who published animation
  dictionaries, scenario lists and prop offsets so openly — this resource
  would just be a list of guesses without that work.
