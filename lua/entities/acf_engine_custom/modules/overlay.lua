local Round = math.Round

ENT.OverlayDelay = 0.1

function ENT:ACF_UpdateOverlayState(State)
    local TorqueMult = self.GetTorqueMult() -- Janky i know, but i gotta get this to work first.
    local CompressionRatio = Round(self.CompressionRatio, 1)

    local PeakPower  = {InKW = Round(self.PeakPower.InKW) * TorqueMult,
                        InHP = Round(self.PeakPower.InHP) * TorqueMult,
                        AtRPM = Round(self.PeakPower.AtRPM)}

    local PeakTorque = {InNm = Round(self.PeakTorque.InNm) * TorqueMult,
                        InFtLb = Round(self.PeakTorque.InFtLb) * TorqueMult,
                        AtRPM = Round(self.PeakTorque.AtRPM)}

    local PowerBand  = {Min = Round(self.PowerBand.Min),
                        Max = Round(self.PowerBand.Max),
                        Width = Round(self.PowerBand.Band)}

    local RedlineRPM = Round(self.RedlineRPM)

    State:AddHeader(self.Name, 2)
    if self.State == "Active" then
        State:AddSuccess(self.State)
    else
        State:AddWarning(self.State)
    end
    State:AddKeyValue("Type", self.Type)
    -- Unit conversion on bore and stroke, from Centimeters to Millimeters
    State:AddKeyValue("Bore", ("%s mm"):format(self.Bore * 10))
    State:AddKeyValue("Stroke", ("%s mm"):format(self.Stroke * 10))
    State:AddKeyValue("Compression Ratio", ("%s:1"):format(CompressionRatio))
    State:AddKeyValue("Power", ("%s kW / %s hp @%s RPM"):format(PeakPower.InKW, PeakPower.InHP, PeakPower.AtRPM))
    State:AddKeyValue("Torque", ("%s Nm / %s ft-lb @%s RPM"):format(PeakTorque.InNm, PeakTorque.InFtLb, PeakTorque.AtRPM))
    State:AddKeyValue("Powerband", ("%s - %s RPM  Δ%s RPM"):format(PowerBand.Min, PowerBand.Max, PowerBand.Width))
    State:AddKeyValue("Redline", ("%s RPM"):format(RedlineRPM))
end