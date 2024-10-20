# IsoSpriteSortingManager.gd
class_name IsoSpriteSortingManager extends Node

var floor_sprite_list: Array[IsoContainer] = []
var static_sprite_list: Array[IsoContainer] = []
var currently_visible_static_sprite_list: Array[IsoContainer] = []
var moveable_sprite_list: Array[IsoContainer] = []
var currently_visible_moveable_sprite_list: Array[IsoContainer] = []

@onready var camera: Camera2D = $"/root/Game/Camera2D"

func _ready():
	pass

func register_sprite(new_sprite: IsoContainer):
	if not new_sprite.registered:
		if new_sprite.render_below_all:
			floor_sprite_list.append(new_sprite)
			_sort_list_simple(floor_sprite_list)
			_set_sort_order_negative(floor_sprite_list)
		else:
			if new_sprite.is_movable:
				moveable_sprite_list.append(new_sprite)
			else:
				static_sprite_list.append(new_sprite)
				_setup_static_dependencies(new_sprite)
		new_sprite.registered = true

func unregister_sprite(sprite_to_remove: IsoContainer):
	if sprite_to_remove.registered:
		if sprite_to_remove.render_below_all:
			floor_sprite_list.erase(sprite_to_remove)
		else:
			if sprite_to_remove.is_movable:
				moveable_sprite_list.erase(sprite_to_remove)
			else:
				static_sprite_list.erase(sprite_to_remove)
				_remove_static_dependencies(sprite_to_remove)
		sprite_to_remove.registered = false

func _setup_static_dependencies(sprite: IsoContainer):
	for other_sprite in static_sprite_list:
		if other_sprite == sprite:
			continue
		var b1 = sprite.cached_bounds
		var b2 = other_sprite.cached_bounds
		print("checking %s and %s intersect" % [sprite, other_sprite])
		if b1.intersects(b2):
			print("%s and %s intersect" % [sprite, other_sprite])
			var compare_result = IsoContainer.compare_iso_sorters(sprite, other_sprite)
			if compare_result == -1:
				other_sprite.static_dependencies.append(sprite)
				sprite.inverse_static_dependencies.append(other_sprite)
			elif compare_result == 1:
				sprite.static_dependencies.append(other_sprite)
				other_sprite.inverse_static_dependencies.append(sprite)

func _remove_static_dependencies(sprite_to_remove: IsoContainer):
	for other_sprite in sprite_to_remove.inverse_static_dependencies:
		other_sprite.static_dependencies.erase(sprite_to_remove)
	sprite_to_remove.inverse_static_dependencies.clear()
	sprite_to_remove.static_dependencies.clear()

func _process(delta):
	_update_sorting()

# TODO
#func _late_process(delta):
#    for sprite in moveable_sprite_list:
#        sprite.late_update_has_changed()

func _update_sorting():
	var invalidated = check_cache_refreshes(moveable_sprite_list)
	var static_changed = filter_list_by_visibility(static_sprite_list, currently_visible_static_sprite_list)
	var moveable_changed = filter_list_by_visibility(moveable_sprite_list, currently_visible_moveable_sprite_list)
	if invalidated or static_changed or moveable_changed:
		_clear_moving_dependencies(currently_visible_static_sprite_list)
		_clear_moving_dependencies(currently_visible_moveable_sprite_list)
		_add_moving_dependencies(currently_visible_moveable_sprite_list, currently_visible_static_sprite_list)
		var sorted_sprites: Array[IsoContainer] = []
		_topological_sort(currently_visible_static_sprite_list, currently_visible_moveable_sprite_list, sorted_sprites)
		_set_sort_order_based_on_list_order(sorted_sprites)

static func check_cache_refreshes(sorters: Array[IsoContainer]) -> bool:
	var invalidated = false
	for sorter in sorters:
		invalidated = sorter.check_cache_refresh() || invalidated
	return invalidated

static func _add_moving_dependencies(moveable_list: Array[IsoContainer], static_list: Array[IsoContainer]):
	for move_sprite1 in moveable_list:
		for static_sprite in static_list:
			if _calculate_bounds_intersection(move_sprite1, static_sprite):
				var compare_result = IsoContainer.compare_iso_sorters(move_sprite1, static_sprite)
				if compare_result == -1:
					static_sprite.moving_dependencies.append(move_sprite1)
				elif compare_result == 1:
					move_sprite1.moving_dependencies.append(static_sprite)
		for move_sprite2 in moveable_list:
			if move_sprite1 == move_sprite2:
				continue
			if _calculate_bounds_intersection(move_sprite1, move_sprite2):
				var compare_result = IsoContainer.compare_iso_sorters(move_sprite1, move_sprite2)
				if compare_result == -1:
					move_sprite2.moving_dependencies.append(move_sprite1)

static func _clear_moving_dependencies(sprites: Array[IsoContainer]):
	for sprite in sprites:
		sprite.moving_dependencies.clear()

static func _calculate_bounds_intersection(sprite: IsoContainer, other_sprite: IsoContainer) -> bool:
	return sprite.cached_bounds.intersects(other_sprite.cached_bounds)

