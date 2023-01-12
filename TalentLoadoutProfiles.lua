local addonName, TalentLoadouts = ...

local talentUI = "Blizzard_ClassTalentUI"
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")
local internalVersion = 4
local NUM_ACTIONBAR_BUTTONS = 15 * 12

local default = {
    configIDs = {},
    name = "Basic",
    profileType = "char",
    key = "default",
}

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

do
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_CREATED")
    eventFrame:RegisterEvent("UPDATE_MACROS")
    eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 == addonName then
                TalentLoadouts:Initialize()
            elseif arg1 == talentUI then
                self:UnregisterEvent("ADDON_LOADED")
                TalentLoadouts:InitializeTalentLoadouts()
                TalentLoadouts:InitializeDropdown()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            TalentLoadouts:InitializeCharacterDB()
            TalentLoadouts:SaveCurrentLoadouts()
        elseif event == "TRAIT_CONFIG_UPDATED" and not TalentLoadouts.activeQueue then
            TalentLoadouts:UpdateConfig(arg1)
        elseif event == "TRAIT_CONFIG_CREATED" then
            if UnitCastingInfo("player") then
                self.ID = arg1.ID
                self:RegisterEvent("UNIT_SPELLCAST_STOP")
                return
            end

            if TalentLoadouts.activeQueue then
                TalentLoadouts:UpdateQueue(arg1.ID)
            else
                TalentLoadouts:UpdateConfig(arg1.ID)
            end
        elseif event == "UNIT_SPELLCAST_STOP" and arg1 == "player" then
            if TalentLoadouts.activeQueue then
                TalentLoadouts:UpdateQueue(self.ID)
                C_ClassTalents.LoadConfig(self.ID, true)
                self.ID = nil
            end
            self:UnregisterEvent("UNIT_SPELLCAST_STOP")
        elseif event == "UPDATE_MACROS" then
            TalentLoadouts:UpdateMacros()
        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
            TalentLoadouts:UpdateSpecID()
            TalentLoadouts:UpdateDropdownText()
        end
    end)
end

local function GetPlayerName()
    local name, realm = UnitName("player"), GetNormalizedRealmName()
    return name .. "-" .. realm
end

function TalentLoadouts:Initialize()
    TalentLoadoutProfilesDB = TalentLoadoutProfilesDB or defaultDB
    self:CheckForDBUpdates()

    if not TalentLoadoutProfilesDB.classesInitialized then
        local classes = {"HUNTER", "WARLOCK", "PRIEST", "PALADIN", "MAGE", "ROGUE", "DRUID", "SHAMAN", "WARRIOR", "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER"}
        for i, className in ipairs(classes) do
            TalentLoadoutProfilesDB.loadouts.globalLoadouts[className] = {configIDs = {}, profiles = {}, categories = {}}
        end

        TalentLoadoutProfilesDB.classesInitialized = true
    end
end

function TalentLoadouts:InitializeCharacterDB()
    local playerName = GetPlayerName()
    if not TalentLoadoutProfilesDB.loadouts.characterLoadouts[playerName] then
        TalentLoadoutProfilesDB.loadouts.characterLoadouts[playerName] = {
            profiles = {}, 
            mapping = {},
            currentProfile = "default",
            currentProfileType = "char",
            firstLoad = true
        }
    end

    if not TalentLoadoutProfilesDB.actionbars.macros.char[playerName] then
        TalentLoadoutProfilesDB.actionbars.macros.char[playerName] = {}
    end

    self.charDB = TalentLoadoutProfilesDB.loadouts.characterLoadouts[playerName]
    self.globalDB = TalentLoadoutProfilesDB.loadouts.globalLoadouts[UnitClassBase("player")]
    self.charMacros = TalentLoadoutProfilesDB.actionbars.macros.char[playerName]
    self.globalMacros = TalentLoadoutProfilesDB.actionbars.macros.global
    self.specID = PlayerUtil.GetCurrentSpecID()
    self:CheckForVersionUpdates()
    self.initialized = true
    self:UpdateMacros()
end

