ACF.Classes.DefineClass("ACF.FuelTypes.JetFuel", "ACF.FuelTypes.BaseFuelType", function()
    CLASS.Name         = "Jet Fuel"
    CLASS.ShortName    = "JetFuel"
    CLASS.Density      = 0.832  -- kg/L
    CLASS.IgnitionType = "both" -- Technically can use both sparkplugs and glowplugs, as well as being multifuel
    CLASS.Efficiency   = 0.45   -- kg/kWh BSFC at ground level
    CLASS.Stoich_AFR   = 15     -- Stoichiometric Air Fuel Ratio; Kerosene type fuel
    CLASS.IsExplosive  = false  -- Lower volatility makes this a combustible rather than a flammable liquid
end)