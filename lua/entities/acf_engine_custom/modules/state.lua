local ENTITY = FindMetaTable("Entity")

function ENT:Think()
    local SelfTbl = ENTITY.GetTable(self)

    if not SelfTbl.Active then return end
    if SelfTbl.Disabled then return end

    self:CalcRPM(SelfTbl)

    -- CalcRPM can turn the engine off or disable it (e.g. no fuel or legality issues)
    if not SelfTbl.Active or SelfTbl.Disabled then return end

    self:NextThink(CurTime() + TickInterval())

    return true
end

-- We're doing an experiment here. It seems that the entity table stores the functions for the entity
-- class as well. So we don't need to do self:Function for every entity (which would invoke the __index function)
-- If true then we should apply this in the rest of the hot paths.
function ENT:CalcRPM(SelfTbl)
    -- Reusing these entity table pointers helps us cut down on __index calls
    -- This helps to massively improve performance throughout the entire drivetrain
    SelfTbl = SelfTbl or ENTITY.GetTable(self)

end