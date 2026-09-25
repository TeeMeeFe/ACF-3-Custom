local Round = math.Round

-- Overlay text
function ENT:ACF_UpdateOverlayState(State)
    if self.ACF.Health == 0 then
        State:AddError("Destroyed")
    elseif self:CanConsume() then
        State:AddSuccess("Active")
    elseif self.Amount == 0 then
        State:AddWarning("Idle and Empty")
    else
        State:AddWarning("Idle")
    end

    if self.Leaking and self.Leaking > 0 then
        State:AddWarning("WARNING: Leaking!")
    end
    -- The V2 fuel type and size instances lives on the entity's field set; read them straight off.
    local SizeX = self:ACF_GetUserVar("FuelSizeX")
    local SizeY = self:ACF_GetUserVar("FuelSizeY")
    local SizeZ = self:ACF_GetUserVar("FuelSizeZ")

    State:AddSize("Size", SizeY, SizeX, SizeZ)

    local FuelType = self:ACF_GetUserVar("FuelType")

    State:AddKeyValue("Fuel Type", FuelType and FuelType.ID or self.FuelType)

    if FuelType and FuelType.FuelTankOverlay then
        FuelType.FuelTankOverlay(self.Amount, State)
    else
        local FuelAmount   = Round(self.Amount or 0, 2)
        local FuelCapacity = Round(self.Capacity or 1, 2)

        State:AddProgressBar("Remaining Fuel", FuelAmount, FuelCapacity, " L")
    end
end

