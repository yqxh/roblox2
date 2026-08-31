--[[
	PromptTheme.luau
	Custom rendering for every ProximityPrompt: a small brass-and-ink
	card with the key glyph, action text, and a hold-progress bar.
	Works for mouse, gamepad and touch (the card itself is tappable).
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Palette)
local SoundBank = require(Shared.SoundBank)

local PromptTheme = {}

local player = Players.LocalPlayer

local function keyGlyph(prompt)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "TAP"
	end
	local lastInput = UserInputService:GetLastInputType()
	if lastInput == Enum.UserInputType.Gamepad1 then
		return "X"
	end
	local key = prompt.KeyboardKeyCode
	return key ~= Enum.KeyCode.Unknown and key.Name or "E"
end

local function buildGui(prompt)
	local adornee = prompt.Parent
	if not (adornee and (adornee:IsA("BasePart") or adornee:IsA("Model"))) then
		return nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "T59Prompt"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(210, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120 -- visibility already governed by the prompt itself
	gui.Active = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0, 0)
	card.BackgroundColor3 = Palette.UIPanel
	card.BackgroundTransparency = 0.18
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.UIPanelEdge
	stroke.Thickness = 1.2
	stroke.Transparency = 0.35
	stroke.Parent = card

	local keyBox = Instance.new("TextLabel")
	keyBox.BackgroundColor3 = Palette.UIPanelEdge
	keyBox.BackgroundTransparency = 0.15
	keyBox.Size = UDim2.fromOffset(34, 34)
	keyBox.Position = UDim2.new(0, 10, 0.5, 0)
	keyBox.AnchorPoint = Vector2.new(0, 0.5)
	keyBox.Font = Palette.FontBodyBold
	keyBox.TextSize = 16
	keyBox.TextColor3 = Palette.UIInk
	keyBox.Text = keyGlyph(prompt)
	keyBox.Parent = card
	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 6)
	keyCorner.Parent = keyBox

	local action = Instance.new("TextLabel")
	action.BackgroundTransparency = 1
	action.Position = UDim2.new(0, 54, 0, prompt.ObjectText ~= "" and 10 or 0)
	action.Size = UDim2.new(1, -64, 0, prompt.ObjectText ~= "" and 26 or 54)
	action.Font = Palette.FontHeader
	action.TextSize = 17
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.TextColor3 = Palette.UIPaper
	action.TextTruncate = Enum.TextTruncate.AtEnd
	action.Text = prompt.ActionText
	action.Parent = card

	local object
	if prompt.ObjectText ~= "" then
		object = Instance.new("TextLabel")
		object.BackgroundTransparency = 1
		object.Position = UDim2.new(0, 54, 0, 34)
		object.Size = UDim2.new(1, -64, 0, 18)
		object.Font = Palette.FontBody
		object.TextSize = 12
		object.TextXAlignment = Enum.TextXAlignment.Left
		object.TextColor3 = Palette.UIPaperDim
		object.TextTruncate = Enum.TextTruncate.AtEnd
		object.Text = prompt.ObjectText
		object.Parent = card
	end

	local holdBar
	if prompt.HoldDuration > 0 then
		local track = Instance.new("Frame")
		track.BackgroundColor3 = Color3.fromRGB(50, 46, 42)
		track.BorderSizePixel = 0
		track.AnchorPoint = Vector2.new(0.5, 1)
		track.Position = UDim2.new(0.5, 0, 1, -5)
		track.Size = UDim2.new(1, -20, 0, 3)
		track.Parent = card
		holdBar = Instance.new("Frame")
		holdBar.BackgroundColor3 = Palette.UIPanelEdge
		holdBar.BorderSizePixel = 0
		holdBar.Size = UDim2.fromScale(0, 1)
		holdBar.Parent = track
	end

	-- touch / click support
	local tapButton = Instance.new("TextButton")
	tapButton.BackgroundTransparency = 1
	tapButton.Size = UDim2.fromScale(1, 1)
	tapButton.Text = ""
	tapButton.Parent = card
	tapButton.MouseButton1Down:Connect(function()
		prompt:InputHoldBegin()
	end)
	tapButton.MouseButton1Up:Connect(function()
		prompt:InputHoldEnd()
	end)

	TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Back), {
		Size = UDim2.fromScale(1, 1),
	}):Play()

	return {
		gui = gui,
		card = card,
		holdBar = holdBar,
		update = function()
			keyBox.Text = keyGlyph(prompt)
			action.Text = prompt.ActionText
			if object then
				object.Text = prompt.ObjectText
			end
		end,
	}
end

function PromptTheme.start()
	local shown = {}

	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end
		local ui = buildGui(prompt)
		if not ui then
			return
		end
		shown[prompt] = ui
		SoundBank.play("UiTick", nil, { volumeScale = 0.4 })

		local changed = prompt.Changed:Connect(ui.update)
		local hidden
		hidden = prompt.PromptHidden:Connect(function()
			changed:Disconnect()
			hidden:Disconnect()
			local record = shown[prompt]
			shown[prompt] = nil
			if record then
				TweenService:Create(record.card, TweenInfo.new(0.12), { Size = UDim2.fromScale(0, 0) }):Play()
				task.delay(0.14, function()
					record.gui:Destroy()
				end)
			end
		end)
	end)

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local ui = shown[prompt]
		if ui and ui.holdBar then
			ui.holdBar.Size = UDim2.fromScale(0, 1)
			TweenService:Create(ui.holdBar, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), {
				Size = UDim2.fromScale(1, 1),
			}):Play()
		end
	end)

	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local ui = shown[prompt]
		if ui and ui.holdBar then
			TweenService:Create(ui.holdBar, TweenInfo.new(0.12), { Size = UDim2.fromScale(0, 1) }):Play()
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local ui = shown[prompt]
		if ui then
			SoundBank.play("UiConfirm", nil, { volumeScale = 0.35 })
		end
	end)
end

return PromptTheme