function TalentLoadouts:CheckForDBUpdates()
    local currentVersion = TalentLoadoutProfilesDB.version
    if currentVersion == 2 then
        currentVersion = 3
        TalentLoadoutProfilesDB = {
            loadouts = {
                characterLoadouts = TalentLoadoutProfilesDB.characterLoadouts or {},
                globalLoadouts = TalentLoadoutProfilesDB.globalLoadouts or {}
            },
            actionbars = {
                macros = {
                    global = {},
                    char = {},
                }
            },
            mode = "loadout",
            version = currentVersion,
            classesInitialized = TalentLoadoutProfilesDB.classesInitialized
        }
    end

    if currentVersion <= 4 then
        local classes = {"HUNTER", "WARLOCK", "PRIEST", "PALADIN", "MAGE", "ROGUE", "DRUID", "SHAMAN", "WARRIOR", "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER"}
        for i, className in ipairs(classes) do
            TalentLoadoutProfilesDB.loadouts.globalLoadouts[className].categories = TalentLoadoutProfilesDB.loadouts.globalLoadouts[className].categories or {}
        end
    end
end


function TalentLoadouts:CheckForVersionUpdates()
    local currentVersion = TalentLoadoutProfilesDB.version

    if not currentVersion then
        currentVersion = 1

        self.charDB.specDefaults = {}

        for specIndex=1, GetNumSpecializations() do
            local specID = GetSpecializationInfo(specIndex)
            self.charDB.specDefaults[specID] = {profileKey = "default", profileType = "char"}
        end
    end

    if currentVersion == 1 then
        currentVersion = 2
        TalentLoadoutProfilesDB.mode = "loadout"
    end

    if not self.charDB.currentProfiles then
        self.charDB.currentProfiles = {}
        for specIndex=1, GetNumSpecializations() do
            local specID = GetSpecializationInfo(specIndex)
            self.charDB.currentProfiles[specID] = {profileName = self.charDB.currentProfile, profileType = self.charDB.currentProfileType}
        end

        self.charDB.currentProfile = nil
        self.charDB.currentProfileType = nil
    end

    TalentLoadoutProfilesDB.version = internalVersion
end

function TalentLoadouts:UpdateSpecID()
    self.specID = PlayerUtil.GetCurrentSpecID()
    self.charDB.lastLoadout = nil
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
    local treeID = configInfo.treeIDs[1] or ClassTalentFrame.TalentsTab:GetTreeInfo().ID
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

    return exportString, loadoutEntryInfo
end

function TalentLoadouts:InitializeTalentLoadouts()
    local specConfigIDs = self.globalDB.configIDs
    local currentSpecID = self.specID
    for configID, configInfo in pairs(specConfigIDs[currentSpecID]) do
        if configInfo.fake then
            configID = C_ClassTalents.GetActiveConfigID()
        end

        if C_Traits.GetConfigInfo(configID) and (not configInfo.exportString or not configInfo.entryInfo) then
            configInfo.exportString, configInfo.entryInfo = CreateExportString(configInfo, configID, currentSpecID)
        end
    end
end

function TalentLoadouts:UpdateConfig(configID)
    local oldConfigID = self.charDB.mapping[configID] or configID
    local currentSpecID = self.specID
    local configInfo = self.globalDB.configIDs[currentSpecID][oldConfigID]
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
        specLoadouts[configID] = configInfo
        self:InitializeTalentLoadouts()
    end
end

function TalentLoadouts:SaveCurrentLoadoutsForCurrentSpec(profileTbl)
    local currentSpecID = self.specID
    local specLoadouts = self.globalDB.configIDs[currentSpecID]
    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(currentSpecID)

    profileTbl.configIDs = {}
    for _, configID in ipairs(configIDs) do
        configID = self.charDB.mapping[configID] or configID

        local newConfigInfo = C_Traits.GetConfigInfo(configID)
        specLoadouts[configID] = specLoadouts[configID] or newConfigInfo
        profileTbl.configIDs[configID] = true
    end

    self:InitializeTalentLoadouts()
