local ADDON_NAME, ns = ...

-- WoW Forever (1.60+, game type "Camelot") dropped the classic QuestLogFrame: the quest log key opens
-- the retail-style quest list docked inside the world map instead. There's nothing left to widen, so
-- this file builds the two-pane quest log as a window of its own, in the shared layout (Layout.lua),
-- and routes the quest log key, the micro menu button and the objective tracker to it.
-- Clients that still have the classic quest log are handled by Legacy.lua
if (QuestLogFrame or not (C_QuestLog and C_QuestLog.GetInfo and QuestInfo_Display and QUEST_TEMPLATE_LOG)) then
	return
end

-- Taint: the window is the addon's own, unprotected frame, so showing it, hiding it and everything in
-- it is fine in combat. What Blizzard's code sees of it:
--  * ToggleQuestLog() and QuestMapFrame_OpenToQuestDetails() are replaced (see the end of the file).
--    Their callers - the key binding, the micro menu button and a click on a quest in the objective
--    tracker - call them last thing, so the taint goes no further than that one keypress or click.
--  * QuestInfo_Display() is Blizzard's own detail renderer, shared with the quest giver window, so it
--    is only ever called while neither that nor the map's details are using it (QuestInfoInUseElsewhere).
--    Each caller sets up everything it reads before using it, so nothing from here carries over. A
--    hooksecurefunc() on it puts the shared objective lines and reward values back Blizzard's way after
--    anyone else uses them; hooks like that run after Blizzard's code without tainting it.
--  * The window's name goes in UISpecialFrames so Escape closes it. Blizzard reads that list through
--    securecall(), which keeps the taint from going any further.

local L = ns.Layout
local BASE_WIDTH, BASE_HEIGHT, PANE_TOP, ROW_HEIGHT = L.BASE_WIDTH, L.BASE_HEIGHT, L.PANE_TOP, L.ROW_HEIGHT
local DEFAULT_POINT = {"TOPLEFT", "UIParent", "TOPLEFT", 0, -104}

local selectedQuestID -- The quest shown in the details
local scrollToQuestID -- A quest opened from elsewhere, to bring into view in the list
local currentHeight

local UpdateAll, ShowQuest, RequestUpdate

---------------------------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "WideQuestLogPlusFrame", UIParent)
frame:Hide()
frame:SetSize(BASE_WIDTH, BASE_HEIGHT)
frame:SetPoint(unpack(DEFAULT_POINT))
frame:SetFrameStrata("MEDIUM")
frame:SetToplevel(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
tinsert(UISpecialFrames, frame:GetName())

-- Book icon behind the portrait ring of the art
local bookIcon = frame:CreateTexture(nil, "BACKGROUND")
bookIcon:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon")
bookIcon:SetSize(64, 64)
bookIcon:SetPoint("TOPLEFT", 4, -4)

local LayoutArt = ns.CreateWindowArt(frame)

local windowTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
windowTitle:SetPoint("TOP", 0, -17)
windowTitle:SetText(QUEST_LOG)

local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
closeButton:SetPoint("CENTER", frame, "TOPRIGHT", -46, -24)
closeButton:SetScript("OnClick", function()
	frame:Hide()
end)

local questCount = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
questCount:SetPoint("RIGHT", frame, "TOPRIGHT", -52, -53)

-- Moved by dragging its title bar
frame:SetScript("OnDragStart", function(self)
	local _, y = GetCursorPosition()
	if ((self:GetTop() - y / self:GetEffectiveScale()) <= PANE_TOP) then
		self:StartMoving()
	end
end)
frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relativePoint, x, y = self:GetPoint(1)
	ns.GetDB().point = {point, "UIParent", relativePoint, x, y}
end)

---------------------------------------------------------------------------------------------------
-- Tracking, and Questie
---------------------------------------------------------------------------------------------------

-- Questie's tracker keeps its own list of tracked quests and only learns about new ones through
-- C_QuestLog.AddQuestWatch(). The client's automatic watch on accepting a quest bypasses that, so a
-- quest can be watched by Blizzard yet missing from Questie's tracker. And Questie's tracker only shows
-- quests in its database, which much of WoW Forever's new content isn't yet. So while Questie's
-- tracker is in charge, a quest counts as tracked only if Questie's tracker shows it
local questieTracker, questiePlayer

local function ImportQuestieModule(name)
	if (not QuestieLoader) then
		return
	end
	local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
	return ok and type(module) == "table" and module or nil
end

-- Returns Questie's tracker if it's in charge of this quest, false if it's in charge but can't show
-- the quest, or nil if Blizzard's tracker is in charge
local function TrackerFor(questID)
	if (not (Questie and Questie.db and Questie.db.profile and Questie.db.profile.trackerEnabled)) then
		return nil
	end
	questieTracker = questieTracker or ImportQuestieModule("QuestieTracker")
	questiePlayer = questiePlayer or ImportQuestieModule("QuestiePlayer")
	if (not (questieTracker and questieTracker.IsTrackedByQuestie and questiePlayer)) then
		return nil
	end
	local log = questiePlayer.currentQuestlog
	return (log and log[questID] ~= nil) and questieTracker or false
