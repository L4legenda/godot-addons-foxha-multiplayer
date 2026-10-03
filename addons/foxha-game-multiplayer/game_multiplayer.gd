extends Node
## Foxha Game Multiplayer — точка входа аддона (автозагрузка FoxhaGameMultiplayer).
##
## Окно списка игроков создаётся автоматически при старте игры, горячая клавиша
## Shift+Tab обрабатывается самим окном. Из игры доступно:
##
##   FoxhaGameMultiplayer.open_list()
##   FoxhaGameMultiplayer.close_list()
##   FoxhaGameMultiplayer.toggle_list()
##   FoxhaGameMultiplayer.set_me({"nickname": "Me", "avatar_color": Color.BLUE})
##   FoxhaGameMultiplayer.set_friends([...])
##   FoxhaGameMultiplayer.set_other([...])
##   FoxhaGameMultiplayer.action_requested.connect(...)  # "invite" / "join"

## Игрок выбрал действие в выпадающем списке: action — "invite" или "join".
signal action_requested(player: Dictionary, action: String)

const PlayerListScene := preload("player_list.tscn")

var player_list: CanvasLayer


func _ready() -> void:
	player_list = PlayerListScene.instantiate()
	add_child(player_list)
	player_list.action_requested.connect(_on_action_requested)


func open_list() -> void:
	player_list.open()


func close_list() -> void:
	player_list.close()


func toggle_list() -> void:
	player_list.toggle()


func is_list_open() -> bool:
	return player_list.is_open


func set_me(player: Dictionary) -> void:
	player_list.set_me(player)


func set_friends(players: Array) -> void:
	player_list.set_friends(players)


func set_other(players: Array) -> void:
	player_list.set_other(players)


func _on_action_requested(player: Dictionary, action: String) -> void:
	action_requested.emit(player, action)
