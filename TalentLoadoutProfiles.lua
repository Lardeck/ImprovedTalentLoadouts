local addonName, TalentLoadouts = ...

local talentUI = "Blizzard_ClassTalentUI"
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local internalVersion = 1

local default = {
    configIDs = {},
    name = "Default",
    profileType = "char",
    key = "default",
}

do
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_CREATED")
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
                self.ID = nil
            end
            self:UnregisterEvent("UNIT_SPELLCAST_STOP")
        end
    end)
end

local function GetPlayerName()
    local name, realm = UnitName("player"), GetNormalizedRealmName()
    return name .. "-" .. realm
end

function TalentLoadouts:Initialize()
    TalentLoadoutProfilesDB = TalentLoadoutProfilesDB or {
        globalLoadouts = {},
        characterLoadouts = {},
    }

    if not TalentLoadoutProfilesDB.classesInitialized then
        local classes = {"HUNTER", "WARLOCK", "PRIEST", "PALADIN", "MAGE", "ROGUE", "DRUID", "SHAMAN", "WARRIOR", "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER"}
        for i, className in ipairs(classes) do
            TalentLoadoutProfilesDB.globalLoadouts[className] = {configIDs = {}, profiles = {}}
        end

        TalentLoadoutProfilesDB.classesInitialized = true
    end
end

function TalentLoadouts:InitializeCharacterDB()
    local playerName = GetPlayerName()
    if not TalentLoadoutProfilesDB.characterLoadouts[playerName] then
        TalentLoadoutProfilesDB.characterLoadouts[playerName] = {
            profiles = {}, 
            mapping = {}, 
            currentProfile = "default",
            currentProfileType = "char",
            firstLoad = true
        }
    end

    self.charDB = TalentLoadoutProfilesDB.characterLoadouts[playerName]
    self.globalDB = TalentLoadoutProfilesDB.globalLoadouts[UnitClassBase("player")]

    self:CheckForVersionUpdates()
end

function TalentLoadouts:CheckForVersionUpdates()
    if not TalentLoadoutProfilesDB.version then
        TalentLoadoutProfilesDB.version = internalVersion
        self.charDB.specDefaults = {}

        for specIndex=1, GetNumSpecializations() do
            local specID = GetSpecializationInfo(specIndex)
            self.charDB.specDefaults[specID] = {profileKey = "default", profileType = "char"}
        end
    end
end

local function CreateExportString(configInfo, configID, specID)
    local treeID = configInfo.treeIDs[1]
    local treeHash = C_Traits.GetTreeHash(treeID);
    local serializationVersion = C_Traits.GetLoadoutSerializationVersion()
    local dataStream = ExportUtil.MakeExportDataStream()
    ClassTalentFrame.TalentsTab:WriteLoadoutHeader(dataStream, serializationVersion, specID, treeHash)
    ClassTalentFrame.TalentsTab:WriteLoadoutContent(dataStream , configID, treeID)

    local exportString = dataStream:GetExportString()
    local importStream = ExportUtil.MakeImportDataStream(exportString)
    local _ = ClassTalentFrame.TalentsTab:ReadLoadoutHeader(importStream)
    local loadoutContent = ClassTalentFrame.TalentsTab:ReadLoadoutContent(importStream, treeID)
    local loadoutEntryInfo = ClassTalentFrame.TalentsTab:ConvertToImportLoadoutEntryInfo(treeID, loadoutContent)

    return exportString, loadoutEntryInfo
end

function TalentLoadouts:InitializeTalentLoadouts()
    local specConfigIDs = self.globalDB.configIDs
    for specID, configIDs in pairs(specConfigIDs) do
        for configID, configInfo in pairs(configIDs) do
            if not configInfo.exportString then
                configInfo.exportString, configInfo.entryInfo = CreateExportString(configInfo, configID, specID)
            end
        end
    end
end

function TalentLoadouts:UpdateConfig(configID)
    local oldConfigID = self.charDB.mapping[configID] or configID

    local currentSpecID = PlayerUtil.GetCurrentSpecID()
    local configInfo = self.globalDB.configIDs[currentSpecID][oldConfigID]
    if configInfo then
        configInfo.exportString, configInfo.entryInfo = CreateExportString(configInfo, configID, currentSpecID)
    end
end

