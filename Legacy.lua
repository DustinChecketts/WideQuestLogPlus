local _, ns = ...

-- Classic Era and Anniversary: widens Blizzard's own quest log into the shared two-pane layout
-- (Layout.lua). WoW Forever has no classic quest log; Modern.lua handles that client
if (not QuestLogFrame) then
	return
end

local L = ns.Layout
local BASE_WIDTH, BASE_HEIGHT = L.BASE_WIDTH, L.BASE_HEIGHT
local BOTTOM_CLAMP = 140 + 12 -- Blizzard's: keeps the bottom of the window clear of the action bars

-- Taint: this file only ever hooks Blizzard's functions (hooksecurefunc, which keeps the hooks' taint
-- out of Blizzard's own code), but a few things it has to do are seen by Blizzard's code as coming
-- from an addon:
--  * The window's new size goes to the panel manager through SetUIPanelAttribute(), the interface
--    Blizzard provides for exactly this, rather than by replacing Blizzard's UIPanelWindows entry.
--  * A taller window needs more list rows, so QUESTS_DISPLAYED (which Blizzard's QuestLog_Update()
--    reads) is raised, the extra rows are created here, and QuestLog_Update() is run when the
--    number of rows changes.
--  * The zone gaps move Blizzard's list rows and widen the list's scroll range (FauxScrollFrame_Update).
-- None of it reaches anything protected: on these clients the quest log, its scroll bar, the quest
-- watch list and the panel manager's positioning of the quest log are all unprotected

local function IsAddOnLoadedCompat(name)
	if (C_AddOns and C_AddOns.IsAddOnLoaded) then
		return C_AddOns.IsAddOnLoaded(name)
	end
	return IsAddOnLoaded(name)
end

-- VoiceOver puts a play button in front of quest titles in the list
local isVoiceOverLoaded = IsAddOnLoadedCompat("AI_VoiceOver")

-- ElvUI's skin can't know about this addon's replacement art, so when ElvUI is loaded, hide Blizzard's
-- art but don't draw any parchment of our own
local hideParchment = IsAddOnLoadedCompat("ElvUI")

local function SetPanelAttribute(name, value)
	if (SetUIPanelAttribute) then
		SetUIPanelAttribute(QuestLogFrame, name, value)
	end
end

---------------------------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------------------------

QuestLogFrame:SetWidth(BASE_WIDTH)
SetPanelAttribute("width", BASE_WIDTH)

QuestLogTitleText:ClearAllPoints()
QuestLogTitleText:SetPoint("TOP", QuestLogFrame, "TOP", 0, -17)

-- Which piece of Blizzard's art a texture is, if it's one of pieces (fileDataID -> name). On current
-- clients XML textures resolve to fileDataIDs and GetTextureFilePath() returns nil, so the ID comes
-- first, with the file name (prefix .. name) as a fallback
local function IdentifyBlizzardArt(region, pieces, prefix)
	local fileID = region.GetTextureFileID and region:GetTextureFileID()
	if (fileID and pieces[fileID]) then
		return pieces[fileID]
	end
	local path = region.GetTextureFilePath and region:GetTextureFilePath() or region:GetTexture()
	if (type(path) == "string") then
		for _, name in pairs(pieces) do
			if (strlower(path) == strlower(prefix .. name)) then
				return name
			end
		end
	end
end

-- Interface\QuestFrame\UI-QuestLog-<TopLeft|TopRight|BotLeft|BotRight>, replaced by the shared art
local QUEST_LOG_ART = {
	[136798] = "BotLeft",
	[136799] = "BotRight",
	[136804] = "TopLeft",
	[136805] = "TopRight"
}
for _, region in ipairs({QuestLogFrame:GetRegions()}) do
	if (region:IsObjectType("Texture") and IdentifyBlizzardArt(region, QUEST_LOG_ART, "Interface\\QuestFrame\\UI-QuestLog-")) then
		region:SetTexture(nil)
		region:SetAlpha(0)
	end
