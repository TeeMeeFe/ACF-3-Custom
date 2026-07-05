local ACF = ACF

local ENTITY         = FindMetaTable("Entity")
local PHYSOBJ		 = FindMetaTable("PhysObj")

local IsEntityValid	 = ACF.Optimizations.IsEntityValid

local Clock          = ACF.Utilities.Clock
local TickInterval   = engine.TickInterval

function ENT:Think()
    local SelfTbl = ENTITY.GetTable(self)

    if not SelfTbl.Active then return end
    if SelfTbl.Disabled then return end

    self:CalcTemp(SelfTbl)

    -- CalcTemp can turn the engine off or disable it (e.g. no fuel or legality issues)
    if not SelfTbl.Active or SelfTbl.Disabled then return end

    self:NextThink(CurTime() + TickInterval())

    return true
end

function ENT:CalcTemp(SelfTbl)
    -- Reusing these entity table pointers helps us cut down on __index calls
    -- This helps to massively improve performance throughout the entire drivetrain
    SelfTbl = SelfTbl or ENTITY.GetTable(self)

end