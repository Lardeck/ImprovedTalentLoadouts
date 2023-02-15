local addonName, TalentLoadouts = ...

local talentUI = "Blizzard_ClassTalentUI"
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")
local internalVersion = 6
local NUM_ACTIONBAR_BUTTONS = 15 * 12

local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
local dataObjText = "ITL: %s, %s"
local dataObj = LDB:NewDataObject(addonName, {type = "data source", text = "ITL: Spec, Loadout"})

local dropdownFont = CreateFont("ITL_DropdownFont")

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
    RegisterEvent("UPDATE_MACROS")
    RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 == addonName then
                TalentLoadouts:Initialize()
            elseif arg1 == talentUI then
                self:UnregisterEvent("ADDON_LOADED")
                TalentLoadouts:InitializeTalentLoadouts()
                TalentLoadouts:UpdateSpecID()
                TalentLoadouts:InitializeDropdown()
                TalentLoadouts:InitializeButtons()
                TalentLoadouts:InitializeHooks()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            TalentLoadouts:InitializeCharacterDB()
            TalentLoadouts:SaveCurrentLoadouts()
            TalentLoadouts:UpdateDataObj(ITLAPI:GetCurrentLoadout())
        elseif event == "TRAIT_CONFIG_UPDATED" then
            TalentLoadouts:UpdateConfig(arg1)
            TalentLoadouts.pendingLoadout = nil
        elseif event == "TRAIT_CONFIG_CREATED" then
            TalentLoadouts:UpdateConfig(arg1.ID)
        elseif event == "UPDATE_MACROS" then
            TalentLoadouts:UpdateMacros()
        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
            TalentLoadouts:UpdateSpecID(true)
            TalentLoadouts:UpdateDropdownText()
            TalentLoadouts:UpdateSpecButtons()
            TalentLoadouts:UpdateDataObj()
        elseif event == "TRAIT_TREE_CURRENCY_INFO_UPDATED" then
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
    dropdownFont:SetFont(GameFontNormal:GetFont(), ImprovedTalentLoadoutsDB.fontSize, "")
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
        ImprovedTalentLoadoutsDB.loadouts.characterLoadouts[playerName] = {
            firstLoad = true
        }
    end

    if not ImprovedTalentLoadoutsDB.actionbars.macros.char[playerName] then
        ImprovedTalentLoadoutsDB.actionbars.macros.char[playerName] = {}
    end

    ImprovedTalentLoadoutsDB.actionbars.macros.global = ImprovedTalentLoadoutsDB.actionbars.macros.global or {}
    self.charDB = ImprovedTalentLoadoutsDB.loadouts.characterLoadouts[playerName]
    self.globalDB = ImprovedTalentLoadoutsDB.loadouts.globalLoadouts[UnitClassBase("player")]
    self.charMacros = ImprovedTalentLoadoutsDB.actionbars.macros.char[playerName]
    self.globalMacros = ImprovedTalentLoadoutsDB.actionbars.macros.global
    self.specID = PlayerUtil.GetCurrentSpecID()
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
end

function TalentLoadouts:CheckForDBUpdates()
    if ImprovedTalentLoadoutsDB.applyLoadout == nil then
        ImprovedTalentLoadoutsDB.applyLoadout = true
    end

    if ImprovedTalentLoadoutsDB.showSpecButtons == nil then
        ImprovedTalentLoadoutsDB.showSpecButtons = true
    end

    ImprovedTalentLoadoutsDB.fontSize = ImprovedTalentLoadoutsDB.fontSize or 10
end


function TalentLoadouts:CheckForVersionUpdates()
    local currentVersion = ImprovedTalentLoadoutsDB.version
    ImprovedTalentLoadoutsDB.version = internalVersion
end

function TalentLoadouts:UpdateSpecID(isRespec)
    self.specID = PlayerUtil.GetCurrentSpecID()
    self.treeID = ClassTalentFrame.TalentsTab:GetTalentTreeID()

    if isRespec then
        self.charDB.lastLoadout = nil
    end
