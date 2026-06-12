local ACF = ACF

do -- Update checker
    hook.Add("ACF_OnLoadAddon", "ACF Custom Update Checker", function()
        ACF.AddRepository("TeeMeeFe", "ACF-3-Custom")

        hook.Remove("ACF_OnLoadAddon", "ACF Custom Update Checker")
    end)
end

print("ACF Custom loaded successfully!")