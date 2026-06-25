do -- Globals
    ACF.SpeedOfSound = 343 -- In Meters Per Second
    ACF.RoomTemperature = 293.15 -- In Degrees Kelvin. This indicates the default temperature inside a safezone, if none defined.
end

do -- Update checker
    hook.Add("ACF_OnLoadAddon", "ACF Custom Update Checker", function()
        ACF.AddRepository("TeeMeeFe", "ACF-3-Custom")

        hook.Remove("ACF_OnLoadAddon", "ACF Custom Update Checker")
    end)
end
