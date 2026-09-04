local BombModule = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Configs
BombModule.Config = {
	CountdownTime = 20, -- seconds before explosion
	SpeedUpRate = 0.1,  -- bomb speeds up over time
	PassCooldown = 1, -- seconds before a player can pass again
	SpeedBoost = 4, -- player speedboost when holding the bomb
	BombFolder = ReplicatedStorage:WaitForChild("BombAssets"), -- folder with bomb assets
	BombHeightOffset = 2.5, -- fallback: how high above the HRP the bomb floats if RightHand isn't available
}

local ActiveBombs = {} -- variable used to track active bombs
local PlayersWithBomb = {} -- variable used to track players holding the bomb

local function applySpeed(player)
	if not player or not player.Character then return end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if not humanoid:GetAttribute("OldSpeed") then
			humanoid:SetAttribute("OldSpeed", humanoid.WalkSpeed)
		end
		humanoid.WalkSpeed = humanoid.WalkSpeed + BombModule.Config.SpeedBoost
	end
end

local function removeSpeed(player)
	if not player or not player.Character then return end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local old = humanoid:GetAttribute("OldSpeed")
		if old then
			humanoid.WalkSpeed = old
			humanoid:SetAttribute("OldSpeed", nil)
		end
	end
end

function BombModule:GiveBombToRandomPlayers(amount)
	local candidates = {}

	for _, plr in pairs(Players:GetPlayers()) do
		local humanoid = plr.Character and plr.Character:FindFirstChild("Humanoid")
		if humanoid and humanoid.Health > 0 and not PlayersWithBomb[plr] then
			table.insert(candidates, plr)
		end
	end

	if #candidates == 0 then
		warn("No valid players found to give a bomb to")
		return
	end

	for i = #candidates, 2, -1 do
		local j = math.random(i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	for i = 1, math.min(amount, #candidates) do
		self:GiveBomb(candidates[i])
	end
end

-- Give bomb to a player
function BombModule:GiveBomb(player)
	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if PlayersWithBomb[player] then return end

	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warn("No HumanoidRootPart found for "..player.Name)
		return
	end
	local rightHand = player.Character:FindFirstChild("RightHand")

	PlayersWithBomb[player] = true

	-- Clone BombPart
	local bombPart = self.Config.BombFolder:WaitForChild("BombPart"):Clone()
	bombPart.Anchored = false
	bombPart.CanCollide = false
	bombPart.Parent = workspace

	-- Clone highlights and light
	local highlight = self.Config.BombFolder:WaitForChild("BombHighlight"):Clone()
	highlight.Parent = bombPart
	highlight.Enabled = false
	local light = self.Config.BombFolder:WaitForChild("BombLight"):Clone()
	light.Parent = bombPart
	light.Enabled = false
	local playerhighlight = self.Config.BombFolder:WaitForChild("PlayerHighlight"):Clone()
	playerhighlight.Parent = player.Character
	playerhighlight.Enabled = true

	-- Position bomb: preferably in-hand via GripAttachment, else floating above the head
	local gripAttachment = bombPart:FindFirstChild("GripAttachment")
	if rightHand and gripAttachment then
		bombPart.CFrame = rightHand.CFrame * gripAttachment.CFrame:Inverse()
	else
		bombPart.CFrame = hrp.CFrame * CFrame.new(0, self.Config.BombHeightOffset, 0) * (gripAttachment and gripAttachment.CFrame:Inverse() or CFrame.new())
	end

	-- Weld bomb to the hand (so it follows the hold animation), falling back to HRP if no hand
	local weld = Instance.new("Weld")
	if rightHand and gripAttachment then
		weld.Part0 = rightHand
		weld.Part1 = bombPart
		weld.C0 = CFrame.new()
		weld.C1 = gripAttachment.CFrame
	else
		weld.Part0 = hrp
		weld.Part1 = bombPart
		weld.C0 = CFrame.new(0, self.Config.BombHeightOffset, 0)
		weld.C1 = gripAttachment and gripAttachment.CFrame or CFrame.new()
	end
	weld.Parent = bombPart

	-- Track who currently holds the bomb
	local holderValue = Instance.new("ObjectValue")
	holderValue.Name = "CurrentHolder"
	holderValue.Value = player
	holderValue.Parent = bombPart

	-- Track last time the bomb was passed
	local lastPassTime = Instance.new("NumberValue")
	lastPassTime.Name = "LastPassTime"
	lastPassTime.Value = 0
	lastPassTime.Parent = bombPart

	-- Tracks the currently playing hold AnimationTrack so it can be stopped
	-- when the bomb passes hands; kept as a closure-local rather than an
	-- Instance since only this script needs to read it
	local currentAnim = nil
	local function playHoldAnimation(newHolder)
		if not newHolder or not newHolder.Character then return end
		local humanoid = newHolder.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		-- Stop previous animation if exists
		if currentAnim then
			currentAnim:Stop()
			currentAnim = nil
		end

		-- Play HoldAnimation
		local holdAnim = BombModule.Config.BombFolder:WaitForChild("BombHold")
		if holdAnim then
			local animTrack = humanoid:LoadAnimation(holdAnim)
			animTrack.Priority = Enum.AnimationPriority.Action
			animTrack:Play()
			currentAnim = animTrack
		end
	end

	-- Apply animation to first holder
	playHoldAnimation(player)
	applySpeed(player)

	-- Handle player death while holding bomb
	local function onDied()
		if PlayersWithBomb[player] then
			PlayersWithBomb[player] = nil
		end
		removeSpeed(player)
	end

	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			-- Clear player bomb attributes
			PlayersWithBomb[player] = nil
			removeSpeed(player)

			-- Clean up bomb
			if holderValue.Value == player then
				if bombPart and bombPart.Parent then
					bombPart:Destroy()
				end

				if playerhighlight then
					playerhighlight:Destroy()
				end
			end
		end)
	end

	-- Spatial query setup: reused every Heartbeat instead of a Touched event,
	-- since GetPartsInPart lets us query overlap on-demand rather than reacting
	-- to physics collision — same detection style as the turret's hitbox check
	local passOverlapParams = OverlapParams.new()
	passOverlapParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Keeps the overlap filter in sync with whoever currently holds the bomb,
	-- so the query never "detects" the holder's own character as a pass target
	local function updatePassFilter(holderChar)
		passOverlapParams.FilterDescendantsInstances = holderChar and {holderChar} or {}
	end
	updatePassFilter(player.Character)

	local function checkForPass()
		local parts = workspace:GetPartsInPart(bombPart, passOverlapParams)

		for _, part in ipairs(parts) do
			local otherChar = part:FindFirstAncestorOfClass("Model")
			local otherHumanoid = otherChar and otherChar:FindFirstChild("Humanoid")
			if not otherHumanoid or otherHumanoid.Health <= 0 then continue end

			local otherPlayer = Players:GetPlayerFromCharacter(otherChar)
			if not otherPlayer then continue end
			if PlayersWithBomb[otherPlayer] then continue end -- ignore players with bomb
			if otherPlayer == holderValue.Value then continue end -- ignore self-touch

			-- Check pass cooldown
			local currentTime = tick()
			if currentTime - lastPassTime.Value < BombModule.Config.PassCooldown then
				continue -- still in cooldown
			end

			if currentAnim then
				currentAnim:Stop()
				currentAnim = nil
			end

			local oldHolder = holderValue.Value
			if oldHolder then
				PlayersWithBomb[oldHolder] = nil
			end

			removeSpeed(oldHolder)

			-- Pass the bomb
			holderValue.Value = otherPlayer
			lastPassTime.Value = tick()

			-- Play new holder animation
			applySpeed(otherPlayer)
			playHoldAnimation(otherPlayer)

			local newHrp = otherPlayer.Character and otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			local newRightHand = otherPlayer.Character and otherPlayer.Character:FindFirstChild("RightHand")
			if newHrp then
				for _, w in pairs(bombPart:GetChildren()) do
					if w:IsA("Weld") or w:IsA("WeldConstraint") then
						w:Destroy()
					end
				end

				-- Move player highlight onto new player
				playerhighlight.Parent = otherPlayer.Character
				playerhighlight.Enabled = true

				-- Position bomb: preferably in-hand via GripAttachment, else floating above the head
				local passGripAttachment = bombPart:FindFirstChild("GripAttachment")
				if newRightHand and passGripAttachment then
					bombPart.CFrame = newRightHand.CFrame * passGripAttachment.CFrame:Inverse()
				else
					bombPart.CFrame = newHrp.CFrame * CFrame.new(0, self.Config.BombHeightOffset, 0) * (passGripAttachment and passGripAttachment.CFrame:Inverse() or CFrame.new())
				end
				PlayersWithBomb[otherPlayer] = true

				-- WeldConstraint auto-solves the offset from current CFrames rather
				-- than needing manual C0/C1 math like the initial Weld above —
				-- used here to show both approaches depending on whether we already
				-- have the GripAttachment CFrame math on hand or not
				local newWeld = Instance.new("WeldConstraint")
				if newRightHand and passGripAttachment then
					newWeld.Part0 = newRightHand
					newWeld.Part1 = bombPart
				else
					newWeld.Part0 = newHrp
					newWeld.Part1 = bombPart
				end
				newWeld.Parent = bombPart
			end

			updatePassFilter(otherPlayer.Character) -- exclude the new holder from future pass checks
			break -- bomb already passed this frame, stop scanning remaining parts
		end
	end

	-- Bomb timer logic
	local timer = self.Config.CountdownTime
	local speedMultiplier = 1
	local flashOn = false
	ActiveBombs[bombPart] = true

	-- beep sound
	local beepSound = self.Config.BombFolder:FindFirstChild("Beep"):Clone()
	beepSound.Parent = bombPart

	local accumulatedTime = 0
	local flashConnection
	flashConnection = RunService.Heartbeat:Connect(function(dt)
		if not bombPart or not bombPart.Parent then
			flashConnection:Disconnect()
			ActiveBombs[bombPart] = nil
			return
		end

		checkForPass() -- spatial-query pass detection, runs every frame alongside the countdown

		-- Countdown
		timer = timer - dt

		local gui = bombPart:FindFirstChild("BillboardGui")
		if gui then
			local label = gui:FindFirstChild("Countdown")
			if label then
				label.Text = tostring(math.ceil(timer))
			end
		end

		local maxInterval = 1.0   -- slowest beep
		local minInterval = 0.05  -- fastest beep at last few seconds
		local interval = math.clamp(timer / BombModule.Config.CountdownTime * maxInterval, minInterval, maxInterval)

		accumulatedTime = accumulatedTime + dt
		if accumulatedTime >= interval then
			accumulatedTime = 0
			flashOn = not flashOn
			highlight.Enabled = flashOn
			light.Enabled = flashOn

			if flashOn then
				beepSound:Stop()
				beepSound.TimePosition = 0
				beepSound:Play()
			end
		end

		if timer <= 0 then
			-- Explosion
			local explosion = Instance.new("Explosion")
			explosion.Position = bombPart.Position
			explosion.BlastRadius = 10
			explosion.BlastPressure = 0
			explosion.DestroyJointRadiusPercent = 0
			explosion.Parent = workspace

			-- Kill Logic
			local char = holderValue.Value and holderValue.Value.Character
			if char and char:FindFirstChild("Humanoid") then
				char.Humanoid.Health = 0
			end

			-- Explode Sound
			if char then
				local hrpForSound = char:FindFirstChild("HumanoidRootPart")
				local explodesound = self.Config.BombFolder:FindFirstChild("Explode"):Clone()
				explodesound.Parent = hrpForSound or workspace.Terrain
				explodesound:Play()
			end

			-- Cleanup
			local holder = holderValue.Value
			if holder then
				PlayersWithBomb[holder] = nil
			end

			removeSpeed(holder) -- reuses the same holder variable instead of redeclaring it
			bombPart:Destroy()
			playerhighlight:Destroy()
			ActiveBombs[bombPart] = nil
			flashConnection:Disconnect()
		end
	end)
end

-- Give bomb to multiple players
function BombModule:GiveBombToPlayers(playerList)
	for _, plr in ipairs(playerList) do
		self:GiveBomb(plr)
	end
end

---------------------------------------------------
-- DEMO STARTER
-- This is what actually triggers the bomb system in the demo Place.
-- Waits for at least 1 player, then hands the bomb to a random eligible
-- player so the pass/explode loop above is observable.
---------------------------------------------------
task.spawn(function()
	while #Players:GetPlayers() < 1 do
		task.wait(1)
	end

	task.wait(3) -- give characters time to fully load in

	BombModule:GiveBombToRandomPlayers(1)
end)
