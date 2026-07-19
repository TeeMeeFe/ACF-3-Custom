local ACF     = ACF
local Classes = ACF.Classes
local GetType = Classes.GetTypeByName

local ENGINE_BLOCK_BASE = "ACF.Engines.BaseEngineBlock"

local function CreateMenu(Menu)
    ACF.SetClientData("PrimaryClass", "N/A")
    ACF.SetClientData("SecondaryClass", "N/A")

    ACF.SetToolMode("acf_menu", "Spawner", "Custom Engine")

    Menu:AddTitle("Custom Engine Settings")
    Menu:AddHelp("Create a custom engine from scratch.")

    -- Engine "classes" are the direct children of the base engine (PistonBlock, TurbineBlock, ElectricBlock);
    -- Their items are the concrete engine types under each.
    local Entries = Classes.GetChildren(GetType(ENGINE_BLOCK_BASE))

    local EngineBlockClass = Menu:AddComboBox()
    EngineBlockClass:SetName("EngineBlockClass")

    ACF.LoadSortedList(EngineBlockClass, Entries, "Name", nil)

    local SubPanel = Menu:AddPanel("ACF_Panel")

    -- Gotta steal functionality from field_menu_cl.lua since we don't use its methods, but the child classes do.
    local SelectedTypeID = nil
    local FieldName = "EngineType" -- Field we looking for 
    local NestedData = {}

    local function PushClientData()
        if not SelectedTypeID then return end
        ACF.SetClientData(FieldName, { Type = SelectedTypeID, Data = NestedData })
    end

    function EngineBlockClass:OnSelect(Index, _, Data)
        if self.Selected == Data then return end

        self.ListData.Index = Index
        self.Selected = Data

        SelectedTypeID = Classes.GetTypeName(Data)
        NestedData = Data

        Menu:ClearTemporal(SubPanel)
        Menu:StartTemporal(SubPanel)

        if Data.CreateMenu then
            -- Equivalently ClassData.CreateMenu(ClassData, ListData, Menu, Base, UseLegacyRatios)
            Data.CreateMenu(SubPanel, Data, PushClientData)
        end

        Menu:EndTemporal(SubPanel)

        PushClientData()
    end
end

ACF.AddMenuItem(299, "#acf.menu.entities", "Custom Engines", "car_add", CreateMenu)