class_name HandCamera
extends Control

## The right index fingertip drives the cursor; left-hand gestures are commands.
## Legacy hand_position/gesture signals retain their names for existing consumers.
signal hand_position_changed(position: Vector2, has_hand: bool)
signal gesture_changed(value: Gesture, confidence: float)
signal right_hand_position_changed(position: Vector2, visible: bool)
signal left_hand_position_changed(position: Vector2, visible: bool)
signal right_gesture_changed(value: Gesture, confidence: float)
signal left_gesture_changed(value: Gesture, confidence: float)
signal tracking_uncertain(reason: String, context: Dictionary)
signal tracking_error(message: String)

enum Gesture {
	NONE,
	CLOSED_FIST,
	OPEN_PALM,
	POINTING_UP,
	THUMB_DOWN,
	THUMB_UP,
	VICTORY,
	I_LOVE_YOU,
}

const HAND_MODEL := "hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
const GESTURE_MODEL := "gesture_recognizer/gesture_recognizer/float16/latest/gesture_recognizer.task"
const MODEL_CACHE := "user://GDMP"
const FRAME_INTERVAL_MS := 66
const MIN_GESTURE_CONFIDENCE := 0.65
const GESTURE_HOLD_MS := 180
const UNCERTAINTY_COOLDOWN_MS := 8000
const MISSING_POINTER_GRACE_MS := 500
const GESTURE_BY_NAME := {
	"Closed_Fist": Gesture.CLOSED_FIST,
	"Open_Palm": Gesture.OPEN_PALM,
	"Pointing_Up": Gesture.POINTING_UP,
	"Thumb_Down": Gesture.THUMB_DOWN,
	"Thumb_Up": Gesture.THUMB_UP,
	"Victory": Gesture.VICTORY,
	"ILoveYou": Gesture.I_LOVE_YOU,
}
const GESTURE_NAMES := [
	"none", "closed_fist", "open_palm", "pointing_up", "thumb_down",
	"thumb_up", "victory", "i_love_you",
]

var hand_position: Vector2 = Vector2(-1.0, -1.0) # Alias for the right hand.
var has_hand := false # Alias for right_hand_visible.
var gesture: Gesture = Gesture.NONE # Alias for the left-hand command.
var gesture_confidence := 0.0
var right_hand_position := Vector2(-1.0, -1.0)
var left_hand_position := Vector2(-1.0, -1.0)
var right_hand_visible := false
var left_hand_visible := false
var right_gesture: Gesture = Gesture.NONE
var left_gesture: Gesture = Gesture.NONE
var right_gesture_confidence := 0.0
var left_gesture_confidence := 0.0
@export var swap_handedness := false

var _camera_extension: CameraServerExtension
var _camera_feed
var _hand_task: MediaPipeHandLandmarker
var _gesture_task: MediaPipeGestureRecognizer
var _models_ready := false
var _frame_pending := false
var _last_frame_ms := 0
var _last_hand_result_ms := 0
var _last_gesture_result_ms := 0
var _last_right_seen_ms := 0
var _last_uncertainty_ms := -UNCERTAINTY_COOLDOWN_MS
var _gesture_candidate := {"left": Gesture.NONE, "right": Gesture.NONE}
var _gesture_candidate_since := {"left": 0, "right": 0}

@onready var preview: TextureRect = $TextureRect
@onready var status: Label = $Status
@onready var camera_viewport: SubViewport = $CameraViewport
@onready var camera_texture: TextureRect = $CameraViewport/TextureRect
@onready var cursor_texture: TextureRect = $Cursor

func gesture_name() -> String:
	return GESTURE_NAMES[gesture]


func tracking_context() -> Dictionary:
	var context := {
		"hand_visible": right_hand_visible,
		"gesture": gesture_name(),
		"gesture_confidence": left_gesture_confidence,
		"right_hand_visible": right_hand_visible,
		"left_hand_visible": left_hand_visible,
		"left_gesture": gesture_name(),
		"left_gesture_confidence": left_gesture_confidence,
	}
	if right_hand_visible:
		context["hand_position"] = {"x": right_hand_position.x, "y": right_hand_position.y}
		context["right_hand_position"] = context["hand_position"]
	if left_hand_visible:
		context["left_hand_position"] = {"x": left_hand_position.x, "y": left_hand_position.y}
	return context


