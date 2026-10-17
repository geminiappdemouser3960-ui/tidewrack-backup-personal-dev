# Journal/save review for Sprint 29

Reviewed baseline: `8c9b1e4` (public-demo candidate). Changes prepared locally on
`fix/journal-save-persistence`; no remote push or PR.

## What actually survived before this patch

| State | Save/Continue behavior at baseline |
|---|---|
| Story flags | Serialized in `flags`; both true and false values restored. |
| Scene | Pause Save records `scene_file_path`; Continue loads that path. |
| Journal | Not serialized. Script not registered as an autoload; no discovery callers. |
| Player position | Not saved; ground-floor player respawns at its fixed starting position. |
| Dialogue | No graph/node/choice cursor saved. Pause is blocked during dialogue. |
| One-shot interactions | `_used` lives on each Interactable and resets on scene recreation. Current ground-floor objects are repeatable. |
| Settings | Not part of this save payload. |

Actual path: node/choice `set_flag` → DialogueManager `_apply_flags` →
GameState.flags → pause Save (`current_scene` set first) → user://save.json →
main-menu Continue → GameState.load_game → change scene. Main Menu does not
save automatically. New Game resets memory but does not delete the previous
on-disk save; an explicit Save replaces it.

The existing devlog says entries are recorded, but the code has no recording
caller. The stair plays placeholder dialogue, rather than entering the lamp
room; the lamp room has no player, save menu, puzzle, or relight interaction.

## Changes

- Register Journal before GameState. Keep ordered discovery IDs separate from
  narrative flags. Return defensive copies; ignore duplicate/blank discoveries.
- Gameplay discovery wiring is out of scope. Dialogue code and data remain
  unchanged; regression tests seed discoveries directly through Journal.discover.
- Save version 2 adds `journal`. Restore deduplicates IDs in first-seen order,
  preserves unknown IDs, and emits a collection change without discovery events.
- Version 1 and unversioned saves retain flags and default missing scene to the
  ground floor. Their journals start empty: historical discoveries cannot be
  reconstructed reliably. Revisiting the logbook records it normally.
- Reject malformed JSON and non-dictionary roots before mutating live state.
  Preserve the original scene assignment, missing-scene default, dictionary flags
  and empty-dictionary fallback for malformed flags. No new scene allowlist or
  version rejection. Missing/non-array journal data becomes empty; mixed arrays
  retain only nonblank string IDs. Journal corruption does not block story recovery.
- New Game clears both flags and journal. Successful load replaces both, avoiding
  stale state from another session.
- Stage writes in save.json.tmp, flush/check errors, then rename over save.json.
  Write/rename failure returns false. This reduces partial-write risk; it is not
  a guarantee against power loss and does not add backup recovery.
- Main-menu behavior remains unchanged.

Schema example:

```json
{"version":2,"scene":"res://scenes/game.tscn","flags":{"trusted_edith":false},"journal":["keeper_intro"]}
```

Compatibility means the new build can read old saves. An old build ignores the
new journal field and will discard it if it resaves; reverse compatibility is
not guaranteed. Back up saves before downgrading.

## Verification performed

Godot 4.3 stable on Linux:

- Headless editor import: passed without script errors.
- `tests/test_save.tscn`: passed, zero failures. Covers seeded journal discoveries alongside unchanged dialogue choices,
  all four belief/trust combinations, both radio choices, preservation of false
  and unknown flags, ordered/unknown journal IDs, copy isolation, duplicate
  discovery events, restoration without rediscovery, New Game reset, existing
  save replacement, v1/unversioned migration and resave, invalid JSON roots, unchanged permissive version/scene handling, malformed flags
  fallback, filtered journal data, truncated JSON, failed staging with old save retained, deletion,
  and the actual main-menu Continue handler opening the saved scene.
- Main menu and ground-floor headless smoke runs: passed.
- `python3 tests/validate_dialogue.py`: both graphs passed, zero warnings.
- `git diff --check`: passed.

Run tests with an isolated user-data directory: they write and delete save.json.

```bash
# Import first so Godot registers global script classes.
godot --headless --editor --path . --quit
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . tests/test_save.tscn
python3 tests/validate_dialogue.py
```

## Gates before calling the launch path done

- Manual end-to-end run: discover → Save → quit process → relaunch → Continue,
  plus repeated Continue and New Game → Save. The automated test runs the real
  handler within one process, not an OS-level restart.
- Journal reader UI: empty state, content lookup for known IDs, graceful handling
  of unknown IDs, discovery order, refresh on load/reset, scrolling, controller
  focus, keyboard close, and interaction with pause/dialogue. No reader exists yet.
- Windows/macOS target builds: verify rename-over-existing behavior and file
  locking. Exercise read-only directory, disk full, interrupted write, leftover
  temp file, and corrupt save. Only staging-open failure is fault-injected here.
- Decide whether invalid saves should disable Continue, offer recovery, or show
  a richer explanation. Currently existence enables it; loading returns false without a UI explanation.
- Decide launch resume scope for player position, one-shot interactions and
  dialogue checkpoints; none is persisted by this patch.
- Wire and playtest lamp-room access, controls, save menu and relight state.
  Its path can round-trip but that does not make the scaffold playable.
- Review New Game's existing disk-save behavior with UX: returning to the menu
  before saving still permits Continue of the previous run.
- Wire gameplay discovery in a separate change and agree on discovery timing.
  This branch persists entries supplied through Journal.discover only.

No story flag was renamed or reinterpreted; no synthetic discoveries are inferred
from legacy flags. A journal UI, autosave, position persistence, backup slots,
and lamp-room gameplay are follow-up work rather than claims of this patch.
