local addonName, TalentLoadouts = ...

local talentUI = "Blizzard_ClassTalentUI"
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")
local internalVersion = 7
local NUM_ACTIONBAR_BUTTONS = 15 * 12
local ITL_LOADOUT_NAME = "[ITL] Temp"

local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
local dataObjText = "ITL: %s, %s"
local dataObj = LDB:NewDataObject(addonName, {type = "data source", text = "ITL: Spec, Loadout", OnClick = function(self) TalentLoadouts.easyMenuAnchor = self LibDD:ToggleDropDownMenu(1, nil, TalentLoadouts.easyMenu, self, 0, 0); end})

local dropdownFont = CreateFont("ITL_DropdownFont")
local iterateLoadouts, iterateCategories

local delayed = {}

--- Create an iterator for a hash table.
-- @param t:table The table to create the iterator for.
-- @param order:function A sort function for the keys.
-- @return function The iterator usable in a loop.
local function spairs(t, order, categoryKey)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end

    if order then
        table.sort(
            keys,
            function(a, b)
                return order(t, a, b, categoryKey)
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

local function sortByValue(t, a, b)
    if t[a] and t[b] then
        return t[a] < t[b]
    end
end

local function sortByOrderAndName(t, a, b, categoryKey)
    if t[a] and t[b] then
        if categoryKey then
            local orderA = t[a].categoryCustomOrder and t[a].categoryCustomOrder[categoryKey] or 1000
            local orderB = t[b].categoryCustomOrder and t[b].categoryCustomOrder[categoryKey] or 1000

            return (orderA < orderB) or (orderA == orderB and (t[a].name < t[b].name))
        else
            local orderA = t[a].customOrder or 1000
            local orderB = t[b].customOrder or 1000

            return (orderA < orderB) or (orderA == orderB and (t[a].name < t[b].name))
        end
    end
end

local function sortByOrder(t, a, b, categoryKey)
    if categoryKey then
        local orderA = t[a].categoryCustomOrder and t[a].categoryCustomOrder[categoryKey] or 1000
        local orderB = t[b].categoryCustomOrder and t[b].categoryCustomOrder[categoryKey] or 1000

        return (orderA < orderB) or (orderA == orderB and (a < b))
    else
        local orderA = t[a].customOrder or 1000
        local orderB = t[b].customOrder or 1000

        return (orderA < orderB) or (orderA == orderB and (a < b))
    end
end

local function sortByKey(t, a, b)
    if a and b then
        return a < b
    end
end

local defaultDB = {
    loadouts = {
        globalLoadouts = {},
        characterLoadouts = {},
    },
    actionbars = {
        macros = {
            global = {},
            char = {},
        }
    }
}

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

local RegisterEvent, UnregisterEvent
do
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
    RegisterEvent("MODIFIER_STATE_CHANGED")
    eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
        if event == "ADDON_LOADED" then
            if arg1 == addonName then
                TalentLoadouts:Initialize()
                TalentLoadouts:InitializeEasyMenu()
            elseif arg1 == talentUI then
                self:UnregisterEvent("ADDON_LOADED")
                TalentLoadouts:UpdateSpecID()
                TalentLoadouts:InitializeTalentLoadouts()
                TalentLoadouts:InitializeDropdown()
                TalentLoadouts:InitializeButtons()
                TalentLoadouts:InitializeHooks()
            end
        elseif event == "PLAYER_ENTERING_WORLD" and (arg1 or arg2) then
            TalentLoadouts:InitializeCharacterDB()
            TalentLoadouts:SaveCurrentLoadouts()
            TalentLoadouts:UpdateDataObj(ITLAPI:GetCurrentLoadout())
            TalentLoadouts:DeleteTempLoadouts()
            TalentLoadouts:UpdateKnownFlyouts()
        elseif event == "VOID_STORAGE_UPDATE" then
            TalentLoadouts:UpdateKnownFlyouts()
        elseif event == "PLAYER_REGEN_ENABLED" then
            RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

            for _, func in pairs(delayed) do
                func()
            end

            delayed = {}
        elseif event == "PLAYER_REGEN_DISABLED" then
            UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        elseif event == "TRAIT_CONFIG_UPDATED" then
            TalentLoadouts:UpdateConfig(arg1)

            if not TalentLoadouts.blizzImported then
                TalentLoadouts.pendingLoadout = nil
            end
        elseif event == "TRAIT_CONFIG_CREATED" and TalentLoadouts.blizzImported then
            if arg1.type ~= Enum.TraitConfigType.Combat then return end
            TalentLoadouts:LoadAsBlizzardLoadout(arg1)
        elseif event == "UPDATE_MACROS" then
            TalentLoadouts:UpdateMacros()
        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
            TalentLoadouts.charDB.lastCategory = nil
            TalentLoadouts:UpdateSpecID(true)
            TalentLoadouts:UpdateDropdownText()
            TalentLoadouts:UpdateSpecButtons()
            TalentLoadouts:UpdateDataObj()
            TalentLoadouts:UpdateLoadoutIterator()
            TalentLoadouts:UpdateCategoryIterator()

            if not InCombatLockdown() then
                TalentLoadouts:UpdateKnownFlyouts()
                TalentLoadouts:UpdateActionBar()
            else
                delayed.UpdateActionBar = delayed.UpdateActionBar or GenerateClosure(TalentLoadouts.UpdateActionBar, TalentLoadouts)
                delayed.UpdateKnownFlyouts = delayed.UpdateKnownFlyouts or GenerateClosure(TalentLoadouts.UpdateKnownFlyouts, TalentLoadouts)
            end
        elseif event == "CONFIG_COMMIT_FAILED" then
            C_Timer.After(0.1, function()
                if (TalentLoadouts.pendingLoadout and not UnitCastingInfo("player")) or TalentLoadouts.lastUpdated then
                    TalentLoadouts:OnLoadoutFail(event)
                end
            end)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" and arg3 == Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID then
            if TalentLoadouts.pendingLoadout then
                TalentLoadouts:OnLoadoutSuccess()
            else
                TalentLoadouts:OnUnknownLoadoutSuccess()
            end
        elseif event == "EQUIPMENT_SWAP_FINISHED" and not arg1 then
            local name = C_EquipmentSet.GetEquipmentSetInfo(arg2)
            TalentLoadouts:Print("Equipment swap failed:", name)
        elseif event == "MODIFIER_STATE_CHANGED" and TalentLoadouts.saveButton and TalentLoadouts.saveButton:IsShown() then
            if IsShiftKeyDown() or IsControlKeyDown() then
                TalentLoadouts.saveButton:Enable()
                if GetMouseFocus() == TalentLoadouts.saveButton then
                    TalentLoadouts.saveButton:SetButtonState("NORMAL")
                end
            else
                TalentLoadouts.saveButton:Disable()
            end
        end
    end)
end

local function GetPlayerName()
    local name, realm = UnitName("player"), GetNormalizedRealmName()
    return name .. "-" .. realm
end

function TalentLoadouts:Initialize()
    ImprovedTalentLoadoutsDB = ImprovedTalentLoadoutsDB or TalentLoadoutProfilesDB or defaultDB
    if not ImprovedTalentLoadoutsDB.classesInitialized then
        self:InitializeClassDBs()
        ImprovedTalentLoadoutsDB.classesInitialized = true
    end
    self:CheckForDBUpdates()
    dropdownFont:SetFont(GameFontNormal:GetFont(), ImprovedTalentLoadoutsDB.options.fontSize, "")
end

function TalentLoadouts:InitializeClassDBs()
    local classes = {"HUNTER", "WARLOCK", "PRIEST", "PALADIN", "MAGE", "ROGUE", "DRUID", "SHAMAN", "WARRIOR", "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER"}
    for i, className in ipairs(classes) do
        ImprovedTalentLoadoutsDB.loadouts.globalLoadouts[className] = ImprovedTalentLoadoutsDB.loadouts.globalLoadouts[className] or {configIDs = {}, categories = {}}
    end
end

function TalentLoadouts:InitializeCharacterDB()
    local playerName = GetPlayerName()
    if not ImprovedTalentLoadoutsDB.loadouts.characterLoadouts[playerName] then
        ImprovedTalentLoadoutsDB.loadouts.characterLoadouts[playerName] = {}
    end

    if not ImprovedTalentLoadoutsDB.actionbars.macros.char[playerName] then
        ImprovedTalentLoadoutsDB.actionbars.macros.char[playerName] = {}
    end

    ImprovedTalentLoadoutsDB.actionbars.macros.global = ImprovedTalentLoadoutsDB.actionbars.macros.global or {}
    self.charDB = ImprovedTalentLoadoutsDB.loadouts.characterLoadouts[playerName]
    self.globalDB = ImprovedTalentLoadoutsDB.loadouts.globalLoadouts[UnitClassBase("player")]
    self.charMacros = ImprovedTalentLoadoutsDB.actionbars.macros.char[playerName]
    self.globalMacros = ImprovedTalentLoadoutsDB.actionbars.macros.global
    self.flyouts = {}
    self.specID = PlayerUtil.GetCurrentSpecID()
    self:CheckDBIntegrity()
    self:CheckForVersionUpdates()
    self.initialized = true
    self:UpdateMacros()
end

-- Not sure how that can happen but apparently it was a problem for someone. Maybe there is another AddOn that overwrites my db?
function TalentLoadouts:CheckDBIntegrity()
    ImprovedTalentLoadoutsDB.loadouts = ImprovedTalentLoadoutsDB.loadouts or {globalLoadouts = {}, characterLoadouts = {}}
    ImprovedTalentLoadoutsDB.loadouts.globalLoadouts = ImprovedTalentLoadoutsDB.loadouts.globalLoadouts or {}
    ImprovedTalentLoadoutsDB.loadouts.characterLoadouts = ImprovedTalentLoadoutsDB.loadouts.characterLoadouts or {}

    if not self.globalDB then
        ImprovedTalentLoadoutsDB.classesInitialized = nil
        self:Initialize()
        self.globalDB = ImprovedTalentLoadoutsDB.loadouts.globalLoadouts[UnitClassBase("player")]
    end

    if not self.charDB then
        local playerName = GetPlayerName()
        self.charDB = ImprovedTalentLoadoutsDB.loadouts.characterLoadouts[playerName]
    end

    self.charDB.cachedActionbars = self.charDB.cachedActionbars or {}
end

function TalentLoadouts:CheckForDBUpdates()
    ImprovedTalentLoadoutsDB.options = ImprovedTalentLoadoutsDB.options or {
        fontSize = ImprovedTalentLoadoutsDB.fontSize or 10,
        simc = ImprovedTalentLoadoutsDB.simc == nil and true or ImprovedTalentLoadoutsDB.simc,
        applyLoadout = ImprovedTalentLoadoutsDB.applyLoadout == nil and true or ImprovedTalentLoadoutsDB.applyLoadout,
        showSpecButtons = ImprovedTalentLoadoutsDB.showSpecButtons == nil and true or ImprovedTalentLoadoutsDB.showSpecButtons,
        specButtonType = "text",
    }

    local options = ImprovedTalentLoadoutsDB.options
    local optionKeys = {
        ["loadActionbars"] = true,
        ["clearEmptySlots"] = false,
        ["findMacroByName"] = false,
        ["loadBlizzard"] = false,
        ["showCategoryName"] = false,
        ["sortLoadoutsByName"] = false,
        ["sortCategoriesByName"] = false,
        ["sortSubcategoriesByName"] = false,
        ["loadActionbarsSpec"] = false,
        ["loadAsBlizzard"] = true,
        ["useAddOnLoadoutFallback"] = false,
        ["findMatchingLoadout"] = true,
        ["showCustomOrder"] = true,
    }

    for key, defaultValue in pairs(optionKeys) do
        if options[key] == nil then
            options[key] = defaultValue
        end
    end
end


function TalentLoadouts:CheckForVersionUpdates()
    local currentVersion = ImprovedTalentLoadoutsDB.version

    if (currentVersion or 0) < 7 then
        ImprovedTalentLoadoutsDB.options.loadAsBlizzard = true
    end

    ImprovedTalentLoadoutsDB.version = internalVersion
end

function TalentLoadouts:GetTreeID(configInfo)
    return (configInfo and configInfo.treeIDs[1]) or (ClassTalentFrame and ClassTalentFrame.TalentsTab:GetTalentTreeID()) or (C_ClassTalents.GetActiveConfigID() and C_Traits.GetConfigInfo(C_ClassTalents.GetActiveConfigID()).treeIDs[1])
end

function TalentLoadouts:UpdateSpecID(isRespec)
    --if not self.loaded then
    --    UIParentLoadAddOn("Blizzard_ClassTalentUI")
    --    self.loaded = true
    --end

    self.specID = PlayerUtil.GetCurrentSpecID()
    self.treeID = self:GetTreeID() or self.treeID

    if isRespec then
        StaticPopup_Hide("TALENTLOADOUTS_LOADOUT_DELETE_ALL")
        self.charDB.lastLoadout = nil
    end
end

function TalentLoadouts:UpdateActionBar()
    if not ImprovedTalentLoadoutsDB.options.loadActionbarsSpec then return end

    local currentSpecID = self.specID
    local configInfo = self.globalDB.configIDs[currentSpecID][self.charDB[currentSpecID]]
    if configInfo and configInfo.actionBars then
        -- Players are reporting that it sometimes doesn't work after changing the specialization. As I can't reproduce I will add a small delay for now, maybe that fixes it.
        C_Timer.After(0.1, function()
            self:LoadActionBar(configInfo.actionBars, configInfo.name)
        end)
    elseif not configInfo then
        self:Print("Couldn't find the last loadout of the spec. Make sure that the dropdown doesn't say \"Unknown\". This means that you've changed the tree without updating a loadout.")
    end
end

function TalentLoadouts:UpdateLoadoutIterator(categoryKey)
    local currentSpecID = self.specID
    if ImprovedTalentLoadoutsDB.options.sortLoadoutsByName then
        iterateLoadouts = GenerateClosure(spairs, TalentLoadouts.globalDB.configIDs[currentSpecID] or {}, sortByOrderAndName, categoryKey)
    else
        iterateLoadouts = GenerateClosure(spairs, TalentLoadouts.globalDB.configIDs[currentSpecID] or {}, sortByOrder, categoryKey)
    end
