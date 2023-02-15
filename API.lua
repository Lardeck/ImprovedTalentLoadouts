local addonName, TalentLoadouts = ...

ITLAPI = {}
function ITLAPI:EnumerateSpecLoadouts()
   if not TalentLoadouts.initialized then return end
   
   local last
   return function()
        local k,v = next(TalentLoadouts.globalDB.configIDs[TalentLoadouts.specID], last)
        last = k
        if k then
            return k, v
        end
   end
end

function ITLAPI:GetCurrentLoadout()
    local configID = TalentLoadouts.charDB.lastLoadout
    if configID then
        local configInfo = TalentLoadouts.globalDB.configIDs[TalentLoadouts.specID][configID]
        return configInfo
    end
end

function ITLAPI:GetExportStringForCurrentTree()
    return TalentLoadouts:GetExportStringForTree()
end