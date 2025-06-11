if SERVER then return end

-- Glass Rewrite Settings Panel
local PANEL = {}

function PANEL:Init()
    self:SetSize(400, 600)
    self:SetTitle("Glass Rewrite Settings")
    self:SetDeleteOnClose(false)
    self:SetDraggable(true)
    self:ShowCloseButton(true)
    self:SetScreenLock(true)
    
    -- Create main container
    local scroll = vgui.Create("DScrollPanel", self)
    scroll:Dock(FILL)
    scroll:DockMargin(5, 5, 5, 5)
    
    -- Title
    local title = vgui.Create("DLabel", scroll)
    title:SetText("Glass Rewrite - Remix Settings")
    title:SetFont("DermaDefaultBold")
    title:SetTextColor(Color(255, 255, 255))
    title:SizeToContents()
    title:DockMargin(0, 0, 0, 10)
    title:Dock(TOP)
    
    -- Presets Section
    self:CreatePresetsSection(scroll)
    
    -- Settings Sections
    self:CreateVisualSection(scroll)
    self:CreatePhysicsSection(scroll)
    self:CreatePlayerSection(scroll)
    self:CreateAdvancedSection(scroll)
    
    -- Apply/Reset buttons
    self:CreateButtonSection(scroll)
end

function PANEL:CreatePresetsSection(parent)
    local presets = vgui.Create("DCollapsibleCategory", parent)
    presets:SetLabel("Presets")
    presets:SetExpanded(true)
    presets:Dock(TOP)
    presets:DockMargin(0, 0, 0, 5)
    
    local presets_list = vgui.Create("DPanelList", presets)
    presets_list:SetDrawBackground(false)
    presets_list:SetSpacing(5)
    presets_list:SetPadding(5)
    presets_list:EnableHorizontal(true)
    presets_list:EnableVerticalScrollbar(false)
    presets:SetContents(presets_list)
    
    -- Preset definitions
    local presets_data = {
        {
            name = "Fragile Glass",
            desc = "Breaks easily like real window glass",
            settings = {
                glass_realistic_breaking = 1,
                glass_show_cracks = 1,
                glass_crack_delay = 0.1,
                glass_shard_count = 3,
                glass_rigidity = 25,
                glass_mass_factor = 1.0,
                glass_velocity_transfer = 1.2,
                glass_player_mass = 70,
                glass_player_break_speed = 120
            }
        },
        {
            name = "Realistic Glass",
            desc = "Balanced realistic glass behavior",
            settings = {
                glass_realistic_breaking = 1,
                glass_show_cracks = 1,
                glass_crack_delay = 0.15,
                glass_shard_count = 4,
                glass_rigidity = 50,
                glass_mass_factor = 1.0,
                glass_velocity_transfer = 1.0,
                glass_player_mass = 70,
                glass_player_break_speed = 150
            }
        },
        {
            name = "Reinforced Glass",
            desc = "Strong security glass",
            settings = {
                glass_realistic_breaking = 1,
                glass_show_cracks = 1,
                glass_crack_delay = 0.2,
                glass_shard_count = 5,
                glass_rigidity = 120,
                glass_mass_factor = 1.5,
                glass_velocity_transfer = 0.8,
                glass_player_mass = 70,
                glass_player_break_speed = 220
            }
        },
        {
            name = "Action Movie",
            desc = "Dramatic explosive glass breaking",
            settings = {
                glass_realistic_breaking = 1,
                glass_show_cracks = 1,
                glass_crack_delay = 0.05,
                glass_shard_count = 6,
                glass_rigidity = 30,
                glass_mass_factor = 0.8,
                glass_velocity_transfer = 2.0,
                glass_player_mass = 80,
                glass_player_break_speed = 100
            }
        },
        {
            name = "Performance Mode",
            desc = "Lower fragment count for better FPS",
            settings = {
                glass_realistic_breaking = 1,
                glass_show_cracks = 0,
                glass_crack_delay = 0.1,
                glass_shard_count = 2,
                glass_rigidity = 40,
                glass_mass_factor = 1.0,
                glass_velocity_transfer = 1.0,
                glass_player_mass = 70,
                glass_player_break_speed = 150
            }
        }
    }
    
    for _, preset in ipairs(presets_data) do
        local btn = vgui.Create("DButton", presets_list)
        btn:SetText(preset.name)
        btn:SetTooltip(preset.desc)
        btn:SetSize(100, 30)
        btn.DoClick = function()
            self:ApplyPreset(preset.settings)
            surface.PlaySound("buttons/button15.wav")
        end
        presets_list:AddItem(btn)
    end
end

