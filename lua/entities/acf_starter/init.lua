include("shared.lua")

ENT.DoNotDuplicate = true
CFW.addParentDetour("acf_engine_custom", "Engine")

-- One can't exist without the other
function ENT:OnRemove()
	if IsValid(self.Engine) then
		self.Engine:Remove()
	end
end

-- This shouldn't be called usually due to parent detouring, but in the offchance that this is ever directly unparented from the turret ring, destroy it and the turret entity since it is no longer a valid turret
function ENT:CFW_OnParented(Entity, Connected)
	if not IsValid(Entity) then return end

	if Connected == false and Entity == self.Engine then self:Remove() end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_PVS
end

-- Invalidate the entity's entry in case this gets destroyed or removed.
-- function ENT:OnRemove()
--     local Engine = self.Engine
--     if not IsValid(Engine) then return end

--     -- local EntTbl = Engine:GetTable()

--     self.Engine = nil
--     -- EntTbl:UpdateOverlay()
-- end

-- -- Destroy this entity if we try to modify its parent.
-- function ENT:CFW_PreParentedTo(OldParent, NewParent)
--     if not IsValid(OldParent) then return end -- Originally we weren't parented, so ignore that

--     if NewParent ~= OldParent then self:Remove() end
-- end

-- function ENT:ACF_PostSpawn()
--     self.Name = "Starter"
--     self:UpdateOverlay()
-- end

-- -- Overlay bullshit
-- function ENT:ACF_UpdateOverlayState(State)
--     if self.State == "Idle" then
--         State:AddSuccess(self.State)
--     else
--         State:AddWarning(self.State)
--     end
-- end