end

local function CanTrack(questID)
	return TrackerFor(questID) ~= false
end

local function IsTracked(questID)
	local tracker = TrackerFor(questID)
	if (tracker) then
		return tracker.IsTrackedByQuestie(questID) and true or false
	elseif (tracker == false) then
		return false
	end
	return QuestUtils_IsQuestWatched(questID)
end

local warnedUntrackable = {}
local function ToggleTracking(questID)
	local tracker = TrackerFor(questID)
	if (tracker == false) then
		if (not warnedUntrackable[questID]) then
			warnedUntrackable[questID] = true
			ns.Print(format("Questie's tracker can't show %s because the quest is missing from Questie's database.",
				GetQuestLink(questID) or C_QuestLog.GetTitleForQuestID(questID) or questID))
		end
		UIErrorsFrame:AddMessage("Questie can't track this quest yet", 1.0, 0.1, 0.1, 1.0)
		return
	end

	local watched = QuestUtils_IsQuestWatched(questID)
	if (IsTracked(questID)) then
		if (tracker and not watched) then
			tracker:UntrackQuestId(questID)
		elseif (QuestUtil.CanRemoveQuestWatch()) then
			C_QuestLog.RemoveQuestWatch(questID) -- Also untracks it in Questie
		end
	elseif (not watched and C_QuestLog.GetNumQuestWatches() >= Constants.QuestWatchConsts.MAX_QUEST_WATCHES) then
		UIErrorsFrame:AddMessage(OBJECTIVES_WATCH_TOO_MANY, 1.0, 0.1, 0.1, 1.0)
	else
		-- Adding a watch that already exists is harmless, and is what tells Questie to track it
		C_QuestLog.AddQuestWatch(questID)
	end
	RequestUpdate()
end

---------------------------------------------------------------------------------------------------
-- Quest list (left pane)
---------------------------------------------------------------------------------------------------

local listBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
listBox:SetPoint("TOPLEFT", L.LIST_LEFT, -PANE_TOP)
listBox:SetWidth(L.LIST_WIDTH)

local listBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
listBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 8, -4)
listBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 8, 4)

local noQuestsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
noQuestsText:SetPoint("TOP", listBox, "TOP", 0, -90)
noQuestsText:SetText(QUESTLOG_NO_QUESTS_TEXT)
noQuestsText:Hide()

local PLUS_TEXTURE = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS_TEXTURE = "Interface\\Buttons\\UI-MinusButton-Up"
local TITLE_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"

local function ToggleHeader(questLogIndex)
	local info = C_QuestLog.GetInfo(questLogIndex)
	if (not info) then
		return
	end
	if (info.isCollapsed) then
		ExpandQuestHeader(questLogIndex)
	else
		CollapseQuestHeader(questLogIndex)
	end
	RequestUpdate()
end

-- Every zone starts the session open; collapsing one only lasts until the next login or reload
local function ExpandAllHeaders()
	for index = C_QuestLog.GetNumQuestLogEntries(), 1, -1 do
		local info = C_QuestLog.GetInfo(index)
		if (info and info.isHeader and info.isCollapsed) then
			ExpandQuestHeader(index)
		end
	end
end

-- The tag at the right of a quest's row: (Failed), (Complete), or its type
local function GetQuestTag(questID)
	if (C_QuestLog.IsFailed(questID)) then
		return FAILED
	elseif (C_QuestLog.IsComplete(questID)) then
		return COMPLETE
	end
	local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
	if (tagInfo and tagInfo.tagName) then
		return tagInfo.tagName
	elseif (C_QuestLog.IsEliteQuest(questID)) then
		return ELITE
	end
end

local function ColorRow(row, highlighted)
	local data = row.data
	if (not data) or data.isSpacer then
		return
	end
	local color, highlight
	if (data.isHeader) then
		color, highlight = QuestDifficultyColors.header, QuestDifficultyHighlightColors.header
	else
		color, highlight = GetQuestDifficultyColor(data.difficultyLevel or data.level, data.isScaling, data.questID)
	end
	local text = (highlighted or (data.questID and data.questID == selectedQuestID)) and highlight or color
	row.Text:SetTextColor(text.r, text.g, text.b)
	row.Tag:SetTextColor(text.r, text.g, text.b)
	row.Highlight:SetVertexColor(color.r, color.g, color.b)
	row.Selected:SetVertexColor(color.r, color.g, color.b)
end

local function OpenQuestMenu(row)
	local questID = row.data.questID
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateButton(IsTracked(questID) and UNTRACK_QUEST or TRACK_QUEST, function()
			ToggleTracking(questID)
		end):SetEnabled(CanTrack(questID))
		root:CreateButton(SHARE_QUEST, function()
			QuestMapQuestOptions_ShareQuest(questID)
		end):SetEnabled(C_QuestLog.IsPushableQuest(questID) and IsInGroup())
		if (C_QuestLog.CanAbandonQuest(questID)) then
			root:CreateButton(ABANDON_QUEST, function()
				QuestMapQuestOptions_AbandonQuest(questID)
			end)
		end
	end)
