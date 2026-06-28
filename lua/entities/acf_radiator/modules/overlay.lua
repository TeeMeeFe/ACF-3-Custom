--local ACF = ACF
--local Round = math.Round

function ENT:ACF_UpdateOverlayState(State)
    if self:CanConsume() then
        State:AddSuccess("Active")
    else
        State:AddWarning("Idle")
    end

    if self.IsLeaking and self.Leaking > 0 then
        State:AddWarning("WARNING: Leaking!")
    end

    --local FuelTypeID = self.FuelType
    --local FuelType   = Classes.FuelTypes.Get(FuelTypeID)

    State:AddKeyValue("Fluid Type", "50% Glycerol, 50% Water")
    -- Unit conversion on the temperature, from Degrees Kelvin to Celcius
    State:AddKeyValue("Temperature", ("%s°C"):format(self.Temperature - 273.15))

    --if FuelType and FuelType.FuelTankOverlay then
    --	FuelType.FuelTankOverlay(self.Amount, State)
    --else
        --local FuelAmount   = math.Round(self.Amount, 2)
        --local FuelCapacity = math.Round(self.Capacity, 2)

        --State:AddProgressBar("Remaining Fuel", FuelAmount, FuelCapacity, " L")
    --end
end