end

function TalentLoadouts:UpdateCategoryIterator()
    local currentSpecID = self.specID
    if ImprovedTalentLoadoutsDB.options.sortCategoriesByName then
        iterateCategories = GenerateClosure(spairs, TalentLoadouts.globalDB.categories[currentSpecID] or {}, sortByName)
    else
        iterateCategories = GenerateClosure(pairs, TalentLoadouts.globalDB.categories[currentSpecID] or {})
    end
end


-- WIP, Wasn't able to reproduce the issue of empty loadout info
local function CreateEntryInfoFromString(configID, exportString, treeID, repeating)
    configID = C_Traits.GetConfigInfo(configID) and configID or C_ClassTalents.GetActiveConfigID()
    local treeID = TalentLoadouts:GetTreeID()
    local importStream = ExportUtil.MakeImportDataStream(exportString)
    local _ = securecallfunction(ClassTalentFrame.TalentsTab.ReadLoadoutHeader, ClassTalentFrame.TalentsTab, importStream)
    local loadoutContent = securecallfunction(ClassTalentFrame.TalentsTab.ReadLoadoutContent, ClassTalentFrame.TalentsTab, importStream, treeID)
    local success, loadoutEntryInfo = pcall(ClassTalentFrame.TalentsTab.ConvertToImportLoadoutEntryInfo, ClassTalentFrame.TalentsTab, configID, treeID, loadoutContent)
    -- TalentLoadouts:Print(success, loadoutEntryInfo and #loadoutEntryInfo)
    if success and #loadoutEntryInfo > 0 then
        return loadoutEntryInfo
    elseif not repeating then
        return CreateEntryInfoFromString(configID, exportString, treeID, true)
    else
        TalentLoadouts:Print("Wasn't able to import the loadout. Try reloading or restarting your game.")
    end
end

local function CreateExportString(configInfo, configID, specID, skipEntryInfo)
    local treeID = TalentLoadouts:GetTreeID(configInfo)
    local treeHash = treeID and C_Traits.GetTreeHash(treeID);

    if treeID and treeID == TalentLoadouts.treeID then
        local serializationVersion = C_Traits.GetLoadoutSerializationVersion()
        local dataStream = ExportUtil.MakeExportDataStream()

        ClassTalentFrame.TalentsTab:WriteLoadoutHeader(dataStream, serializationVersion, specID, treeHash)
        ClassTalentFrame.TalentsTab:WriteLoadoutContent(dataStream , configID, treeID)

        local exportString = dataStream:GetExportString()

        local loadoutEntryInfo
        if not skipEntryInfo then
            loadoutEntryInfo = CreateEntryInfoFromString(configID, exportString, treeID)
        end

        return exportString, loadoutEntryInfo, treeHash
    end
end

function TalentLoadouts:InitializeTalentLoadouts()
    if not self.globalDB or not self.charDB then
        self:CheckDBIntegrity()
    end

    local specConfigIDs = self.globalDB.configIDs
    local currentSpecID = self.specID
    if specConfigIDs[currentSpecID] then
        for configID, configInfo in pairs(specConfigIDs[currentSpecID]) do
            if C_Traits.GetConfigInfo(configID) and (not configInfo.exportString or not configInfo.entryInfo or not configInfo.treeHash) then
                configInfo.exportString, configInfo.entryInfo, configInfo.treeHash = CreateExportString(configInfo, configID, currentSpecID)
            end
        end
    else
        self:UpdateSpecID()
        self:SaveCurrentLoadouts()
    end

    self.loaded = true
end

function TalentLoadouts:InitializeTalentLoadout(newConfigID)
    local specConfigIDs = self.globalDB.configIDs
    local currentSpecID = self.specID
    if not specConfigIDs[currentSpecID] then
        self:UpdateSpecID()
        currentSpecID = self.specID
        specConfigIDs[currentSpecID] = {}
    end

    local configID = C_Traits.GetConfigInfo(newConfigID) and newConfigID or C_ClassTalents.GetActiveConfigID()
    local configInfo = specConfigIDs[currentSpecID][newConfigID]
    if configInfo and (not configInfo.exportString or not configInfo.entryInfo or not configInfo.treeHash) then
        configInfo.exportString, configInfo.entryInfo, configInfo.treeHash = CreateExportString(configInfo, configID, currentSpecID)
    end
end

function TalentLoadouts:UpdateConfig(configID)
    if not self.loaded then
        UIParentLoadAddOn("Blizzard_ClassTalentUI")
        self.loaded = true
        self:UpdateConfig(configID)
        return
    end

    local currentSpecID = self.specID
    local configInfo = self.globalDB.configIDs[currentSpecID][configID]
    if configInfo then
        local newConfigInfo = C_Traits.GetConfigInfo(configID)
        configInfo.exportString, configInfo.entryInfo = CreateExportString(configInfo, configID, currentSpecID)
        configInfo.name = newConfigInfo and newConfigInfo.name or configInfo.name
    else
        self:SaveLoadout(configID, currentSpecID)
    end
end

function TalentLoadouts:SaveLoadout(configID, currentSpecID)
    local specLoadouts = self.globalDB.configIDs[currentSpecID]
    local configInfo = C_Traits.GetConfigInfo(configID)
    if configInfo.type == 1 and configInfo.name ~= ITL_LOADOUT_NAME then
        configInfo.default = configID == C_ClassTalents.GetActiveConfigID() or nil
        specLoadouts[configID] = configInfo
        self:InitializeTalentLoadout(configID)
    end
end

-- Delete duplicate Temp Loadouts
function TalentLoadouts:DeleteTempLoadouts()
    if InCombatLockdown() then return end

    local specID = self.specID
    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)

    local counter = 0
    for _, configID in ipairs(configIDs) do
        local configInfo = C_Traits.GetConfigInfo(configID)
        if configInfo.name == ITL_LOADOUT_NAME then
            if counter > 1 then
                C_ClassTalents.DeleteConfig(configID)
            else
                self.charDB.tempLoadout = configID
            end

            counter = counter + 1
        end
    end

    if ClassTalentFrame and ClassTalentFrame:IsShown() then
        C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, nil)
        securecall(ClassTalentFrame.TalentsTab.RefreshLoadoutOptions, ClassTalentFrame.TalentsTab)
        securecall(ClassTalentFrame.TalentsTab.LoadoutDropDown.ClearSelection, ClassTalentFrame.TalentsTab.LoadoutDropDown)
    end

    self.pendingDeletion = nil
end


function TalentLoadouts:GetExportStringForTree(skipEntryInfo)
    return CreateExportString(nil, C_ClassTalents.GetActiveConfigID(), self.specID, skipEntryInfo)
end

function TalentLoadouts:SaveCurrentLoadouts()
    if not self.globalDB or not self.charDB then
        self:CheckDBIntegrity()
    end

    for specIndex=1, GetNumSpecializations() do
        local specID = GetSpecializationInfo(specIndex)
        self.globalDB.configIDs[specID] = self.globalDB.configIDs[specID] or {}

        local specLoadouts = self.globalDB.configIDs[specID]
        local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)

        for _, configID in ipairs(configIDs) do
            if not specLoadouts[configID] then
                local configInfo = C_Traits.GetConfigInfo(configID)
                if not (configInfo.name == ITL_LOADOUT_NAME) then
                    specLoadouts[configID] = configInfo
                end
            end
        end
    end

    local currentSpecID = self.specID
    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    if activeConfigID then
        self.globalDB.configIDs[currentSpecID][activeConfigID] = self.globalDB.configIDs[currentSpecID][activeConfigID] or C_Traits.GetConfigInfo(activeConfigID)
        self.globalDB.configIDs[currentSpecID][activeConfigID].default = true
    end
end

function TalentLoadouts:UpdateDataObj(configInfo)
    local _, name = GetSpecializationInfoByID(TalentLoadouts.specID)
    dataObj.text = dataObjText:format(name, configInfo and configInfo.name or "Unknown")
end

function TalentLoadouts:LoadGearAndLayout(configInfo)
    if not InCombatLockdown() then
        if configInfo.gearset then
            -- Without delay it may fail.
            C_Timer.After(0, function() EquipmentManager_EquipSet(configInfo.gearset) end)
        end

        if configInfo.layout then
            C_EditMode.SetActiveLayout(configInfo.layout)
        end
    else
        self:Print("Can't change gear or layouts in combat")
    end
end

local function ResetTree(treeID, treeType)
    local activeConfigID = C_ClassTalents.GetActiveConfigID()

    if C_Traits.ConfigHasStagedChanges(activeConfigID) then
        C_Traits.RollbackConfig(activeConfigID)
    end

    if not treeType or treeType == 1 then
        C_Traits.ResetTree(activeConfigID, treeID)
    else
        local currencyInfo = C_Traits.GetTreeCurrencyInfo(activeConfigID, treeID, false)
        if treeType == 2 then
            C_Traits.ResetTreeByCurrency(activeConfigID, treeID, currencyInfo[1].traitCurrencyID)
        elseif treeType == 3 then
            C_Traits.ResetTreeByCurrency(activeConfigID, treeID, currencyInfo[2].traitCurrencyID)
        end
    end
end

local function CommitLoadout()
    local configInfo = TalentLoadouts.pendingLoadout
    if configInfo then
        local activeConfigID = C_ClassTalents.GetActiveConfigID()

        if not configInfo.entryInfo and configInfo.exportString then
            configInfo.entryInfo = CreateEntryInfoFromString(configInfo.ID, configInfo.exportString)
        end

        local entryInfo = configInfo.entryInfo
        if not entryInfo then return end

        table.sort(entryInfo, function(a, b)
            local nodeA = C_Traits.GetNodeInfo(activeConfigID, a.nodeID)
            local nodeB = C_Traits.GetNodeInfo(activeConfigID, b.nodeID)

            return nodeA.posY < nodeB.posY or (nodeA.posY == nodeB.posY and nodeA.posX < nodeB.posX)
        end)

        for i=1, #entryInfo do
            local entry = entryInfo[i]
            local nodeInfo = C_Traits.GetNodeInfo(activeConfigID, entry.nodeID)
            if nodeInfo.isAvailable and nodeInfo.isVisible then
                if nodeInfo.type == Enum.TraitNodeType.Selection then
                    C_Traits.SetSelection(activeConfigID, entry.nodeID, entry.selectionEntryID)
                end

                if C_Traits.CanPurchaseRank(activeConfigID, entry.nodeID, entry.selectionEntryID) then
                    for rank=1, entry.ranksPurchased do
                        C_Traits.PurchaseRank(activeConfigID, entry.nodeID)
                    end
                end
            end
        end

        if ImprovedTalentLoadoutsDB.options.applyLoadout then
            local canChange, _, changeError = C_ClassTalents.CanChangeTalents()
            if not canChange then 
                if changeError == ERR_TALENT_FAILED_UNSPENT_TALENT_POINTS then
                    configInfo.error = true
                end
        
                TalentLoadouts:OnLoadoutFail()
                TalentLoadouts:Print("|cffff0000Can't load Loadout.|r", changeError)
                return
            end

            if pcall(C_Traits.GetConfigInfo, TalentLoadouts.charDB.tempLoadout) then
                --securecallfunction(ClassTalentFrame.TalentsTab.UpdateTreeCurrencyInfo, ClassTalentFrame.TalentsTab)
                RunNextFrame(GenerateClosure(C_ClassTalents.CommitConfig, TalentLoadouts.charDB.tempLoadout))
                RunNextFrame(GenerateClosure(C_ClassTalents.UpdateLastSelectedSavedConfigID, TalentLoadouts.specID, TalentLoadouts.charDB.tempLoadout))
            else
                --securecallfunction(ClassTalentFrame.TalentsTab.UpdateTreeCurrencyInfo, ClassTalentFrame.TalentsTab)
                RunNextFrame(GenerateClosure(C_ClassTalents.CommitConfig, activeConfigID))
            end

            RegisterEvent("CONFIG_COMMIT_FAILED")
        else
            HookFunction(C_Traits, "RollbackConfig", TalentLoadouts.OnLoadoutFail)
        end

        if not C_Traits.ConfigHasStagedChanges(activeConfigID) and TalentLoadouts.pendingLoadout then
            TalentLoadouts:OnLoadoutSuccess()
        end
    end
end

function TalentLoadouts:LoadAsBlizzardLoadout(newConfigInfo)
    if newConfigInfo.name == ITL_LOADOUT_NAME then
        if not self.charDB.tempLoadout or self.charDB.tempLoadout ~= newConfigInfo.ID then
            self.charDB.tempLoadout = newConfigInfo.ID
            --C_ClassTalents.SetUsesSharedActionBars(newConfigInfo.ID, true)
        end

        ResetTree(newConfigInfo.treeIDs[1], newConfigInfo.type)
        RunNextFrame(CommitLoadout)
    end
end

local function LoadBlizzardLoadout(configID, currentSpecID, configInfo, categoryInfo)
    C_ClassTalents.LoadConfig(configID, true)
    C_ClassTalents.UpdateLastSelectedSavedConfigID(currentSpecID, nil)
    TalentLoadouts.pendingLoadout = configInfo
    TalentLoadouts.pendingCategory = categoryInfo
    TalentLoadouts.lastUpdated = nil
    TalentLoadouts.lastUpdatedCategory = nil
    TalentLoadouts:UpdateDropdownText()
    TalentLoadouts:UpdateDataObj(configInfo)
    TalentLoadouts:LoadGearAndLayout(configInfo)
end