end

local function Row_OnClick(self, button)
	local data = self.data
	if (not data) or data.isSpacer then
		return
	end

	if (data.isHeader) then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ToggleHeader(data.questLogIndex)
	elseif (ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID(data.questID)) then
		return -- Shift-click with a chat box open links the quest
	elseif (IsShiftKeyDown()) then
		ToggleTracking(data.questID) -- Otherwise it toggles tracking, as in Classic
	elseif (button == "RightButton") then
		OpenQuestMenu(self)
	else
		PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
		ShowQuest(data.questID)
	end
end

local function Row_OnEnter(self)
	ColorRow(self, true)
end

local function Row_OnLeave(self)
	ColorRow(self, false)
end

local function SetupRow(row)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("LEFT", 3, 0)

	row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)

	row.Tag = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Tag:SetPoint("RIGHT", -2, 0)
	row.Tag:SetJustifyH("RIGHT")

	row.Check = row:CreateTexture(nil, "ARTWORK")
	row.Check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	row.Check:SetSize(16, 16)
	row.Check:SetPoint("LEFT", L.CHECK_X, 0)
	row.Check:SetVertexColor(64 / 255, 224 / 255, 208 / 255)

	row.Selected = row:CreateTexture(nil, "BACKGROUND")
	row.Selected:SetTexture(TITLE_HIGHLIGHT)
	row.Selected:SetBlendMode("ADD")
	row.Selected:SetAllPoints()

	row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.Highlight:SetTexture(TITLE_HIGHLIGHT)
	row.Highlight:SetBlendMode("ADD")
	row.Highlight:SetAllPoints()

	row:SetScript("OnClick", Row_OnClick)
	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", Row_OnLeave)
end

-- Rows are recycled between zone headers, quests and the blank spacers above headers, so each one is
-- set up from scratch for whatever it's showing now
local function InitRow(row, data)
	if (not row.Text) then
		SetupRow(row)
	end
	row.data = data

	row.Text:SetWidth(0)
	row.Tag:SetText(nil)
	row.Check:Hide()
	row:EnableMouse(not data.isSpacer)

	if (data.isSpacer) then
		row.Icon:Hide()
		row.Text:SetText(nil)
		row.Selected:Hide()
		return
	end

	if (data.isHeader) then
		row.Text:SetPoint("LEFT", L.HEADER_TEXT_X, 0)
		row.Icon:SetTexture(data.isCollapsed and PLUS_TEXTURE or MINUS_TEXTURE)
		row.Icon:Show()
		row.Text:SetText(data.title)
		row.Selected:Hide()
	else
		local questID = data.questID
		local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
		local elite = C_QuestLog.IsEliteQuest(questID) or (tagInfo and tagInfo.isElite)
		row.Text:SetPoint("LEFT", L.QUEST_TEXT_X, 0)
		row.Icon:Hide()
		row.Text:SetText(ns.LevelTitle(data.difficultyLevel or data.level, data.title, ns.QuestSuffix(tagInfo and tagInfo.tagID, elite)))

		local tag = GetQuestTag(questID)
		if (tag) then
			row.Tag:SetText(PARENS_TEMPLATE and PARENS_TEMPLATE:format(tag) or ("(" .. tag .. ")"))
		end

		-- Shorten the title if it would run into the tag
		local room = L.LIST_WIDTH - L.QUEST_TEXT_X - (tag and (row.Tag:GetStringWidth() + 6) or 2)
		if (row.Text:GetStringWidth() > room) then
			row.Text:SetWidth(room)
		end
		row.Check:SetShown(IsTracked(questID))
		row.Selected:SetShown(questID == selectedQuestID)
	end

	ColorRow(row, row:IsMouseOver())
end

local listView = CreateScrollBoxListLinearView()
listView:SetElementExtentCalculator(function(_, data)
	return data.isSpacer and L.HEADER_GAP or ROW_HEIGHT
end)
listView:SetElementInitializer("Button", InitRow)
ScrollUtil.InitScrollBoxListWithScrollBar(listBox, listBar, listView)

-- Collapse or expand every zone at once, like the classic "All" toggle
local collapseAll = CreateFrame("Button", nil, frame)
collapseAll:SetSize(60, 16)
collapseAll:SetPoint("TOPLEFT", 74, -45)
collapseAll.Icon = collapseAll:CreateTexture(nil, "ARTWORK")
collapseAll.Icon:SetSize(16, 16)
collapseAll.Icon:SetPoint("LEFT")
collapseAll:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
collapseAll:GetHighlightTexture():ClearAllPoints()
collapseAll:GetHighlightTexture():SetAllPoints(collapseAll.Icon)
collapseAll.Text = collapseAll:CreateFontString(nil, "ARTWORK", "GameFontNormal")
collapseAll.Text:SetPoint("LEFT", collapseAll.Icon, "RIGHT", 2, 0)
collapseAll.Text:SetText(ALL)
collapseAll:SetScript("OnClick", function(self)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	local collapse = not self.allCollapsed
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if (info and info.isHeader and info.isCollapsed ~= collapse) then
			if (collapse) then
				CollapseQuestHeader(index)
			else
				ExpandQuestHeader(index)
			end
		end
	end
	RequestUpdate()
end)

