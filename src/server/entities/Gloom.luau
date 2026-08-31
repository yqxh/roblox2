--[[
	Gloom.luau
	Lives in the dark tunnels. It cannot see you; it can see light.
	Douse everything and crouch still, or feed it a thrown flare and run.
	Holding your lantern high in a black tunnel is a form of volunteering.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Forge = require(Shared.Forge)
local Palette = require(Shared.Palette)
local SoundBank = require(Shared.SoundBank)
local Util = require(Shared.Util)
local Tags = require(Shared.Tags)

local Gloom = {}
local ctx

local E = Config.Entities.Gloom
local T = Config.Train

local active = false
local rig = nil
local loopThread = nil

function Gloom.init(c)
	ctx = c
end

function Gloom.isActive()
	return active
end

local function buildRig(position)
	local model = Forge.model("Gloom", ctx.folders.entities)
	local CollectionService = game:GetService("CollectionService")
	CollectionService:AddTag(model, Tags.EntityRig)
	model:SetAttribute("EntityKind", "Gloom")

	local core = Forge.ball({
		parent = model, name = "Core",
		size = Vector3.new(3.4, 3.8, 3.4),
		cf = CFrame.new(position),
		color = Palette.GloomBody, material = Enum.Material.SmoothPlastic,
		transparency = 0.25, cancollide = false, castshadow = false,
	})
	local att = Forge.attach(core, CFrame.new())
	Forge.particles(att, {
		color = ColorSequence.new(Color3.fromRGB(6, 6, 10)),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 5) }),
		transparency = NumberSequence.new(0.35, 1),
		lifetime = NumberRange.new(0.8, 1.6),
		rate = 36,
		speed = NumberRange.new(0.5, 2),
		spread = Vector2.new(180, 180),
	})
	-- a ring of pale eyes that watch nothing in particular
	for k = 1, 4 do
		local eye = Forge.part({
			parent = model, name = "Eye",
			size = Vector3.new(0.18, 0.12, 0.12),
			cf = CFrame.new(position),
			color = Color3.fromRGB(200, 210, 230), material = Enum.Material.Neon,
			cancollide = false, castshadow = false,
		})
		eye:SetAttribute("Ring", k)
	end
	return { model = model, core = core }
end

local function sourcesOnTrain()
	local list = {}
	for _, source in ipairs(ctx.ItemService.lightSources()) do
		local pos = source.pos
		if math.abs(pos.Z) < T.CarWidth and pos.Y > T.FloorY - 6 and pos.Y < T.FloorY + T.CarHeight + 6 then
			local car = math.floor(pos.X / T.CarPitch) + 1
			if car >= ctx.TrainBuilder.rearMostBuilt() and car <= ctx.TrainBuilder.frontMostBuilt() then
				table.insert(list, source)
			end
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.pos.X > b.pos.X
	end)
	return list
end

local function hunt()
	local grazed = {}
	local pos = Vector3.new((ctx.TrainBuilder.frontMostBuilt()) * T.CarPitch, T.FloorY + 3, 0)
	rig = buildRig(pos)
	local satiatedUntil = 0

	while active and rig.model.Parent do
		local dt = task.wait(0.1)
		local eyesPhase = os.clock() * 1.3
		for _, part in ipairs(rig.model:GetChildren()) do
			if part.Name == "Eye" then
				local k = part:GetAttribute("Ring") or 1
				part.CFrame = CFrame.new(pos) * CFrame.Angles(0, eyesPhase + k * 1.57, 0) * CFrame.new(0, math.sin(eyesPhase + k) * 0.4, 1.5)
			end
		end

		if os.clock() < satiatedUntil then
			rig.core.CFrame = CFrame.new(pos)
			continue
		end

		local sources = sourcesOnTrain()
		local target = sources[1]
		if target then
			local delta = target.pos - pos
			local dist = delta.Magnitude
			if dist < 3.2 then
				-- feeding time
				if target.kind == "GroundFlare" then
					SoundBank.play("GloomFeed", pos)
					ctx.ItemService.extinguish(target)
					satiatedUntil = os.clock() + 5
				elseif target.player then
					ctx.PlayerService.damage(target.player, E.SourceDamage, "gloom")
					Net.fireClient(target.player, Net.T.Subtitle, { text = "It drank the light out of your hands, and some of you with it.", seconds = 4 })
					SoundBank.play("GloomFeed", pos)
					ctx.ItemService.extinguish(target)
					satiatedUntil = os.clock() + 2.5
				end
			else
				pos += delta.Unit * math.min(E.HuntSpeed * dt, dist)
			end
		else
			-- blind drift toward the rear of the train
			local rearX = (ctx.TrainBuilder.rearMostBuilt() - 1) * T.CarPitch + 6
			if pos.X > rearX then
				pos += Vector3.new(-E.DriftSpeed * dt, math.sin(os.clock()) * 0.02, 0)
			else
				pos = Vector3.new((ctx.TrainBuilder.frontMostBuilt()) * T.CarPitch, T.FloorY + 3, 0)
			end
			-- brush past the noisy and the upright
			for _, player in ipairs(Util.livingPlayers()) do
				if not grazed[player] then
					local char, _, root = Util.aliveCharacter(player)
					if char and (root.Position - pos).Magnitude < 4.5 then
						local vel = root.AssemblyLinearVelocity
						local moving = Vector3.new(vel.X, 0, vel.Z).Magnitude > 3
						local standing = player:GetAttribute("Stance") ~= "crouch"
							and not (player:GetAttribute("HiddenSpot") ~= "" and player:GetAttribute("HiddenSpot") ~= nil)
						if moving or standing then
							grazed[player] = true
							ctx.PlayerService.damage(player, E.GrazeDamage, "gloom")
							Net.fireClient(player, Net.T.Subtitle, { text = "Cold passes through your chest. Be still. Be small.", seconds = 3 })
						end
					end
				end
			end
		end
		pos = Vector3.new(pos.X, T.FloorY + 3 + math.sin(os.clock() * 0.8) * 0.4, math.clamp(pos.Z, -4, 4))
		rig.core.CFrame = CFrame.new(pos)
		if os.clock() % 7 < 0.11 then
			SoundBank.play("GloomHiss", pos, { max = 80 })
		end
	end
end

function Gloom.start(_feature)
	if active then
		return
	end
	active = true
	loopThread = task.spawn(hunt)
end

function Gloom.stop()
	if not active then
		return
	end
	active = false
	if loopThread then
		pcall(task.cancel, loopThread)
		loopThread = nil
	end
	if rig and rig.model.Parent then
		local model = rig.model
		task.spawn(function()
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					game:GetService("TweenService"):Create(part, TweenInfo.new(1.5), { Transparency = 1 }):Play()
				end
			end
			task.wait(1.6)
			model:Destroy()
		end)
	end
	rig = nil
end

return Gloom