func _ready() -> void:
	CameraServer.camera_feed_added.connect(_on_camera_feed_added, CONNECT_DEFERRED)
	CameraServer.camera_feed_removed.connect(_on_camera_feed_removed, CONNECT_DEFERRED)
	CameraServer.camera_feeds_updated.connect(_try_start_camera, CONNECT_DEFERRED)
	CameraServer.monitoring_feeds = true
	if OS.get_name() == "Windows":
		_camera_extension = CameraServerExtension.new()
		_camera_extension.permission_result.connect(_on_camera_permission_result, CONNECT_DEFERRED)
		if not _camera_extension.permission_granted():
			_camera_extension.request_permission()
	hand_position_changed.connect(_on_hand_position_changed)
	cursor_texture.visible = false
	var narrator := get_node_or_null("/root/NarratorClient")
	if narrator != null:
		narrator.register_tracking_source(self)
	_try_start_camera()
	_prepare_models()


func _exit_tree() -> void:
	var narrator := get_node_or_null("/root/NarratorClient")
	if narrator != null:
		narrator.unregister_tracking_source(self)
	_stop_camera()
	_hand_task = null
	_gesture_task = null
	_camera_extension = null


func _prepare_models() -> void:
	status.text = "Loading hand tracking models..."
	var hand_bytes: PackedByteArray = await _load_model(HAND_MODEL)
	if hand_bytes.is_empty() or not is_inside_tree():
		_fail("Hand Landmarker model could not be loaded")
		return
	var gesture_bytes: PackedByteArray = await _load_model(GESTURE_MODEL)
	if gesture_bytes.is_empty() or not is_inside_tree():
		_fail("Gesture Recognizer model could not be loaded")
		return

	var hand_options := MediaPipeTaskBaseOptions.new()
	hand_options.delegate = MediaPipeTaskBaseOptions.DELEGATE_CPU
	hand_options.model_asset_buffer = hand_bytes
	_hand_task = MediaPipeHandLandmarker.new()
	_hand_task.initialize(hand_options, MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM, 2)
	_hand_task.result_callback.connect(_on_hand_result)

	var gesture_options := MediaPipeTaskBaseOptions.new()
	gesture_options.delegate = MediaPipeTaskBaseOptions.DELEGATE_CPU
	gesture_options.model_asset_buffer = gesture_bytes
	_gesture_task = MediaPipeGestureRecognizer.new()
	_gesture_task.initialize(gesture_options, MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM, 2)
	_gesture_task.result_callback.connect(_on_gesture_result)
	_models_ready = true
	status.text = "Hand tracking ready" if _camera_feed != null else "Waiting for a camera"


