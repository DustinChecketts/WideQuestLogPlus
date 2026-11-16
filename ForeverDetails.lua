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
	local id = parent:CreateFontString(nil, "OVERLAY", "QuestFontNormalSmall")
	id:SetJustifyH("RIGHT")
	id:SetWidth(80)
	id:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, -6)
	id:SetDrawLayer("OVERLAY", 7)
	-- Own the footer and its reward buttons; never reparent Blizzard's map frames.
	local footer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	footer:SetFrameLevel(scroll:GetFrameLevel() + 5)
	footer:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, 6)
	footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 6)
	footer:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = {left = 3, right = 3, top = 3, bottom = 3}})
	footer:SetBackdropColor(0.16, 0.09, 0.04, 0.95)
	local footerHeading = footer:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
	footerHeading:SetPoint("TOP", 0, -7)
	footerHeading:SetText(QUEST_REWARDS or "Rewards")
	local rewardButtons = {}
	local rewardLabels = {}
	local valueCards = {}
	local function RewardLabel(i)
		if not rewardLabels[i] then
			rewardLabels[i] = footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
			rewardLabels[i]:SetJustifyH("LEFT")
			rewardLabels[i]:SetWidth(math.max(150, parent:GetWidth() - 34))
			rewardLabels[i]:SetWordWrap(true)
		end
		return rewardLabels[i]
	end
	local function ItemButton(i)
		if not rewardButtons[i] then
			local button = CreateFrame("Button", nil, footer, "LargeItemButtonTemplate")
			button:SetSize(147, 37)
			button:SetScript("OnEnter", function(self)
				if not self.reward then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				C_QuestLog.SetSelectedQuest(self.questID)
				if self.reward.kind == "currency" then
					GameTooltip:SetQuestLogCurrency(self.reward.type, self.reward.index)
				else
					GameTooltip:SetQuestLogItem(self.reward.type, self.reward.index)
				end
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			button:SetScript("OnClick", function(self)
				if not self.reward or self.reward.kind ~= "item" or not IsModifiedClick("CHATLINK") then return end
				C_QuestLog.SetSelectedQuest(self.questID)
				local link = GetQuestLogItemLink(self.reward.type, self.reward.index)
				if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
			end)
			rewardButtons[i] = button
		end
		return rewardButtons[i]
	end
	local function ValueCard(i)
		if not valueCards[i] then
			local card = CreateFrame("Frame", nil, footer, "BackdropTemplate")
			card:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 9, insets = {left = 2, right = 2, top = 2, bottom = 2}})
			card:SetBackdropColor(0.10, 0.06, 0.025, 0.95)
			card.text = card:CreateFontString(nil, "ARTWORK", "QuestFont")
			card.icon = card:CreateTexture(nil, "ARTWORK")
			card.icon:SetSize(28, 28)
			card.icon:SetPoint("LEFT", 3, 0)
			card.text:SetPoint("LEFT", card.icon, "RIGHT", 5, 0)
			card.text:SetJustifyH("LEFT")
			valueCards[i] = card
		end
		return valueCards[i]
	end
	local function GetRewardData(questID, allowed, money, xp)
		local data = {choices = {}, guaranteed = {}, money = money, xp = xp}
		if not allowed then return data end
		local itemIndex, currencyIndex = 0, 0
		for i = 1, GetNumQuestLogChoices(questID, true) or 0 do
			local isCurrency = type(GetQuestLogChoiceInfoLootType) == "function" and GetQuestLogChoiceInfoLootType(i) == 1
			local reward
			if isCurrency and C_QuestLog.GetQuestRewardCurrencyInfo then
				currencyIndex = currencyIndex + 1
				local info = C_QuestLog.GetQuestRewardCurrencyInfo(questID, i, true)
				if info then reward = {kind = "currency", type = "choice", index = currencyIndex, name = info.name, texture = info.texture, count = info.totalRewardAmount} end
			else
				itemIndex = itemIndex + 1
				local name, texture, count, quality = GetQuestLogChoiceInfo(i)
				reward = {kind = "item", type = "choice", index = itemIndex, name = name, texture = texture, count = count, quality = quality}
			end
			if reward then data.choices[#data.choices + 1] = reward end
		end
		for i = 1, GetNumQuestLogRewards() or 0 do
			local name, texture, count, quality = GetQuestLogRewardInfo(i)
			data.guaranteed[#data.guaranteed + 1] = {kind = "item", type = "reward", index = i, name = name, texture = texture, count = count, quality = quality}
		end
		if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies then
			for i, info in ipairs(C_QuestInfoSystem.GetQuestRewardCurrencies(questID) or {}) do
				data.guaranteed[#data.guaranteed + 1] = {kind = "currency", type = "reward", index = i, name = info.name, texture = info.texture, count = info.totalRewardAmount}
			end
		end
		return data
	end
	local function UpdateRewardShelf(questID, data, contentHeight)
		for _, button in ipairs(rewardButtons) do button:Hide() button.reward = nil end
		for _, label in ipairs(rewardLabels) do label:Hide() end
		for _, card in ipairs(valueCards) do card:Hide() end
		local hasRewards = #data.choices > 0 or #data.guaranteed > 0 or data.money > 0 or data.xp > 0
		footer:SetShown(hasRewards)
		local row, buttonIndex, labelIndex, valueIndex = 29, 0, 0, 0
		local available = math.max(190, parent:GetWidth() - 34)
		local cardWidth = math.floor((available - 8) / 2)
		local function AddLabel(value)
			labelIndex = labelIndex + 1
			local label = RewardLabel(labelIndex)
			label:ClearAllPoints()
			label:SetPoint("TOPLEFT", footer, "TOPLEFT", 12, -row)
			label:SetText(value)
			label:Show()
			row = row + math.max(15, label:GetStringHeight() + 3)
		end
		local function AddItems(items)
			for i, reward in ipairs(items) do
				buttonIndex = buttonIndex + 1
				local button = ItemButton(buttonIndex)
				button.reward, button.questID = reward, questID
				button:ClearAllPoints()
				local column = (i - 1) % 2
				button:SetPoint("TOPLEFT", footer, "TOPLEFT", 12 + column * (cardWidth + 6), -row)
				button:SetWidth(cardWidth)
				button.Icon:SetTexture(reward.texture)
				button.Name:SetText(reward.name or "")
				button.Name:SetTextColor(1, 1, 1)
				button.Count:SetText((reward.count or 1) > 1 and reward.count or "")
				button:Show()
				if column == 1 or i == #items then row = row + 39 end
			end
		end
		if #data.choices > 0 then
			AddLabel(#data.choices == 1 and (REWARD_ITEMS_ONLY or "You will receive:") or (REWARD_CHOICES or "Choose your reward:"))
			AddItems(data.choices)
		end
		if #data.guaranteed > 0 or data.money > 0 or data.xp > 0 then
			AddLabel(#data.choices > 0 and (REWARD_ITEMS or "You will also receive:") or (REWARD_ITEMS_ONLY or "You will receive:"))
			local values = {}
			if data.xp > 0 then values[#values + 1] = {text = BreakUpLargeNumbers(data.xp), xp = true} end
			if data.money > 0 then
				local formatted = tostring(data.money) .. " copper"
				if type(GetCoinTextureString) == "function" then
					local ok, value = pcall(GetCoinTextureString, data.money)
					if ok and type(value) == "string" and value ~= "" then formatted = value end
				end
				values[#values + 1] = {text = formatted, money = true}
			end
			for i, value in ipairs(values) do
				valueIndex = valueIndex + 1
				local card = ValueCard(valueIndex)
				card:ClearAllPoints()
				card:SetPoint("TOPLEFT", footer, "TOPLEFT", 12 + (i - 1) * (cardWidth + 6), -row)
				card:SetSize(cardWidth, 33)
				card.text:SetText(value.text)
				if value.xp then
					card.icon:SetTexture("Interface\\Icons\\XP_Icon")
				else
					card.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
				end
				card:Show()
			end
			if #values > 0 then row = row + 36 end
			AddItems(data.guaranteed)
		end
		local footerHeight = hasRewards and row + 8 or 0
		footer:SetHeight(footerHeight)
		local fixed = ns.GetOption("alwaysShowFullRewards")
		if fixed then
			if footer:GetParent() ~= parent then footer:SetParent(parent) end
			footer:SetFrameLevel(scroll:GetFrameLevel() + 5)
			footer:ClearAllPoints()
			footer:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, 6)
			footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 6)
		else
			-- Native-style flow: the same reward controls follow the quest text
			-- inside the scroll child rather than occupying a separate viewport.
			if footer:GetParent() ~= child then footer:SetParent(child) end
			footer:SetFrameLevel(child:GetFrameLevel() + 1)
			footer:ClearAllPoints()
			footer:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -((contentHeight or 0) + 18))
			footer:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4, -(height + 18))
		end
		scroll:ClearAllPoints()
		scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -2)
		scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, fixed and hasRewards and footerHeight + 10 or 2)
		return fixed, footerHeight
	end
	local objectives = {}
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
		UpdateRewardShelf(nil, {choices = {}, guaranteed = {}, money = 0, xp = 0})
		for _, region in ipairs(placed) do region:Hide() end
		for _, region in ipairs(regions) do region:Hide() end
		id:Hide()
		for _, obj in ipairs(objectives) do
			obj.line:Hide()
			obj.count:Hide()
		end
		
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
		local coins = GetQuestLogRewardMoney() or 0
		local experience = GetQuestLogRewardXP() or 0
		local rewardData = GetRewardData(questID, allowed, coins, experience)
		rewardSnapshot = {
			questID = questID, allowed = allowed, choices = #rewardData.choices,
			rewards = #rewardData.guaranteed, money = coins, xp = experience,
		}
		local fixed, footerHeight = UpdateRewardShelf(questID, rewardData, height)
		id:SetText(ns.QuestIDText(questID))
		id:SetShown(ns.GetOption("showQuestID"))
		child:SetHeight(math.max(height + (not fixed and footerHeight > 0 and footerHeight + 28 or 22), scroll:GetHeight()))
		scroll:UpdateScrollChildRect()
		-- Always start at the title when selecting a quest.\n\t\tscroll:SetVerticalScroll(0)
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
