--!strict
-- Local-only combat feedback: blood bursts, bullet tracers and the melee swipe. Greybox
-- visuals; the art pass (week 9) swaps textures and adds sound. One pooled emitter serves
-- every blood burst, so heavy fights don't create instances.

local Debris = game:GetService("Debris")

local Effects = {}

local COLOR_BLOOD = Color3.fromRGB(70, 8, 8)
local COLOR_TRACER = Color3.fromRGB(255, 220, 140)

local folder: Folder? = nil
local bloodAttachment: Attachment? = nil
local bloodEmitter: ParticleEmitter? = nil

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
	pe:Emit(amount)
end

function Effects.tracer(from: Vector3, to: Vector3)
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
	beam.Color = COLOR_TRACER
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