local function LoadLoadout(self, configInfo, categoryInfo, forceBlizzardDisable)
    if not configInfo then return end

    local currentSpecID = TalentLoadouts.specID
    local configID = configInfo.ID

    if ImprovedTalentLoadoutsDB.options.loadBlizzard and C_Traits.GetConfigInfo(configID) then
        LoadBlizzardLoadout(configID, currentSpecID, configInfo, categoryInfo)
        return
    end

    if not forceBlizzardDisable and ImprovedTalentLoadoutsDB.options.loadAsBlizzard then
        local tempLoadoutInfo = TalentLoadouts.charDB.tempLoadout and C_Traits.GetConfigInfo(TalentLoadouts.charDB.tempLoadout)
        local canCreate = C_ClassTalents.CanCreateNewConfig()
        if (tempLoadoutInfo or canCreate) and TalentLoadouts.charDB.lastLoadout ~= configInfo.ID then
            TalentLoadouts:CacheActionBars()

            TalentLoadouts.pendingLoadout = configInfo
            TalentLoadouts.pendingCategory = categoryInfo
            TalentLoadouts.lastUpdated = nil
            TalentLoadouts.lastUpdatedCategory = nil
        
            TalentLoadouts:UpdateDropdownText()
            TalentLoadouts:UpdateDataObj()

            TalentLoadouts.blizzImported = true

            if not TalentLoadouts.charDB.tempLoadout or not tempLoadoutInfo then
                C_ClassTalents.RequestNewConfig(ITL_LOADOUT_NAME)
            elseif tempLoadoutInfo then
                C_ClassTalents.UpdateLastSelectedSavedConfigID(currentSpecID, TalentLoadouts.charDB.tempLoadout)
                ResetTree(configInfo.treeIDs[1], configInfo.type)
                RunNextFrame(CommitLoadout)
            end
        elseif not tempLoadoutInfo or not canCreate then
            if not ImprovedTalentLoadoutsDB.options.useBlizzardFallback then
                TalentLoadouts:Print("|cFFFF0000Can't load the loadouts as a Blizzard one because you have 10 Blizzard loadouts|r. |cFFFFFF00Delete one of them or disable \"Options -> Loadouts -> Load As Blizzard Loadout\"|r. You can also enable the \"Fall back to AddOn Loadout \" option to fall back to the old way of loading loadouts if the AddOn can't create/find the " .. ITL_LOADOUT_NAME .. " loadout.")
            else
                LoadLoadout(self, configInfo, categoryInfo, true)
            end
        end
    elseif configInfo.entryInfo then
        TalentLoadouts:CacheActionBars()
        TalentLoadouts.pendingLoadout = configInfo
        TalentLoadouts.pendingCategory = categoryInfo
        TalentLoadouts.lastUpdated = nil
        TalentLoadouts.lastUpdatedCategory = nil

        ResetTree(configInfo.treeIDs[1], configInfo.type)
        RunNextFrame(CommitLoadout)
    
        TalentLoadouts:UpdateDropdownText()
        TalentLoadouts:UpdateDataObj()
    elseif C_Traits.GetConfigInfo(configID) then
        LoadBlizzardLoadout(configID, currentSpecID, configInfo, categoryInfo)
    end

    configInfo.error = nil
    LibDD:CloseDropDownMenus()
end

function TalentLoadouts:LoadLoadoutByConfigID(configID, categoryInfo)
    LoadLoadout(nil, TalentLoadouts.globalDB.configIDs[TalentLoadouts.specID][configID], categoryInfo)
end

function TalentLoadouts:OnLoadoutSuccess()
    local configInfo = TalentLoadouts.pendingLoadout
    local categoryInfo = TalentLoadouts.pendingCategory

    TalentLoadouts:LoadGearAndLayout(configInfo)

    TalentLoadouts.charDB.lastLoadout = configInfo.ID
    TalentLoadouts.charDB[self.specID] = configInfo.ID
    TalentLoadouts.charDB.lastCategory = categoryInfo
    TalentLoadouts.pendingLoadout = nil
    TalentLoadouts.pendingCategory = nil

    TalentLoadouts:UpdateDropdownText()
    TalentLoadouts:UpdateDataObj(configInfo)

    UnhookFunction("RollbackConfig")
    UnregisterEvent("CONFIG_COMMIT_FAILED")

    if TalentLoadouts.blizzImported then
        TalentLoadouts.blizzImported = nil
        TalentLoadouts.pendingDeletion = true
    end

    if ImprovedTalentLoadoutsDB.options.loadActionbars and configInfo.actionBars then
        C_Timer.After(0.25, function()
            TalentLoadouts:LoadActionBar(configInfo.actionBars, configInfo.name)
        end)
    end

    C_Timer.After(0.25, function()
        if IsAddOnLoaded(talentUI) then
            TalentLoadouts:UpdateCurrentExportString()
        end
    end)

    C_Timer.After(0.35, function()
        TalentLoadouts:CacheActionBars()
    end)
end

function TalentLoadouts:OnUnknownLoadoutSuccess()
    local known = false
    if TalentLoadouts.lastUpdated then
        local configInfo = TalentLoadouts.lastUpdated
        local exportString = CreateExportString(configInfo, C_ClassTalents.GetActiveConfigID(), self.specID, true)
        if exportString == configInfo.exportString then
            TalentLoadouts.charDB.lastLoadout = configInfo.ID
            TalentLoadouts.charDB[self.specID] = configInfo.ID
            TalentLoadouts.charDB.lastCategory = TalentLoadouts.lastUpdatedCategory
            known = true
        end
    end

    if not known then
        local exportString = CreateExportString(nil, C_ClassTalents.GetActiveConfigID(), self.specID, true)
        local configID = nil

        if ImprovedTalentLoadoutsDB.options.findMatchingLoadout then
            for _, configInfo in pairs(self.globalDB.configIDs[self.specID]) do
                if configInfo and configInfo.exportString and configInfo.exportString == exportString then
                    configID = configInfo.ID
                    break
                end
            end
        end

        TalentLoadouts.charDB.lastLoadout = configID
        TalentLoadouts.charDB[self.specID] = configID
        TalentLoadouts.charDB.lastCategory = nil

        if not configID then
            C_ClassTalents.UpdateLastSelectedSavedConfigID(self.specID, nil)
        end
    end

    UnregisterEvent("CONFIG_COMMIT_FAILED")

    TalentLoadouts:UpdateDropdownText()
    TalentLoadouts:UpdateDataObj()

    TalentLoadouts.pendingDeletion = true
end

function TalentLoadouts:OnLoadoutFail()
    TalentLoadouts.pendingLoadout = nil
    TalentLoadouts.pendingCategory = nil
    TalentLoadouts.lastUpdated = nil
    TalentLoadouts.lastUpdatedCategory = nil

    UnhookFunction("RollbackConfig")
    UnregisterEvent("CONFIG_COMMIT_FAILED")

    TalentLoadouts:UpdateDropdownText()
    TalentLoadouts:UpdateDataObj()
end

function TalentLoadouts:CacheActionBars()
    local cachedActionbars = self.charDB.cachedActionbars
    cachedActionbars[self.specID] = TalentLoadouts:GetCurrentActionBarsCompressed() or cachedActionbars[self.specID]
end

function TalentLoadouts:UpdateCurrentExportString()
    local configID = TalentLoadouts.charDB[self.specID]
    local configInfo = configID and self.globalDB.configIDs[self.specID][configID]
    if configInfo then
        local exportString, entryInfo
        if not configInfo.entryInfo then
            exportString, entryInfo = CreateExportString(nil, C_ClassTalents.GetActiveConfigID(), self.specID)
        else
            exportString = CreateExportString(nil, C_ClassTalents.GetActiveConfigID(), self.specID, true)
        end

        configInfo.exportString = exportString
        configInfo.entryInfo = configInfo.entryInfo or entryInfo
    end
end

function TalentLoadouts:LoadLoadoutByName(name)
    local configIDs = self.globalDB.configIDs[self.specID]
    for _, configInfo in pairs(configIDs) do
        if configInfo.name == name then
            LoadLoadout(nil, configInfo)
            break
        end
    end
end

local function FindFreeConfigID()
    local freeIndex = 1

    for _ in ipairs(TalentLoadouts.globalDB.configIDs[TalentLoadouts.specID]) do
        freeIndex = freeIndex + 1
    end

    return freeIndex
end

