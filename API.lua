local addonName, TalentLoadouts = ...

PTLAPI = {}
function PTLAPI:EnumerateSpecLoadouts()
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