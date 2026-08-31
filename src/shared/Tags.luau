--[[
	Tags.luau
	Every CollectionService tag used across the codebase, in one place.
]]

return {
	CarModel = "T59_Car",            -- each built car Model
	HideSpot = "T59_HideSpot",       -- tuck-away volumes (under seats, lockers, tarps)
	LootContainer = "T59_Loot",      -- suitcases, drawers, crates, sacks
	Window = "T59_Window",           -- window bay models (glass + blind)
	DoorSlide = "T59_Door",          -- vestibule sliding doors
	LampLight = "T59_Lamp",          -- interior lights the Furnace can burst
	SwingLamp = "T59_SwingLamp",     -- hanging fixtures the client sways
	VendingMachine = "T59_Vend",
	NoisyProp = "T59_NoisyProp",     -- the lounge piano and friends
	BoardLever = "T59_BoardLever",
	RoofZone = "T59_RoofZone",       -- volumes marking car roofs
	InteriorZone = "T59_Interior",   -- volumes marking car interiors
	RoofHatch = "T59_RoofHatch",
	EntityRig = "T59_Entity",        -- any hostile rig (clients add local FX)
	CouplingRig = "T59_Coupling",    -- the finale's release lever
	GhostChar = "T59_Ghost",         -- characters currently riding as ghosts
	Pickup = "T59_Pickup",           -- items lying loose in the world
	ThemedPrompt = "T59_Prompt",     -- ProximityPrompts drawn by the custom theme
	Flicker = "T59_Flicker",         -- lights with a client-side candle flicker
	StationModel = "T59_Station",
	EmergencyStrip = "T59_EmStrip",  -- red guide lights that live in tunnels
	Blind = "T59_Blind",             -- window blind prompts
}
