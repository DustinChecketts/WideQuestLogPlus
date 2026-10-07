local ADDON_NAME = ...

-- Era / Anniversary TBC only: preserve Blizzard's native Classic quest log.
if not QuestLogFrame then
	return
end

-- Geometry of the quest log at its default (unresized) size
local BASE_WIDTH = 724
local BASE_HEIGHT = 513
local BASE_PANE_HEIGHT = 362 -- Height of the list and detail panes at BASE_HEIGHT
local PANE_INSET = BASE_HEIGHT - BASE_PANE_HEIGHT -- Vertical space the panes never occupy
local BOTTOM_CLAMP = 140 + 12 -- Keep the bottom of the window clear of the action bars
local MIN_BOTTOM_CLAMP = 20 -- ...but a window dragged taller may claim that space down to here

-- The window art doesn't reach the edges of the frame it lives in: the opaque part of the corner
-- pieces (img/WQLP_BotRight) stops 176px into a 256px piece drawn at x=515, and 211px down a piece
-- whose bottom sits a pixel above the frame's, so the drawn border is inset by this much
local ART_INSET_RIGHT = BASE_WIDTH - (515 + 176)
local ART_INSET_BOTTOM = 256 - 211 + 1

-- Where the resize grip sits inside that drawn corner. ElvUI's skin replaces the art with a backdrop
-- of its own, so the grip is re-anchored to that backdrop instead when one shows up
local GRIP_INSET = 4

-- Customize the appearance and behavior of the Quest Log window
UIPanelWindows["QuestLogFrame"] = {
	area = "left", -- the modern (11509+) panel manager has no "override" area
	pushable = 0,
	xoffset = -16,
	yoffset = 12,
	bottomClampOverride = BOTTOM_CLAMP,
	width = BASE_WIDTH,
	height = BASE_HEIGHT,
	whileDead = 1
}

-- The panel manager copies UIPanelWindows entries into frame attributes on first use and reads
-- only the attributes afterward, so push the overrides there as well
if (SetUIPanelAttribute) then
	for name, value in pairs(UIPanelWindows["QuestLogFrame"]) do
		SetUIPanelAttribute(QuestLogFrame, name, value)
	end
end

