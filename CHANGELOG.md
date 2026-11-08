# Changelog

## 1.3.6 — 2026-11-08

- Expanded Automatically open containers to all carried items Blizzard identifies as loot containers, replacing the clam-only restriction. Existing toggle choices and combat/interaction safeguards remain; unlocking and confirmations stay manual.

## 1.3.5 — 2026-11-07

- Restored action paging to the v1.3.3 behavior after fixing the v1.3.4 secure-snippet regression; manual pages 2-6 suspend modifier paging until page 1 is selected.
- Removed the Native setup page and its camera, dispel and panel tools.
- Added separate default-off Items options for opening four known clam types and using newly acquired direct quest-starting items. Quest acceptance stays manual; combat, casting and native item interactions pause use.

## 1.3.4 — 2026-11-07

- Held action-paging modifiers now override manually selected pages; releasing restores the selected native page. Paging can resume after a temporary attribute conflict clears, while preserving foreign overrides and native special bars.
- Removed automatic enchant-replacement confirmation so enchants and armor kits retain Blizzard's normal confirmation dialog. Old saved flags no longer activate it.
- Added a Native setup page with on-demand wheel-binding diagnosis and an explicit camera-wheel repair for minimap or unbound assignments, preserving custom bindings and active overrides.
- Added explicit native dispel-indicator setup and shortcuts to Blizzard party/raid settings, Edit Mode, click casting and camera bindings. Existing debuffs remain visible; spell bindings stay manual.
- Added an independent, default-off spell ID option for the main Blizzard spell tooltip using native tooltip callbacks.
- Corrected portable README image and document URLs and added the WowUp Hub link.

## 1.3.3 — 2026-11-06

- Fixed the action-paging checkbox reading an obsolete saved setting, preventing reliable enable and disable behavior.

## 1.3.2 — 2026-11-06

- Restored default-off modifier paging with page 1 as its starting page and synchronized displayed page numbers. Hold Shift for page 2 by default; releasing returns to page 1.
- Manual page selection suspends modifier paging until page 1 is selected again. Native bonus/vehicle bars retain their behavior; forms without a bonus bar can use modifier paging.

## 1.3.1 — 2026-11-06

- Removed the broken graphics settings page and modifier action-bar paging. These features remain unavailable pending fixes.

## 1.3.0 — 2026-11-06

- Added opt-in hold-to-page controls for Blizzard main action buttons, with configurable Shift/Ctrl/Alt pages and reversible temporary modified key bindings.
- Native stance, form, bonus, vehicle, override and other special action bars retain their normal paging.

## 1.2.0 — 2026-11-06

- Added explicit HDR and world-effect controls using native graphics preferences, including ground-effect density and distance.
- Added access to native quest-level labels, equipped-ammunition counts and item ID/vendor-value tooltip details.
- Added manual marking of eligible non-equipment vendor items and reviewed sales at an open merchant; existing automatic grey-junk sales are unchanged.

## 1.1.1 — 2026-11-06

- Replaced bag-hover and Edit Mode hooks with removable native callbacks, preserving combat safeguards and native opacity restoration.

## 1.1.0 — 2026-11-05

- Added an opt-in Convenience page for native bag disenchanting, class Train All, bulk buying and cost-reviewed restock targets.
- Added selected loot and enchant confirmations, direct flight-map opening, spell-rank warnings and highest-value quest reward markers.
- Added a shortcut to Blizzard click-casting settings; new options start disabled and preserve native combat and confirmation boundaries.

## 1.0.5 — 2026-11-05

- Fixed the combined bag drag control to cover the native title and receive mouse input above its frame layers.

## 1.0.4 — 2026-11-05

- Added optional dragging and saved positioning for the combined bag window, with a reset to Blizzard placement.
- Shortened the quest-header setting label to prevent overlap.

## 1.0.3 — 2026-10-26

- Added Wago distribution support for tagged releases.

## 1.0.2 — 2026-10-14

- Added optional action-bar fading during combat, with 0%, 25%, 50% and 75% opacity.
- Bars return to their normal opacity outside combat and in Edit Mode. Keybinds and mouse clicks remain active at 0%.

## 1.0.1 — 2026-10-14

- Updated project branding, distribution links and optional support information.
- Added CurseForge project metadata for addon managers.
- Gameplay features are unchanged from 1.0.0.

## 1.0.0 — 2026-10-12

WoW Forever only.

### Features

- Account-wide settings, draggable window, page-specific bulk controls and
  confirmed reset. `/murgle`, version/reset subcommands and `/rl` when available.
- Optional hiding of Micro Menu, bag bar, XP bar, macro names and totem timers;
  buff-arrow hover; Talking Head, boss-banner and zone-text suppression.
- Objective Tracker header cleanup, font sizes and Always / Out of Combat / Hidden
  visibility. Optional blocking of new help tips and standard loot-reward toasts.
- Square minimap with a thin border and native ring cleanup; independent controls
  for the rim, day/night artwork, header, zone text, clock and minimap buttons.
- Compact player, target and target-of-target artwork; independent player-name
  and enemy-faction controls; native nameplate modes.
- Chat utility/voice button and Combat Log hiding, with Hide / Fade / Default
  choices for regular and custom chat tabs.
- Tooltip cursor placement and combat hiding for unit, object and corpse tooltips.
- Native quest-object sparkles and automatic watching of recognized reputation gains.
- Optional quest acceptance and turn-in without reward choices or money costs.
  World Refresh Just hide / Accept & hide modes with Shift/combat bypass.
- Native Spell Queue Window slider and an on-demand latency-based suggestion.
- Fast Loot respecting native Auto Loot; optional affordable repair, guild-fund
  preference and unlocked poor-quality item selling on merchant opening.
- All / Important only error modes and 13 sound mute controls, with
  Mute all listed / Unmute all listed buttons.

### Recent changes

- Cursor positions, World Refresh modes and guild repair preferences appear below
  their parent option only when enabled, preserving saved choices while hidden.
- Removed ineffective tooltip spacing reduction and the duplicate minimap
  coordinates option. The current native coordinates preference is preserved.
- Hide minimap rim appears only outside square mode. Help marks sit beside captions.
- Removed unsupported class-colour and independent quest-area-circle controls.
  Compact frames retain native bar shapes and target curvature.
- Updated player level/resting-state restoration and target faction/leader artwork
  handling; added independent compact target-of-target frames.
