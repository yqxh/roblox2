--[[
	Main.client.luau
	Client boot: networking, then every controller in dependency order.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

Net.client()

-- We draw our own hotbar and health; keep chat and the player list.
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end)

-- Own the footsteps: retire the default character sound script when it appears.
local player = Players.LocalPlayer
task.spawn(function()
	local scripts = player:WaitForChild("PlayerScripts")
	local existing = scripts:FindFirstChild("RbxCharacterSounds")
	if existing then
		existing:Destroy()
	end
	scripts.ChildAdded:Connect(function(child)
		if child.Name == "RbxCharacterSounds" then
			child:Destroy()
		end
	end)
end)

local ClientRoot = script.Parent

local ClientState = require(ClientRoot:WaitForChild("ClientState"))
ClientState.start()

local controllers = {
	"LightingDirector",
	"SceneryController",
	"AudioController",
	"CameraFX",
	"CharacterFX",
	"PromptTheme",
	"GhostController",
	"EntityFX",
	"ScareDirector",
	"UIController",
}

for _, name in ipairs(controllers) do
	local module = require(ClientRoot:WaitForChild(name))
	if module.start then
		task.spawn(module.start)
	end
end
