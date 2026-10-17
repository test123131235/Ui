--[[
	Feral UI - Example
	Showcases every element the library has.

	1. Upload Library.lua (and this file) to your GitHub repo.
	2. Point `Repo` below at your raw URL:  https://raw.githubusercontent.com/<user>/<repo>/<branch>/
]]

local Repo = "https://raw.githubusercontent.com/test123131235/uiuiui/main/"
local Library = loadstring(game:HttpGet(Repo .. "Library.lua"))()

--// Optional: tweak the library before building the window
Library.Directory = "feral_example"      -- folder used for configs / fonts
Library.Animation.Time = 0.3             -- global tween time
-- Library:SetTheme("Accent", Color3.fromRGB(255, 80, 80)) -- change colors before or after creating the UI

--// Window ---------------------------------------------------------------------
local Window = Library:Window({
	Title = "Feral Hub",
	GameName = "Library Showcase",
	Logo = "rbxassetid://121449270899000",
	Keybind = Enum.KeyCode.X,         -- menu key (also changeable in the Settings tab)
	-- NotificationAnchor = false,    -- hide the draggable "Example" notification
	-- Watermark = false,             -- hide the watermark
})

Window:SetWatermark("Feral Hub - Example", "rbxassetid://104479390541433")

--// Pills (info boxes in the title bar) ----------------------------------------
Window:AddFPSPill()
Window:AddPingPill()
Window:AddTimePill()
Window:AddCoordsPill()
Window:AddUsernamePill()

local CustomPill = Window:AddCustomPill("Custom", "Hello!", nil, Color3.fromRGB(255, 120, 0))
-- CustomPill:Set("New title", "New description")  |  :SetTitle() :SetDescription() :SetLogo() :SetAccent() :Destroy()

--// Tabs -----------------------------------------------------------------------
local MainTab = Window:AddTab("Main", "rbxassetid://106606600179475")
local VisualTab = Window:AddTab("Visuals", "rbxassetid://106606600179475")
local SettingsTab = Window:AddTab("Settings", "rbxassetid://106606600179475")

--// Main > Elements --------------------------------------------------------------
local Elements = MainTab:AddSubTab("Elements")

local Toggles = Elements:AddSection("Toggles & Sliders", "Left")

local MainToggle = Toggles:AddToggle({
	Title = "Simple toggle",
	Flag = "simple_toggle",
	Default = false,
	Callback = function(Value)
		print("simple_toggle:", Value)
	end,
})

Toggles:AddToggle({
	Title = "Toggle + color",
	Flag = "color_toggle",
	Default = true,
	Callback = function(Value)
		print("color_toggle:", Value)
	end,
	Color = Color3.fromRGB(255, 60, 60),   -- adds a colorpicker next to the switch
	ColorFlag = "color_toggle_color",
	ColorCallback = function(Color)
		print("toggle color:", Color)
	end,
})

local Speed = Toggles:AddSlider({
	Title = "Slider (integer)",
	Flag = "speed",
	Min = 0, Max = 100, Default = 50,
	Suffix = " studs",
	Callback = function(Value)
		print("speed:", Value)
	end,
})

Toggles:AddSlider({
	Title = "Slider (decimals)",
	Flag = "smoothness",
	Min = 0, Max = 1, Default = 0.5, Decimals = 2,
	Prefix = "x",
})

Toggles:AddDivider()

Toggles:AddLabel("Labels wrap automatically and can be changed with :Set().")

local Buttons = Elements:AddSection("Buttons & Keybinds", "Left")

Buttons:AddButton({
	Title = "Print all flags",
	Callback = function()
		for Flag, Value in pairs(Library.Flags) do
			print(Flag, "=", Value)
		end

		Library:Notify("Flags", "Printed to the console (F9)", 3)
	end,
})

Buttons:AddButton({
	Title = "Flip simple toggle from code",
	Callback = function()
		MainToggle:Set(not MainToggle.Value) -- :Set(Value, Silent) - Silent skips the callback
	end,
})