end
local LayoutArt = (not hideParchment) and ns.CreateWindowArt(QuestLogFrame, 1)

-- Some of the bottom row of buttons are pinned to the window's top edge; re-hang them off the bottom
-- edge so they follow it when the window is dragged taller
for _, child in ipairs({QuestLogFrame:GetChildren()}) do
	for i = 1, child:GetNumPoints() do
		local point, relativeTo, relativePoint, x, y = child:GetPoint(i)
		local anchoredToWindow = (relativeTo == QuestLogFrame or relativeTo == nil)
		local anchoredToTop = relativePoint and relativePoint:find("^TOP")
		local nearTheBottom = y and y < -(BASE_HEIGHT * 0.6)
		if (anchoredToWindow and anchoredToTop and nearTheBottom) then
			child:SetPoint(point, relativeTo, (relativePoint:gsub("^TOP", "BOTTOM")), x, y + BASE_HEIGHT)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Quest list (left pane)
---------------------------------------------------------------------------------------------------

QuestLogNoQuestsText:ClearAllPoints()
QuestLogNoQuestsText:SetPoint("TOP", QuestLogListScrollFrame, 0, -90)

-- Quest rows overlap by a pixel, so the pitch of the list is one less than a title's height
local rowHeight = (QuestLogTitle1 and QuestLogTitle1:GetHeight() or 0)
if (rowHeight < 8) then
	rowHeight = 16 -- QUESTLOG_QUEST_HEIGHT
end
rowHeight = rowHeight - 1

-- QuestLog_Update() only fills rows up to QUESTS_DISPLAYED, so rows a taller window created and a
-- shorter one no longer needs have to be hidden here or they keep drawing past the bottom edge.
-- Returns whether the number of rows changed
local createdRows = QUESTS_DISPLAYED
local function SetQuestRowCount(count)
	if (count == QUESTS_DISPLAYED) then
		return false
	end
	for i = createdRows + 1, count do
		local button = CreateFrame("Button", "QuestLogTitle" .. i, QuestLogFrame, "QuestLogTitleButtonTemplate")
		button:SetID(i)
		button:Hide()
		button:SetPoint("TOPLEFT", QuestLogTitle1, "TOPLEFT", 0, -(i - 1) * rowHeight)
	end
	createdRows = math.max(createdRows, count)
	for i = count + 1, createdRows do
		_G["QuestLogTitle" .. i]:Hide()
	end
	QUESTS_DISPLAYED = count
	return true
end

local function GetQuestSuffix(questID, questTag)
	local tagID = questID and GetQuestTagInfo and GetQuestTagInfo(questID)
	return ns.QuestSuffix(tagID, ELITE ~= nil and questTag == ELITE)
end

-- A gap above every zone but the first, made by moving Blizzard's own rows rather than replacing them,
-- so each row still shows the quest Blizzard put in it and addons that hook the rows (Questie,
-- VoiceOver) keep working. Rows pushed past the bottom are hidden, and each gap counts as an extra row
-- of scrolling so the last quests can still be scrolled into view
local layingOutRows
local function AddZoneGaps()
	if (layingOutRows) then
		return -- Extending the scroll range can scroll the list, which runs QuestLog_Update() again
	end
	layingOutRows = true

	local numEntries = GetNumQuestLogEntries()
	local gaps = 0
	for index = 2, numEntries do
		if (select(4, GetQuestLogTitle(index))) then
			gaps = gaps + 1
		end
	end
	if (gaps > 0) then
		FauxScrollFrame_Update(QuestLogListScrollFrame, numEntries + math.ceil(gaps * L.HEADER_GAP / rowHeight), QUESTS_DISPLAYED, QUESTLOG_QUEST_HEIGHT, nil, nil, nil, QuestLogHighlightFrame, 293, 316)
	end

	local offset = FauxScrollFrame_GetOffset(QuestLogListScrollFrame)
	local paneHeight = QuestLogListScrollFrame:GetHeight()
	local top = 0
	for i = 2, QUESTS_DISPLAYED do
		local row = _G["QuestLogTitle" .. i]
		local index = offset + i
		top = top + rowHeight
		if (index <= numEntries and select(4, GetQuestLogTitle(index))) then
			top = top + L.HEADER_GAP
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", QuestLogTitle1, "TOPLEFT", 0, -top)
		if (top + rowHeight > paneHeight) then
			row:Hide()
			if (select(2, QuestLogHighlightFrame:GetPoint(1)) == row) then
				QuestLogHighlightFrame:Hide()
			end
		end
	end

	layingOutRows = nil
