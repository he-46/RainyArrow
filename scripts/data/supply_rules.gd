class_name SupplyRules
extends Resource

@export var purchases_per_segment: int = 2
@export var draws_per_purchase: int = 1
@export var first_cost: int = 24
@export var cost_growth: float = 1.6

func parameters() -> Dictionary:
	return {"limit": purchases_per_segment, "draws": draws_per_purchase, "first_cost": first_cost, "growth": cost_growth}

static func price(parameters: Dictionary, bought: int) -> int:
	# Stop exponentiation before overflow; the wallet and price share a hard cap.
	var first: float = float(parameters["first_cost"])
	var growth: float = float(parameters["growth"])
	if bought >= log(1000000000.0 / first) / log(growth): return 1000000000
	return mini(1000000000, ceili(first * pow(growth, bought)))

