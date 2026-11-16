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
	local rewardSnapshot
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
	local receive = Text("QuestFont", REWARD_ITEMS_ONLY or "You will receive:")
	local choiceLabel = Text("QuestFont", REWARD_CHOICES or "Choose your reward:")
	local id = parent:CreateFontString(nil, "OVERLAY", "QuestFontNormalSmall")
	id:SetJustifyH("RIGHT")
	id:SetWidth(80)
	id:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, -yStart)
	id:SetDrawLayer("OVERLAY", 7)
	-- Fixed reward shelf: independent of the scrolling text and its anchor chain.
	-- This is intentionally plain until native Forever atlas names are verified.
	local footer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	footer:SetFrameLevel(scroll:GetFrameLevel() + 5)
	footer:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, 6)
	footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 6)
	footer:SetHeight(91)
	footer:EnableMouse(false)
	footer:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = {left = 3, right = 3, top = 3, bottom = 3}})
	footer:SetBackdropColor(0.16, 0.09, 0.04, 0.95)
	local footerHeading = footer:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
	footerHeading:SetPoint("TOP", 0, -7)
	footerHeading:SetText(QUEST_REWARDS or "Rewards")
	local rewardCards = {}
	for i = 1, 2 do
		local card = CreateFrame("Frame", nil, footer, "BackdropTemplate")
		card:SetSize(170, 34)
		card:EnableMouse(false)
		card:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9, insets = {left = 2, right = 2, top = 2, bottom = 2}})
		card:SetBackdropColor(0.10, 0.06, 0.025, 0.95)
		card:SetPoint("TOPLEFT", footer, "TOPLEFT", 9 + (i - 1) * 184, -45)
		local icon = card:CreateTexture(nil, "ARTWORK")
		icon:SetSize(28, 28)
		icon:SetPoint("LEFT", 4, 0)
		local value = card:CreateFontString(nil, "ARTWORK", "QuestFont")
		value:SetPoint("LEFT", icon, "RIGHT", 5, 0)
		value:SetJustifyH("LEFT")
		rewardCards[i] = {frame = card, icon = icon, value = value}
	end
	local function UpdateRewardShelf(moneyValue, experienceValue)
		local entries = {}
		if experienceValue > 0 then entries[#entries + 1] = {"XP", tostring(experienceValue)} end
		if moneyValue > 0 then
			-- Coin formatting must not prevent the reward footer from appearing.
			local formatted = tostring(moneyValue) .. " copper"
			if type(GetCoinTextureString) == "function" then
				local ok, value = pcall(GetCoinTextureString, moneyValue)
				if ok and type(value) == "string" and value ~= "" then
					formatted = value
				end
			end
			entries[#entries + 1] = {"", formatted}
		end
		footer:SetShown(#entries > 0)
		for i, card in ipairs(rewardCards) do
			local entry = entries[i]
			card.frame:SetShown(entry ~= nil)
			if entry then
				card.icon:SetTexture(nil)
				card.value:SetText((entry[1] ~= "" and (entry[1] .. "  ") or "") .. entry[2])
			end
		end
		scroll:ClearAllPoints()
		scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -2)
		scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, #entries > 0 and 102 or 2)
	end
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
		UpdateRewardShelf(0, 0)
		for _, region in ipairs(placed) do region:Hide() end
		for _, region in ipairs(regions) do region:Hide() end
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
		-- Forever's leaderboard commonly reports "0/8 Creature slain". Keep the
		-- complete localized text and let the font string wrap as one paragraph.
		-- Parsing and separating the count caused incorrect order and indentation.
		obj.line:SetWidth(width)
		obj.line:SetText(value or "")
		Place(obj.line, i == 1 and 10 or 2)
	end

	local function RewardButton(i, kind, index, name, texture, count)
		local button = buttons[i]
		if not button then
			button = CreateFrame("Button", nil, child, "LargeItemButtonTemplate")
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
		local allowed = not C_QuestLog.ShouldShowQuestRewards or C_QuestLog.ShouldShowQuestRewards(questID)
		-- Reward values must be queried for the currently selected quest on every
		-- render. Do not gate XP/money behind ShouldShowQuestRewards: that flag
		-- can suppress item reward disclosure independently of visible native XP.
		local coins = GetQuestLogRewardMoney() or 0
		local experience = GetQuestLogRewardXP() or 0
		local choices = allowed and (GetNumQuestLogChoices(questID, true) or 0) or 0
		local rewards = allowed and (GetNumQuestLogRewards() or 0) or 0
		rewardSnapshot = { questID = questID, allowed = allowed, choices = choices, rewards = rewards, money = coins, xp = experience }
		UpdateRewardShelf(coins, experience)
		if allowed then
			if choices > 0 or rewards > 0 then
				if choices > 0 then
					Place(choiceLabel, 5)
					AddRewardButtons("choice", choices, 1)
				end
				if rewards > 0 or coins > 0 then
					Place(receive, 8)
				end
				if rewards > 0 then AddRewardButtons("reward", rewards, choices + 1) end
			end
		end
		id:SetText(ns.QuestIDText(questID))
		id:SetShown(ns.GetOption("showQuestID"))
		child:SetHeight(math.max(height + 22, scroll:GetHeight()))
		scroll:UpdateScrollChildRect()
		if reset then scroll:SetVerticalScroll(0) end
	end
	SLASH_WQLP_REWARDS1 = "/wqlprewards"
	SlashCmdList.WQLP_REWARDS = function()
		local info = rewardSnapshot
		if not info then print("WQLP: no quest reward data rendered yet") return end
		print(format("WQLP rewards quest=%s allowed=%s choices=%s items=%s copper=%s xp=%s",
			tostring(info.questID), tostring(info.allowed), tostring(info.choices),
			tostring(info.rewards), tostring(info.money), tostring(info.xp)))
		print("WQLP footer:", "visible=" .. tostring(footer:IsShown()), "height=" .. tostring(footer:GetHeight()), "scrollHeight=" .. tostring(scroll:GetHeight()), "coinHelper=" .. type(GetCoinTextureString))
	end
	return Display
end