end

local function CreateEntryInfoFromString(exportString, treeID)
    local importStream = ExportUtil.MakeImportDataStream(exportString)
    local _ = ClassTalentFrame.TalentsTab:ReadLoadoutHeader(importStream)
    local loadoutContent = ClassTalentFrame.TalentsTab:ReadLoadoutContent(importStream, treeID)
    local success, loadoutEntryInfo = pcall(ClassTalentFrame.TalentsTab.ConvertToImportLoadoutEntryInfo, ClassTalentFrame.TalentsTab, treeID, loadoutContent)

    if success then
        return loadoutEntryInfo
    end
end

local function CreateExportString(configInfo, configID, specID, skipEntryInfo)
    local treeID = (configInfo and configInfo.treeIDs[1]) or ClassTalentFrame.TalentsTab:GetTreeInfo().ID
    local treeHash = C_Traits.GetTreeHash(treeID);
    local serializationVersion = C_Traits.GetLoadoutSerializationVersion()
    local dataStream = ExportUtil.MakeExportDataStream()

    ClassTalentFrame.TalentsTab:WriteLoadoutHeader(dataStream, serializationVersion, specID, treeHash)
    ClassTalentFrame.TalentsTab:WriteLoadoutContent(dataStream , configID, treeID)

    local exportString = dataStream:GetExportString()

    local loadoutEntryInfo
    if not skipEntryInfo then
        loadoutEntryInfo = CreateEntryInfoFromString(exportString, treeID)
    end

    return exportString, loadoutEntryInfo, treeHash
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
        EventUtil.ContinueOnAddOnLoaded("Blizzard_ClassTalentUI", GenerateClosure(self.UpdateConfig, self, configID));
        UIParentLoadAddOn("Blizzard_ClassTalentUI")
        self.loaded = true
        return
    end

    local currentSpecID = self.specID
    local configInfo = self.globalDB.configIDs[currentSpecID][configID]
    if configInfo then
        local newConfigInfo = C_Traits.GetConfigInfo(configID)
        configInfo.exportString, configInfo.entryInfo = CreateExportString(configInfo, configID, currentSpecID)
        configInfo.name = newConfigInfo and newConfigInfo.name or configInfo.name
        configInfo.usesSharedActionBars = newConfigInfo.usesSharedActionBars
    else
        self:SaveLoadout(configID, currentSpecID)
    end
end

function TalentLoadouts:SaveLoadout(configID, currentSpecID)
    local specLoadouts = self.globalDB.configIDs[currentSpecID]
    local configInfo = C_Traits.GetConfigInfo(configID)
    if configInfo.type == 1 then
        configInfo.default = configID == C_ClassTalents.GetActiveConfigID() or nil
        specLoadouts[configID] = configInfo
        self:InitializeTalentLoadout(configID)
    end
end

function TalentLoadouts:GetExportStringForTree(skipEntryInfo)
    return CreateExportString(nil, C_ClassTalents.GetActiveConfigID(), self.specID, skipEntryInfo)
end

function TalentLoadouts:SaveCurrentLoadouts()
    if not self.globalDB or not self.charDB then
        self:CheckDBIntegrity()
    end

    local firstLoad = self.charDB.firstLoad
    if self.charDB.firstLoad then
        for specIndex=1, GetNumSpecializations() do
            local specID = GetSpecializationInfo(specIndex)
            self.globalDB.configIDs[specID] = self.globalDB.configIDs[specID] or {}

            local specLoadouts = self.globalDB.configIDs[specID]
            local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)

            for _, configID in ipairs(configIDs) do
                specLoadouts[configID] = specLoadouts[configID] or C_Traits.GetConfigInfo(configID)
                firstLoad = false
            end
        end
    end

    self.charDB.firstLoad = firstLoad
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

