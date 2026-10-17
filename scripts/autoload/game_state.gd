extends Node
## Story flags and scene retain their original behavior; journal is additive.

signal state_changed

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2
const DEFAULT_SCENE := "res://scenes/game.tscn"

var flags: Dictionary = {}
var current_scene: String = DEFAULT_SCENE


func set_flag(name: String, value: Variant) -> void:
	flags[name] = value
	state_changed.emit()


func get_flag(name: String, default: Variant = false) -> Variant:
	return flags.get(name, default)


func new_game() -> void:
	flags.clear()
	current_scene = DEFAULT_SCENE
	Journal.restore([])
	state_changed.emit()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"scene": current_scene,
		"flags": flags,
		"journal": Journal.entries(),
	}
	# Write beside the original, then replace it only after a successful flush.
	var temporary := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return false
	if DirAccess.rename_absolute(temporary, SAVE_PATH) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return true


func load_game() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return false
	if typeof(parser.data) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parser.data
	# Preserve the original scene assignment and flags fallback exactly.
	current_scene = data.get("scene", "res://scenes/game.tscn")
	var loaded_flags: Variant = data.get("flags", {})
	flags = loaded_flags if typeof(loaded_flags) == TYPE_DICTIONARY else {}
	# Missing or malformed journal data must not prevent story-state recovery.
	Journal.restore(_journal_ids(data.get("journal", [])))
	state_changed.emit()
	return true


func _journal_ids(raw_entries: Variant) -> Array[String]:
	var ids: Array[String] = []
	if typeof(raw_entries) == TYPE_ARRAY:
		for id: Variant in raw_entries:
			if typeof(id) == TYPE_STRING and not id.strip_edges().is_empty():
				if id not in ids:
					ids.append(id)
	return ids


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
