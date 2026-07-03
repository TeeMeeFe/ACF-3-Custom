-- Await for the main module to load first before we try to register our menu operations
timer.Simple(0.1, function ()
    ACF.CreateMenuOperation("Custom Engines", "Custom Engine")
    ACF.CreateMenuOperation("Radiators", "Radiator")
end)