local function LoadLoadout(self, configInfo)
    local currentSpecID = TalentLoadouts.specID
    local configID = configInfo.ID
    if C_Traits.GetConfigInfo(configID) then
        C_ClassTalents.LoadConfig(configID, true)
        C_ClassTalents.UpdateLastSelectedSavedConfigID(currentSpecID, configID)
        TalentLoadouts.charDB.lastLoadout = configInfo.ID
        TalentLoadouts:UpdateDropdownText()
        TalentLoadouts:UpdateDataObj(configInfo)

        if configInfo.actionBars then
            TalentLoadouts:LoadActionBar(configInfo.actionBars)
        end
        return
    end

    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    local treeID = configInfo.treeIDs[1]

    if configInfo.currencyID then
        securecallfunction(C_Traits.ResetTreeByCurrency, activeConfigID, treeID, configInfo.currencyID)
    else
        C_Traits.ResetTree(activeConfigID, treeID)
    end

    table.sort(configInfo.entryInfo, function(a, b)
        local nodeA = C_Traits.GetNodeInfo(activeConfigID, a.nodeID)
        local nodeB = C_Traits.GetNodeInfo(activeConfigID, b.nodeID)

        return nodeA.posY < nodeB.posY or (nodeA.posY == nodeB.posY and nodeA.posX < nodeB.posX)
    end)


    for i=1, #configInfo.entryInfo do
        local entry = configInfo.entryInfo[i]
        local nodeInfo = C_Traits.GetNodeInfo(activeConfigID, entry.nodeID)
        if nodeInfo.canPurchaseRank and nodeInfo.isAvailable and nodeInfo.isVisible then
            C_Traits.SetSelection(activeConfigID, entry.nodeID, entry.selectionEntryID)
            if C_Traits.CanPurchaseRank(activeConfigID, entry.nodeID, entry.selectionEntryID) then
                for rank=1, entry.ranksPurchased do
                    C_Traits.PurchaseRank(activeConfigID, entry.nodeID)
                end
            end
        end
    end

    if ImprovedTalentLoadoutsDB.applyLoadout then
        local canChange, _, changeError = C_ClassTalents.CanChangeTalents()
        if canChange then
            TalentLoadouts.pendingLoadout = nil
            C_ClassTalents.SaveConfig(configInfo.ID)
            C_ClassTalents.CommitConfig(configInfo.ID)
            TalentLoadouts.charDB.lastLoadout = configInfo.ID
            TalentLoadouts:UpdateDropdownText()
            TalentLoadouts:UpdateDataObj(configInfo)
            C_ClassTalents.UpdateLastSelectedSavedConfigID(currentSpecID, nil)
            ClassTalentFrame.TalentsTab.LoadoutDropDown:ClearSelection()

            if configInfo.actionBars then
                TalentLoadouts:LoadActionBar(configInfo.actionBars)
            end
        else
            TalentLoadouts:Print("|cffff0000Can't load Loadout.|r", changeError)
        end
    else
        TalentLoadouts.currentLoadout = TalentLoadouts.charDB.lastLoadout
        TalentLoadouts.charDB.lastLoadout = configInfo.ID
        TalentLoadouts:UpdateDropdownText()
        TalentLoadouts:UpdateDataObj(configInfo)
        TalentLoadouts.pendingLoadout = configInfo
        --RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED")
    end

    LibDD:CloseDropDownMenus()
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
       TalentLoadouts:ImportCategory(importString)
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

function TalentLoadouts:ImportCategory(importString)
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

    if categories[data.key] then 
        self:Print("A category with this key already exists. You will be able to rename the category in the next update")
        return 
    else
        categories[data.key] = {
            key = data.key,
            name = data.name,
            loadouts = {}
        }

        for _, configInfo in ipairs(data) do
            local configID = TalentLoadouts:ImportLoadout(configInfo.exportString, configInfo.name, data.key)
            tinsert(categories[data.key].loadouts, configID)
        end
    end
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

local function ExportCategory(self, categoryInfo)
    if categoryInfo then
        local export = {name = categoryInfo.name, key = categoryInfo.key}
        local currentSpecID = TalentLoadouts.specID
        for _, configID in ipairs(categoryInfo.loadouts) do
            local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
            if configInfo then
                tinsert(export, {name = configInfo.name, exportString = configInfo.exportString})
            end
        end

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
    dialog.data = categoryInfo
