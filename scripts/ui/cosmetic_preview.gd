class_name CosmeticPreview
extends Control

var skin: CosmeticData
var loadout: Dictionary = {}
var preview_clock: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Only the large equipped preview breathes; the nine palette swatches stay still.
	set_process(skin == null)

func _process(delta: float) -> void:
	preview_clock += delta
	queue_redraw()

func _draw() -> void:
	if skin == null:
		draw_set_transform(Vector2(68, 14), 0, Vector2.ONE * 3.5)
		var pose: ArcherPose = ArcherPose.sample(Vector2.RIGHT, true, 0.25, 0, 0.65, 0, 0, preview_clock)
		CosmeticDrawing.archer(self, CosmeticCatalog.equipped(loadout, "archer"), Vector2.ZERO, pose)
		CosmeticDrawing.bow(self, CosmeticCatalog.equipped(loadout, "bow"), ArcherPose.GRIP, pose.direction, pose.tension)
		CosmeticDrawing.nocked_arrow(self, CosmeticCatalog.equipped(loadout, "arrow"), pose.draw_hand, pose.direction)
	elif skin.slot == "archer":
		draw_set_transform(Vector2(17, 4), 0, Vector2.ONE * 1.2)
		CosmeticDrawing.archer(self, skin, Vector2.ZERO)
	elif skin.slot == "bow":
		CosmeticDrawing.bow(self, skin, Vector2(28, 42), Vector2.RIGHT, 0.2)
	else:
		draw_set_transform(Vector2(52, 42), 0, Vector2.ONE * 2.3)
		CosmeticDrawing.arrow(self, skin, Vector2.ZERO, 1)
