extends "res://scripts/game/village_sim.gd"

var worst_tick_us: int = 0
var worst_route_us: int = 0
var route_queries: int = 0


func tick(dt: float) -> void:
	var before: int = Time.get_ticks_usec()
	super.tick(dt)
	worst_tick_us = maxi(worst_tick_us, Time.get_ticks_usec() - before)


func route(start: Vector2i, goal: Vector2i, enemy: bool = false) -> Array[Vector2i]:
	var before: int = Time.get_ticks_usec()
	var found: Array[Vector2i] = super.route(start, goal, enemy)
	route_queries += 1
	worst_route_us = maxi(worst_route_us, Time.get_ticks_usec() - before)
	return found