end

function TalentLoadouts:RenameCategory(categoryInfo, newCategoryName)
    if categoryInfo and #newCategoryName > 0 then
        categoryInfo.name = newCategoryName
    end
end

StaticPopupDialogs["TALENTLOADOUTS_CATEGORY_DELETE"] = {
    text = "Are you sure you want to delete the category?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, categoryInfo)
        TalentLoadouts:DeleteCategory(categoryInfo)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
 }

local function DeleteCategory(self, categoryInfo)
    local dialog = StaticPopup_Show("TALENTLOADOUTS_CATEGORY_DELETE", categoryInfo.name)
    dialog.data = categoryInfo
end

function TalentLoadouts:DeleteCategory(categoryInfo)
    if categoryInfo then
        local currentSpecID = self.specID
        for _, configInfo in pairs(self.globalDB.configIDs[currentSpecID]) do
            if configInfo.category == categoryInfo.key then
                configInfo.category = nil
            end
        end

        self.globalDB.categories[currentSpecID][categoryInfo.key] = nil
    end
end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_SAVE"] = {
    text = "Loadout Name",
    button1 = "Save",
    button2 = "Cancel",
    OnAccept = function(self, saveType)
        local loadoutName = self.editBox:GetText()
        if saveType == 1 then
            TalentLoadouts:SaveCurrentLoadout(loadoutName)
        elseif saveType == 2 then
            TalentLoadouts:SaveCurrentClassTree(loadoutName)
        elseif saveType == 3 then
            TalentLoadouts:SaveCurrentSpecTree(loadoutName)
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

 local function SaveCurrentLoadout()
    local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_SAVE")
    dialog.data = 1
 end

 local function SaveCurrentClassTree()
    local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_SAVE")
    dialog.data = 2
 end

 local function SaveCurrentSpecTree()
    local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_SAVE")
    dialog.data = 3
 end

 function TalentLoadouts:SaveCurrentLoadout(loadoutName, currencyID)
    local currentSpecID = self.specID
    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    local fakeConfigID = FindFreeConfigID()
    if not fakeConfigID then return end

    self.globalDB.configIDs[currentSpecID][fakeConfigID] = C_Traits.GetConfigInfo(activeConfigID)
    self.globalDB.configIDs[currentSpecID][fakeConfigID].fake = true
    self.globalDB.configIDs[currentSpecID][fakeConfigID].name = loadoutName
    self.globalDB.configIDs[currentSpecID][fakeConfigID].ID = fakeConfigID
    self.globalDB.configIDs[currentSpecID][fakeConfigID].currencyID = currencyID
    self.globalDB.configIDs[currentSpecID][fakeConfigID].categories = {}
    self:InitializeTalentLoadout(fakeConfigID)

    if currencyID then
        self.charDB.lastClassLoadout = fakeConfigID
    else
        self.charDB.lastLoadout = fakeConfigID
    end
    TalentLoadouts:UpdateDropdownText()
    TalentLoadouts:UpdateDataObj(self.globalDB.configIDs[currentSpecID][fakeConfigID])
 end

 function TalentLoadouts:SaveCurrentClassTree(loadoutName)
    local currencyInfoClass, currencyInfoSpec = unpack(ClassTalentFrame.TalentsTab.treeCurrencyInfo)
    if currencyInfoClass then
        loadoutName = string.format("[C] %s", loadoutName)
        local configID = C_ClassTalents.GetActiveConfigID()
        C_Traits.ResetTreeByCurrency(configID, self.treeID, currencyInfoSpec.traitCurrencyID)
        self:SaveCurrentLoadout(loadoutName, currencyInfoClass.traitCurrencyID)
        C_Traits.RollbackConfig(configID) 
        securecallfunction(ClassTalentFrame.TalentsTab.UpdateTreeCurrencyInfo, ClassTalentFrame.TalentsTab)
    end
 end

 function TalentLoadouts:SaveCurrentSpecTree(loadoutName)
    local currencyInfoClass, currencyInfoSpec = unpack(ClassTalentFrame.TalentsTab.treeCurrencyInfo)
    if currencyInfoClass then
        loadoutName = string.format("[S] %s", loadoutName)
        local configID = C_ClassTalents.GetActiveConfigID()
        C_Traits.ResetTreeByCurrency(configID, self.treeID, currencyInfoClass.traitCurrencyID)
        self:SaveCurrentLoadout(loadoutName, currencyInfoSpec.traitCurrencyID)
        C_Traits.RollbackConfig(configID) 
        securecallfunction(ClassTalentFrame.TalentsTab.UpdateTreeCurrencyInfo, ClassTalentFrame.TalentsTab)
    end
 end

 local function UpdateWithCurrentTree(self, configID)
    if configID then
        local currentSpecID = TalentLoadouts.specID
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
        if configInfo then
            local activeConfigID = C_ClassTalents.GetActiveConfigID()
            local exportString, entryInfo = CreateExportString(configInfo, activeConfigID, currentSpecID)
            
            configInfo.exportString = exportString
            configInfo.entryInfo = entryInfo
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
    OnAccept = function(self, configID)
       local newName = self.editBox:GetText()
       TalentLoadouts:RenameLoadout(configID, newName)
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
    local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_RENAME")
    dialog.data = configID
