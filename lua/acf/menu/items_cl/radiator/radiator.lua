local ACF = ACF
local Classes = ACF.Classes

local function CreateMenu(Menu)
    -- Set the tool's operations 
    ACF.SetClientData("PrimaryClass", "acf_radiator")
    ACF.SetClientData("SecondaryClass", "N/A")

    ACF.SetToolMode("acf_menu", "Spawner", "acf_radiator")

    Menu:AddTitle("Radiator Settings")
    Menu:AddLabel("Allows you to efficiently cool down and stabilize an engine's temperature.")

    local RadiatorClass = Classes.GetTypeByName("acf_radiator")
    local TypeSelector  = Classes.CreateTypeSelector(Menu, RadiatorClass, "RadiatorType")
    local ClassList     = TypeSelector.ComboBox

    -- Ideally the rest of the menus would go here or in the base radiator class.
    -- Biggest problem i'm currently facing with this menu code is carrying-fetching data around.
    -- In this file i can know which class was selected, but i cannot fetch the class' field data. 
    -- (I don't know the field method to fetch them nor what argument value/type they take)
    -- Instead if the menu gets built in the selected class, i get access to the class' fields to build
    -- the menu but i cannot figure out a pattern to fetch whose class was selected from this menu panel.
    -- Not even doing the datavar below does the trick and methinks the order and realm of when things 
    -- happen and where, those don't exactly match for my usecase.
    -- So instead i'm taking the dumb, redundant course here and build a menu for every class...
    -- TLDR: This menu sucks r/bigdickproblems and needs to be rewritten. 
    if ClassList and ClassList.Selected then
        local TypeName = ACF.Classes.GetTypeName(ClassList.Selected)
        ACF.SetClientData("RadiatorType", TypeName)
    end

    function TypeSelector.OnTypeChanged(TypeObj)
        local TypeName = ACF.Classes.GetTypeName(TypeObj)
        ACF.SetClientData("RadiatorType", TypeName)
    end
end

ACF.AddMenuItem(298, "#acf.menu.entities", "Radiators", "water", CreateMenu)