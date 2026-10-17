# Journal/save regression checklist

Run on `fix/journal-save-persistence` with a disposable save or a backup of
`user://save.json`. Save edits below must remain valid JSON. The journal reader
UI is pending; inspect `Journal.entries()` through the debugger or a test harness.

## Required checks

### 1. Normal Save and Continue

- [ ] Discover two distinct entries and make a story choice. Save, quit the process, relaunch, and Continue.

**Expected:** Saved scene and story flags restore as before, including false
values. Both journal IDs restore in discovery order, without replaying
`entry_added` discovery events.

### 2. Old saves without journal data

- [ ] Remove `journal` from a save and set `version` to 1. Populate the in-memory journal, then load. Repeat with no version field. Save again and Continue.

**Expected:** Load succeeds, the journal becomes empty, and story flags survive.
No entries are inferred from flags. The upgraded save loads successfully.

### 3. New Game

- [ ] Discover entries and set story flags, return to the title screen, and start New Game.

**Expected:** In-memory journal and flags clear; scene resets to the ground
floor. The old disk save remains until explicitly replaced: Continue before
saving the new run restores the old run.

### 4. Duplicate entries

- [ ] Discover A twice. Separately load `"journal": ["A", "B", "A"]`.

**Expected:** Live discovery stores A once and emits one discovery event. The
loaded list is `["A", "B"]`. IDs are compared exactly; surrounding whitespace
is not normalized.

### 5. Broken journal data

- [ ] Load saves with `journal` set to a string, null, number, or object. Then try `["A", 123, null, "", "   ", "A", "B"]`.

**Expected:** Non-lists produce an empty journal; the mixed list produces
`["A", "B"]`. Scene and valid story flags still load. Unknown nonblank string
IDs are retained.

## Additional checks

- [ ] **Replace, don't stack:** Save A, discover B without saving, then load twice. Only A remains after each load; no discovery events replay.
- [ ] **Empty saved journal:** Load `"journal": []` over a populated journal. Journal becomes empty; scene and flags restore.
- [ ] **Broken whole save:** Try truncated JSON or a JSON list as the root. Load returns false and leaves in-memory state unchanged.
- [ ] **Existing flag fallback:** Load with flags missing or non-dictionary. Flags become an empty dictionary; valid flag dictionaries retain their values.
- [ ] **Failed save:** Keep a known-good save, discover something new, and force staging failure (for example, a directory at `user://save.json.tmp`). Save reports failure. Remove the obstruction and load: the previous save still works and excludes the unsaved discovery.

Before launch, repeat save replacement and process-restart checks on each target
OS. Exercise disk-full, locked-file, and interrupted-write cases. Staging plus
rename reduces partial-write risk but does not guarantee recovery after power
loss. Dialogue-position persistence remains separate work.

## Automated check

Requires Godot 4.3+. Run from the repository root. The regression scene writes
and deletes its save; use an isolated user-data directory. Linux example:

```bash
godot --headless --editor --path . --quit
XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . tests/test_save.tscn
python3 tests/validate_dialogue.py
```

Expect `Save/journal regression failures: 0` and both dialogue graphs valid.
The automated suite covers the Continue handler in one process; the quit and
relaunch check above still needs a manual pass.
