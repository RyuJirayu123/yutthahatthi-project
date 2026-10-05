class_name AIProfile
extends Resource
## How a CPU elephant fights. Arcade uses one per stage (easy → hard), so difficulty
## comes from the stage, not from which elephant the CPU drives.

## Seconds between decisions — lower is faster.
@export_range(0.05, 1.0) var tick := 0.28
## Chance to react to an incoming attack.
@export_range(0.0, 1.0) var block := 0.38
@export_range(0.0, 1.0) var aggr := 0.62
@export_range(0.0, 1.0) var heavy := 0.4
@export_range(0.0, 1.0) var special := 0.6
## Share of close-range attacks that are glaive strikes.
@export_range(0.0, 1.0) var rider := 0.25