end

-- Blizzard rewrites the list from QuestLog_Update(), which runs on quest log events, scrolling and
-- selection; restyle the rows it filled: level and type before each title, and the tracking check in a
-- slot in front of it
local function StyleQuestRows()
	local numEntries = GetNumQuestLogEntries()
	local offset = FauxScrollFrame_GetOffset(QuestLogListScrollFrame)
	for i = 1, math.min(QUESTS_DISPLAYED, numEntries - offset) do
		local row = _G["QuestLogTitle" .. i]
		local text, check = row.Text, _G["QuestLogTitle" .. i .. "Check"]
		local title, level, questTag, isHeader, _, _, _, questID = GetQuestLogTitle(i + offset)

		if (isHeader) then
			text:SetPoint("LEFT", row, "LEFT", L.HEADER_TEXT_X, 0)
			check:Hide()
		else
			local label = ns.LevelTitle(level, title, GetQuestSuffix(questID, questTag))
			check:ClearAllPoints()
			check:SetVertexColor(64 / 255, 224 / 255, 208 / 255)
			check:SetDrawLayer("ARTWORK")
			if (isVoiceOverLoaded) then
				-- VoiceOver's play button sits in front of the title, so the check stays after it
				row:SetText("	   " .. label)
				text:SetPoint("LEFT", row, "LEFT", L.HEADER_TEXT_X, 0)
				check:SetPoint("LEFT", row, "LEFT", text:GetStringWidth() + 18, 0)
			else
				row:SetText(label)
				text:SetPoint("LEFT", row, "LEFT", L.QUEST_TEXT_X, 0)
				check:SetPoint("LEFT", row, "LEFT", L.CHECK_X, 0)

				-- Blizzard sized the title for its old position and cut it short there, so measure it
				-- whole, then shorten it to clear the tag ("(Complete)", "(Elite)", ...) if it has to
				local tag = _G["QuestLogTitle" .. i .. "Tag"]
				local tagWidth = (tag and tag:IsShown() and (tag:GetText() or "") ~= "") and (tag:GetStringWidth() + 6) or 2
				local room = row:GetWidth() - L.QUEST_TEXT_X - tagWidth
				text:SetWidth(0)
				if (text:GetStringWidth() > room) then
					text:SetWidth(room)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Quest details (right pane)
---------------------------------------------------------------------------------------------------

-- Beside the list, reaching to the right edge of the parchment
QuestLogDetailScrollFrame:ClearAllPoints()
QuestLogDetailScrollFrame:SetPoint("TOPLEFT", QuestLogListScrollFrame, "TOPRIGHT", L.DETAIL_LEFT - (L.LIST_LEFT + L.LIST_WIDTH), 0)
QuestLogDetailScrollFrame:SetWidth(L.PARCHMENT_RIGHT - L.DETAIL_LEFT)
QuestLogDetailScrollChildFrame:SetWidth(L.PARCHMENT_RIGHT - L.DETAIL_LEFT)

