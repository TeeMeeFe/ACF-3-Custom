local Round = math.Round

ENT.OverlayDelay = 0.1

function ENT:ACF_UpdateOverlayState(State)
    State:AddHeader(self.Name, 2)
    if self.State == "Active" then
        State:AddSuccess(self.State)
    else
        State:AddWarning(self.State)
    end
    State:AddKeyValue("Type", ACF.Classes.GetTypeByName(self.EngineClass).Name)
    -- Unit conversion on bore and stroke, from Centimeters to Millimeters
    State:AddKeyValue("Bore", ("%s mm"):format(self.Bore * 10))
    State:AddKeyValue("Stroke", ("%s mm"):format(self.Stroke * 10))
    State:AddKeyValue("Compression Ratio", ("%s:1"):format(Round(self.CompressionRatio, 1)))
    State:AddKeyValue("Power", ("%s kW / %s hp @%s RPM"):format(Round(self.PeakPower.InKW), Round(self.PeakPower.InHP), Round(self.PeakPower.AtRPM)))
    State:AddKeyValue("Torque", ("%s Nm / %s ft-lb @%s RPM"):format(Round(self.PeakTorque.InNm), Round(self.PeakTorque.InFtLb), Round(self.PeakTorque.AtRPM)))
    -- Unit conversion on the temperature, from Degrees Kelvin to Celcius
    State:AddKeyValue("Temperature", ("Water: %s°C / Oil: %s°C"):format(Round(self.Temperature.Coolant, 1) - 273.15, Round(self.Temperature.Oil, 1) - 273.15))
    State:AddKeyValue("Powerband", ("%s - %s RPM  Δ%s RPM"):format(Round(self.PowerBand.Min), Round(self.PowerBand.Max), Round(self.PowerBand.Band)))
    State:AddKeyValue("Redline", ("%s RPM"):format(Round(self.RedlineRPM)))
end