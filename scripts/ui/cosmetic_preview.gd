class_name CosmeticPreview
extends Control

var skin: CosmeticData
var loadout: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if skin == null:
		draw_set_transform(Vector2(68, 14), 0, Vector2.ONE * 3.5)
		CosmeticDrawing.archer(self, CosmeticCatalog.equipped(loadout, "archer"), Vector2.ZERO)
		CosmeticDrawing.bow(self, CosmeticCatalog.equipped(loadout, "bow"), Vector2(25, 17), Vector2.RIGHT, 0.25)
		CosmeticDrawing.arrow(self, CosmeticCatalog.equipped(loadout, "arrow"), Vector2(44, 17), 1)
	elif skin.slot == "archer":
		draw_set_transform(Vector2(17, 4), 0, Vector2.ONE * 1.2)
		CosmeticDrawing.archer(self, skin, Vector2.ZERO)
	elif skin.slot == "bow":
		CosmeticDrawing.bow(self, skin, Vector2(28, 42), Vector2.RIGHT, 0.2)
	else:
		draw_set_transform(Vector2(52, 42), 0, Vector2.ONE * 2.3)
		CosmeticDrawing.arrow(self, skin, Vector2.ZERO, 1)
