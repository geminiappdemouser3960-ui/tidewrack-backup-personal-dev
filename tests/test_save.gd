extends Node
## Run with isolated XDG_DATA_HOME; this test writes user://save.json.

var failures := 0
var discoveries := 0
var notifications := 0


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)


func write_save(value: Variant) -> void:
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func _ready() -> void:
	Journal.entry_added.connect(func(_id): discoveries += 1)
	GameState.state_changed.connect(func(): notifications += 1)
	GameState.delete_save()
	check(not GameState.load_game(), "missing save fails")
	GameState.new_game()
	Journal.discover("")
	Journal.discover("  ")
	Journal.discover("keeper_intro")
	Journal.discover("keeper_intro")
	Journal.discover("future_content")
	check(discoveries == 2, "unique nonblank discovery events")
	var copy := Journal.entries()
	copy.clear()
	check(Journal.entries().size() == 2, "entries returns defensive copy")
	var expected_flags := {"skeptic": true, "believer": false, "trusted_edith": false,
		"radioed_tom": true, "lamp_relit": false, "future_flag": {"value": "kept"}}
	GameState.flags = expected_flags.duplicate(true)
	GameState.current_scene = "res://scenes/lamp_room.tscn"
	check(GameState.save_game(), "first save")
	check(GameState.save_game(), "replace existing save")
	GameState.new_game()
	check(Journal.entries().is_empty() and GameState.flags.is_empty(), "new game clears memory")
	check(GameState.has_save(), "new game preserves disk save until explicit save")
	check(GameState.load_game(), "v2 round trip")
	check(GameState.flags == expected_flags, "all flag values survive")
	check(GameState.current_scene == "res://scenes/lamp_room.tscn", "scene survives")
	check(Journal.entries() == ["keeper_intro", "future_content"], "journal order and unknown IDs survive")
	check(discoveries == 2, "restore does not replay discovery events")
	Journal.discover("unsaved_entry")
	var discoveries_before_load := discoveries
	check(GameState.load_game() and Journal.entries() == ["keeper_intro", "future_content"],
		"load replaces live journal and removes unsaved entries")
	check(GameState.load_game() and Journal.entries() == ["keeper_intro", "future_content"],
		"repeated load does not stack entries")
	check(discoveries == discoveries_before_load, "replacement emits no discovery events")
	write_save({"version": 2, "flags": expected_flags, "journal": []})
	check(GameState.load_game() and Journal.entries().is_empty(), "empty saved journal replaces populated journal")
	for legacy in [{"version": 1, "flags": expected_flags}, {"flags": expected_flags}]:
		Journal.discover("stale_legacy_entry")
		write_save(legacy)
		check(GameState.load_game(), "legacy load")
		check(GameState.flags == expected_flags and Journal.entries().is_empty(), "legacy flags kept; stale journal cleared")
		check(GameState.save_game() and GameState.load_game(), "legacy upgrade round trip")
	write_save({"version": 2, "journal": ["b", "a", "b"]})
	check(GameState.load_game() and Journal.entries() == ["b", "a"], "deduplicate in discovery order")
	var before_events := notifications
	for invalid in [null, [], "oops"]:
		write_save(invalid)
		check(not GameState.load_game(), "invalid save rejected: %s" % str(invalid))
		check(Journal.entries() == ["b", "a"] and GameState.flags.is_empty()
			and GameState.current_scene == GameState.DEFAULT_SCENE, "failed load preserves all state")
	check(notifications == before_events, "failed loads emit no state event")
	# Preserve the pre-existing permissive scene/flags/version semantics.
	for malformed_flags in [null, [], "bad", 42]:
		write_save({"flags": malformed_flags, "journal": ["kept"]})
		check(GameState.load_game() and GameState.flags.is_empty()
			and Journal.has("kept"), "malformed flags still fall back to empty dictionary")
	for version in [3, 1.5, "2", true]:
		write_save({"version": version, "scene": "res://future/chapter.tscn", "flags": expected_flags})
		check(GameState.load_game() and GameState.current_scene == "res://future/chapter.tscn"
			and GameState.flags == expected_flags, "no new version or scene restrictions")
	check(GameState.save_game(), "unrestricted scene can still be saved")
	for malformed_journal in [null, 42, {}, "bad", ["good", 8, null, "", "  ", "good"]]:
		write_save({"flags": expected_flags, "journal": malformed_journal})
		check(GameState.load_game() and GameState.flags == expected_flags, "bad journal does not block flags")
		check(Journal.entries() == (["good"] if malformed_journal is Array else []), "journal safely filtered")
	var broken := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	broken.store_string('{"version":')
	broken.close()
	check(not GameState.load_game(), "truncated JSON rejected")
	GameState.new_game()
	Journal.discover("keeper_intro")  # Fixture: gameplay discovery wiring is out of scope.
	check(DialogueManager.start("res://data/dialogue/keeper_intro.json", "logbook"), "logbook opens")
	check(Journal.has("keeper_intro"), "journal fixture present")
	DialogueManager.advance()
	DialogueManager.advance()
	DialogueManager.choose(0)
	DialogueManager.advance()
	DialogueManager.advance()
	DialogueManager.choose(1)
	DialogueManager.advance()
	check(GameState.get_flag("skeptic") == true and GameState.get_flag("trusted_edith", true) == false,
		"existing choice hooks unchanged")
	check(GameState.save_game(), "save discovered journal and flags")
	GameState.new_game()
	check(GameState.load_game() and Journal.has("keeper_intro") and GameState.get_flag("skeptic"),
		"real dialogue round trip")
	# Force staging failure without relying on filesystem permissions/root behavior.
	DirAccess.make_dir_absolute(GameState.SAVE_PATH + ".tmp")
	Journal.discover("unsaved")
	check(not GameState.save_game(), "staging failure reported")
	DirAccess.remove_absolute(GameState.SAVE_PATH + ".tmp")
	check(GameState.load_game() and not Journal.has("unsaved"), "failed write retains previous save")
	# Exercise both narrative branches, both trust choices, and both radio choices.
	for belief in [0, 1]:
		for trust in [0, 1]:
			GameState.new_game()
			Journal.discover("keeper_intro")
			DialogueManager.start("res://data/dialogue/keeper_intro.json", "logbook")
			DialogueManager.advance()
			DialogueManager.advance()
			DialogueManager.choose(belief)
			DialogueManager.advance()
			DialogueManager.advance()
			DialogueManager.choose(trust)
			DialogueManager.advance()
			DialogueManager.start("res://data/dialogue/keeper_intro.json", "radio")
			DialogueManager.advance()
			DialogueManager.choose(trust)
			DialogueManager.advance()
			var branch_flags := GameState.flags.duplicate(true)
			check(GameState.get_flag("skeptic" if belief == 0 else "believer"), "belief choice")
			check(GameState.get_flag("trusted_edith") == (trust == 0), "trust choice")
			check(GameState.get_flag("radioed_tom"), "radio choice")
			check(GameState.save_game(), "branch save")
			GameState.new_game()
			check(GameState.load_game() and GameState.flags == branch_flags
				and Journal.entries() == ["keeper_intro"], "branch round trip")
	# Keep this test node alive while the real menu changes the current scene.
	GameState.new_game()
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	get_tree().current_scene = menu
	menu._on_continue()
	await get_tree().process_frame
	await get_tree().process_frame
	check(get_tree().current_scene.scene_file_path == GameState.DEFAULT_SCENE, "Continue opens saved scene")
	check(Journal.has("keeper_intro") and GameState.get_flag("believer")
		and GameState.get_flag("radioed_tom"), "Continue restores journal and flags")
	GameState.delete_save()
	check(not GameState.has_save(), "delete save")
	print("Save/journal regression failures: ", failures)
	get_tree().quit(1 if failures else 0)