StaticPopupDialogs["TALENTLOADOUTS_CATEGORY_CREATE"] = {
    text = "Category Name",
    button1 = "Create",
    button2 = "Cancel",
    OnAccept = function(self)
       local categoryName = self.editBox:GetText()
       TalentLoadouts:CreateCategory(categoryName)
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

local function CreateCategory()
    StaticPopup_Show("TALENTLOADOUTS_CATEGORY_CREATE")
end

function TalentLoadouts:CreateCategory(categoryName)
    local key = categoryName:lower()
    local currentSpecID = self.specID
    self.globalDB.categories[currentSpecID] = self.globalDB.categories[currentSpecID] or {}

    if self.globalDB.categories[currentSpecID][key] then
        self:Print("A category with this name already exists.")
        return
    end

    self.globalDB.categories[currentSpecID][key] = {
        name = categoryName,
        key = key,
        loadouts = {},
    }
end

StaticPopupDialogs["TALENTLOADOUTS_CATEGORY_IMPORT"] = {
    text = "Category Import String",
    button1 = "Import",
    button2 = "Cancel",
    OnAccept = function(self)
       local importString = self.editBox:GetText()
       TalentLoadouts:ProcessCategoryImport(importString)
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

local function ImportCategory()
    StaticPopup_Show("TALENTLOADOUTS_CATEGORY_IMPORT")
end

function TalentLoadouts:ProcessCategoryImport(importString)
    local version, categoryString = importString:match("!PTL(%d+)!(.+)")
    local decoded = LibDeflate:DecodeForPrint(categoryString)
    if not decoded then return end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return end
    local success, data = LibSerialize:Deserialize(decompressed)
    if not success then return end
    
    local categories = self.globalDB.categories[self.specID]
    if not categories then
        self.globalDB.categories[self.specID] = {}
        categories = self.globalDB.categories[self.specID]
    end

    self:ImportCategory(data)
end

local function GetAvailableCategoryKey(categories, key, index)
    local newKey = string.format("%s-%d", key, index)
    if not categories[newKey] then
        return newKey
    else
        return GetAvailableCategoryKey(categories, key, index + 1)
    end
end

function TalentLoadouts:ImportCategory(data, isSubCategory, parentKey)
    local categories = self.globalDB.categories[self.specID]
    if categories[data.key] then 
        data.key = GetAvailableCategoryKey(categories, data.key, 2)
    end

    categories[data.key] = {
        key = data.key,
        name = data.name,
        loadouts = {},
        categories = {},
        isSubCategory = isSubCategory,
        parents = isSubCategory and {}
    }

    local categoryInfo = categories[data.key]
    if parentKey then
        tInsertUnique(categoryInfo.parents, parentKey)
    end

    if data.subCategories then
        for _, subCategory in ipairs(data.subCategories) do
            local key = self:ImportCategory(subCategory, true, data.key)
            tInsertUnique(categoryInfo.categories, key)
        end
    end

    for _, configInfo in ipairs(data) do
        local configID = TalentLoadouts:ImportLoadout(configInfo.exportString, configInfo.name, data.key)
        if configID then
            tinsert(categoryInfo.loadouts, configID)
        end
    end

    return data.key
end

StaticPopupDialogs["TALENTLOADOUTS_CATEGORY_EXPORT"] = {
    text = "Export Category",
    button1 = "Okay",
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

local function CreateCategoryExportTbl(categoryInfo)
    local currentSpecID = TalentLoadouts.specID
    local export = {name = categoryInfo.name, key = categoryInfo.key}
    if categoryInfo.categories and #categoryInfo.categories > 0 then
        export.subCategories = {}

        for _, categoryKey in ipairs(categoryInfo.categories) do
            local subCategoryInfo = TalentLoadouts.globalDB.categories[currentSpecID][categoryKey]
            if subCategoryInfo then
                tinsert(export.subCategories, CreateCategoryExportTbl(subCategoryInfo))
            end
        end
    end

    if categoryInfo.loadouts and #categoryInfo.loadouts > 0 then
        for _, configID in ipairs(categoryInfo.loadouts) do
            local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
            if configInfo then
                tinsert(export, {name = configInfo.name, exportString = configInfo.exportString})
            end
        end
    end

    return export
end

local function ExportCategory(self, categoryInfo)
    if categoryInfo then
        local export = CreateCategoryExportTbl(categoryInfo)

        local serialized = LibSerialize:Serialize(export)
        local compressed = LibDeflate:CompressDeflate(serialized)
        local encode = LibDeflate:EncodeForPrint(compressed)
        local dialog = StaticPopup_Show("TALENTLOADOUTS_CATEGORY_EXPORT")
        dialog.editBox:SetText("!PTL1!" .. encode)
        dialog.editBox:HighlightText()
        dialog.editBox:SetFocus()
    end
end

StaticPopupDialogs["TALENTLOADOUTS_CATEGORY_RENAME"] = {
    text = "New Category Name for '%s'",
    button1 = "Rename",
    button2 = "Cancel",
    OnAccept = function(self, categoryInfo)
       local newCategoryName = self.editBox:GetText()
       TalentLoadouts:RenameCategory(categoryInfo, newCategoryName)
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

local function RenameCategory(self, categoryInfo)
    local dialog = StaticPopup_Show("TALENTLOADOUTS_CATEGORY_RENAME", categoryInfo.name)
    dialog.editBox:SetText(categoryInfo.name)
    dialog.data = categoryInfo
end

function TalentLoadouts:RenameCategory(categoryInfo, newCategoryName)
    if categoryInfo and #newCategoryName > 0 then
        categoryInfo.name = newCategoryName
    end
end

local function RemoveCategoryFromCategory(self, parentCategory, categoryInfo, isDeletion)
    if not isDeletion then
        tDeleteItem(parentCategory.categories, categoryInfo.key)
    end

    if categoryInfo.parents then
        tDeleteItem(categoryInfo.parents, parentCategory.key)
    end

    if not categoryInfo.parents or #categoryInfo.parents == 0 then
        categoryInfo.isSubCategory = nil
    end
    LibDD:CloseDropDownMenus()
end

StaticPopupDialogs["TALENTLOADOUTS_CATEGORY_DELETE"] = {
    text = "Are you sure you want to delete the category%s?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, categoryInfo, withLoadouts)
        TalentLoadouts:DeleteCategory(categoryInfo, withLoadouts)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
 }

local function DeleteCategory(self, categoryInfo, withLoadouts)
    local dialog = StaticPopup_Show("TALENTLOADOUTS_CATEGORY_DELETE", withLoadouts and " (|cffff0000including loadouts|r)" or "")
    dialog.data = categoryInfo
    dialog.data2 = withLoadouts
end

function TalentLoadouts:DeleteCategory(categoryInfo, withLoadouts)
    if categoryInfo then
        local currentSpecID = self.specID
        if withLoadouts then
            for _, configID in ipairs(categoryInfo.loadouts) do
                self.globalDB.configIDs[currentSpecID][configID] = nil
            end
        else
            for _, configID in ipairs(categoryInfo.loadouts) do
                local configInfo = self.globalDB.configIDs[currentSpecID][configID]
                if configInfo and configInfo.categories and configInfo.categories[categoryInfo.key] then
                    configInfo.categories[categoryInfo.key] = nil
                end
            end
        end

        if categoryInfo.isSubCategory then
            for _, categoryKey in ipairs(categoryInfo.parents) do
                local parentCategoryInfo = self.globalDB.categories[currentSpecID][categoryKey]
                if parentCategoryInfo then
                    tDeleteItem(parentCategoryInfo.categories, categoryInfo.key)
                end
            end
        end

        if categoryInfo.categories then
            for _, categoryKey in ipairs(categoryInfo.categories) do
                local subCategoryInfo = self.globalDB.categories[currentSpecID][categoryKey]
                if subCategoryInfo then
                    RemoveCategoryFromCategory(nil, categoryInfo, subCategoryInfo, true)
                end
            end
        end

        self.globalDB.categories[currentSpecID][categoryInfo.key] = nil
    end
end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_SAVE"] = {
    text = "Loadout Name",
    button1 = "Create",
    button2 = "Create + Apply",
    button3 = "Cancel",
    OnShow = function(self)
        self.action = 1
    end,
    OnAccept = function(self)
        self.action = 2
    end,
    OnCancel = function(self)
        self.action = 3
    end,
    OnHide = function(self, data)
        if self.action > 1 then
            local treeType, categoryInfo = unpack(data)
            local loadoutName = self.editBox:GetText()
            local fakeConfigID
            if treeType == 1 then
                fakeConfigID = TalentLoadouts:SaveCurrentTree(loadoutName, categoryInfo)
            elseif treeType == 2 then
                fakeConfigID = TalentLoadouts:SaveCurrentClassTree(loadoutName, categoryInfo)
            elseif treeType == 3 then
                fakeConfigID = TalentLoadouts:SaveCurrentSpecTree(loadoutName, categoryInfo)
            end

            if fakeConfigID and self.action == 3 then
                TalentLoadouts:LoadLoadoutByConfigID(fakeConfigID, categoryInfo)
            end
        end
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
 }

 local function SaveCurrentTree(self, treeType, categoryInfo)
    local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_SAVE")
    dialog.data = {treeType, categoryInfo}
 end

 function TalentLoadouts:SaveCurrentTree(loadoutName, categoryInfo)
    local isInspecting = ClassTalentFrame.TalentsTab:IsInspecting()
    local exportString
    if isInspecting then
        local unit = ClassTalentFrame:GetInspectUnit()
        if unit and GetInspectSpecialization(unit) == self.specID then
            exportString = C_Traits.GenerateInspectImportString(unit)
        end
    end

    if not isInspecting or exportString then
        return self:ImportLoadout(exportString or self:GetExportStringForTree(), loadoutName, categoryInfo and categoryInfo.key)
    elseif isInspecting and not exportString then
        TalentLoadouts:Print("Unable to generate the export string. Make sure the specialization of the inspected unit is equalt to your current one.")
    end
 end

 function TalentLoadouts:SaveCurrentClassTree(loadoutName, categoryInfo)
    loadoutName = string.format("[C] %s", loadoutName)
    return self:ImportClassLoadout(self:GetExportStringForTree(), loadoutName, categoryInfo and categoryInfo.key)
 end

 function TalentLoadouts:SaveCurrentSpecTree(loadoutName, categoryInfo)
    loadoutName = string.format("[S] %s", loadoutName)
    return self:ImportSpecLoadout(self:GetExportStringForTree(), loadoutName, categoryInfo and categoryInfo.key)
 end

 local function UpdateWithCurrentTree(self, configID, categoryInfo, isButtonUpdate)
    if configID then
        local currentSpecID = TalentLoadouts.specID
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
        if configInfo then
            local activeConfigID = C_ClassTalents.GetActiveConfigID()
            configInfo.exportString, configInfo.entryInfo = CreateExportString(configInfo, activeConfigID, currentSpecID)
            configInfo.error = nil

            TalentLoadouts:Print(configInfo.name, "updated")

            if isButtonUpdate then
                TalentLoadouts.lastUpdated = configInfo
                TalentLoadouts.lastUpdatedCategory = categoryInfo
            end
        end
    end
end



StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_CUSTOM_ORDER_CATEGORY"] = {
    text = "Order of |cFF33ff96%s|r in |cFF34ebe1%s|r",
    button1 = "Set",
    button2 = "Cancel",
    OnAccept = function(self, data)
        local customOrder = tonumber(self.editBox:GetText())
        local configInfo, categoryInfo = unpack(data)
        TalentLoadouts:SetLoadoutCustomOrder(configInfo, categoryInfo, customOrder)
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_CUSTOM_ORDER"] = {
    text = "Order of |cFF33ff96%s|r",
    button1 = "Set",
    button2 = "Cancel",
    OnAccept = function(self, configInfo)
        local customOrder = tonumber(self.editBox:GetText())
        TalentLoadouts:SetLoadoutCustomOrder(configInfo, nil, customOrder)
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

function TalentLoadouts:SetLoadoutCustomOrder(configInfo, categoryInfo, customOrder)
    if configInfo then
        if categoryInfo then
            configInfo.categoryCustomOrder = configInfo.categoryCustomOrder or {}
            configInfo.categoryCustomOrder[categoryInfo.key] = customOrder
        else
            configInfo.customOrder = customOrder
        end
    end
end

local function SetCustomOrder(self, configID, categoryInfo)
    if configID then
        local currentSpecID = TalentLoadouts.specID
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
        if categoryInfo then
            local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_CUSTOM_ORDER_CATEGORY", configInfo.name, categoryInfo.name)
            dialog.data = {configInfo, categoryInfo}
        else
            local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_CUSTOM_ORDER", configInfo.name)
            dialog.data = configInfo
        end
    end
end

local function RemoveCustomOrder(self, configID, categoryInfo)
    if configID then
        local currentSpecID = TalentLoadouts.specID
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
        if categoryInfo and configInfo.categoryCustomOrder then
            configInfo.categoryCustomOrder[categoryInfo.key] = nil
        else
            configInfo.customOrder = nil
        end
    end
end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_IMPORT_STRING_UPDATE"] = {
    text = "Loadout Import String",
    button1 = "Import",
    button2 = "Cancel",
    OnAccept = function(self, configID)
       local importString = self.editBox:GetText()
       TalentLoadouts:UpdateWithString(configID, importString)
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

 local function UpdateWithString(self, configID)
    local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_IMPORT_STRING_UPDATE")
    dialog.data = configID
 end

 function TalentLoadouts:UpdateWithString(configID, importString)
    if configID then
        local currentSpecID = TalentLoadouts.specID
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
        if configInfo then
            local treeID = TalentLoadouts:GetTreeID()
            local entryInfo = CreateEntryInfoFromString(configID, importString, treeID)
        
            if entryInfo then
                if configID == self.charDB.lastLoadout then
                    self.charDB.lastLoadout = nil
                    self:UpdateDropdownText()
                    self:UpdateDataObj()
                end

                configInfo.entryInfo = entryInfo
                configInfo.exportString = importString
                configInfo.error = nil
            else
                self:Print("Invalid import string.")
            end
        end
    end
 end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_DELETE"] = {
    text = "Are you sure you want to delete the loadout?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, configID)
        TalentLoadouts:DeleteLoadout(configID)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
 }

local function DeleteLoadout(self, configID)
    local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_DELETE")
    dialog.data = configID
end

function TalentLoadouts:DeleteLoadout(configID)
    local currentSpecID = self.specID

    local configInfo = self.globalDB.configIDs[currentSpecID][configID]
    self.globalDB.configIDs[currentSpecID][configID] = nil

    if self.charDB.lastLoadout == configID then
        self.charDB.lastLoadout = nil
    end

    if configInfo.categories then
        for categoryKey in pairs(configInfo.categories) do
            tDeleteItem(self.globalDB.categories[currentSpecID][categoryKey].loadouts, configID)
        end
    end

    LibDD:CloseDropDownMenus()
    self:UpdateDropdownText()
    self:UpdateDataObj()
end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_RENAME"] = {
    text = "New Loadout Name",
    button1 = "Rename",
    button2 = "Cancel",
    OnAccept = function(self, configInfo)
       local newName = self.editBox:GetText()
       TalentLoadouts:RenameLoadout(configInfo, newName)
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
    end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

local function RenameLoadout(self, configID)
    local currentSpecID = TalentLoadouts.specID
    local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]

    if configInfo then
        local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_RENAME")
        dialog.editBox:SetText(configInfo.name)
        dialog.data = configInfo
    end
end

function TalentLoadouts:RenameLoadout(configInfo, newLoadoutName)
    configInfo.name = newLoadoutName

    LibDD:CloseDropDownMenus()
    self:UpdateDropdownText()
    self:UpdateDataObj(configInfo)
end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_IMPORT_STRING"] = {
    text = "Loadout Import String",
    button1 = "Accept",
    button2 = "Cancel",
    OnAccept = function(self, data)
        local treeType, categoryInfo = unpack(data)
        local importString = self.editBox:GetText()
        local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_IMPORT_NAME")
        dialog.data = {treeType, importString, categoryInfo}
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}


-- action = 1 -> do nothing
-- action = 2 -> import
-- action = 3 -> import + apply
StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_IMPORT_NAME"] = {
    text = "Loadout Import Name",
    button1 = "Import",
    button2 = "Import + Apply",
    button3 = "Cancel",
    OnShow = function(self)
        self.action = 1
    end,
    OnAccept = function(self)
        self.action = 2
    end,
    OnCancel = function(self)
        self.action = 3
    end,
    OnHide = function(self, data)
        if self.action > 1 then
            local treeType, importString, categoryInfo = unpack(data)
            local loadoutName = self.editBox:GetText()
            local fakeConfigID
            if not treeType or treeType == 1 then
                fakeConfigID = TalentLoadouts:ImportLoadout(importString, loadoutName, categoryInfo and categoryInfo.key)
            elseif treeType == 2 then
                loadoutName = string.format("[C] %s", loadoutName)
                fakeConfigID = TalentLoadouts:ImportClassLoadout(importString, loadoutName, categoryInfo and categoryInfo.key)
            elseif treeType == 3 then
                loadoutName = string.format("[S] %s", loadoutName)
                fakeConfigID = TalentLoadouts:ImportSpecLoadout(importString, loadoutName, categoryInfo and categoryInfo.key)
            end

            if fakeConfigID and self.action == 3 then
                TalentLoadouts:LoadLoadoutByConfigID(fakeConfigID, categoryInfo)
            end
        end
        self.apply = nil
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

local function ImportCustomLoadout(self, treeType, categoryInfo, entryInfo)
    ImprovedTalentLoadoutsImportDialog:ShowDialog(treeType, categoryInfo)
    --local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_IMPORT_STRING")
    --dialog.data = {treeType, categoryInfo}
end

function TalentLoadouts:ImportLoadout(importString, loadoutName, categoryKey)
    local currentSpecID = self.specID
    local fakeConfigID = FindFreeConfigID()
    if not fakeConfigID then return end

    local treeID = TalentLoadouts:GetTreeID()
    local entryInfo = CreateEntryInfoFromString(C_ClassTalents.GetActiveConfigID(), importString, treeID)

    if entryInfo and #entryInfo > 40 then
        self.globalDB.configIDs[currentSpecID][fakeConfigID] = {
            ID = fakeConfigID,
            fake = true,
            type = 1,
            treeIDs = {treeID},
            name = loadoutName,
            exportString = importString,
            entryInfo = entryInfo,
            usesSharedActionBars = true,
            categories = categoryKey and {[categoryKey] = true} or {},
        }

        if categoryKey then
            tInsertUnique(TalentLoadouts.globalDB.categories[currentSpecID][categoryKey].loadouts, fakeConfigID)
        end
    else
        self:Print("Invalid import string. Try reloading.")
        return
    end

    return fakeConfigID
end

function TalentLoadouts:ImportSpecLoadout(importString, loadoutName, categoryKey)
    local currentSpecID = self.specID
    local fakeConfigID = FindFreeConfigID()
    if not fakeConfigID then return end

    local treeID = TalentLoadouts:GetTreeID()
    local loadoutEntryInfo = CreateEntryInfoFromString(C_ClassTalents.GetActiveConfigID(), importString, treeID)

    if loadoutEntryInfo then
        local configID = C_ClassTalents.GetActiveConfigID()
        local specEntryInfo = {}
        for i=1, #loadoutEntryInfo do
            local nodeInfo = C_Traits.GetNodeInfo(configID, loadoutEntryInfo[i].nodeID)
            local nodeCost = C_Traits.GetNodeCost(configID, nodeInfo.ID)
            if C_Traits.GetTraitCurrencyInfo(nodeCost[1].ID) == Enum.TraitCurrencyFlag.UseSpecIcon then
                tinsert(specEntryInfo, loadoutEntryInfo[i])
            end
        end

        self.globalDB.configIDs[currentSpecID][fakeConfigID] = {
            ID = fakeConfigID,
            fake = true,
            type = 3,
            treeIDs = {treeID},
            name = loadoutName,
            exportString = importString,
            entryInfo = specEntryInfo,
            usesSharedActionBars = true,
            categories = categoryKey and {[categoryKey] = true} or {},
        }

        if categoryKey then
            tInsertUnique(TalentLoadouts.globalDB.categories[currentSpecID][categoryKey].loadouts, fakeConfigID)
        end
    else
        self:Print("Invalid import string.")
        return
    end

    return fakeConfigID
end

