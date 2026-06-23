ACF.Classes.DefineClass("ACF.FuelTypes.CustomDiesel", "ACF.FuelTypes.FuelType", function()
    CLASS.Name         = "Diesel Fuel"
    CLASS.ShortName    = "Diesel"
    CLASS.Density      = 0.745  -- kg/L
    CLASS.IgnitionType = "glow" -- Ignition through compression; glow plugs required for cold start
    CLASS.Efficiency   = 0.243  -- kg/kWh (up to 0.274 at best efficiency)
    CLASS.Stoich_AFR   = 14.5   -- Stoichiometric Air Fuel Ratio
    CLASS.IsExplosive  = false  -- Ignition is done by compression instead 
end)
