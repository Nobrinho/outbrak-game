--!strict
-- Two-bone IK for R15 arms driven through joint Transforms. Everything is in UpperTorso space
-- (the shoulders' Part0). Shoulder transforms use PoseController's parametrisation: raise by
-- `pitch` about X (0 = hanging, pi/2 = forward), then swing by `yaw` about Y; the elbow bends
-- about its X axis. The elbow bend is found by bisection on the real joint offsets, so it
-- works for any body scale.

local ArmIK = {}

-- A joint's fixed frames: Part1 = Part0 * C0 * Transform * C1:Inverse().
export type Frames = { C0: CFrame, C1: CFrame }
export type Chain = { shoulder: Frames, elbow: Frames, wrist: Frames }

-- Frames of a Motor6D (C0/C1) or an AnimationConstraint (its attachments), nil otherwise.
function ArmIK.frames(joint: Instance?): Frames?
	if joint and joint:IsA("Motor6D") then
		return { C0 = joint.C0, C1 = joint.C1 }
	elseif joint and joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		if a0 and a1 then
			return { C0 = a0.CFrame, C1 = a1.CFrame }
		end
	end
	return nil
end

local MAX_BEND = 2.6

-- The wrist pivot relative to the shoulder joint frame, for elbow bend `e` and no shoulder
-- turn. The pivot (not the hand's centre) is what the arm must reach: the wrist then turns
-- the hand around it without moving it.
local function reach(chain: Chain, e: number): Vector3
	return (
		chain.shoulder.C1:Inverse()
		* chain.elbow.C0
		* CFrame.Angles(e, 0, 0)
		* chain.elbow.C1:Inverse()
		* chain.wrist.C0
	).Position
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Shoulder transform and elbow bend that put the wrist pivot at `target`. Out of reach, the
-- arm straightens and points at it.
function ArmIK.solve(chain: Chain, target: Vector3): (CFrame, number)
	local goal = chain.shoulder.C0:PointToObjectSpace(target)
	local distance = goal.Magnitude
	local bend
	if distance >= reach(chain, 0).Magnitude then
		bend = 0
	elseif distance <= reach(chain, MAX_BEND).Magnitude then
		bend = MAX_BEND
	else
		local lo, hi = 0, MAX_BEND
		for _ = 1, 14 do
			local mid = (lo + hi) / 2
			if reach(chain, mid).Magnitude > distance then
				lo = mid
			else
				hi = mid
			end
		end
		bend = (lo + hi) / 2
	end

	-- Turn the hand direction u onto the goal direction w: pitch fixes the height
	-- (u.Y cos p - u.Z sin p = w.Y), yaw then fixes the heading. Of the two pitch solutions,
	-- keep the one needing the smaller yaw (arm in front rather than twisted behind).
	local u = reach(chain, bend)
	local w = if distance > 1e-4 then goal.Unit * u.Magnitude else u
	local r0 = math.max(math.sqrt(u.Y * u.Y + u.Z * u.Z), 1e-6)
	local phi = math.atan2(u.Z, u.Y)
	local base = math.acos(math.clamp(w.Y / r0, -1, 1))
	local best, bestYaw = CFrame.identity, math.huge
	for _, sign in { 1, -1 } do
		local pitch = sign * base - phi
		local q = CFrame.Angles(pitch, 0, 0) * u
		local yaw = wrapAngle(math.atan2(w.X, w.Z) - math.atan2(q.X, q.Z))
		if math.abs(yaw) < bestYaw then
			bestYaw = math.abs(yaw)
			best = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		end
	end
	return best, bend
end

-- The lower arm's CFrame for a solved shoulder transform and elbow bend.
function ArmIK.lowerArm(chain: Chain, shoulder: CFrame, bend: number): CFrame
	return chain.shoulder.C0
		* shoulder
		* chain.shoulder.C1:Inverse()
		* chain.elbow.C0
		* CFrame.Angles(bend, 0, 0)
		* chain.elbow.C1:Inverse()
end

-- Where the wrist pivot must be for the hand to sit at `hand`.
function ArmIK.pivotFor(chain: Chain, hand: CFrame): Vector3
	return (hand * chain.wrist.C1).Position
end

-- Wrist rotation that turns the hand to `hand` (position comes from the arm, not the wrist).
function ArmIK.wrist(chain: Chain, lowerArm: CFrame, hand: CFrame): CFrame
	return (chain.wrist.C0:Inverse() * lowerArm:Inverse() * hand * chain.wrist.C1).Rotation
end

return table.freeze(ArmIK)