func _load_model(model_path: String) -> PackedByteArray:
	var cache_path := MODEL_CACHE.path_join(model_path)
	if FileAccess.file_exists(cache_path):
		var cached := FileAccess.open(cache_path, FileAccess.READ)
		if cached != null:
			return cached.get_buffer(cached.get_length())
	status.text = "Downloading hand tracking models..."
	var model_loader := get_node_or_null("/root/MediaPipeExternalFiles")
	if model_loader == null:
		return PackedByteArray()
	var request: HTTPRequest = model_loader.get_model(model_path)
	if request == null:
		return PackedByteArray()
	var response: Array = await request.request_completed
	if response.size() != 4 or response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != HTTPClient.RESPONSE_OK:
		return PackedByteArray()
	var bytes: PackedByteArray = response[3]
	if bytes.is_empty():
		return bytes
	var absolute_dir := ProjectSettings.globalize_path(cache_path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		return PackedByteArray()
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if file == null:
		return PackedByteArray()
	file.store_buffer(bytes)
	file.close()
	return bytes


func _on_camera_permission_result(granted: bool) -> void:
	if granted:
		_try_start_camera()
	else:
		_fail("Camera permission denied")


func _on_camera_feed_added(_id: int) -> void:
	_try_start_camera()


func _on_camera_feed_removed(id: int) -> void:
	if _camera_feed != null and _camera_feed.get_id() == id:
		_stop_camera()
		preview.texture = null
		_clear_tracking()
		status.text = "Waiting for a camera"
		_try_start_camera()


func _try_start_camera() -> void:
	if _camera_feed != null:
		return
	for feed in CameraServer.feeds():
		if feed == null:
			continue
		var formats: Array = feed.get_formats()
		if not formats.is_empty() and not feed.set_format(0, {}):
			continue
		_camera_feed = feed
		_camera_feed.format_changed.connect(_on_camera_format_changed, CONNECT_DEFERRED)
		_camera_feed.frame_changed.connect(_on_camera_frame_changed, CONNECT_DEFERRED)
		camera_texture.flip_h = feed.get_position() != CameraFeed.FEED_BACK
		_camera_feed.feed_is_active = true
		_on_camera_format_changed()
		status.text = "Hand tracking ready" if _models_ready else "Loading hand tracking models..."
		return
	status.text = "Waiting for camera permission or a camera feed"


func _stop_camera() -> void:
	if _camera_feed == null:
		return
	_camera_feed.feed_is_active = false
	if _camera_feed.format_changed.is_connected(_on_camera_format_changed):
		_camera_feed.format_changed.disconnect(_on_camera_format_changed)
	if _camera_feed.frame_changed.is_connected(_on_camera_frame_changed):
		_camera_feed.frame_changed.disconnect(_on_camera_frame_changed)
	_camera_feed = null


func _on_camera_format_changed() -> void:
	if _camera_feed == null:
		return
	var frame_size := Vector2i.ZERO
	match _camera_feed.get_datatype():
		CameraFeed.FEED_RGB:
			var rgb := CameraTexture.new()
			rgb.camera_feed_id = _camera_feed.get_id()
			rgb.which_feed = CameraServer.FEED_RGBA_IMAGE
			frame_size = rgb.get_size()
			camera_texture.material = null
			camera_texture.texture = rgb
		CameraFeed.FEED_YCBCR:
			var yuy2 := CameraTexture.new()
			yuy2.camera_feed_id = _camera_feed.get_id()
			yuy2.which_feed = CameraServer.FEED_YCBCR_IMAGE
			frame_size = yuy2.get_size()
			var conversion_material := ShaderMaterial.new()
			conversion_material.shader = preload("res://shaders/yuy2_to_rgb.gdshader")
			conversion_material.set_shader_parameter("texture_yuy2", yuy2)
			camera_texture.material = conversion_material
			if frame_size.x <= 0 or frame_size.y <= 0:
				return
			camera_texture.texture = ImageTexture.create_from_image(Image.create_empty(frame_size.x, frame_size.y, false, Image.FORMAT_RGB8))
		CameraFeed.FEED_YCBCR_SEP:
			var y := CameraTexture.new()
			var uv := CameraTexture.new()
			y.camera_feed_id = _camera_feed.get_id()
			uv.camera_feed_id = _camera_feed.get_id()
			y.which_feed = CameraServer.FEED_Y_IMAGE
			uv.which_feed = CameraServer.FEED_CBCR_IMAGE
			frame_size = y.get_size()
			var conversion_material := ShaderMaterial.new()
			conversion_material.shader = preload("res://shaders/yuv420_to_rgb.gdshader")
			conversion_material.set_shader_parameter("texture_y", y)
			conversion_material.set_shader_parameter("texture_uv", uv)
			camera_texture.material = conversion_material
			if frame_size.x <= 0 or frame_size.y <= 0:
				return
			camera_texture.texture = ImageTexture.create_from_image(Image.create_empty(frame_size.x, frame_size.y, false, Image.FORMAT_RGB8))
		_:
			_fail("Unsupported camera pixel format")
			return
	if frame_size.x <= 0 or frame_size.y <= 0:
		return
	camera_texture.size = Vector2(frame_size)
	var feed_rotation: float = _camera_feed.feed_transform.get_rotation()
	if camera_texture.flip_h:
		feed_rotation *= -1.0
	var rotated_size := Vector2(frame_size).rotated(feed_rotation)
	camera_texture.rotation = feed_rotation
	camera_texture.position = -Vector2(minf(rotated_size.x, 0.0), minf(rotated_size.y, 0.0))
	camera_viewport.size = Vector2i(roundi(absf(rotated_size.x)), roundi(absf(rotated_size.y)))
	preview.texture = camera_viewport.get_texture()


func _on_camera_frame_changed() -> void:
	if preview.texture == null:
		_on_camera_format_changed()
	if not _models_ready or _frame_pending or camera_viewport.size == Vector2i.ZERO:
		return
	var timestamp_ms := Time.get_ticks_msec()
	if timestamp_ms - _last_frame_ms < FRAME_INTERVAL_MS:
		return
	_last_frame_ms = timestamp_ms
	_frame_pending = true
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _camera_feed == null:
		_frame_pending = false
		return
	var frame := camera_viewport.get_texture().get_image()
	if frame == null or frame.is_empty():
		_frame_pending = false
		return
	frame.convert(Image.FORMAT_RGB8)
	var media_image := MediaPipeImage.new()
	media_image.set_image(frame)
	_hand_task.detect_async(media_image, timestamp_ms)
	_gesture_task.recognize_async(media_image, timestamp_ms)
	_frame_pending = false


func _on_hand_result(result: MediaPipeHandLandmarkerResult, _image: MediaPipeImage, timestamp_ms: int) -> void:
	call_deferred("_apply_hand_result", result, timestamp_ms)


func _apply_hand_result(result: MediaPipeHandLandmarkerResult, timestamp_ms: int) -> void:
	if timestamp_ms < _last_hand_result_ms:
		return
	_last_hand_result_ms = timestamp_ms
	var positions := {"left": Vector2(-1.0, -1.0), "right": Vector2(-1.0, -1.0)}
	for i in range(mini(result.hand_landmarks.size(), result.handedness.size())):
		var side := _side_from_categories(result.handedness[i])
		if side.is_empty() or result.hand_landmarks[i].landmarks.size() <= 8:
			continue
		var tip: MediaPipeNormalizedLandmark = result.hand_landmarks[i].landmarks[8]
		positions[side] = Vector2(clampf(tip.x, 0.0, 1.0), clampf(tip.y, 0.0, 1.0))
	_apply_hand_positions(positions, timestamp_ms)


func _apply_hand_positions(positions: Dictionary, timestamp_ms: int) -> void:
	_set_hand_state("right", positions["right"], positions["right"].x >= 0.0, timestamp_ms)
	_set_hand_state("left", positions["left"], positions["left"].x >= 0.0, timestamp_ms)


func _side_from_categories(categories) -> String:
	if categories == null or categories.categories.is_empty():
		return ""
	var category: MediaPipeCategory = categories.categories[0]
	var side: String = category.category_name
	if side.is_empty():
		side = category.display_name
	return _normalise_side(side)


func _normalise_side(label: String) -> String:
	var side := label.to_lower()
	if side != "left" and side != "right":
		return ""
	if swap_handedness:
		return "right" if side == "left" else "left"
	return side


func _set_hand_state(side: String, hand_tip_position: Vector2, hand_is_visible: bool, timestamp_ms: int) -> void:
	if side == "right":
		if hand_is_visible:
			_last_right_seen_ms = timestamp_ms
		if hand_is_visible == right_hand_visible and (not hand_is_visible or hand_tip_position == right_hand_position):
			return
		if not hand_is_visible and right_hand_visible:
			_clear_left_command()
		right_hand_visible = hand_is_visible
		right_hand_position = hand_tip_position
		has_hand = hand_is_visible
		hand_position = hand_tip_position
		right_hand_position_changed.emit(hand_tip_position, hand_is_visible)
		hand_position_changed.emit(hand_tip_position, hand_is_visible)
	else:
		if hand_is_visible == left_hand_visible and (not hand_is_visible or hand_tip_position == left_hand_position):
			return
		left_hand_visible = hand_is_visible
		left_hand_position = hand_tip_position
		left_hand_position_changed.emit(hand_tip_position, hand_is_visible)


func _on_hand_position_changed(hand_tip_position: Vector2, hand_is_visible: bool) -> void:
	const CURSOR_OFFSET := Vector2(0, -20)
	if hand_is_visible:
		cursor_texture.visible = true
		var image_size := preview.size
		var image_origin := preview.position
		if preview.texture != null:
			var texture_size := preview.texture.get_size()
			if texture_size.x > 0 and texture_size.y > 0:
				var scale_factor := minf(preview.size.x / texture_size.x, preview.size.y / texture_size.y)
				image_size = texture_size * scale_factor
				image_origin += (preview.size - image_size) / 2.0
		cursor_texture.position = image_origin + hand_tip_position * image_size + CURSOR_OFFSET
	else:
		cursor_texture.visible = false


func _on_gesture_result(result: MediaPipeGestureRecognizerResult, _image: MediaPipeImage, timestamp_ms: int) -> void:
	call_deferred("_apply_gesture_result", result, timestamp_ms)


func _apply_gesture_result(result: MediaPipeGestureRecognizerResult, timestamp_ms: int) -> void:
	if timestamp_ms < _last_gesture_result_ms:
		return
	_last_gesture_result_ms = timestamp_ms
	var observed := {
		"left": {"gesture": Gesture.NONE, "confidence": 0.0},
		"right": {"gesture": Gesture.NONE, "confidence": 0.0},
	}
	for i in range(mini(result.gestures.size(), result.handedness.size())):
		var side := _side_from_categories(result.handedness[i])
		if side.is_empty() or result.gestures[i].categories.is_empty():
			continue
		var category: MediaPipeCategory = result.gestures[i].categories[0]
		var value: Gesture = GESTURE_BY_NAME.get(category.category_name, Gesture.NONE)
		if value != Gesture.NONE and category.score < MIN_GESTURE_CONFIDENCE:
			if side == "left":
				_emit_uncertain("low_gesture_confidence", {
					"observed_gesture": category.category_name,
					"confidence": category.score,
				})
			continue
		observed[side] = {"gesture": value, "confidence": category.score}
	_apply_gesture_observations(observed, timestamp_ms)


func _apply_gesture_observations(observed: Dictionary, timestamp_ms: int) -> void:
	for side in ["left", "right"]:
		_update_stable_gesture(side, observed[side]["gesture"], observed[side]["confidence"], timestamp_ms)


func _update_stable_gesture(side: String, value: Gesture, confidence: float, timestamp_ms: int) -> void:
	if _gesture_candidate[side] != value:
		_gesture_candidate[side] = value
		_gesture_candidate_since[side] = timestamp_ms
		return
	if timestamp_ms - int(_gesture_candidate_since[side]) < GESTURE_HOLD_MS:
		return
	if side == "left":
		if value != Gesture.NONE and not right_hand_visible:
			if timestamp_ms - _last_right_seen_ms > MISSING_POINTER_GRACE_MS:
				_emit_uncertain("right_hand_missing", {"left_gesture": GESTURE_NAMES[value]})
			return
		left_gesture_confidence = confidence
		gesture_confidence = confidence
		if left_gesture == value:
			return
		left_gesture = value
		gesture = value
		left_gesture_changed.emit(value, confidence)
		gesture_changed.emit(value, confidence)
	else:
		right_gesture_confidence = confidence
		if right_gesture == value:
			return
		right_gesture = value
		right_gesture_changed.emit(value, confidence)


func _emit_uncertain(reason: String, details: Dictionary = {}) -> void:
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_uncertainty_ms < UNCERTAINTY_COOLDOWN_MS:
		return
	_last_uncertainty_ms = now_ms
	var context := tracking_context()
	context.merge(details, true)
	tracking_uncertain.emit(reason, context)
	if is_inside_tree():
		var narrator := get_node_or_null("/root/NarratorClient")
		if narrator != null:
			narrator.report_uncertainty(reason, context)


func _clear_tracking() -> void:
	_set_hand_state("right", Vector2(-1.0, -1.0), false, Time.get_ticks_msec())
	_set_hand_state("left", Vector2(-1.0, -1.0), false, Time.get_ticks_msec())
	_clear_left_command()
	_gesture_candidate["right"] = Gesture.NONE
	_gesture_candidate_since["right"] = 0
	if right_gesture != Gesture.NONE:
		right_gesture = Gesture.NONE
		right_gesture_changed.emit(Gesture.NONE, 0.0)
	right_gesture_confidence = 0.0


func _clear_left_command() -> void:
	_gesture_candidate["left"] = Gesture.NONE
	_gesture_candidate_since["left"] = 0
	if left_gesture != Gesture.NONE:
		left_gesture = Gesture.NONE
		gesture = Gesture.NONE
		left_gesture_changed.emit(Gesture.NONE, 0.0)
		gesture_changed.emit(Gesture.NONE, 0.0)
	left_gesture_confidence = 0.0
	gesture_confidence = 0.0


func _fail(message: String) -> void:
	status.text = message
	tracking_error.emit(message)
