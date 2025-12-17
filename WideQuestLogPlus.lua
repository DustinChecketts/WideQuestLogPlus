--- CONSTANTS & LOCALS
local _G = _G
local format = string.format
local hooksecurefunc = hooksecurefunc
local C_AddOns = C_AddOns
local GetQuestLogTitle = GetQuestLogTitle
local GetNumQuestLogEntries = GetNumQuestLogEntries
local GetQuestLogSelection = GetQuestLogSelection
local FauxScrollFrame_GetOffset = FauxScrollFrame_GetOffset
local IsCurrentQuestFailed = IsCurrentQuestFailed

local EXTRA_QUEST_ROWS = 17
local WIDE_LOG_WIDTH = 724
local WIDE_LOG_HEIGHT = 513
local LIST_HEIGHT = 362

--- PANEL CONFIGURATION
UIPanelWindows["QuestLogFrame"] = {
    area = "override",
    pushable = 0,
    xoffset = -16,
    yoffset = 12,
    bottomClampOverride = 152,
    width = WIDE_LOG_WIDTH,
    height = WIDE_LOG_HEIGHT,
    whileDead = 1
}

--- LOGIC & HOOKS
local function IsVoiceOverEnabled()
    local name, _, _, enabled = C_AddOns.GetAddOnInfo("AI_VoiceOver")
    return name and enabled
end

local function UpdateQuestLogDisplay()
    local numEntries = GetNumQuestLogEntries()
    if numEntries == 0 then
        return
    end

    local isVoiceOverLoaded = IsVoiceOverEnabled()
    local offset = FauxScrollFrame_GetOffset(QuestLogListScrollFrame)
    local questIndex, questLogTitle, title, level, isHeader, questCheck, questTextFormatted

    for i = 1, _G.QUESTS_DISPLAYED do
        questIndex = i + offset
        if questIndex <= numEntries then
            questLogTitle = _G["QuestLogTitle" .. i]
            questCheck = _G["QuestLogTitle" .. i .. "Check"]
            title, level, _, isHeader = GetQuestLogTitle(questIndex)

            if not isHeader then
                if isVoiceOverLoaded then
                    questTextFormatted = format("       [%d] %s", level, title)
                else
                    questTextFormatted = format("[%d] %s", level, title)
                end

                questLogTitle:SetText(questTextFormatted)
                questCheck:SetPoint("LEFT", questLogTitle, "LEFT", questLogTitle.Text:GetStringWidth() + 18, 0)
                questCheck:SetVertexColor(0.25, 0.88, 0.82)
                questCheck:SetDrawLayer("ARTWORK")
            else
                questCheck:Hide()
            end
        end
    end

    local selectionIndex = GetQuestLogSelection()
    local selTitle, _, _, _, _, _, _, selID = GetQuestLogTitle(selectionIndex)

    if selTitle then
        selTitle = format("%s [%d]", selTitle, selID)
        if IsCurrentQuestFailed() then
            selTitle = format("%s - (%s)", selTitle, _G.FAILED)
        end
        QuestLogQuestTitle:SetText(selTitle)
    end
end

--- INITIALIZATION
local function InitializeWideQuestLog()
    QuestLogFrame:SetWidth(WIDE_LOG_WIDTH)
    QuestLogFrame:SetHeight(WIDE_LOG_HEIGHT)

    QuestLogTitleText:ClearAllPoints()
    QuestLogTitleText:SetPoint("TOP", QuestLogFrame, "TOP", 0, -17)

    QuestLogDetailScrollFrame:ClearAllPoints()
    QuestLogDetailScrollFrame:SetPoint("TOPLEFT", QuestLogListScrollFrame, "TOPRIGHT", 41, 0)
    QuestLogDetailScrollFrame:SetHeight(LIST_HEIGHT)

    QuestLogNoQuestsText:ClearAllPoints()
    QuestLogNoQuestsText:SetPoint("TOP", QuestLogListScrollFrame, 0, -90)

    QuestLogListScrollFrame:SetHeight(LIST_HEIGHT)

    local oldQuestsDisplayed = _G.QUESTS_DISPLAYED
    _G.QUESTS_DISPLAYED = _G.QUESTS_DISPLAYED + EXTRA_QUEST_ROWS

    for i = oldQuestsDisplayed + 1, _G.QUESTS_DISPLAYED do
        local button = CreateFrame("Button", "QuestLogTitle" .. i, QuestLogFrame, "QuestLogTitleButtonTemplate")
        button:SetID(i)
        button:Hide()
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", _G["QuestLogTitle" .. (i - 1)], "BOTTOMLEFT", 0, 1)
    end

    hooksecurefunc("QuestLog_Update", UpdateQuestLogDisplay)
