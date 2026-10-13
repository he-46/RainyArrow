class_name DifficultyData
extends Resource

@export var id: String = "normal"
@export var title: String = "普通"
@export var target_health: float = 1.0
@export var boss_health: float = 1.0
@export var score: float = 1.0
@export var health_growth: float = 0.06

func parameters() -> Dictionary:
	return {"target_health": target_health, "boss_health": boss_health, "score": score, "health_growth": health_growth}

func description() -> String:
	return "普通靶血量 ×%s · Boss 血量 ×%s · 得分 ×%s\n新靶每击倒成长 +%d%%基础血量 · 金币沿用普通收益" % [str(target_health), str(boss_health), str(score), roundi(health_growth * 100)]