function TalentLoadouts:ImportClassLoadout(importString, loadoutName, categoryKey)
    local currentSpecID = self.specID
    local fakeConfigID = FindFreeConfigID()
    if not fakeConfigID then return end

    local configID = C_ClassTalents.GetActiveConfigID()
    local treeID = TalentLoadouts:GetTreeID()
    local loadoutEntryInfo = CreateEntryInfoFromString(configID, importString, treeID)

    if loadoutEntryInfo then
        local classEntryInfo = {}
        for i=1, #loadoutEntryInfo do
            local nodeInfo = C_Traits.GetNodeInfo(configID, loadoutEntryInfo[i].nodeID)
            local nodeCost = C_Traits.GetNodeCost(configID, nodeInfo.ID)
            if C_Traits.GetTraitCurrencyInfo(nodeCost[1].ID) == Enum.TraitCurrencyFlag.UseClassIcon then
                tinsert(classEntryInfo, loadoutEntryInfo[i])
            end
        end

        self.globalDB.configIDs[currentSpecID][fakeConfigID] = {
            ID = fakeConfigID,
            fake = true,
            type = 2,
            treeIDs = {treeID},
            name = loadoutName,
            exportString = importString,
            entryInfo = classEntryInfo,
            usesSharedActionBars = true,
            categories = categoryKey and {[categoryKey] = true} or {},
        }

        if categoryKey then
            tInsertUnique(TalentLoadouts.globalDB.categories[currentSpecID][categoryKey].loadouts, fakeConfigID)
        end
    else
        self:Print("Invalid import string.")
        return
    end

    return fakeConfigID
end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_EXPORT"] = {
    text = "Loadout Export String",
    button1 = "Okay",
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
     end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

local function ExportLoadout(self, configID)
    local currentSpecID = TalentLoadouts.specID
    local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
    if configInfo then
        local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_EXPORT")
        dialog.editBox:SetText(configInfo.exportString)
        dialog.editBox:HighlightText()
        dialog.editBox:SetFocus()
    end
end

local function PostInChat(self, configID)
    local currentSpecID = TalentLoadouts.specID
    local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
        if configInfo then
        local linkDisplayText = ("[%s - %s]"):format(TALENT_BUILD_CHAT_LINK_TEXT:format(PlayerUtil.GetSpecName(), PlayerUtil.GetClassName()), configInfo.name);
        local linkText = LinkUtil.FormatLink("talentbuild", linkDisplayText, currentSpecID, UnitLevel("player"), configInfo.exportString);
        local chatLink = PlayerUtil.GetClassColor():WrapTextInColorCode(linkText);
        if not ChatEdit_InsertLink(chatLink) then
            ChatFrame_OpenChat(chatLink);
        end
    end
end

local function UpdateActionBars(self, configID)
    local currentSpecID = TalentLoadouts.specID
    local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
    if configInfo then
        TalentLoadouts:UpdateActionBars(configInfo)
    end
end

local function RemoveActionBars(self, configID)
    local currentSpecID = TalentLoadouts.specID
    local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
    if configInfo then
        configInfo.actionBars = nil
    end
end

function TalentLoadouts:GetCurrentActionBarsCompressed()
    local actionBars = {}

    for actionSlot = 1, NUM_ACTIONBAR_BUTTONS do
        local actionType, id, actionSubType = GetActionInfo(actionSlot)
        if actionType then
            local key, macroType, macroName
            if actionType == "macro" then
                local name = GetActionText(actionSlot)
                --local name, _, body = GetMacroInfo(id)

                if name then
                    local macroIndex = not self.duplicates[name] and (self.globalMacros[name] or self.characterMacros[name])
                    if macroIndex then
                        macroName = name
                        macroType = macroIndex > MAX_ACCOUNT_MACROS and "characterMacros" or "globalMacros"

                        if body then
                            body = strtrim(body:gsub("\r", ""))
                            key = string.format("%s\031%s", name, body)
                        end
                    end
                end
            elseif actionType == "spell" then
                id = FindBaseSpellByID(id)
            end

            actionBars[actionSlot] = {
                type = actionType,
                id = id,
                subType = actionSubType,
                key = key,
                macroName = macroName,
                macroType = macroType
            }
        end
    end

    if next(actionBars) then
        local serialized = LibSerialize:Serialize(actionBars)
        local compressed = LibDeflate:CompressDeflate(serialized)

        return compressed
    end
end

function TalentLoadouts:UpdateActionBars(configInfo)
    self:UpdateKnownFlyouts()

    configInfo.actionBars = configInfo.actionBars or {}
    local actionBars = self:GetCurrentActionBarsCompressed()

    if actionBars then
        configInfo.actionBars = actionBars
    end
end

local function LoadActionBar(self, configID)
    local currentSpecID = TalentLoadouts.specID
    local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
    if configInfo and configInfo.actionBars then
        TalentLoadouts:LoadActionBar(configInfo.actionBars, configInfo.name)
    end
end

function TalentLoadouts:LoadActionBar(actionBars, name)
    if not actionBars then return end

    if InCombatLockdown() then
        TalentLoadouts:Print("Can't load actionbars in combat. Will try to load them after combat...")
        delayed.LoadActionBar = delayed.LoadActionBar or GenerateClosure(TalentLoadouts.LoadActionBar, TalentLoadouts, actionBars, name)
        return
    end

    local decompressed = LibDeflate:DecompressDeflate(actionBars)
    if not decompressed then return end
    local success, data = LibSerialize:Deserialize(decompressed)
    if not success then return end

    self:UpdateMacros()
    self:UpdateKnownFlyouts()

    if not next(data) then return end

    if name then
        self:Print("Loading action bars of", name)
    end


    local printWarning = false
    for actionSlot = 1, NUM_ACTIONBAR_BUTTONS do
        local slotInfo = data[actionSlot]
        local currentType, currentID, currentSubType = GetActionInfo(actionSlot)
        if slotInfo then

            local pickedUp = false
            ClearCursor()
            if slotInfo.type == "spell" and slotInfo.id ~= currentID then
                PickupSpell(slotInfo.id)
                pickedUp = true
            elseif slotInfo.type == "macro" then
                if slotInfo.macroType and self[slotInfo.macroType] and not self.duplicates[slotInfo.macroName] then
                    local id = self[slotInfo.macroType][slotInfo.key]
                    if not id then
                        id = slotInfo.macroName and self[slotInfo.macroType][slotInfo.macroName]
                    end

                    if id and id ~= currentID then
                        PickupMacro(id)
                        pickedUp = true
                    elseif not id then
                        self:Print("Please resave your action bars. Couldn't find macro: ", slotInfo.macroName, (slotInfo.body or ""):gsub("\n", " "))
                    end
                elseif self.duplicates[slotInfo.macroName] then
                    printWarning = true
                end
            elseif slotInfo.type == "summonmount" then
                local _, spellID = C_MountJournal.GetMountInfoByID(slotInfo.id)
                if spellID then
                    PickupSpell(spellID)
                else
                    C_MountJournal.Pickup(0)
                end
                pickedUp = true
            elseif slotInfo.type == "companion" then
                PickupSpell(slotInfo.id)
                pickedUp = true
            elseif slotInfo.type == "flyout" then
                PickupSpellBookItem(self.flyouts[slotInfo.id], BOOKTYPE_SPELL)
                pickedUp = true
            elseif slotInfo.type == "item" then
                PickupItem(slotInfo.id)
                pickedUp = true
            end

            if pickedUp then
                PlaceAction(actionSlot)
                ClearCursor()
            end
        elseif ImprovedTalentLoadoutsDB.options.clearEmptySlots and not slotInfo and currentType then
            PickupAction(actionSlot)
            ClearCursor()
        end
    end

    if printWarning then
        self:Print("|cffff0000For now the AddOn won't place macros with duplicate names until Blizzard fixes the issue with receiving the macro body.|r")
    end
end

local function AddToCategory(self, categoryInfo, value)
    if type(value) == "number" then
        local configInfo = TalentLoadouts.globalDB.configIDs[TalentLoadouts.specID][value]

        if configInfo and categoryInfo then
            configInfo.categories = configInfo.categories or {}
            configInfo.categories[categoryInfo.key] = true
            tInsertUnique(categoryInfo.loadouts, value)
            LibDD:CloseDropDownMenus()
        end
    elseif type(value) == "table" then
        local parentCategory = categoryInfo
        local subCategory = value

        subCategory.isSubCategory = true
        subCategory.parents = subCategory.parents or {}
        tInsertUnique(subCategory.parents, parentCategory.key)

        parentCategory.categories = parentCategory.categories or {}
        tInsertUnique(parentCategory.categories, subCategory.key)
        LibDD:CloseDropDownMenus()
    end
end

local function RemoveFromSpecificCategory(self, configID, categoryInfo)
    local configInfo = TalentLoadouts.globalDB.configIDs[TalentLoadouts.specID][configID]
    if configInfo then
        configInfo.categories[categoryInfo.key] = nil
        tDeleteItem(categoryInfo.loadouts, configID)
        LibDD:CloseDropDownMenus()
    end
end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_DELETE_ALL"] = {
    text = "Do you want to delete all of your loadouts? Type \"DELETE\".",
    button1 = "Delete",
    button2 = "Cancel",
    OnShow = function(self)
        self.button1:Disable()
    end,
    OnAccept = function()
        TalentLoadouts:DeleteAllLoadouts()
    end,
    timeout = 0,
    EditBoxOnEnterPressed = function(self)
         if ( self:GetParent().button1:IsEnabled() ) then
             self:GetParent().button1:Click();
         end
    end,
    EditBoxOnTextChanged = function(self)
        if self:GetText() == "DELETE" then
            self:GetParent().button1:Enable()
            return
        end

        self:GetParent().button1:Disable()
    end,
    hasEditBox = true,
    whileDead = true,
    hideOnEscape = true,
}

function TalentLoadouts:ShowDeleteAll()
    StaticPopup_Show("TALENTLOADOUTS_LOADOUT_DELETE_ALL")
end

function TalentLoadouts:DeleteAllLoadouts()
    for configID in pairs(self.globalDB.configIDs[self.specID]) do
        TalentLoadouts:DeleteLoadout(configID)
    end

    LibDD.CloseDropDownMenus()
end

function TalentLoadouts:AddSubCategoriesToImportDropdown(categoryInfo, currentSpecID, dropdownLevel, subCategoryLevel)
    if not categoryInfo.categories then return end

    for _, categoryKey in ipairs(categoryInfo.categories) do
        local categoryInfo = TalentLoadouts.globalDB.categories[currentSpecID][categoryKey]
        LibDD:UIDropDownMenu_AddButton(
            {
                arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                arg2 = categoryInfo,
                text = string.format("%sto |cFF34ebe1%s|r", string.rep(" ", subCategoryLevel * 5), categoryInfo.name),
                minWidth = 170,
                func = ImportCustomLoadout,
                fontObject = dropdownFont,
                notCheckable = 1,
            },
        dropdownLevel)
        
        if categoryInfo.categories and #categoryInfo.categories > 0 then
            self:AddSubCategoriesToImportDropdown(categoryInfo, currentSpecID, dropdownLevel, subCategoryLevel + 1)
        end
    end
end

function TalentLoadouts:AddSubCategoriesToCreateDropdown(categoryInfo, currentSpecID, dropdownLevel, subCategoryLevel)
    if not categoryInfo.categories then return end

    for _, categoryKey in ipairs(categoryInfo.categories) do
        local categoryInfo = TalentLoadouts.globalDB.categories[currentSpecID][categoryKey]
        LibDD:UIDropDownMenu_AddButton(
            {
                arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                arg2 = categoryInfo,
                text = string.format("%sto |cFF34ebe1%s|r", string.rep(" ", subCategoryLevel * 5), categoryInfo.name),
                minWidth = 170,
                func = SaveCurrentTree,
                fontObject = dropdownFont,
                notCheckable = 1,
            },
        dropdownLevel)
        
        if categoryInfo.categories and #categoryInfo.categories > 0 then
            self:AddSubCategoriesToCreateDropdown(categoryInfo, currentSpecID, dropdownLevel, subCategoryLevel + 1)
        end
    end
end

local loadoutFunctions = {
    assignGearset = {
        name = "Assign Gearset",
        notCheckable = true,
        hasArrow = true,
        menuList = "gearset",
    },
    assignLayout = {
        name = "Assign Layout",
        notCheckable = true,
        hasArrow = true,
        menuList = "layout",
    },
    setCustomOrder = {
        name = "Set Custom Order",
        notCheckable = true,
        func = SetCustomOrder,
    },
    removeCustomOrder = {
        name = "Remove Custom Order",
        notCheckable = true,
        func = RemoveCustomOrder
    },
    updateTree = {
        name = "Update Tree",
        notCheckable = true,
        func = UpdateWithCurrentTree,
    },
    updateWithString = {
        name = "Update with String",
        notCheckable = true,
        func = UpdateWithString,
    },
    updateActionbars = {
        name = "Save Actionbars",
        notCheckable = true,
        func = UpdateActionBars,
    },
    removeActionbars = {
        name = "Remove Actionbars",
        notCheckable = true,
        func = RemoveActionBars,
        required = "actionBars"
    },
    loadActionbars = {
        name = "Load Actionbars",
        notCheckable = true,
        func = LoadActionBar,
        required = "actionBars",
    },
    delete = {
        name = "Delete",
        func = DeleteLoadout,
        notCheckable = true,
        skipFor = {default = true}
    },
    rename = {
        name = "Rename",
        func = RenameLoadout,
        notCheckable = true,
    },
    export = {
        name = "Export",
        func = ExportLoadout,
        notCheckable = true
    },
    addToCategory = {
        name = "Add to Category",
        menuList = "addToCategory",
        notCheckable = true,
        hasArrow = true,
    },
    removeFromCategory = {
        name = "Remove from this Category",
        func = RemoveFromSpecificCategory,
        notCheckable = true,
        level = 3,
    },
    postInChat = {
        name = "Post in Chat",
        func = PostInChat,
        notCheckable = true,
    }
}

local categoryFunctions = {
    addToCategory = {
        name = "Add to Category",
        hasArrow = true,
        notCheckable = true,
        menuList = "addToCategory"
    },
    removeFromCategory = {
        name = "Remove from Category",
        hasArrow = true,
        notCheckable = true,
        menuList = "removeFromCategory",
        required = "isSubCategory",
    },
    delete = {
        name = "Delete",
        func = DeleteCategory,
        notCheckable = true,
    },
    deleteWithLoadouts = {
        name = "Delete including Loadouts",
        func = DeleteCategory,
        arg2 = true,
        notCheckable = true,
    },
    rename = {
        name = "Rename",
        func = RenameCategory,
        notCheckable = true,
    },
    export = {
        name = "Export Category",
        tooltipTitle = "Export",
        tooltipText = "Export all loadouts associated with this category at once.",
        func = ExportCategory,
        notCheckable = true
    }
}

