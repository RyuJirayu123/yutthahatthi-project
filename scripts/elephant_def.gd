class_name ElephantDef
extends Resource
## One war elephant. Duplicate a .tres in data/elephants to add a new one,
## then add it to Main's roster.

@export var display_name := "พลาย"
@export var name_en := "PHLAI"
@export var tagline := ""
@export var tagline_en := ""
## Hidden on the select screen until arcade mode is cleared.
@export var locked := false

@export_group("Moves")
## Move on the heavy button (G).
@export_enum("rush") var signature: String = "rush"
## Move on the charge button (H) when the power bar is full.
@export_enum("charge3", "storm", "blink", "quake", "blessing", "roar") var ultimate: String = "charge3"

@export_group("Look")
## Skin, lit side.
@export var body := Color("#8f8a8c")
## Skin, far legs / ears / shade.
@export var dark := Color("#6a6466")
## Caparison — the elephant's team colour (HUD, cards).
@export var cloth := Color("#c8191e")
## Ornaments: borders, anklets, headdress.
@export var trim := Color("#e8b33a")
@export var flag := Color("#c8191e")
## Royal regalia: tiered umbrella instead of a flag, a crown on the headdress.
@export var royal := false
## Armoured look (design variant B): scale-armour caparison, forehead plate, capped tusks.
## Off = the ceremonial look (variant A).
@export var armored := false

@export_group("Stats")
@export var hp := 100.0
## Damage multiplier.
@export var power := 1.0
## Walk and jump speed multiplier.
@export var speed := 1.0
## Balance damage multiplier for every hit ("BREAK" on the select screen); also the trunk storm's damage.
@export var rider_skill := 1.0
## Balance: incoming balance damage is divided by this.
@export var steady := 1.0
## Power bar gain multiplier.
@export var charge := 1.0
