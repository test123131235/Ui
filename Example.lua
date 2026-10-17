-- Feral UI showcase: every element + SaveManager (modelled on the Obsidian example)
-- Replace the repo URL with where you host Library.lua and SaveManager.lua.

local repo = "https://raw.githubusercontent.com/test123131235/Ui/main/" -- change to your repo (must end with /)

local genv = (getgenv and getgenv()) or shared

-- Downloads + runs a file. Some executors run loadstring chunks asynchronously and return nothing,
-- so if there is no return value we wait for the file to publish itself on getgenv().
local function Load(Name, GlobalName)
	local Old = genv[GlobalName]

	local Source = game:HttpGet(repo .. Name)
	local Chunk, CompileError = loadstring(Source)
	assert(Chunk, ("%s failed to compile: %s (check the URL, got %d bytes)"):format(Name, tostring(CompileError), #Source))

	local Result = Chunk()

	if not Result then
		local Start = os.clock()
		repeat
			task.wait()
			Result = genv[GlobalName]
		until (Result and Result ~= Old) or os.clock() - Start > 10

		if Result == Old then
			Result = nil
		end
	end

	return Result
end

local Library = Load("Library.lua", "Library")
assert(Library, "Library.lua did not load: open the console for an earlier error, and make sure the repo URL is right")
assert(Library.Elements and Library.Dialog, "Your hosted Library.lua is OLD. Upload the new Library.lua (v1.1.0) and run again")

local SaveManager = Load("SaveManager.lua", "FeralSaveManager")
assert(SaveManager, "SaveManager.lua did not load: upload SaveManager.lua next to Library.lua")

-- NOTE: Feral has no Options/Toggles tables or :OnChanged. Give an element a `Flag` and either
--   * pass a `Callback = function(Value) ... end`, or
--   * read it any time with  Library.Flags.MyFlag   (or Library:Get("MyFlag")).
-- The returned element objects also have :Set(Value) and .Value.
local Flags = Library.Flags

--// Window -------------------------------------------------------------------

local Window = Library:Window({
	Title = "Feral Hub",
	GameName = "Example game",
	-- Logo = "rbxassetid://121449270899000",
	Keybind = Enum.KeyCode.RightShift, -- menu toggle key (can also be changed with Library:SetMenuKey)
	Watermark = true,                  -- draggable watermark
	NotificationAnchor = true,         -- set false to hide the "drag me" notification anchor
})

-- Little info boxes next to the title
Window:AddFPSPill()
Window:AddPingPill()
Window:AddTimePill()
-- Window:AddCoordsPill()
-- Window:AddUsernamePill()
-- local Custom = Window:AddCustomPill("Kills", "0", nil, Color3.fromRGB(255, 80, 80))
-- Custom:SetDescription("12")   -- also :SetTitle, :SetLogo, :SetAccent, :Destroy

Window:SetWatermark("Feral Hub | example") -- (Text, Logo)

--// Tabs ---------------------------------------------------------------------
-- Window:AddTab(Name, Icon) -> Tab:AddSubTab(Name) -> SubTab:AddSection(Name, "Left" | "Right")

local MainTab = Window:AddTab("Main")
local UITab = Window:AddTab("UI Settings")

local Elements = MainTab:AddSubTab("Elements")
local Inputs = MainTab:AddSubTab("Inputs")

--// Toggles ------------------------------------------------------------------

local Toggles = Elements:AddSection("Toggles", "Left")

local MyToggle = Toggles:AddToggle({
	Title = "This is a toggle",
	Flag = "MyToggle",
	Default = true,
	Callback = function(Value)
		print("[cb] MyToggle changed to:", Value)
	end,
})

-- A toggle can have a colorpicker attached (square next to the switch)
Toggles:AddToggle({
	Title = "Toggle with color",
	Flag = "ColorToggle",
	Default = false,
	Color = Color3.fromRGB(255, 0, 0),
	ColorFlag = "ColorToggleColor",
	ColorCallback = function(Color)
		print("[cb] Toggle color changed:", Color)
	end,
	Callback = function(Value)
		print("[cb] ColorToggle:", Value)
	end,
})

-- This prints "[cb] MyToggle changed to: false"
MyToggle:Set(false)
-- Read it any time:
print("MyToggle is", Flags.MyToggle)

--// Buttons / labels / dividers ------------------------------------------------

local Misc = Elements:AddSection("Buttons & labels", "Left")

local MyButton = Misc:AddButton({
	Title = "Button",
	Callback = function()
		print("You clicked a button!")
		Library:Notify("Button", "You clicked a button!", 3) -- (Title, Description, Duration)
	end,
})

Misc:AddButton({
	Title = "Confirm dialog",
	Callback = function()
		Library:Dialog({
			Title = "Are you sure?",
			Description = "This is a confirm dialog. Click outside of it to cancel.",
			ConfirmText = "Do it",
			CancelText = "Nope",
			Destructive = true,
			Callback = function()
				Library:Notify("Dialog", "Confirmed!")
			end,
			OnCancel = function()
				Library:Notify("Dialog", "Cancelled")
			end,
		})
	end,
})

Misc:AddButton({
	Title = "Rename first button",
	Callback = function()
		MyButton:SetText("Renamed!")
	end,
})

Misc:AddDivider()

Misc:AddLabel("This is a label")
Misc:AddLabel({ Title = "This is a dim label which wraps its text when it gets too long.", Dim = true })

local ChangingLabel = Misc:AddLabel("This label gets changed")
Misc:AddButton({
	Title = "Change label",
	Callback = function()
		ChangingLabel:Set("Changed at " .. os.date("%X"))
	end,
})

--// Sliders ---------------------------------------------------------------------

local Sliders = Elements:AddSection("Sliders", "Right")

Sliders:AddSlider({
	Title = "This is my slider!",
	Flag = "MySlider",
	Default = 0,
	Min = 0,
	Max = 5,
	Decimals = 1, -- 0 = whole numbers
	Callback = function(Value)
		print("[cb] MySlider was changed! New value:", Value)
	end,
})

Sliders:AddSlider({
	Title = "Slider with prefix / suffix",
	Flag = "MySlider2",
	Default = 50,
	Min = 0,
	Max = 100,
	Prefix = "~",
	Suffix = "%",
})

local MySlider = Sliders:AddSlider({ Title = "Set from code", Flag = "MySlider3", Min = 0, Max = 10, Default = 2 })
MySlider:Set(3)
-- MySlider:Set(7, true) -- second argument = silent (no callback)

--// Colorpickers ------------------------------------------------------------------

local Colors = Elements:AddSection("Colorpickers", "Right")

Colors:AddColorpicker({
	Title = "Color",
	Flag = "ColorPicker",
	Default = Color3.fromRGB(0, 255, 140),
	Callback = function(Color)
		print("[cb] Color changed!", Color)
	end,
})

Colors:AddButton({
	Title = "Set color to red",
	Callback = function()
		Library:Set("ColorPicker", Color3.fromRGB(255, 0, 0)) -- Library:Set(Flag, Value) works on any flag
	end,
})

--// Keybinds ------------------------------------------------------------------------

local Keybinds = Elements:AddSection("Keybinds", "Right")

local Toggle_Keybind = Keybinds:AddKeybind({
	Title = "Toggle keybind",
	Flag = "KeyPicker",
	Mode = "Toggle", -- "Press" (default) | "Toggle" | "Hold"
	Default = Enum.KeyCode.E, -- KeyCode or its name ("E")
	Callback = function(State)
		print("[cb] KeyPicker state:", State)
	end,
	ChangedCallback = function(Key) -- Key is a KeyCode, or nil when cleared with Escape
		print("[cb] KeyPicker rebound to:", Key and Key.Name or "None")
	end,
})

local Hold_Keybind = Keybinds:AddKeybind({
	Title = "Hold keybind",
	Flag = "HoldKeyPicker",
	Mode = "Hold",
	Default = "Q",
	Callback = function(State)
		print("[cb] Hold keybind:", State)
	end,
})

local KeybindNumber = 0
Keybinds:AddKeybind({
	Title = "Press keybind (counter)",
	Flag = "PressKeyPicker",
	Mode = "Press",
	Default = "X",
	Callback = function()
		KeybindNumber = KeybindNumber + 1
		print("[cb] Keybind pressed! Number increased to:", KeybindNumber)
	end,
})

-- Checking a keybind's state from a loop (works for Toggle / Hold)
task.spawn(function()
	while task.wait(1) do
		if Library.Unloaded then
			break
		end

		if Toggle_Keybind:GetState() then
			print("Toggle keybind is on")
		end
	end
end)

--// Inputs tab ------------------------------------------------------------------------

local TextboxSection = Inputs:AddSection("Textboxes", "Left")

TextboxSection:AddLabel({ Title = "Textbox (value is applied when it loses focus)", Dim = true })
TextboxSection:AddTextbox({
	Title = "This is a textbox",
	Flag = "MyTextbox",
	Default = "My textbox!",
	Placeholder = "Placeholder text",
	-- Icon = "rbxassetid://...",
	Callback = function(Value)
		print("[cb] Text updated. New text:", Value)
	end,
})

-- Read-only text box, handy for live status. :Set(Text, Animate)
local Indicator = TextboxSection:AddTextIndicator({
	Title = "Indicator",
	Flag = "MyIndicator",
	Default = "Waiting...",
})

TextboxSection:AddButton({
	Title = "Type into indicator",
	Callback = function()
		Indicator:Set("Hello from the indicator!", true) -- true = typewriter animation
	end,
})

local DropdownSection = Inputs:AddSection("Dropdowns", "Right")

DropdownSection:AddDropdown({
	Title = "A dropdown",
	Flag = "MyDropdown",
	Options = { "This", "is", "a", "dropdown" },
	Default = "is", -- defaults to the first option
	Callback = function(Value)
		print("[cb] Dropdown got changed. New value:", Value)
	end,
})

-- Multi dropdown: the value is an array of the selected options
DropdownSection:AddDropdown({
	Title = "A multi dropdown",
	Flag = "MyMultiDropdown",
	Options = { "This", "is", "a", "multi", "dropdown" },
	Multi = true,
	Default = { "This", "is" },
	Callback = function(Value)
		print("[cb] Multi dropdown got changed:", table.concat(Value, ", "))
	end,
})

-- Format changes only what is displayed, the value stays the same
DropdownSection:AddDropdown({
	Title = "A display formatted dropdown",
	Flag = "MyFormattedDropdown",
	Options = { "This", "is", "formatted" },
	Format = function(Value)
		if Value == "formatted" then
			return "display formatted"
		end

		return Value
	end,
	Callback = function(Value)
		print("[cb] Formatted dropdown value:", Value) -- still "formatted"
	end,
})

-- Dropdown with options we can swap out at runtime
local Players = game:GetService("Players")
local PlayerDropdown = DropdownSection:AddDropdown({
	Title = "A player dropdown",
	Flag = "MyPlayerDropdown",
	Options = {},
	Callback = function(Value)
		print("[cb] Player dropdown got changed:", Value)
	end,
})

local function RefreshPlayers()
	local Names = {}

	for _, Player in ipairs(Players:GetPlayers()) do
		if Player ~= Players.LocalPlayer then
			table.insert(Names, Player.Name)
		end
	end

	PlayerDropdown:Refresh(Names) -- (Options, optional Default)
end

RefreshPlayers()
Library:Connect(Players.PlayerAdded, RefreshPlayers)
Library:Connect(Players.PlayerRemoving, function()
	task.defer(RefreshPlayers)
end)

--// UI Settings -----------------------------------------------------------------------

Library:OnUnload(function()
	print("Unloaded!")
end)

local MenuTab = UITab:AddSubTab("Menu")
local ConfigTab = UITab:AddSubTab("Config")

local MenuSection = MenuTab:AddSection("Menu", "Left")

MenuSection:AddToggle({
	Title = "Watermark",
	Flag = "WatermarkVisible",
	Default = true,
	Callback = function(Value)
		Window:SetWatermarkVisible(Value)
	end,
})

MenuSection:AddButton({
	Title = "Test notification",
	Callback = function()
		Library:Notify("Notification", "Drag the example notification to move where these appear.", 4)
	end,
})

MenuSection:AddDivider()

-- Rebinding the menu key. Window opens/closes with Library.Keybind
MenuSection:AddKeybind({
	Title = "Menu keybind",
	Flag = "MenuKeybind",
	Mode = "Press",
	Default = Enum.KeyCode.RightShift,
	ChangedCallback = function(Key)
		if Key then
			Library:SetMenuKey(Key)
		end
	end,
})

MenuSection:AddButton({
	Title = "Unload",
	Callback = function()
		Library:Exit() -- same as Library:Unload()
	end,
})

-- Live theme editing. Every color of the UI is in Library.Theme
local ThemeSection = MenuTab:AddSection("Theme", "Right")

for _, Key in ipairs({ "Accent", "AccentDark", "Window", "Panel", "Section", "Element", "Outline" }) do
	ThemeSection:AddColorpicker({
		Title = Key,
		Flag = "Theme_" .. Key, -- "Theme_*" flags are skipped by SaveManager:IgnoreThemeSettings()
		Default = Library.Theme[Key],
		Callback = function(Color)
			Library:SetTheme(Key, Color)
		end,
	})
end

--// SaveManager --------------------------------------------------------------------------

-- Hand the library over to the manager
SaveManager:SetLibrary(Library)

-- Don't save theme colors inside configs (flags named like theme keys, or "Theme_<Key>")
SaveManager:IgnoreThemeSettings()

-- Ignore flags you don't want per-config (do you want each config to have a different menu key? probably not)
SaveManager:SetIgnoreIndexes({ "MenuKeybind", "MyIndicator" })

-- Config files go to:  MyScriptHub/specific-game/settings/specific-place/<name>.json
SaveManager:SetFolder("MyScriptHub/specific-game")
SaveManager:SetSubFolder("specific-place") -- optional, e.g. different places of one game

-- Optional: load element types in a specific order (e.g. dropdowns before the things that depend on them)
-- SaveManager:SetLoadingOrder(true, { "Dropdown", "Toggle", "Slider", "Textbox", "Colorpicker", "Keybind" })

-- Optional: don't save the window / notification position
-- SaveManager:SetSaveLayout(false)

-- Builds the Configuration section (right side by default; pass "Left" as 2nd argument for the left)
SaveManager:BuildConfigSection(ConfigTab)

-- Loads the config marked "Set as autoload". Keep this as the LAST line of your script.
SaveManager:LoadAutoloadConfig()
