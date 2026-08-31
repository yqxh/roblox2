--[[
	ItemDefs.luau
	Data for every carriable item. Geometry builders live in the server's
	ItemService; the client reads this for hotbar labels and shop cards.
]]

local Palette = require(script.Parent.Palette)

local ItemDefs = {}

ItemDefs.Order = {
	"Flashlight", "Lantern", "Flare", "Bandage", "Tonic",
	"Ticket", "Prybar", "Pocketwatch", "Battery", "Oil", "BrassKey",
}

ItemDefs.Items = {
	Flashlight = {
		display = "Torch",
		glyph = "T",
		color = Color3.fromRGB(210, 210, 220),
		desc = "Electric torch. Click to switch. Batteries are not immortal.",
		kind = "tool",
		fuelMax = 100,        -- seconds of light
		fuelName = "battery",
	},
	Lantern = {
		display = "Oil Lantern",
		glyph = "L",
		color = Palette.Brass,
		desc = "Lights the whole compartment. In tunnels, things drink light.",
		kind = "tool",
		fuelMax = 150,
		fuelName = "oil",
	},
	Flare = {
		display = "Flare",
		glyph = "F",
		color = Color3.fromRGB(255, 84, 62),
		desc = "Strike, then throw. Loud, bright, and very interesting to the wrong crowd.",
		kind = "tool",
		consumable = true,
		burnSeconds = 22,
	},
	Bandage = {
		display = "Bandage",
		glyph = "B",
		color = Color3.fromRGB(224, 214, 194),
		desc = "Hold still for a few seconds. Restores 35 health.",
		kind = "tool",
		consumable = true,
		healAmount = 35,
		useSeconds = 3,
	},
	Tonic = {
		display = "Dr. Voss' Tonic",
		glyph = "V",
		color = Color3.fromRGB(120, 200, 140),
		desc = "Full health and quick feet for a spell. Tastes of pennies.",
		kind = "tool",
		consumable = true,
		speedBoost = 4,
		boostSeconds = 8,
	},
	Ticket = {
		display = "Ticket",
		glyph = "№",
		color = Palette.UIPaper,
		desc = "Second class, one way. Be SEATED when the Inspector calls and it will be honored.",
		kind = "passive",
	},
	Prybar = {
		display = "Pry Bar",
		glyph = "P",
		color = Color3.fromRGB(140, 60, 50),
		desc = "Opens jammed doors and nailed crates quickly and quietly-ish.",
		kind = "tool",
		unique = true,
	},
	Pocketwatch = {
		display = "Conductor's Watch",
		glyph = "W",
		color = Palette.Brass,
		desc = "It still keeps the timetable. Hold it to read what comes next. It ticks. Things hear ticks.",
		kind = "tool",
		unique = true,
	},
	Battery = {
		display = "Battery",
		glyph = "+",
		color = Color3.fromRGB(90, 110, 190),
		desc = "Refills a torch.",
		kind = "tool",
		consumable = true,
		refills = "Flashlight",
	},
	Oil = {
		display = "Lamp Oil",
		glyph = "O",
		color = Color3.fromRGB(160, 130, 60),
		desc = "Refills a lantern.",
		kind = "tool",
		consumable = true,
		refills = "Lantern",
	},
	BrassKey = {
		display = "Brass Key",
		glyph = "K",
		color = Palette.Brass,
		desc = "Stamped with a car number. Somebody locked something.",
		kind = "passive",
	},
}

function ItemDefs.get(name)
	return ItemDefs.Items[name]
end

return ItemDefs
