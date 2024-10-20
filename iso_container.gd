class_name IsoContainer extends Node2D

enum IsoSortType {
	POINT,
	LINE
}

class Segment:
	var start: Vector2
	var end: Vector2
	static func gen(my_start: Vector2, my_end: Vector2):
		var s = Segment.new()
		s.start = my_start
		s.end = my_end
		return s

@onready var iso_sorting_manager: IsoSpriteSortingManager = $"/root/Game/IsoSpriteSortingManager"

@export var is_movable: bool = false
@export var render_below_all: bool = false
@export var sort_type: IsoSortType = IsoSortType.POINT
@export var points_offsets: Array[Vector2] = []
@export var registered: bool = false
# set this to true if you did changed to the first sprite / animated sprite
@export var sprite_changed: bool = false

@export var debug: bool = true
@onready var marker_container = $"Markers"

@export var force_sort: bool = true

var static_dependencies: Array[IsoContainer] = []
var inverse_static_dependencies: Array[IsoContainer] = []
var moving_dependencies: Array[IsoContainer] = []
var visible_static_dependencies: Array[IsoContainer]:
	get:
		if _visible_static_last_refresh_frame < Engine.get_frames_drawn():
			iso_sorting_manager.filter_list_by_visibility(static_dependencies, _visible_static_dependencies)
			_visible_static_last_refresh_frame = Engine.get_frames_drawn()
		return _visible_static_dependencies
	set(value): 
		_visible_static_dependencies = value

var renderer_sorting_order: int:
	get:
		return self.z_index
	set(value):
		print("setting z_index for %s to %s" % [self, value])
		self.z_index = value

var _points: Array[Vector2] = []
var _segments: Array[Segment] = []
var _static_sprites: Array[Sprite2D] = []
var _animated_sprites: Array[AnimatedSprite2D] = []
var cached_bounds: Rect2
var _last_refreshed_frame: int = 0

var _visible_static_dependencies: Array[IsoContainer] = []
var _visible_static_last_refresh_frame: int = 0;

var _old_position: Vector2
var _old_rotation: float
var _old_scale: Vector2

func _ready():
	match points_offsets.size():
		0:
			print("IsoContainer must have at once one point offset")
		1:
			sort_type = IsoSortType.POINT
		_:
			sort_type = IsoSortType.LINE

	set_sprites_to_sort()
	refresh_cache()
	iso_sorting_manager.register_sprite(self)

	if debug:
		var line = Line2D.new()
		marker_container.add_child(line)
		line.default_color = Color(1, 0, 0)  # Rot
		line.width = 2  # Breite der Linie
		line.z_index = 10
		for point_offset in points_offsets:
			line.add_point(point_offset)
		if points_offsets.size() == 1:
			line.add_point(Vector2.ZERO)

func _exit_tree():
	iso_sorting_manager.unregister_sprite(self)

func child_is_visible() -> bool:
	for sprite in _static_sprites + _animated_sprites:
		if sprite.is_visible():
			return true
	return false

func _on_tree_changed(child):
	#print("_on_tree_changed")
	set_sprites_to_sort()

func set_sprites_to_sort():
	_static_sprites = get_Sprite2Ds()
	_animated_sprites = get_AnimatedSprite2Ds()
	if _static_sprites.size() == 0 and _animated_sprites.size() == 0:
		print("IsoContainer must have at least one Sprite2D or AnimatedSprite2D child")

func get_Sprite2Ds() -> Array[Sprite2D]:
	var my_children: Array[Sprite2D]  = []
	for child in get_children():
		#print("child: %s" % [child])
		if child is Sprite2D:
			#print("child: %s is Sprite2D" % [child])
			my_children.append(child)
	return my_children

func get_AnimatedSprite2Ds() -> Array[AnimatedSprite2D]:
	var my_children: Array[AnimatedSprite2D] = []
	for child in get_children():
		#print("child: %s" % [child])
		if child is AnimatedSprite2D:
			#print("child: %s is AnimatedSprite2D" % [child])
			my_children.append(child)
	return my_children

func should_refresh():
	if sprite_changed:
		return true
	if _old_position != global_position:
		return true
	if _old_rotation != rotation:
		return true
	if _old_scale != scale:
		return true
	return false

func check_cache_refresh():
	if is_movable && should_refresh():
		refresh_cache();
		return true;
	return false;

func refresh_cache():
	_old_position = global_position
	_old_rotation = rotation
	_old_scale = scale
	sprite_changed = false
	if _static_sprites.size() > 0 or _animated_sprites.size() > 0:
		cached_bounds = _static_sprites[0].get_rect() if _static_sprites.size() > 0 else _animated_sprites[0].get_rect()
		var pos = global_position
		_points.clear()
		for offset in points_offsets:
			_points.append((offset + pos))
		_segments.clear()
		for i in range(_points.size() - 1):
			_segments.append(Segment.gen(_points[i], _points[i + 1]))
		_last_refreshed_frame = Engine.get_frames_drawn()
		if debug:
			var boundingBox: Line2D = $"BoundingBox"
			boundingBox.clear_points()
			boundingBox.width = 2
			boundingBox.z_index = 15
			boundingBox.default_color = Color(0, 0, 1)
			boundingBox.add_point(cached_bounds.position)
			boundingBox.add_point(cached_bounds.position + Vector2(cached_bounds.size.x, 0))
			boundingBox.add_point(cached_bounds.position + cached_bounds.size)
			boundingBox.add_point(cached_bounds.position + Vector2(0, cached_bounds.size.y))
			boundingBox.closed = true

