@tool
extends EditorPlugin
## Плагин редактора для аддона Foxha Game Multiplayer.
## При включении регистрирует автозагрузку FoxhaGameMultiplayer — она сама создаёт
## окно списка игроков, так что в сценах игры ничего добавлять не нужно.
##
## Автозагрузка намеренно не удаляется в _exit_tree: редактор вызывает _exit_tree
## при каждом выходе, и тогда настройка пропадала бы из project.godot (проверено),
## а вместе с ней ломался бы запуск игры вне редактора и сборка экспорта.
## Чтобы полностью отключить аддон, удалите автозагрузку FoxhaGameMultiplayer
## в Project Settings → Autoload (или отключите плагин — окно создавать некому).

const AUTOLOAD_NAME := "FoxhaGameMultiplayer"
const AUTOLOAD_PATH := "res://addons/foxha-game-multiplayer/game_multiplayer.gd"


func _enter_tree() -> void:
	var settings := {
		"foxha_multiplayer/api_url": "https://games.foxha.ru",
		"foxha_multiplayer/game_id": "",
		"foxha_multiplayer/protocol_version": "1",
	}
	var changed := false
	for key: String in settings:
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, settings[key])
			changed = true
		ProjectSettings.set_initial_value(key, settings[key])
		ProjectSettings.add_property_info({"name": key, "type": TYPE_STRING})
	if changed:
		ProjectSettings.save()
	# На случай, если запись потерялась: восстанавливаем автозагрузку.
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		return
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	# Пишем именно res:// путь, а не uid:// — так аддон переносится между
	# проектами копированием папки. Сохраняем на диск: add_autoload_singleton
	# меняет настройки только в памяти.
	ProjectSettings.set_setting("autoload/" + AUTOLOAD_NAME, "*" + AUTOLOAD_PATH)
	ProjectSettings.save()
