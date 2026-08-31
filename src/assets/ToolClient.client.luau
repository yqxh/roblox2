--[[
	ToolClient.client.luau (template — cloned into every active Tool)
	Translates clicks into intents; the server does the believing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local tool = script.Parent
if not tool:IsA("Tool") then
	return
end

local name = tool:GetAttribute("ItemName") or tool.Name

tool.Activated:Connect(function()
	if name == "Flashlight" or name == "Lantern" then
		Net.fire(Net.T.ToolAction, { tool = name, action = "toggle" })
	elseif name == "Flare" then
		if tool:GetAttribute("Lit") then
			Net.fire(Net.T.ToolAction, { tool = name, action = "throw" })
		else
			Net.fire(Net.T.ToolAction, { tool = name, action = "strike" })
		end
	elseif name == "Bandage" or name == "Tonic" or name == "Battery" or name == "Oil" then
		Net.fire(Net.T.ToolAction, { tool = name, action = "use" })
	end
end)
