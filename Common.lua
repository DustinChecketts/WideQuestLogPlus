local _, ns = ...

-- Helpers shared by every client's quest log: text formats and saved settings

-- Saved settings, account-wide. Saved variables aren't loaded until this addon's ADDON_LOADED, so this
-- is only read from things the player does, or from the window opening
function ns.GetDB()
	WideQuestLogPlusDB = WideQuestLogPlusDB or {}
	return WideQuestLogPlusDB
end

function ns.Print(text)
	print("|cffffd200WideQuestLogPlus:|r " .. text)
end

-- Letters after the level in the quest list, by quest tag (Enum.QuestTag): D dungeon, R raid, P PvP,
-- G group. Elite quests without one of those get E
local QUEST_TAG_SUFFIX = {
	[81] = "D", -- Dungeon
	[85] = "D", -- Heroic
	[62] = "R", -- Raid
	[88] = "R", -- Raid (10)
	[89] = "R", -- Raid (25)
	[41] = "P", -- PvP
	[1] = "G" -- Group
}
local ELITE_SUFFIX = "E"

function ns.QuestSuffix(tagID, isElite)
	return (tagID and QUEST_TAG_SUFFIX[tagID]) or (isElite and ELITE_SUFFIX) or ""
end

-- "[13] Quest Name", or "[13D] Quest Name" for a dungeon quest, and so on
function ns.LevelTitle(level, title, suffix)
	return format("[%d%s] %s", level or 0, suffix or "", title or "")
end

function ns.QuestIDText(questID)
	return format("ID %d", questID)
end

-- Shows a quest ID in a FontString, in the same font and colour as source (the description) but
-- smaller
function ns.StyleQuestID(text, questID, source)
	local file, size, flags = source:GetFont()
	if (file and size) then
		text:SetFont(file, size - ns.Layout.QUEST_ID_FONT_SHRINK, flags)
	end
	text:SetTextColor(source:GetTextColor())
	text:SetText(ns.QuestIDText(questID))
end

-- Objective lines in the quest details: two spaces in, then a green check for a finished objective (or
-- a blank the same size, so the names line up), the objective's name, and its count ("8 / 8")
-- right-aligned in a column of its own at the right edge of the text column
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
local NO_CHECK = "|TInterface\\Common\\spacer:0|t"
local COUNT_GAP = 8 -- Between a name and its count

-- "8/8 Ragefire Trogg slain" (WoW Forever) or "Ragefire Trogg slain: 8/8" (Classic). Anything else, a
-- reputation objective say, is all name
local function SplitObjective(text)
	local have, need, name = text:match("^%s*(%d+)%s*/%s*(%d+)%s+(.+)$")
	if (not have) then
		name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
	end
	if (have) then
		return name, format("%s / %s", have, need)
	end
	return text
end

local objectiveCounts = {} -- Count column for each objective line, by line

-- Hides every count, before the objective lines showing now are styled
function ns.ClearObjectiveCounts()
	for _, count in pairs(objectiveCounts) do
		count:Hide()
	end
end

-- Gives a FontString the same font as another, keeping its own colour
local function MatchFont(region, source)
	local r, g, b, a = region:GetTextColor()
	local fontObject = source:GetFontObject()
	if (fontObject) then
		region:SetFontObject(fontObject)
	else
		region:SetFont(source:GetFont())
	end
	region:SetTextColor(r, g, b, a)
end

-- Restyles one of Blizzard's objective lines (a FontString), whose left edge is the left edge of a
-- text column width wide. text and finished are the objective's, from GetQuestLogLeaderBoard().
-- Blizzard draws objectives a size smaller than the rest of the quest text; they take fontSource's
-- font (the description's) instead
function ns.StyleObjective(line, text, finished, width, fontSource)
	local name, countText = SplitObjective(text or "")
	MatchFont(line, fontSource)
	line:SetText("  " .. (finished and CHECK or NO_CHECK) .. " " .. name)

	local count = objectiveCounts[line]
	if (not count) then
		count = line:GetParent():CreateFontString(nil, "ARTWORK")
		count:SetJustifyH("RIGHT")
		objectiveCounts[line] = count
	end
	if (not countText) then
		line:SetWidth(width)
		return
	end

	MatchFont(count, line)
	count:SetTextColor(line:GetTextColor())
	-- Skins (ElvUI) recolour the lines in hooks that may run after this one, so match them again after
	C_Timer.After(0, function()
		count:SetTextColor(line:GetTextColor())
	end)
	count:SetText(countText)
	count:ClearAllPoints()
	count:SetPoint("TOPRIGHT", line, "TOPLEFT", width, 0)
	count:Show()
	line:SetWidth(width - count:GetStringWidth() - COUNT_GAP)
end
