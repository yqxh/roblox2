--[[
	UIKit.luau
	The house style: aged ticket-stock panels, brass edges, typewriter
	headers. Small component helpers so UIController reads like layout.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Palette)
local SoundBank = require(Shared.SoundBank)

local UIKit = {}

local player = Players.LocalPlayer

function UIKit.screen(name, props)
	props = props or {}
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = props.ignoreInset ~= false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = props.order or 0
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

function UIKit.frame(props)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = props.color or Palette.UIPanel
	frame.BackgroundTransparency = props.transparency or 0
	frame.BorderSizePixel = 0
	frame.Size = props.size or UDim2.fromScale(1, 1)
	if props.pos then
		frame.Position = props.pos
	end
	if props.anchor then
		frame.AnchorPoint = props.anchor
	end
	if props.corner then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, props.corner)
		corner.Parent = frame
	end
	if props.stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = props.strokeColor or Palette.UIPanelEdge
		stroke.Thickness = props.stroke
		stroke.Transparency = props.strokeTransparency or 0.3
		stroke.Parent = frame
	end
	frame.Visible = props.visible ~= false
	frame.ZIndex = props.z or 1
	frame.ClipsDescendants = props.clip == true
	frame.Parent = props.parent
	return frame
end

function UIKit.label(props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = props.size or UDim2.fromScale(1, 1)
	if props.pos then
		label.Position = props.pos
	end
	if props.anchor then
		label.AnchorPoint = props.anchor
	end
	label.Font = props.font or Palette.FontBody
	label.TextSize = props.textSize or 14
	label.TextColor3 = props.color or Palette.UIPaper
	label.Text = props.text or ""
	label.TextWrapped = props.wrap == true
	label.RichText = props.rich == true
	label.TextXAlignment = props.xalign or Enum.TextXAlignment.Center
	label.TextYAlignment = props.yalign or Enum.TextYAlignment.Center
	label.TextTransparency = props.textTransparency or 0
	label.ZIndex = props.z or 1
	if props.strokeTransparency then
		label.TextStrokeTransparency = props.strokeTransparency
		label.TextStrokeColor3 = props.strokeColor or Color3.new(0, 0, 0)
	end
	if props.scaled then
		label.TextScaled = true
	end
	label.Parent = props.parent
	return label
end

function UIKit.button(props)
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BackgroundColor3 = props.color or Palette.UIPanel
	button.BackgroundTransparency = props.transparency or 0.1
	button.BorderSizePixel = 0
	button.Size = props.size or UDim2.fromOffset(120, 36)
	if props.pos then
		button.Position = props.pos
	end
	if props.anchor then
		button.AnchorPoint = props.anchor
	end
	button.Font = props.font or Palette.FontHeader
	button.TextSize = props.textSize or 16
	button.TextColor3 = props.textColor or Palette.UIPaper
	button.Text = props.text or "?"
	button.ZIndex = props.z or 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, props.corner or 6)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = props.strokeColor or Palette.UIPanelEdge
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = Palette.UIPanelEdge, TextColor3 = Palette.UIInk }):Play()
		SoundBank.play("UiTick", nil, { volumeScale = 0.25 })
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15), {
			BackgroundColor3 = props.color or Palette.UIPanel,
			TextColor3 = props.textColor or Palette.UIPaper,
		}):Play()
	end)
	if props.onClick then
		button.Activated:Connect(function()
			SoundBank.play("UiConfirm", nil, { volumeScale = 0.4 })
			props.onClick(button)
		end)
	end
	button.Parent = props.parent
	return button
end

function UIKit.bar(props)
	local track = UIKit.frame({
		parent = props.parent,
		size = props.size,
		pos = props.pos,
		anchor = props.anchor,
		color = props.bg or Color3.fromRGB(30, 26, 24),
		transparency = props.bgTransparency or 0.25,
		corner = props.corner or 4,
		stroke = props.stroke,
		z = props.z,
	})
	local fill = UIKit.frame({
		parent = track,
		size = UDim2.fromScale(1, 1),
		color = props.color or Palette.UIWarn,
		corner = props.corner or 4,
		z = (props.z or 1) + 1,
	})
	local api = { track = track, fill = fill }
	function api.set(frac, instant)
		frac = math.clamp(frac, 0, 1)
		local target = UDim2.fromScale(frac, 1)
		if instant then
			fill.Size = target
		else
			TweenService:Create(fill, TweenInfo.new(0.2), { Size = target }):Play()
		end
	end
	function api.tint(color)
		fill.BackgroundColor3 = color
	end
	return api
end

-- Four-edge gradient vignette; set(alpha) drives overall strength.
function UIKit.vignette(parent, color, z)
	local holder = UIKit.frame({ parent = parent, transparency = 1, z = z or 5 })
	local edges = {}
	local specs = {
		{ pos = UDim2.fromScale(0.5, 0), anchor = Vector2.new(0.5, 0), size = UDim2.new(1, 0, 0.22, 0), rot = 90 },
		{ pos = UDim2.fromScale(0.5, 1), anchor = Vector2.new(0.5, 1), size = UDim2.new(1, 0, 0.22, 0), rot = -90 },
		{ pos = UDim2.fromScale(0, 0.5), anchor = Vector2.new(0, 0.5), size = UDim2.new(0.18, 0, 1, 0), rot = 0 },
		{ pos = UDim2.fromScale(1, 0.5), anchor = Vector2.new(1, 0.5), size = UDim2.new(0.18, 0, 1, 0), rot = 180 },
	}
	for _, spec in ipairs(specs) do
		local edge = UIKit.frame({
			parent = holder,
			size = spec.size,
			pos = spec.pos,
			anchor = spec.anchor,
			color = color,
			transparency = 1,
			z = z or 5,
		})
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec.rot
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = edge
		table.insert(edges, edge)
	end
	local api = { holder = holder }
	function api.set(alpha)
		for _, edge in ipairs(edges) do
			edge.BackgroundTransparency = 1 - math.clamp(alpha, 0, 1)
		end
	end
	function api.setColor(newColor)
		for _, edge in ipairs(edges) do
			edge.BackgroundColor3 = newColor
		end
	end
	return api
end

function UIKit.vlist(parent, padding)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, padding or 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = parent
	return layout
end

function UIKit.hlist(parent, padding)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, padding or 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = parent
	return layout
end

return UIKit
