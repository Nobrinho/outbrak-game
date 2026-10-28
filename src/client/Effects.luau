--!strict
-- Local-only combat feedback: blood, tracers, muzzle flashes, the melee swipe, explosion
-- fireballs and camera shake. Pooled emitters serve every burst, so heavy fights don't create
-- instances. `Effects.quality` drops to 0.5 when the frame rate sags (§2 Gráficos Dinâmicos):
-- fewer particles and no flash lights.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(game:GetService("ReplicatedStorage").Shared.Art.AssetIds)

local Effects = {}

Effects.quality = 1

local COLOR_BLOOD = Color3.fromRGB(70, 8, 8)
local COLOR_TRACER = Color3.fromRGB(255, 220, 140)

local folder: Folder? = nil
local bloodAttachment: Attachment? = nil
local bloodEmitter: ParticleEmitter? = nil
local smokeAttachment: Attachment? = nil
local smokeEmitter: ParticleEmitter? = nil
local flashAttachment: Attachment?
local flashEmitter: ParticleEmitter?
local sparkAttachment: Attachment?
local sparkEmitter: ParticleEmitter?
local trauma = 0 -- camera shake, 0..1

local function container(): Folder
	if folder then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "EffectsClient"
	f.Parent = workspace
	folder = f
	return f
end

local function emitter(): (Attachment, ParticleEmitter)
	if bloodAttachment and bloodEmitter then
		return bloodAttachment, bloodEmitter
	end
	local anchor = Instance.new("Part")
	anchor.Name = "BloodAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new()
	anchor.Parent = container()

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local pe = Instance.new("ParticleEmitter")
	pe.Enabled = false
	pe.Texture = "rbxassetid://" .. AssetIds["vfx.soft-particle"]
	pe.Color = ColorSequence.new(COLOR_BLOOD)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Lifetime = NumberRange.new(0.35, 0.6)
	pe.Speed = NumberRange.new(6, 14)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -60, 0)
	pe.Drag = 2
	pe.LightInfluence = 1
	pe.Parent = attachment

	bloodAttachment, bloodEmitter = attachment, pe
	return attachment, pe
end

function Effects.blood(position: Vector3, amount: number)
	local attachment, pe = emitter()
	attachment.WorldPosition = position
	pe:Emit(math.max(1, math.round(amount * Effects.quality)))
end

local function smoke(): (Attachment, ParticleEmitter)
	if smokeAttachment and smokeEmitter then
		return smokeAttachment, smokeEmitter
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Enabled = false
	pe.Texture = "rbxassetid://" .. AssetIds["vfx.smoke"]
	pe.Color = ColorSequence.new(Color3.fromRGB(70, 64, 60))
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 7),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(1.2, 2)
	pe.Speed = NumberRange.new(4, 12)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, 6, 0)
	pe.Drag = 1.5
	pe.RotSpeed = NumberRange.new(-40, 40)
	pe.Parent = attachment
	smokeAttachment, smokeEmitter = attachment, pe
	return attachment, pe
end

-- Two reusable emitters; one flash per shot and a bounded spark burst per explosion.
local function catalogBurst(position: Vector3, sparks: boolean)
	local attachment = if sparks then sparkAttachment else flashAttachment
	local particle = if sparks then sparkEmitter else flashEmitter
	if not attachment or not particle then
		attachment = Instance.new("Attachment")
		attachment.Name = if sparks then "CatalogSparks" else "CatalogMuzzle"
		attachment.Parent = workspace.Terrain
		particle = Instance.new("ParticleEmitter")
		particle.Enabled = false
		particle.Texture = "rbxassetid://"
			.. AssetIds[if sparks then "vfx.spark" else "vfx.muzzle-flash"]
		particle.Color =
			ColorSequence.new(Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 100, 20))
		particle.LightEmission = 1
		particle.Size = NumberSequence.new(if sparks then 0.3 else 1.2, 0)
		particle.Lifetime = if sparks
			then NumberRange.new(0.2, 0.45)
			else NumberRange.new(0.04, 0.07)
		particle.Speed = if sparks then NumberRange.new(10, 24) else NumberRange.new(0)
		particle.SpreadAngle = Vector2.new(180, 180)
		particle.Acceleration = if sparks then Vector3.new(0, -35, 0) else Vector3.zero
		particle.Parent = attachment
		if sparks then
			sparkAttachment, sparkEmitter = attachment, particle
		else
			flashAttachment, flashEmitter = attachment, particle
		end
	end
	attachment.WorldPosition = position
	particle:Emit(if sparks then math.max(2, math.round(10 * Effects.quality)) else 1)
