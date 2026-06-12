local ACF = ACF

if SERVER then return end -- Silence wench

function CreateMenu(Menu)

end

ACF.AddMenuItem(299, "#acf.menu.entities", "Custom Engines", "car", CreateMenu)