end

function TalentLoadouts:SaveCurrentLoadouts()
    local firstLoad = self.charDB.firstLoad
    if self.charDB.firstLoad then
        for specIndex=1, GetNumSpecializations() do
            local specID = GetSpecializationInfo(specIndex)
            self.globalDB.configIDs[specID] = self.globalDB.configIDs[specID] or {}
            self.globalDB.profiles[specID] = self.globalDB.profiles[specID] or {}
            self.charDB.profiles[specID] = self.charDB.profiles[specID] or {default = default}

            local specLoadouts = self.globalDB.configIDs[specID]
            local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)

            for _, configID in ipairs(configIDs) do
                configID = self.charDB.mapping[configID] or configID
                specLoadouts[configID] = specLoadouts[configID] or C_Traits.GetConfigInfo(configID)
                firstLoad = false

                self.charDB.profiles[specID].default.configIDs[configID] = true
            end
        end
    end

    self.charDB.firstLoad = firstLoad
    local currentSpecID = self.specID
    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    self.globalDB.configIDs[currentSpecID][activeConfigID] = self.globalDB.configIDs[currentSpecID][activeConfigID] or C_Traits.GetConfigInfo(activeConfigID)
    self.globalDB.configIDs[currentSpecID][activeConfigID].default = true
end

function TalentLoadouts:UpdateQueue(newConfigID)
    local oldConfigID = select(3, unpack(table.remove(self.activeQueue, 1)))

    if oldConfigID then
        self.charDB.mapping[oldConfigID] = newConfigID
        self.charDB.mapping[newConfigID] = oldConfigID

        local currentSpecID = self.specID
        C_ClassTalents.SetUsesSharedActionBars(newConfigID, self.globalDB.configIDs[currentSpecID][oldConfigID].usesSharedActionBars)
        self:WorkOffQueue()

        if not self.activeQueue or #self.activeQueue == 0 then
            self.activeQueue = nil
        end
    end
end

function TalentLoadouts:WorkOffQueue()
    if self.activeQueue and #self.activeQueue == 0 then
        return
    end

    local name, loadoutEntryInfo = unpack(self.activeQueue[1])

    local configID = ClassTalentFrame.TalentsTab:GetConfigID()
    C_ClassTalents.ImportLoadout(configID, loadoutEntryInfo, name, false)
end

