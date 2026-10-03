# Foxha Game Multiplayer

Аддон Godot 4: окно со списком игроков по **Shift+Tab** — затемнение экрана
с анимацией 0.3 с, перетаскиваемое окно, разделы «Friends» и «Other»,
у каждого игрока стрелка с действиями «Пригласить» и «Присоединиться».

## Установка

1. Скопировать папку `addons/foxha-game-multiplayer/` в проект.
2. `Project → Project Settings → Plugins` → включить **Foxha Game Multiplayer**.

Плагин сам регистрирует автозагрузку `FoxhaGameMultiplayer`, поэтому добавлять
что-либо в сцены не нужно: окно создаётся при старте игры.

## Использование

```gdscript
# Данные игроков
FoxhaGameMultiplayer.set_me({"nickname": "Me", "avatar_color": Color.SKY_BLUE})
FoxhaGameMultiplayer.set_friends([
    {"nickname": "Alex", "avatar_color": Color.ORANGE_RED},
])
FoxhaGameMultiplayer.set_other([
    {"nickname": "Guest", "avatar_color": Color.GRAY},
])

# Управление окном
FoxhaGameMultiplayer.open_list()
FoxhaGameMultiplayer.close_list()
FoxhaGameMultiplayer.toggle_list()
print(FoxhaGameMultiplayer.is_list_open())

# Реакция на действия из выпадающего списка ("invite" / "join")
FoxhaGameMultiplayer.action_requested.connect(func(player, action):
    print(action, " -> ", player.nickname)
)
```

Пока `set_*` не вызваны, показываются заглушки из `player_list.gd` (MOCK_ME,
MOCK_FRIENDS, MOCK_OTHER) — так окно видно сразу после установки.

## Настройки

Открыть `addons/foxha-game-multiplayer/player_list.tscn` и выбрать корневой узел:

- `pause_game` — ставить игру на паузу, пока окно открыто (по умолчанию да);
- `release_mouse` — освобождать курсор и возвращать прежний режим при закрытии;
- `toggle_with_shift_tab` — реагировать на Shift+Tab (можно отключить, если
  окно открывается только из кода).

## Заметки

- Esc закрывает сначала выпадающий список, потом само окно.
- Клик мимо выпадающего списка закрывает только его.
- Стили и размеры окна — в `player_list.tscn`, цвета и тексты — в скрипте.