function PANEL:CreateVisualSection(parent)
    local visual = vgui.Create("DCollapsibleCategory", parent)
    visual:SetLabel("Visual Effects")
    visual:SetExpanded(true)
    visual:Dock(TOP)
    visual:DockMargin(0, 0, 0, 5)
    
    local visual_panel = vgui.Create("DPanel", visual)
    visual_panel:SetDrawBackground(false)
    visual:SetContents(visual_panel)
    
    -- Realistic Breaking
    local realistic_check = vgui.Create("DCheckBoxLabel", visual_panel)
    realistic_check:SetText("Breaking Patterns")
    realistic_check:SetConVar("glass_realistic_breaking")
    realistic_check:SizeToContents()
    realistic_check:Dock(TOP)
    realistic_check:DockMargin(5, 5, 5, 2)
    
    -- Show Cracks
    local cracks_check = vgui.Create("DCheckBoxLabel", visual_panel)
    cracks_check:SetText("Show Cracks Before Breaking")
    cracks_check:SetConVar("glass_show_cracks")
    cracks_check:SizeToContents()
    cracks_check:Dock(TOP)
    cracks_check:DockMargin(5, 2, 5, 2)
    
    -- Crack Delay
    self:CreateSlider(visual_panel, "Crack Delay", "glass_crack_delay", 0.05, 1.0, 2, "Time between cracks appearing and glass breaking")
    
    -- Shard Count
    self:CreateSlider(visual_panel, "Shard Count", "glass_shard_count", 1, 7, 0, "Number of pieces glass breaks into")
    
    -- Velocity Transfer
    self:CreateSlider(visual_panel, "Velocity Transfer", "glass_velocity_transfer", 0.1, 3.0, 1, "How dramatic the glass explosion is")
end

function PANEL:CreatePhysicsSection(parent)
    local physics = vgui.Create("DCollapsibleCategory", parent)
    physics:SetLabel("Physics Settings")
    physics:SetExpanded(true)
    physics:Dock(TOP)
    physics:DockMargin(0, 0, 0, 5)
    
    local physics_panel = vgui.Create("DPanel", physics)
    physics_panel:SetDrawBackground(false)
    physics:SetContents(physics_panel)
    
    -- Glass Rigidity
    self:CreateSlider(physics_panel, "Glass Rigidity", "glass_rigidity", 0, 200, 0, "How much damage glass can take before breaking")
    
    -- Mass Factor
    self:CreateSlider(physics_panel, "Mass Factor", "glass_mass_factor", 0.1, 3.0, 1, "How much object mass affects impact force")
end

function PANEL:CreatePlayerSection(parent)
    local player = vgui.Create("DCollapsibleCategory", parent)
    player:SetLabel("Player Collision")
    player:SetExpanded(true)
    player:Dock(TOP)
    player:DockMargin(0, 0, 0, 5)
    
    local player_panel = vgui.Create("DPanel", player)
    player_panel:SetDrawBackground(false)
    player:SetContents(player_panel)
    
    -- Player Mass
    self:CreateSlider(player_panel, "Player Mass (kg)", "glass_player_mass", 30, 150, 0, "Player mass for glass breaking calculations")
    
    -- Player Break Speed
    self:CreateSlider(player_panel, "Min Break Speed", "glass_player_break_speed", 50, 400, 0, "Minimum player speed to break glass")
end

function PANEL:CreateAdvancedSection(parent)
    local advanced = vgui.Create("DCollapsibleCategory", parent)
    advanced:SetLabel("Advanced")
    advanced:SetExpanded(false)
    advanced:Dock(TOP)
    advanced:DockMargin(0, 0, 0, 5)
    
    local advanced_panel = vgui.Create("DPanel", advanced)
    advanced_panel:SetDrawBackground(false)
    advanced:SetContents(advanced_panel)
    
    -- Lag Friendly
    local lag_check = vgui.Create("DCheckBoxLabel", advanced_panel)
    lag_check:SetText("Lag Friendly Mode (Reduces Performance Impact)")
    lag_check:SetConVar("glass_lagfriendly")
    lag_check:SizeToContents()
    lag_check:Dock(TOP)
    lag_check:DockMargin(5, 5, 5, 10)
end

function PANEL:CreateButtonSection(parent)
    local button_panel = vgui.Create("DPanel", parent)
    button_panel:SetTall(40)
    button_panel:SetDrawBackground(false)
    button_panel:Dock(TOP)
    button_panel:DockMargin(0, 10, 0, 0)
    
    local reset_btn = vgui.Create("DButton", button_panel)
    reset_btn:SetText("Reset to Defaults")
    reset_btn:SetSize(120, 30)
    reset_btn:SetPos(5, 5)
    reset_btn.DoClick = function()
        self:ResetToDefaults()
        surface.PlaySound("buttons/button14.wav")
    end
    
    local test_btn = vgui.Create("DButton", button_panel)
    test_btn:SetText("Test Settings")
    test_btn:SetSize(120, 30)
    test_btn:SetPos(135, 5)
    test_btn.DoClick = function()
        RunConsoleCommand("glass_settings")
        surface.PlaySound("buttons/button9.wav")
    end
    
    local debug_btn = vgui.Create("DButton", button_panel)
    debug_btn:SetText("Player Debug")
    debug_btn:SetSize(120, 30)
    debug_btn:SetPos(265, 5)
    debug_btn.DoClick = function()
        RunConsoleCommand("glass_player_debug")
        surface.PlaySound("buttons/button9.wav")
    end