StaticPopupDialogs["TALENTLOADOUTS_PROFILE_CREATE"] = {
   text = "Profile Name (This will create an empty profile)",
   button1 = "Create",
   button2 = "Cancel",
   OnAccept = function(self)
      local profileName = self.editBox:GetText()
      TalentLoadouts:CreateProfile(profileName)
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

StaticPopupDialogs["TALENTLOADOUTS_PROFILE_RENAME"] = {
   text = "New Profile Name",
   button1 = "Rename",
   button2 = "Cancel",
   OnAccept = function(self, profileTbl)
      local newName = self.editBox:GetText()
      TalentLoadouts:RenameProfile(profileTbl, newName)
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

StaticPopupDialogs["TALENTLOADOUTS_PROFILE_DELETE"] = {
    text = "Are you sure you want to delete the profile '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, profileTbl)
        TalentLoadouts:DeleteProfile(profileTbl)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
 }

function TalentLoadouts:CreateProfile(profileName)
    if not profileName or #profileName == 0 or profileName:lower() == "default" then return end

    local currentSpecID = self.specID
    local key = profileName:lower()
    self.charDB.profiles[currentSpecID][key] = {
        name = profileName,
        key = key,
        profileType = "char",
        configIDs = {}
    }
end

function TalentLoadouts:RenameProfile(profileTbl, newName)
    profileTbl.name = newName
    self:UpdateDropdownText()
end

function TalentLoadouts:DeleteProfile(profileTbl)
    local currentSpecID = self.specID
    local db = profileTbl.profileType == "char" and TalentLoadouts.charDB or TalentLoadouts.globalDB
    db.profiles[currentSpecID][profileTbl.key] = nil

    if self.charDB.currentProfile == profileTbl.key then
        TalentLoadouts:UpdateDropdownText()
    end
end

local function ResetCurrentLoadout(currentSpecID)
    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(currentSpecID)

    for _, configID in ipairs(configIDs) do
        C_ClassTalents.DeleteConfig(configID)
    end
end

local function LoadProfile(self, profileName, profileTbl)
    local currentSpecID = TalentLoadouts.specID
    local globalConfigDB = TalentLoadouts.globalDB.configIDs[currentSpecID]
    local queue = {}
    for configID in pairs(profileTbl.configIDs) do
        local oldConfigID = TalentLoadouts.charDB.mapping[configID] or configID
        local configInfo = globalConfigDB[configID] or globalConfigDB[oldConfigID]
        if configInfo then
            tinsert(queue, {configInfo.name, configInfo.entryInfo, configInfo.ID})
        end
    end

    if #queue > 0 then
        ResetCurrentLoadout(currentSpecID)

        TalentLoadouts.activeQueue = queue
        TalentLoadouts.charDB.currentProfile = profileTbl.key
        TalentLoadouts.charDB.currentProfileType = profileTbl.profileType
        TalentLoadouts:UpdateDropdownText()
        TalentLoadouts:WorkOffQueue()
    else
        TalentLoadouts:Print("Can't load an empty profile")
    end
end

local function LoadLoadout(self, configInfo)
    local currentSpecID = TalentLoadouts.specID
    local configID = TalentLoadouts.charDB.mapping[configInfo.ID] or configInfo.ID
    if C_Traits.GetConfigInfo(configID) then
        C_ClassTalents.LoadConfig(configID, true)
        C_ClassTalents.UpdateLastSelectedSavedConfigID(currentSpecID, configID)
        TalentLoadouts.charDB.lastLoadout = configInfo.ID
        TalentLoadouts:UpdateDropdownText()

        if configInfo.actionBars then
            TalentLoadouts:LoadActionBar(configInfo.actionBars)
        end
        return
    end

    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    local treeID = configInfo.treeIDs[1]

    C_Traits.ResetTree(activeConfigID, treeID)
    table.sort(configInfo.entryInfo, function(a, b)
        local nodeA = C_Traits.GetNodeInfo(activeConfigID, a.nodeID)
        local nodeB = C_Traits.GetNodeInfo(activeConfigID, b.nodeID)

        return nodeA.posY < nodeB.posY or (nodeA.posY == nodeB.posY and nodeA.posX < nodeB.posX)
    end)


    for i=1, #configInfo.entryInfo do
        local entry = configInfo.entryInfo[i]
        C_Traits.SetSelection(activeConfigID, entry.nodeID, entry.selectionEntryID)
        if C_Traits.CanPurchaseRank(activeConfigID, entry.nodeID, entry.selectionEntryID) then
            for rank=1, entry.ranksPurchased do
                C_Traits.PurchaseRank(activeConfigID, entry.nodeID)
            end
        end
    end

    local canChange, _, changeError = C_ClassTalents.CanChangeTalents()
    if canChange then
        C_ClassTalents.SaveConfig(configInfo.ID)
        C_ClassTalents.CommitConfig(configInfo.ID)
        TalentLoadouts.charDB.lastLoadout = configInfo.ID
        TalentLoadouts:UpdateDropdownText()
        C_ClassTalents.UpdateLastSelectedSavedConfigID(currentSpecID, nil)
        ClassTalentFrame.TalentsTab.LoadoutDropDown:ClearSelection()

        if configInfo.actionBars then
            TalentLoadouts:LoadActionBar(configInfo.actionBars)
        end
    else
        TalentLoadouts:Print("|cffff0000Can't load Loadout.|r", changeError)
        C_Traits.RollbackConfig(activeConfigID)
    end

    LibDD:CloseDropDownMenus()
end

local function ToggleProfileGlobal(self, profileTbl, ...)
    local key = profileTbl.key
    local currentSpecID = TalentLoadouts.specID

    if profileTbl.profileType == "char" then
        TalentLoadouts.globalDB.profiles[currentSpecID][key] = profileTbl
        TalentLoadouts.charDB.profiles[currentSpecID][key] = nil
        TalentLoadouts.charDB.currentProfileType = "global"
        profileTbl.profileType = "global"
    elseif profileTbl.profileType == "global" then
        TalentLoadouts.charDB.profiles[currentSpecID][key] = profileTbl
        TalentLoadouts.globalDB.profiles[currentSpecID][key] = nil
        TalentLoadouts.charDB.currentProfileType = "char"
        profileTbl.profileType = "char"
    end

    LibDD:CloseDropDownMenus()
end

local function DeleteProfile(self, profileTbl, ...)
    local dialog = StaticPopup_Show("TALENTLOADOUTS_PROFILE_DELETE", profileTbl.name)
    dialog.data = profileTbl
end

local function RenameProfile(self, arg1, ...)
    local dialog = StaticPopup_Show("TALENTLOADOUTS_PROFILE_RENAME")
    dialog.data = arg1
end

local function CopyCurrentLoadouts(self, profileTbl, ...)
    TalentLoadouts:SaveCurrentLoadoutsForCurrentSpec(profileTbl)
end

local function UpdateDefaultProfile(self, profileTbl)
end

local function LoadSpecificLoadout()
end

local function ExportProfile(self, profileTbl)
end

local profileFunctions = {
    loadouts = {
        name = "Load specific Loadout (NYI)",
        func = LoadSpecificLoadout,
        notCheckable = true,
        hasArrow = true,
        menuList = "loadouts",
    },
    global = {
        name = "Global",
        func = ToggleProfileGlobal,
        skipFor = {default = true}
    },
    default = {
        name = "Default (NYI)",
        func = UpdateDefaultProfile,
    },
    delete = {
        name = "Delete",
        func = DeleteProfile,
        notCheckable = true,
    },
    rename = {
        name = "Rename",
        func = RenameProfile,
        notCheckable = true,
    },
    copy = {
        name = "Save current Loadouts",
        func = CopyCurrentLoadouts,
        notCheckable = true,
    },
    export = {
        name = "Export (NYI)",
        func = ExportProfile,
        notCheckable = true
    }
}

local function ProfileDropdownInitialize(frame, level, menu, ...)
    if level == 1 then
        local currentSpecID = TalentLoadouts.specID
        for profile, profileTbl  in pairs(TalentLoadouts.globalDB.profiles[currentSpecID]) do
            LibDD:UIDropDownMenu_AddButton(
                {
                    colorCode = "|cFF33ff96",
                    arg1 = profile,
                    arg2 = profileTbl,
                    text = profileTbl.name,
                    hasArrow = true,
                    minWidth = 170,
                    value = profileTbl,
                    func = LoadProfile,
                    checked = function()
                        return TalentLoadouts.charDB.currentProfile == profile
                    end,
                    menuList = "profile"
                },
            level)
        end

        for profile, profileTbl  in pairs(TalentLoadouts.charDB.profiles[currentSpecID]) do
            LibDD:UIDropDownMenu_AddButton(
                {
                    colorCode = "|cFFFFD100",
                    arg1 = profile,
                    arg2 = profileTbl,
                    text = profileTbl.name,
                    hasArrow = true,
                    minWidth = 170,
                    value = profileTbl,
                    func = LoadProfile,
                    checked = function()
                        return TalentLoadouts.charDB.currentProfile == profile
                    end,
                    menuList = "profile"
                },
            level)
        end

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Create Profile",
                minWidth = 170,
                notCheckable = 1,
                func = function(...)
                    StaticPopup_Show("TALENTLOADOUTS_PROFILE_CREATE")
                end,
                menuList = "profile"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Import Profile (NYI)",
                minWidth = 170,
                notCheckable = 1,
                func = function(...)
                end,
                menuList = "profile"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Switch to Loadout Mode",
                minWidth = 170,
                tooltipTitle = "Loadout Mode",
                tooltipText = "This mode displays all saved loadouts for your current spec.",
                tooltipOnButton = 1,
                notCheckable = 1,
                func = function()
                    TalentLoadouts:SwitchToLoadoutMode()
                end,
                menuList = "profile"
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Close",
                minWidth = 170,
                notCheckable = 1,
                func = LibDD.CloseDropDownMenus,
                menuList = "profile"
            },
        level)
    elseif menu == "profile" then
        local functions = {"global", "default", "loadouts", "copy", "rename", "delete", "export"}
        for _, func in ipairs(functions) do
            local info = profileFunctions[func]
            if not info.skipFor or (L_UIDROPDOWNMENU_MENU_VALUE and not info.skipFor[L_UIDROPDOWNMENU_MENU_VALUE.key]) then
                LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                    value = L_UIDROPDOWNMENU_MENU_VALUE,
                    notCheckable = info.notCheckable and 1 or nil,
                    checked = not info.notCheckable and function(self)
                        return type(L_UIDROPDOWNMENU_MENU_VALUE) == "table" and L_UIDROPDOWNMENU_MENU_VALUE.profileType == "global"
                    end,
                    menuList = info.menuList,
                    hasArrow = info.hasArrow,
                    isNotRadio = true,
                    text = info.name,
                    func = info.func,
                    minWidth = 150,
                },
                level)
            end
        end
    end
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
    OnAccept = function(self)
       local loadoutName = self.editBox:GetText()
       TalentLoadouts:SaveCurrentLoadout(loadoutName)
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
    StaticPopup_Show("TALENTLOADOUTS_LOADOUT_SAVE")
 end

 function TalentLoadouts:SaveCurrentLoadout(loadoutName)
    local currentSpecID = self.specID
    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    local fakeConfigID = #self.globalDB.configIDs[currentSpecID] + 1

    self.globalDB.configIDs[currentSpecID][fakeConfigID] = C_Traits.GetConfigInfo(activeConfigID)
    self.globalDB.configIDs[currentSpecID][fakeConfigID].fake = true
    self.globalDB.configIDs[currentSpecID][fakeConfigID].name = loadoutName
    self.globalDB.configIDs[currentSpecID][fakeConfigID].ID = fakeConfigID
    self:InitializeTalentLoadouts()

    self.charDB.lastLoadout = fakeConfigID
    TalentLoadouts:UpdateDropdownText()
 end

 local function UpdateWithCurrentTree(self, configID)
    local currentSpecID = TalentLoadouts.specID
    local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
    if configInfo then
        local activeConfigID = C_ClassTalents.GetActiveConfigID()
        local exportString, entryInfo = CreateExportString(configInfo, activeConfigID, currentSpecID)
        
        configInfo.exportString = exportString
        configInfo.entryInfo = entryInfo
    end
 end