function TalentLoadouts:SaveCurrentLoadoutsForCurrentSpec(profileTbl)
    local currentSpecID = PlayerUtil.GetCurrentSpecID()
    local specLoadouts = self.globalDB.configIDs[currentSpecID]
    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(currentSpecID)

    profileTbl.configIDs = {}
    for _, configID in ipairs(configIDs) do
        configID = self.charDB.mapping[configID] or configID
        specLoadouts[configID] = specLoadouts[configID] or C_Traits.GetConfigInfo(configID)
        profileTbl.configIDs[configID] = true
    end
end

function TalentLoadouts:SaveCurrentLoadouts()
    local firstLoad = self.charDB.firstLoad

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

            if self.charDB.firstLoad then
                firstLoad = false

                self.charDB.profiles[specID].default.configIDs[configID] = true
            end
        end
        self.charDB.firstLoad = firstLoad
    end

    local currentSpecID = PlayerUtil.GetCurrentSpecID()
    local activeConfigID = C_ClassTalents.GetActiveConfigID()
    self.globalDB.configIDs[currentSpecID][activeConfigID] = self.globalDB.configIDs[currentSpecID][activeConfigID] or C_Traits.GetConfigInfo(activeConfigID)
    self.globalDB.configIDs[currentSpecID][activeConfigID].default = true
end

function TalentLoadouts:UpdateQueue(newConfigID)
    local oldConfigID = select(3, unpack(table.remove(self.activeQueue, 1)))

    if oldConfigID then
        self.charDB.mapping[oldConfigID] = newConfigID
        self.charDB.mapping[newConfigID] = oldConfigID

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
    C_ClassTalents.ImportLoadout(configID, loadoutEntryInfo, name, true)
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

    local currentSpecID = PlayerUtil.GetCurrentSpecID()
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
    local currentSpecID = PlayerUtil.GetCurrentSpecID()
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
    local currentSpecID = PlayerUtil.GetCurrentSpecID()
    local globalConfigDB = TalentLoadouts.globalDB.configIDs[currentSpecID]
    local queue = {}
    for configID in pairs(profileTbl.configIDs) do
        local configInfo = globalConfigDB[configID]
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

local function ToggleProfileGlobal(self, profileTbl, ...)
    local key = profileTbl.key
    local currentSpecID = PlayerUtil.GetCurrentSpecID()

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
    if profileTbl.key == "default" then
        TalentLoadouts:Print("You can't delete the default profile.")
        return
    end

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

local function LoadSpecificLoadout(...)
end

local function ExportProfile()
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
    delete = {
        name = "Delete",
        func = DeleteProfile,
        notCheckable = true,
        skipFor = {default = true}
    },
    rename = {
        name = "Rename",
        func = RenameProfile,
        notCheckable = true,
    },
    copy = {
        name = "Copy current Loadouts",
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
        local currentSpecID = PlayerUtil.GetCurrentSpecID()
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
                text = "Close",
                minWidth = 170,
                notCheckable = 1,
                func = LibDD.CloseDropDownMenus,
                menuList = "profile"
            },
        level)
    elseif menu == "profile" then
        local functions = {"global", "loadouts", "copy", "rename", "delete", "export"}
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

function TalentLoadouts:UpdateDropdownText()
    local currentSpecID = PlayerUtil.GetCurrentSpecID()
    local profileName
    if self.charDB.currentProfileType == "global" then
        local db = self.globalDB.profiles[currentSpecID][self.charDB.currentProfile]
        profileName = db and db.name or "MIA"
    else
        local db = self.charDB.profiles[currentSpecID][self.charDB.currentProfile]
        profileName = db and db.name or "MIA"
    end
    LibDD:UIDropDownMenu_SetText(self.dropdown, profileName)
end

function TalentLoadouts:InitializeDropdown()
    local dropdown = LibDD:Create_UIDropDownMenu("TestDropdownMenu", ClassTalentFrame.TalentsTab)
    self.dropdown = dropdown
    dropdown:SetPoint("LEFT", ClassTalentFrame.TalentsTab.SearchBox, "RIGHT", 0, -1)
    
    LibDD:UIDropDownMenu_SetAnchor(dropdown, 0, 16, "BOTTOM", dropdown.Middle, "CENTER")
    LibDD:UIDropDownMenu_Initialize(dropdown, ProfileDropdownInitialize)
    LibDD:UIDropDownMenu_SetWidth(dropdown, 170)
    self:UpdateDropdownText()
end

function TalentLoadouts:Print(...)
    print("|cff33ff96[TalentLoadouts]|r", ...)
end
