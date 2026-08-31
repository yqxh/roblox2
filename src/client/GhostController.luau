--[[
	GhostController.luau
	Ghosts drift with the train until the next station. This paints them
	(soft blue highlight + name wisp), and gives a ghost their one gift:
	sight. Unopened containers glow faintly through the walls — and the
	uneasy ones glow warning-red — so the dead can scout for the living.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tags = require(Shared.Tags)
local Palette = require(Shared.Palette)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local SoundBank = require(Shared.SoundBank)
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local GhostController = {}

local player = Players.LocalPlayer
local ghostHighlights = {} -- character -> Highlight
local lootHighlights = {}  -- part -> Highlight

----------------------------------------------------------------
-- Ghost characters glow for everyone
----------------------------------------------------------------
local function paintGhost(character)
	if ghostHighlights[character] then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Palette.GhostBlue
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = Palette.GhostBlue
	highlight.OutlineTransparency = 0.35
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	ghostHighlights[character] = highlight

	local owner = Players:GetPlayerFromCharacter(character)
	if owner then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			local gui = Instance.new("BillboardGui")
			gui.Name = "GhostTag"
			gui.Size = UDim2.fromOffset(160, 22)
			gui.StudsOffset = Vector3.new(0, 3.4, 0)
			gui.AlwaysOnTop = false
			gui.Parent = root
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Palette.FontHeader
			label.TextSize = 13
			label.TextColor3 = Palette.GhostBlue
			label.TextTransparency = 0.25
			label.Text = ("ghost of %s"):format(owner.DisplayName)
			label.Parent = gui
		end
	end
end

local function unpaintGhost(character)
	local highlight = ghostHighlights[character]
	if highlight then
		highlight:Destroy()
		ghostHighlights[character] = nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local tag = root and root:FindFirstChild("GhostTag")
	if tag then
		tag:Destroy()
	end
end

----------------------------------------------------------------
-- Dead sight: loot shines through the train for ghosts
----------------------------------------------------------------
local function refreshLootSight()
	local amGhost = ClientState.isGhost()
	if not amGhost then
		for part, highlight in pairs(lootHighlights) do
			highlight:Destroy()
			lootHighlights[part] = nil
		end
		return
	end
	local root = ClientState.localRoot()
	if not root then
		return
	end
	local seen = {}
	for _, prompt in ipairs(CollectionService:GetTagged(Tags.ThemedPrompt)) do
		local id = prompt:GetAttribute("PromptId")
		if type(id) == "string" and id:sub(1, 5) == "loot:" then
			local part = prompt.Parent
			if part and part:IsA("BasePart") and (part.Position - root.Position).Magnitude < 70 then
				seen[part] = true
				if not lootHighlights[part] then
					local highlight = Instance.new("Highlight")
					local uneasy = part:GetAttribute("Uneasy") == true
					highlight.FillTransparency = 1
					highlight.OutlineColor = uneasy and Palette.EmergencyRed or Palette.Brass
					highlight.OutlineTransparency = 0.25
					highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					highlight.Parent = part
					lootHighlights[part] = highlight
				end
			end
		end
	end
	for part, highlight in pairs(lootHighlights) do
		if not seen[part] or not part.Parent then
			highlight:Destroy()
			lootHighlights[part] = nil
		end
	end
end

----------------------------------------------------------------
-- Pings
----------------------------------------------------------------
local function showPing(data)
	if typeof(data.pos) ~= "Vector3" then
		return
	end
	local marker = Forge.part({
		parent = workspace, name = "PingMarker",
		size = Vector3.new(0.5, 0.5, 0.5),
		cf = CFrame.new(data.pos),
		color = data.ghost and Palette.GhostBlue or Palette.UIWarn,
		material = Enum.Material.Neon,
		cancollide = false, canquery = false, castshadow = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 40)
	gui.StudsOffset = Vector3.new(0, 1.4, 0)
	gui.AlwaysOnTop = true
	gui.Parent = marker
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Palette.FontHeader
	label.TextSize = 14
	label.TextColor3 = data.ghost and Palette.GhostBlue or Palette.UIWarn
	label.Text = "* " .. (data.name or "?")
	label.Parent = gui
	SoundBank.play("PingMark", data.pos, { volumeScale = 0.5 })
	task.delay(4, function()
		marker:Destroy()
	end)
end

----------------------------------------------------------------
-- Start
----------------------------------------------------------------
function GhostController.start()
	for _, character in ipairs(CollectionService:GetTagged(Tags.GhostChar)) do
		paintGhost(character)
	end
	CollectionService:GetInstanceAddedSignal(Tags.GhostChar):Connect(paintGhost)
	CollectionService:GetInstanceRemovedSignal(Tags.GhostChar):Connect(unpaintGhost)

	task.spawn(function()
		while true do
			task.wait(0.8)
			refreshLootSight()
		end
	end)

	Net.on(Net.T.Ping, showPing)

	-- ghosts drift: lighter gravity feel via jump power staying default;
	-- their speed is set server-side. Here we just soften the camera.
	player:GetAttributeChangedSignal("Ghost"):Connect(function()
		if player:GetAttribute("Ghost") then
			SoundBank.play("GhostRise", nil, { volumeScale = 0.6 })
		end
	end)
end

return GhostController