static func _set_sort_order_based_on_list_order(sprite_list: Array[IsoContainer]):
	var order_current = 0
	for sprite in sprite_list:
		sprite.renderer_sorting_order = order_current
		order_current += 2

static func _set_sort_order_negative(sprite_list: Array[IsoContainer]):
	var order = (-sprite_list.size() - 1) * 2
	for sprite in sprite_list:
		sprite.renderer_sorting_order = order
		order += 2

const SORT_RANGE = 80.0
func filter_list_by_visibility(full_list: Array[IsoContainer], destination_list: Array[IsoContainer]) -> bool:
	var original_list = destination_list.duplicate()
	destination_list.clear()
	if camera:
		var camera_pos = camera.global_position
		var camera_bounds = Rect2(camera_pos.x - SORT_RANGE, camera_pos.y - SORT_RANGE, SORT_RANGE * 2, SORT_RANGE * 2)
		for sprite in full_list:
			if sprite.force_sort:
				destination_list.append(sprite)
				sprite.force_sort = false
			elif sprite.cached_bounds.intersects(camera_bounds):
				if sprite.child_is_visible:
					destination_list.append(sprite)
	return original_list != destination_list

static func _sort_list_simple(list: Array[IsoContainer]):
	var compare_callable: Callable = func (a, b):
		return IsoContainer.compare_iso_sorters(a, b)
	list.sort_custom(compare_callable)

static func _topological_sort(static_list: Array[IsoContainer], moveable_list: Array[IsoContainer], sorted_sprites: Array[IsoContainer]):
	var visited = {}
	var all_sprites = static_list + moveable_list

	var i: int = 0
	while i  < 5 :
		var circular_dep_stack: Array[IsoContainer] = []
		var circular_dep_data = {}
		var removedDependency: bool = false;
		for sprite in all_sprites:
			if _topological_sort_remove_circular_dependencies(sprite, circular_dep_stack, circular_dep_data):
				removedDependency = true;
		if !removedDependency: 
			break;

	for sprite in all_sprites:
		visited[sprite] = false

	for sprite in all_sprites:
		if not visited[sprite]:
			_topological_sort_visit(sprite, visited, sorted_sprites)

static func _topological_sort_visit(sprite: IsoContainer, visited: Dictionary, sorted_sprites: Array[IsoContainer]):
	if !visited[sprite]:
		for dep in sprite.moving_dependencies:
			_topological_sort_visit(dep, visited, sorted_sprites)
		for dep in sprite.visible_static_dependencies:
			_topological_sort_visit(dep, visited, sorted_sprites)
		visited[sprite] = true
		sorted_sprites.append(sprite)

static func _topological_sort_remove_circular_dependencies(item: IsoContainer, circular_dep_stack: Array[IsoContainer], circular_dep_data: Dictionary) -> bool:
	circular_dep_stack.append(item)
	var removed_dependency = false

	var id = item.get_instance_id()
	var already_visited = circular_dep_data.has(id)
	if already_visited:
		if circular_dep_data[id]:
			_topological_sort_remove_circular_dependency_from_stack(circular_dep_stack)
			removed_dependency = true
	else:
		circular_dep_data[id] = true

		var dependencies = item.moving_dependencies
		for dep in dependencies:
			if _topological_sort_remove_circular_dependencies(dep, circular_dep_stack, circular_dep_data):
				removed_dependency = true

		dependencies = item.static_dependencies
		for dep in dependencies:
			if _topological_sort_remove_circular_dependencies(dep, circular_dep_stack, circular_dep_data):
				removed_dependency = true

		circular_dep_data[id] = false

	circular_dep_stack.pop_back()
	return removed_dependency

static func _topological_sort_remove_circular_dependency_from_stack(circular_reference_stack: Array[IsoContainer]):
	if circular_reference_stack.size() > 1:
		var starting_sorter = circular_reference_stack[circular_reference_stack.size() - 1]
		var repeat_index = 0
		for i in range(circular_reference_stack.size() - 2, -1, -1):
			var sorter = circular_reference_stack[i]
			if sorter == starting_sorter:
				repeat_index = i
				break

		var weakest_dep_index = -1
		var longest_distance = -INF
		for i in range(repeat_index, circular_reference_stack.size() - 1):
			var sorter1a = circular_reference_stack[i]
			var sorter2a = circular_reference_stack[i + 1]
			if sorter1a.sort_type == IsoContainer.IsoSortType.POINT and sorter2a.sort_type == IsoContainer.IsoSortType.POINT:
				var dist = abs(sorter1a.as_point().x - sorter2a.as_point().x)
				if dist > longest_distance:
					weakest_dep_index = i
					longest_distance = dist

		if weakest_dep_index == -1:
			for i in range(repeat_index, circular_reference_stack.size() - 1):
				var sorter1a = circular_reference_stack[i]
				var sorter2a = circular_reference_stack[i + 1]
				var dist = abs(sorter1a.as_point().x - sorter2a.as_point().x)
				if dist > longest_distance:
					weakest_dep_index = i
					longest_distance = dist

		var sorter1 = circular_reference_stack[weakest_dep_index]
		var sorter2 = circular_reference_stack[weakest_dep_index + 1]
		sorter1.static_dependencies.erase(sorter2)
		sorter1.moving_dependencies.erase(sorter2)
