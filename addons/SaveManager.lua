--[[
	Feral SaveManager  (modelled after Obsidian's SaveManager)

	local Library     = loadstring(game:HttpGet(".../Library.lua"))()
	local SaveManager = loadstring(game:HttpGet(".../SaveManager.lua"))()

	SaveManager:SetLibrary(Library)
	SaveManager:SetFolder("MyHub")              -- files go to  MyHub/settings/...
	SaveManager:SetSubFolder("MyGame")          -- optional:    MyHub/settings/MyGame/...
	SaveManager:IgnoreThemeSettings()           -- optional
	SaveManager:SetIgnoreIndexes({ "SomeFlag" }) -- optional
	SaveManager:BuildConfigSection(SubTab)      -- adds a "Configuration" section (right side by default)
	SaveManager:LoadAutoloadConfig()            -- call at the end of your script

	Only elements created with a Flag are saved.
]]

local cloneref = cloneref or function(Object) return Object end
local HttpService = cloneref(game:GetService("HttpService"))

local HasFS = (isfolder and isfile and makefolder and readfile and writefile and listfiles and delfile) ~= nil

--// Safe filesystem wrappers (never error, always return the expected type) -----

local function IsFolder(Path)
	local Ok, Result = pcall(isfolder, Path)
	return Ok and Result == true
end

local function IsFile(Path)
	local Ok, Result = pcall(isfile, Path)
	return Ok and Result == true
end

local function ListFiles(Path)
	local Ok, Result = pcall(listfiles, Path)
	return (Ok and type(Result) == "table") and Result or {}
end

--// Module -----------------------------------------------------------------------

local SaveManager = {
	Library = nil,

	Folder = "FeralLibSettings",
	SubFolder = "",

	Ignore = {},
	LoadingOrder = { "Toggle", "Slider", "Dropdown", "Textbox", "Colorpicker", "Keybind" },
	UseLoadingOrder = false,

	SaveLayout = true, -- also save window position + notification anchor
	AutoloadConfig = nil,
}

function SaveManager:SetLibrary(Library)
	SaveManager.Library = Library
end

--// Element parsers --------------------------------------------------------------

local function EncodeUDim2(Value)
	return {
		X = { Scale = Value.X.Scale, Offset = Value.X.Offset },
		Y = { Scale = Value.Y.Scale, Offset = Value.Y.Offset },
	}
end

local function DecodeUDim2(Data)
	if typeof(Data) == "UDim2" then
		return Data
	end

	if type(Data) == "table" and type(Data.X) == "table" and type(Data.Y) == "table" then
		return UDim2.new(
			tonumber(Data.X.Scale) or 0, tonumber(Data.X.Offset) or 0,
			tonumber(Data.Y.Scale) or 0, tonumber(Data.Y.Offset) or 0
		)
	end

	return nil
end

local function CopyArray(Value)
	local Copy = {}
	for _, Item in ipairs(Value) do
		table.insert(Copy, Item)
	end
	return Copy
end

local Parsers = {}

Parsers.Toggle = {
	Save = function(Element)
		return { value = Element.Value == true }
	end,
	Load = function(Element, Data)
		Element:Set(Data.value == true)
	end,
}

Parsers.Slider = {
	Save = function(Element)
		return { value = Element.Value }
	end,
	Load = function(Element, Data)
		local Value = tonumber(Data.value)
		if Value then
			Element:Set(Value)
		end
	end,
}

Parsers.Dropdown = {
	Save = function(Element)
		local Value = Element.Value
		if Element.Multi and type(Value) == "table" then
			Value = CopyArray(Value)
		end

		return { value = Value, multi = Element.Multi }
	end,
	Load = function(Element, Data)
		if Data.value == nil and not Element.Multi then
			return
		end

		Element:Set(Data.value)
	end,
}

Parsers.Textbox = {
	Save = function(Element)
		return { text = Element.Value }
	end,
	Load = function(Element, Data)
		if type(Data.text) == "string" then
			Element:Set(Data.text, false)
		end
	end,
}

Parsers.Colorpicker = {
	Save = function(Element)
		return { value = Element.Value:ToHex() }
	end,
	Load = function(Element, Data)
		if type(Data.value) == "string" then
			Element:Set(Data.value)
		end
	end,
}

Parsers.Keybind = {
	Save = function(Element)
		return { key = Element.Key and Element.Key.Name or "None", mode = Element.Mode }
	end,
	Load = function(Element, Data)
		if type(Data.mode) == "string" then
			Element.Mode = Data.mode
		end

		Element:Set(Data.key or "None")
	end,
}

--// Helpers ----------------------------------------------------------------------

local function Trim(Text)
	return Text:match("^%s*(.-)%s*$")
end

local function IsStringEmpty(String)
	return type(String) ~= "string" or Trim(String) == ""
end

local function IsValidFolderPath(Name)
	return type(Name) == "string" and Trim(Name) ~= "" and not Name:find('[<>:"|%?%*]')
end

local function IsValidConfigName(Name)
	return type(Name) == "string" and Trim(Name) ~= "" and not Name:find('[<>:"|%?%*/\\]')
end

local function SplitPath(Path)
	local Result, Current = {}, ""

	for Part in string.gmatch(Path, "[^/]+") do
		Current = (Current == "") and Part or (Current .. "/" .. Part)
		table.insert(Result, Current)
	end

	return Result
end

local function Notify(Text)
	if SaveManager.Library then
		SaveManager.Library:Notify("Config", Text)
	end
end

--// Paths ------------------------------------------------------------------------

local function GetFolderPath()
	if IsStringEmpty(SaveManager.Folder) then
		return false
	end

	return string.format("%s/settings", SaveManager.Folder)
end

local function GetSubFolderPath()
	if IsStringEmpty(SaveManager.Folder) or IsStringEmpty(SaveManager.SubFolder) then
		return false
	end

	return string.format("%s/settings/%s", SaveManager.Folder, SaveManager.SubFolder)
end

local function GetCurrentSettingsPath()
	local SubFolderPath = GetSubFolderPath()
	if SubFolderPath == false then
		return GetFolderPath()
	end

	return SubFolderPath
end

local function GetConfigPath(ConfigName)
	local Current = GetCurrentSettingsPath()
	if Current == false then
		return false
	end

	return string.format("%s/%s.json", Current, ConfigName)
end

local function GetAutoloadPath()
	local Current = GetCurrentSettingsPath()
	if Current == false then
		return false
	end

	return string.format("%s/autoload.txt", Current)
end

local function DoesConfigExist(ConfigName)
	local Path = GetConfigPath(ConfigName)
	return Path ~= false and IsFile(Path)
end

--// Ignore / loading order ---------------------------------------------------------

function SaveManager:SetLoadingOrder(Enabled, Order)
	SaveManager.UseLoadingOrder = Enabled == true

	if type(Order) == "table" then
		SaveManager.LoadingOrder = Order
	end
end

function SaveManager:SetIgnoreIndexes(Indexes)
	assert(type(Indexes) == "table", "Expected table, got " .. typeof(Indexes))

	for _, Index in ipairs(Indexes) do
		SaveManager.Ignore[Index] = true
	end
end

--- Ignores flags named after the theme keys ("Accent", "Theme_Accent", ...) so themes aren't stored in configs.
function SaveManager:IgnoreThemeSettings()
	local Indexes = {}

	if SaveManager.Library then
		for Key in pairs(SaveManager.Library.Theme) do
			table.insert(Indexes, Key)
			table.insert(Indexes, "Theme_" .. Key)
		end
	end

	table.insert(Indexes, "ThemeList")
	table.insert(Indexes, "ThemeManager_ThemeList")

	SaveManager:SetIgnoreIndexes(Indexes)
end

--- Toggle saving of the window position / notification position.
function SaveManager:SetSaveLayout(Enabled)
	SaveManager.SaveLayout = Enabled == true
end

--// Folders ------------------------------------------------------------------------

function SaveManager:GetPaths()
	local SubFolderPath = GetSubFolderPath()
	if SubFolderPath == false then
		local FolderPath = GetFolderPath()
		return (FolderPath == false) and {} or SplitPath(FolderPath)
	end

	return SplitPath(SubFolderPath)
end

function SaveManager:BuildFolderTree(SkipWhenCreated)
	if not HasFS then
		return false
	end

	local Paths = SaveManager:GetPaths()
	if #Paths == 0 then
		return false
	end

	if SkipWhenCreated == true and IsFolder(Paths[#Paths]) then
		return true
	end

	for _, Path in ipairs(Paths) do
		if not IsFolder(Path) then
			pcall(makefolder, Path)
		end
	end

	return true
end

function SaveManager:CheckFolderTree()
	return SaveManager:BuildFolderTree(true)
end

function SaveManager:SetFolder(Folder)
	assert(IsValidFolderPath(Folder), "Invalid path provided")

	SaveManager.Folder = Folder
	SaveManager:BuildFolderTree()
end

function SaveManager:SetSubFolder(SubFolder)
	assert(IsValidFolderPath(SubFolder), "Invalid path provided")

	SaveManager.SubFolder = SubFolder
	SaveManager:BuildFolderTree()
end

--// Config management ----------------------------------------------------------------

function SaveManager:RefreshConfigList()
	local SettingsPath = GetCurrentSettingsPath()
	if SettingsPath == false or not HasFS then
		return {}
	end

	SaveManager:CheckFolderTree()

	local Names = {}
	for _, FilePath in ipairs(ListFiles(SettingsPath)) do
		local Normalized = tostring(FilePath):gsub("\\", "/")
		local Name = Normalized:match("([^/]+)%.json$")

		if Name and string.lower(Name) ~= "autoload" then
			table.insert(Names, Name)
		end
	end

	table.sort(Names)
	return Names
end

function SaveManager:Save(ConfigName)
	if not HasFS then
		return false, "executor has no file functions"
	end

	if not IsValidConfigName(ConfigName) or string.lower(ConfigName) == "autoload" then
		return false, "Invalid config name provided"
	end

	local ConfigPath = GetConfigPath(ConfigName)
	if ConfigPath == false then
		return false, "Invalid config name provided"
	end

	SaveManager:CheckFolderTree()

	local Library = SaveManager.Library
	local Data = {
		timestamp = os.date("%d.%m.%Y %H:%M:%S"),
		name = ConfigName,
		objects = {},
	}

	local Flags = {}
	for Flag in pairs(Library.Elements) do
		table.insert(Flags, Flag)
	end
	table.sort(Flags)

	for _, Flag in ipairs(Flags) do
		local Element = Library.Elements[Flag]
		local Parser = Element and Parsers[Element.Type]

		if Parser and not SaveManager.Ignore[Flag] then
			local Ok, Object = pcall(Parser.Save, Element)
			if Ok and type(Object) == "table" then
				Object.type = Element.Type
				Object.idx = Flag
				table.insert(Data.objects, Object)
			end
		end
	end

	if SaveManager.SaveLayout then
		local Layout = {}

		if Library.MainWindow then
			Layout.window = EncodeUDim2(Library.MainWindow.OpenPosition)
		end

		Layout.notifications = EncodeUDim2(Library.NotificationAnchor)
		Data.layout = Layout
	end

	local EncodeOk, Encoded = pcall(HttpService.JSONEncode, HttpService, Data)
	if not EncodeOk then
		return false, "Failed to encode data"
	end

	local WriteOk, WriteError = pcall(writefile, ConfigPath, Encoded)
	if not WriteOk then
		return false, "Failed to write config file: " .. tostring(WriteError)
	end

	return true
end

function SaveManager:Load(ConfigName)
	if IsStringEmpty(ConfigName) then
		return false, "No config is selected"
	end

	local ConfigPath = GetConfigPath(ConfigName)
	if ConfigPath == false or not IsFile(ConfigPath) then
		return false, "Config file does not exist"
	end

	local ReadOk, Content = pcall(readfile, ConfigPath)
	if not ReadOk then
		return false, "Failed to read config file"
	end

	local DecodeOk, Decoded = pcall(HttpService.JSONDecode, HttpService, Content)
	if not DecodeOk or type(Decoded) ~= "table" or type(Decoded.objects) ~= "table" then
		return false, "Failed to decode config data"
	end

	local Library = SaveManager.Library

	if SaveManager.UseLoadingOrder and type(SaveManager.LoadingOrder) == "table" then
		local Order = SaveManager.LoadingOrder

		table.sort(Decoded.objects, function(A, B)
			return (table.find(Order, A.type) or math.huge) < (table.find(Order, B.type) or math.huge)
		end)
	end

	--// Layout (window + notification position)
	if SaveManager.SaveLayout and type(Decoded.layout) == "table" then
		local WindowPosition = DecodeUDim2(Decoded.layout.window)
		local Window = Library.MainWindow

		if Window and WindowPosition then
			Window.OpenPosition = WindowPosition
			Window.ClosedPosition = UDim2.new(WindowPosition.X.Scale, WindowPosition.X.Offset, 1.4, 0)

			if Window.Open then
				Library:Tween(Window.Instance, { Position = WindowPosition })
			end
		end

		local NotificationPosition = DecodeUDim2(Decoded.layout.notifications)
		if NotificationPosition then
			Library.NotificationAnchor = NotificationPosition

			if Library.AnchorFrame and Library.AnchorVisible then
				Library:Tween(Library.AnchorFrame, { Position = NotificationPosition })
			end

			Library:UpdateNotifications()
		end
	end

	--// Elements
	for _, Object in ipairs(Decoded.objects) do
		local Flag = Object.idx
		local Element = Flag and Library.Elements[Flag]
		local Parser = Element and Parsers[Object.type]

		if Parser and Element.Type == Object.type and not SaveManager.Ignore[Flag] then
			task.defer(function()
				local Ok, Err = pcall(Parser.Load, Element, Object)
				if not Ok then
					warn("[FeralUI] failed to load " .. tostring(Flag) .. ": " .. tostring(Err))
				end
			end)
		end
	end

	return true
end

function SaveManager:Delete(ConfigName)
	if IsStringEmpty(ConfigName) then
		return false, "No config is selected"
	end

	local ConfigPath = GetConfigPath(ConfigName)
	if ConfigPath == false or not IsFile(ConfigPath) then
		return false, "Config file does not exist"
	end

	local Ok, Err = pcall(delfile, ConfigPath)
	if not Ok then
		return false, "Failed to delete config file: " .. tostring(Err)
	end

	if ConfigName == SaveManager.AutoloadConfig then
		SaveManager:DeleteAutoLoadConfig()
	end

	return true
end

--// Autoload ----------------------------------------------------------------------------

function SaveManager:GetAutoloadConfig()
	SaveManager.AutoloadConfig = nil

	if not HasFS then
		return "none", false, "executor has no file functions"
	end

	SaveManager:CheckFolderTree()

	local AutoloadPath = GetAutoloadPath()
	if AutoloadPath == false then
		return "none", false, "Invalid path provided"
	end

	if not IsFile(AutoloadPath) then
		return "none", false, "Autoload config is not set"
	end

	local Ok, Name = pcall(readfile, AutoloadPath)
	if not (Ok and type(Name) == "string") then
		return "none", false, tostring(Name)
	end

	Name = Trim(Name)

	if not DoesConfigExist(Name) then
		return "none", false, "Config file not found"
	end

	SaveManager.AutoloadConfig = Name
	return Name, true
end

function SaveManager:SaveAutoloadConfig(ConfigName)
	if IsStringEmpty(ConfigName) then
		return false, "No config is selected"
	end

	SaveManager:CheckFolderTree()

	local AutoloadPath = GetAutoloadPath()
	if AutoloadPath == false then
		return false, "Invalid path provided"
	end

	if not DoesConfigExist(ConfigName) then
		return false, "Config does not exist"
	end

	local Ok, Err = pcall(writefile, AutoloadPath, ConfigName)
	if not Ok then
		return false, tostring(Err)
	end

	SaveManager.AutoloadConfig = ConfigName
	return true
end

function SaveManager:DeleteAutoLoadConfig()
	SaveManager:CheckFolderTree()

	local AutoloadPath = GetAutoloadPath()
	if AutoloadPath == false then
		return false, "Invalid path provided"
	end

	if not IsFile(AutoloadPath) then
		return false, "Autoload config is not set"
	end

	local Ok, Err = pcall(delfile, AutoloadPath)
	if not Ok then
		return false, tostring(Err)
	end

	SaveManager.AutoloadConfig = nil
	return true
end

function SaveManager:LoadAutoloadConfig()
	local Name, Success, FetchError = SaveManager:GetAutoloadConfig()
	if not Success then
		if FetchError ~= "Autoload config is not set" then
			Notify("Failed to load autoload config: " .. tostring(FetchError))
		end

		return
	end

	local LoadOk, LoadError = SaveManager:Load(Name)
	if not LoadOk then
		Notify("Failed to load autoload config: " .. tostring(LoadError))
		return
	end

	Notify(string.format("Successfully loaded autoload config %q", Name))
end

--// GUI -----------------------------------------------------------------------------------

local function ShowDialog(Condition, Title, Description, ConfirmText, Action)
	if not Condition() then
		return Action()
	end

	return SaveManager.Library:Dialog({
		Title = Title,
		Description = Description,
		ConfirmText = ConfirmText,
		Destructive = true,
		Callback = Action,
	})
end

--- Builds the "Configuration" section. Pass a SubTab (a new section is added, right side by default)
--- or an existing section object.
function SaveManager:BuildConfigSection(Tab, Side)
	assert(SaveManager.Library, "Library is not set, call SaveManager:SetLibrary(Library) first.")

	local Library = SaveManager.Library
	SaveManager:BuildFolderTree()

	local Section = Tab
	if type(Tab.AddSection) == "function" then
		Section = Tab:AddSection("Configuration", Side or "Right")
	end

	local ConfigNameInput, ConfigList, AutoloadLabel

	local function FormatConfig(Value)
		if Value ~= nil and Value == SaveManager.AutoloadConfig then
			return string.format("%s (autoload)", tostring(Value))
		end

		return tostring(Value)
	end

	local function RefreshList()
		ConfigList:Refresh(SaveManager:RefreshConfigList())
		ConfigList:Set(nil, true)
	end

	local function RefreshAutoloadLabel()
		local Name = SaveManager:GetAutoloadConfig()
		AutoloadLabel:Set(string.format("Current autoload config: %s", Name))
		RefreshList()
	end

	local function SelectedConfig()
		local Name = ConfigList.Value

		if IsStringEmpty(Name) then
			Notify("Please select a config first.")
			return nil
		end

		return Name
	end

	--// Create
	ConfigNameInput = Section:AddTextbox({
		Title = "Config name",
		Placeholder = "Config name...",
		Flag = "SaveManager_ConfigName",
	})

	Section:AddButton({
		Title = "Create config",
		Callback = function()
			-- read the box directly so text that hasn't lost focus yet is still picked up
			local Box = ConfigNameInput.Instance:FindFirstChild("input")
			local ConfigName = Box and Box.Text or ConfigNameInput.Value
			ConfigName = Trim(ConfigName or "")

			if ConfigName == "" then
				Notify("Configuration name cannot be empty.")
				return
			end

			if not IsValidConfigName(ConfigName) or string.lower(ConfigName) == "autoload" then
				Notify("Invalid config name provided.")
				return
			end

			ShowDialog(
				function()
					return DoesConfigExist(ConfigName)
				end,
				"Config already exists",
				string.format("A config named %q already exists. Overwriting will replace it with your current settings.", ConfigName),
				"Overwrite",
				function()
					local Ok, Err = SaveManager:Save(ConfigName)
					if not Ok then
						Notify(string.format("Failed to create config %q: %s", ConfigName, tostring(Err)))
						return
					end

					Notify(string.format("Successfully created config %q", ConfigName))
					RefreshList()
				end
			)
		end,
	})

	Section:AddDivider()

	--// Manage
	ConfigList = Section:AddDropdown({
		Title = "Config list",
		Options = SaveManager:RefreshConfigList(),
		Format = FormatConfig,
		Flag = "SaveManager_ConfigList",
	})
	ConfigList:Set(nil, true)

	Section:AddButton({
		Title = "Load config",
		Callback = function()
			local Name = SelectedConfig()
			if not Name then
				return
			end

			local Ok, Err = SaveManager:Load(Name)
			if not Ok then
				Notify(string.format("Failed to load config %q: %s", Name, tostring(Err)))
				return
			end

			Notify(string.format("Successfully loaded config %q", Name))
		end,
	})

	Section:AddButton({
		Title = "Overwrite config",
		Callback = function()
			local Name = SelectedConfig()
			if not Name then
				return
			end

			ShowDialog(
				function() return true end,
				"Overwrite config",
				string.format("Are you sure you want to overwrite %q with your current settings? This cannot be undone.", Name),
				"Overwrite",
				function()
					local Ok, Err = SaveManager:Save(Name)
					if not Ok then
						Notify(string.format("Failed to overwrite config %q: %s", Name, tostring(Err)))
						return
					end

					Notify(string.format("Successfully overwrote config %q", Name))
				end
			)
		end,
	})

	Section:AddButton({
		Title = "Delete config",
		Callback = function()
			local Name = SelectedConfig()
			if not Name then
				return
			end

			ShowDialog(
				function() return true end,
				"Delete config",
				string.format("Are you sure you want to delete %q? This cannot be undone.", Name),
				"Delete",
				function()
					local Ok, Err = SaveManager:Delete(Name)
					if not Ok then
						Notify(string.format("Failed to delete config %q: %s", Name, tostring(Err)))
						return
					end

					Notify(string.format("Successfully deleted config %q", Name))
					RefreshAutoloadLabel()
				end
			)
		end,
	})

	Section:AddButton({
		Title = "Refresh list",
		Callback = RefreshList,
	})

	--// Autoload
	Section:AddButton({
		Title = "Set as autoload",
		Callback = function()
			local Name = SelectedConfig()
			if not Name then
				return
			end

			local Ok, Err = SaveManager:SaveAutoloadConfig(Name)
			if not Ok then
				Notify(string.format("Failed to set autoload config %q: %s", Name, tostring(Err)))
				return
			end

			Notify(string.format("Successfully set autoload config to %q", Name))
			RefreshAutoloadLabel()
		end,
	})

	Section:AddButton({
		Title = "Reset autoload",
		Callback = function()
			ShowDialog(
				function() return true end,
				"Reset autoload config",
				"Are you sure you want to clear the autoload config? No config will be loaded automatically on next launch.",
				"Reset",
				function()
					local Ok, Err = SaveManager:DeleteAutoLoadConfig()
					if not Ok then
						Notify(string.format("Failed to reset autoload config: %s", tostring(Err)))
						return
					end

					Notify("Successfully reset autoload config.")
					RefreshAutoloadLabel()
				end
			)
		end,
	})

	AutoloadLabel = Section:AddLabel({ Title = "Current autoload config: ...", Dim = true })

	SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName" })
	RefreshAutoloadLabel()

	return Section
end

SaveManager:BuildFolderTree()
return SaveManager
