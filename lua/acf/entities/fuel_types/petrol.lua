ACF.Classes.DefineClass("ACF.CustomFuelTypes.Petrol", "ACF.CustomFuelTypes.FuelType", function()
    CLASS.Name         = "Petrol Fuel"
    CLASS.ShortName    = "Petrol"
    CLASS.ID           = "Petrol"
    CLASS.Density      = 0.755   -- kg/L
    CLASS.IgnitionType = "spark" -- ignition through sparkplugs
    CLASS.Efficiency   = 0.304   -- kg/kWh BSFC
    CLASS.Stoich_AFR   = 14.7    -- Stoichiometric Air Fuel Ratio
end)