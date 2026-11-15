local ADDON_NAME, ns = ...

-- Shared, account-wide presentation preferences. The settings page is registered after
-- SavedVariables load; the active client renderer supplies its own refresh callback.
local defaults = { showQuestLevel = true, showQuestID = true }

function ns.GetOption(key)
	local value = ns.GetDB()[key]
	if value == nil then
		return defaults[key]
	end
	return value
end

function ns.RegisterOptionsRefresh(callback)
	ns.RefreshOptions = callback
end

local function SetOption(key, value)
	ns.GetDB()[key] = value and true or false
	if ns.RefreshOptions then
		ns.RefreshOptions()
	end
end

local panel = CreateFrame("Frame")
panel.name = ADDON_NAME

local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
heading:SetPoint("TOPLEFT", 16, -16)
heading:SetText(ADDON_NAME)

local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
description:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -10)
description:SetText("Quest log display options")

local function AddCheckbox(label, key, anchor, offset)
	local check = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
	check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset)
	check.Text:SetText(label)
	check:SetScript("OnClick", function(self)
		SetOption(key, self:GetChecked())
	end)
	check:SetScript("OnShow", function(self)
		self:SetChecked(ns.GetOption(key))
	end)
	return check
end

local levelCheck = AddCheckbox("Show Quest Level", "showQuestLevel", description, -16)
AddCheckbox("Show Quest ID", "showQuestID", levelCheck, -10)

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON_NAME then
		return
	end
	self:UnregisterEvent("ADDON_LOADED")
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end)