end

--- UI RESKINNING
local function ApplyTextures()
    local xOffsets = {Left = 3, Middle = 259, Right = 515}
    local yOffsets = {Top = 0, Bot = -256}
    local textures = {
        TopLeft = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_TopLeft",
        TopMiddle = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_TopMid",
        TopRight = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_TopRight",
        BotLeft = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_BotLeft",
        BotMiddle = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_BotMid",
        BotRight = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_BotRight"
    }

    local regions = {QuestLogFrame:GetRegions()}
    local PATTERN = "^Interface\\QuestFrame\\UI%-QuestLog%-(([A-Z][a-z]+)([A-Z][a-z]+))$"

    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") then
            local texturePath = region:GetTextureFilePath()
            if texturePath then
                local which, yOfs, xOfs = texturePath:match(PATTERN)
                if which and textures[which] then
                    region:SetTexture(nil)
                    region:SetAlpha(0)
                end
            end
        end
    end

    for name, path in pairs(textures) do
        local yKey, xKey = name:match("^([A-Z][a-z]+)([A-Z][a-z]+)$")
        if xOffsets[xKey] and yOffsets[yKey] then
            local region = QuestLogFrame:CreateTexture(nil, "ARTWORK", nil, 2)
            region:SetPoint("TOPLEFT", QuestLogFrame, "TOPLEFT", xOffsets[xKey], yOffsets[yKey])
            region:SetSize(256, 256)
            region:SetTexture(path)
        end
    end

    local nxSize = QuestLogDetailScrollFrame:GetWidth() + 26
    local nySize = QuestLogDetailScrollFrame:GetHeight() + 8
    local fullWidth, fullHeight = 320, 384

    local emptyRegions = {EmptyQuestLogFrame:GetRegions()}
    for _, region in ipairs(emptyRegions) do
        if region:IsObjectType("Texture") then
            local path = region:GetTextureFilePath()
            if type(path) == "string" then
                local suffix = path:match("-([^-]+)$")
                if suffix then
                    if suffix == "TopLeft" then
                        region:SetTexCoord(0, 1, 0.37, 1)
                        region:SetPoint("TOPLEFT", QuestLogDetailScrollFrame, -10, 8)
                        region:SetSize((256 / fullWidth) * nxSize, (161 / fullHeight) * nySize)
                    elseif suffix == "TopRight" then
                        region:SetTexCoord(0, 1, 0.37, 1)
                        region:SetPoint("TOPLEFT", QuestLogDetailScrollFrame, (256 / fullWidth) * nxSize - 10, 8)
                        region:SetSize((64 / fullWidth) * nxSize, (161 / fullHeight) * nySize)
                    elseif suffix == "BotLeft" then
                        region:SetTexCoord(0, 1, 0, 0.83)
                        region:SetPoint("TOPLEFT", QuestLogDetailScrollFrame, -10, 8 - ((161 / fullHeight) * nySize))
                        region:SetSize((256 / fullWidth) * nxSize, (106 / fullHeight) * nySize)
                    elseif suffix == "BotRight" then
                        region:SetTexCoord(0, 1, 0, 0.83)
                        region:SetPoint(
                            "TOPLEFT",
                            QuestLogDetailScrollFrame,
                            (256 / fullWidth) * nxSize - 10,
                            8 - ((161 / fullHeight) * nySize)
                        )
                        region:SetSize((64 / fullWidth) * nxSize, (106 / fullHeight) * nySize)
                    else
                        region:Hide()
                    end
                end
            end
        end
    end
end

InitializeWideQuestLog()
ApplyTextures()
