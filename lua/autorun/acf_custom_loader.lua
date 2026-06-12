include("includes/gloader.lua")

-- Await till the main addon is loaded first before we go on 
hook.Add("ACF_OnLoadAddon", "ACF Custom Loader", function()
    gloader.Load("ACF-3-Custom", "acf_custom")

    hook.Remove("ACF_OnLoadAddon", "ACF Custom Loader")
end)