end

function TalentLoadouts:RenameLoadout(configID, newLoadoutName)
    local currentSpecID = self.specID
    local configInfo = self.globalDB.configIDs[currentSpecID][configID]
    if configInfo then
        configInfo.name = newLoadoutName
    end

    LibDD:CloseDropDownMenus()
    self:UpdateDropdownText()
    self:UpdateDataObj(configInfo)
end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_IMPORT_STRING"] = {
    text = "Loadout Import String",
    button1 = "Import",
    button2 = "Cancel",
    OnAccept = function(self)
       local importString = self.editBox:GetText()
       local dialog = StaticPopup_Show("TALENTLOADOUTS_LOADOUT_IMPORT_NAME")
       dialog.data = importString
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

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_IMPORT_NAME"] = {
    text = "Loadout Import Name",
    button1 = "Import",
    button2 = "Cancel",
    OnAccept = function(self, importString)
       local loadoutName = self.editBox:GetText()
       TalentLoadouts:ImportLoadout(importString, loadoutName)
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

local function ImportCustomLoadout()
    StaticPopup_Show("TALENTLOADOUTS_LOADOUT_IMPORT_STRING")
end

function TalentLoadouts:ImportLoadout(importString, loadoutName, category)
    local currentSpecID = self.specID
    local fakeConfigID = FindFreeConfigID()
    if not fakeConfigID then return end

    local treeID = ClassTalentFrame.TalentsTab:GetTreeInfo().ID
    local entryInfo = CreateEntryInfoFromString(importString, treeID)

    if entryInfo then
        self.globalDB.configIDs[currentSpecID][fakeConfigID] = {
            ID = fakeConfigID,
            fake = true,
            type = 1,
            treeIDs = {treeID},
            name = loadoutName,
            exportString = importString,
            entryInfo = entryInfo,
            usesSharedActionBars = true,
            categories = category and {[category] = true} or {},
        }
    else
        self:Print("Invalid import string.")
    end

    return fakeConfigID
end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_EXPORT"] = {
    text = "Loadout Import Name",
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

function TalentLoadouts:UpdateActionBars(configInfo)
    configInfo.actionBars = configInfo.actionBars or {}
    local actionBars = {}

    for actionSlot = 1, NUM_ACTIONBAR_BUTTONS do
        local actionType, id, actionSubType = GetActionInfo(actionSlot)
        if actionType then
            local key, macroType
            if actionType == "macro" then
                local name, _, body = GetMacroInfo(id)
                if name and body then
                    body = strtrim(body:gsub("\r", ""))
                    key = string.format("%s\031%s", name, body)
                    macroType = id > MAX_ACCOUNT_MACROS and "characterMacros" or "globalMacros"
                end
            end

            actionBars[actionSlot] = {
                type = actionType,
                id = id,
                subType = actionSubType,
                key = key,
                macroType = macroType
            }
        end
    end

    local serialized = LibSerialize:Serialize(actionBars)
    local compressed = LibDeflate:CompressDeflate(serialized)
    configInfo.actionBars = compressed
