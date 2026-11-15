local _, ns = ...
if not (ns.Compat and ns.Compat.isForever) then return end

-- Independent Forever parchment renderer. Pattern informed by Pretty Wide Quest Log
-- (Gogo1951, MIT): build a vertical flow from quest data instead of borrowing
-- Blizzard's QuestInfo frames, which are shared with quest givers and the map.
function ns.CreateForeverDetails(parent, scroll, L)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(L.PARCHMENT_RIGHT - L.PARCHMENT_LEFT, 300)
	scroll:SetScrollChild(child)
	local width = L.CONTENT_WIDTH
	local x = L.CONTENT_LEFT - L.PARCHMENT_LEFT
	local yStart = L.CONTENT_TOP - L.PANE_TOP
	local regions = {}
	local function Text(font, value)
		local t = child:CreateFontString(nil, "ARTWORK", font)
		t:SetJustifyH("LEFT")
		t:SetWidth(width)
		t:SetText(value or "")
		t:Hide()
		regions[#regions + 1] = t
		return t
	end
	local title = Text("QuestTitleFont")
	local summary = Text("QuestFont")
	local descriptionHeader = Text("QuestTitleFont", QUEST_DESCRIPTION)
	local description = Text("QuestFont")
	local rewardsHeader = Text("QuestTitleFont", QUEST_REWARDS)
	local receive = Text("QuestFont", REWARD_ITEMS_ONLY or "You will receive:")
	local choiceLabel = Text("QuestFont", REWARD_CHOICES or "Choose your reward:")
	local xpLabel = Text("QuestFont", EXPERIENCE_COLON or "Experience:")
	local money = Text("QuestFont")
	local xp = Text("QuestFont")
	local id = Text("QuestFontNormalSmall")
	id:SetJustifyH("RIGHT")
	id:SetWidth(80)
	id:SetPoint("TOPRIGHT", child, "TOPLEFT", x + width, -yStart)
	local objectives = {}
	local buttons = {}
	local placed = {}
	local last, height
	local function Place(region, gap)
		region:ClearAllPoints()
		if last then
			region:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -(gap or 0))
			height = height + (gap or 0)
		else
			region:SetPoint("TOPLEFT", child, "TOPLEFT", x, -yStart)
			height = yStart
		end
		region:Show()
		height = height + region:GetHeight()
		last = region
		placed[#placed + 1] = region
	end
	local function Clear()
		for _, region in ipairs(placed) do region:Hide() end
		for _, region in ipairs(regions) do region:Hide() end
		money:Hide()
		xp:Hide()
		id:Hide()
		for _, obj in ipairs(objectives) do
			obj.line:Hide()
			obj.count:Hide()
		end
		for _, button in ipairs(buttons) do button:Hide() end
		wipe(placed)
		last, height = nil, 0
	end
	local function Objective(i)
		if objectives[i] then return objectives[i] end
		local line = Text("QuestFont")
		local count = child:CreateFontString(nil, "ARTWORK", "QuestFont")
		count:SetJustifyH("RIGHT")
		local item = {line = line, count = count}
		objectives[i] = item
		return item
	end
	local function AddObjective(i, value, finished)
		local obj = Objective(i)
		local name, have, need = value:match("^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
		if not name then
			have, need, name = value:match("^%s*(%d+)%s*/%s*(%d+)%s+(.+)$")
		end
		local counter = have and (have .. " / " .. need) or nil
		obj.line:SetText((finished and "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t " or "") .. (name or value))
		obj.line:SetWidth(counter and width - 85 or width)
		Place(obj.line, i == 1 and 10 or 2)
		if counter then
			obj.count:SetText(counter)
			obj.count:ClearAllPoints()
			obj.count:SetPoint("TOPRIGHT", obj.line, "TOPLEFT", width - 32, 0)
			obj.count:Show()
		end
	end
	local function RewardButton(i, kind, index, name, texture, count)
		local button = buttons[i]
		if not button then
			button = CreateFrame("Button", nil, child, "QuestInfoItemButtonTemplate")
			button:SetSize(147, 37)
			button:EnableMouse(true)
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if self.kind == "choice" then GameTooltip:SetQuestLogItem("choice", self.index)
				else GameTooltip:SetQuestLogItem("reward", self.index) end
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			button:SetScript("OnClick", function(self)
				if IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
					local link = GetQuestLogItemLink(self.kind == "choice" and "choice" or "reward", self.index)
					if link then ChatEdit_InsertLink(link) end
				end
			end)
			buttons[i] = button
		end
		button.kind, button.index = kind, index
		if button.Name then button.Name:SetText(name or "") end
		if button.Icon then button.Icon:SetTexture(texture) end
		if button.Count then button.Count:SetText((count or 1) > 1 and count or "") end
		return button
	end
	local function AddRewardButtons(kind, count, offset)
		local lastRow
		for i = 1, count do
			local name, texture, quantity
			if kind == "choice" then name, texture, quantity = GetQuestLogChoiceInfo(i)
			else name, texture, quantity = GetQuestLogRewardInfo(i) end
			local button = RewardButton(offset + i, kind, i, name, texture, quantity)
			if i % 2 == 1 then
				Place(button, i == 1 and 8 or 4)
				lastRow = button
			else
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", lastRow, "TOPRIGHT", 1, 0)
				button:Show()
				placed[#placed + 1] = button
			end
		end
	end
	local function Display(questID, reset)
		Clear()
		if not questID then id:Hide() return end
		C_QuestLog.SetSelectedQuest(questID)
		local descriptionValue, objectivesValue = GetQuestLogQuestText()
		title:SetText(C_QuestLog.GetTitleForQuestID(questID) or "")
		Place(title)
		if objectivesValue and objectivesValue ~= "" then
			summary:SetText(objectivesValue)
			Place(summary, 4)
		end
		local objectiveIndex = 0
		local waypoint = C_QuestLog.GetNextWaypointText and C_QuestLog.GetNextWaypointText(questID)
		if waypoint and waypoint ~= "" then
			local line = Objective(1).line
			line:SetWidth(width)
			line:SetText(waypoint)
			Place(line, 10)
			objectiveIndex = 1
		end
		for i = 1, GetNumQuestLeaderBoards() do
			local value, kind, finished = GetQuestLogLeaderBoard(i)
			if kind ~= "spell" and kind ~= "log" then
				objectiveIndex = objectiveIndex + 1
				AddObjective(objectiveIndex, (value and value ~= "") and value or (kind or ""), finished)
			end
		end
		if descriptionValue and descriptionValue ~= "" then
			Place(descriptionHeader, 20)
			description:SetText(descriptionValue)
			Place(description, 5)
		end
		if not C_QuestLog.ShouldShowQuestRewards or C_QuestLog.ShouldShowQuestRewards(questID) then
			local choices = GetNumQuestLogChoices() or 0
			local rewards = GetNumQuestLogRewards() or 0
			local coins = GetQuestLogRewardMoney() or 0
			local experience = GetQuestLogRewardXP() or 0
			if choices > 0 or rewards > 0 or coins > 0 or experience > 0 then
				Place(rewardsHeader, 18)
				if choices > 0 then
					Place(choiceLabel, 5)
					AddRewardButtons("choice", choices, 1)
				end
				if rewards > 0 or coins > 0 or experience > 0 then
					Place(receive, 8)
					if coins > 0 then
						money:SetText(GetCoinTextureString(coins))
						money:ClearAllPoints()
						money:SetPoint("TOPLEFT", receive, "TOPLEFT", L.REWARD_VALUE_X - 48, 0)
						money:Show()
					end
					if experience > 0 then
						Place(xpLabel, 4)
						xp:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(experience) or tostring(experience))
						xp:ClearAllPoints()
						xp:SetPoint("TOPLEFT", xpLabel, "TOPLEFT", L.REWARD_VALUE_X - 48, 0)
						xp:Show()
					end
					AddRewardButtons("reward", rewards, choices + 1)
				end
			end
		end
		id:SetShown(ns.GetOption("showQuestID"))
		id:SetText(ns.QuestIDText(questID))
		child:SetHeight(math.max(height + 22, scroll:GetHeight()))
		scroll:UpdateScrollChildRect()
		if reset then scroll:SetVerticalScroll(0) end
	end
	return Display
end
