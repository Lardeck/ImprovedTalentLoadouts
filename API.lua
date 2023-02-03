local addonName, TalentLoadouts = ...

TLMAPI = {}
function TLMAPI:EnumerateSpecLoadouts()
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

function TLMAPI:GetCurrentLoadout()
    local configID = TalentLoadouts.charDB.lastLoadout
    if configID then
        local configInfo = TalentLoadouts.globalDB.configIDs[TalentLoadouts.specID][configID]
        return configInfo
    end
end