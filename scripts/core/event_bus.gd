extends Node

var _listeners: Dictionary = {}

func emit(event_name: String, data: Dictionary = {}) -> void:
	for cb in _listeners.get(event_name, []).duplicate():
		if not cb.is_valid():
			off(event_name, cb)
			continue
		cb.call(data)

func on(event_name: String, callable: Callable) -> void:
	if not _listeners.has(event_name):
		_listeners[event_name] = []
	if _listeners[event_name].has(callable):
		return
	_listeners[event_name].append(callable)

func off(event_name: String, callable: Callable) -> void:
	if _listeners.has(event_name):
		_listeners[event_name].erase(callable)

func clear() -> void:
	_listeners.clear()