end

function PANEL:CreateSlider(parent, label, convar, min_val, max_val, decimals, tooltip)
    local slider = vgui.Create("DNumSlider", parent)
    slider:SetText(label)
    slider:SetConVar(convar)
    slider:SetMin(min_val)
    slider:SetMax(max_val)
    slider:SetDecimals(decimals)
    slider:SetTooltip(tooltip)
    slider:Dock(TOP)
    slider:DockMargin(5, 2, 5, 2)
    slider:SetTall(25)
    return slider
end

function PANEL:ApplyPreset(settings)
    for convar, value in pairs(settings) do
        RunConsoleCommand(convar, tostring(value))
    end
    chat.AddText(Color(100, 255, 100), "[Glass] Preset applied successfully!")
end

function PANEL:ResetToDefaults()
    local defaults = {
        glass_realistic_breaking = 1,
        glass_show_cracks = 1,
        glass_crack_delay = 0.15,
        glass_shard_count = 4,
        glass_rigidity = 50,
        glass_mass_factor = 1.0,
        glass_velocity_transfer = 1.0,
        glass_player_mass = 70,
        glass_player_break_speed = 150,
        glass_lagfriendly = 0
    }
    
    self:ApplyPreset(defaults)
end

vgui.Register("GlassSettingsPanel", PANEL, "DFrame")

-- Add to spawnmenu
hook.Add("PopulateToolMenu", "GlassRewriteSettings", function()
    spawnmenu.AddToolMenuOption("Utilities", "Glass Rewrite", "GlassSettings", "Settings", "", "", function(panel)
        panel:ClearControls()
        
        panel:AddControl("Header", {Description = "Glass Rewrite - Remix\nRealistic glass destruction system"})
        
        -- Quick Settings Button
        panel:AddControl("Button", {
            Label = "Open Settings Panel",
            Command = "glass_open_panel"
        })
        
        -- Quick Presets
        panel:AddControl("Header", {Description = "Quick Presets:"})
        
        local presets = {
            {"Fragile Glass", "glass_realistic_breaking 1; glass_rigidity 25; glass_shard_count 3; glass_velocity_transfer 1.2"},
            {"Realistic Glass", "glass_realistic_breaking 1; glass_rigidity 50; glass_shard_count 4; glass_velocity_transfer 1.0"},
            {"Reinforced Glass", "glass_realistic_breaking 1; glass_rigidity 120; glass_shard_count 5; glass_velocity_transfer 0.8"},
            {"Action Movie", "glass_realistic_breaking 1; glass_rigidity 30; glass_shard_count 6; glass_velocity_transfer 2.0"}
        }
        
        for _, preset in ipairs(presets) do
            panel:AddControl("Button", {
                Label = preset[1],
                Command = preset[2]
            })
        end
        
        -- Debug Tools
        panel:AddControl("Header", {Description = "Debug Tools:"})
        
        panel:AddControl("Button", {
            Label = "Show Current Settings",
            Command = "glass_settings"
        })
        
        panel:AddControl("Button", {
            Label = "Player Impact Analysis",
            Command = "glass_player_debug"
        })
        
        -- Manual Controls
        panel:AddControl("Header", {Description = "Manual Controls:"})
        
        panel:AddControl("CheckBox", {
            Label = "Realistic Breaking",
            Command = "glass_realistic_breaking"
        })
        
        panel:AddControl("CheckBox", {
            Label = "Show Cracks",
            Command = "glass_show_cracks"
        })
        
        panel:AddControl("Slider", {
            Label = "Glass Rigidity",
            Command = "glass_rigidity",
            Type = "Integer",
            Min = "0",
            Max = "200"
        })
        
        panel:AddControl("Slider", {
            Label = "Shard Count",
            Command = "glass_shard_count",
            Type = "Integer", 
            Min = "1",
            Max = "7"
        })
        
        panel:AddControl("Slider", {
            Label = "Velocity Transfer",
            Command = "glass_velocity_transfer",
            Type = "Float",
            Min = "0.1",
            Max = "3.0"
        })
    end)
end)

-- Console command to open settings panel
concommand.Add("glass_open_panel", function()
    if IsValid(GLASS_SETTINGS_FRAME) then
        GLASS_SETTINGS_FRAME:Remove()
    end
    
    GLASS_SETTINGS_FRAME = vgui.Create("GlassSettingsPanel")
    GLASS_SETTINGS_FRAME:Center()
    GLASS_SETTINGS_FRAME:MakePopup()
end) 