-- Function to customize the appearance and behavior of the wide Quest Log
local function WideQuestLogPlus()
	local function IsAddOnLoadedCompat(addonName)
		if (C_AddOns and C_AddOns.IsAddOnLoaded) then
			return C_AddOns.IsAddOnLoaded(addonName)
		end
		return IsAddOnLoaded(addonName)
	end

	-- Check if VoiceOver is installed and enabled
	local isVoiceOverLoaded = IsAddOnLoadedCompat("AI_VoiceOver")

	-- ElvUI's Parchment Remover can't know about this addon's replacement art, so when ElvUI
	-- is handling the quest log's look, hide the originals but don't draw any parchment of our own
	local hideParchment = IsAddOnLoadedCompat("ElvUI")

	-- Widen the window
	QuestLogFrame:SetWidth(BASE_WIDTH)

	-- Adjust quest log title text position
	QuestLogTitleText:ClearAllPoints()
	QuestLogTitleText:SetPoint("TOP", QuestLogFrame, "TOP", 0, -17)

	-- Relocate the quest detail frame
	QuestLogDetailScrollFrame:ClearAllPoints()
	QuestLogDetailScrollFrame:SetPoint("TOPLEFT", QuestLogListScrollFrame, "TOPRIGHT", 41, 0)

	-- Relocate the "No Active Quests" text
	QuestLogNoQuestsText:ClearAllPoints()
	QuestLogNoQuestsText:SetPoint("TOP", QuestLogListScrollFrame, 0, -90)

	-- Quest rows overlap by a pixel, so the pitch of the list is one less than a title's height
	local rowHeight = QuestLogTitle1 and QuestLogTitle1:GetHeight() or 0
	if (rowHeight < 8) then
		rowHeight = 16 -- QUESTLOG_QUEST_HEIGHT
	end
	rowHeight = rowHeight - 1

	-- Create additional rows for displaying quests. QuestLog_Update() only ever touches rows up to
	-- QUESTS_DISPLAYED, so rows left over from a taller window have to be hidden here or they keep
	-- drawing past the bottom edge
	local createdRows = QUESTS_DISPLAYED
	local function SetQuestRowCount(count)
		for i = createdRows + 1, count do
			local button = CreateFrame("Button", "QuestLogTitle" .. i, QuestLogFrame, "QuestLogTitleButtonTemplate")
			button:SetID(i)
			button:Hide()
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", _G["QuestLogTitle" .. (i - 1)], "BOTTOMLEFT", 0, 1)
		end
		if (count > createdRows) then
			createdRows = count
		end

		for i = count + 1, createdRows do
			local button = _G["QuestLogTitle" .. i]
			if (button) then
				button:Hide()
			end
		end

		QUESTS_DISPLAYED = count
	end

	-- Add the recommended level to the quest titles in the list. Blizzard rewrites those titles from
	-- QuestLog_Update(), which is what runs on quest log events, on scrolling and on selection, so
	-- hook that rather than redo the whole list every frame from OnUpdate
	local function AddQuestLevels()
		local numEntries = GetNumQuestLogEntries()

		if (numEntries == 0) then
			return
		end

		local offset = FauxScrollFrame_GetOffset(QuestLogListScrollFrame)
		for i = 1, QUESTS_DISPLAYED, 1 do
			local questIndex = i + offset

			if (questIndex <= numEntries) then
				local questLogTitle = _G["QuestLogTitle" .. i]
				local questCheck = _G["QuestLogTitle" .. i .. "Check"]
				local title, level, _, isHeader = GetQuestLogTitle(questIndex)

				if (not isHeader) then
					local questTextFormatted
					if isVoiceOverLoaded then -- Adjustment for play button overlap
						questTextFormatted = format("	   [%d] %s", level, title)
					else -- Default spacing
						questTextFormatted = format("[%d] %s", level, title)
					end
					questLogTitle:SetText(questTextFormatted)
					questCheck:SetPoint("LEFT", questLogTitle, "LEFT", questLogTitle.Text:GetStringWidth() + 18, 0)
					questCheck:SetVertexColor(64 / 255, 224 / 255, 208 / 255)
					questCheck:SetDrawLayer("ARTWORK")
				else
					questCheck:Hide()
				end
			end
		end
	end

	hooksecurefunc("QuestLog_Update", AddQuestLevels)

	-- Add quest ID to quest text. The detail pane's title is written by QuestLog_UpdateQuestDetails()
	-- and again while QuestFrameItems_Update() rebuilds the pane, so follow both
	local function AddQuestID()
		local title, _, _, _, _, _, _, id = GetQuestLogTitle(GetQuestLogSelection())
		if (not title) or (not id) then
			return
		end

		title = format("%s [%d]", title, id)
		if (IsCurrentQuestFailed()) then
			title = format("%s - (%s)", title, _G.FAILED)
		end
		QuestLogQuestTitle:SetText(title)
	end

	hooksecurefunc("QuestLog_UpdateQuestDetails", AddQuestID)
	hooksecurefunc("QuestFrameItems_Update", AddQuestID)

	-- Handle background textures
	local regions = {QuestLogFrame:GetRegions()}
	local xOffsets = {Left = 3, Middle = 259, Right = 515}
	local textures = {
		TopLeft = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_TopLeft",
		TopMiddle = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_TopMid",
		TopRight = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_TopRight",
		BotLeft = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_BotLeft",
		BotMiddle = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_BotMid",
		BotRight = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_BotRight"
	}

	-- The top half of each upper texture carries the window's top border and has to keep its
	-- proportions, so each one is drawn as two pieces and only the lower (plain parchment) piece is
	-- stretched to cover whatever height the window has been dragged to
	local TOP_SPLIT = 0.5
	local artPieces = {}

	local function CreateArtPiece(name, sublevel)
		local path = textures[name]
		local row, column = name:match("^([A-Z][a-z]+)([A-Z][a-z]+)$")
		local xOfs = column and xOffsets[column]
		if (not path) or (not xOfs) then
			return
		end

		-- Remove the stored texture reference
		textures[name] = nil

		local pieces = (row == "Top") and 2 or 1
		for piece = 1, pieces do
			-- Create and configure a new texture region
			local region = QuestLogFrame:CreateTexture(nil, "ARTWORK")
			region:SetTexture(path)
			region:SetWidth(256)
			if (sublevel) then
				-- Adjust the sublevel as needed to prevent the default UI textures from appearing in front of the new textures we're providing
				region:SetDrawLayer("ARTWORK", sublevel)
			end
			if (pieces > 1) then
				if (piece == 1) then
					region:SetTexCoord(0, 1, 0, TOP_SPLIT)
				else
					region:SetTexCoord(0, 1, TOP_SPLIT, 1)
				end
			end
			artPieces[#artPieces + 1] = {region = region, x = xOfs, row = row, piece = piece}
		end
	end

	-- Pin the top row to the top of the window and the bottom row to the bottom of it, giving any
	-- height above the default to the stretchable lower half of the top row
	local function LayoutArt(height)
		local extra = height - BASE_HEIGHT
		for _, art in ipairs(artPieces) do
			art.region:ClearAllPoints()
			if (art.row == "Top") then
				if (art.piece == 1) then
					art.region:SetHeight(256 * TOP_SPLIT)
					art.region:SetPoint("TOPLEFT", QuestLogFrame, "TOPLEFT", art.x, 0)
				else
					art.region:SetHeight(256 * (1 - TOP_SPLIT) + extra)
					art.region:SetPoint("TOPLEFT", QuestLogFrame, "TOPLEFT", art.x, -256 * TOP_SPLIT)
				end
			else
				art.region:SetHeight(256)
				art.region:SetPoint("TOPLEFT", QuestLogFrame, "TOPLEFT", art.x, -(height - 257))
			end
		end
	end

	-- On modern clients (Interface 11509/20506+) XML-defined textures resolve to fileDataIDs and
	-- GetTextureFilePath() returns nil for Blizzard's art, so identify it by fileDataID first and
	-- fall back to path matching for older clients
	local function IdentifyBlizzardArt(region, fileIDs, pattern)
		local fileID = region.GetTextureFileID and region:GetTextureFileID()
		if (fileIDs[fileID]) then
			return fileIDs[fileID]
		end
		local path = region.GetTextureFilePath and region:GetTextureFilePath() or region:GetTexture()
		if (type(path) == "string") then
			return path:match(pattern)
		end
	end

	-- fileDataIDs of Interface\QuestFrame\UI-QuestLog-<TopLeft|TopRight|BotLeft|BotRight>
	local questLogArt = {
		[136798] = "BotLeft",
		[136799] = "BotRight",
		[136804] = "TopLeft",
		[136805] = "TopRight"
	}

	local PATTERN = "^Interface\\QuestFrame\\UI%-QuestLog%-(([A-Z][a-z]+)([A-Z][a-z]+))$"
	for _, region in ipairs(regions) do
		if (region:IsObjectType("Texture")) then
			local which = IdentifyBlizzardArt(region, questLogArt, PATTERN)
			if (which and textures[which]) then
				-- Attempt to hide the original textures
				region:SetTexture(nil)
				region:SetAlpha(0)

				if (not hideParchment) then
					CreateArtPiece(which)
				else
					textures[which] = nil
				end
			end
		end
	end

	-- Place the local textures
	if (not hideParchment) then
		for name in pairs(textures) do
			CreateArtPiece(name, 2)
		end
	end

	-- Handle empty quest log textures
	local topOfs = 0.37
	local topH = 256 * (1 - topOfs)

	local botCap = 0.83
	local botH = 128 * botCap

	local xSize = 256 + 64
	local ySize = topH + botH

	-- fileDataIDs of Interface\QuestFrame\UI-QuestLog-Empty-<piece>
	local emptyArt = {
		[136800] = "BotLeft",
		[136801] = "BotRight",
		[136802] = "TopLeft",
		[136803] = "TopRight"
	}

	-- Loop through and handle empty quest log frame textures, sized to the current detail pane
	local function LayoutEmptyArt()
		local nxSize = QuestLogDetailScrollFrame:GetWidth() + 26
		local nySize = QuestLogDetailScrollFrame:GetHeight() + 8

		local function relocateEmpty(t, w, h, x, y)
			local nx = x / xSize * nxSize - 10
			local ny = y / ySize * nySize + 8
			local nw = w / xSize * nxSize
			local nh = h / ySize * nySize

			t:SetWidth(nw)
			t:SetHeight(nh)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", QuestLogDetailScrollFrame, "TOPLEFT", nx, ny)
		end

		local txset = {EmptyQuestLogFrame:GetRegions()}
		for _, t in ipairs(txset) do
			if (t:IsObjectType("Texture")) then
				local p = IdentifyBlizzardArt(t, emptyArt, "-([^-]+)$")
				if (p) then
					if (hideParchment) then
						t:Hide()
					elseif (p == "TopLeft") then
						t:SetTexCoord(0, 1, topOfs, 1)
						relocateEmpty(t, 256, topH, 0, 0)
					elseif (p == "TopRight") then
						t:SetTexCoord(0, 1, topOfs, 1)
						relocateEmpty(t, 64, topH, 256, 0)
					elseif (p == "BotLeft") then
						t:SetTexCoord(0, 1, 0, botCap)
						relocateEmpty(t, 256, botH, 0, -topH)
					elseif (p == "BotRight") then
						t:SetTexCoord(0, 1, 0, botCap)
						relocateEmpty(t, 64, botH, 256, -topH)
					else
						t:Hide() -- Hide textures that don't match expected patterns
					end
				end
			end
		end
	end

	-- Height the window is allowed to eat out of the space the panel manager keeps below it. The
	-- default window stops well above the action bars; dragging it taller trades that away a pixel
	-- at a time, which is the only way there's meaningful room to grow at a normal UI scale
	local function BottomClamp(height)
		return math.max(MIN_BOTTOM_CLAMP, BOTTOM_CLAMP - (height - BASE_HEIGHT))
	end

	-- The window can only grow downward, so cap it just above the bottom of the screen
	local function MaxHeight()
		local top = QuestLogFrame:GetTop() or UIParent:GetHeight()
		return math.max(BASE_HEIGHT, top - MIN_BOTTOM_CLAMP)
	end

	-- Snap to whole quest rows so the list never ends on a partial row
	local function ClampHeight(height)
		height = BASE_HEIGHT + math.floor((height - BASE_HEIGHT) / rowHeight + 0.5) * rowHeight

		local maxHeight = MaxHeight()
		if (height > maxHeight) then
			height = BASE_HEIGHT + math.floor((maxHeight - BASE_HEIGHT) / rowHeight) * rowHeight
		end
		if (height < BASE_HEIGHT) then
			height = BASE_HEIGHT
		end

		return height
	end

	local currentHeight

	-- Resize the window and everything inside it that has to follow the bottom edge
	local function ApplyHeight(height)
		height = ClampHeight(height or BASE_HEIGHT)
		if (height == currentHeight) then
			return
		end
		currentHeight = height

		QuestLogFrame:SetHeight(height)

		-- Keep the panel manager's idea of the window in sync with the real thing, or it will scale
		-- the whole window down to fit the space it thinks the window still needs
		local clamp = BottomClamp(height)
		UIPanelWindows["QuestLogFrame"].height = height
		UIPanelWindows["QuestLogFrame"].bottomClampOverride = clamp
		if (SetUIPanelAttribute) then
			SetUIPanelAttribute(QuestLogFrame, "height", height)
			SetUIPanelAttribute(QuestLogFrame, "bottomClampOverride", clamp)
		end

		-- Expand the height of the quest list and the quest detail frame
		local paneHeight = height - PANE_INSET
		QuestLogListScrollFrame:SetHeight(paneHeight)
		QuestLogDetailScrollFrame:SetHeight(paneHeight)

		-- Fill the list with rows, creating any that don't exist yet and hiding any that no longer fit
		SetQuestRowCount(math.floor(paneHeight / rowHeight))

		if (not hideParchment) then
			LayoutArt(height)
		end
		LayoutEmptyArt()

		if (QuestLog_Update and QuestLogFrame:IsShown()) then
			QuestLog_Update()
		end
	end

	-- Some elements of the quest log are pinned to the window's top edge even though they belong to
	-- the bottom row of buttons; re-hang those off the bottom edge so they ride the resize
	for _, child in ipairs({QuestLogFrame:GetChildren()}) do
		for i = 1, child:GetNumPoints() do
			local point, relativeTo, relativePoint, xOfs, yOfs = child:GetPoint(i)
			local anchoredToWindow = (relativeTo == QuestLogFrame or relativeTo == nil)
			local anchoredToTop = relativePoint and relativePoint:find("^TOP")
			local nearTheBottom = yOfs and yOfs < -(BASE_HEIGHT * 0.6)
			if (anchoredToWindow and anchoredToTop and nearTheBottom) then
				child:SetPoint(point, relativeTo, relativePoint:gsub("^TOP", "BOTTOM"), xOfs, yOfs + BASE_HEIGHT)
			end
		end
	end

	-- Add a grip to the bottom-right corner for dragging the window taller
	local grip = CreateFrame("Button", "WideQuestLogPlusSizeGrip", QuestLogFrame)
	grip:SetSize(16, 16)
	grip:SetFrameLevel(QuestLogFrame:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

	-- ElvUI draws the window as a backdrop inset from the frame's own edges, so follow that corner
	-- when it exists rather than the frame's, which sits outside the visible window
	local function AnchorGrip()
		grip:ClearAllPoints()
		if (QuestLogFrame.backdrop) then
			grip:SetPoint("BOTTOMRIGHT", QuestLogFrame.backdrop, "BOTTOMRIGHT", -2, 2)
		else
			local x = -(ART_INSET_RIGHT + GRIP_INSET)
			local y = ART_INSET_BOTTOM + GRIP_INSET
			grip:SetPoint("BOTTOMRIGHT", QuestLogFrame, "BOTTOMRIGHT", x, y)
		end
	end
	AnchorGrip()

	grip:SetScript(
		"OnEnter",
		function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("Drag to resize the Quest Log")
			GameTooltip:Show()
		end
	)
	grip:SetScript(
		"OnLeave",
		function()
			GameTooltip:Hide()
		end
	)

	local sizingFrom, sizingHeight

	local function StopSizing(self)
		if (not sizingFrom) then
			return
		end
		sizingFrom = nil
		self:SetScript("OnUpdate", nil)
		WideQuestLogPlusDB = WideQuestLogPlusDB or {}
		WideQuestLogPlusDB.height = currentHeight
	end

	grip:SetScript(
		"OnMouseDown",
		function(self)
			local _, y = GetCursorPosition()
			sizingFrom = y / QuestLogFrame:GetEffectiveScale()
			sizingHeight = currentHeight
			self:SetScript(
				"OnUpdate",
				function(this)
					if (not IsMouseButtonDown("LeftButton")) then
						StopSizing(this) -- Don't keep sizing if the mouse-up went somewhere else
						return
					end
					local _, cursorY = GetCursorPosition()
					ApplyHeight(sizingHeight + (sizingFrom - cursorY / QuestLogFrame:GetEffectiveScale()))
				end
			)
		end
	)
	grip:SetScript("OnMouseUp", StopSizing)
	grip:SetScript("OnHide", StopSizing)

	-- The window isn't positioned until it's shown, so re-check the clamp (and the skin's backdrop)
	-- every time it opens
	QuestLogFrame:HookScript(
		"OnShow",
		function()
			AnchorGrip()
			local height = currentHeight
			currentHeight = nil
			ApplyHeight(height)
		end
	)

	ApplyHeight(BASE_HEIGHT)

	-- An escape hatch, in case a saved height (or a grip hidden behind another addon) ever leaves the
	-- window in a state that can't be dragged back
	SLASH_WIDEQUESTLOGPLUS1 = "/wqlp"
	SLASH_WIDEQUESTLOGPLUS2 = "/widequestlogplus"
	SlashCmdList["WIDEQUESTLOGPLUS"] = function(msg)
		if (strlower(strtrim(msg or "")) == "reset") then
			ApplyHeight(BASE_HEIGHT)
			WideQuestLogPlusDB = WideQuestLogPlusDB or {}
			WideQuestLogPlusDB.height = nil
			print("WideQuestLogPlus: quest log height reset to default.")
		else
			print("WideQuestLogPlus: |cffffd200/wqlp reset|r - restore the default quest log height")
		end
	end

	-- Saved variables aren't available until this addon's ADDON_LOADED fires
	local loader = CreateFrame("Frame")
	loader:RegisterEvent("ADDON_LOADED")
	loader:SetScript(
		"OnEvent",
		function(self, event, name)
			if (name ~= ADDON_NAME) then
				return
			end
			self:UnregisterEvent("ADDON_LOADED")
			WideQuestLogPlusDB = WideQuestLogPlusDB or {}
			if (WideQuestLogPlusDB.height) then
				ApplyHeight(WideQuestLogPlusDB.height)
			end
		end
	)
end

-- Call the functions to customize the Quest Log appearance
WideQuestLogPlus()