end

-- Short-lived neon flash at the muzzle; a light too unless quality is reduced.
function Effects.muzzleFlash(position: Vector3, direction: Vector3)
	catalogBurst(position + direction * 0.4, false)
	local flash = Instance.new("Part")
	flash.Transparency = 1 -- visual is now the catalog texture; this anchor carries the brief light
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 200, 90)
	flash.Size = Vector3.new(0.35, 0.35, 0.9)
	flash.CFrame = CFrame.lookAt(position + direction * 0.4, position + direction)
	if Effects.quality >= 1 then
		local light = Instance.new("PointLight")
		light.Color = flash.Color
		light.Range = 10
		light.Brightness = 3
		light.Parent = flash
	end
	flash.Parent = container()
	Debris:AddItem(flash, 0.05)
end

-- Fireball that swells and fades, a burst of smoke, and shake that falls off with distance.
function Effects.explosion(position: Vector3, radius: number)
	catalogBurst(position, true)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 130, 30)
	ball.Size = Vector3.one * 2
	ball.CFrame = CFrame.new(position)
	ball.Parent = container()
	local grow = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ball, grow, {
		Size = Vector3.one * radius * 1.2,
		Transparency = 1,
		Color = Color3.fromRGB(120, 40, 10),
	}):Play()
	Debris:AddItem(ball, 0.4)

	local attachment, pe = smoke()
	attachment.WorldPosition = position
	pe:Emit(math.max(4, math.round(18 * Effects.quality)))

	local camera = workspace.CurrentCamera
	local distance = (camera.CFrame.Position - position).Magnitude
	Effects.shake(math.clamp(1 - distance / (radius * 6), 0, 1) * 0.9)
end

-- Adds camera shake (0..1); it decays on its own.
function Effects.shake(amount: number)
	trauma = math.min(1, trauma + amount)
end

local function applyShake(dt: number)
	if trauma <= 0 then
		return
	end
	local strength = trauma * trauma
	local t = os.clock() * 25
	local camera = workspace.CurrentCamera
	camera.CFrame *= CFrame.Angles(
		math.rad(math.noise(t, 1) * 4 * strength),
		math.rad(math.noise(t, 2) * 4 * strength),
		math.rad(math.noise(t, 3) * 3 * strength)
	)
	trauma = math.max(0, trauma - dt * 1.6)
end

-- Starts camera shake and the frame-rate watch that drives `quality`. Call once.
function Effects.start()
	-- After the default camera has positioned itself this frame.
	RunService:BindToRenderStep("SwarmShake", Enum.RenderPriority.Camera.Value + 2, applyShake)

	local frames, elapsed = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		frames += 1
		elapsed += dt
		if elapsed >= 2 then
			local fps = frames / elapsed
			-- Hysteresis so it doesn't flip every sample around the threshold.
			if fps < 40 then
				Effects.quality = 0.5
			elseif fps > 50 then
				Effects.quality = 1
			end
			frames, elapsed = 0, 0
		end
	end)
end

function Effects.tracer(from: Vector3, to: Vector3, color: Color3?)
	local offset = to - from
	local length = offset.Magnitude
	if length < 0.5 then
		return
	end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color or COLOR_TRACER
	beam.Transparency = 0.3
	beam.Size = Vector3.new(0.08, 0.08, length)
	beam.CFrame = CFrame.lookAt(from + offset / 2, to)
	beam.Parent = container()
	Debris:AddItem(beam, 0.05)
end

-- Flat arc flash in front of the player for a melee swing.
function Effects.swipe(root: CFrame, range: number)
	local slab = Instance.new("Part")
	slab.Anchored = true
	slab.CanCollide = false
	slab.CanQuery = false
	slab.CanTouch = false
	slab.CastShadow = false
	slab.Material = Enum.Material.Neon
	slab.Color = Color3.new(1, 1, 1)
	slab.Transparency = 0.7
	slab.Size = Vector3.new(range * 1.2, 0.1, range * 0.6)
	slab.CFrame = root * CFrame.new(0, 0.5, -range * 0.5)
	slab.Parent = container()
	Debris:AddItem(slab, 0.08)
end

return Effects
