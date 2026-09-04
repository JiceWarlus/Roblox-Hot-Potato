--[[ Connected Discord-GitHub

	This is a system for game's like Pass the Bomb / Hot Potato Type Gamemodes. 
	Every 3 Seconds a bomb will be given to a random player in the game. Players will have 20 seconds
	total to pass the bomb to another player. If the bomb is not passed in 20 seconds, the bomb will explode

	JiceWarlus on Roblox & Discord
]]

local BombModule = {}
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Configs
BombModule.Config = {
	CountdownTime = 20, -- seconds before explosion
	PassCooldown = 1, -- seconds before a player can pass again
	SpeedBoost = 4, -- player speedboost when holding the bomb
	BombFolder = ReplicatedStorage:WaitForChild("BombAssets"), -- folder with bomb assets
	BombHeightOffset = 2.5, -- fallback: how high above the HRP the bomb floats if RightHand isn't available
}

local ActiveBombs = {} -- table used to track active bombs
local PlayersWithBomb = {} -- table used to track players holding the bomb

local function applySpeed(player)
	if not player or not player.Character then return end -- check if player and character exist
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid") -- we find the players humanoid
	if humanoid then -- if the humanoid exist then we apply the new walkspeed
		if not humanoid:GetAttribute("OldSpeed") then -- we check if the player has the "OldSpeed" attribute if not we continue this line
			humanoid:SetAttribute("OldSpeed", humanoid.WalkSpeed) -- if the player has no "OldSpeed" Attribute saved we store the players current walkspeed onto the attribute
		end
		humanoid.WalkSpeed = humanoid.WalkSpeed + BombModule.Config.SpeedBoost -- we add the speedboost to the players current speed
	end
end

local function removeSpeed(player)
	if not player or not player.Character then return end -- check if player and character exist
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid") -- we find the players humanoid
	if humanoid then -- if the humanoid exist we apply their old speed back
		local old = humanoid:GetAttribute("OldSpeed") -- variable for getting the OldSpeed attribute
		if old then -- if the player has the OldSpeed attribute we continue
			humanoid.WalkSpeed = old -- we set the players Speed to the OldSpeed's value
			humanoid:SetAttribute("OldSpeed", nil) -- we remove the value of the attribute after we set the players speed to their old speed
		end
	end
end

