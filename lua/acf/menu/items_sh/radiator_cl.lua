local ACF     = ACF
local Classes = ACF.Classes
local GetType = Classes.GetTypeByName
local PAGE    = "acf_radiator"

local RADIATOR_BASE = "ACF.Radiators.BaseRadiator"

local function Build(Menu, Context)
    Menu:AddTitle("Radiator Settings")
    Menu:AddLabel("Allows you to efficiently cool down and stabilize an engine's temperature.")

    local Entries = Classes.GetChildren(GetType(RADIATOR_BASE))
    local Radiator = Context.Radiator

    local RadiatorTypeDef = Menu:AddComboBox()
    RadiatorTypeDef:SetName("RadiatorTypeDef")

    local SubPanel = Menu:AddPanel("ACF_Panel")

    function RadiatorTypeDef:OnSelect(Index, _, Data)
        if self.Selected == Data then return end

        self.ListData.Index = Index
        self.Selected = Data

        ACF.Menu.SaveClassCombo(PAGE, "radiator", Data)
        Radiator:Set("RadiatorType", Classes.GetTypeName(Data))

        Menu:ClearTemporal(SubPanel)
        Menu:StartTemporal(SubPanel)

        if Data.CreateMenu then
            -- Equivalently ClassData.CreateMenu(ClassData, ListData, Menu, Base, UseLegacyRatios)
            Data.CreateMenu(SubPanel, Data, Radiator)
        end

        Menu:EndTemporal(SubPanel)
    end

    ACF.Menu.LoadClassCombo(RadiatorTypeDef, Entries, "Name", nil, PAGE, "radiator")
end

ACF.Menu.RegisterPage({
    ID       = "acf_radiator",
    Category = "#acf.menu.entities",
    Name     = "Radiators",
    Icon     = "water",
    Order    = 298,

    Contexts = { Radiator = "acf_radiator" },

    Actions = {
        { Bind = "left", Context = "Radiator", Preview = true, Desc = "Spawn a new radiator, or update the one you're aiming at." },
        { Bind = "right", Commit = "link", Desc = "Select a radiator, then an engine, to link them (hold R to unlink)." },
    },

    Build = Build,
})
