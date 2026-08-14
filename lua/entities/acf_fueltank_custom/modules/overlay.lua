local Round = math.Round

-- Overlay text
function ENT:ACF_UpdateOverlayState(State)
    if self:CanConsume() then
        State:AddSuccess("Active")
    else
        State:AddWarning("Idle")
    end

    if self.Leaking and self.Leaking > 0 then
        State:AddWarning("WARNING: Leaking!")
    end

    -- The V2 fuel type instance lives on the entity's field set; read it straight off.
    local FuelType = self:ACF_GetUserVar("FuelType")

    State:AddKeyValue("Fuel Type", FuelType and FuelType.ID or self.FuelType)

    if FuelType and FuelType.FuelTankOverlay then
        FuelType.FuelTankOverlay(self.Amount, State)
    else
        local FuelAmount   = Round(self.Amount, 2)
        local FuelCapacity = Round(self.Capacity, 2)

        State:AddProgressBar("Remaining Fuel", FuelAmount, FuelCapacity, " L")
    end
end