local function LoadoutDropdownInitialize(frame, level, menu, ...)
    TalentLoadouts:UpdateSpecID()
    local currentSpecID = TalentLoadouts.specID


    if level == 1 then

        -- Gets changed delayed because of text length, need to find a way to get the correct width for the separators, maybe cache the width?
        --print(_G["L_DropDownList" .. level]:GetWidth())
        local options = ImprovedTalentLoadoutsDB.options
        TalentLoadouts.globalDB.categories[currentSpecID] = TalentLoadouts.globalDB.categories[currentSpecID] or {}
        TalentLoadouts.globalDB.configIDs[currentSpecID] = TalentLoadouts.globalDB.configIDs[currentSpecID] or {}
        TalentLoadouts:UpdateLoadoutIterator()
        TalentLoadouts:UpdateCategoryIterator()
        
        local needSeparator = false
        for _, categoryInfo in iterateCategories() do
            if not categoryInfo.isSubCategory then
                needSeparator = true
                LibDD:UIDropDownMenu_AddButton(
                        {
                            value = categoryInfo,
                            colorCode = "|cFF34ebe1",
                            text = categoryInfo.name,
                            hasArrow = true,
                            minWidth = 170,
                            fontObject = dropdownFont,
                            notCheckable = 1,
                            menuList = "category"
                        },
                level)
            end
        end


        for configID, configInfo in iterateLoadouts() do
            if not configInfo.default and (not configInfo.categories or not next(configInfo.categories)) then
                needSeparator = true

                local color = (configInfo.error and "|cFFFF0000") or "|cFF33ff96"
                local customOrder = options.showCustomOrder and configInfo.customOrder
                LibDD:UIDropDownMenu_AddButton(
                    {
                        arg1 = configInfo,
                        value = configID,
                        colorCode = color,
                        text = customOrder and string.format("|cFFFFFFFF[%d]|r %s", customOrder, configInfo.name) or  configInfo.name,
                        hasArrow = true,
                        minWidth = 170,
                        fontObject = dropdownFont,
                        func = LoadLoadout,
                        checked = function()
                            return TalentLoadouts.charDB.lastLoadout and TalentLoadouts.charDB.lastLoadout == configID
                        end,
                        menuList = "loadout"
                    },
                level)
            end
        end

        if needSeparator then
            LibDD:UIDropDownMenu_AddButton(
                {
                    icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                    iconInfo = {tSizeX = 165},
                    notClickable = 1,
                    iconOnly = 1,
                    minWidth = 170,
                    hasArrow = false,
                    notCheckable = 1,
                },
            level)
        end

        if frame == TalentLoadouts.easyMenu and not IsAddOnLoaded(talentUI) then
            LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = 1,
                    text = string.format("%s New Loadout", CreateAtlasMarkup("communities-icon-addchannelplus")),
                    minWidth = 170,
                    fontObject = dropdownFont,
                    hasArrow = true,
                    disabled = 1,
                    tooltipWhileDisabled = 1,
                    tooltipTitle = "",
                    tooltipText = "Plase open the talent window at least once.",
                    tooltipOnButton = 1,
                    notCheckable = 1,
                    func = SaveCurrentTree,
                    menuList = "createLoadout"
                },
            level)
    
            LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = 1,
                    text = "Import Loadout",
                    minWidth = 170,
                    colorCode = "|cFFFFFFFF",
                    fontObject = dropdownFont,
                    hasArrow = true,
                    disabled = 1,
                    tooltipWhileDisabled = 1,
                    tooltipTitle = "",
                    tooltipText = "Plase open the talent window at least once.",
                    tooltipOnButton = 1,
                    notCheckable = 1,
                    func = ImportCustomLoadout,
                    menuList = "importLoadout"
                },
            level)
        else
            LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = 1,
                    text = string.format("%s %sNew Loadout|r", CreateAtlasMarkup("communities-icon-addchannelplus"), GREEN_FONT_COLOR_CODE),
                    minWidth = 170,
                    fontObject = dropdownFont,
                    hasArrow = true,
                    disabled = frame == TalentLoadouts.easyMenu and not IsAddOnLoaded(talentUI) and 1 or nil,
                    notCheckable = 1,
                    func = SaveCurrentTree,
                    menuList = "createLoadout"
                },
            level)
    
            LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = 1,
                    text = "Import Loadout",
                    minWidth = 170,
                    colorCode = "|cFFFFFFFF",
                    fontObject = dropdownFont,
                    hasArrow = true,
                    disabled = frame == TalentLoadouts.easyMenu and not IsAddOnLoaded(talentUI) and 1 or nil,
                    notCheckable = 1,
                    func = ImportCustomLoadout,
                    menuList = "importLoadout"
                },
            level)
        end


        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 165},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Create Category",
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                notCheckable = 1,
                func = CreateCategory,
            }
        )

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Import Category",
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCategory,
            }
        )

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 165},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Options",
                notCheckable = 1,
                hasArrow = true,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                minWidth = 170,
                menuList = "options"
            }
        )

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Close",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = LibDD.CloseDropDownMenus,
            },
        level)
    elseif menu == "createLoadout" then
        local categories = TalentLoadouts.globalDB.categories[currentSpecID]
        local hasCategory = next(categories) ~= nil

        LibDD:UIDropDownMenu_AddButton(
            {
                value = 1,
                arg1 = 1,
                text = "New Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = SaveCurrentTree,
                hasArrow = hasCategory,
                menuList = hasCategory and "createLoadoutToCategory"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                value = 2,
                arg1 = 2,
                text = "New Class Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = SaveCurrentTree,
                hasArrow = hasCategory,
                menuList = hasCategory and "createLoadoutToCategory"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                value = 3,
                arg1 = 3,
                text = "New Spec Loadout",
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                notCheckable = 1,
                func = SaveCurrentTree,
                hasArrow = hasCategory,
                menuList = hasCategory and "createLoadoutToCategory"
            },
        level)
    elseif menu == "importLoadout" then
        local categories = TalentLoadouts.globalDB.categories[currentSpecID]
        local hasCategory = next(categories) ~= nil

        LibDD:UIDropDownMenu_AddButton(
            {
                value = 1,
                arg1 = 1,
                text = "Import Loadout",
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCustomLoadout,
                hasArrow = hasCategory,
                menuList = hasCategory and "importLoadoutToCategory"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                value = 2,
                arg1 = 2,
                text = "Import Class Loadout",
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCustomLoadout,
                hasArrow = hasCategory,
                menuList = hasCategory and "importLoadoutToCategory"
            },
        level)
        
        LibDD:UIDropDownMenu_AddButton(
            {
                value = 3,
                arg1 = 3,
                text = "Import Spec Loadout",
                colorCode = "|cFFFFFFFF",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCustomLoadout,
                hasArrow = hasCategory,
                menuList = hasCategory and "importLoadoutToCategory"
            },
        level)
    elseif menu == "importLoadoutToCategory" then
        -- L_UIDROPDOWNMENU_MENU_VALUE
        for _, categoryInfo in iterateCategories() do
            if not categoryInfo.isSubCategory then
                LibDD:UIDropDownMenu_AddButton(
                        {
                            arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                            arg2 = categoryInfo,
                            text = string.format("to |cFF34ebe1%s|r", categoryInfo.name),
                            minWidth = 170,
                            func = ImportCustomLoadout,
                            fontObject = dropdownFont,
                            notCheckable = 1,
                        },
                level)

                TalentLoadouts:AddSubCategoriesToImportDropdown(categoryInfo, currentSpecID, level, 1)
            end
        end
    elseif menu == "createLoadoutToCategory" then
        -- L_UIDROPDOWNMENU_MENU_VALUE
        for _, categoryInfo in iterateCategories() do
            if not categoryInfo.isSubCategory then
                LibDD:UIDropDownMenu_AddButton(
                        {
                            arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                            arg2 = categoryInfo,
                            text = string.format("to |cFF34ebe1%s|r", categoryInfo.name),
                            minWidth = 170,
                            func = SaveCurrentTree,
                            fontObject = dropdownFont,
                            notCheckable = 1,
                        },
                level)

                TalentLoadouts:AddSubCategoriesToCreateDropdown(categoryInfo, currentSpecID, level, 1)
            end
        end
    elseif menu == "options" then
        --print(_G["L_DropDownList" .. level]:GetWidth())

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Display Category Name",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.showCategoryName = not ImprovedTalentLoadoutsDB.options.showCategoryName
                    TalentLoadouts:UpdateDropdownText()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.showCategoryName
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Show Spec Buttons",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.showSpecButtons = not ImprovedTalentLoadoutsDB.options.showSpecButtons
                    TalentLoadouts:UpdateSpecButtons()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.showSpecButtons
                end 
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Sort Loadouts by Name",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.sortLoadoutsByName = not ImprovedTalentLoadoutsDB.options.sortLoadoutsByName
                    TalentLoadouts:UpdateLoadoutIterator()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.sortLoadoutsByName
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Sort Categories by Name",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.sortCategoriesByName = not ImprovedTalentLoadoutsDB.options.sortCategoriesByName
                    TalentLoadouts:UpdateCategoryIterator()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.sortCategoriesByName
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Sort Subcategories by Name",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.sortSubcategoriesByName = not ImprovedTalentLoadoutsDB.options.sortSubcategoriesByName
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.sortSubcategoriesByName
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Show Custom Order",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.showCustomOrder = not ImprovedTalentLoadoutsDB.options.showCustomOrder
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.showCustomOrder
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 209},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Loadouts",
                notCheckable = 1,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "globalLoadoutOptions"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Action Bars",
                notCheckable = 1,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "actionBarOptions"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Spec Button Type",
                notCheckable = 1,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "specButtonType"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Font Size",
                notCheckable = 1,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "fontSizeOptions"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Cached Actionbars",
                notCheckable = 1,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "cachedActionbars"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 209},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Delete All",
                notCheckable = 1,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                func = function()
                    TalentLoadouts:ShowDeleteAll()
                end,
            },
        level)
    elseif menu == "cachedActionbars" then
        local cached = TalentLoadouts.charDB.cachedActionbars
        for specID, actionBars in pairs(cached) do
            LibDD:UIDropDownMenu_AddButton(
                {
                    text = select(2, GetSpecializationInfoByID(specID)),
                    colorCode = "|cFFFFFFFF",
                    fontObject = dropdownFont,
                    func = function()
                        TalentLoadouts:LoadActionBar(actionBars)
                        LibDD.CloseDropDownMenus()
                    end,
                    notCheckable = 1,
                },
            level)
        end
    elseif menu == "fontSizeOptions" then
        local fontSizes = {10, 11, 12, 13, 14, 15, 16, 18, 20}
        for _, fontSize in ipairs(fontSizes) do
            LibDD:UIDropDownMenu_AddButton(
                {
                    text = fontSize,
                    colorCode = "|cFFFFFFFF",
                    fontObject = dropdownFont,
                    func = function()
                        ImprovedTalentLoadoutsDB.options.fontSize = fontSize
                        TalentLoadouts:UpdateDropdownFont()
                        LibDD.CloseDropDownMenus()
                    end,
                    checked = function()
                        return ImprovedTalentLoadoutsDB.options.fontSize == fontSize
                    end
                },
            level)
        end
    elseif menu == "actionBarOptions" then
        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Load Action Bars with Loadout",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.loadActionbars = not ImprovedTalentLoadoutsDB.options.loadActionbars
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.loadActionbars
                end
            },
        level)

                LibDD:UIDropDownMenu_AddButton(
            {
                text = "Load Action Bars with Spec",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.loadActionbarsSpec = not ImprovedTalentLoadoutsDB.options.loadActionbarsSpec
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.loadActionbarsSpec
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Clear Slots when loading Action Bars",
                isNotRadio = true,
                minWidth = 170,
                tooltipTitle = "|cffff0000WARNING! Use this option at your own risk!|r",
                tooltipText = "This will remove an action from a slot if it was empty when you've saved the action bars. It's unclear if this affects the action bars of other specs.",
                tooltipOnButton = 1,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.clearEmptySlots = not ImprovedTalentLoadoutsDB.options.clearEmptySlots
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.clearEmptySlots
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Find Macro By Name",
                isNotRadio = true,
                tooltipTitle = "Description:",
                tooltipText = "Lets the AddOn find saved macros based on their names (instead of name + body).",
                tooltipOnButton = 1,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.findMacroByName = not ImprovedTalentLoadoutsDB.options.findMacroByName
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.findMacroByName
                end
            },
        level)
    elseif menu == "globalLoadoutOptions" then
        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Automatically apply Loadout",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.applyLoadout = not ImprovedTalentLoadoutsDB.options.applyLoadout
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.applyLoadout
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Add Loadouts to /simc",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.simc = not ImprovedTalentLoadoutsDB.options.simc
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.simc
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Load Blizzard Loadouts",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                tooltipOnButton = 1,
                tooltipTitle = "Load Blizzard Loadouts",
                tooltipText = "Load loadouts which also exists in the Blizzard dropdown with the Blizzard API functions and don't handle it as an AddOn loadout. At large this disables the action bar handling of the AddOn",
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.loadBlizzard = not ImprovedTalentLoadoutsDB.options.loadBlizzard
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.loadBlizzard
                end 
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Use Blizzard Loading Method",
                isNotRadio = true,
                minWidth = 170,
                tooltipOnButton = 1,
                tooltipTitle = "",
                tooltipText = "|cffff0000It is recommended to enable this option to avoid some actionbar related bugs which cannot be fixed. This uses the [ITL] Temp loadout.|r",
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.loadAsBlizzard = not ImprovedTalentLoadoutsDB.options.loadAsBlizzard
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.loadAsBlizzard
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Fall back to AddOn Loadout",
                isNotRadio = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.useAddOnLoadoutFallback = not ImprovedTalentLoadoutsDB.options.useAddOnLoadoutFallback
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.useAddOnLoadoutFallback
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Find Matching Loadout",
                isNotRadio = true,
                minWidth = 170,
                tooltipOnButton = 1,
                tooltipTitle = "",
                tooltipText = "Instead of showing 'Unknown' the AddOn searches for a Loadout that has a matching export string to the current one when changing talents manually.",
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                keepShownOnClick = 1,
                func = function()
                    ImprovedTalentLoadoutsDB.options.findMatchingLoadout = not ImprovedTalentLoadoutsDB.options.findMatchingLoadout
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.findMatchingLoadout
                end
            },
        level)
    elseif menu == "specButtonType" then
        local buttonTypes = {"text", "icon"}
        local buttonTypesText = {"Text", "Icons"}
        for i, buttonType in ipairs(buttonTypes) do
            LibDD:UIDropDownMenu_AddButton(
            {
                text = buttonTypesText[i],
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.specButtonType = buttonType
                    TalentLoadouts:UpdateSpecButtons()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.specButtonType == buttonType
                end,
            }
            ,level)
        end
    elseif menu == "loadout" then
        local configID, categoryInfo = L_UIDROPDOWNMENU_MENU_VALUE
        if type(L_UIDROPDOWNMENU_MENU_VALUE) == "table" then
            configID, categoryInfo = unpack(L_UIDROPDOWNMENU_MENU_VALUE)
        end
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]

        local arrowFunctions = {"addToCategory", "removeFromCategory", "assignGearset", "assignLayout"}
        for _, func in ipairs(arrowFunctions) do
            local info = loadoutFunctions[func]
            if info and (not info.required or configInfo[info.required]) and (not info.level or level == info.level) then
                LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = configID,
                    arg2 = categoryInfo,
                    value = configID,
                    notCheckable = info.notCheckable and 1 or nil,
                    tooltipTitle = info.tooltipTitle,
                    tooltipOnButton = info.tooltipText and 1 or nil,
                    tooltipText = info.tooltipText,
                    text = info.name,
                    isNotRadio = true,
                    colorCode = "|cFFFFFFFF",
                    fontObject = dropdownFont,
                    func = info.func,
                    checked = info.checked,
                    hasArrow = info.hasArrow,
                    menuList = info.menuList,
                    minWidth = 150,
                },
                level)
            end
        end

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 165},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        local orderFunctions = {"setCustomOrder", "removeCustomOrder"}
        for _, func in ipairs(orderFunctions) do
            local info = loadoutFunctions[func]
            if info and (not info.required or configInfo[info.required]) and (not info.level or level == info.level) then
                LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = configID,
                    arg2 = categoryInfo,
                    value = configID,
                    notCheckable = info.notCheckable and 1 or nil,
                    tooltipTitle = info.tooltipTitle,
                    tooltipOnButton = info.tooltipText and 1 or nil,
                    tooltipText = info.tooltipText,
                    text = info.name,
                    isNotRadio = true,
                    colorCode = "|cFFFFFFFF",
                    fontObject = dropdownFont,
                    keepShownOnClick = 1,
                    func = info.func,
                    checked = info.checked,
                    hasArrow = info.hasArrow,
                    menuList = info.menuList,
                    minWidth = 150,
                },
                level)
            end
        end

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 165},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        local updateFunctions = {"updateTree", "updateWithString"}
        for _, func in ipairs(updateFunctions) do
            local info = loadoutFunctions[func]
            if info and (not info.required or configInfo[info.required]) and (not info.level or level == info.level) then
                LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = configID,
                    arg2 = categoryInfo,
                    value = configID,
                    notCheckable = info.notCheckable and 1 or nil,
                    tooltipTitle = info.tooltipTitle,
                    tooltipOnButton = info.tooltipText and 1 or nil,
                    tooltipText = info.tooltipText,
                    text = info.name,
                    isNotRadio = true,
                    colorCode = "|cFFFFFFFF",
                    fontObject = dropdownFont,
                    keepShownOnClick = 1,
                    func = info.func,
                    checked = info.checked,
                    hasArrow = info.hasArrow,
                    menuList = info.menuList,
                    minWidth = 150,
                },
                level)
            end
        end

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 165},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        local actionbarFunctions = {"updateActionbars", "removeActionbars", "loadActionbars"}
        for _, func in ipairs(actionbarFunctions) do
            local info = loadoutFunctions[func]
            if info and (not info.required or configInfo[info.required]) and (not info.level or level == info.level) then
                LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = configID,
                    arg2 = categoryInfo,
                    value = configID,
                    notCheckable = info.notCheckable and 1 or nil,
                    tooltipTitle = info.tooltipTitle,
                    tooltipOnButton = info.tooltipText and 1 or nil,
                    tooltipText = info.tooltipText,
                    text = info.name,
                    isNotRadio = true,
                    colorCode = "|cFFFFFFFF",
                    fontObject = dropdownFont,
                    func = info.func,
                    checked = info.checked,
                    hasArrow = info.hasArrow,
                    menuList = info.menuList,
                    minWidth = 150,
                },
                level)
            end
        end

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 165},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        local defaultFunctions = {"rename", "delete", "export"}
        for _, func in ipairs(defaultFunctions) do
            local info = loadoutFunctions[func]
            if info and (not info.required or configInfo[info.required]) and (not info.level or level == info.level) then
                LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = configID,
                    arg2 = categoryInfo,
                    value = configID,
                    notCheckable = info.notCheckable and 1 or nil,
                    tooltipTitle = info.tooltipTitle,
                    tooltipOnButton = info.tooltipText and 1 or nil,
                    tooltipText = info.tooltipText,
                    text = info.name,
                    isNotRadio = true,
                    colorCode = "|cFFFFFFFF",
                    fontObject = dropdownFont,
                    func = info.func,
                    checked = info.checked,
                    hasArrow = info.hasArrow,
                    menuList = info.menuList,
                    minWidth = 150,
                },
                level)
            end
        end
    elseif menu == "category" then
        local categoryInfo = TalentLoadouts.globalDB.categories[currentSpecID][L_UIDROPDOWNMENU_MENU_VALUE.key]
        if categoryInfo then
            if categoryInfo.categories then
                local sort = ImprovedTalentLoadoutsDB.options.sortSubcategoriesByName
                local iterator = GenerateClosure(sort and spairs or ipairs, categoryInfo.categories, sort and sortByValue or nil)
                for _, categoryKey in iterator() do
                    local categoryInfo = TalentLoadouts.globalDB.categories[currentSpecID][categoryKey]
                    if categoryInfo and categoryInfo.name then
                        LibDD:UIDropDownMenu_AddButton(
                        {
                            value = categoryInfo,
                            colorCode = "|cFF34ebe1",
                            text = categoryInfo.name,
                            hasArrow = true,
                            minWidth = 170,
                            fontObject = dropdownFont,
                            notCheckable = 1,
                            menuList = "category"
                        },
                level)
                    end
                end
            end

            local categoryLoadouts = {}
            for _, cID in ipairs(categoryInfo.loadouts) do
                table.insert(categoryLoadouts, cID, true)
            end

            TalentLoadouts:UpdateLoadoutIterator(L_UIDROPDOWNMENU_MENU_VALUE.key)

            for configID, configInfo in iterateLoadouts() do
                if categoryLoadouts[configID] ~= nil and configInfo and not configInfo.default then
                    local customOrder = ImprovedTalentLoadoutsDB.options.showCustomOrder and configInfo.categoryCustomOrder and configInfo.categoryCustomOrder[L_UIDROPDOWNMENU_MENU_VALUE.key]
                    LibDD:UIDropDownMenu_AddButton(
                        {
                            arg1 = configInfo,
                            arg2 = categoryInfo,
                            value = {configID, categoryInfo},
                            colorCode = "|cFF33ff96",
                            text = customOrder and string.format("|cFFFFFFFF[%d]|r %s", customOrder, configInfo.name) or configInfo.name,
                            minWidth = 170,
                            fontObject = dropdownFont,
                            hasArrow = true,
                            func = function(...)
                                LoadLoadout(...)
                                LibDD:CloseDropDownMenus()
                            end,
                            checked = function()
                                return TalentLoadouts.charDB.lastLoadout and TalentLoadouts.charDB.lastLoadout == configID
                            end,
                            menuList = "loadout"
                        },
                    level)
                end
            end
        end

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 165},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                value = L_UIDROPDOWNMENU_MENU_VALUE,
                text = "Category Options",
                hasArrow = true,
                minWidth = 170,
                colorCode = "|cFFFFFFFF",
                fontObject = dropdownFont,
                notCheckable = 1,
                menuList = "categoryOptions"
            },
        level)
    elseif menu == "categoryOptions" then
        local arrowFunctions = {"addToCategory"}
        for _, func in ipairs(arrowFunctions) do
            local info = categoryFunctions[func]
            if info and (not info.required or L_UIDROPDOWNMENU_MENU_VALUE[info.required]) then
                LibDD:UIDropDownMenu_AddButton(
                {
                    value = L_UIDROPDOWNMENU_MENU_VALUE,
                    arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                    arg2 = info.arg2,
                    colorCode = "|cFFFFFFFF",
                    notCheckable = info.notCheckable and 1 or nil,
                    tooltipTitle = info.tooltipTitle,
                    tooltipOnButton = info.tooltipText and 1 or nil,
                    tooltipText = info.tooltipText,
                    text = info.name,
                    isNotRadio = true,
                    fontObject = dropdownFont,
                    func = info.func,
                    checked = info.checked,
                    hasArrow = info.hasArrow,
                    menuList = info.menuList,
                    minWidth = 170,
                },
                level)
            end
        end

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 165},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        local defaultFunctions = {"rename", "delete", "deleteWithLoadouts"}
        for _, func in ipairs(defaultFunctions) do
            local info = categoryFunctions[func]
            if info and (not info.required or L_UIDROPDOWNMENU_MENU_VALUE[info.required]) then
                LibDD:UIDropDownMenu_AddButton(
                {
                    value = L_UIDROPDOWNMENU_MENU_VALUE,
                    arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                    arg2 = info.arg2,
                    colorCode = "|cFFFFFFFF",
                    notCheckable = info.notCheckable and 1 or nil,
                    tooltipTitle = info.tooltipTitle,
                    tooltipOnButton = info.tooltipText and 1 or nil,
                    tooltipText = info.tooltipText,
                    text = info.name,
                    isNotRadio = true,
                    fontObject = dropdownFont,
                    func = info.func,
                    checked = info.checked,
                    hasArrow = info.hasArrow,
                    menuList = info.menuList,
                    minWidth = 170,
                },
                level)
            end
        end

        LibDD:UIDropDownMenu_AddButton(
            {
                icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
                iconInfo = {tSizeX = 165},
                notClickable = 1,
                iconOnly = 1,
                minWidth = 170,
                hasArrow = false,
                notCheckable = 1,
            },
        level)

        local advancedOptions = {"export"}
        for _, func in ipairs(advancedOptions) do
            local info = categoryFunctions[func]
            if info and (not info.required or L_UIDROPDOWNMENU_MENU_VALUE[info.required]) then
                LibDD:UIDropDownMenu_AddButton(
                {
                    value = L_UIDROPDOWNMENU_MENU_VALUE,
                    arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                    arg2 = info.arg2,
                    colorCode = "|cFFFFFFFF",
                    notCheckable = info.notCheckable and 1 or nil,
                    tooltipTitle = info.tooltipTitle,
                    tooltipOnButton = info.tooltipText and 1 or nil,
                    tooltipText = info.tooltipText,
                    text = info.name,
                    isNotRadio = true,
                    fontObject = dropdownFont,
                    func = info.func,
                    checked = info.checked,
                    hasArrow = info.hasArrow,
                    menuList = info.menuList,
                    minWidth = 170,
                },
                level)
            end
        end
    elseif menu == "addToCategory" then
        local isCategory = type(L_UIDROPDOWNMENU_MENU_VALUE) == "table"

        for _, categoryInfo in iterateCategories() do
            if not isCategory or categoryInfo.key ~= L_UIDROPDOWNMENU_MENU_VALUE.key then
                LibDD:UIDropDownMenu_AddButton(
                        {
                            arg1 = categoryInfo,
                            arg2 = L_UIDROPDOWNMENU_MENU_VALUE,
                            colorCode = "|cFFab96b3",
                            text = categoryInfo.name,
                            minWidth = 170,
                            fontObject = dropdownFont,
                            notCheckable = 1,
                            func = AddToCategory,
                        },
                level)
            end
        end
    elseif menu == "removeFromCategory" then
        for _, categoryKey in ipairs(L_UIDROPDOWNMENU_MENU_VALUE.parents) do
            local categoryInfo = TalentLoadouts.globalDB.categories[currentSpecID][categoryKey]
            if categoryInfo then
                LibDD:UIDropDownMenu_AddButton(
                        {
                            arg1 = categoryInfo,
                            arg2 = L_UIDROPDOWNMENU_MENU_VALUE,
                            colorCode = "|cFFab96b3",
                            text = categoryInfo.name,
                            minWidth = 170,
                            fontObject = dropdownFont,
                            notCheckable = 1,
                            func = RemoveCategoryFromCategory,
                        },
                level)
            end
        end
    elseif menu == "gearset" then
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][L_UIDROPDOWNMENU_MENU_VALUE]
        if configInfo then
            for _, equipmentSetID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
                local name, icon = C_EquipmentSet.GetEquipmentSetInfo(equipmentSetID)

                LibDD:UIDropDownMenu_AddButton(
                    {
                        arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                        text = string.format("|T%d:0|t %s", icon, name),
                        colorCode = "|cFFFFFFFF",
                        fontObject = dropdownFont,
                        minWidth = 170,
                        checked = function()
                            return configInfo.gearset and configInfo.gearset == equipmentSetID
                        end,
                        func = function()
                            if configInfo.gearset and configInfo.gearset == equipmentSetID then
                                configInfo.gearset = nil
                            else
                                configInfo.gearset = equipmentSetID
                            end
                        end
                    },
                level)
            end
        end
    elseif menu == "layout" then
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][L_UIDROPDOWNMENU_MENU_VALUE]
        if configInfo then
            local layoutsInfo =  C_EditMode.GetLayouts()
            if not layoutsInfo then return end

            for index, info in ipairs(layoutsInfo.layouts) do
                local layoutIndex = index + 2

                LibDD:UIDropDownMenu_AddButton(
                    {
                        text = info.layoutName,
                        colorCode = "|cFFFFFFFF",
                        fontObject = dropdownFont,
                        minWidth = 170,
                        checked = function()
                            return configInfo.layout and configInfo.layout == layoutIndex
                        end,
                        func = function()
                            if configInfo.layout and configInfo.layout == layoutIndex then
                                configInfo.layout = nil
                            else
                                configInfo.layout = layoutIndex
                            end
                        end
                    },
                level)
            end
        end
    end