-- Quest text as wide as two columns of reward buttons, with the same margin of parchment on the left,
-- right and top, and the title level with the first quest row of the list. Only the title is anchored
-- to the pane; everything else hangs off it
QuestLogQuestTitle:SetPoint("TOPLEFT", QuestLogDetailScrollChildFrame, "TOPLEFT", L.CONTENT_LEFT - L.DETAIL_LEFT, -(L.CONTENT_TOP - L.PANE_TOP))
QuestLogObjectivesText:SetPoint("TOPLEFT", QuestLogQuestTitle, "BOTTOMLEFT", 0, -L.TITLE_GAP)
QuestLogQuestDescription:SetPoint("TOPLEFT", QuestLogDescriptionTitle, "BOTTOMLEFT", 0, -L.TITLE_GAP)
for _, name in ipairs({
	"QuestLogQuestTitle",
	"QuestLogObjectivesText",
	"QuestLogTimerText",
	"QuestLogDescriptionTitle",
	"QuestLogQuestDescription",
	"QuestLogRewardTitleText",
	"QuestLogItemChooseText"
}) do
	if (_G[name]) then
		_G[name]:SetWidth(L.CONTENT_WIDTH)
	end
end
local objective = 1
while (_G["QuestLogObjective" .. objective]) do
	_G["QuestLogObjective" .. objective]:SetWidth(L.CONTENT_WIDTH)
	objective = objective + 1
end

-- Gold right-aligned to the text column, rather than just after "You will receive:"
QuestLogMoneyFrame:ClearAllPoints()
QuestLogMoneyFrame:SetPoint("RIGHT", QuestLogItemReceiveText, "LEFT", L.CONTENT_WIDTH + L.MONEY_RIGHT_PADDING, 0)

-- Objective lines: check, name and a right-aligned count (Common.lua). The quest log has one line per
-- leaderboard entry
local function StyleObjectives()
	ns.ClearObjectiveCounts()
	for index = 1, GetNumQuestLeaderBoards() do
		local line = _G["QuestLogObjective" .. index]
		if (not line) then
			break
		end
		local text, objectiveType, finished = GetQuestLogLeaderBoard(index)
		if (line:IsShown()) then
			ns.StyleObjective(line, (text and text ~= "") and text or objectiveType, finished, L.CONTENT_WIDTH, QuestLogQuestDescription)
		end
	end
end

-- The quest ID, right-aligned under the rewards (or whatever comes last). Blizzard hangs a spacer below
-- the last thing in the pane, so it goes inside that, made tall enough to hold it
local questIDText = QuestLogDetailScrollChildFrame:CreateFontString(nil, "ARTWORK", "QuestFontNormalSmall")
questIDText:SetJustifyH("RIGHT")
QuestLogSpacerFrame:SetHeight(L.QUEST_ID_GAP + 20) -- Room for the ID, so it scrolls into view

local function PlaceQuestID()
	local spacerTop, childTop = QuestLogSpacerFrame:GetTop(), QuestLogDetailScrollChildFrame:GetTop()
	if (spacerTop and childTop) then
		questIDText:ClearAllPoints()
		questIDText:SetPoint("TOPRIGHT", QuestLogDetailScrollChildFrame, "TOPLEFT", L.CONTENT_LEFT + L.CONTENT_WIDTH - L.DETAIL_LEFT, spacerTop - childTop - L.QUEST_ID_GAP)
	end
end

-- The pane is written by QuestLog_UpdateQuestDetails() and again while QuestFrameItems_Update()
-- rebuilds it, so this follows both
local function ShowQuestID()
	local title, _, _, _, _, _, _, questID = GetQuestLogTitle(GetQuestLogSelection())
	if (not title) or (not questID) then
		questIDText:Hide()
		return
	end
	-- Description's colour: dark on the parchment, white under ElvUI's parchment remover
	ns.StyleQuestID(questIDText, questID, QuestLogQuestDescription)
	questIDText:Show()
	PlaceQuestID()
	C_Timer.After(0, PlaceQuestID) -- Again once the pane's layout has settled
end

-- Blizzard hangs the first reward button of each section 3px left of the text above it, and the
-- reward captions 3px in. Line them all up with the rest of the text, as on WoW Forever, so two
-- columns of buttons fill the text column exactly
local function IsRewardButton(region)
	local name = region and region.GetName and region:GetName()
	return name and name:find("^QuestLogItem%d+$") ~= nil
