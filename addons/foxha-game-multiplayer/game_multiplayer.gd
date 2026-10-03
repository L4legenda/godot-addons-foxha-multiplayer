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
const NetworkClient := preload("res://addons/foxha-game-multiplayer/network_client.gd")
const SessionPanel := preload("res://addons/foxha-game-multiplayer/session_panel.gd")

var player_list: CanvasLayer
var client: NetworkClient


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player_list = PlayerListScene.instantiate()
	add_child(player_list)
	player_list.pause_game = false
	client = NetworkClient.new()
	client.name = "NetworkClient"
	client.api_url = ProjectSettings.get_setting("foxha_multiplayer/api_url", "https://games.foxha.ru")
	client.game_id = ProjectSettings.get_setting("foxha_multiplayer/game_id", "")
	client.protocol_version = ProjectSettings.get_setting("foxha_multiplayer/protocol_version", "1")
	add_child(client)
	var session := SessionPanel.new()
	session.attach(player_list, client)
	player_list.action_requested.connect(_on_action_requested)
	client.initialize.call_deferred()


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
	if action == "invite" and player.has("id"):
		await client.invite_player(str(player.id))
	elif action == "join" and player.get("roomCode") != null:
		await client.join_lobby(str(player.roomCode))
	elif action == "join":
		client.message.emit("У игрока нет доступного лобби.")
