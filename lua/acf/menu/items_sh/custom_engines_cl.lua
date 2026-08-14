local ACF     = ACF
local Classes = ACF.Classes
local GetType = Classes.GetTypeByName
local PAGE    = "acf_engine_custom"

local ENGINE_BLOCK_BASE = "ACF.CustomEngines.BaseEngineBlock"

local function Build(Menu, Contexts)
    Menu:AddTitle("Custom Engine Settings")
    Menu:AddHelp("Create a custom engine from scratch.")

    -- Engine "classes" are the direct children of the base engine (PistonBlock, TurbineBlock, ElectricBlock);
    -- Their items are the concrete engine types under each.
    local Entries  = Classes.GetChildren(GetType(ENGINE_BLOCK_BASE))
    local Engine   = Contexts.Engine
    local Fuel     = Contexts.Fuel
    local TankSize = Vector(Fuel:Get("FuelSizeX") or 24, Fuel:Get("FuelSizeY") or 24, Fuel:Get("FuelSizeZ") or 24)

    local ClassList = Menu:AddComboBox()

    local SubPanel = Menu:AddPanel("ACF_Panel")

    function ClassList:OnSelect(Index, _, Data)
        if self.Selected == Data then return end

        self.ListData.Index = Index
        self.Selected = Data

        ACF.Menu.SaveClassCombo(PAGE, "engine", Data)

        Engine:Set("BlockType", Data)

        Menu:ClearTemporal(SubPanel)
        Menu:StartTemporal(SubPanel)

        local CustomMenu = Data.CreateMenu

        if CustomMenu then
            CustomMenu(SubPanel, Data, Contexts)
        end

        Menu:EndTemporal(SubPanel)
    end

    ACF.Menu.LoadClassCombo(ClassList, Entries, "Name", nil, PAGE, "engine")

    -- Fuel config labels and stuff 
    local FuelConfig = Menu:AddCollapsible("Fuel System Configuration", nil, "icon16/shape_square_edit.png")
    local EngineType = FuelConfig:AddComboBox()
    EngineType:AddChoice("Diesel Engine", "ACF.EngineTypes.GenericDiesel")
    EngineType:AddChoice("Petrol Engine", "ACF.EngineTypes.GenericPetrol")
    EngineType:SetValue("Petrol Engine") -- Filthy fucking hack, i hate this
    timer.Simple(0, function() if IsValid(EngineType) then EngineType:OnSelect(nil, nil, "ACF.EngineTypes.GenericPetrol") end end) -- smh

    local FuelType = FuelConfig:AddComboBox()
    --=========================================================================--
    -- RIGHT BELOW THIS CODE IS MOSTLY COPIED FROM engines.lua MENU CODE       --
    --=========================================================================--
    local FuelShape = FuelConfig:AddComboBox()
    FuelShape:AddChoice("Box", "ACF.ContainerShapes.Box")
    FuelShape:AddChoice("Sphere", "ACF.ContainerShapes.Sphere")
    FuelShape:AddChoice("Cylinder", "ACF.ContainerShapes.Cylinder")

    local Min = ACF.ContainerMinSize
    local Max = ACF.ContainerMaxSize

    local SizeX = FuelConfig:AddSlider("#acf.menu.fuel.tank_length", Min, Max)
    local SizeY = FuelConfig:AddSlider("#acf.menu.fuel.tank_width", Min, Max)
    local SizeZ = FuelConfig:AddSlider("#acf.menu.fuel.tank_height", Min, Max)

    local FuelBase    = Menu:AddCollapsible("#acf.menu.fuel.tank_info", nil, "icon16/cup_edit.png")
    local FuelDesc    = FuelBase:AddLabel()
    local FuelPreview = FuelBase:AddModelPreview(nil, true, "Secondary")
    local FuelInfo    = FuelBase:AddLabel()

    -- We don't work with a preset list of engines, these are created on the run instead.
    function EngineType:OnSelect(_, _, Data)
        if self.Selected == Data then return end

        self.Selected = Data

        local FuelData

        -- Shitty hack to get the type of fuel used for these engine Classes
        if Data == "ACF.EngineTypes.GenericPetrol" then
            FuelData = "ACF.FuelTypes.Petrol"
        elseif Data == "ACF.EngineTypes.GenericDiesel" then
            FuelData = "ACF.FuelTypes.Diesel"
        end

        local FuelDescription = GetType(FuelData)
        local Fueltank = {FuelData = FuelDescription}

        ACF.Menu.LoadClassCombo(FuelType, Fueltank, "ID", nil, PAGE, "engine")
    end

    function FuelType:UpdateFuelText()
        if not self.Selected then return end

        local Wall  = ACF.ContainerArmor * ACF.MmToInch
        local ShapeInst = Fuel:Get("Shape")
        local Shape = (ShapeInst and ShapeInst.GetType) and ShapeInst:GetType() or GetType("ACF.ContainerShapes.Box")

        local Volume, Area = Shape.ShapeCalculation(TankSize, Wall)

        local Capacity  = Volume * ACF.gCmToKgIn
        local EmptyMass = Area * Wall * ACF.InchToCmCu * ACF.SteelDensity
        local Mass      = EmptyMass + Capacity * self.Selected.Density

        local FuelText
        if self.Selected.FuelTankText then
            FuelText = self.Selected.FuelTankText(Capacity, Mass, EmptyMass)
        else
            local Text = language.GetPhrase("acf.menu.fuel.tank_stats")
            FuelText = Text:format(ACF.ContainerArmor, math.Round(Capacity, 2), math.Round(Capacity * ACF.LToGal, 2), ACF.GetProperMass(Mass), ACF.GetProperMass(EmptyMass))
        end

        FuelDesc:SetText("Scalable Fuel Tank\n\nShape: " .. (Shape.Name or "Box"))
        FuelInfo:SetText(FuelText)
    end

    local function ScalePreview()
        if IsValid(FuelPreview) then FuelPreview:SetModelScale(TankSize * 12) end
    end

    function FuelType:OnSelect(Index, _, Data)
        if self.Selected == Data then return end

        self.ListData.Index = Index
        self.Selected = Data

        ACF.Menu.SaveClassCombo(PAGE, "fuel", Data)

        Fuel:Set("FuelType", Classes.GetTypeName(Data))
        self:UpdateFuelText()
    end

    function FuelShape:OnSelect(_, _, Data)
        Fuel:Set("Shape", Data)

        local ShapeClass = GetType(Data) or GetType("ACF.ContainerShapes.Box")
        if IsValid(FuelPreview) then FuelPreview:UpdateModel(ShapeClass.Model, "models/props_canal/metalcrate001d") end

        FuelType:UpdateFuelText()
    end

    local function BindSize(Slider, Axis, Field)
        function Slider:OnValueChanged(Value)
            local N = math.Round(Value)
            self:SetValue(N)
            TankSize[Axis] = N
            Fuel:Set(Field, N)
            FuelType:UpdateFuelText()
            ScalePreview()
        end
    end

    BindSize(SizeX, "x", "FuelSizeX")
    BindSize(SizeY, "y", "FuelSizeY")
    BindSize(SizeZ, "z", "FuelSizeZ")

    -- Restore shape (fires OnSelect) then seed the size sliders (fires their handlers -> context + preview).
    local ShapeInst = Fuel:Get("Shape")
    local ShapeFQN  = (ShapeInst and ShapeInst.GetType) and Classes.GetTypeName(ShapeInst:GetType()) or "ACF.ContainerShapes.Box"
    FuelShape:ChooseOptionID(ShapeFQN == "ACF.ContainerShapes.Sphere" and 2 or ShapeFQN == "ACF.ContainerShapes.Cylinder" and 3 or 1)

    SizeX:SetValue(TankSize.x)
    SizeY:SetValue(TankSize.y)
    SizeZ:SetValue(TankSize.z)
end

ACF.Menu.RegisterPage({
    ID       = "acf_engine_custom",
    Category = "#acf.menu.entities",
    Name     = "Custom Engines",
    Icon     = "car_add",
    Order    = 299,

    Contexts = { Engine = "acf_engine_custom", Fuel = "acf_fueltank_custom" },

    -- Not yet my baby <3
    -- Actions = {
    --     { Bind = nil, Context = nil, Preview = false, Desc = "Select an option from the menu."},
    -- },

    Actions = {
        { Bind = "left",       Context = "Engine", Preview = true, Desc = "Spawn a new custom engine, or update the one you're aiming at." },
        { Bind = "shift+left", Context = "Fuel",   Preview = true, Desc = "Spawn a new fuel tank, or update the one you're aiming at." },
        { Bind = "right",      Commit = "link", Desc = "Select entities, then an engine/tank/radiator, to link them (hold R to unlink)." },
    },

    Build = Build,
})