function BombModule:GiveBombToRandomPlayers(amount)
	local candidates = {} -- table used for storing players who can receive the bomb

	for _, plr in pairs(Players:GetPlayers()) do -- we loop through all the players in the game to check if their applicable to receive the random bomb
		local humanoid = plr.Character and plr.Character:FindFirstChild("Humanoid") -- we check if the player has a humanoid and if the humanoid is alive
		if humanoid and humanoid.Health > 0 and not PlayersWithBomb[plr] then -- if the player is alive and hasnt received a bomb we continue
			table.insert(candidates, plr) -- we add the player to the candidates table
		end
	end

	if #candidates == 0 then -- if theres no players valid to give the bomb we warn the server
		warn("No valid players found to give a bomb to") -- we warn the server
		return
	end

	for i = #candidates, 2, -1 do -- we shuffle the table to get a random player
		local j = math.random(i) -- we get a random player from the table
		candidates[i], candidates[j] = candidates[j], candidates[i] -- we swap the players in the table to randomize the table
	end

	for i = 1, math.min(amount, #candidates) do -- we give the bomb to the random player
		self:GiveBomb(candidates[i]) -- we call the GiveBomb function and give the bomb to the player
	end
end

function BombModule:GiveBomb(player)
	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid") -- we check if the player has a humanoid and if the humanoid is alive
	if not humanoid or humanoid.Health <= 0 then return end -- if the player is dead we return
	if PlayersWithBomb[player] then return end -- if the player has already received a bomb we return

	local hrp = player.Character:FindFirstChild("HumanoidRootPart") -- we get the players HumanoidRootPart
	if not hrp then -- if the player has no HumanoidRootPart we warn the server
		warn("No HumanoidRootPart found for "..player.Name) -- we warn the server
		return
	end

	local rightHand = player.Character:FindFirstChild("RightHand") -- we get the players RightHand

	PlayersWithBomb[player] = true -- we set the player to the PlayersWithBomb table to prevent them from receiving another bomb

	local bombPart = self.Config.BombFolder:WaitForChild("BombPart"):Clone() -- we clone the bomb part
	bombPart.Anchored = false -- we unanchor the bomb for players to move with it
	bombPart.CanCollide = false -- we disable collisions to prevent the bomb from colliding with the player and parts of the map
	bombPart.Parent = workspace -- we parent the bomb to the workspace

	local highlight = self.Config.BombFolder:WaitForChild("BombHighlight"):Clone() -- we clone the bombs highlight
	highlight.Parent = bombPart -- we parent the highlight to the bomb
	highlight.Enabled = false -- we disable the highlight
	local light = self.Config.BombFolder:WaitForChild("BombLight"):Clone() -- we clone the bomb light
	light.Parent = bombPart -- we parent the light to the bomb
	light.Enabled = false -- we disable the light
	local playerhighlight = self.Config.BombFolder:WaitForChild("PlayerHighlight"):Clone() -- we clone the player highlight
	playerhighlight.Parent = player.Character -- we parent the highlight to the player
	playerhighlight.Enabled = true -- we enable the highlight

	local gripAttachment = bombPart:FindFirstChild("GripAttachment") -- we get the bombs grip attachment
	if rightHand and gripAttachment then -- if the player has a right hand and the bomb has a grip attachment we continue
		bombPart.CFrame = rightHand.CFrame * gripAttachment.CFrame:Inverse() -- we position the bomb in the players right hand
	else
		bombPart.CFrame = hrp.CFrame * CFrame.new(0, self.Config.BombHeightOffset, 0) * (gripAttachment and gripAttachment.CFrame:Inverse() or CFrame.new()) --  if the player has no right hand or the bomb has no grip attachment we position the bomb above the players head
	end

	local weld = Instance.new("Weld")  -- we create a weld to weld the bomb to the players hand or HumanoidRootPart
	if rightHand and gripAttachment then -- if the player has a right hand and the bomb has a grip attachment we continue

		-- we weld the bomb to the players right hand
		weld.Part0 = rightHand 
		weld.Part1 = bombPart

		-- we set the weld offset to the grip attachments offset
		weld.C0 = CFrame.new()
		weld.C1 = gripAttachment.CFrame
	else -- if player has no right hand or the bomb has no grip attachment we weld the bomb to the players HumanoidRootPart

		-- we weld the bomb to the players HumanoidRootPart
		weld.Part0 = hrp
		weld.Part1 = bombPart

		-- we set the weld offset to the grip attachments offset
		weld.C0 = CFrame.new(0, self.Config.BombHeightOffset, 0)
		weld.C1 = gripAttachment and gripAttachment.CFrame or CFrame.new()

	end

	weld.Parent = bombPart -- we parent the weld to the bomb

	-- for traking the player currently holding the bomb
	local holderValue = Instance.new("ObjectValue") -- we create an object value to track the player holding the bomb
	holderValue.Name = "CurrentHolder" -- we name the object value CurrentHolder
	holderValue.Value = player -- we set the object values value to the player
	holderValue.Parent = bombPart -- we parent the object value to the bomb

	-- for tracking when the bomb was last passed. used for the passing cooldown
	local lastPassTime = Instance.new("NumberValue") -- we create a number value to track the last time the bomb was passed
	lastPassTime.Name = "LastPassTime" -- we name the number value LastPassTime
	lastPassTime.Value = 0 -- we set the number values value to 0
	lastPassTime.Parent = bombPart -- we parent the number value to the bomb

	-- Tracks the currently playing hold AnimationTrack so it can be stopped
	-- when the bomb passes hands; kept as a closure-local rather than an
	-- Instance since only this script needs to read it
	local currentAnim = nil -- we create a nil variable to track the current animation track
	local function playHoldAnimation(newHolder)
		if not newHolder or not newHolder.Character then return end -- if there is no new holder or the new holders character does not exist we return
		local humanoid = newHolder.Character:FindFirstChildOfClass("Humanoid") -- we find the humanoid in the new holders character
		if not humanoid then return end -- if there is no humanoid we return

		if currentAnim then
			currentAnim:Stop() -- we stop the previous animation if it exists
			currentAnim = nil -- we set the current animation to nil
		end

		-- Play HoldAnimation
		local holdAnim = BombModule.Config.BombFolder:WaitForChild("BombHold") -- we find the HoldAnimation in the bomb folder
		if holdAnim then -- if there is a HoldAnimation
			local animTrack = humanoid:LoadAnimation(holdAnim) -- we load the HoldAnimation
			animTrack:Play() -- we play the animation
			currentAnim = animTrack -- we set the current animation to the animation track
		end
	end

	playHoldAnimation(player)  -- we play the hold animation for the player
	applySpeed(player) -- we apply the speed to the player

	local humanoid = player.Character:FindFirstChildOfClass("Humanoid") -- we find the humanoid in the player's character
	if humanoid then -- if the player has a humanoid
		humanoid.Died:Connect(function() ---- once the player dies or their health reaches 0 we run a clear players bomb attributes

			PlayersWithBomb[player] = nil -- we remove the player from the list of players holding the bomb
			removeSpeed(player) -- we remove the speed from the player

			if holderValue.Value == player then -- if the player was still holding the bomb we remove the bomb
				if bombPart and bombPart.Parent then -- if theres still a bomb on the player
					bombPart:Destroy() -- we destroy the bomb
				end

				if playerhighlight then -- if the player still has a playerhighlight
					playerhighlight:Destroy() -- we destroy the highlight
				end
			end
		end)
	end

	local passOverlapParams = OverlapParams.new() -- we create a new overlap params for spatial queries
	passOverlapParams.FilterType = Enum.RaycastFilterType.Exclude -- we set the filter type to exclude

	local function updatePassFilter(holderChar)
		passOverlapParams.FilterDescendantsInstances = holderChar and {holderChar} or {} -- excludes the holder's own character so the query never detects them as a pass target
	end

	updatePassFilter(player.Character) -- update the filter for the player's character

	local function checkForPass()
		local parts = workspace:GetPartsInPart(bombPart, passOverlapParams) -- we get all parts in the bomb part

		for _, part in ipairs(parts) do -- we loop through all parts in the bomb part
			local otherChar = part:FindFirstAncestorOfClass("Model") -- we find the model ancestor of the part
			local otherHumanoid = otherChar and otherChar:FindFirstChild("Humanoid") -- we find the humanoid in the model
			if not otherHumanoid or otherHumanoid.Health <= 0 then continue end -- if the other character doesn't have a humanoid or the humanoid's health is 0 we skip the player

			local otherPlayer = Players:GetPlayerFromCharacter(otherChar) -- we get the player from the other character
			if not otherPlayer then continue end -- if there is no player in the other character we skip the player
			if PlayersWithBomb[otherPlayer] then continue end -- we ignore players with bomb
			if otherPlayer == holderValue.Value then continue end -- fail safety check to make sure the player thats holding the bomb doesn't pass to themselves

			local currentTime = tick() -- get current time
			if currentTime - lastPassTime.Value < BombModule.Config.PassCooldown then -- if the lastpasstime is still less than the passcooldown then its still in cooldown
				continue -- still in cooldown so we continue
			end

			if currentAnim then -- if there is a current animation
				currentAnim:Stop() -- stop the current animation
				currentAnim = nil -- we set the current animation to nil
			end

			local oldHolder = holderValue.Value -- get the old holder of the bomb
			if oldHolder then -- if there was an old holder of the bomb
				PlayersWithBomb[oldHolder] = nil -- we remove the old holder from the playerswithbomb table
			end

			removeSpeed(oldHolder) -- remove the speed from the old holder

			holderValue.Value = otherPlayer -- set the new holder of the bomb
			lastPassTime.Value = tick() -- set the lastpasstime to the current time

			applySpeed(otherPlayer) -- apply speed to the new holder
			playHoldAnimation(otherPlayer) -- play the hold animation for the new holder

			local newHrp = otherPlayer.Character and otherPlayer.Character:FindFirstChild("HumanoidRootPart") -- we get the new humanoid root part
			local newRightHand = otherPlayer.Character and otherPlayer.Character:FindFirstChild("RightHand") -- we get the new right hand
			if newHrp then -- if there is a new humanoid root part
				for _, w in pairs(bombPart:GetChildren()) do -- we loop through all children of the bomb part
					if w:IsA("Weld") or w:IsA("WeldConstraint") then -- if the child is a weld or weldconstraint
						w:Destroy() -- we destroy the weld or weldconstraint
					end
				end

				playerhighlight.Parent = otherPlayer.Character -- set the player highlight to the new player
				playerhighlight.Enabled = true -- enable the player highlight

				-- Position bomb: preferably in-hand via GripAttachment, else floating above the head
				local passGripAttachment = bombPart:FindFirstChild("GripAttachment") -- we get the grip attachment of the bomb
				if newRightHand and passGripAttachment then -- if there is a right hand and grip attachment
					bombPart.CFrame = newRightHand.CFrame * passGripAttachment.CFrame:Inverse() -- we position the bomb in the players right hand
				else -- if theres no grip attachment or right hand
					bombPart.CFrame = newHrp.CFrame * CFrame.new(0, self.Config.BombHeightOffset, 0) * (passGripAttachment and passGripAttachment.CFrame:Inverse() or CFrame.new()) --  if the player has no right hand or the bomb has no grip attachment we position the bomb above the players head
				end
				PlayersWithBomb[otherPlayer] = true -- we add the new player to the playerswithbomb table

				local newWeld = Instance.new("WeldConstraint") -- we create a weld constraint for the bomb to the players right hand or head
				if newRightHand and passGripAttachment then -- if there is a right hand and grip attachment
					newWeld.Part0 = newRightHand -- we weld the bomb to the players right hand
					newWeld.Part1 = bombPart -- we weld the bomb to the players right hand
				else
					newWeld.Part0 = newHrp -- we weld the bomb to the players head
					newWeld.Part1 = bombPart -- we weld the bomb to the players head
				end
				newWeld.Parent = bombPart -- we parent the weld to the bomb
			end

			updatePassFilter(otherPlayer.Character) -- exclude the new holder from future pass checks
			break
		end
	end

	local timer = self.Config.CountdownTime -- we get the countdown time from the config
	local flashOn = false -- we get the flash on value from the config
	ActiveBombs[bombPart] = true -- we add the bomb to the activebombs table

	local beepSound = self.Config.BombFolder:FindFirstChild("Beep"):Clone() -- we get the beep sound from the bomb folder
	beepSound.Parent = bombPart -- we parent the beep sound to the bomb

	local accumulatedTime = 0 -- timer used for the beep interval
	local flashConnection -- connection for the bombs countdown loop
	flashConnection = RunService.Heartbeat:Connect(function(dt) -- we run it every frame while the bomb is active
		if not bombPart or not bombPart.Parent then -- the bomb no longer exists
			flashConnection:Disconnect() -- we stop the loop
			ActiveBombs[bombPart] = nil -- we remove it from active bombs
			return
		end
		
		checkForPass() -- we call this function to check if the bomb should be passed
		
		timer = timer - dt -- we subtract the time that has passed from the total time to get the current time of the bomb

		local gui = bombPart:FindFirstChild("BillboardGui") -- we get the gui for the bomb timer
		if gui then -- if the gui exists we continue
			local label = gui:FindFirstChild("Countdown") -- we get the label for the timer
			if label then -- if the label exists we continue
				label.Text = tostring(math.ceil(timer)) -- we set the text to the time
			end
		end

		local maxInterval = 1.0 -- max amount it can wait between beeps
		local minInterval = 0.05 -- fastest beep at last few seconds
		local interval = math.clamp(timer / BombModule.Config.CountdownTime * maxInterval, minInterval, maxInterval) -- we get the interval for the beep

		accumulatedTime = accumulatedTime + dt -- we add the time that has passed to the accumulated time
		if accumulatedTime >= interval then -- if the accumulated time is greater than the interval we continue
			accumulatedTime = 0 -- we reset the accumulated time
			flashOn = not flashOn -- we toggle the flash on value
			highlight.Enabled = flashOn -- we set the highlight to match the flash value
			light.Enabled = flashOn -- we set the light to match the flash value

			if flashOn then -- we only play the bombs beep if flashon is true
				beepSound:Stop() -- stop the sound if its still playing
				beepSound.TimePosition = 0 -- reset it back to the start
				beepSound:Play() -- play the beep
			end
		end
		
		if timer <= 0 then -- if the timer is less than or equal to 0 we continue
			
			local explosion = Instance.new("Explosion") -- we create the explosion
			explosion.Position = bombPart.Position -- we set the position of the explosion to the bomb part
			explosion.BlastRadius = 10 -- we set the radius of the explosion
			explosion.BlastPressure = 0 -- we set the pressure of the explosion
			explosion.DestroyJointRadiusPercent = 0 -- we set the destroy joint radius to 0
			explosion.Parent = workspace -- we parent the explosion to the workspace

			local char = holderValue.Value and holderValue.Value.Character -- we get the character of the player holding the bomb
			if char and char:FindFirstChild("Humanoid") then -- if the character exists we continue
				char.Humanoid.Health = 0 -- we set the players health to 0 to explode them
			end

			if char then -- we only play the sound if the character exists
				local hrpForSound = char:FindFirstChild("HumanoidRootPart") -- we get the players root part
				local explodesound = self.Config.BombFolder:FindFirstChild("Explode"):Clone() -- we clone the explode sound
				explodesound.Parent = hrpForSound or workspace.Terrain -- we parent the sound to the players root part or the terrain if it doesn't exist
				explodesound:Play() -- we play the sound
			end

			local holder = holderValue.Value -- we get the player holding the bomb
			if holder then -- if the player exists we continue
				PlayersWithBomb[holder] = nil -- we remove the player from the players with bomb table
			end

			removeSpeed(holder) -- we get remove the speed from the player holding the bomb
			bombPart:Destroy() -- we destroy the bomb part
			playerhighlight:Destroy() -- we destroy the highlight
			ActiveBombs[bombPart] = nil -- we remove the bomb from the active bombs table
			flashConnection:Disconnect() -- we disconnect the flash connection
		end
	end)
end

function BombModule:GiveBombToPlayers(playerList)
	for _, plr in ipairs(playerList) do -- we loop through the player list
		self:GiveBomb(plr) -- we give the bomb to the player
	end
end

task.spawn(function()
	while #Players:GetPlayers() < 1 do -- wait until at least one player has joined
		task.wait(1) -- wait a second between checks
	end

	task.wait(3) -- 3 second wait to give players time to fully load in before the first bomb spawns

	while true do -- we loop forever to give out bombs for showcasing
		BombModule:GiveBombToRandomPlayers(1) -- we give a bomb to a random player
		
		repeat
			task.wait(1) -- we wait a second between checks
		until next(ActiveBombs) == nil -- we wait until theres no active bombs

		task.wait(3) -- short break between bombs before the next one spawns
	end
end)