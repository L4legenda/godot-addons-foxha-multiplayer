extends CharacterBody3D
## Базовый прототип персонажа от третьего лица.
## WASD — движение, мышь — поворот камеры, Space — прыжок, Esc — освободить курсор.

const SPEED := 6.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := -1.1
const PITCH_MAX := 0.2

@onready var cam_pivot: Node3D = $CamPivot

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var locally_controlled := true


func _ready() -> void:
	$CamPivot/Camera3D.current = locally_controlled
	set_physics_process(locally_controlled)
	set_process_unhandled_input(locally_controlled)
	if locally_controlled and not FoxhaGameMultiplayer.is_list_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if FoxhaGameMultiplayer.is_list_open():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Мышь влево/вправо вращает персонажа, вверх/вниз — наклон камеры.
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		cam_pivot.rotation.x = clampf(
			cam_pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY,
			PITCH_MIN,
			PITCH_MAX
		)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if is_on_floor() and Input.is_physical_key_pressed(KEY_SPACE) and not FoxhaGameMultiplayer.is_list_open():
		velocity.y = JUMP_VELOCITY

	# X — влево/вправо, Y — вперёд/назад (вперёд это -Z).
	var input_dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if FoxhaGameMultiplayer.is_list_open():
		input_dir = Vector2.ZERO
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
