extends CharacterBody2D

func _unhandled_input(event: InputEvent) -> void:	
	if event is InputEventKey:
		if event.pressed:
			match event.keycode:
				KEY_W:
					position.y -= 1
				KEY_A:
					position.x -= 1
				KEY_S:
					position.y += 1
				KEY_D:
					position.x += 1
