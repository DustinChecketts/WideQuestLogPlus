local _, ns = ...

-- Central client compatibility layer.
-- Presentation remains client-specific: Classic.lua enhances Blizzard's native quest log,
-- while Forever.lua recreates that experience where QuestLogFrame no longer exists.

local Compat = {}
ns.Compat = Compat

local projectID = WOW_PROJECT_ID

Compat.projectID = projectID
Compat.isMainline = WOW_PROJECT_MAINLINE and projectID == WOW_PROJECT_MAINLINE or false
Compat.isClassic = WOW_PROJECT_CLASSIC and projectID == WOW_PROJECT_CLASSIC or false
Compat.hasClassicQuestLog = QuestLogFrame ~= nil

-- WoW Forever currently reports WOW_PROJECT_ID == 1 like Mainline, so project ID alone
-- cannot identify it. The 16xxx interface generation is the stable discriminator available
-- to this addon, with the missing Classic QuestLogFrame as an additional guard.
local interfaceVersion = select(4, GetBuildInfo())
Compat.interfaceVersion = interfaceVersion or 0
Compat.isForever = not Compat.hasClassicQuestLog
	and Compat.interfaceVersion >= 16000
	and Compat.interfaceVersion < 17000

-- Supported native Classic clients are Era-family (11xxx) and Anniversary TBC (20xxx).
Compat.isClassicEra = Compat.hasClassicQuestLog
	and Compat.interfaceVersion >= 11000
	and Compat.interfaceVersion < 12000
Compat.isAnniversaryTBC = Compat.hasClassicQuestLog
	and Compat.interfaceVersion >= 20000
	and Compat.interfaceVersion < 21000
Compat.isSupportedClassic = Compat.isClassicEra or Compat.isAnniversaryTBC
Compat.isSupported = Compat.isSupportedClassic or Compat.isForever
