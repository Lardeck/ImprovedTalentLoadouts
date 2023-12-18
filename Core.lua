local addonName, ITL = ...
local ITL = LibStub("AceAddon-3.0"):NewAddon(ITL, addonName)

-- Libs --
local LibDDM = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")
local LibDB = LibStub:GetLibrary("LibDataBroker-1.1")

-- Constants --
local internalVersion = 10
local talentUI = "Blizzard_ClassTalentUI"
local NUM_ACTIONBAR_BUTTONS = 15 * 12
local ITL_LOADOUT_NAME = "[ITL] Temp"
local dataObjText = "ITL: %s, %s"

-- Objects --
local dataObj = LibDB:NewDataObject(addonName, {type = "data source", text = "ITL: Spec, Loadout"})
local dropdownFont = CreateFont("ITL_DropdownFont")
local RegisterEvent, UnregisterEvent

--- Create an iterator for a hash table.
-- @param t:table The table to create the iterator for.
-- @param order:function A sort function for the keys.
-- @return function The iterator usable in a loop.
local function spairs(t, order)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end

    if order then
        table.sort(
            keys,
            function(a, b)
                return order(t, a, b)
            end
        )
    else
        table.sort(keys)
    end

    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]], keys[i + 1]
        end
    end
end

local function sortByName(t, a, b)
    if t[a] and t[b] and t[a].name and t[b].name then
        return t[a].name < t[b].name
    end
end

local defaultDB = {
    global = {
        loadouts = {},
        macros = {},
        actionbars = {},
        options = {
            fontSize = 12,
            simc = true,
            showSpecButtons = true,
            specButtonType = "icon",
            applyLoadout = true,
            loadAsBlizzard = true,
            loadActionbars = false,
            loadActionbarsSpec = false,
            clearEmptySlots = false,
            findMacroByName = false,
            loadBlizzard = false,
            showCategoryName = false,
            sortLoadoutsByName = false,
            useAddOnLoadoutFallback = false,
        },
        version = 0
    },
    char = {
        macros = {}
    }
}

function ITL:OnInitialize()
    if ImprovedTalentLoadoutsDB and not ImprovedTalentLoadoutsDB.global then
        self:RefactorDB()
    end

    self.db = LibStub("AceDB-3.0"):New(addonName .. "DB", defaultDB, true)

    if not self.db.global.classesInitialized then
        self:InitializeClassDBs()
    end
end

function ITL:OnEnable()
    self:CheckForVersionUpdates()
    self:UpdateMacros()
    dropdownFont:SetFont(GameFontNormal:GetFont(), self.db.global.options.fontSize, "")

    local eventFrame = CreateFrame("Frame")
    function RegisterEvent(event)
        eventFrame:RegisterEvent(event)
    end

    function UnregisterEvent(event)
        eventFrame:UnregisterEvent(event)
    end

    RegisterEvent("ADDON_LOADED")
    RegisterEvent("PLAYER_ENTERING_WORLD")
    RegisterEvent("TRAIT_CONFIG_UPDATED")
    RegisterEvent("TRAIT_CONFIG_CREATED")
    RegisterEvent("PLAYER_REGEN_ENABLED")
    RegisterEvent("PLAYER_REGEN_DISABLED")
    RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    RegisterEvent("UPDATE_MACROS")
    RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    RegisterEvent("VOID_STORAGE_UPDATE")
    eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
        if event == "ADDON_LOADED" and arg1 == talentUI then
            self:UnregisterEvent("ADDON_LOADED")
            ITL:InitializeTalentLoadouts()
            ITL:InitializeDropdown()
            ITL:InitializeButtons()
            ITL:InitializeHooks()
        elseif event == "PLAYER_ENTERING_WORLD" then
            ITL:InitializeCharacterDB()
            ITL:SaveCurrentLoadouts()
            ITL:UpdateDataObj(ITLAPI:GetCurrentLoadout())
            ITL:DeleteTempLoadouts()
            ITL:UpdateKnownFlyouts()
        elseif event == "VOID_STORAGE_UPDATE" then
            ITL:UpdateKnownFlyouts()
        elseif event == "PLAYER_REGEN_ENABLED" then
            RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        elseif event == "PLAYER_REGEN_DISABLED" then
            UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        elseif event == "TRAIT_CONFIG_UPDATED" then
            ITL:UpdateConfig(arg1)

            if not ITL.blizzImported then
                ITL.pendingLoadout = nil
            end
        elseif event == "TRAIT_CONFIG_CREATED" and ITL.blizzImported then
            if arg1.type ~= Enum.TraitConfigType.Combat then return end
            ITL:LoadAsBlizzardLoadout(arg1)
        elseif event == "UPDATE_MACROS" then
            ITL:UpdateMacros()
        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
            ITL.charDB.lastCategory = nil
            ITL:UpdateSpecID(true)
            ITL:UpdateActionBar()
            ITL:UpdateDropdownText()
            ITL:UpdateSpecButtons()
            ITL:UpdateDataObj()
            ITL:UpdateIterator()
        elseif event == "CONFIG_COMMIT_FAILED" then
            C_Timer.After(0.1, function()
                if (ITL.pendingLoadout and not UnitCastingInfo("player")) or ITL.lastUpdated then
                    ITL:OnLoadoutFail(event)
                end
            end)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" and arg3 == Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID then
            if ITL.pendingLoadout then
                ITL:OnLoadoutSuccess()
            else
                ITL:OnUnknownLoadoutSuccess()
            end
        elseif event == "EQUIPMENT_SWAP_FINISHED" and not arg1 then
            local name = C_EquipmentSet.GetEquipmentSetInfo(arg2)
            ITL:Print("Equipment swap failed:", name)
        end
    end)
end

function ITL:RefactorDB()
    local db = CopyTable(defaultDB)

    db.global.version = ImprovedTalentLoadoutsDB.version
    db.global.classesInitialized = ImprovedTalentLoadoutsDB.classesInitialized
    db.global.options = CopyTable(ImprovedTalentLoadoutsDB.options)
    db.global.macros = CopyTable(ImprovedTalentLoadoutsDB.actionbars.macros.global)
    db.char.macros = CopyTable(ImprovedTalentLoadoutsDB.actionbars.macros.char)
    db.global.loadouts = CopyTable(ImprovedTalentLoadoutsDB.loadouts.globalLoadouts)

    ImprovedTalentLoadoutsDB = db
end

local hooks = {}
local function HookFunction(namespace, key, func)
    hooksecurefunc(namespace, key, function()
        if hooks[key] then
            func()
        end
    end)
    hooks[key] = true
end

local function UnhookFunction(key)
    hooks[key] = nil
end

function ITL:InitializeClassDBs()
    for _, className in ipairs(CLASS_SORT_ORDER) do
        self.db.global.loadouts[className] = self.db.global.loadouts[className] or {configIDs = {}, categories = {}}
    end

    self.db.global.classesInitialized = true
end

function ITL:CheckForVersionUpdates()
    local currentVersion = self.db.global.version

    if currentVersion < 10 then
        print("refactor here")
    end
end