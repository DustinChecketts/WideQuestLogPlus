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
	local titleTag = child:CreateTexture(nil, "ARTWORK")
	titleTag:SetSize(18, 18)
	titleTag:Hide()
	local summary = Text("QuestFont")
	local descriptionHeader = Text("QuestTitleFont", QUEST_DESCRIPTION)
	local description = Text("QuestFont")
	local id = parent:CreateFontString(nil, "OVERLAY", "QuestFontNormalSmall")
	id:SetJustifyH("RIGHT")
	id:SetWidth(80)
	id:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, -6)
	id:SetDrawLayer("OVERLAY", 7)
	-- Quest IDs are metadata, not part of the quest title hierarchy.
	local idFont, idSize, idFlags = id:GetFont()
	if idFont then id:SetFont(idFont, math.max(9, idSize - 2), idFlags) end
	-- Own the footer and its reward buttons; never reparent Blizzard's map frames.
	local footer = CreateFrame("Frame", nil, parent)
	footer:SetFrameLevel(scroll:GetFrameLevel() + 5)
	footer:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
	footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	-- Mirror QuestMapFrame.xml's three native atlas layers. Keep the header and
	-- bottom at their atlas dimensions; only the middle texture stretches.
	local rewardTop = footer:CreateTexture(nil, "BORDER", nil, 1)
	rewardTop:SetAtlas("questlog-reward-header-top", true)
	rewardTop:SetPoint("TOPLEFT", footer, "TOPLEFT")
	rewardTop:SetPoint("TOPRIGHT", footer, "TOPRIGHT")
	local rewardBottom = footer:CreateTexture(nil, "BORDER", nil, 1)
	rewardBottom:SetAtlas("questlog-reward-bottom", true)
	rewardBottom:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT")
	rewardBottom:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT")
	local rewardBackground = footer:CreateTexture(nil, "BACKGROUND")
	rewardBackground:SetAtlas("questlog-reward-tile-vertical")
	rewardBackground:SetPoint("TOPLEFT", rewardTop, "BOTTOMLEFT")
	rewardBackground:SetPoint("RIGHT", footer, "RIGHT")
	rewardBackground:SetPoint("BOTTOM", footer, "BOTTOM")
	-- Native QuestMapFrame.xml uses QuestFont_Huge at -22 with tan text.
	local footerHeading = footer:CreateFontString(nil, "ARTWORK", "QuestFont_Huge")
	footerHeading:SetPoint("TOP", footer, "TOP", 0, -22)
	footerHeading:SetText(QUEST_REWARDS or "Rewards")
	footerHeading:SetTextColor(0.902, 0.788, 0.671)
	local rewardButtons = {}
	local rewardLabels = {}
	local valueCards = {}
	local function RewardLabel(i)
		if not rewardLabels[i] then
			rewardLabels[i] = footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			rewardLabels[i]:SetTextColor(0.902, 0.788, 0.671)
			rewardLabels[i]:SetJustifyH("LEFT")
			rewardLabels[i]:SetWidth(math.max(150, parent:GetWidth() - 34))
			rewardLabels[i]:SetWordWrap(true)
		end
		return rewardLabels[i]
	end
	local function ItemButton(i)
		if not rewardButtons[i] then
			local button = CreateFrame("Button", nil, footer, "LargeQuestRewardItemButtonTemplate")
			button:SetSize(147, 41)
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
			local card = CreateFrame("Frame", nil, footer)
			local textBackground = card:CreateTexture(nil, "BACKGROUND")
			-- Reuse the native quest item name background, not a flat color block.
			textBackground:SetTexture("Interface\\QuestFrame\\UI-QuestItemNameFrame")
			-- Keep the Blizzard name-frame art, but scale its rendered height to
			-- the 32px reward icon instead of the oversized 64px template art.
			textBackground:SetSize(128, 48)
			-- Match the item reward name frame: its visible edge sits beside the icon.
			textBackground:SetPoint("LEFT", card, "LEFT", 21, 0)
			card.text = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			card.text:SetTextColor(1, 1, 1)
			-- Use the client's narrow UI font instead of the parchment quest font.
			local fontPath, fontSize, fontFlags = card.text:GetFont()
			if fontPath then card.text:SetFont("Fonts\\ARIALN.TTF", math.max(fontSize, 14), fontFlags) end
			card.icon = card:CreateTexture(nil, "ARTWORK")
			card.icon:SetSize(32, 32)
			card.icon:SetPoint("LEFT", 0, 0)
			card.text:SetPoint("LEFT", card, "LEFT", 36, 0)
			card.background = textBackground
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
		local row, buttonIndex, labelIndex, valueIndex = 61, 0, 0, 0
		-- Native reward icons are 32px; keep only a small gap between rows.
		local rewardRowHeight = 34
		local available = math.max(190, parent:GetWidth() - 24)
		local cardWidth = math.floor((available - 8) / 2)
		local function AddLabel(value)
			labelIndex = labelIndex + 1
			local label = RewardLabel(labelIndex)
			label:ClearAllPoints()
			label:SetPoint("TOPLEFT", footer, "TOPLEFT", 12, -row)
			label:SetText(value)
			label:Show()
			row = row + math.max(16, label:GetStringHeight() + 3)
		end
		local function AddItems(items)
			for i, reward in ipairs(items) do
				buttonIndex = buttonIndex + 1
				local button = ItemButton(buttonIndex)
				button.reward, button.questID = reward, questID
				button:ClearAllPoints()
				local column = (i - 1) % 2
				button:SetPoint("TOPLEFT", footer, "TOPLEFT", 12 + column * (cardWidth + 6), -row)
				button:SetSize(cardWidth, rewardRowHeight)
				-- Use native name art, with a shorter displayed height to match the map rewards.
				if button.NameFrame then button.NameFrame:SetSize(128, 48) end
				button.Icon:SetSize(32, 32)
				-- Use the available native name-frame space; the old 90px cap forced
				-- extra wrapping even when the reward button had room for two lines.
				button.Name:SetWidth(math.max(1, cardWidth - 43))
				button.Icon:SetTexture(reward.texture)
				button.Name:SetText(reward.name or "")
				button.Name:SetTextColor(1, 1, 1)
			-- LargeQuestRewardItemButtonTemplate supplies the square WhiteIconFrame.
			-- Tint it with Blizzard's item quality colors; never use the generic ring.
			if button.IconBorder then
				local quality = reward.quality
				local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
				if color then
					button.IconBorder:SetVertexColor(color.r, color.g, color.b)
					button.IconBorder:Show()
				else
					button.IconBorder:Hide()
				end
			end
			local nameFont, nameSize, nameFlags = button.Name:GetFont()
			if nameFont and nameSize > 11 then button.Name:SetFont(nameFont, 11, nameFlags) end
				button.Count:SetText((reward.count or 1) > 1 and reward.count or "")
				button:Show()
				if column == 1 or i == #items then row = row + rewardRowHeight end
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
				-- Quest reward money is expressed in copper. Match the native coin
				-- presentation rather than displaying that raw amount as text.
				local gold = math.floor(data.money / 10000)
				local silver = math.floor(data.money / 100) % 100
				local copper = data.money % 100
				local parts = {}
				local function AddCoin(amount, denomination)
					parts[#parts + 1] = amount .. " |TInterface\\MoneyFrame\\UI-" .. denomination .. "Icon:14:14:0:0|t"
				end
				if gold > 0 then AddCoin(gold, "Gold") end
				if silver > 0 then AddCoin(silver, "Silver") end
				if copper > 0 then AddCoin(copper, "Copper") end
				values[#values + 1] = {text = table.concat(parts, " "), money = true}
			end
			for i, value in ipairs(values) do
				valueIndex = valueIndex + 1
				local card = ValueCard(valueIndex)
				card:ClearAllPoints()
				card:SetPoint("TOPLEFT", footer, "TOPLEFT", 12 + (i - 1) * (cardWidth + 6), -row)
				card:SetSize(cardWidth, 34)
				-- The XP name-frame art sits one pixel left of the item name frames.
				card.background:ClearAllPoints()
				card.background:SetPoint("LEFT", card, "LEFT", value.xp and 22 or 21, 0)
				card.text:SetWidth(cardWidth - 58)
				card.text:SetText(value.text)
				card.text:SetTextColor(1, 1, 1)
				if value.xp then
					card.icon:SetTexture("Interface\\Icons\\XP_Icon")
				else
					card.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
				end
				card:Show()
			end
			if #values > 0 then row = row + rewardRowHeight end
			AddItems(data.guaranteed)
		end
		-- Avoid an extra empty strip below the last reward row.
		local footerHeight = hasRewards and row + 2 or 0
		-- Extend the native rewards art through the parchment's lower inset.
		local lowerInset = hasRewards and 16 or 0
		footer:SetHeight(footerHeight + lowerInset)
		local fixed = ns.GetOption("alwaysShowFullRewards")
		if fixed then
			if footer:GetParent() ~= parent then footer:SetParent(parent) end
			footer:SetFrameLevel(scroll:GetFrameLevel() + 5)
			footer:ClearAllPoints()
			footer:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, -lowerInset)
			footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, -lowerInset)
		else
			-- Native-style flow: the same reward controls follow the quest text
			-- inside the scroll child rather than occupying a separate viewport.
			if footer:GetParent() ~= child then footer:SetParent(child) end
			footer:SetFrameLevel(child:GetFrameLevel() + 1)
			footer:ClearAllPoints()
			footer:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -((contentHeight or 0) + 18))
			footer:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -((contentHeight or 0) + 18))
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
			height = height + (gap or 0)
		else
			height = yStart
		end
		-- Fixed parchment margin: title icon indentation must not propagate.
		region:SetPoint("TOPLEFT", child, "TOPLEFT", x, -height)
		region:Show()
		height = height + region:GetHeight()
		last = region
		placed[#placed + 1] = region
	end
	local function Clear()
		UpdateRewardShelf(nil, {choices = {}, guaranteed = {}, money = 0, xp = 0})
		for _, region in ipairs(placed) do region:Hide() end
		for _, region in ipairs(regions) do region:Hide() end
		titleTag:Hide()
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
		title:SetWidth(width)
		title:SetText(C_QuestLog.GetTitleForQuestID(questID) or "")
		Place(title)
		local tagInfo = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
		local tagAtlas = tagInfo and type(QuestUtils_GetQuestTagAtlas) == "function"
			and QuestUtils_GetQuestTagAtlas(tagInfo.tagID)
		if tagAtlas then
			titleTag:SetAtlas(tagAtlas)
			titleTag:ClearAllPoints()
			titleTag:SetPoint("TOPLEFT", child, "TOPLEFT", x, -yStart - 2)
			titleTag:Show()
			title:ClearAllPoints()
			title:SetPoint("TOPLEFT", child, "TOPLEFT", x + 24, -yStart)
			title:SetWidth(width - 24)
			height = yStart + title:GetHeight()
		else
			title:SetWidth(width)
		end
		if objectivesValue and objectivesValue ~= "" then
			summary:SetText(objectivesValue)
			Place(summary, 8)
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