static func signum(x: float)-> int:
	if x > 0:
		return 1
	elif x < 0:
		return -1
	else:
		return 0

# returns 1 if sprite1 is above sprite2, -1 if sprite1 is below sprite2
static func compare_iso_sorters(sprite1: IsoContainer, sprite2: IsoContainer) -> int:
	if sprite1.sort_type == IsoSortType.POINT and sprite2.sort_type == IsoSortType.POINT:
		return signum(sprite1.as_point().y - sprite2.as_point().y)
	elif sprite1.sort_type == IsoSortType.LINE and sprite2.sort_type == IsoSortType.LINE:
		return compare_line_and_line(sprite1, sprite2)
	elif sprite1.sort_type == IsoSortType.POINT and sprite2.sort_type == IsoSortType.LINE:
		return compare_point_and_line(sprite1.as_point(), sprite2)
	elif sprite1.sort_type == IsoSortType.LINE and sprite2.sort_type == IsoSortType.POINT:
		return -compare_point_and_line(sprite2.as_point(), sprite1)
	else:
		return 0

static func compare_line_and_line(line1: IsoContainer, line2: IsoContainer) -> int:
	var line1_start = line1._points[0]
	var line1_end = line1._points[line1._points.size() - 1]
	var line2_start = line2._points[0]
	var line2_end = line2._points[line2._points.size() - 1]

	var comp1: int = compare_point_and_line(line1_start, line2)
	var comp2: int = compare_point_and_line(line1_end, line2)
	var one_vs_two: int = 42

	if comp1 == comp2:
		one_vs_two = comp1

	var comp3 = compare_point_and_line(line2_start, line1)
	var comp4 = compare_point_and_line(line2_end, line1)
	var two_vs_one: int = 42

	if comp3 == comp4:
		two_vs_one = -comp3

	if one_vs_two != 42 and two_vs_one != 42:
		if one_vs_two == two_vs_one:
			return one_vs_two
		return compare_line_centers(line1, line2)
	elif one_vs_two != 42:
		return one_vs_two
	elif two_vs_one != 42:
		return two_vs_one
	else:
		return compare_line_centers(line1, line2)

# returns 1 if line1 is above line2, -1 if line1 is below line2
static func compare_line_centers(line1: IsoContainer, line2: IsoContainer) -> int:
	return signum(line1.sorting_line_center_height() - line2.sorting_line_center_height())

# returns 1 if line1 is above line2, -1 if line1 is below line2
static func compare_point_and_line(point: Vector2, line: IsoContainer) -> int:
	if line._points.size() > 2:
		return compare_point_with_line_segments(point, line)
	else:
		return compare_point_with_line_segment(point, line)

# returns 1 if point is above line, -1 if point is below line
static func compare_point_with_line_segments(point: Vector2, line: IsoContainer) -> int:
	var closest_point    
	for segment in line._segments:
		var candidate = get_closest_point_on_line_segment(point, segment)
		if candidate != null:
			closest_point = candidate
			break

	if closest_point is Vector2:    
		if closest_point.y > point.y:
			return -1
		return 1
	return compare_point_with_line_segment(point, line)

# returns 1 if point is above line, -1 if point is below line
static func compare_point_with_line_segment(point: Vector2, line: IsoContainer) -> int:
	var line_start = line._points[0]
	var line_end = line._points[line._points.size() - 1]

	if point.y > line_start.y and point.y > line_end.y:
		return 1
	elif point.y < line_start.y and point.y < line_end.y:
		return -1

	var slope = (line_end.y - line_start.y) / (line_end.x - line_start.x)
	var intercept = line_start.y - (slope * line_start.x)
	var y_on_line_for_point = (slope * point.x) + intercept
	if y_on_line_for_point > point.y:
		return -1
	return 1

# returns Vector2 or null if no point found
static func get_closest_point_on_line_segment(point: Vector2, segment: Segment):
	var AP = point - segment.start
	var AB = segment.end - segment.start
	var distance = AP.dot(AB) / AB.length_squared()

	if distance < 0 or distance > 1:
		return null
	else:
		return segment.start + AB * distance

func as_point() -> Vector2:
	if sort_type == IsoSortType.LINE:
		return median_vector(_points)
	else:
		return _points[0]

func median_vector(vectors: Array[Vector2]) -> Vector2:
	var ret = Vector2.ZERO
	for vec in vectors:
		ret += vec
	return ret / vectors.size()

func sorting_line_center_height() -> float:
	if sort_type == IsoSortType.LINE:
		return median_y(_points)
	else:
		print("calling line center height on point type")
		return _points[0].y

func median_y(vectors: Array[Vector2]) -> float:
	var ret :float = 0.0
	for vec in vectors:
		ret += vec.y
	return ret / vectors.size()
