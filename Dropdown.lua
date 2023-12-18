local addonName, ITL = ...
local LibDDM = LibStub:GetLibrary("LibUIDropDownMenu-4.0")

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

local function LoadoutDropdownInitialize(_, level, menu, ...)
    local currentSpecID = ITL.specID
    if level == 1 then
        ITL.globalDB.categories[currentSpecID] = ITL.globalDB.categories[currentSpecID] or {}
        ITL.globalDB.configIDs[currentSpecID] = ITL.globalDB.configIDs[currentSpecID] or {}
        ITL:UpdateIterator()

        
        for _, categoryInfo in spairs(ITL.globalDB.categories[currentSpecID], sortByName) do
            if not categoryInfo.isSubCategory then
                LibDDM:UIDropDownMenu_AddButton(
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
                local color = (configInfo.error and "|cFFFF0000") or (configInfo.fake and "|cFF33ff96") or "|cFFFFD100"

                LibDDM:UIDropDownMenu_AddButton(
                    {
                        arg1 = configInfo,
                        value = configID,
                        colorCode = color,
                        text = string.format("%s%s", prefix or configInfo.name, prefix and configInfo.name or ""),
                        hasArrow = true,
                        minWidth = 170,
                        fontObject = dropdownFont,
                        func = LoadLoadout,
                        checked = function()
                            return ITL.charDB.lastLoadout and ITL.charDB.lastLoadout == configID
                        end,
                        menuList = "loadout"
                    },
                level)
            end
        end

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Options",
                notCheckable = 1,
                hasArrow = true,
                fontObject = dropdownFont,
                minWidth = 170,
                menuList = "options"
            }
        )

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Create Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                hasArrow = true,
                notCheckable = 1,
                func = SaveCurrentLoadout,
                menuList = "createLoadout"
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Import Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                hasArrow = true,
                notCheckable = 1,
                func = ImportCustomLoadout,
                menuList = "importLoadout"
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Create Category",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = CreateCategory,
            }
        )

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Import Category",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCategory,
            }
        )

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Close",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = LibDDM.CloseDropDownMenus,
            },
        level)
    elseif menu == "createLoadout" then
        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Create Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = SaveCurrentLoadout,
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Create Loadout + Apply",
                arg1 = true,
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = SaveCurrentLoadout,
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Create Class Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = SaveCurrentClassTree,
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Create Spec Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = SaveCurrentSpecTree,
            },
        level)
    elseif menu == "importLoadout" then
        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Import Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCustomLoadout,
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Import Loadout + Apply",
                arg1 = true,
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCustomLoadout,
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Import Class Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCustomClassLoadout,
            },
        level)
        
        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Import Spec Loadout",
                minWidth = 170,
                fontObject = dropdownFont,
                notCheckable = 1,
                func = ImportCustomSpecLoadout,
            },
        level)

    elseif menu == "options" then
        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Display Category Name",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.showCategoryName = not ImprovedTalentLoadoutsDB.options.showCategoryName
                    ITL:UpdateDropdownText()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.showCategoryName
                end
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Show Spec Buttons",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.showSpecButtons = not ImprovedTalentLoadoutsDB.options.showSpecButtons
                    ITL:UpdateSpecButtons()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.showSpecButtons
                end 
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Sort Loadouts by Name",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.sortLoadoutsByName = not ImprovedTalentLoadoutsDB.options.sortLoadoutsByName
                    ITL:UpdateIterator()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.sortLoadoutsByName
                end
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Loadouts",
                notCheckable = 1,
                minWidth = 170,
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "globalLoadoutOptions"
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Action Bars",
                notCheckable = 1,
                minWidth = 170,
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "actionBarOptions"
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Spec Button Type",
                notCheckable = 1,
                minWidth = 170,
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "specButtonType"
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Font Size",
                notCheckable = 1,
                minWidth = 170,
                fontObject = dropdownFont,
                hasArrow = true,
                menuList = "fontSizeOptions"
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Delete All",
                notCheckable = 1,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ITL:ShowDeleteAll()
                end,
            },
        level)
    elseif menu == "fontSizeOptions" then
        local fontSizes = {10, 11, 12, 13, 14, 15, 16, 18, 20}
        for _, fontSize in ipairs(fontSizes) do
            LibDDM:UIDropDownMenu_AddButton(
                {
                    text = fontSize,
                    fontObject = dropdownFont,
                    func = function()
                        ImprovedTalentLoadoutsDB.options.fontSize = fontSize
                        ITL:UpdateDropdownFont()
                        LibDDM.CloseDropDownMenus()
                    end,
                    checked = function()
                        return ImprovedTalentLoadoutsDB.options.fontSize == fontSize
                    end
                },
            level)
        end
    elseif menu == "actionBarOptions" then
        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Load Action Bars with Loadout",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.loadActionbars = not ImprovedTalentLoadoutsDB.options.loadActionbars
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.loadActionbars
                end
            },
        level)

                LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Load Action Bars with Spec",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.loadActionbarsSpec = not ImprovedTalentLoadoutsDB.options.loadActionbarsSpec
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.loadActionbarsSpec
                end
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Clear Slots when loading Action Bars",
                isNotRadio = true,
                minWidth = 170,
                tooltipTitle = "|cffff0000WARNING! Use this option at your own risk!|r",
                tooltipText = "This will remove an action from a slot if it was empty when you've saved the action bars. It's unclear if this affects the action bars of other specs.",
                tooltipOnButton = 1,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.clearEmptySlots = not ImprovedTalentLoadoutsDB.options.clearEmptySlots
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.clearEmptySlots
                end
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Find Macro By Name",
                isNotRadio = true,
                tooltipTitle = "Description:",
                tooltipText = "Lets the AddOn find saved macros based on their names (instead of name + body).",
                tooltipOnButton = 1,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.findMacroByName = not ImprovedTalentLoadoutsDB.options.findMacroByName
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.findMacroByName
                end
            },
        level)
    elseif menu == "globalLoadoutOptions" then
        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Automatically apply Loadout",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.applyLoadout = not ImprovedTalentLoadoutsDB.options.applyLoadout
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.applyLoadout
                end
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Add Loadouts to /simc",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.simc = not ImprovedTalentLoadoutsDB.options.simc
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.simc
                end
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Load Blizzard Loadouts (yellow)",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                tooltipOnButton = 1,
                tooltipTitle = "Load Blizzard Loadouts",
                tooltipText = "Load the yellow loadouts (if they exists) with the Blizzard API functions and don't handle it as an AddOn loadout. At large this disables the action bar handling of the AddOn for the yellow loadouts.",
                func = function()
                    ImprovedTalentLoadoutsDB.options.loadBlizzard = not ImprovedTalentLoadoutsDB.options.loadBlizzard
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.loadBlizzard
                end 
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Load as Blizzard Loadout",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.loadAsBlizzard = not ImprovedTalentLoadoutsDB.options.loadAsBlizzard
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.loadAsBlizzard
                end
            },
        level)

        LibDDM:UIDropDownMenu_AddButton(
            {
                text = "Fall back to AddOn Loadout",
                isNotRadio = true,
                minWidth = 170,
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.useAddOnLoadoutFallback = not ImprovedTalentLoadoutsDB.options.useAddOnLoadoutFallback
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.useAddOnLoadoutFallback
                end
            },
        level)
    elseif menu == "specButtonType" then
        local buttonTypes = {"text", "icon"}
        local buttonTypesText = {"Text", "Icons"}
        for i, buttonType in ipairs(buttonTypes) do
            LibDDM:UIDropDownMenu_AddButton(
            {
                text = buttonTypesText[i],
                fontObject = dropdownFont,
                func = function()
                    ImprovedTalentLoadoutsDB.options.specButtonType = buttonType
                    ITL:UpdateSpecButtons()
                end,
                checked = function()
                    return ImprovedTalentLoadoutsDB.options.specButtonType == buttonType
                end,
            }
            ,level)
        end
    elseif menu == "loadout" then
        local functions = {"addToCategory", "removeFromCategory", "assignGearset", "assignLayout", "updateTree", "updateWithString", "updateActionbars", "removeActionbars", "loadActionbars", "rename", "delete", "export"}
        local configID, categoryInfo = L_UIDROPDOWNMENU_MENU_VALUE
        if type(L_UIDROPDOWNMENU_MENU_VALUE) == "table" then
            configID, categoryInfo = unpack(L_UIDROPDOWNMENU_MENU_VALUE)
        end
        local configInfo = ITL.globalDB.configIDs[currentSpecID][configID]

        for _, func in ipairs(functions) do
            local info = loadoutFunctions[func]
            if (not info.required or configInfo[info.required]) and (not info.level or level == info.level) then
                LibDDM:UIDropDownMenu_AddButton(
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
        local categoryInfo = ITL.globalDB.categories[currentSpecID][L_UIDROPDOWNMENU_MENU_VALUE.key]
        if categoryInfo then
            if categoryInfo.categories then
                for _, categoryKey in ipairs(categoryInfo.categories) do
                    local categoryInfo = ITL.globalDB.categories[currentSpecID][categoryKey]
                    if categoryInfo and categoryInfo.name then
                        LibDDM:UIDropDownMenu_AddButton(
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

            for _, configID in ipairs(categoryInfo.loadouts) do
                local configInfo = ITL.globalDB.configIDs[currentSpecID][configID]
                if configInfo and not configInfo.default then
                    local color = configInfo.fake and "|cFF33ff96" or "|cFFFFD100"
                    LibDDM:UIDropDownMenu_AddButton(
                        {
                            arg1 = configInfo,
                            arg2 = categoryInfo,
                            value = {configID, categoryInfo},
                            colorCode = color,
                            text = configInfo.name,
                            minWidth = 170,
                            fontObject = dropdownFont,
                            hasArrow = true,
                            func = function(...)
                                LoadLoadout(...)
                                LibDDM:CloseDropDownMenus()
                            end,
                            checked = function()
                                return ITL.charDB.lastLoadout and ITL.charDB.lastLoadout == configID
                            end,
                            menuList = "loadout"
                        },
                    level)
                end
            end
        end

        LibDDM:UIDropDownMenu_AddButton(
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
        local functions = {"addToCategory", "removeFromCategory", "rename", "delete", "deleteWithLoadouts", "export"}
        for _, func in ipairs(functions) do
            local info = categoryFunctions[func]
            if (not info.required or L_UIDROPDOWNMENU_MENU_VALUE[info.required]) then
                LibDDM:UIDropDownMenu_AddButton(
                {
                    value = L_UIDROPDOWNMENU_MENU_VALUE,
                    arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                    arg2 = info.arg2,
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

        for _, categoryInfo in spairs(ITL.globalDB.categories[currentSpecID], 
        function(t, a, b) if t[a] and t[b] and t[a].name and t[b].name then return t[a].name < t[b].name end end) do
            if not isCategory or categoryInfo.key ~= L_UIDROPDOWNMENU_MENU_VALUE.key then
                LibDDM:UIDropDownMenu_AddButton(
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
            local categoryInfo = ITL.globalDB.categories[currentSpecID][categoryKey]
            if categoryInfo then
                LibDDM:UIDropDownMenu_AddButton(
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
        local configInfo = ITL.globalDB.configIDs[currentSpecID][L_UIDROPDOWNMENU_MENU_VALUE]
        if configInfo then
            for _, equipmentSetID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
                local name, icon = C_EquipmentSet.GetEquipmentSetInfo(equipmentSetID)

                LibDDM:UIDropDownMenu_AddButton(
                    {
                        arg1 = L_UIDROPDOWNMENU_MENU_VALUE,
                        text = string.format("|T%d:0|t %s", icon, name),
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
        local configInfo = ITL.globalDB.configIDs[currentSpecID][L_UIDROPDOWNMENU_MENU_VALUE]
        if configInfo then
            local layoutsInfo =  C_EditMode.GetLayouts()
            if not layoutsInfo then return end

            for index, info in ipairs(layoutsInfo.layouts) do
                local layoutIndex = index + 2

                LibDDM:UIDropDownMenu_AddButton(
                    {
                        text = info.layoutName,
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

function ITL:UpdateDropdownText()
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
        LibDDM:UIDropDownMenu_SetText(self.dropdown, dropdownText)
    else
        LibDDM:UIDropDownMenu_SetText(self.dropdown, dropdownText)
    end
end

function ITL:UpdateDropdownFont()
    dropdownFont:SetFont(GameFontNormal:GetFont(), ImprovedTalentLoadoutsDB.options.fontSize or 10, "")
end
