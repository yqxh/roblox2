--[[
	Engineer.luau
	The finale. He has stoked this run since 1913 and sees no reason to
	stop. Crank the coupling release at the tender's rear while he patrols
	the coal; a struck flare buys stunned seconds; the last crank frees
	the cars from the engine — and everyone still in the tender leaps back
	as the gap opens.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)

local Engineer = {}
local ctx

local E = Config.Entities.Engineer
local T = Config.Train

local active = false
local rig = nil
local progress = 0
local staggeredUntil = 0
local usedFlares = {}

function Engineer.init(c)
	ctx = c
end

function Engineer.isActive()
	return active
end

local function tenderCar()
	return T.Cars
end

local function inTender(pos)
	local x0 = (tenderCar() - 1) * T.CarPitch
	return pos.X > x0 - 2 and math.abs(pos.Z) < T.CarWidth and pos.Y > T.FloorY - 6
end

local function buildRig()
	local built = ctx.EntityUtil.buildBiped({
		name = "Engineer",
		height = 8.6,
		coat = Color3.fromRGB(30, 26, 24),
		material = Enum.Material.Leather,
		skin = Color3.fromRGB(70, 60, 56),
		glowEyes = true,
		eyeColor = Palette.FurnaceEmber,
		headTilt = 6,
	})
	built.model:SetAttribute("EntityKind", "Engineer")
	local u = built.unit
	-- the firebox where a heart would go
	local grate = Forge.part({
		parent = built.model, name = "Grate",
		size = Vector3.new(0.9 * u, 1.1 * u, 0.2 * u),
		color = Palette.FurnaceCore, material = Enum.Material.Neon,
		cancollide = false, castshadow = false,
	})
	Forge.light(grate, { color = Palette.FurnaceCore, range = 16, brightness = 1.6, shadows = true, flicker = true })
	-- the shovel
	local haft = Forge.part({
		parent = built.model, name = "Haft",
		size = Vector3.new(0.16 * u, 3 * u, 0.16 * u),
		color = Palette.SnagWood, material = Enum.Material.Wood, cancollide = false,
	})
	local blade = Forge.part({
		parent = built.model, name = "Blade",
		size = Vector3.new(0.9 * u, 0.9 * u, 0.12 * u),
		color = Color3.fromRGB(60, 62, 66), material = Enum.Material.Metal, cancollide = false,
	})
	local baseSetCF = built.setCF
	built.setCF = function(pelvisCF, dt, moveSpeed)
		baseSetCF(pelvisCF, dt, moveSpeed)
		grate.CFrame = built.torso.CFrame * CFrame.new(0, 0.1 * u, -0.56 * u)
		haft.CFrame = built.limbs.ArmR.CFrame * CFrame.new(0.35 * u, -0.6 * u, 0) * CFrame.Angles(math.rad(30), 0, math.rad(-12))
		blade.CFrame = haft.CFrame * CFrame.new(0, -1.55 * u, 0)
	end
	return built
end

----------------------------------------------------------------
-- Brain
----------------------------------------------------------------
local function nearestPrey(fromPos)
	local best, bestDist = nil, math.huge
	for _, player in ipairs(Util.livingPlayers()) do
		local char, _, root = Util.aliveCharacter(player)
		if char and inTender(root.Position) and not ctx.HideSystem.isHidden(player) then
			local dist = (root.Position - fromPos).Magnitude
			if dist < bestDist then
				best, bestDist = player, dist
			end
		end
	end
	return best, bestDist
end

local function checkFlares(pos)
	for _, source in ipairs(ctx.ItemService.lightSources()) do
		if source.kind == "GroundFlare" and source.part and not usedFlares[source.part] then
			if (source.pos - pos).Magnitude < 7 then
				usedFlares[source.part] = true
				staggeredUntil = os.clock() + E.FlareStaggerSeconds
				SoundBank.play("EngineerBellow", pos, { max = 300, pitchScale = 1.3 })
				Net.fireAll(Net.T.Subtitle, { text = "The light offends him. He claws at his eyes.", seconds = 3 })
			end
		end
	end
end

local function brainLoop()
	local meta = ctx.TrainBuilder.carMeta(tenderCar())
	local waypoints = meta and meta.patrol or { CFrame.new((tenderCar() - 1) * T.CarPitch + 20, T.FloorY + 2, 0) }
	local wpIndex = 1
	local pos = waypoints[1].Position
	local lastSwing = 0

	rig = buildRig()
	while active and rig.model.Parent do
		local dt = RunService.Heartbeat:Wait()
		if not active or not rig.model.Parent then
			break
		end
		checkFlares(pos)

		local speed = 0
		local target = nil
		if os.clock() < staggeredUntil then
			-- clawing at the light in his eyes
			rig.setCF(CFrame.lookAt(pos, pos + Vector3.new(math.sin(os.clock() * 9), 0, math.cos(os.clock() * 9))), dt, 12)
			continue
		end

		local prey, dist = nearestPrey(pos)
		if prey then
			local _, _, root = Util.aliveCharacter(prey)
			target = root.Position
			speed = E.ChaseSpeed
			if dist < 3.4 and os.clock() - lastSwing > 1.6 then
				lastSwing = os.clock()
				SoundBank.play("EngineerShovel", pos, { max = 160 })
				ctx.PlayerService.damage(prey, E.Damage, "engineer")
				local char2, hum2, root2 = Util.aliveCharacter(prey)
				if char2 and root2 then
					root2.CFrame = root2.CFrame + Vector3.new(-6, 1, 0)
					if hum2 then
						hum2:ChangeState(Enum.HumanoidStateType.FallingDown)
					end
				end
			end
		else
			target = waypoints[wpIndex].Position
			speed = E.PatrolSpeed
			if (Vector3.new(target.X, 0, target.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 2 then
				wpIndex = wpIndex % #waypoints + 1
				target = waypoints[wpIndex].Position
			end
		end

		local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
		if flat.Magnitude > 0.5 then
			local step = flat.Unit * math.min(speed * dt, flat.Magnitude)
			pos += step
		end
		-- clamp him to the tender
		local x0 = (tenderCar() - 1) * T.CarPitch
		pos = Vector3.new(math.max(pos.X, x0 + 2), T.FloorY + 0.2, math.clamp(pos.Z, -4.2, 4.2))
		local lookTarget = target and Vector3.new(target.X, pos.Y, target.Z) or (pos + Vector3.new(1, 0, 0))
		if (lookTarget - pos).Magnitude < 0.6 then
			lookTarget = pos + Vector3.new(1, 0, 0)
		end
		rig.setCF(CFrame.lookAt(pos + Vector3.new(0, 2.6, 0), lookTarget + Vector3.new(0, 2.6, 0)), dt, speed)

		if os.clock() % 9 < dt then
			SoundBank.play("EngineerBellow", pos, { max = 260 })
		end
	end
end

----------------------------------------------------------------
-- The coupling
----------------------------------------------------------------
local function wireCoupling()
	local meta = ctx.TrainBuilder.carMeta(tenderCar())
	if not (meta and meta.coupling) then
		return
	end
	local housing = meta.coupling
	local prompt = housing:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end
	prompt.Triggered:Connect(function(player)
		if not active or player:GetAttribute("Ghost") or player:GetAttribute("Downed") then
			return
		end
		local char, _, root = Util.aliveCharacter(player)
		if not char or (root.Position - housing.Position).Magnitude > 9 then
			return
		end
		progress = math.min(progress + 1.4, E.CoupleSeconds)
		housing:SetAttribute("CoupleProgress", progress / E.CoupleSeconds)
		SoundBank.play("PryCreak", housing, { pitchScale = 0.8 + progress / E.CoupleSeconds * 0.6 })
		ctx.signals.noiseEvent:fire(player, 0.25, housing.Position)
		if progress >= E.CoupleSeconds then
			Engineer.uncouple()
		else
			Net.fireClient(player, Net.T.Toast, {
				text = ("The pin lifts... %d%%"):format(math.floor(progress / E.CoupleSeconds * 100)),
				tone = "warn",
			})
		end
	end)
end

function Engineer.uncouple()
	if not active then
		return
	end
	active = false

	local x0 = (tenderCar() - 1) * T.CarPitch
	SoundBank.play("Uncouple", Vector3.new(x0, T.FloorY + 2, 0), { max = 500 })
	Net.fireAll(Net.T.Subtitle, { text = "The pin sings free. The engine leaps ahead, hungry for somewhere else.", seconds = 6 })

	-- everyone still in the tender makes the leap back to car 27
	for _, player in ipairs(Players:GetPlayers()) do
		local char, _, root = Util.aliveCharacter(player)
		if char and inTender(root.Position) then
			root.CFrame = CFrame.new(x0 - 8, T.FloorY + 3.5, 0) * CFrame.Angles(0, math.rad(90), 0)
		end
	end

	-- the engine (and its keeper) pull away into the dark
	if rig and rig.model.Parent then
		local model = rig.model
		task.spawn(function()
			local start = os.clock()
			local origin = model:GetPivot()
			SoundBank.play("EngineerBellow", origin.Position, { max = 500, pitchScale = 0.8 })
			while os.clock() - start < 4 do
				local t = os.clock() - start
				model:PivotTo(origin * CFrame.new(t * t * 14, 0, 0))
				task.wait(0.05)
			end
			model:Destroy()
		end)
	end
	local meta = ctx.TrainBuilder.carMeta(tenderCar())
	if meta and meta.model then
		task.delay(1, function()
			-- the tender slides away with the engine
			local model = meta.model
			local start = os.clock()
			local origin = model:GetPivot()
			while os.clock() - start < 6 and model.Parent do
				local t = os.clock() - start
				model:PivotTo(origin * CFrame.new(t * t * 10, 0, 0))
				task.wait(0.05)
			end
		end)
	end

	ctx.GameLoop.victory()
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------
function Engineer.startFinale()
	if active then
		return
	end
	active = true
	progress = 0
	usedFlares = {}
	staggeredUntil = 0

	Net.fireAll(Net.T.Announce, {
		title = "THE TENDER",
		sub = "Crank the coupling release at the rear housing. He will object. Flares blind him.",
		seconds = 8, tone = "warn",
	})
	SoundBank.play("EngineerBellow", ctx.TrainBuilder.carPosition(tenderCar()), { max = 500 })
	wireCoupling()
	task.spawn(brainLoop)
end

function Engineer.stop()
	active = false
	if rig and rig.model then
		rig.model:Destroy()
	end
	rig = nil
	progress = 0
end

return Engineer