end

local function Realign(region, offset, unlessAnchoredToButton)
	if (not region) or (not region:IsShown()) or (region:GetNumPoints() < 1) then
		return
	end
	local point, relativeTo, relativePoint, x, y = region:GetPoint(1)
	if (unlessAnchoredToButton and IsRewardButton(relativeTo)) then
		return -- Buttons further down a section only sit beside or below the one before
	end
	if (x and math.abs(x - offset) < 0.01) then
		region:SetPoint(point, relativeTo, relativePoint, 0, y)
	end
end

-- A blank line under the Rewards heading, as under the title and Description: whichever line comes
-- first under the heading is moved down
local function SpaceUnderRewardsHeading(region)
	if (region and region:IsShown() and region:GetNumPoints() > 0) then
		local point, relativeTo, relativePoint, x = region:GetPoint(1)
		if (relativeTo == QuestLogRewardTitleText) then
			region:SetPoint(point, relativeTo, relativePoint, x, -L.TITLE_GAP)
		end
	end
end

local function AlignRewards()
	Realign(QuestLogItemReceiveText, 3)
	Realign(QuestLogSpellLearnText, 3)
	SpaceUnderRewardsHeading(QuestLogItemChooseText)
	SpaceUnderRewardsHeading(QuestLogItemReceiveText)
	SpaceUnderRewardsHeading(QuestLogSpellLearnText)
	local index = 1
	while (_G["QuestLogItem" .. index]) do
		Realign(_G["QuestLogItem" .. index], -3, true)
		index = index + 1
	end
end

---------------------------------------------------------------------------------------------------
-- Resizing
---------------------------------------------------------------------------------------------------

-- Height the window may take out of the space the panel manager keeps below it. The default window
-- stops well above the action bars; dragging it taller trades that away a pixel at a time, which is
-- the only way there's meaningful room to grow at a normal UI scale
local function BottomClamp(height)
	return math.max(L.MIN_BOTTOM_CLAMP, BOTTOM_CLAMP - (height - BASE_HEIGHT))
end

-- The "no active quests" parchment, laid over the detail pane at whatever size it is
local EMPTY_ART = {
	[136800] = "BotLeft",
	[136801] = "BotRight",
	[136802] = "TopLeft",
	[136803] = "TopRight"
}
local EMPTY_TOP_CROP, EMPTY_BOTTOM_CROP = 0.37, 0.83
local EMPTY_TOP_HEIGHT = 256 * (1 - EMPTY_TOP_CROP)
local EMPTY_BOTTOM_HEIGHT = 128 * EMPTY_BOTTOM_CROP
local EMPTY_WIDTH, EMPTY_HEIGHT = 256 + 64, EMPTY_TOP_HEIGHT + EMPTY_BOTTOM_HEIGHT
local EMPTY_PIECES = { -- Size and position within the whole picture, and the part of the texture shown
	TopLeft = {256, EMPTY_TOP_HEIGHT, 0, 0, EMPTY_TOP_CROP, 1},
	TopRight = {64, EMPTY_TOP_HEIGHT, 256, 0, EMPTY_TOP_CROP, 1},
	BotLeft = {256, EMPTY_BOTTOM_HEIGHT, 0, -EMPTY_TOP_HEIGHT, 0, EMPTY_BOTTOM_CROP},
	BotRight = {64, EMPTY_BOTTOM_HEIGHT, 256, -EMPTY_TOP_HEIGHT, 0, EMPTY_BOTTOM_CROP}
}

