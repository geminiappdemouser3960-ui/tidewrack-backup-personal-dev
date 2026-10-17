extends Node
## Ordered discovery IDs. Save/load belongs to GameState; no story flags here.

signal entry_added(id: String)
signal entries_changed

var _entries: Array[String] = []


func discover(id: String) -> void:
	if id.strip_edges().is_empty() or id in _entries:
		return
	_entries.append(id)
	entry_added.emit(id)
	entries_changed.emit()


func entries() -> Array[String]:
	return _entries.duplicate()


func has(id: String) -> bool:
	return id in _entries


## Replace the entire journal, including when the saved list is empty.
## Restore silently with respect to discovery notifications/rewards.
## Caller validates save data first. Unknown IDs survive content updates.
func restore(ids: Array[String]) -> void:
	var restored: Array[String] = []
	for id in ids:
		if not id.strip_edges().is_empty() and id not in restored:
			restored.append(id)
	_entries = restored
	entries_changed.emit()