---------------------------------------------------------------------------------------------------
-- Quest details (right pane)
---------------------------------------------------------------------------------------------------

-- QuestInfo_Display() expects the scroll child's grandparent to carry the quest ID and the seal
-- texture, the same arrangement as Blizzard's QuestLogPopupDetailFrame. It covers the parchment
local detail = CreateFrame("Frame", nil, frame)
detail:SetPoint("TOPLEFT", L.PARCHMENT_LEFT, -(PANE_TOP - 2))
detail:SetWidth(L.PARCHMENT_RIGHT - L.PARCHMENT_LEFT)

detail.SealMaterialBG = detail:CreateTexture(nil, "BACKGROUND")
detail.SealMaterialBG:SetAllPoints()
detail.SealMaterialBG:Hide()

-- Shown over the parchment when the accessibility "Quest Text Contrast" option is on
detail.ContrastBG = detail:CreateTexture(nil, "BACKGROUND", nil, -1)
detail.ContrastBG:SetAllPoints()
detail.ContrastBG:Hide()

-- The scroll bar sits in the slot to the right of the parchment
local detailScroll = CreateFrame("ScrollFrame", nil, detail, "ScrollFrameTemplate")
detailScroll:SetPoint("TOPLEFT", 0, -2)
detailScroll:SetPoint("BOTTOMRIGHT", 0, 2)
local scrollBarX = (L.DETAIL_SCROLL_SLOT_X - 4) - L.PARCHMENT_RIGHT
detailScroll.ScrollBar:ClearAllPoints()
detailScroll.ScrollBar:SetPoint("TOPLEFT", detailScroll, "TOPRIGHT", scrollBarX, -4)
detailScroll.ScrollBar:SetPoint("BOTTOMLEFT", detailScroll, "BOTTOMRIGHT", scrollBarX, 4)

local detailChild = CreateFrame("Frame", nil, detailScroll)
detailChild:SetSize(L.PARCHMENT_RIGHT - L.PARCHMENT_LEFT, 300)
detailScroll:SetScrollChild(detailChild)

-- The quest giver window and Blizzard's own quest detail panes use the same QuestInfo elements as this
-- one. Taking them while one of those is open would blank it (mid turn-in, say), so wait until it closes
local function QuestInfoInUseElsewhere()
	if (QuestFrame and QuestFrame:IsShown()) or (QuestLogPopupDetailFrame and QuestLogPopupDetailFrame:IsShown()) then
		return true
	end
	local mapDetails = QuestMapFrame and QuestMapFrame.DetailsFrame
	return (mapDetails and mapDetails:IsVisible()) and true or false
end

-- The quest ID, right-aligned under the rewards (or whatever comes last), in the description's colour
local questIDRow = CreateFrame("Frame", nil, detailChild)
questIDRow:SetSize(L.CONTENT_WIDTH, 14)
questIDRow.Text = questIDRow:CreateFontString(nil, "ARTWORK", "QuestFontNormalSmall")
questIDRow.Text:SetPoint("RIGHT")
questIDRow.Text:SetJustifyH("RIGHT")

local function QuestInfo_ShowQuestID()
	ns.StyleQuestID(questIDRow.Text, C_QuestLog.GetSelectedQuest(), QuestInfoDescriptionText)
	questIDRow:Show()
	return questIDRow
end

-- Blizzard's QUEST_TEMPLATE_LOG lays out the description, objectives and rewards in one column, as
-- Classic did. A copy of it is placed and spaced to the shared layout, with the quest ID added at the end
local LOG_TEMPLATE = CopyTable(QUEST_TEMPLATE_LOG)
LOG_TEMPLATE.contentWidth = L.CONTENT_WIDTH
do
	local elements = LOG_TEMPLATE.elements
	for index = 1, #elements, 3 do
		local show = elements[index]
		if (show == QuestInfo_ShowTitle) then
			elements[index + 1] = L.CONTENT_LEFT - L.PARCHMENT_LEFT
			elements[index + 2] = -(L.CONTENT_TOP - PANE_TOP)
		elseif (show == QuestInfo_ShowObjectivesText) then
			elements[index + 2] = -L.TITLE_GAP
		elseif (show == QuestInfo_ShowDescriptionText) then
			elements[index + 2] = -L.TITLE_GAP
		elseif (show == QuestInfo_ShowDescriptionHeader) then
			elements[index + 2] = -L.DESCRIPTION_GAP
		elseif (show == QuestInfo_ShowRewards) then
			elements[index + 2] = -L.REWARDS_GAP
		end
	end
	for index = 1, #elements, 3 do
		if (elements[index] == QuestInfo_ShowSpacer) then
			tinsert(elements, index, -L.QUEST_ID_GAP)
			tinsert(elements, index, 0)
			tinsert(elements, index, QuestInfo_ShowQuestID)
			break
		end
	end