StaticPopupDialogs["TALENTLOADOUTS_LOADOUT_DELETE"] = {
    text = "Are you sure you want to delete the loadout? |cffff0000The loadout will also be deleted from any profile|r",
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

    if configInfo.category then
        tDeleteItem(self.globalDB.categories[currentSpecID][configInfo.category].loadouts, configID)
    end

    LibDD:CloseDropDownMenus()
    self:UpdateDropdownText()
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

function TalentLoadouts:ImportLoadout(importString, loadoutName)
    local currentSpecID = self.specID
    local fakeConfigID = #self.globalDB.configIDs[currentSpecID] + 1
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
        }
    else
        self:Print("Invalid import string.")
    end
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
            actionBars[actionSlot] = {
                type = actionType,
                id = id,
                subType = actionSubType
            }
        end
    end

    local serialized = LibSerialize:Serialize(actionBars)
    local compressed = LibDeflate:CompressDeflate(serialized)
    configInfo.actionBars = compressed
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
                PickupMacro(slotInfo.id)
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
        configInfo.category = categoryInfo.key
        tInsertUnique(categoryInfo.loadouts, L_UIDROPDOWNMENU_MENU_VALUE)
    end
end

local loadoutFunctions = {
    addToProfile = {
        name = "Add to Profile (NYI)",
        notCheckable = true,
        hasArrow = true,
        menuList = "addProfile"
    },
    updateTree = {
        name = "Save Tree",
        tooltipTitle = "Disclaimer",
        notCheckable = true,
        func = UpdateWithCurrentTree,
        tooltipText = "If you're updating a Blizzard Loadout (yellow ones) then the changes will not take effect on Blizzard's end until you re-import the profile."
    },
    updateActionbars = {
        name = "Save Action Bars",
        notCheckable = true,
        func = UpdateActionBars,
    },
    removeActionbars = {
        name = "Remove Action Bars",
        notCheckable = true,
        func = RemoveActionBars,
        required = "actionBars"
    },
    delete = {
        name = "Delete",
        tooltipTitle = "Disclaimer",
        tooltipText = "This will also delete the Loadout from all profiles.",
        func = DeleteLoadout,
        notCheckable = true,
        skipFor = {default = true}
    },
    rename = {
        name = "Rename",
        tooltipTitle = "Disclaimer",
        tooltipText = "If you're updating a Blizzard Loadout (yellow ones) then the changes will not take effect on Blizzard's end until you re-import the profile.",
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
        name = "Export (NYI)",
        tooltipTitle = "Export",
        tooltipText = "Export all loadouts associated with this category at once.",
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
                        notCheckable = 1,
                        menuList = "category"
                    },
            level)
        end

        for configID, configInfo  in pairs(TalentLoadouts.globalDB.configIDs[currentSpecID]) do
            if not configInfo.default and not configInfo.category then
                local color = configInfo.fake and "|cFF33ff96" or "|cFFFFD100"
                LibDD:UIDropDownMenu_AddButton(
                    {
                        arg1 = configInfo,
                        value = configID,
                        colorCode = color,
                        text = configInfo.name,
                        hasArrow = true,
                        minWidth = 170,
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
                text = "Create Loadout from current Tree",
                minWidth = 170,
                notCheckable = 1,
                func = SaveCurrentLoadout,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Import Loadout",
                minWidth = 170,
                notCheckable = 1,
                func = ImportCustomLoadout,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Create Category",
                minWidth = 170,
                notCheckable = 1,
                func = CreateCategory,
            }
        )

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Switch to Profile Mode",
                minWidth = 170,
                notCheckable = 1,
                func = function()
                    TalentLoadouts:SwitchToProfileMode()
                end,
            },
        level)

        LibDD:UIDropDownMenu_AddButton(
            {
                text = "Close",
                minWidth = 170,
                notCheckable = 1,
                func = LibDD.CloseDropDownMenus,
            },
        level)
    elseif menu == "loadout" then
        local functions = {"addToCategory", "updateTree", "updateActionbars", "removeActionbars", "rename", "delete", "export"}
        local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][L_UIDROPDOWNMENU_MENU_VALUE]

        for _, func in ipairs(functions) do
            local info = loadoutFunctions[func]
            if not info.required or configInfo[info.required] then
                LibDD:UIDropDownMenu_AddButton(
                {
                    arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                    value = L_UIDROPDOWNMENU_MENU_VALUE,
                    notCheckable = info.notCheckable and 1 or nil,
                    tooltipTitle = info.tooltipTitle,
                    tooltipOnButton = info.tooltipText and 1 or nil,
                    tooltipText = info.tooltipText,
                    text = info.name,
                    isNotRadio = true,
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
        LibDD:UIDropDownMenu_AddButton(
            {
                value = L_UIDROPDOWNMENU_MENU_VALUE,
                text = "Options",
                hasArrow = true,
                minWidth = 170,
                notCheckable = 1,
                menuList = "categoryOptions"
            },
        level)

        local categoryInfo = TalentLoadouts.globalDB.categories[currentSpecID][L_UIDROPDOWNMENU_MENU_VALUE.key]
        if categoryInfo then
            for _, configID in ipairs(categoryInfo.loadouts) do
                local configInfo = TalentLoadouts.globalDB.configIDs[currentSpecID][configID]
                if configInfo and not configInfo.default then
                    local color = configInfo.fake and "|cFF33ff96" or "|cFFFFD100"
                    LibDD:UIDropDownMenu_AddButton(
                        {
                            arg1 = configInfo,
                            value = configID,
                            colorCode = color,
                            text = configInfo.name,
                            minWidth = 170,
                            hasArrow = true,
                            func = LoadLoadout,
                            checked = function()
                                return TalentLoadouts.charDB.lastLoadout and TalentLoadouts.charDB.lastLoadout == configID
                            end,
                            menuList = "loadout"
                        },
                    level)
                end
            end
        end
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
                func = info.func,
                checked = info.checked,
                minWidth = 150,
            },
            level)
        end
    elseif menu == "addToCategory" then
        for categoryKey, categoryInfo in pairs(TalentLoadouts.globalDB.categories[currentSpecID]) do
            LibDD:UIDropDownMenu_AddButton(
                    {
                        arg1 = categoryInfo,
                        colorCode = "|cFFab96b3",
                        text = categoryInfo.name,
                        minWidth = 170,
                        notCheckable = 1,
                        func = AddToCategory,
                    },
            level)
        end
    end