end

local function LoadActionBar(self, configID)
    local currentSpecID = TalentLoadouts.specID
    local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
    if configInfo and configInfo.actionBars then
        TalentLoadouts:LoadActionBar(configInfo.actionBars)
    end
end

function TalentLoadouts:LoadActionBar(actionBars)
    if not actionBars then return end

    local decompressed = LibDeflate:DecompressDeflate(actionBars)
    if not decompressed then return end
    local success, data = LibSerialize:Deserialize(decompressed)
    if not success then return end

    for actionSlot = 1, NUM_ACTIONBAR_BUTTONS do
        local slotInfo = data[actionSlot]
        local currentType, currentID, currentSubType = GetActionInfo(actionSlot)
        if slotInfo and (currentType ~= slotInfo.type or currentID ~= slotInfo.id or currentSubType ~= slotInfo.subType) then
            ClearCursor()
            if slotInfo.type == "spell" then
                PickupSpell(slotInfo.id)
            elseif slotInfo.type == "macro" then
                if slotInfo.macroType and self[slotInfo.macroType] then
                    local id = self[slotInfo.macroType][slotInfo.key]
                    if id then
                        PickupMacro(id)
                    end
                else
                    PickupMacro(slotInfo.id)
                end
            elseif slotInfo.type == "item" then
                PickupItem(slotInfo.id)
            end
            PlaceAction(actionSlot)
            ClearCursor()
        end
    end    
end

local function AddToCategory(self, categoryInfo)
    local configInfo = TalentLoadouts.globalDB.configIDs[TalentLoadouts.specID][L_UIDROPDOWNMENU_MENU_VALUE]

    if configInfo and categoryInfo then
        configInfo.categories = configInfo.categories or {}
        configInfo.categories[categoryInfo.key] = true
        tInsertUnique(categoryInfo.loadouts, L_UIDROPDOWNMENU_MENU_VALUE)
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

local loadoutFunctions = {
    updateTree = {
        name = "Update Tree",
        notCheckable = true,
        func = UpdateWithCurrentTree,
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
        name = "Remove from this category",
        func = RemoveFromSpecificCategory,
        notCheckable = true,
        level = 3,
    }
}