Buttons:AddKeybind({
	Title = "Press keybind",
	Flag = "press_key",
	Default = Enum.KeyCode.Z,
	Mode = "Press",
	Callback = function()
		Library:Notify("Keybind", "You pressed the Press keybind", 2)
	end,
})

Buttons:AddKeybind({
	Title = "Toggle keybind",
	Flag = "toggle_key",
	Default = Enum.KeyCode.C,
	Mode = "Toggle",
	Callback = function(State)
		print("toggle keybind state:", State)
	end,
})

Buttons:AddKeybind({
	Title = "Hold keybind",
	Flag = "hold_key",
	Default = Enum.KeyCode.V,
	Mode = "Hold",
	Callback = function(State)
		print("hold keybind:", State and "held" or "released")
	end,
})

local Inputs = Elements:AddSection("Inputs", "Right")

Inputs:AddDropdown({
	Title = "Dropdown",
	Flag = "single_dropdown",
	Options = { "Option 1", "Option 2", "Option 3" },
	Default = "Option 1",
	Callback = function(Value)
		print("dropdown:", Value)
	end,
})

local Multi = Inputs:AddDropdown({
	Title = "Multi dropdown",
	Flag = "multi_dropdown",
	Multi = true,
	Options = { "Alpha", "Beta", "Gamma", "Delta" },
	Default = { "Alpha" },
	Callback = function(Selected)
		print("multi dropdown:", table.concat(Selected, ", "))
	end,
})
-- Multi:Refresh({ "New", "Options" })  -- replace the options at runtime

Inputs:AddTextbox({
	Title = "Textbox",
	Flag = "textbox",
	Placeholder = "Type something and press enter...",
	Icon = "rbxassetid://107972121937062",
	Callback = function(Text)
		Library:Notify("Textbox", "You typed: " .. Text, 3)
	end,
})

local Indicator = Inputs:AddTextIndicator({
	Title = "Indicator",
	Flag = "indicator",
	Default = "Read-only text",
	Icon = "rbxassetid://102638872351950",
})

Inputs:AddButton({
	Title = "Animate indicator",
	Callback = function()
		Indicator:Set("Typed out letter by letter!", true) -- second argument = animate
	end,
})

Inputs:AddColorpicker({
	Title = "Colorpicker",
	Flag = "colorpicker",
	Default = Color3.fromRGB(0, 170, 255),
	Callback = function(Color)
		print("colorpicker:", Color)
	end,
})

--// Main > Live values -----------------------------------------------------------
local Live = MainTab:AddSubTab("Live values")

local Readout = Live:AddSection("Reading flags", "Left")
local SpeedLabel = Readout:AddLabel("Speed: " .. tostring(Library.Flags.speed))
local ToggleLabel = Readout:AddLabel("Simple toggle: " .. tostring(Library.Flags.simple_toggle))

Readout:AddLabel({
	Title = "Library.Flags[<flag>] always holds the current value of every element that has a Flag.",
	Dim = true,
})

task.spawn(function()
	while not Library.Unloaded do
		SpeedLabel:Set("Speed: " .. tostring(Library.Flags.speed))
		ToggleLabel:Set("Simple toggle: " .. tostring(Library.Flags.simple_toggle))
		task.wait(0.25)
	end
end)

local Programmatic = Live:AddSection("Set values from code", "Right")

Programmatic:AddButton({
	Title = "Library:Set('speed', 80)",
	Callback = function()
		Library:Set("speed", 80)
	end,
})

Programmatic:AddButton({
	Title = "Speed:Set(10)",
	Callback = function()
		Speed:Set(10)
	end,
})

--// Visuals > Feedback ---------------------------------------------------------
local Feedback = VisualTab:AddSubTab("Feedback")

local Notifications = Feedback:AddSection("Notifications", "Left")

Notifications:AddButton({
	Title = "Short notification",
	Callback = function()
		Library:Notify("Hello", "This is a short notification.", 2)
	end,
})