local function LayoutEmptyArt()
	local scaleX = (QuestLogDetailScrollFrame:GetWidth() + 26) / EMPTY_WIDTH
	local scaleY = (QuestLogDetailScrollFrame:GetHeight() + 8) / EMPTY_HEIGHT
	for _, region in ipairs({EmptyQuestLogFrame:GetRegions()}) do
		local piece = region:IsObjectType("Texture") and IdentifyBlizzardArt(region, EMPTY_ART, "Interface\\QuestFrame\\UI-QuestLog-Empty-")
		local spec = piece and EMPTY_PIECES[piece]
		if (piece and hideParchment) then
			region:Hide()
		elseif (spec) then
			local width, height, x, y, top, bottom = unpack(spec)
			region:SetTexCoord(0, 1, top, bottom)
			region:SetSize(width * scaleX, height * scaleY)
			region:ClearAllPoints()
			region:SetPoint("TOPLEFT", QuestLogDetailScrollFrame, "TOPLEFT", x * scaleX - 10, y * scaleY + 8)
		end
	end
end

local currentHeight

-- Resizes the window and everything inside it that has to follow the bottom edge
local function ApplyHeight(height)
	height = ns.ClampHeight(QuestLogFrame, height or BASE_HEIGHT, rowHeight)
	if (height == currentHeight) then
		return
	end
	currentHeight = height

	QuestLogFrame:SetHeight(height)

	-- Keep the panel manager's idea of the window in step, or it scales the whole window down to fit
	-- the space it thinks the window still needs
	SetPanelAttribute("height", height)
	SetPanelAttribute("bottomClampOverride", BottomClamp(height))

	local paneHeight = height - L.PANE_INSET
	QuestLogListScrollFrame:SetHeight(paneHeight)
	QuestLogDetailScrollFrame:SetHeight(paneHeight)

	if (LayoutArt) then
		LayoutArt(height)
	end
	LayoutEmptyArt()

	if (SetQuestRowCount(math.floor(paneHeight / rowHeight)) and QuestLogFrame:IsShown()) then
		QuestLog_Update()
	end
end

local grip = ns.CreateResizeGrip(QuestLogFrame, ApplyHeight, function()
	return currentHeight
end)

-- ElvUI draws the window as a backdrop inset from the frame's own edges, so follow that corner when
-- it exists rather than the frame's, which sits outside the visible window
local function AnchorGrip()
	if (QuestLogFrame.backdrop) then
		grip:ClearAllPoints()
		grip:SetPoint("BOTTOMRIGHT", QuestLogFrame.backdrop, "BOTTOMRIGHT", -2, 2)
	end
end

ApplyHeight(BASE_HEIGHT)

---------------------------------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------------------------------

hooksecurefunc("QuestLog_Update", function()
	AddZoneGaps()
	StyleQuestRows()
end)
hooksecurefunc("QuestLog_UpdateQuestDetails", function()
	StyleObjectives()
	ShowQuestID()
end)
hooksecurefunc("QuestFrameItems_Update", function(questState)
	if (questState == "QuestLog") then -- The quest giver window's rewards use it too
		AlignRewards()
		ShowQuestID()
	end
end)

-- The saved height is applied every time the window opens rather than when it loads, because the
-- screen size and UI scale aren't settled then and the clamp to the screen would cut it short. The
-- saved value is left alone, so a smaller screen only shrinks the window, not the setting
QuestLogFrame:HookScript("OnShow", function()
	AnchorGrip()
	local height = ns.GetDB().height or currentHeight
	currentHeight = nil
	ApplyHeight(height)
end)

---------------------------------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------------------------------

-- An escape hatch, in case a saved height (or a grip hidden behind another addon) ever leaves the
-- window in a state that can't be dragged back
SLASH_WIDEQUESTLOGPLUS1 = "/wqlp"
SLASH_WIDEQUESTLOGPLUS2 = "/widequestlogplus"
SlashCmdList.WIDEQUESTLOGPLUS = function(msg)
	if (strlower(strtrim(msg or "")) == "reset") then
		ns.GetDB().height = nil
		currentHeight = nil
		ApplyHeight(BASE_HEIGHT)
		ns.Print("quest log size reset.")
	else
		ns.Print("|cffffd200/wqlp reset|r - restore the default quest log size")
	end
end