end

function TalentLoadouts:SwitchToLoadoutMode()
    TalentLoadoutProfilesDB.mode = "loadout"
    LibDD:UIDropDownMenu_SetInitializeFunction(self.dropdown, LoadoutDropdownInitialize)
    self:UpdateDropdownText()
end

function TalentLoadouts:SwitchToProfileMode()
    TalentLoadoutProfilesDB.mode = "profile"
    LibDD:UIDropDownMenu_SetInitializeFunction(self.dropdown, ProfileDropdownInitialize)
    self:UpdateDropdownText()
end

function TalentLoadouts:UpdateDropdownText()
    local currentSpecID = self.specID
    local dropdownText = ""

    if TalentLoadoutProfilesDB.mode == "profile" then
        if self.charDB.currentProfileType == "global" then
            local db = self.globalDB.profiles[currentSpecID][self.charDB.currentProfile]
            dropdownText = db and db.name or "MIA"
        else
            local db = self.charDB.profiles[currentSpecID][self.charDB.currentProfile]
            dropdownText = db and db.name or "MIA"
        end
    elseif TalentLoadoutProfilesDB.mode == "loadout" then
        local configInfo = self.charDB.lastLoadout and self.globalDB.configIDs[currentSpecID][self.charDB.lastLoadout]
        dropdownText = configInfo and configInfo.name or "Unknown"
    end

    LibDD:UIDropDownMenu_SetText(self.dropdown, dropdownText)
