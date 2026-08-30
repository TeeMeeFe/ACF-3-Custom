include("shared.lua")

ENT.DoNotDuplicate = true

-- Invalidate the entity's entry in case this gets destroyed or removed.
function ENT:OnRemove()
    local Engine = self.Engine
    if not IsValid(Engine) then return end

    -- local EntTbl = Engine:GetTable()

    self.Engine = nil
    -- EntTbl:UpdateOverlay()
end

-- Destroy this entity if we try to modify its parent.
function ENT:CFW_PreParentedTo(OldParent, NewParent)
    if not IsValid(OldParent) then return end -- Originally we weren't parented, so ignore that

    if NewParent ~= OldParent then self:Remove() end
end

-- function ENT:ACF_PostSpawn()
--     self.Name = "Starter"
--     self:UpdateOverlay()
-- end

function ENT:UpdateTransmitState()
    return TRANSMIT_PVS
end