Notifications:AddButton({
	Title = "Long notification (6s)",
	Callback = function()
		Library:Notify("Long one", "This one stays for six seconds so you can see stacking.", 6)
	end,
})

Notifications:AddLabel({
	Title = "Drag the \"Example\" notification (visible while the menu is open) to choose where notifications appear.",
	Dim = true,
})

local Pills = Feedback:AddSection("Pills & watermark", "Right")

Pills:AddTextbox({
	Title = "Pill text",
	Placeholder = "Custom pill description...",
	Callback = function(Text)
		CustomPill:SetDescription(Text)
	end,
})

Pills:AddTextbox({
	Title = "Watermark text",
	Placeholder = "Watermark text...",
	Callback = function(Text)
		Window:SetWatermark(Text)
	end,
})

Pills:AddToggle({
	Title = "Show watermark",
	Default = true,
	Callback = function(Value)
		Window:SetWatermarkVisible(Value)
	end,
})

local Greeting = VisualTab:AddSubTab("Window")
local WindowSection = Greeting:AddSection("Window text", "Left")

WindowSection:AddTextbox({
	Title = "Window title",
	Placeholder = "Window title...",
	Callback = function(Text)
		Window:SetTitle(Text)
	end,
})

WindowSection:AddTextbox({
	Title = "Game name",
	Placeholder = "Game name...",
	Callback = function(Text)
		Window:SetGameName(Text)
	end,
})

--// Settings -------------------------------------------------------------------
local Settings = SettingsTab:AddSubTab("Menu")

local Menu = Settings:AddSection("Menu", "Left")

Menu:AddKeybind({
	Title = "Menu key",
	Flag = "menu_key",
	Default = Library.Keybind,
	Mode = "Press",
	ChangedCallback = function(Key)
		if Key then
			Library:SetMenuKey(Key)
		end
	end,
	Callback = function() end,
})

Menu:AddButton({
	Title = "Unload UI",
	Callback = function()
		Library:Unload()
	end,
})

local Theme = Settings:AddSection("Theme", "Right")

Theme:AddColorpicker({
	Title = "Accent",
	Flag = "theme_accent",
	Default = Library.Theme.Accent,
	Callback = function(Color)
		Library:SetTheme("Accent", Color)
	end,
})

Theme:AddColorpicker({
	Title = "Accent (dark end)",
	Flag = "theme_accent_dark",
	Default = Library.Theme.AccentDark,
	Callback = function(Color)
		Library:SetTheme("AccentDark", Color)
	end,
})

Theme:AddColorpicker({
	Title = "Window background",
	Flag = "theme_window",
	Default = Library.Theme.Window,
	Callback = function(Color)
		Library:SetTheme("Window", Color)
	end,
})

Theme:AddButton({
	Title = "Reset theme",
	Callback = function()
		Library:SetTheme({
			Accent = Color3.fromRGB(0, 131, 255),
			AccentDark = Color3.fromRGB(0, 63, 255),
			Window = Color3.fromRGB(21, 21, 22),
		})

		Library:Set("theme_accent", Color3.fromRGB(0, 131, 255))
		Library:Set("theme_accent_dark", Color3.fromRGB(0, 63, 255))
		Library:Set("theme_window", Color3.fromRGB(21, 21, 22))
	end,
})

local Configs = Settings:AddSubTab("Configs")
local ConfigSection = Configs:AddSection("Configs", "Left")
ConfigSection:AddConfigManager()

local ConfigInfo = Configs:AddSection("How it works", "Right")
ConfigInfo:AddLabel("Every element with a Flag is saved. Pick a config, press Save / Load, or mark one with Set Auto-Load.")

--// Cleanup hook
Library:OnUnload(function()
	print("[Example] UI unloaded")
end)

--// Finish
Library:LoadAutoload() -- loads the config marked with "Set Auto-Load" (does nothing if there is none)

task.delay(1, function()
	Library:Notify("Feral UI", "Loaded! Press " .. Library.Keybind.Name .. " to toggle the menu.", 4)
end)
