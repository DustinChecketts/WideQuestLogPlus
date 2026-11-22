local _, ns = ...
-- Recognized Classic-era dungeon quest-log headers. Only exact normalized header
-- names are classified; dungeon-tagged quests in outdoor zones remain outdoors.
-- Extend this table with verified Forever-specific dungeon headers as discovered.
local names = {
    "Ragefire Chasm", "The Deadmines", "Wailing Caverns", "Shadowfang Keep",
    "Blackfathom Deeps", "The Stockade", "Stormwind Stockade", "Gnomeregan",
    "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs", "Uldaman",
    "Zul'Farrak", "Maraudon", "The Temple of Atal'Hakkar", "Sunken Temple",
    "Blackrock Depths", "Lower Blackrock Spire", "Upper Blackrock Spire",
    "Blackrock Spire", "Dire Maul", "Scholomance", "Stratholme",
}
local dungeonHeaders = {}
for _, name in ipairs(names) do
    dungeonHeaders[name:lower()] = true
end
function ns.IsDungeonQuestHeader(title)
    return type(title) == "string" and dungeonHeaders[title:match("^%s*(.-)%s*$"):lower()] == true
end