end

function TalentLoadouts:UpdateDropdownText()
    if not self.dropdown then return end

    local currentSpecID = self.specID
    local dropdownText = ""

    local color, configInfo = "FFFFFF", nil
    if self.pendingLoadout then
        color = "F5B042"
        configInfo = self.pendingLoadout
    elseif self.charDB[currentSpecID] then
        configInfo = self.globalDB.configIDs[currentSpecID][self.charDB[currentSpecID]]
    elseif self.charDB.lastLoadout then 
        configInfo = self.globalDB.configIDs[currentSpecID][self.charDB.lastLoadout]
    end
    dropdownText = string.format("|cFF%s%s|r", color, configInfo and configInfo.name or "Unknown")

    if self.charDB.lastCategory and ImprovedTalentLoadoutsDB.options.showCategoryName then
        dropdownText = string.format("|cFF34ebe1[%s]|r %s", self.charDB.lastCategory.name, dropdownText)
        LibDD:UIDropDownMenu_SetText(self.dropdown, dropdownText)
    else
        LibDD:UIDropDownMenu_SetText(self.dropdown, dropdownText)
    end
end

function TalentLoadouts:UpdateDropdownFont()
    dropdownFont:SetFont(GameFontNormal:GetFont(), ImprovedTalentLoadoutsDB.options.fontSize or 10, "")
