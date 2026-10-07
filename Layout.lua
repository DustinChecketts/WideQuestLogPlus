local _, ns = ...

-- Window geometry and art shared by every client's quest log, so they all look the same: the classic
-- quest log on Classic Era and Anniversary (Legacy.lua), and the standalone window on WoW
-- Forever (Modern.lua). All x/y values are offsets from the window's top-left corner

local L = {}
ns.Layout = L

-- Quest details are as wide as two columns of reward buttons (147px each, 1px apart), which can't
-- shrink, with TEXT_MARGIN of parchment on the left, right and top
L.REWARD_COLUMNS_WIDTH = 276 -- Match the existing WQLP parchment content width
L.TEXT_MARGIN = 17

-- The classic art's parchment spans x 348-658; the window is widened by however much more it needs
local ART_PARCHMENT_LEFT, ART_PARCHMENT_RIGHT = 348, 658
L.EXTRA_WIDTH = 0 -- Canonical WQLP width; Forever must match Era/TBC, not widen it further

L.BASE_WIDTH = 724 + L.EXTRA_WIDTH
L.BASE_HEIGHT = 513
L.PANE_TOP = 75 -- Top of the quest list and the quest details
L.PANE_INSET = 151 -- Vertical space the panes never occupy
L.ROW_HEIGHT = 16

-- The quest list on the left, and the quest details 41px to its right
L.LIST_LEFT = 19
L.LIST_WIDTH = 300
L.DETAIL_LEFT = L.LIST_LEFT + L.LIST_WIDTH + 41

L.PARCHMENT_LEFT = ART_PARCHMENT_LEFT
L.PARCHMENT_RIGHT = ART_PARCHMENT_RIGHT + L.EXTRA_WIDTH
L.PARCHMENT_TOP = 74

-- Where the quest text goes: TEXT_MARGIN inside the parchment, and level with the first quest row of
-- the list (one row below the top, under the first zone header)
L.CONTENT_LEFT = L.PARCHMENT_LEFT + L.TEXT_MARGIN
L.CONTENT_WIDTH = L.REWARD_COLUMNS_WIDTH
L.CONTENT_TOP = L.PANE_TOP + L.ROW_HEIGHT

-- A blank line under the quest's title and under the Description and Rewards headings: Blizzard's 5px
-- plus a line of quest text
L.TITLE_GAP = 5
local BLIZZARD_HEADING_GAP = 5
L.EXTRA_HEADING_GAP = L.TITLE_GAP - BLIZZARD_HEADING_GAP