local categoryFunctions = {
    delete = {
        name = "Delete",
        func = DeleteCategory,
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
    local currentSpecID = TalentLoadouts.specID
    if level == 1 then
        TalentLoadouts.globalDB.categories[currentSpecID] = TalentLoadouts.globalDB.categories[currentSpecID] or {}
        for categoryKey, categoryInfo in pairs(TalentLoadouts.globalDB.categories[currentSpecID]) do
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

        for configID, configInfo  in pairs(TalentLoadouts.globalDB.configIDs[currentSpecID]) do
            if not configInfo.default and (not configInfo.categories or not next(configInfo.categories)) then
                local color = configInfo.fake and "|cFF33ff96" or "|cFFFFD100"
                LibDD:UIDropDownMenu_AddButton(
                    {
                        arg1 = configInfo,
                        value = configID,
                        colorCode = color,
                        text = configInfo.name,
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

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Options",
                notCheckable = 1,
                hasArrow = true,
                fontObject = dropdownFont,
                minWidth = 170,
                menuList = "options"
            }
        )

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Create Loadout from current Tree",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = SaveCurrentLoadout,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Import Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCustomLoadout,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Create Category",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = CreateCategory,
            }
        )

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Import Category",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCategory,
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
    elseif menu == "options" then
        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Automatically apply Loadout",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.applyLoadout = not ImprovedTalentLoadoutsDB.applyLoadout
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.applyLoadout
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Add Loadouts to /simc",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.simc = not ImprovedTalentLoadoutsDB.simc
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.simc
                end
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Show Spec Buttons",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.showSpecButtons = not ImprovedTalentLoadoutsDB.showSpecButtons
                    TalentLoadouts:UpdateSpecButtons()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.showSpecButtons
                end 
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Font Size",
                notCheckable = 1,
                minWidth = 170,
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "fontSize"
            },
        level)
    elseif menu == "fontSize" then
        local fontSizes = {10, 11, 12, 13, 14, 15, 16, 18, 20}
        for _, fontSize in ipairs(fontSizes) do
            LibDD:UIDropDownMenu_AddButton(
                {
                    text = fontSize,
                    fontObject = dropdownFont,
                    func = function()
                        ImprovedTalentLoadoutsDB.fontSize = fontSize
                        TalentLoadouts:UpdateDropdownFont()
                        LibDD.CloseDropDownMenus()
                    end,
                    checked = function()
                        return ImprovedTalentLoadoutsDB.fontSize == fontSize
                    end
                },
            level)
        end
    elseif menu == "loadout" then
        local functions = {"addToCategory", "removeFromCategory", "updateTree", "updateActionbars", "removeActionbars", "loadActionbars", "rename", "delete", "export"}
        local configID, categoryInfo = L_UIDROPDOWNMENU_MENU_VALUE
        if type(L_UIDROPDOWNMENU_MENU_VALUE) == "table" then
            configID, categoryInfo = unpack(L_UIDROPDOWNMENU_MENU_VALUE)
        end
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]

        for _, func in ipairs(functions) do
            local info = loadoutFunctions[func]
            if (not info.required or configInfo[info.required]) and (not info.level or level == info.level) then
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
            for _, configID in ipairs(categoryInfo.loadouts) do
                local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
                if configInfo and not configInfo.default then
                    local color = configInfo.fake and "|cFF33ff96" or "|cFFFFD100"
                    LibDD:UIDropDownMenu_AddButton(
                        {
                            arg1 = configInfo,
                            value = {configID, categoryInfo},
                            colorCode = color,
                            text = configInfo.name,
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
                value = L_UIDROPDOWNMENU_MENU_VALUE,
                text = "Category Options",
                hasArrow = true,
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                menuList = "categoryOptions"
            },
        level)
    elseif menu == "categoryOptions" then
        local functions = {"rename", "delete", "export"}
        for _, func in ipairs(functions) do
            local info = categoryFunctions[func]
            LibDD:UIDropDownMenu_AddButton(
            {
                arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                notCheckable = info.notCheckable and 1 or nil,
                tooltipTitle = info.tooltipTitle,
                tooltipOnButton = info.tooltipText and 1 or nil,
                tooltipText = info.tooltipText,
                text = info.name,
                isNotRadio = true,
                fontObject = dropdownFont,
                func = info.func,
                checked = info.checked,
                minWidth = 150,
            },
            level)
        end
    elseif menu == "addToCategory" then
        for _, categoryInfo in pairs(TalentLoadouts.globalDB.categories[currentSpecID]) do
            LibDD:UIDropDownMenu_AddButton(
                    {
                        arg1 = categoryInfo,
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
end

function TalentLoadouts:UpdateDropdownText()
    local currentSpecID = self.specID
    local dropdownText = ""

    local configInfo = self.charDB.lastLoadout and self.globalDB.configIDs[currentSpecID][self.charDB.lastLoadout]
    dropdownText = configInfo and configInfo.name or "Unknown"
    LibDD:UIDropDownMenu_SetText(self.dropdown, dropdownText)
end

function TalentLoadouts:UpdateDropdownFont()
    dropdownFont:SetFont(GameFontNormal:GetFont(), ImprovedTalentLoadoutsDB.fontSize or 10, "")
end

function TalentLoadouts:InitializeHooks()
    ClassTalentFrame:HookScript("OnShow", function()
        if ClassTalentFrame.inspectUnit then
            local specID = GetInspectSpecialization(ClassTalentFrame.inspectUnit)
            if not specID or specID ~= self.specID then
                self.dropdown:Hide()
                self.saveButton:Hide()
            end

            for _, specButton in ipairs(self.specButtons) do
                specButton:Hide()
            end
            self.hidden = true
        elseif self.hidden then
            self.dropdown:Show()
            self.saveButton:Show()
            for _, specButton in ipairs(self.specButtons) do
                specButton:Show()
            end

            self.hidden = nil
        end
    end)

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
        if not ImprovedTalentLoadoutsDB.simc then return end

        local customLoadouts
        for _, v in ITLAPI.EnumerateSpecLoadouts() do
           if not v.default then
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
    local dropdown = LibDD:Create_UIDropDownMenu("TestDropdownMenu", ClassTalentFrame.TalentsTab)
    self.dropdown = dropdown
    dropdown:SetPoint("LEFT", ClassTalentFrame.TalentsTab.SearchBox, "RIGHT", 0, -1)
    
    LibDD:UIDropDownMenu_SetAnchor(dropdown, 0, 16, "BOTTOM", dropdown.Middle, "CENTER")
    LibDD:UIDropDownMenu_Initialize(dropdown, LoadoutDropdownInitialize)
    LibDD:UIDropDownMenu_SetWidth(dropdown, 170)
    self:UpdateDropdownText()
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
    --saveButton:Disable()
    saveButton.enabled = false

    saveButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(saveButton, "ANCHOR_TOP")
        GameTooltip:AddLine("Update the active loadout with the current tree.")
        GameTooltip:AddLine("The button will only work while you're holding down SHIFT")
        GameTooltip:Show()
    end)
    
    saveButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    saveButton:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            UpdateWithCurrentTree(nil, TalentLoadouts.charDB.lastLoadout)
        end
    end)

    self.specButtons = {}
    local numSpecializations = GetNumSpecializations()
    local width = 318 / numSpecializations
    for specIndex=1, numSpecializations do
        local specName = select(2, GetSpecializationInfo(specIndex))
        local specButton = CreateFrame("Button", nil, self.dropdown, "UIPanelButtonNoTooltipTemplate, UIButtonTemplate")
        self.specButtons[specIndex] = specButton
        specButton.specIndex = specIndex
        specButton:SetNormalAtlas("charactercreate-customize-dropdownbox")
        specButton:SetScript("OnClick", function(self)
            if self.specIndex ~= GetSpecialization() then
                SetSpecialization(specIndex)
            end
        end)
        specButton:RegisterForClicks("LeftButtonDown")

        if #specName > ceil(width/10) then
            specButton:SetText(specName:sub(1, ceil(width/11)) .. "...")
        else
            specButton:SetText(specName)
        end

        specButton:SetPoint("LEFT", ClassTalentFrame.TalentsTab.ResetButton , "RIGHT", (specIndex-1) * (width + 1), -2)
        specButton:SetSize(width, 30)
        
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

function TalentLoadouts:UpdateSpecButtons()
    if not ImprovedTalentLoadoutsDB.showSpecButtons then
        for specIndex, specButton in ipairs(self.specButtons) do
            specButton:Hide()
        end
        return
    end

    for specIndex, specButton in ipairs(self.specButtons) do
        specButton:Show()
        if specIndex == GetSpecialization() then
            specButton:GetNormalTexture():SetVertexColor(0, 1, 0)
        else
            specButton:GetNormalTexture():SetVertexColor(1, 1, 1)
        end
    end
end

function TalentLoadouts:Print(...)
    print("|cff33ff96[TalentLoadouts]|r", ...)
end

function TalentLoadouts:UpdateMacros()
    if not self.initialized then return end

    local globalMacros = self.globalMacros
    local charMacros = self.charMacros

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

            globalMacros[key] = macroSlot
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

            charMacros[key] = macroSlot
        elseif charMacros[macroSlot] then
            charMacros[charMacros[macroSlot].key] = nil
            charMacros[macroSlot] = nil
        end
    end
end