end

function TalentLoadouts:InitializeHooks()
    hooksecurefunc(C_Traits, "RollbackConfig", function()
        if TalentLoadouts.currentLoadout then
            TalentLoadouts.pendingLoadout = nil
            TalentLoadouts.charDB.lastLoadout = TalentLoadouts.currentLoadout
            TalentLoadouts.currentLoadout = nil
            TalentLoadouts:UpdateDropdownText()
        end
    end)

    if not IsAddOnLoaded("Simulationcraft") then return end
    hooksecurefunc(SlashCmdList, "ACECONSOLE_SIMC", function()
        if not ImprovedTalentLoadoutsDB.options.simc then return end

        local customLoadouts
        for _, v in ITLAPI.EnumerateSpecLoadouts() do
           if not v.default and v.exportString then
              if customLoadouts then
                 customLoadouts = string.format("%s\n# Saved Loadout: %s\n# talents=%s", customLoadouts, v.name, v.exportString)
              else
                 customLoadouts = string.format("\n# Saved Loadout: %s\n# talents=%s", v.name, v.exportString)
              end
           end
        end
        
        if customLoadouts and SimcEditBox then
           local hooked = true
           local text = SimcEditBox:GetText()

           local outputHeader = "\n\n# From ImprovedTalentLoadouts\n#"
           customLoadouts = outputHeader .. customLoadouts

           SimcEditBox:SetCursorPosition(SimcEditBox:GetNumLetters())
           SimcEditBox:HighlightText(0,0)
           SimcEditBox:Insert(customLoadouts)
           SimcEditBox:HighlightText()
           SimcEditBox:SetFocus()
           SimcEditBox:HookScript("OnTextChanged", function(self) 
                 if hooked then
                    self:SetText(text .. customLoadouts)
                    self:HighlightText()
                 end
           end)
           
           SimcEditBox:HookScript("OnHide", function(self)
                 hooked = false
           end)
        end
  end)
end

function TalentLoadouts:InitializeDropdown()
    local dropdown = LibDD:Create_UIDropDownMenu(addonName .. "DropdownMenu", ClassTalentFrame.TalentsTab)
    self.dropdown = dropdown
    dropdown:SetPoint("LEFT", ClassTalentFrame.TalentsTab.SearchBox, "RIGHT", 0, -1)
    
    LibDD:UIDropDownMenu_SetAnchor(dropdown, 0, 16, "BOTTOM", dropdown.Middle, "CENTER")
    LibDD:UIDropDownMenu_Initialize(dropdown, LoadoutDropdownInitialize)
    LibDD:UIDropDownMenu_SetWidth(dropdown, 170)
    self:UpdateDropdownText()

    if IsAddOnLoaded('ElvUI') then
        ElvUI[1]:GetModule('Skins'):HandleDropDownBox(dropdown)
        LibDD:UIDropDownMenu_SetWidth(dropdown, 170)
    end

    --[[hooksecurefunc(LibDD, "ToggleDropDownMenu", function(self, level, ...)
        if level then
            if (level - 1) > 0 then
                local button
                for i=1, L_UIDROPDOWNMENU_MAXBUTTONS do
                    button = _G["L_DropDownList"..(level-1).."Button"..i];
                    if button:IsMouseOver() then
                        TalentLoadouts.lastButton = button
                        return
                    end
                end
            end
            print(TalentLoadouts.dropdown, _G["L_DropDownList" .. level], level, ...)
        end
    end)]]
end

function TalentLoadouts:InitializeEasyMenu()
    local easyMenu = LibDD:Create_UIDropDownMenu(addonName .. "EasyMenu", nil)
    self.easyMenu = easyMenu
    easyMenu.displayMode = "MENU"
    LibDD:UIDropDownMenu_Initialize(easyMenu, LoadoutDropdownInitialize, "MENU")
end

local function CreateTextSpecButton(width, specIndex, _, specName)
    local specButton = CreateFrame("Button", nil, TalentLoadouts.dropdown, "UIPanelButtonNoTooltipTemplate, UIButtonTemplate")
    specButton:SetNormalAtlas("charactercreate-customize-dropdownbox")
    specButton:SetSize(width, 30)

    if #specName > ceil(width/10) then
        specButton:SetText(specName:sub(1, ceil(width/11)) .. "...")
    else
        specButton:SetText(specName)
    end
    PixelUtil.SetPoint(specButton,"LEFT", ClassTalentFrame.TalentsTab.ResetButton , "RIGHT", (specIndex-1) * (width + 1), -2)

    if IsAddOnLoaded('ElvUI') then
        ElvUI[1]:GetModule('Skins'):HandleButton(specButton)
        specButton:SetSize(width - 2, 25)
    end
    return specButton
end

local function CreateIconSpecButton(width, specIndex, numSpecializations, _, icon)
    width = 79.5

    local specButton = CreateFrame("Button", nil, TalentLoadouts.dropdown)
    specButton:SetNormalTexture(icon)
    specButton:SetHighlightTexture(icon)
    specButton:SetSize(39.75, 39.75)
    specButton:SetPoint("LEFT", ClassTalentFrame.TalentsTab.ResetButton , "RIGHT", (specIndex-1) * (width/2 + 1) + (width * (numSpecializations==3 and 1.25 or 1)), -2)
    
    return specButton
end

function TalentLoadouts:CreateSpecButtons(specButtonType)
    local createFunction = specButtonType == "text" and CreateTextSpecButton or CreateIconSpecButton
    self.specButtons[specButtonType] = {}
    local specTypeButtons = self.specButtons[specButtonType]

    local numSpecializations = GetNumSpecializations()
    local width = 318 / numSpecializations
    for specIndex=1, numSpecializations do
        local specName, _, icon = select(2, GetSpecializationInfo(specIndex))
        local specButton = createFunction(width, specIndex, numSpecializations, specName, icon)
        specButton.name = specName
        specButton.icon = icon
        specButton.width = width
        specButton.type = ImprovedTalentLoadoutsDB.options.specButtonType
        specTypeButtons[specIndex] = specButton
        specButton.specIndex = specIndex
        specButton:RegisterForClicks("LeftButtonDown")

        specButton:SetScript("OnClick", function(self)
            if self.specIndex ~= GetSpecialization() then
                SetSpecialization(specIndex)
            end
        end)
        
        specButton:SetScript("OnEnter", function()
            GameTooltip:SetOwner(specButton, "ANCHOR_TOP")
            GameTooltip:AddLine("Change your specialization to " .. specName)
            GameTooltip:Show()
        end)
        
        specButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        if specIndex == GetSpecialization() then
            specButton:GetNormalTexture():SetVertexColor(0, 1, 0)
        end
    end
end

function TalentLoadouts:InitializeButtons()
    local saveButton = CreateFrame("Button", nil, self.dropdown, "UIPanelButtonNoTooltipTemplate, UIButtonTemplate")
    self.saveButton = saveButton
    saveButton:SetSize(65, 32)
    saveButton:SetNormalAtlas("charactercreate-customize-dropdownbox")
    --saveButton:SetHighlightAtlas("charactercreate-customize-dropdownbox-open")    
    saveButton:RegisterForClicks("LeftButtonDown")
    saveButton:SetPoint("LEFT", self.dropdown, "RIGHT", -10, 2)
    saveButton:SetText("Update")
    saveButton:Disable()
    saveButton.enabled = false

    saveButton:SetDisabledTooltip("", "ANCHOR_TOP")
    saveButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(saveButton, "ANCHOR_TOP")
        GameTooltip:AddLine("Update the active loadout with the current tree.")
        GameTooltip:AddLine("Hold down SHIFT to update the loadout")
        GameTooltip:AddLine("Hold down CTRL to update the loadout + action bars")
        GameTooltip:Show()
    end)
    
    saveButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    saveButton:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            UpdateWithCurrentTree(nil, TalentLoadouts.charDB.lastLoadout, TalentLoadouts.charDB.lastCategory, true)
        elseif IsControlKeyDown() then
            UpdateWithCurrentTree(nil, TalentLoadouts.charDB.lastLoadout, TalentLoadouts.charDB.lastCategory, true)
            UpdateActionBars(nil, TalentLoadouts.charDB.lastLoadout)
        end
    end)

    if IsAddOnLoaded('ElvUI') then
        ElvUI[1]:GetModule('Skins'):HandleButton(saveButton)
        saveButton:SetHeight(22)
        saveButton:AdjustPointsOffset(4, 1)
    end

    self.specButtons = {}
    if ImprovedTalentLoadoutsDB.options.showSpecButtons then
        self:CreateSpecButtons(ImprovedTalentLoadoutsDB.options.specButtonType)
    end
end

function TalentLoadouts:UpdateSpecButtons()
    local specButtonType = ImprovedTalentLoadoutsDB.options.specButtonType

    for _, specButtons in pairs(self.specButtons) do
        for _, specButton in ipairs(specButtons) do
            specButton:Hide()
        end
    end

    if not self.specButtons[specButtonType] then
        self:CreateSpecButtons(specButtonType)
    end

    if ImprovedTalentLoadoutsDB.options.showSpecButtons then
        for specIndex, specButton in ipairs(self.specButtons[specButtonType]) do
            specButton:Show()
            if specIndex == GetSpecialization() then
                specButton:GetNormalTexture():SetVertexColor(0, 1, 0)
            else
                specButton:GetNormalTexture():SetVertexColor(1, 1, 1)
            end
        end
    end
end

function TalentLoadouts:Print(...)
    print("|cff33ff96[TalentLoadouts]|r", ...)
end

function TalentLoadouts:UpdateMacros()
    if not self.initialized then return end

    self.globalMacros = {}
    self.characterMacros = {}
    self.duplicates = {}
    local globalMacros = self.globalMacros
    local charMacros = self.characterMacros

    for macroSlot = 1, MAX_ACCOUNT_MACROS do
        local name, _, body = GetMacroInfo(macroSlot)

        if name then
            body = strtrim(body:gsub("\r", ""))
            local key = string.format("%s\031%s", name, body)
            globalMacros[macroSlot] = {
                slot = macroSlot,
                body = body,
                name = name,
                key = key
            }

            if globalMacros[name] then
                self.duplicates[name] = true
            end

            globalMacros[key] = macroSlot
            globalMacros[name] = macroSlot
        elseif globalMacros[macroSlot] then
            globalMacros[globalMacros[macroSlot].key] = nil
            globalMacros[macroSlot] = nil
        end
    end

    for macroSlot = MAX_ACCOUNT_MACROS + 1, (MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS) do
        local name, _, body = GetMacroInfo(macroSlot)
        if name then
        body = strtrim(body:gsub("\r", ""))
            local key = string.format("%s\031%s", name, body)
            charMacros[macroSlot] = {
                slot = macroSlot,
                body = body,
                name = name,
                key = key,
            }

            if charMacros[name] then
                self.duplicates[name] = true
            end

            charMacros[key] = macroSlot
            charMacros[name] = macroSlot
        elseif charMacros[macroSlot] then
            charMacros[charMacros[macroSlot].key] = nil
            charMacros[macroSlot] = nil
        end
    end

    --backwards compatibility
    self.charMacros = self.characterMacros
end

function TalentLoadouts:UpdateKnownFlyouts()
    self.flyouts = {}

    for i = 1, GetNumSpellTabs() do
        local offset, numSpells, _, offSpecID = select(3, GetSpellTabInfo(i));
        if offSpecID == 0 then
            for slotId = offset + 1, numSpells + offset do
                local spellType, id = GetSpellBookItemInfo(slotId, BOOKTYPE_SPELL)
                if spellType  and spellType == "FLYOUT" then
                    self.flyouts[id] = slotId
                end
            end
        end
    end
end
SLASH_IMPROVEDTALENDLOADOUTS1 = '/itl'
SlashCmdList["IMPROVEDTALENDLOADOUTS"] = function(msg)
    local action, argument = strsplit(" ", msg, 2)
    argument = SecureCmdOptionParse(argument) or argument

    if action == 'saveActionbar' then
        local currentSpecID = TalentLoadouts.specID
        local configID = TalentLoadouts.charDB[currentSpecID]
        if configID then
            UpdateActionBars(nil, configID)
        end
    elseif action == 'load' then
        if #argument > 0 then
            TalentLoadouts:LoadLoadoutByName(argument)
        end
    end
end