-- A blank line between the money ("You will receive:") and experience lines of the rewards (WoW Forever;
-- the classic quest log doesn't show experience)
L.MONEY_XP_GAP = 0

-- In WoW Forever's quest details Blizzard leaves 20px above the "Description" heading but only 10px
-- above "Rewards", which comes out ~13px shorter on screen. Keep the roomier one and match the other
-- to it
L.DESCRIPTION_GAP = 20
L.REWARDS_GAP = 10

-- Blizzard's money frames keep their last coin this far inside their right edge, so a money frame
-- right-aligned to the text column sits this much further right
L.MONEY_RIGHT_PADDING = 13

-- The quest ID sits under everything else in the quest details, right-aligned to the text column, two
-- blank lines down, in the description's font a little smaller
L.QUEST_ID_GAP = 10
L.QUEST_ID_FONT_SHRINK = 2

-- Quest list rows: zone headers have their +/- at the left and their name after it; quest titles sit
-- further in, after a slot for the tracking check that's there whether the quest is tracked or not
L.HEADER_TEXT_X = 20
L.CHECK_X = 18
L.QUEST_TEXT_X = L.CHECK_X + 16

-- Blank space above every zone header in the quest list except the first
L.HEADER_GAP = 0

-- Buttons along the bottom: the outer ones' offsets from the window's corners, and the size of the
-- ones in between
L.BUTTON_BOTTOM = 54
L.BUTTON_LEFT = 17
L.BUTTON_RIGHT = 43
L.BUTTON_WIDTH = 123
L.BUTTON_HEIGHT = 21

-- Centre of the scroll bar slot to the right of the parchment
L.DETAIL_SCROLL_SLOT_X = 673 + L.EXTRA_WIDTH

-- The drawn border stops short of the frame's own edges: the opaque part of img/WQLP_BotRight stops
-- 176px into the piece and 211px down it. The resize grip sits GRIP_INSET inside that corner
L.ART_INSET_RIGHT = L.BASE_WIDTH - (515 + L.EXTRA_WIDTH + 176)
L.ART_INSET_BOTTOM = 256 - 211 + 1
L.GRIP_INSET = 4

-- A window dragged taller still leaves this much of the screen below it
L.MIN_BOTTOM_CLAMP = 20

local IMG = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_"
local TOP_SPLIT = 0.5
local STRIP_SOURCE = 8 -- Pixels of the middle piece the widening strip is cut from

-- Draws the window art on a frame and returns a function that lays it out for a given window height.
-- Three columns of pieces, plus a strip widening the parchment where the middle and right pieces meet.
-- The strip is cut from the last few pixels of the middle piece and stretched, so both of its seams
-- continue the art on either side. The top half of each upper piece carries the window's top border
-- and keeps its proportions; only the plain lower half is stretched when the window is dragged taller
function ns.CreateWindowArt(frame, sublevel)
	local pieces = {}
	for _, column in ipairs({
		{"Left", 3, 0, 256},
		{"Mid", 259, 0, 256},
		{"Mid", 515, 1 - STRIP_SOURCE / 256, L.EXTRA_WIDTH},
		{"Right", 515 + L.EXTRA_WIDTH, 0, 256}
	}) do
		local name, x, left, width = unpack(column)
		for _, row in ipairs({"Top", "Bot"}) do
			local count = (row == "Top") and 2 or 1
			for piece = 1, count do
				local region = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
				region:SetTexture(IMG .. row .. name)
				region:SetWidth(width)
				if (count == 1) then
					region:SetTexCoord(left, 1, 0, 1)
				elseif (piece == 1) then
					region:SetTexCoord(left, 1, 0, TOP_SPLIT)
				else
					region:SetTexCoord(left, 1, TOP_SPLIT, 1)
				end
				pieces[#pieces + 1] = {region = region, x = x, row = row, piece = piece}
			end
		end
	end

	return function(height)
		local extra = height - L.BASE_HEIGHT
		for _, art in ipairs(pieces) do
			art.region:ClearAllPoints()
			if (art.row == "Top") then
				if (art.piece == 1) then
					art.region:SetHeight(256 * TOP_SPLIT)
					art.region:SetPoint("TOPLEFT", frame, "TOPLEFT", art.x, 0)
				else
					art.region:SetHeight(256 * (1 - TOP_SPLIT) + extra)
					art.region:SetPoint("TOPLEFT", frame, "TOPLEFT", art.x, -256 * TOP_SPLIT)
				end
			else
				art.region:SetHeight(256)
				art.region:SetPoint("TOPLEFT", frame, "TOPLEFT", art.x, -(height - 257))
			end
		end
	end
end

-- Snaps a window height to whole list rows, between the default height and the bottom of the screen
-- (the window grows downward from its top edge)
function ns.ClampHeight(frame, height, rowHeight)
	local base = L.BASE_HEIGHT
	height = base + math.floor((height - base) / rowHeight + 0.5) * rowHeight

	local top = frame:GetTop() or UIParent:GetHeight()
	local maxHeight = math.max(base, top - L.MIN_BOTTOM_CLAMP)
	if (height > maxHeight) then
		height = base + math.floor((maxHeight - base) / rowHeight) * rowHeight
	end
	return math.max(height, base)
end

-- A grip in the window's bottom-right corner for dragging it taller. applyHeight(height) resizes the
-- window and getHeight() returns its height now; the height it's dragged to is saved when the drag ends
function ns.CreateResizeGrip(frame, applyHeight, getHeight)
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	grip:SetPoint("BOTTOMRIGHT", -(L.ART_INSET_RIGHT + L.GRIP_INSET), L.ART_INSET_BOTTOM + L.GRIP_INSET)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Drag to resize the Quest Log")
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)

	local startY, startHeight
	local function StopSizing(self)
		if (not startY) then
			return
		end
		startY = nil
		self:SetScript("OnUpdate", nil)
		ns.GetDB().height = getHeight()
	end

	grip:SetScript("OnMouseDown", function(self)
		local _, y = GetCursorPosition()
		startY, startHeight = y / frame:GetEffectiveScale(), getHeight()
		self:SetScript("OnUpdate", function(this)
			if (not IsMouseButtonDown("LeftButton")) then
				StopSizing(this) -- The mouse-up went somewhere else
				return
			end
			local _, cursorY = GetCursorPosition()
			applyHeight(startHeight + (startY - cursorY / frame:GetEffectiveScale()))
		end)
	end)
	grip:SetScript("OnMouseUp", StopSizing)
	grip:SetScript("OnHide", StopSizing)

	return grip
end