end

-- The quest giver window and the map's quest details use the same objective lines and reward frames,
-- laid out Blizzard's way, so they go back to Blizzard's font and positions, without this addon's
-- count column, whenever anything else displays quest info
local function RestoreSharedLayout(_, parentFrame)
	if (parentFrame == detailChild) then
		return
	end
	ns.ClearObjectiveCounts()
	for _, line in ipairs(QuestInfoObjectivesFrame.Objectives or {}) do
		local r, g, b, a = line:GetTextColor()
		line:SetFontObject(QuestFontNormalSmall)
		line:SetTextColor(r, g, b, a)
	end
	local rewardsFrame = QuestInfoRewardsFrame
	rewardsFrame.MoneyFrame:ClearAllPoints()
	rewardsFrame.MoneyFrame:SetPoint("LEFT", rewardsFrame.ItemReceiveText, "RIGHT", 15, 0)
	rewardsFrame.XPFrame.ValueText:ClearAllPoints()
	rewardsFrame.XPFrame.ValueText:SetPoint("LEFT", rewardsFrame.XPFrame.ReceiveText, "RIGHT", 15, 0)
end
hooksecurefunc("QuestInfo_Display", RestoreSharedLayout)

local function DisplayDetails(resetScroll)
	detailScroll:SetShown(selectedQuestID ~= nil)
	if (not selectedQuestID) or QuestInfoInUseElsewhere() then
		return
	end

	C_QuestLog.SetSelectedQuest(selectedQuestID)
	detail.questID = selectedQuestID

	if (QuestTextContrast and QuestTextContrast.IsEnabled()) then
		detail.ContrastBG:SetAtlas(QuestTextContrast.GetDefaultBackgroundAtlas())
		detail.ContrastBG:Show()
	else
		detail.ContrastBG:Hide()
	end

	QuestInfo_Display(LOG_TEMPLATE, detailChild)

	-- Just the quest's name: Blizzard decorates it with the quest type's icon, and that and the level
	-- are already in the list
	local title = C_QuestLog.GetTitleForQuestID(selectedQuestID)
	if (title) then
		if (IsCurrentQuestFailed()) then
			title = (QUEST_TITLE_FORMAT_FAILED or "%s - (Failed)"):format(title)
		end
		QuestInfoTitleHeader:SetText(title)
	end

	-- Objective lines: check, name and a right-aligned count. Blizzard's lines follow the leaderboard,
	-- skipping spell and log objectives, after an optional waypoint line
	ns.ClearObjectiveCounts()
	local lines = QuestInfoObjectivesFrame.Objectives
	local lineIndex = C_QuestLog.GetNextWaypointText(selectedQuestID) and 1 or 0
	for index = 1, GetNumQuestLeaderBoards() do
		local text, objectiveType, finished = GetQuestLogLeaderBoard(index)
		if (objectiveType ~= "spell" and objectiveType ~= "log") then
			lineIndex = lineIndex + 1
			local line = lines and lines[lineIndex]
			if (line and line:IsShown()) then
				ns.StyleObjective(line, (text and text ~= "") and text or objectiveType, finished, L.CONTENT_WIDTH, QuestInfoDescriptionText)
			end
		end
	end

	-- Gold and experience right-aligned to the text column (see RestoreSharedLayout)
	local rewardsFrame = QuestInfoRewardsFrame
	rewardsFrame.MoneyFrame:ClearAllPoints()
	rewardsFrame.MoneyFrame:SetPoint("RIGHT", rewardsFrame.ItemReceiveText, "LEFT", L.CONTENT_WIDTH + L.MONEY_RIGHT_PADDING, 0)
	rewardsFrame.XPFrame.ValueText:ClearAllPoints()
	rewardsFrame.XPFrame.ValueText:SetPoint("RIGHT", rewardsFrame.XPFrame, "LEFT", L.CONTENT_WIDTH, 0)

	-- The same blank line under the Rewards heading. Blizzard hangs the first reward line just under
	-- the heading and sizes the rewards block to fit, so move that line down and grow the block to match
	local rewards = QuestInfoFrame.rewardsFrame
	local first = rewards and rewards:IsShown() and rewards.activeRewardElements and rewards.activeRewardElements[1]
	if (first and first:GetNumPoints() > 0) then
		local point, relativeTo, relativePoint, x = first:GetPoint(1)
		if (relativeTo == rewards.Header) then
			first:SetPoint(point, relativeTo, relativePoint, x, -L.TITLE_GAP)
			rewards:SetHeight(rewards:GetHeight() + L.EXTRA_HEADING_GAP)
		end
	end

	-- A blank line between the money and experience lines, again growing the rewards block to match
	local xpFrame = rewards and rewards:IsShown() and rewards.XPFrame
	if (xpFrame and xpFrame:IsShown() and xpFrame:GetNumPoints() > 0) then
		local point, relativeTo, relativePoint, x, y = xpFrame:GetPoint(1)
		if (relativeTo == rewards.ItemReceiveText) then
			xpFrame:SetPoint(point, relativeTo, relativePoint, x, y - L.MONEY_XP_GAP)
			rewards:SetHeight(rewards:GetHeight() + L.MONEY_XP_GAP)
		end
	end

	detailScroll:UpdateScrollChildRect()
	if (resetScroll) then
		detailScroll:SetVerticalScroll(0)
	end