end

function TalentLoadouts:InitializeDropdown()
    local dropdown = LibDD:Create_UIDropDownMenu("TestDropdownMenu", ClassTalentFrame.TalentsTab)
    self.dropdown = dropdown
    dropdown:SetPoint("LEFT", ClassTalentFrame.TalentsTab.SearchBox, "RIGHT", 0, -1)
    
    LibDD:UIDropDownMenu_SetAnchor(dropdown, 0, 16, "BOTTOM", dropdown.Middle, "CENTER")

    if TalentLoadoutProfilesDB.mode == "profile" then
        LibDD:UIDropDownMenu_Initialize(dropdown, ProfileDropdownInitialize)
    else
        LibDD:UIDropDownMenu_Initialize(dropdown, LoadoutDropdownInitialize)
    end
    LibDD:UIDropDownMenu_SetWidth(dropdown, 170)
    self:UpdateDropdownText()
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
            globalMacros[macroSlot] = {
                slot = macroSlot,
                body = body,
                name = name,
            }
        end
    end

    for macroSlot = MAX_ACCOUNT_MACROS + 1, (MAX_ACCOUNT_MACROS + MAX_CHARACTER_MACROS) do
        local name, _, body = GetMacroInfo(macroSlot)
        if name then
            body = strtrim(body:gsub("\r", ""))
            charMacros[macroSlot] = {
                slot = macroSlot,
                body = body,
                name = name,
            }
        end
    end
end