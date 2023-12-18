local addonName, ITL = ...

local function UpdateActionBars(self, configID)
    local currentSpecID = PlayerUtil.GetCurrentSpecID()
    local configInfo = ITL.globalDB.configIDs[currentSpecID][configID]
    if configInfo then
        ITL:UpdateActionBars(configInfo)
    end
end

local function RemoveActionBars(self, configID)
    local currentSpecID = PlayerUtil.GetCurrentSpecID()
    local configInfo = ITL.globalDB.configIDs[currentSpecID][configID]
    if configInfo then
        configInfo.actionBars = nil
    end
end

function ITL:UpdateActionBars(configInfo)
    self:UpdateKnownFlyouts()

    configInfo.actionBars = configInfo.actionBars or {}
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
            elseif actionType == "flyout" then
                id = self.flyouts[id]
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
        configInfo.actionBars = ITL:Compress(actionBars)
    end
end

local function LoadActionBar(self, configID)
    local currentSpecID = PlayerUtil.GetCurrentSpecID()
    local configInfo = ITL.globalDB.configIDs[currentSpecID][configID]
    if configInfo and configInfo.actionBars then
        ITL:LoadActionBar(configInfo.actionBars, configInfo.name)
    end
end

function ITL:LoadActionBar(actionBars, name)
    if not actionBars then return end

    local decompressed = LibDeflate:DecompressDeflate(actionBars)
    if not decompressed then return end
    local success, data = LibSerialize:Deserialize(decompressed)
    if not success then return end

    self:UpdateMacros()

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
                PickupSpell(spellID)
                pickedUp = true
            elseif slotInfo.type == "flyout" then
                PickupSpellBookItem(slotInfo.id, BOOKTYPE_SPELL)
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

function ITL:UpdateMacros()
    if not self.initialized then return end

    self.db.global.macros = {}
    self.db.char.macros = {}
    self.duplicates = {}
    local globalMacros = self.db.global.macros
    local charMacros = self.db.char.macros

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
end

function ITL:UpdateKnownFlyouts()
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