end

---------------------------------------------------------------------------------------------------
-- Buttons along the bottom
---------------------------------------------------------------------------------------------------

local function CreateBottomButton(text, width, onClick)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(width or L.BUTTON_WIDTH, L.BUTTON_HEIGHT)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function ForSelectedQuest(action)
	return function()
		if (selectedQuestID) then
			action(selectedQuestID)
		end
	end
end

local abandonButton = CreateBottomButton(ABANDON_QUEST, 125, ForSelectedQuest(QuestMapQuestOptions_AbandonQuest))
abandonButton:SetPoint("BOTTOMLEFT", L.BUTTON_LEFT, L.BUTTON_BOTTOM)

local exitButton = CreateBottomButton(EXIT, 77, function()
	frame:Hide()
end)
exitButton:SetPoint("BOTTOMRIGHT", -L.BUTTON_RIGHT, L.BUTTON_BOTTOM)

local shareButton = CreateBottomButton(SHARE_QUEST, nil, ForSelectedQuest(QuestMapQuestOptions_ShareQuest))
shareButton:SetPoint("RIGHT", exitButton, "LEFT")

local trackButton = CreateBottomButton(TRACK_QUEST_ABBREV, nil, ForSelectedQuest(ToggleTracking))
trackButton:SetPoint("RIGHT", shareButton, "LEFT")

-- Say why the button is greyed out for quests Questie can't track
trackButton:SetMotionScriptsWhileDisabled(true)
trackButton:SetScript("OnEnter", function(self)
	if (self.untrackable) then
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Can't track with Questie", 1, 1, 1)
		GameTooltip:AddLine("This quest is missing from Questie's database, so Questie's tracker can't show it.", nil, nil, nil, true)
		GameTooltip:Show()
	end
end)
trackButton:SetScript("OnLeave", GameTooltip_Hide)

local function UpdateButtons()
	local questID = selectedQuestID
	if (not questID) then
		abandonButton:Disable()
		shareButton:Disable()
		trackButton:Disable()
		return
	end

	local disabled = C_QuestLog.IsQuestDisabledForSession(questID)
	abandonButton:SetEnabled(not disabled and C_QuestLog.CanAbandonQuest(questID))
	shareButton:SetEnabled(not disabled and C_QuestLog.IsPushableQuest(questID) and IsInGroup())

	local tracked, trackable = IsTracked(questID), CanTrack(questID)
	trackButton:SetText(tracked and UNTRACK_QUEST_ABBREV or TRACK_QUEST_ABBREV)
	trackButton:SetEnabled(trackable and ((tracked and QuestUtil.CanRemoveQuestWatch()) or (not tracked and not disabled)))
	trackButton.untrackable = not trackable
end

---------------------------------------------------------------------------------------------------
-- Refreshing
---------------------------------------------------------------------------------------------------

-- Zones with the same average quest level sort alphabetically, ignoring a leading "The" (The Barrens
-- goes under B)
local function ZoneSortKey(header)
	return (strlower(header.title or ""):gsub("^the%s+", ""))
end

-- Zone order, by name, worked out when the window opens and held while it stays open, so dropping or
-- finishing a quest doesn't shuffle the zones on screen. Zones that turn up while it's open go after
-- the rest
local zoneOrder

local function QuestLevel(quest)
	return quest.difficultyLevel or quest.level or 0
end

-- Quests sort highest level first; quests of the same level keep the quest log's order
local function SortQuests(quests)
	table.sort(quests, function(a, b)
		local levelA, levelB = QuestLevel(a), QuestLevel(b)
		if (levelA ~= levelB) then
			return levelA > levelB
		end
		return a.questLogIndex < b.questLogIndex
	end)
end

