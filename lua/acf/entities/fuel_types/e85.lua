ACF.Classes.DefineClass("ACF.CustomFuelTypes.E85", "ACF.CustomFuelTypes.FuelType", function()
    CLASS.Name         = "Ethanol 85 Fuel"
    CLASS.ShortName    = "E85"
    CLASS.ID           = "Petrol"
    CLASS.Density      = 0.785   -- kg/L
    CLASS.IgnitionType = "spark" -- ignition through sparkplugs
    CLASS.Efficiency   = 0.7     -- kg/kWh BSFC, lower energy density than petrol so roughly 30% more fuel by mass is needed
    CLASS.Stoich_AFR   = 9.8     -- Stoichiometric Air Fuel Ratio
end)