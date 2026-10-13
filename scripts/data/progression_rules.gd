class_name ProgressionRules
extends Resource
## Permanent XP thresholds: 100, 250, 450...; one point per gained level.

@export var first_level_score: float = 100.0
@export var extra_score_per_level: float = 50.0
@export var max_level: int = 1000

func threshold(level: int) -> float:
	var steps: float = float(maxi(0, level - 1))
	return steps * first_level_score + steps * maxf(0.0, steps - 1.0) * extra_score_per_level * 0.5

func level_for_score(score: float) -> int:
	var low: int = 1
	var high: int = max_level
	while low < high:
		var middle: int = (low + high + 1) / 2
		if threshold(middle) <= score:
			low = middle
		else:
			high = middle - 1
	return low
