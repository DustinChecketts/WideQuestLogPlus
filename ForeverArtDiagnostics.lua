local _, ns = ...
if not (ns.Compat and ns.Compat.isForever) then return end

-- Read-only native art inventory. Writes a report to our own SavedVariables only.
-- No Blizzard frames, textures, anchors, or templates are modified.
local targets = {
    map = function() return WorldMapFrame end,
    quests = function() return QuestMapFrame end,
    professions = function() return ProfessionsFrame or TradeSkillFrame end,
    character = function() return CharacterFrame end,
    friends = function() return FriendsFrame end,
    talents = function() return PlayerTalentFrame or ClassTalentFrame end,
    addon = function() return WideQuestLogPlusFrame end,
}
local function Safe(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then return nil end
    local ok, result = pcall(obj[method], obj, ...)
    if ok then return result end
end
local function Describe(obj)
    local record = {
        type = Safe(obj, "GetObjectType"),
        name = Safe(obj, "GetName"),
        width = Safe(obj, "GetWidth"),
        height = Safe(obj, "GetHeight"),
        shown = Safe(obj, "IsShown"),
        atlas = Safe(obj, "GetAtlas"),
        texture = Safe(obj, "GetTexture"),
        drawLayer = Safe(obj, "GetDrawLayer"),
    }
    if type(record.texture) ~= "string" and type(record.texture) ~= "number" then
        record.texture = nil
    end
    local parent = Safe(obj, "GetParent")
    record.parent = parent and (Safe(parent, "GetName") or Safe(parent, "GetObjectType")) or nil
    return record
end
local function Scan(root)
    local report = {root = Describe(root), regions = {}, frames = {}, truncated = false}
    local seen, count = {}, 0
    local function Walk(frame, path, depth)
        if seen[frame] or depth > 3 or count >= 220 then
            if count >= 220 then report.truncated = true end
            return
        end
        seen[frame] = true
        count = count + 1
        local data = Describe(frame)
        data.path = path
        if frame.NineSlice then
            data.hasNineSlice = true
        end
        report.frames[#report.frames + 1] = data
        local regions = {frame:GetRegions()}
        for i, region in ipairs(regions) do
            local regionData = Describe(region)
            if regionData.atlas or regionData.texture then
                regionData.path = path .. "/region" .. i
                report.regions[#report.regions + 1] = regionData
            end
        end
        if depth < 3 then
            local children = {frame:GetChildren()}
            for i, child in ipairs(children) do
                Walk(child, path .. "/" .. (Safe(child, "GetName") or ("child" .. i)), depth + 1)
            end
        end
    end
    Walk(root, Safe(root, "GetName") or "root", 0)
    return report
end

SLASH_WQLP_FRAMEART1 = "/wqlpframeart"
SlashCmdList.WQLP_FRAMEART = function(msg)
    local key = (msg or ""):match("^%s*(%S+)") or ""
    if key == "help" or key == "" then
        ns.Print("Usage: /wqlpframeart map | quests | professions | character | friends | talents | addon")
        ns.Print("Open the native window first; report is saved in WideQuestLogPlusDB.frameArtDiagnostics.")
        return
    end
    local getter = targets[key]
    if not getter then ns.Print("Unknown target. Use /wqlpframeart help") return end
    local root = getter()
    if not root then ns.Print("Frame not loaded: " .. key .. ". Open its window first.") return end
    local result = Scan(root)
    local db = ns.GetDB()
    db.frameArtDiagnostics = db.frameArtDiagnostics or {}
    db.frameArtDiagnostics[key] = result
    ns.Print(("Captured %s: %d frames, %d textured regions%s. /reload or logout to save."):format(
        key, #result.frames, #result.regions, result.truncated and " (truncated)" or ""))
end
