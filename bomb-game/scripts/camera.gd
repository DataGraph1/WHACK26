class_name HandCamera
extends Control

## The index fingertip, normalized to the mirrored camera preview (0..1).
## Only use hand_position when has_hand is true.
signal hand_position_changed(position: Vector2, has_hand: bool)
signal gesture_changed(value: Gesture, confidence: float)
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

var hand_position: Vector2 = Vector2(-1.0, -1.0)
var has_hand := false
var gesture: Gesture = Gesture.NONE
var gesture_confidence := 0.0

var _camera_extension: CameraServerExtension
var _camera_feed
var _hand_task: MediaPipeHandLandmarker
var _gesture_task: MediaPipeGestureRecognizer
var _models_ready := false
var _frame_pending := false
var _last_frame_ms := 0
var _last_hand_result_ms := 0
var _last_gesture_result_ms := 0

@onready var preview: TextureRect = $TextureRect
@onready var status: Label = $Status
@onready var camera_viewport: SubViewport = $CameraViewport
@onready var camera_texture: TextureRect = $CameraViewport/TextureRect
@onready var cursor_texture: TextureRect = $Cursor

func gesture_name() -> String:
	return GESTURE_NAMES[gesture]


func tracking_context() -> Dictionary:
	var context := {
		"hand_visible": has_hand,
		"gesture": gesture_name(),
		"gesture_confidence": gesture_confidence,
	}
	if has_hand:
		context["hand_position"] = {"x": hand_position.x, "y": hand_position.y}
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
	_try_start_camera()
	_prepare_models()


func _exit_tree() -> void:
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
	_hand_task.initialize(hand_options, MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM)
	_hand_task.result_callback.connect(_on_hand_result)

	var gesture_options := MediaPipeTaskBaseOptions.new()
	gesture_options.delegate = MediaPipeTaskBaseOptions.DELEGATE_CPU
	gesture_options.model_asset_buffer = gesture_bytes
	_gesture_task = MediaPipeGestureRecognizer.new()
	_gesture_task.initialize(gesture_options, MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM)
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
	var request: HTTPRequest = MediaPipeExternalFiles.get_model(model_path)
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
			var material := ShaderMaterial.new()
			material.shader = preload("res://shaders/yuy2_to_rgb.gdshader")
			material.set_shader_parameter("texture_yuy2", yuy2)
			camera_texture.material = material
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
			var material := ShaderMaterial.new()
			material.shader = preload("res://shaders/yuv420_to_rgb.gdshader")
			material.set_shader_parameter("texture_y", y)
			material.set_shader_parameter("texture_uv", uv)
			camera_texture.material = material
			if frame_size.x <= 0 or frame_size.y <= 0:
				return
			camera_texture.texture = ImageTexture.create_from_image(Image.create_empty(frame_size.x, frame_size.y, false, Image.FORMAT_RGB8))
		_:
			_fail("Unsupported camera pixel format")
			return
	if frame_size.x <= 0 or frame_size.y <= 0:
		return
	camera_texture.size = Vector2(frame_size)
	var rotation: float = _camera_feed.feed_transform.get_rotation()
	if camera_texture.flip_h:
		rotation *= -1.0
	var rotated_size := Vector2(frame_size).rotated(rotation)
	camera_texture.rotation = rotation
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
	if result.hand_landmarks.is_empty() or result.hand_landmarks[0].landmarks.size() <= 8:
		if has_hand:
			has_hand = false
			hand_position = Vector2(-1.0, -1.0)
			hand_position_changed.emit(hand_position, false)
		return
	var tip: MediaPipeNormalizedLandmark = result.hand_landmarks[0].landmarks[8]
	hand_position = Vector2(clampf(tip.x, 0.0, 1.0), clampf(tip.y, 0.0, 1.0))
	has_hand = true
	hand_position_changed.emit(hand_position, true)


func _on_hand_position_changed(position: Vector2, has_hand: bool):
	var CURSOR_OFFSET : Vector2 = Vector2(0, -20)
	
	if has_hand:
		cursor_texture.visible = true
		var screen_pos := position * get_viewport().get_visible_rect().size
		cursor_texture.position = screen_pos + CURSOR_OFFSET
	else:
		cursor_texture.visible = false


func _on_gesture_result(result: MediaPipeGestureRecognizerResult, _image: MediaPipeImage, timestamp_ms: int) -> void:
	call_deferred("_apply_gesture_result", result, timestamp_ms)


func _apply_gesture_result(result: MediaPipeGestureRecognizerResult, timestamp_ms: int) -> void:
	if timestamp_ms < _last_gesture_result_ms:
		return
	_last_gesture_result_ms = timestamp_ms
	var next_gesture: Gesture = Gesture.NONE
	var confidence := 0.0
	if not result.gestures.is_empty() and not result.gestures[0].categories.is_empty():
		var category: MediaPipeCategory = result.gestures[0].categories[0]
		next_gesture = GESTURE_BY_NAME.get(category.category_name, Gesture.NONE)
		confidence = category.score
	if next_gesture != gesture:
		gesture = next_gesture
		gesture_confidence = confidence
		gesture_changed.emit(gesture, gesture_confidence)
	else:
		gesture_confidence = confidence


func _clear_tracking() -> void:
	has_hand = false
	hand_position = Vector2(-1.0, -1.0)
	hand_position_changed.emit(hand_position, false)
	gesture = Gesture.NONE
	gesture_confidence = 0.0
	gesture_changed.emit(gesture, gesture_confidence)


func _fail(message: String) -> void:
	status.text = message
	tracking_error.emit(message)