-- The average level of the quests showing under a zone
local function AverageLevel(quests)
	local total = 0
	for _, quest in ipairs(quests) do
		total = total + QuestLevel(quest)
	end
	return total / math.max(#quests, 1)
end

-- Same visibility rules as the map's quest list: no hidden quests, world quests or bonus objectives,
-- and zones only when something under them would show. Quests outside any zone come first, then the
-- zones from the highest average quest level to the lowest, so the zones you're levelling in now sit
-- at the top, each after a blank spacer but the first. Within each, quests go highest level first. Returns the list entries,
-- every quest that would show with its zone open, and whether every zone is collapsed
local function BuildEntries()
	local entries, quests, zones = {}, {}, {}
	local header

	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if (info and info.isHeader) then
			header = info
			header.quests = {}
			header.sortKey = ZoneSortKey(header)
			zones[#zones + 1] = header
		elseif (info and not info.isHidden and not info.isTask and (not info.isBounty or C_QuestLog.IsComplete(info.questID))) then
			quests[#quests + 1] = info
			if (header) then
				header.quests[#header.quests + 1] = info
			else
				entries[#entries + 1] = info
			end
		end
	end

	SortQuests(entries) -- Quests outside any zone
	for _, zone in ipairs(zones) do
		zone.averageLevel = AverageLevel(zone.quests)
		SortQuests(zone.quests)
	end
	table.sort(zones, function(a, b)
		local rankA, rankB = zoneOrder and zoneOrder[a.title or ""], zoneOrder and zoneOrder[b.title or ""]
		if (rankA and rankB) then
			return rankA < rankB
		elseif (rankA or rankB) then
			return rankA ~= nil
		elseif (a.averageLevel ~= b.averageLevel) then
			return a.averageLevel > b.averageLevel
		elseif (a.sortKey ~= b.sortKey) then
			return a.sortKey < b.sortKey
		end
		return a.questLogIndex < b.questLogIndex
	end)

	if (not zoneOrder) then
		zoneOrder = {}
		for rank, zone in ipairs(zones) do
			zoneOrder[zone.title or ""] = rank
		end
	end

	local anyHeader, anyExpanded = false, false
	for _, zone in ipairs(zones) do
		if (#zone.quests > 0) then
			if (#entries > 0) then
				entries[#entries + 1] = {isSpacer = true}
			end
			entries[#entries + 1] = zone
			anyHeader = true
			if (not zone.isCollapsed) then
				anyExpanded = true
				for _, quest in ipairs(zone.quests) do
					entries[#entries + 1] = quest
				end
			end
		end
	end

	return entries, quests, anyHeader and not anyExpanded
end

-- Picks a quest to show when nothing (or a quest no longer in the log) is selected: the first one
-- showing, or failing that the first one under a collapsed zone
local function ValidateSelection(entries, quests)
	if (selectedQuestID and C_QuestLog.GetLogIndexForQuestID(selectedQuestID)) then
		return
	end
	selectedQuestID = nil
	for _, info in ipairs(entries) do
		if (info.questID and not info.isHeader) then
			selectedQuestID = info.questID
			return
		end
	end
	selectedQuestID = quests[1] and quests[1].questID
end

local function UpdateList(entries)
	listBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)

	-- Bring a quest opened from elsewhere into view once it's in the list (its zone may still have been
	-- opening)
	if (scrollToQuestID) then
		local index = listBox:FindElementDataIndexByPredicate(function(data)
			return data.questID == scrollToQuestID
		end)
		if (index) then
			scrollToQuestID = nil
			listBox:ScrollToElementDataIndex(index, ScrollBoxConstants.AlignNearest, 0, ScrollBoxConstants.NoScrollInterpolation)
		end
	end
end

local function UpdateCount(numQuests)
	local maxQuests = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 0
	local color = (numQuests > maxQuests) and RED_FONT_COLOR_CODE or HIGHLIGHT_FONT_COLOR_CODE
	questCount:SetFormattedText(QUEST_LOG_COUNT_TEMPLATE, color, numQuests, maxQuests)
end

function UpdateAll(resetScroll)
	if (not frame:IsShown()) then
		return
	end

	local entries, quests, allCollapsed = BuildEntries()
	ValidateSelection(entries, quests)

	noQuestsText:SetShown(#quests == 0)
	collapseAll.allCollapsed = allCollapsed
	collapseAll.Icon:SetTexture(allCollapsed and PLUS_TEXTURE or MINUS_TEXTURE)

	UpdateList(entries)
	UpdateCount(#quests)
	DisplayDetails(resetScroll)
	UpdateButtons()
end

function ShowQuest(questID)
	selectedQuestID = questID
	scrollToQuestID = questID

	-- Open the quest's zone if it's collapsed
	local headerIndex = C_QuestLog.GetHeaderIndexForQuest(questID)
	local header = headerIndex and C_QuestLog.GetInfo(headerIndex)
	if (header and header.isCollapsed) then
		ExpandQuestHeader(headerIndex)
	end

	if (frame:IsShown()) then
		UpdateAll(true)
	else
		frame:Show()
	end
end

-- QUEST_LOG_UPDATE comes in bursts, so repaint at most once a frame
local updatePending
function RequestUpdate()
	if (updatePending or not frame:IsShown()) then
		return
	end
	updatePending = true
	C_Timer.After(0, function()
		updatePending = nil
		UpdateAll()
	end)
end

frame:SetScript("OnEvent", function(_, event, unit)
	if (event ~= "UNIT_QUEST_LOG_CHANGED" or unit == "player") then
		RequestUpdate()
	end
end)
for _, event in ipairs({
	"QUEST_LOG_UPDATE",
	"QUEST_WATCH_LIST_CHANGED",
	"QUEST_ACCEPTED",
	"QUEST_REMOVED",
	"QUEST_TURNED_IN",
	"UNIT_QUEST_LOG_CHANGED",
	"GROUP_ROSTER_UPDATE",
	"PLAYER_LEVEL_UP"
}) do
	frame:RegisterEvent(event)
end

-- Take the QuestInfo elements back once whatever borrowed them closes
for _, borrower in pairs({QuestFrame, QuestLogPopupDetailFrame, QuestMapFrame and QuestMapFrame.DetailsFrame or nil}) do
	borrower:HookScript("OnHide", RequestUpdate)
end

---------------------------------------------------------------------------------------------------
-- Resizing
---------------------------------------------------------------------------------------------------

local function ApplyHeight(height)
	height = ns.ClampHeight(frame, height or BASE_HEIGHT, ROW_HEIGHT)
	if (height == currentHeight) then
		return
	end
	currentHeight = height

	frame:SetHeight(height)
	local paneHeight = height - L.PANE_INSET
	listBox:SetHeight(paneHeight)
	detail:SetHeight(paneHeight + 4)
	LayoutArt(height)
end

ns.CreateResizeGrip(frame, ApplyHeight, function()
	return currentHeight
end)

ApplyHeight(BASE_HEIGHT)

---------------------------------------------------------------------------------------------------
-- Showing and hiding
---------------------------------------------------------------------------------------------------

-- The saved height is applied every time the window opens rather than when it loads, because the
-- screen size and UI scale aren't settled then and the clamp to the screen would cut it short. The
-- saved value is left alone, so a smaller screen only shrinks the window, not the setting
local headersOpened
frame:SetScript("OnShow", function()
	PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
	ApplyHeight(ns.GetDB().height)
	if (not headersOpened) then
		headersOpened = true
		ExpandAllHeaders()
	end
	UpdateAll(true)
end)

frame:SetScript("OnHide", function()
	scrollToQuestID = nil
	zoneOrder = nil -- Sorted afresh next time the window opens
	PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE)
	StaticPopup_Hide("ABANDON_QUEST")
	StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
end)

local function Toggle()
	frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------------------------------
-- Taking over the quest log
---------------------------------------------------------------------------------------------------

-- The quest log key binding and the micro menu button call ToggleQuestLog(); the objective tracker (and
-- Questie, and a few others) call QuestMapFrame_OpenToQuestDetails(). See the taint note at the top.
-- The world map (M) keeps its own quest list, and /wqlp map hands the quest log key back to it
local BlizzardToggleQuestLog = ToggleQuestLog
local BlizzardOpenToQuestDetails = QuestMapFrame_OpenToQuestDetails

function ToggleQuestLog(...)
	if (ns.GetDB().useMap) then
		return BlizzardToggleQuestLog(...)
	end
	Toggle()
end

function QuestMapFrame_OpenToQuestDetails(questID, ...)
	if (ns.GetDB().useMap or not questID or not C_QuestLog.GetLogIndexForQuestID(questID)) then
		return BlizzardOpenToQuestDetails(questID, ...)
	end
	ShowQuest(questID)
end

SLASH_WIDEQUESTLOGPLUS1 = "/wqlp"
SLASH_WIDEQUESTLOGPLUS2 = "/widequestlogplus"
SlashCmdList.WIDEQUESTLOGPLUS = function(msg)
	msg = strlower(strtrim(msg or ""))
	local db = ns.GetDB()
	if (msg == "") then
		Toggle()
	elseif (msg == "reset") then
		db.height, db.point = nil, nil
		frame:ClearAllPoints()
		frame:SetPoint(unpack(DEFAULT_POINT))
		ApplyHeight(BASE_HEIGHT)
		ns.Print("quest log size and position reset.")
	elseif (msg == "map") then
		db.useMap = (not db.useMap) or nil
		if (db.useMap) then
			frame:Hide()
			ns.Print("the quest log key now opens Blizzard's map quest log. |cffffd200/wqlp map|r switches back.")
		else
			ns.Print("the quest log key now opens the wide quest log.")
		end
	else
		ns.Print("commands:")
		print("  |cffffd200/wqlp|r - open or close the quest log")
		print("  |cffffd200/wqlp reset|r - restore the default size and position")
		print("  |cffffd200/wqlp map|r - switch the quest log key between this log and Blizzard's map log")
	end
end

-- The saved position, once saved variables have loaded, and a refresh whenever Questie's tracker
-- updates (untracking from its own menu doesn't always touch Blizzard's watch list)
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if (name ~= ADDON_NAME) then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")

	local point = ns.GetDB().point
	if (point) then
		frame:ClearAllPoints()
		frame:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	end

	local tracker = ImportQuestieModule("QuestieTracker")
	if (tracker and type(tracker.Update) == "function") then
		hooksecurefunc(tracker, "Update", RequestUpdate)
	end
end)
