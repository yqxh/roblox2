--[[
	UIController.luau
	Every screen and readout: title card, HUD (health, stamina, noise
	candle, fare, hotbar), subtitles, announcements, toasts, station and
	boarding timers, the pocketwatch timetable, the sleeper meter,
	downed/ghost overlays, endcards, and settings.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Palette = require(Shared.Palette)
local ItemDefs = require(Shared.ItemDefs)
local Util = require(Shared.Util)
local SoundBank = require(Shared.SoundBank)
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local UIController = {}

local player = Players.LocalPlayer

local hud, overlayScreen
local healthBar, staminaBar, noiseFlame, fareLabel, passiveRow
local carLabel, subtitleLabel, subtitleQueue = nil, nil, {}
local announceCard, toastColumn
local stationCard, stationTimerLabel, stationTimerThread
local timetableCard, timetableRows, timetableHideThread
local sleeperCard, sleeperBar
local damageVignette, lowHpVignette, ghostVignette
local downedCard, endCard
local hotbarSlots = {}
local settingsPanel
local scareFrame, scareEyes
local channelBar, channelThread

----------------------------------------------------------------
-- HUD construction
----------------------------------------------------------------
local function buildHealthCluster()
	local cluster = UIKit.frame({
		parent = hud, transparency = 1,
		size = UDim2.fromOffset(240, 84),
		pos = UDim2.new(0, 18, 1, -18),
		anchor = Vector2.new(0, 1),
	})
	UIKit.label({
		parent = cluster, text = "VITALITY",
		font = Palette.FontHeader, textSize = 11, color = Palette.UIPaperDim,
		size = UDim2.fromOffset(100, 12), pos = UDim2.fromOffset(2, 8),
		xalign = Enum.TextXAlignment.Left,
	})
	healthBar = UIKit.bar({
		parent = cluster,
		size = UDim2.new(1, 0, 0, 14),
		pos = UDim2.fromOffset(0, 22),
		color = Palette.UIBlood,
		stroke = 1,
	})
	staminaBar = UIKit.bar({
		parent = cluster,
		size = UDim2.new(0.8, 0, 0, 5),
		pos = UDim2.fromOffset(0, 40),
		color = Color3.fromRGB(200, 186, 150),
	})

	-- the noise candle: a flame that fattens as you get loud
	noiseFlame = UIKit.frame({
		parent = cluster,
		size = UDim2.fromOffset(10, 10),
		pos = UDim2.new(1, -6, 0, 30),
		anchor = Vector2.new(1, 1),
		color = Palette.LampGlow,
		corner = 12,
	})
	UIKit.label({
		parent = cluster, text = "NOISE",
		font = Palette.FontHeader, textSize = 10, color = Palette.UIPaperDim,
		size = UDim2.fromOffset(50, 12), pos = UDim2.new(1, -40, 0, 36),
	})
end

local function buildFareCluster()
	local chip = UIKit.frame({
		parent = hud,
		size = UDim2.fromOffset(170, 64),
		pos = UDim2.new(1, -18, 1, -18),
		anchor = Vector2.new(1, 1),
		color = Palette.UIPanel, transparency = 0.25, corner = 8, stroke = 1,
	})
	fareLabel = UIKit.label({
		parent = chip, text = "0 fare",
		font = Palette.FontHeader, textSize = 20, color = Palette.CarLetters,
		size = UDim2.new(1, -12, 0, 26), pos = UDim2.fromOffset(6, 6),
		xalign = Enum.TextXAlignment.Right,
	})
	passiveRow = UIKit.label({
		parent = chip, text = "",
		font = Palette.FontBody, textSize = 12, color = Palette.UIPaperDim,
		size = UDim2.new(1, -12, 0, 18), pos = UDim2.fromOffset(6, 36),
		xalign = Enum.TextXAlignment.Right,
	})
end

local function buildCarLabel()
	carLabel = UIKit.label({
		parent = hud, text = "",
		font = Palette.FontHeader, textSize = 16, color = Palette.UIPaperDim,
		size = UDim2.fromOffset(340, 22),
		pos = UDim2.new(0.5, 0, 0, 12), anchor = Vector2.new(0.5, 0),
		strokeTransparency = 0.7,
	})
end

local function buildSubtitles()
	subtitleLabel = UIKit.label({
		parent = hud, text = "",
		font = Palette.FontHeader, textSize = 17, color = Palette.UIPaper,
		size = UDim2.new(0.7, 0, 0, 52),
		pos = UDim2.new(0.5, 0, 1, -132), anchor = Vector2.new(0.5, 1),
		wrap = true, strokeTransparency = 0.5,
	})
end

local function buildAnnounce()
	announceCard = UIKit.frame({
		parent = hud, visible = false,
		size = UDim2.fromOffset(520, 92),
		pos = UDim2.new(0.5, 0, 0.16, 0), anchor = Vector2.new(0.5, 0.5),
		color = Palette.UIPanel, transparency = 0.14, corner = 10, stroke = 1.4,
	})
	UIKit.label({
		parent = announceCard, text = "", size = UDim2.new(1, -24, 0, 44),
		pos = UDim2.fromOffset(12, 10),
		font = Palette.FontTitle, textSize = 34, color = Palette.UIPaper,
	}).Name = "Title"
	UIKit.label({
		parent = announceCard, text = "", size = UDim2.new(1, -24, 0, 30),
		pos = UDim2.fromOffset(12, 54),
		font = Palette.FontHeader, textSize = 13, color = Palette.UIPaperDim, wrap = true,
	}).Name = "Sub"
end

local function buildToasts()
	toastColumn = UIKit.frame({
		parent = hud, transparency = 1,
		size = UDim2.fromOffset(300, 300),
		pos = UDim2.new(1, -14, 0.5, 60), anchor = Vector2.new(1, 0.5),
	})
	local layout = UIKit.vlist(toastColumn, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
end

local function buildStationCard()
	stationCard = UIKit.frame({
		parent = hud, visible = false,
		size = UDim2.fromOffset(300, 58),
		pos = UDim2.new(0.5, 0, 0, 44), anchor = Vector2.new(0.5, 0),
		color = Palette.UIPanel, transparency = 0.2, corner = 8, stroke = 1,
	})
	UIKit.label({
		parent = stationCard, text = "", size = UDim2.new(1, 0, 0, 24), pos = UDim2.fromOffset(0, 6),
		font = Palette.FontHeader, textSize = 16, color = Palette.CarLetters,
	}).Name = "Name"
	stationTimerLabel = UIKit.label({
		parent = stationCard, text = "", size = UDim2.new(1, 0, 0, 24), pos = UDim2.fromOffset(0, 28),
		font = Palette.FontTitle, textSize = 22, color = Palette.UIPaper,
	})
end

local function buildTimetable()
	timetableCard = UIKit.frame({
		parent = hud, visible = false,
		size = UDim2.fromOffset(250, 96),
		pos = UDim2.new(1, -14, 0, 90), anchor = Vector2.new(1, 0),
		color = Palette.UIPaper, transparency = 0.08, corner = 6, stroke = 1,
		strokeColor = Palette.UIInk,
	})
	UIKit.label({
		parent = timetableCard, text = "— TIMETABLE —",
		size = UDim2.new(1, 0, 0, 20), pos = UDim2.fromOffset(0, 4),
		font = Palette.FontHeader, textSize = 12, color = Palette.UIInk,
	})
	timetableRows = {}
	for k = 1, 3 do
		timetableRows[k] = UIKit.label({
			parent = timetableCard, text = "",
			size = UDim2.new(1, -16, 0, 20), pos = UDim2.fromOffset(8, 6 + k * 22),
			font = Palette.FontHeader, textSize = 12, color = Palette.UIInk,
			xalign = Enum.TextXAlignment.Left,
		})
	end
end

local function buildSleeperCard()
	sleeperCard = UIKit.frame({
		parent = hud, visible = false,
		size = UDim2.fromOffset(320, 46),
		pos = UDim2.new(0.5, 0, 0, 78), anchor = Vector2.new(0.5, 0),
		color = Palette.UIPanel, transparency = 0.25, corner = 8, stroke = 1,
	})
	UIKit.label({
		parent = sleeperCard, text = "D O   N O T   W A K E   I T",
		size = UDim2.new(1, 0, 0, 20), pos = UDim2.fromOffset(0, 4),
		font = Palette.FontHeader, textSize = 13, color = Palette.UIWarn,
	})
	sleeperBar = UIKit.bar({
		parent = sleeperCard,
		size = UDim2.new(1, -24, 0, 8),
		pos = UDim2.new(0.5, 0, 1, -10), anchor = Vector2.new(0.5, 1),
		color = Palette.UIWarn,
	})
end

local function buildOverlays()
	damageVignette = UIKit.vignette(overlayScreen, Palette.UIBlood, 8)
	lowHpVignette = UIKit.vignette(overlayScreen, Color3.fromRGB(90, 10, 10), 7)
	ghostVignette = UIKit.vignette(overlayScreen, Palette.GhostBlue, 6)

	downedCard = UIKit.frame({
		parent = overlayScreen, visible = false,
		size = UDim2.fromOffset(460, 74),
		pos = UDim2.new(0.5, 0, 0.78, 0), anchor = Vector2.new(0.5, 0.5),
		color = Palette.UIPanel, transparency = 0.2, corner = 10, stroke = 1.4,
		strokeColor = Palette.UIBlood, z = 9,
	})
	UIKit.label({
		parent = downedCard, text = "YOU ARE DOWN",
		size = UDim2.new(1, 0, 0, 30), pos = UDim2.fromOffset(0, 8),
		font = Palette.FontTitle, textSize = 26, color = Palette.UIBlood, z = 9,
	})
	UIKit.label({
		parent = downedCard, text = "A friend can lift you. Bleeding out…",
		size = UDim2.new(1, 0, 0, 22), pos = UDim2.fromOffset(0, 42),
		font = Palette.FontHeader, textSize = 13, color = Palette.UIPaperDim, z = 9,
	}).Name = "Line"

	endCard = UIKit.frame({
		parent = overlayScreen, visible = false,
		size = UDim2.fromScale(1, 1),
		color = Color3.new(0, 0, 0), transparency = 0.35, z = 10,
	})
	UIKit.label({
		parent = endCard, text = "", size = UDim2.new(1, 0, 0, 80),
		pos = UDim2.new(0, 0, 0.3, 0),
		font = Palette.FontTitle, textSize = 64, color = Palette.UIPaper, z = 10,
	}).Name = "Big"
	UIKit.label({
		parent = endCard, text = "", size = UDim2.new(0.7, 0, 0, 90),
		pos = UDim2.new(0.15, 0, 0.45, 0),
		font = Palette.FontHeader, textSize = 16, color = Palette.UIPaperDim, wrap = true, z = 10,
	}).Name = "Detail"

	-- the split second where the night has a face
	scareFrame = UIKit.frame({
		parent = overlayScreen, visible = false,
		color = Color3.new(0, 0, 0), transparency = 0.05, z = 20,
	})
	scareEyes = {}
	for _, off in ipairs({ -0.09, 0.09 }) do
		local eye = UIKit.frame({
			parent = scareFrame,
			size = UDim2.fromOffset(46, 26),
			pos = UDim2.new(0.5 + off, 0, 0.44, 0),
			anchor = Vector2.new(0.5, 0.5),
			color = Color3.fromRGB(222, 214, 196),
			corner = 999, z = 21,
		})
		table.insert(scareEyes, eye)
	end

	-- bandage channel readout
	channelBar = UIKit.frame({
		parent = overlayScreen, visible = false,
		size = UDim2.fromOffset(200, 30),
		pos = UDim2.new(0.5, 0, 0.62, 0), anchor = Vector2.new(0.5, 0.5),
		color = Palette.UIPanel, transparency = 0.25, corner = 8, stroke = 1, z = 6,
	})
	UIKit.label({
		parent = channelBar, text = "wrapping…",
		font = Palette.FontHeader, textSize = 12, color = Palette.UIPaperDim,
		size = UDim2.new(1, 0, 0, 14), pos = UDim2.fromOffset(0, 2), z = 6,
	})
	local track = UIKit.frame({
		parent = channelBar,
		size = UDim2.new(1, -16, 0, 5),
		pos = UDim2.new(0.5, 0, 1, -7), anchor = Vector2.new(0.5, 1),
		color = Color3.fromRGB(50, 46, 42), corner = 3, z = 6,
	})
	local fill = UIKit.frame({
		parent = track, size = UDim2.fromScale(0, 1),
		color = Palette.UIGood, corner = 3, z = 7,
	})
	fill.Name = "Fill"
end

local function showScare()
	SoundBank.play("JumpScare", nil, { volumeScale = 0.9 })
	if ClientState.settings.reduceMotion then
		return
	end
	scareFrame.Visible = true
	scareFrame.Rotation = (math.random() - 0.5) * 10
	for _, eye in ipairs(scareEyes) do
		eye.Size = UDim2.fromOffset(38 + math.random(0, 14), 20 + math.random(0, 12))
		eye.Rotation = (math.random() - 0.5) * 24
	end
	task.delay(0.05, function()
		-- one blink: they were closed, then they weren't
		for _, eye in ipairs(scareEyes) do
			eye.Visible = false
		end
		task.wait(0.04)
		for _, eye in ipairs(scareEyes) do
			eye.Visible = true
		end
	end)
	task.delay(0.24, function()
		scareFrame.Visible = false
	end)
end

local function showChannel(seconds)
	if channelThread then
		pcall(task.cancel, channelThread)
	end
	local fill = channelBar:FindFirstChild("Fill", true)
	channelBar.Visible = true
	channelThread = task.spawn(function()
		local start = os.clock()
		while os.clock() - start < seconds do
			if fill then
				fill.Size = UDim2.fromScale(math.clamp((os.clock() - start) / seconds, 0, 1), 1)
			end
			task.wait(0.05)
		end
		channelBar.Visible = false
	end)
end

----------------------------------------------------------------
-- Hotbar
----------------------------------------------------------------
local SLOT_COUNT = 6

local function buildHotbar()
	local bar = UIKit.frame({
		parent = hud, transparency = 1,
		size = UDim2.fromOffset(SLOT_COUNT * 58, 56),
		pos = UDim2.new(0.5, 0, 1, -16), anchor = Vector2.new(0.5, 1),
	})
	UIKit.hlist(bar, 6)
	for k = 1, SLOT_COUNT do
		local slot = UIKit.frame({
			parent = bar,
			size = UDim2.fromOffset(52, 52),
			color = Palette.UIPanel, transparency = 0.35, corner = 8, stroke = 1,
		})
		local glyph = UIKit.label({
			parent = slot, text = "",
			font = Palette.FontTitle, textSize = 24, color = Palette.UIPaper,
			size = UDim2.fromScale(1, 1),
		})
		UIKit.label({
			parent = slot, text = tostring(k),
			font = Palette.FontBody, textSize = 10, color = Palette.UIPaperDim,
			size = UDim2.fromOffset(12, 12), pos = UDim2.fromOffset(4, 2),
		})
		local fuel = UIKit.bar({
			parent = slot,
			size = UDim2.new(1, -8, 0, 3),
			pos = UDim2.new(0.5, 0, 1, -4), anchor = Vector2.new(0.5, 1),
			color = Palette.UIGood,
		})
		fuel.track.Visible = false
		local button = Instance.new("TextButton")
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Size = UDim2.fromScale(1, 1)
		button.Parent = slot
		hotbarSlots[k] = { frame = slot, glyph = glyph, fuel = fuel, button = button, tool = nil }
	end
end

-- Tools keep the slot they arrived in; nothing shuffles underfoot.
local slotOf = {} -- tool -> slot index

local function currentTools()
	local list = {}
	local char = player.Character
	if char then
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				table.insert(list, tool)
			end
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") then
				table.insert(list, tool)
			end
		end
	end
	return list
end

local function refreshHotbar()
	local tools = currentTools()
	local char = player.Character

	-- drop vanished tools, then seat newcomers in the lowest empty slot
	local present = {}
	for _, tool in ipairs(tools) do
		present[tool] = true
	end
	local used = {}
	for tool, k in pairs(slotOf) do
		if present[tool] then
			used[k] = true
		else
			slotOf[tool] = nil
		end
	end
	for _, tool in ipairs(tools) do
		if not slotOf[tool] then
			for k = 1, SLOT_COUNT do
				if not used[k] then
					slotOf[tool] = k
					used[k] = true
					break
				end
			end
		end
	end
	local bySlot = {}
	for tool, k in pairs(slotOf) do
		bySlot[k] = tool
	end

	for k = 1, SLOT_COUNT do
		local slot = hotbarSlots[k]
		local tool = bySlot[k]
		slot.tool = tool
		if tool then
			local name = tool:GetAttribute("ItemName") or tool.Name
			local def = ItemDefs.get(name)
			slot.glyph.Text = def and def.glyph or "?"
			slot.glyph.TextColor3 = def and def.color or Palette.UIPaper
			local equipped = char ~= nil and tool.Parent == char
			slot.frame.BackgroundTransparency = equipped and 0.05 or 0.35
			slot.frame.BackgroundColor3 = equipped and Color3.fromRGB(44, 38, 30) or Palette.UIPanel
			local fuelMax = tool:GetAttribute("FuelMax")
			if fuelMax then
				slot.fuel.track.Visible = true
				slot.fuel.set((tool:GetAttribute("Fuel") or 0) / fuelMax, true)
			elseif tool:GetAttribute("Lit") then
				slot.fuel.track.Visible = true
				slot.fuel.tint(Color3.fromRGB(255, 90, 60))
				slot.fuel.set(1, true)
			else
				slot.fuel.track.Visible = false
			end
		else
			slot.glyph.Text = ""
			slot.frame.BackgroundTransparency = 0.55
			slot.frame.BackgroundColor3 = Palette.UIPanel
			slot.fuel.track.Visible = false
		end
	end
end

local function equipSlot(k)
	local slot = hotbarSlots[k]
	local tool = slot and slot.tool
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (tool and hum) then
		return
	end
	if tool.Parent == char then
		hum:UnequipTools()
	else
		hum:EquipTool(tool)
	end
end

local function wireHotbar()
	for k = 1, SLOT_COUNT do
		hotbarSlots[k].button.Activated:Connect(function()
			equipSlot(k)
		end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local map = {
			[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
			[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
		}
		local k = map[input.KeyCode]
		if k then
			equipSlot(k)
		end
	end)

	local function watchContainer(container)
		container.ChildAdded:Connect(function(child)
			refreshHotbar()
			if child:IsA("Tool") then
				child.AttributeChanged:Connect(refreshHotbar)
			end
		end)
		container.ChildRemoved:Connect(refreshHotbar)
	end
	local function onCharacter(char)
		watchContainer(char)
		local backpack = player:WaitForChild("Backpack")
		watchContainer(backpack)
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") then
				tool.AttributeChanged:Connect(refreshHotbar)
			end
		end
		refreshHotbar()
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	task.spawn(function()
		while true do
			task.wait(1)
			refreshHotbar() -- fuel bars tick down
		end
	end)
end

----------------------------------------------------------------
-- Subtitles / announcements / toasts
----------------------------------------------------------------
local subtitleShowing = false
local function pumpSubtitles()
	if subtitleShowing then
		return
	end
	local entry = table.remove(subtitleQueue, 1)
	if not entry then
		return
	end
	subtitleShowing = true
	subtitleLabel.Text = entry.text
	subtitleLabel.TextTransparency = 0
	task.delay(entry.seconds or 4, function()
		TweenService:Create(subtitleLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.wait(0.55)
		subtitleShowing = false
		pumpSubtitles()
	end)
end

local function onSubtitle(data)
	if not ClientState.settings.subtitles or type(data) ~= "table" then
		return
	end
	if #subtitleQueue > 3 then
		table.remove(subtitleQueue, 1)
	end
	table.insert(subtitleQueue, { text = data.text or "", seconds = data.seconds })
	pumpSubtitles()
end

local TONE_COLORS = {
	good = Palette.UIGood,
	warn = Palette.UIWarn,
	bad = Palette.UIBlood,
	loot = Palette.CarLetters,
	ghost = Palette.GhostBlue,
	station = Palette.CarLetters,
}

local function onAnnounce(data)
	local title = announceCard:FindFirstChild("Title")
	local sub = announceCard:FindFirstChild("Sub")
	title.Text = data.title or ""
	title.TextColor3 = TONE_COLORS[data.tone] or Palette.UIPaper
	sub.Text = data.sub or ""
	announceCard.Visible = true
	announceCard.Position = UDim2.new(0.5, 0, 0.1, 0)
	TweenService:Create(announceCard, TweenInfo.new(0.35, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, 0, 0.16, 0),
	}):Play()
	SoundBank.play("StationBell", nil, { volumeScale = 0.25 })
	task.delay(data.seconds or 6, function()
		if title.Text == (data.title or "") then
			announceCard.Visible = false
		end
	end)
end

local function onToast(data)
	local toast = UIKit.frame({
		parent = toastColumn,
		size = UDim2.fromOffset(280, 34),
		color = Palette.UIPanel, transparency = 0.2, corner = 6, stroke = 1,
		strokeColor = TONE_COLORS[data.tone] or Palette.UIPanelEdge,
	})
	UIKit.label({
		parent = toast, text = data.text or "",
		font = Palette.FontHeader, textSize = 12,
		color = TONE_COLORS[data.tone] or Palette.UIPaper,
		size = UDim2.new(1, -14, 1, 0), pos = UDim2.fromOffset(7, 0),
		xalign = Enum.TextXAlignment.Left, wrap = true,
	})
	SoundBank.play("Toast", nil, { volumeScale = 0.3 })
	task.delay(4.5, function()
		TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		for _, child in ipairs(toast:GetChildren()) do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			end
		end
		task.wait(0.45)
		toast:Destroy()
	end)
end

----------------------------------------------------------------
-- Station + boarding
----------------------------------------------------------------
local function runStationTimer(seconds, warn)
	if stationTimerThread then
		pcall(task.cancel, stationTimerThread)
	end
	stationTimerThread = task.spawn(function()
		for remaining = seconds, 0, -1 do
			stationTimerLabel.Text = Util.formatClock(remaining)
			stationTimerLabel.TextColor3 = (warn or remaining <= Config.Run.StationWarnSeconds) and Palette.UIWarn or Palette.UIPaper
			task.wait(1)
		end
	end)
end

local function onStationState(data)
	local nameLabel = stationCard:FindFirstChild("Name")
	if data.phase == "approach" then
		stationCard.Visible = true
		nameLabel.Text = "APPROACHING  " .. (data.name or "")
		stationTimerLabel.Text = ""
	elseif data.phase == "open" then
		stationCard.Visible = true
		nameLabel.Text = data.name or ""
		runStationTimer(data.seconds or 60, false)
	elseif data.phase == "warn" then
		stationCard.Visible = true
		nameLabel.Text = (data.name or "") .. "  ·  LAST CALL"
		runStationTimer(data.seconds or 15, true)
	else
		if stationTimerThread then
			pcall(task.cancel, stationTimerThread)
			stationTimerThread = nil
		end
		stationCard.Visible = false
	end
end

local function onBoardingState(data)
	local nameLabel = stationCard:FindFirstChild("Name")
	if data.phase == "count" then
		stationCard.Visible = true
		nameLabel.Text = "DEPARTURE"
		runStationTimer(data.seconds or 30, false)
	elseif data.phase == "departed" or data.phase == "idle" then
		if stationTimerThread then
			pcall(task.cancel, stationTimerThread)
			stationTimerThread = nil
		end
		stationCard.Visible = false
	end
end

----------------------------------------------------------------
-- Timetable + sleeper
----------------------------------------------------------------
local function onTimetableNext(data)
	timetableCard.Visible = true
	for k = 1, 3 do
		local entry = data.entries and data.entries[k]
		if entry then
			local eta = entry.eta and (" · %s"):format(Util.formatClock(entry.eta)) or ""
			timetableRows[k].Text = "• " .. entry.label .. eta
		else
			timetableRows[k].Text = ""
		end
	end
	if timetableHideThread then
		pcall(task.cancel, timetableHideThread)
	end
	timetableHideThread = task.delay(2.5, function()
		timetableCard.Visible = false
	end)
end

local sleeperHideThread = nil
local function onSleeperStage(data)
	if data.stage == "wake" then
		sleeperCard.Visible = true
		sleeperBar.set(1)
		sleeperBar.tint(Palette.UIBlood)
	elseif ClientState.carIndex > 0 then
		sleeperCard.Visible = true
		sleeperBar.set(data.level or 0)
		sleeperBar.tint(data.stage == "panic" and Palette.UIBlood or Palette.UIWarn)
	end
	if sleeperHideThread then
		pcall(task.cancel, sleeperHideThread)
	end
	sleeperHideThread = task.delay(2, function()
		sleeperCard.Visible = false
	end)
end

----------------------------------------------------------------
-- Overlays: damage, low hp, downed, ghost, endcards
----------------------------------------------------------------
local function onDamage()
	damageVignette.set(0.85)
	task.delay(0.1, function()
		local start = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = (os.clock() - start) / 0.7
			if t >= 1 then
				conn:Disconnect()
				damageVignette.set(0)
				return
			end
			damageVignette.set(0.85 * (1 - t))
		end)
	end)
end

local function overlayLoop()
	while true do
		task.wait(0.3)
		local hum = ClientState.localHumanoid()
		local frac = hum and hum.Health / math.max(hum.MaxHealth, 1) or 1
		if ClientState.isDowned() then
			lowHpVignette.set(0.9)
		elseif frac < 0.4 then
			lowHpVignette.set((0.4 - frac) / 0.4 * (0.55 + math.sin(os.clock() * 3) * 0.12))
		else
			lowHpVignette.set(0)
		end
		ghostVignette.set(ClientState.isGhost() and 0.5 or 0)
		downedCard.Visible = ClientState.isDowned()
	end
end

local function showEndCard(victory)
	local big = endCard:FindFirstChild("Big")
	local detail = endCard:FindFirstChild("Detail")
	local best = player:FindFirstChild("leaderstats")
	local bestCar = best and best:FindFirstChild("Best Car")
	local escapes = best and best:FindFirstChild("Escapes")
	big.Text = victory and "DAWN" or "THE LINE KEEPS YOU"
	big.TextColor3 = victory and Palette.CarLetters or Palette.UIBlood
	detail.Text = ("Reached %s   ·   %d fare in hand   ·   best car %s   ·   escapes %s\nThe 11:59 makes its round trip. Board again."):format(
		Util.carLabel(math.max(ClientState.carIndex, 1)),
		player:GetAttribute("Fare") or 0,
		bestCar and tostring(bestCar.Value) or "—",
		escapes and tostring(escapes.Value) or "—"
	)
	endCard.Visible = true
	endCard.BackgroundTransparency = 1
	TweenService:Create(endCard, TweenInfo.new(1.2), { BackgroundTransparency = 0.35 }):Play()
end

----------------------------------------------------------------
-- Title + settings
----------------------------------------------------------------
local function buildTitle()
	local title = UIKit.screen("T59Title", { order = 20 })
	local cover = UIKit.frame({
		parent = title, color = Color3.fromRGB(6, 8, 12), transparency = 0.05,
	})
	UIKit.label({
		parent = cover, text = Config.GameName,
		font = Palette.FontTitle, textSize = 84, color = Palette.UIPaper,
		size = UDim2.new(1, 0, 0, 110), pos = UDim2.new(0, 0, 0.3, 0),
	})
	UIKit.label({
		parent = cover, text = Config.Tagline .. "\nA co-operative night. Keep together. Keep a ticket.",
		font = Palette.FontHeader, textSize = 16, color = Palette.UIPaperDim,
		size = UDim2.new(1, 0, 0, 60), pos = UDim2.new(0, 0, 0.48, 0), wrap = true,
	})
	UIKit.button({
		parent = cover, text = "B O A R D",
		size = UDim2.fromOffset(220, 48),
		pos = UDim2.new(0.5, 0, 0.66, 0), anchor = Vector2.new(0.5, 0.5),
		textSize = 20,
		onClick = function()
			TweenService:Create(cover, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
			for _, child in ipairs(cover:GetDescendants()) do
				if child:IsA("TextLabel") or child:IsA("TextButton") then
					TweenService:Create(child, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
					if child:IsA("TextButton") then
						child.Active = false
					end
				end
			end
			task.delay(0.9, function()
				title:Destroy()
			end)
		end,
	})
end

local function buildSettings()
	UIKit.button({
		parent = hud, text = "MENU",
		size = UDim2.fromOffset(58, 30),
		pos = UDim2.new(0, 14, 0, 14),
		textSize = 12,
		onClick = function()
			settingsPanel.Visible = not settingsPanel.Visible
		end,
	})
	settingsPanel = UIKit.frame({
		parent = hud, visible = false,
		size = UDim2.fromOffset(240, 150),
		pos = UDim2.new(0, 14, 0, 54),
		color = Palette.UIPanel, transparency = 0.1, corner = 8, stroke = 1,
	})
	UIKit.vlist(settingsPanel, 8)
	local function toggleRow(labelText, get, set)
		local row = UIKit.frame({ parent = settingsPanel, size = UDim2.new(1, -16, 0, 30), transparency = 1 })
		UIKit.label({
			parent = row, text = labelText, size = UDim2.new(0.6, 0, 1, 0),
			font = Palette.FontHeader, textSize = 13, xalign = Enum.TextXAlignment.Left,
		})
		local button
		button = UIKit.button({
			parent = row, text = get() and "ON" or "OFF",
			size = UDim2.fromOffset(64, 26),
			pos = UDim2.new(1, 0, 0.5, 0), anchor = Vector2.new(1, 0.5),
			textSize = 12,
			onClick = function()
				set(not get())
				button.Text = get() and "ON" or "OFF"
			end,
		})
	end
	toggleRow("Steady camera", function()
		return ClientState.settings.reduceMotion
	end, function(v)
		ClientState.settings.reduceMotion = v
	end)
	toggleRow("Subtitles", function()
		return ClientState.settings.subtitles
	end, function(v)
		ClientState.settings.subtitles = v
	end)
	toggleRow("Loud world", function()
		return ClientState.settings.ambienceVolume > 0.5
	end, function(v)
		ClientState.settings.ambienceVolume = v and 1 or 0.35
	end)
end

----------------------------------------------------------------
-- Attribute wiring
----------------------------------------------------------------
local function wireAttributes()
	local function refreshFare()
		fareLabel.Text = ("%d fare"):format(player:GetAttribute("Fare") or 0)
	end
	local function refreshPassives()
		local tickets = player:GetAttribute("Item_Ticket") or 0
		local keys = player:GetAttribute("Item_BrassKey") or 0
		local bits = {}
		if tickets > 0 then
			table.insert(bits, ("tickets x%d"):format(tickets))
		end
		if keys > 0 then
			table.insert(bits, ("keys x%d"):format(keys))
		end
		passiveRow.Text = #bits > 0 and table.concat(bits, "   ") or "no papers"
	end
	player:GetAttributeChangedSignal("Fare"):Connect(refreshFare)
	player:GetAttributeChangedSignal("Item_Ticket"):Connect(refreshPassives)
	player:GetAttributeChangedSignal("Item_BrassKey"):Connect(refreshPassives)
	refreshFare()
	refreshPassives()

	task.spawn(function()
		while true do
			task.wait(0.15)
			local hum = ClientState.localHumanoid()
			if hum then
				healthBar.set(hum.Health / math.max(hum.MaxHealth, 1))
			end
			staminaBar.set(ClientState.stamina, true)
			local noise = player:GetAttribute("NoiseLevel") or 0
			local size = 8 + noise * 26
			noiseFlame.Size = UDim2.fromOffset(size, size)
			noiseFlame.BackgroundColor3 = Palette.LampGlow:Lerp(Palette.UIBlood, noise)
		end
	end)
end

----------------------------------------------------------------
-- Start
----------------------------------------------------------------
function UIController.start()
	hud = UIKit.screen("T59HUD", { order = 5 })
	overlayScreen = UIKit.screen("T59Overlay", { order = 15 })

	buildHealthCluster()
	buildFareCluster()
	buildCarLabel()
	buildSubtitles()
	buildAnnounce()
	buildToasts()
	buildStationCard()
	buildTimetable()
	buildSleeperCard()
	buildOverlays()
	buildHotbar()
	wireHotbar()
	buildSettings()
	buildTitle()
	wireAttributes()
	task.spawn(overlayLoop)

	ClientState.signals.carChanged:connect(function(_, label, archetype)
		carLabel.Text = ("%s   —   %s"):format(label or "", string.upper(archetype or ""))
		carLabel.TextTransparency = 0
		task.delay(3, function()
			TweenService:Create(carLabel, TweenInfo.new(1.5), { TextTransparency = 0.6 }):Play()
		end)
	end)

	Net.on(Net.T.Subtitle, onSubtitle)
	Net.on(Net.T.Announce, onAnnounce)
	Net.on(Net.T.Toast, onToast)
	Net.on(Net.T.StationState, onStationState)
	Net.on(Net.T.BoardingState, onBoardingState)
	Net.on(Net.T.TimetableNext, onTimetableNext)
	Net.on(Net.T.SleeperStage, onSleeperStage)
	Net.on(Net.T.Damage, function(data)
		onDamage(data)
		if type(data) == "table" and (data.amount or 0) >= 45 then
			showScare()
		end
	end)
	Net.on(Net.T.ItemState, function(data)
		if type(data) == "table" and type(data.channel) == "number" then
			showChannel(data.channel)
		end
	end)
	local function hookDeath(char)
		local hum = char:WaitForChild("Humanoid", 5)
		if hum then
			hum.Died:Connect(showScare)
		end
	end
	if player.Character then
		task.spawn(hookDeath, player.Character)
	end
	player.CharacterAdded:Connect(function(char)
		task.spawn(hookDeath, char)
	end)
	Net.on(Net.T.ShopResult, function(data)
		if data and data.ok == false and data.reason then
			onToast({ text = "The machine declines: " .. data.reason, tone = "warn" })
		end
	end)
	Net.on(Net.T.HideState, function(data)
		if data.hidden then
			onSubtitle({ text = "Hidden. Jump to slip out.", seconds = 3 })
		end
	end)
	Net.on(Net.T.InspectorState, function(data)
		if data.phase == "warn" then
			-- keep the dread on screen while he approaches
			onSubtitle({ text = "Find a seat. Hold your ticket. Or hide, and hope.", seconds = 6 })
		end
	end)
	Net.on(Net.T.VictoryCine, function()
		showEndCard(true)
	end)
	Net.on(Net.T.DefeatCine, function()
		showEndCard(false)
	end)

	ClientState.signals.runStateChanged:connect(function(state)
		if state == "Lobby" then
			endCard.Visible = false
			stationCard.Visible = false
			announceCard.Visible = false
		end
	end)
end

return UIController
