# Foxha Game Multiplayer

Аддон для Godot 4: оранжево-чёрный оверлей по **Shift+Tab**, авторизация внутри игры, друзья, приглашения и WebRTC-лобби на **2–20 игроков**.

## Содержание

- [Установка и настройки](#установка-и-настройки)
- [Быстрый старт](#быстрый-старт)
- [API FoxhaGameMultiplayer](#api-foxhagamemultiplayer)
- [API сетевого клиента](#api-сетевого-клиента)
- [Сигналы клиента](#сигналы-клиента)
- [Форматы данных](#форматы-данных)
- [Примеры своего интерфейса](#примеры-своего-интерфейса)
- [Подключение игрового мира](#подключение-игрового-мира)
- [Настройка оверлея](#настройка-оверлея)
- [Диагностика и проверки](#диагностика-и-проверки)

## Установка и настройки

1. Скопируйте `addons/foxha-game-multiplayer/` в проект.
2. Для скачиваемой игры скопируйте также `addons/webrtc_native/` из этого репозитория и полностью перезапустите Godot. Бинарные файлы `1.2.2-stable` уже лежат в Git, в том числе Windows, Linux и универсальные macOS-библиотеки для Intel/Apple Silicon. При клонировании всего проекта отдельно скачивать их не нужно.
3. Включите **Foxha Game Multiplayer** в **Project Settings → Plugins**. Плагин добавит автозагрузку `FoxhaGameMultiplayer`.
4. В Project Settings задайте параметры ниже. При необходимости включите отображение расширенных настроек.

| Настройка | По умолчанию | Назначение |
| --- | --- | --- |
| `foxha_multiplayer/api_url` | `https://games.foxha.ru` | Адрес API без пути конкретного endpoint. |
| `foxha_multiplayer/game_id` | Пустая строка | Публичный UUID опубликованной игры, **не код владельца**. Обязателен. |
| `foxha_multiplayer/protocol_version` | `1` | Версия сетевого протокола игры. У всех участников должна совпадать; меняйте при несовместимых изменениях RPC/сцен. |

Настройки читаются при запуске автозагрузки. После изменения перезапустите игру.

Web-экспорт использует браузерный WebRTC и `postMessage`-мост страницы Foxha. Запускайте его внутри страницы игры на платформе; простая публикация HTML-экспорта на произвольном сайте не предоставляет этот мост. Для работы через разные сети серверу нужны настроенные STUN/TURN и актуальные game-auth/multiplayer endpoints.

Автозагрузка сохраняется при отключении редакторного плагина. Для полного удаления аддона отключите плагин и вручную удалите `FoxhaGameMultiplayer` из **Project Settings → Autoload**.

## Быстрый старт

Для готового интерфейса дополнительный код не нужен: запустите игру, нажмите **Shift+Tab**, войдите или зарегистрируйтесь, создайте лобби либо введите код. Подтверждение почты и повторная отправка кода доступны прямо в окне. После подтверждения нужно войти с паролем.

Открыть окно из своей кнопки:

```gdscript
func _on_multiplayer_button_pressed() -> void:
    FoxhaGameMultiplayer.open_list()
```

Входящее приглашение автоматически появляется справа сверху со звуком, даже
когда оверлей закрыт. Плашка показывает отправителя (если он есть в списке друзей)
и код лобби. Нажмите **«Принять» / F6** или **«Отклонить» / F7**.
Уведомление не освобождает захваченную игрой мышь: для нажатия кнопок можно открыть
оверлей через Shift+Tab либо использовать горячие клавиши. При нескольких
приглашениях отображается их количество, а после обработки — следующее.
Повторные обновления того же приглашения не воспроизводят звук заново.
Если вы уже в лобби, кнопка называется **«Выйти из лобби и принять»**:
сначала выполняется выход, затем принятие; при ошибке выхода новое подключение
не запускается. Истёкшие и обработанные приглашения исчезают при обновлении
серверного списка. Реализация: [invitation_notifications.gd](invitation_notifications.gd).

Аддон начинает восстанавливать вход сразу при старте игры. Пока идёт начальная проверка, встроенная панель показывает загрузку. Повторно вызывать `initialize()` при каждом открытии окна не нужно.

В native-игре сохраняются только refresh-токен и срок его действия в `user://foxha-session-<hash>.cfg`. Пароль и access-токен на диск не записываются. Файл не зашифрован и содержит учётные данные — не включайте его в сборки или Git. Сессии разделены по адресу API и ID игры. Access-токен обновляется автоматически, а срок всей сессии задаёт сервер. При временной недоступности сервера восстановление повторяется автоматически. `logout()` удаляет сохранённую сессию; после истечения её срока нужен новый вход.

В браузере используется мост страницы игры; аддон не сохраняет refresh-токен в локальный файл. Выход из игровой сессии не означает выход из аккаунта на всём сайте.

## API FoxhaGameMultiplayer

Точка входа — автозагрузка из [game_multiplayer.gd](game_multiplayer.gd).

| Метод | Что делает |
| --- | --- |
| `open_list() -> void` | Открывает оверлей. Повторное открытие безопасно. |
| `close_list() -> void` | Закрывает оверлей и восстанавливает состояние мыши/фокуса. |
| `toggle_list() -> void` | Переключает открытое/закрытое состояние. |
| `is_list_open() -> bool` | Возвращает, открыт ли оверлей. Используйте для блокировки игрового ввода. |
| `set_me(player: Dictionary) -> void` | Меняет отображение собственного профиля. Формат UI-игрока описан ниже. |
| `set_friends(players: Array) -> void` | Заменяет отображаемый список друзей. |
| `set_other(players: Array) -> void` | Заменяет отображаемый список остальных игроков. |

Публичные свойства:

- `client` — экземпляр сетевого клиента, описанного далее.
- `player_list: CanvasLayer` — экземпляр оверлея для настройки его свойств.

Сигнал `action_requested(player: Dictionary, action: String)` сообщает о выборе действия над игроком. `action` равен `"invite"` или `"join"`. Автозагрузка уже отправляет приглашение по `player.id` или присоединяется по `player.roomCode`: в обработчике сигнала **не дублируйте сетевой запрос**. Сигнал подходит, например, для аналитики или звука интерфейса.

Методы `set_me`, `set_friends`, `set_other` меняют только интерфейс: они не авторизуют пользователя, не создают дружбу и не добавляют участника в лобби. Обновления с сервера могут перезаписать отображаемые данные.

## API сетевого клиента

Доступ: `FoxhaGameMultiplayer.client`. Реализация: [network_client.gd](network_client.gd).

### Свойства

Конфигурацию задавайте до инициализации/подключения. Для стандартной автозагрузки используйте Project Settings.

| Свойство | Значение/назначение |
| --- | --- |
| `api_url: String` | По умолчанию `https://games.foxha.ru`. |
| `game_id: String` | UUID игры; по умолчанию пусто. |
| `protocol_version: String` | По умолчанию `"1"`. |
| `allow_local_http: bool` | По умолчанию `false`. Для локальных тестов разрешает HTTP к `localhost`/`127.0.0.1` с портом. Рабочий API использует HTTPS. |
| `ice_transport_policy: String` | `"all"` по умолчанию; `"relay"` — диагностика соединения только через TURN. Задавайте перед созданием/входом в лобби. |

Следующие свойства читайте как состояние клиента, не изменяйте вручную:

| Свойство | Назначение |
| --- | --- |
| `user: Dictionary` | Текущий аккаунт; `{}` означает отсутствие входа. |
| `initializing: bool` | Выполняется начальная проверка сохранённого входа. |
| `lobby: Dictionary` | Текущее лобби; `{}` означает отсутствие лобби. |
| `rtc: WebRTCMultiplayerPeer` | Транспорт текущего подключения или `null`. Само наличие объекта не доказывает соединение с другим игроком. |
| `connection_status: String` | Текст диагностического состояния соединения. |
| `connection_log: Array[String]` | Последние записи диагностики WebRTC, максимум 60. |

### Авторизация

Сетевые методы асинхронные: используйте `await`, если дальнейший код зависит от результата. Методы с результатом `void` не возвращают признак успеха; слушайте сигналы и проверяйте состояние.

| Метод | Результат и поведение |
| --- | --- |
| `initialize() -> void` | Начинает восстановление входа. Автозагрузка вызывает автоматически. Повторный вызов после начала/завершения проверки сразу возвращается, а не ожидает уже запущенную проверку. |
| `authenticate(register: bool, email: String, password: String, display_name := "") -> bool` | `register = false` — вход; `true` — регистрация, `display_name` задаёт ник. Возвращает `true`, если получена авторизованная сессия. |
| `confirm_email(email: String, code: String) -> bool` | Отправляет код из письма; `true` означает подтверждение почты. Сам по себе не выполняет вход: затем вызовите `authenticate(false, ...)`. |
| `resend_code(email: String) -> void` | Повторно запрашивает письмо с кодом; соблюдайте серверный интервал повторной отправки (интерфейс сообщает 60 секунд). |
| `logout() -> void` | Удаляет сохранённую сессию, отправляет запрос выхода, очищает локальный аккаунт и транспорт. При недоступности сервера локальный выход не гарантирует успешный отзыв токена на сервере. |

`authenticate()` может вернуть `false` после **успешной регистрации**, если требуется подтверждение почты. В этом случае приходит `confirmation_required`; покажите форму кода, а не просто сообщение «регистрация не удалась».

### Лобби и соединение

Для создания/входа нужны авторизованный `user`, пустой `lobby` и доступный WebRTC. Перед запросом клиент проверяет транспорт и получает ICE-настройки сервера.

| Метод | Результат и поведение |
| --- | --- |
| `create_lobby(capacity := 20, visibility := "friends") -> bool` | Создаёт лобби и транспорт хоста. Вместимость **2–20**, включая хоста. |
| `join_lobby(code: String) -> bool` | Входит по коду. Краевые пробелы удаляются, код переводится в верхний регистр. Действуют ограничения доступа и версии протокола. |
| `leave_lobby() -> void` | Выходит из лобби и отключает транспорт. Если серверный выход завершился ошибкой, кроме 404, состояние лобби сохраняется для повторной попытки. Проверяйте `lobby.is_empty()`. |
| `reconnect() -> void` | Для гостя: выходит и повторно входит по прежнему коду. Без лобби ничего не делает. Хосту сообщает о необходимости пересоздать лобби. Для закрытого лобби может потребоваться новое приглашение. |

Режимы `visibility`:

| Значение | Кто может войти |
| --- | --- |
| `"code"` | Игрок с кодом лобби. |
| `"friends"` | Друзья хоста или приглашённые игроки. |
| `"invite"` | Приглашённые игроки. |

`true` от `create_lobby()`/`join_lobby()` означает, что лобби принято клиентом и транспорт создан. **Игровое соединение устанавливается позже**. Ожидайте события `MultiplayerAPI`, описанные в разделе подключения мира.

### Приглашения

| Метод | Результат и поведение |
| --- | --- |
| `invite_player(id: String) -> void` | Приглашает аккаунт с указанным UUID. Если своего лобби ещё нет, сначала вызывает `create_lobby()` с параметрами по умолчанию: 20 мест, `"friends"`. |
| `accept_invitation(id: String) -> bool` | Принимает приглашение по **UUID приглашения** и создаёт транспорт. Требует предварительного выхода из текущего лобби. Как и `join_lobby()`, не ожидает готовности всех WebRTC-соединений. |
| `decline_invitation(id: String) -> void` | Отклоняет приглашение по UUID и ускоряет очередное обновление социального списка. |

Приглашения поступают через `social_changed`. Создание/удаление дружбы выполняется на сайте; публичных методов управления дружбой в аддоне пока нет.

## Сигналы клиента

| Сигнал | Когда использовать |
| --- | --- |
| `user_changed(user: Dictionary)` | Обновить профиль/форму входа. Пустой словарь означает отсутствие авторизации. |
| `lobby_changed(lobby: Dictionary)` | Обновить код, участников, доступность кнопок выхода. Пустой словарь означает отсутствие лобби. Не используйте количество участников как количество подключённых игровых peers. |
| `social_changed(data: Dictionary)` | Обновить друзей и приглашения. |
| `confirmation_required` | Показать ввод кода подтверждения почты. Аргументов нет. |
| `message(text: String)` | Показать статус или ошибку пользователю. Это текст, не структурированный код ошибки; не стройте логику на сравнении русских сообщений. |
| `transport_ready(peer: WebRTCMultiplayerPeer)` | Транспорт уже назначен в `multiplayer.multiplayer_peer`. Можно подготовить игровую синхронизацию; соединение с другими peers ещё может устанавливаться. |
| `initialization_changed` | Перечитать `client.initializing` и показать/скрыть начальную загрузку. Аргументов нет. |

Сигналы не воспроизводят прошлые события новому подписчику. В `_ready()` сначала подключайте обработчики, затем отрисуйте текущее состояние из `client.user`, `client.lobby`, `client.initializing`.

## Форматы данных

Имена полей серверных словарей сохраняют **camelCase**. Ниже значения UUID и кодов условные.

### Аккаунт и лобби

```gdscript
# client.user; {} — пользователь не авторизован.
{"id": "user-uuid", "displayName": "Foxha"}

# client.lobby; {} — лобби отсутствует.
{
    "code": "ABC123",
    "gameId": "game-uuid",
    "hostUserId": "host-user-uuid",
    "capacity": 20,
    "visibility": "friends",
    "protocolVersion": "1",
    "members": [
        {"userId": "host-user-uuid", "peerId": 1},
        {"userId": "guest-user-uuid", "peerId": 2}
    ],
    "guestUserId": "guest-user-uuid"
}
```

`guestUserId` — совместимое со старым API поле одного гостя; полный список берите из `members`.

Не смешивайте идентификаторы:

- `userId`/`user.id` — UUID аккаунта, используется для приглашений.
- `peerId` — числовой ID игрового соединения. Хост всегда `1`; у гостя ID может измениться после переподключения и не обязан укладываться в диапазон 1–20.
- `code`/`roomCode` — код лобби, используется для `join_lobby()`.
- `invitation.id` — UUID приглашения, используется для принятия/отклонения.

### Социальные данные

Минимальные поля, используемые интерфейсом из `social_changed(data)`:

```gdscript
{
    "friends": [{
        "id": "friend-user-uuid",
        "displayName": "Друг",
        "presence": {
            "status": "in_game",
            "roomCode": "ABC123",
            "canJoin": true
        }
    }],
    "invitations": [{"id": "invitation-uuid", "roomCode": "ABC123"}]
}
```

Читайте необязательные значения через `get()`: у друга без доступного лобби `roomCode` может отсутствовать или быть `null`. Социальное состояние периодически обновляется самим клиентом; публичный ручной `refresh_friends()` не предусмотрен.

### Данные для set_me/set_friends/set_other

UI использует другой формат:

```gdscript
FoxhaGameMultiplayer.set_other([{
    "id": "user-uuid",
    "nickname": "Игрок",
    "avatar_color": Color.ORANGE,
    "status": "in_game",
    "game": "Моя игра",
    "roomCode": "ABC123",
    "can_join": true
}])
```

`nickname` — подпись, `avatar_color` — цвет аватара с буквой, `status` — `"online"`, `"offline"` или `"in_game"`, `game` — необязательное название игры. `id` нужен для приглашения, `roomCode` — для присоединения. `can_join` передаётся социальным адаптером, но сам по себе не задаёт разрешение на сервере и не управляет доступностью пункта меню в текущей реализации.

## Примеры своего интерфейса

### Наблюдение за состоянием

Пример отдельного скрипта `Node` без зависимостей от конкретных UI-узлов. Вместо `print()` обновляйте свои элементы интерфейса.

```gdscript
extends Node

@onready var client = FoxhaGameMultiplayer.client

func _ready() -> void:
    client.user_changed.connect(_show_user)
    client.lobby_changed.connect(_show_lobby)
    client.initialization_changed.connect(_show_loading)
    client.message.connect(func(text: String): print(text))
    client.confirmation_required.connect(func(): print("Покажите форму кода из письма"))
    _show_user(client.user)
    _show_lobby(client.lobby)
    _show_loading()

func _show_user(user: Dictionary) -> void:
    print("Гость" if user.is_empty() else str(user.get("displayName", "Игрок")))

func _show_lobby(lobby: Dictionary) -> void:
    print("Нет лобби" if lobby.is_empty() else "Код: " + str(lobby.code))

func _show_loading() -> void:
    print("Начальная проверка входа: ", client.initializing)
```

`initializing == false` не гарантирует вход: проверяйте `user`. При сетевой ошибке первая проверка может завершиться, а восстановление продолжится позже автоматически.

### Вход, регистрация и подтверждение

Следующие функции можно добавить в скрипт выше. Передавайте реальные значения из своих полей; не вшивайте пароль в исходники. Пока запрос выполняется, блокируйте повторное нажатие кнопки.

```gdscript
func sign_in(email: String, password: String) -> bool:
    return await client.authenticate(false, email, password)

func register_account(email: String, password: String, nickname: String) -> bool:
    # false также возвращается, если теперь требуется код из письма.
    return await client.authenticate(true, email, password, nickname)

func confirm_account(email: String, code: String) -> bool:
    return await client.confirm_email(email, code)

func send_code_again(email: String) -> void:
    await client.resend_code(email)

func sign_out() -> void:
    await client.logout()
```

Очищайте поле пароля после отправки. После успешного `confirm_account()` снова покажите вход.

### Создание, вход и выход из лобби

Функции для того же скрипта; `busy` защищает от одновременных операций из собственного UI.

```gdscript
var busy := false

func host_game() -> void:
    if busy:
        return
    busy = true
    var ok: bool = await client.create_lobby(20, "code")
    busy = false
    if ok:
        print("Код для друзей: ", client.lobby.code)

func join_game(code: String) -> void:
    if busy:
        return
    busy = true
    var ok: bool = await client.join_lobby(code)
    busy = false
    if ok:
        print("В лобби; ожидаем игровое соединение")

func exit_game() -> void:
    if busy:
        return
    busy = true
    await client.leave_lobby()
    busy = false
    if client.lobby.is_empty():
        print("Можно вернуться в одиночный режим")
```

Вызовы приглашений и переподключения (ID получайте из `social_changed`):

```gdscript
func invite_friend(user_id: String) -> void:
    await client.invite_player(user_id)

func accept_invite(invitation_id: String) -> bool:
    return await client.accept_invitation(invitation_id)

func decline_invite(invitation_id: String) -> void:
    await client.decline_invitation(invitation_id)

func retry_connection() -> void:
    await client.reconnect()
```

## Подключение игрового мира

Аддон реализует аккаунты, лобби, сигналинг и WebRTC-транспорт. Персонажей, RPC, загрузку сцены, авторитет и синхронизацию состояния реализует игра.

Порядок подключения:

1. `create_lobby()`/`join_lobby()`/`accept_invitation()` получает серверное лобби.
2. Клиент создаёт `WebRTCMultiplayerPeer` и назначает `multiplayer.multiplayer_peer`.
3. Приходят `lobby_changed` и `transport_ready`.
4. Обмен SDP/ICE устанавливает соединение; `MultiplayerAPI` сообщает о подключённых peers.
5. Игра создаёт/синхронизирует сетевые объекты.

Хост имеет peer ID `1`. Гости устанавливают WebRTC-соединение с хостом; `SceneMultiplayer` пересылает сообщения между гостями. Выход хоста закрывает лобби, миграции хоста нет. Лимит 20 — настройка текущего приложения/API, а не универсальный предел WebRTC.

Пример наблюдения за транспортом в отдельном `Node`:

```gdscript
extends Node

func _ready() -> void:
    FoxhaGameMultiplayer.client.transport_ready.connect(_on_transport_ready)
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(func(): print("Соединение с хостом готово"))
    multiplayer.connection_failed.connect(func(): print("Соединение не установлено"))
    multiplayer.server_disconnected.connect(func(): print("Хост отключился"))
    # Сцена могла загрузиться уже после создания транспорта.
    if FoxhaGameMultiplayer.client.rtc != null:
        _on_transport_ready(FoxhaGameMultiplayer.client.rtc)
    for peer_id in multiplayer.get_peers():
        _on_peer_connected(peer_id)

func _on_transport_ready(_peer: WebRTCMultiplayerPeer) -> void:
    print("Создан транспорт; локальный peer ID: ", multiplayer.get_unique_id())

func _on_peer_connected(peer_id: int) -> void:
    print("Игровой peer подключён: ", peer_id)
    # Здесь подключите логику спавна/обмена состоянием своей игры.

func _on_peer_disconnected(peer_id: int) -> void:
    print("Игровой peer отключён: ", peer_id)
    # Удалите связанный с peer сетевой объект своей игры.
```

`peer_connected` сообщает об удалённом участнике, не о самом себе. При смене сцены обрабатывайте уже подключённых peers и не создавайте одного персонажа дважды. При выходе следите также за пустым `lobby_changed`: отключение транспорта требует очистки состояния игрового мира.

Готовый 3D-пример: [main.tscn](../../main.tscn), [main.gd](../../main.gd), [player.gd](../../player.gd). Запустите проект на двух устройствах под разными аккаунтами. Пример сохраняет локального персонажа при входе/выходе, создаёт удалённых после подключения и передаёт позиции/повороты через хоста. У демонстрации протокол `playground-3d-1`; у обычного аддона по умолчанию `1`. Расчёт движения в примере выполняет сам игрок, проверки против читов нет.

Не назначайте второй транспорт в тот же `MultiplayerAPI`, пока им управляет аддон. Открытие оверлея не ставит сетевую игру на паузу. При чтении ввода в `_physics_process()` проверяйте `FoxhaGameMultiplayer.is_list_open()`: пропускайте игровой ввод, но продолжайте нужную физику и сетевую обработку.

## Настройка оверлея

`FoxhaGameMultiplayer.player_list` — экземпляр [player_list.tscn](player_list.tscn) со скриптом [player_list.gd](player_list.gd).

| Свойство | Назначение |
| --- | --- |
| `pause_game: bool` | В самостоятельной сцене по умолчанию `true`; автозагрузка устанавливает `false`, чтобы не останавливать сетевую игру. |
| `release_mouse: bool` | По умолчанию `true`: освобождает мышь при открытии и восстанавливает её режим при закрытии. |
| `toggle_with_shift_tab: bool` | По умолчанию `true`; отключите, если используете свою горячую клавишу. |
| `is_open: bool` | Текущее состояние. Для переключения используйте методы, не присваивайте напрямую. |

Публичные методы самого оверлея: `open() -> void`, `close() -> void`, `toggle() -> void`, `set_me(player: Dictionary) -> void`, `set_friends(players: Array) -> void`, `set_other(players: Array) -> void`. Они соответствуют обёрткам автозагрузки. Сигнал `action_requested(player: Dictionary, action: String)` передаёт выбранное действие.

```gdscript
func configure_overlay() -> void:
    FoxhaGameMultiplayer.player_list.toggle_with_shift_tab = false
    FoxhaGameMultiplayer.player_list.release_mouse = true
    FoxhaGameMultiplayer.player_list.pause_game = false
```

Окно закрывается по Esc, перетаскивается за шапку и меняет размер ручкой справа снизу. Базовая ширина — 520, минимум — 260 × 480; размер сохраняется на время запуска. Поиск игроков работает по нику.

Файлы для изменения оформления:

- [overlay_theme.tres](overlay_theme.tres) — тема.
- [player_list.tscn](player_list.tscn) и [player_list.gd](player_list.gd) — каркас окна и списки.
- [session_panel.gd](session_panel.gd) — формы входа, лобби и приглашений.
- [chevron.gd](chevron.gd) — стрелка раскрытия; свойства `opened`, `color`, `thickness` управляют отрисовкой.

`session_panel.gd` предоставляет `attach(target: CanvasLayer, network: ClientScript) -> void`: подключает формы к оверлею и сетевому клиенту. Публичные поля `overlay` и `client` содержат эти ссылки. Автозагрузка уже вызывает `attach()` один раз. Метод рассчитан на структуру штатной сцены, включая `Panel/Margin/Content`; не прикрепляйте вторую панель к тому же окну. Для полностью своего UI достаточно работать с `client` и его сигналами.

Методы, начинающиеся с `_`, — внутренняя реализация и callbacks Godot, не публичный API. Не вызывайте из игры `_request()`, `_enter_lobby()`, `_sync_peers()` и другие внутренние методы. Редакторный [plugin.gd](plugin.gd) подключает настройки/автозагрузку и не предоставляет игровых методов.

## Диагностика и проверки

| Симптом | Что проверить |
| --- | --- |
| «Сетевая игра пока не настроена» | Заполнен ли публичный `game_id`; перезапущена ли игра после изменения настроек. |
| В лобби двое, а в мире один | Лобби отражает членство на сервере. Проверьте `connection_status`, Output с `[Foxha WebRTC]`, события `peer_connected` и логику спавна. |
| `Required virtual method ... must be overridden`, `CH_RELIABLE ... is_null()` | Загружена ли нативная библиотека из `addons/webrtc_native/`, соответствует ли платформа; полностью перезапустите редактор после установки. |
| Соединение между разными сетями не устанавливается | Доступны ли STUN/TURN и их порты. Текущая native-библиотека использует TURN по UDP; наличие только TCP/TLS TURN недостаточно. |
| «Сначала выйдите из текущего лобби» | Вызовите `await client.leave_lobby()` и проверьте пустой `client.lobby`. При ошибке выхода повторите запрос. |
| После восстановления виден код лобби, но нет транспорта | Серверное членство могло сохраниться от предыдущего запуска. Гость может вызвать `reconnect()`, хосту нужно выйти и пересоздать лобби. |
| Несовместимая версия | Сверьте `game_id`, `protocol_version`, RPC и игровые сцены у всех участников. |
| Вход не восстанавливается | Проверьте `initializing`, сигнал `message`, доступность API и срок сессии. Смена API/ID игры создаёт отдельное хранилище авторизации. |

Команды выполняются из корня проекта этого репозитория, где лежит `project.godot`; `godot` — ваш исполняемый файл Godot.

```sh
# Локальный игровой транспорт, без аккаунтов и запросов к API.
godot --headless --path . --script res://tests/main_network_smoke.gd -- --webrtc
# То же для 20 участников.
godot --headless --path . --script res://tests/main_network_smoke.gd -- --webrtc --twenty
# Проверки интерфейса.
godot --headless --path . --script res://tests/overlay_smoke.gd
godot --headless --path . --script res://tests/session_ui_smoke.gd
```

Для WebRTC-проверок нужен `webrtc_native`. Дополнительные проверки находятся в [tests](../../tests).

`tests/network_smoke.gd` запускает восемь native-клиентов против тестового API `http://127.0.0.1:5099`. Требуются переменная окружения `FOXHA_TEST_GAME` с UUID тестовой игры и отключённое подтверждение почты на тестовом API. Тест создаёт аккаунты, поэтому используйте отдельную тестовую БД. Восемь участников в этом тесте не являются лимитом аддона.
