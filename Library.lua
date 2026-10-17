--[[
	Feral UI Library  v1.0.0
	Load it with:
		local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/<user>/<repo>/main/Library.lua"))()

	See README.md for the full API and Example.lua for a showcase of every element.
]]

--// Services
local cloneref = cloneref or function(Object) return Object end
local Players = cloneref(game:GetService("Players"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))
local HttpService = cloneref(game:GetService("HttpService"))
local TweenService = cloneref(game:GetService("TweenService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local Stats = cloneref(game:GetService("Stats"))

local Genv = (getgenv and getgenv()) or shared
local GetHui = gethui or function() return CoreGui end

--// Unload a previous instance so re-executing never stacks UIs
if Genv.Library and type(Genv.Library.Exit) == "function" then
	pcall(Genv.Library.Exit, Genv.Library)
end

local LocalPlayer = Players.LocalPlayer
local White = Color3.new(1, 1, 1)

local HasFS = (isfolder and makefolder and isfile and readfile and writefile) ~= nil

--// Library table
local Library = {
	Version = "1.0.0",

	Flags = {},       -- [Flag] = current value of every element that has a Flag
	SetFlags = {},    -- [Flag] = function(Value) used by the config system
	Keybind = Enum.KeyCode.X, -- key that opens / closes the menu

	Directory = "feral",
	Folders = { Assets = "Assets", Configs = "Configs" },

	Animation = { Time = 0.3, Style = "Exponential", Direction = "Out" },

	FontUrls = {
		Regular = "https://github.com/ilxypp/assets/raw/refs/heads/main/InterMedium.ttf",
		Bold = "https://github.com/ilxypp/assets/raw/refs/heads/main/InterBold.ttf",
	},
	Font = nil,
	FontBold = nil,

	Theme = {
		Accent = Color3.fromRGB(0, 131, 255),
		AccentDark = Color3.fromRGB(0, 63, 255),
		Window = Color3.fromRGB(21, 21, 22),
		WindowOutline = Color3.fromRGB(61, 61, 61),
		Panel = Color3.fromRGB(20, 20, 21),
		Tab = Color3.fromRGB(25, 25, 27),
		Section = Color3.fromRGB(24, 24, 26),
		Element = Color3.fromRGB(28, 28, 30),
		Outline = Color3.fromRGB(40, 40, 40),
		OutlineLight = Color3.fromRGB(60, 60, 60),
		Text = Color3.fromRGB(255, 255, 255),
		SubText = Color3.fromRGB(235, 235, 235),
		ToggleOn = Color3.fromRGB(29, 146, 234),
	},

	-- If clicks on dropdowns / colorpickers feel shifted vertically on your executor,
	-- set this to Vector2.new(0, -36) (or whatever your GuiInset is).
	MouseOffset = Vector2.new(0, 0),

	Connections = {},
	Threads = {},
	GradientTweens = {},
	ThemeItems = {},
	ThemeHooks = {},
	UnloadCallbacks = {},
	Popups = {},
	Notifications = {},

	NotificationAnchor = UDim2.new(0, 100, 0, 100),
	AnchorVisible = false,
	AnchorFrame = nil,

	ActivePopup = nil,
	Listening = false, -- true while a Keybind element waits for a key
	MainWindow = nil,
	Initialized = false,
	Unloaded = false,
}

--// Low level helpers --------------------------------------------------------

local function ResolveEnum(EnumType, Value, Default)
	if typeof(Value) == "EnumItem" then
		return Value
	end

	local Ok, Result = pcall(function()
		return EnumType[Value]
	end)

	return (Ok and Result) or Default
end

function Library:GetTweenInfo(Time)
	local Animation = self.Animation
	return TweenInfo.new(
		Time or Animation.Time,
		ResolveEnum(Enum.EasingStyle, Animation.Style, Enum.EasingStyle.Exponential),
		ResolveEnum(Enum.EasingDirection, Animation.Direction, Enum.EasingDirection.Out)
	)
end

local function Tween(Object, Properties, Info)
	if not Object then
		return
	end

	local NewTween = TweenService:Create(Object, Info or Library:GetTweenInfo(), Properties)
	NewTween:Play()
	return NewTween
end

function Library:Tween(Object, Properties, Info)
	return Tween(Object, Properties, Info)
end

function Library:TweenGradient(Gradient, Target, Info)
	if not Gradient then
		return
	end

	Info = Info or self:GetTweenInfo()

	local Existing = self.GradientTweens[Gradient]
	if Existing then
		Existing:Disconnect()
		self.GradientTweens[Gradient] = nil
	end

	local StartTime = os.clock()
	local From = Gradient.Transparency.Keypoints[1].Value
	local Connection

	Connection = RunService.RenderStepped:Connect(function()
		local Alpha = Info.Time > 0 and math.clamp((os.clock() - StartTime) / Info.Time, 0, 1) or 1
		local Eased = TweenService:GetValue(Alpha, Info.EasingStyle, Info.EasingDirection)
		Gradient.Transparency = NumberSequence.new(From + (Target - From) * Eased)

		if Alpha >= 1 then
			Connection:Disconnect()
			if Library.GradientTweens[Gradient] == Connection then
				Library.GradientTweens[Gradient] = nil
			end
		end
	end)

	self.GradientTweens[Gradient] = Connection
	return Connection
end

function Library:Connect(Signal, Callback)
	local Connection = Signal:Connect(Callback)
	table.insert(self.Connections, Connection)
	return Connection
end

function Library:Thread(Function)
	local Thread = task.spawn(Function)
	table.insert(self.Threads, Thread)
	return Thread
end

function Library:Call(Function, ...)
	if type(Function) ~= "function" then
		return
	end

	local Ok, Err = pcall(Function, ...)
	if not Ok then
		warn("[FeralUI] callback error: " .. tostring(Err))
	end
end

local function IsClick(Input)
	return Input.UserInputType == Enum.UserInputType.MouseButton1
		or Input.UserInputType == Enum.UserInputType.Touch
end

local function IsMove(Input)
	return Input.UserInputType == Enum.UserInputType.MouseMovement
		or Input.UserInputType == Enum.UserInputType.Touch
end

function Library:OnClick(Object, Callback)
	return self:Connect(Object.InputBegan, function(Input)
		if IsClick(Input) then
			Callback(Input)
		end
	end)
end

--// The holder uses IgnoreGuiInset, so GetMouseLocation() is already in the same
--// coordinate space as AbsolutePosition (no inset subtraction needed).
function Library:GetMouse()
	local Location = UserInputService:GetMouseLocation()
	return Vector2.new(Location.X + self.MouseOffset.X, Location.Y + self.MouseOffset.Y)
end

function Library:IsOver(Frame)
	if not Frame then
		return false
	end

	local Mouse = self:GetMouse()
	local Position, Size = Frame.AbsolutePosition, Frame.AbsoluteSize

	return Mouse.X >= Position.X and Mouse.X <= Position.X + Size.X
		and Mouse.Y >= Position.Y and Mouse.Y <= Position.Y + Size.Y
end

function Library:IsOverPopup()
	for _, Popup in ipairs(self.Popups) do
		if Popup.Parent and Popup.Visible and self:IsOver(Popup) then
			return true
		end
	end

	return false
end

--// Theme --------------------------------------------------------------------

local function Themed(Object, Map)
	for Property, Key in pairs(Map) do
		if type(Key) == "function" then
			Object[Property] = Key()
		else
			Object[Property] = Library.Theme[Key]
		end
	end

	table.insert(Library.ThemeItems, { Object, Map })
	return Object
end

--- Change one theme color (Key, Color) or many at once ({ Accent = ..., ... }).
function Library:SetTheme(Key, Color)
	if type(Key) == "table" then
		for Name, Value in pairs(Key) do
			self.Theme[Name] = Value
		end
	else
		self.Theme[Key] = Color
	end

	for Index = #self.ThemeItems, 1, -1 do
		local Item = self.ThemeItems[Index]
		local Object = Item[1]

		if not Object.Parent then
			table.remove(self.ThemeItems, Index)
		else
			for Property, ThemeKey in pairs(Item[2]) do
				if type(ThemeKey) == "function" then
					Object[Property] = ThemeKey()
				else
					Object[Property] = self.Theme[ThemeKey]
				end
			end
		end
	end

	for _, Hook in ipairs(self.ThemeHooks) do
		Library:Call(Hook)
	end
end

local function AccentSequence()
	return ColorSequence.new(Library.Theme.Accent, Library.Theme.AccentDark)
end

--// Instance helpers ---------------------------------------------------------

local function Create(Class, Properties, Parent)
	local Object = Instance.new(Class)

	if Properties then
		for Property, Value in pairs(Properties) do
			Object[Property] = Value
		end
	end

	if Parent then
		Object.Parent = Parent
	end

	return Object
end

local function Corner(Parent, Radius, Extra)
	local Object = Create("UICorner", { CornerRadius = UDim.new(0, Radius) }, Parent)

	if Extra then
		for Property, Value in pairs(Extra) do
			Object[Property] = Value
		end
	end

	return Object
end

local function Stroke(Parent, ColorKey)
	local Object = Create("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, Parent)
	return Themed(Object, { Color = ColorKey or "Outline" })
end

local function Padding(Parent, Top, Right, Left, Bottom)
	return Create("UIPadding", {
		PaddingTop = UDim.new(0, Top or 0),
		PaddingRight = UDim.new(0, Right or 0),
		PaddingLeft = UDim.new(0, Left or 0),
		PaddingBottom = UDim.new(0, Bottom or 0),
	}, Parent)
end

local function Gradient(Parent, Rotation)
	local Object = Create("UIGradient", { Rotation = Rotation or 0 }, Parent)
	return Themed(Object, { Color = AccentSequence })
end

local function List(Parent, PaddingPixels, Extra)
	local Object = Create("UIListLayout", {
		Padding = UDim.new(0, PaddingPixels or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, Parent)

	if Extra then
		for Property, Value in pairs(Extra) do
			Object[Property] = Value
		end
	end

	return Object
end

local function MakeLabel(Parent, Properties)
	Properties = Properties or {}

	local ColorKey = Properties.ColorKey or "Text"
	local Bold = Properties.Bold
	Properties.ColorKey = nil
	Properties.Bold = nil

	local Final = {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Bold and Library.FontBold or Library.Font,
	}

	for Property, Value in pairs(Properties) do
		Final[Property] = Value
	end

	local Label = Create("TextLabel", Final, Parent)
	Themed(Label, { TextColor3 = ColorKey })
	return Label
end

local function Draggable(Target, Handle, Options)
	Options = Options or {}

	local Dragging = false
	local DragStart, StartPosition
	local DragInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	Library:Connect(UserInputService.InputBegan, function(Input)
		if not IsClick(Input) then
			return
		end

		if Options.Condition and not Options.Condition() then
			return
		end

		if not Library:IsOver(Handle) then
			return
		end

		Dragging = true
		DragStart = Input.Position
		StartPosition = Target.Position

		if Options.OnStart then
			Options.OnStart()
		end
	end)

	Library:Connect(UserInputService.InputChanged, function(Input)
		if not Dragging or not IsMove(Input) then
			return
		end

		local Delta = Input.Position - DragStart
		local Position = UDim2.new(
			StartPosition.X.Scale, StartPosition.X.Offset + Delta.X,
			StartPosition.Y.Scale, StartPosition.Y.Offset + Delta.Y
		)

		Tween(Target, { Position = Position }, DragInfo)

		if Options.OnMove then
			Options.OnMove(Position)
		end
	end)

	Library:Connect(UserInputService.InputEnded, function(Input)
		if Dragging and IsClick(Input) then
			Dragging = false

			if Options.OnEnd then
				Options.OnEnd()
			end
		end
	end)
end

local function HexToColor(Hex)
	Hex = tostring(Hex):gsub("#", "")

	if #Hex ~= 6 then
		return nil
	end

	local R, G, B = tonumber(Hex:sub(1, 2), 16), tonumber(Hex:sub(3, 4), 16), tonumber(Hex:sub(5, 6), 16)
	if R and G and B then
		return Color3.fromRGB(R, G, B)
	end

	return nil
end

--// Setup: folders, fonts, holder -------------------------------------------

function Library:GetPath(...)
	return table.concat({ self.Directory, ... }, "/")
end

function Library:EnsureFolders()
	if not HasFS then
		return
	end

	pcall(function()
		if not isfolder(self.Directory) then
			makefolder(self.Directory)
		end

		for _, Folder in pairs(self.Folders) do
			local Path = self:GetPath(Folder)
			if not isfolder(Path) then
				makefolder(Path)
			end
		end
	end)
end

function Library:LoadFonts()
	if self.Font and self.FontBold then
		return
	end

	local CanLoad = HasFS and (getcustomasset or getsynasset)
	local GetAsset = getcustomasset or getsynasset

	local function Make(Name, Url)
		if not CanLoad then
			return nil
		end

		local Ok, Result = pcall(function()
			local TtfPath = self:GetPath(self.Folders.Assets, Name .. ".ttf")
			if not isfile(TtfPath) then
				writefile(TtfPath, game:HttpGet(Url))
			end

			local FontData = {
				name = Name,
				faces = { { name = Name, weight = 400, style = "Regular", assetId = GetAsset(TtfPath) } },
			}

			local FontPath = self:GetPath(self.Folders.Assets, Name .. ".font")
			writefile(FontPath, HttpService:JSONEncode(FontData))

			return Font.new(GetAsset(FontPath))
		end)

		if Ok then
			return Result
		end

		warn("[FeralUI] could not load font " .. Name .. ": " .. tostring(Result))
		return nil
	end

	self.Font = self.Font or Make("InterMedium", self.FontUrls.Regular) or Font.fromEnum(Enum.Font.GothamMedium)
	self.FontBold = self.FontBold or Make("InterBold", self.FontUrls.Bold) or Font.fromEnum(Enum.Font.GothamBold)
end

--- Use your own Font objects instead of the downloaded ones (call before creating a window).
function Library:SetFonts(Regular, Bold)
	self.Font = Regular or self.Font
	self.FontBold = Bold or Regular or self.FontBold
end

local Holder = Instance.new("ScreenGui")
Holder.Name = "\0"
Holder.IgnoreGuiInset = true
Holder.ResetOnSpawn = false
Holder.DisplayOrder = 10
Holder.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
	if syn and syn.protect_gui then
		syn.protect_gui(Holder)
	end
end)

do
	local Ok = pcall(function()
		Holder.Parent = GetHui()
	end)

	if not Ok or not Holder.Parent then
		Holder.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end
end

Library.Holder = Holder

function Library:Init()
	if self.Initialized then
		return
	end

	self.Initialized = true
	self:EnsureFolders()
	self:LoadFonts()
end

--// Lifetime ------------------------------------------------------------------

function Library:OnUnload(Callback)
	table.insert(self.UnloadCallbacks, Callback)
end

function Library:Exit()
	if self.Unloaded then
		return
	end

	self.Unloaded = true

	for _, Callback in ipairs(self.UnloadCallbacks) do
		Library:Call(Callback)
	end

	for _, Connection in ipairs(self.Connections) do
		pcall(function() Connection:Disconnect() end)
	end

	for _, Connection in pairs(self.GradientTweens) do
		pcall(function() Connection:Disconnect() end)
	end

	for _, Thread in ipairs(self.Threads) do
		pcall(task.cancel, Thread)
	end

	if self.Holder then
		self.Holder:Destroy()
	end

	if Genv.Library == self then
		Genv.Library = nil
	end
end

Library.Unload = Library.Exit

--// Menu visibility / key -----------------------------------------------------

function Library:SetMenuKey(Key)
	self.Keybind = ResolveEnum(Enum.KeyCode, Key, self.Keybind)
end

function Library:Toggle(Value)
	local Window = self.MainWindow
	if not Window then
		return
	end

	if Value == nil then
		Value = not Window.Open
	end

	Window:SetVisible(Value)
end

--// Flags ---------------------------------------------------------------------

function Library:Get(Flag)
	return self.Flags[Flag]
end

function Library:Set(Flag, Value)
	local Setter = self.SetFlags[Flag]
	if Setter then
		Setter(Value)
	end
end

--// Configs -------------------------------------------------------------------

function Library:GetConfig()
	local Data = {}

	for Flag, Value in pairs(self.Flags) do
		if typeof(Value) == "Color3" then
			Data[Flag] = { Color = Value:ToHex() }
		else
			Data[Flag] = Value
		end
	end

	local Ok, Result = pcall(function()
		return HttpService:JSONEncode(Data)
	end)

	if not Ok then
		warn("[FeralUI] failed to encode config: " .. tostring(Result))
		return nil
	end

	return Result
end

function Library:LoadConfig(Json)
	local Ok, Decoded = pcall(function()
		return HttpService:JSONDecode(Json)
	end)

	if not Ok then
		warn("[FeralUI] failed to decode config: " .. tostring(Decoded))
		return false
	end

	for Flag, Value in pairs(Decoded) do
		local Setter = self.SetFlags[Flag]
		if Setter then
			local Success, Err = pcall(Setter, Value)
			if not Success then
				warn("[FeralUI] failed to load flag " .. tostring(Flag) .. ": " .. tostring(Err))
			end
		end
	end

	return true
end

local function CleanName(Name)
	return (tostring(Name):gsub("[^%w_%-%s]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Library:ConfigPath(Name)
	return self:GetPath(self.Folders.Configs, CleanName(Name) .. ".json")
end

function Library:ListConfigs()
	local Out = {}
	if not HasFS or not listfiles then
		return Out
	end

	self:EnsureFolders()

	local Ok, Files = pcall(listfiles, self:GetPath(self.Folders.Configs))
	if Ok then
		for _, File in ipairs(Files) do
			local Name = tostring(File):match("([^/\\]+)%.json$")
			if Name then
				table.insert(Out, Name)
			end
		end
	end

	table.sort(Out)
	return Out
end

function Library:SaveConfig(Name)
	if not HasFS then
		return false, "executor has no file functions"
	end

	Name = CleanName(Name or "")
	if #Name == 0 then
		return false, "enter a name first"
	end

	local Json = self:GetConfig()
	if not Json then
		return false, "failed to encode"
	end

	self:EnsureFolders()
	local Ok, Err = pcall(writefile, self:ConfigPath(Name), Json)
	if not Ok then
		return false, tostring(Err)
	end

	return true
end

function Library:LoadConfigFile(Name)
	if not HasFS then
		return false, "executor has no file functions"
	end

	local Path = self:ConfigPath(Name or "")
	if not isfile(Path) then
		return false, "config does not exist"
	end

	return self:LoadConfig(readfile(Path))
end

function Library:DeleteConfig(Name)
	if not HasFS or not delfile then
		return false
	end

	local Path = self:ConfigPath(Name or "")
	if isfile(Path) then
		delfile(Path)
		return true
	end

	return false
end

function Library:SetAutoload(Name)
	if not HasFS then
		return false
	end

	self:EnsureFolders()
	writefile(self:GetPath("AutoLoad.json"), CleanName(Name))
	return true
end

--- Loads the config marked via "Set Auto-Load" in the config manager. Call it at the end of your script.
function Library:LoadAutoload()
	if not HasFS then
		return false
	end

	local Path = self:GetPath("AutoLoad.json")
	if not isfile(Path) then
		return false
	end

	local Name = readfile(Path)
	if not Name or #Name == 0 then
		return false
	end

	return self:LoadConfigFile(Name)
end

--// Notifications -------------------------------------------------------------

local NotificationHeight, NotificationGap = 60, 8

function Library:MakeNotification(Title, Description)
	self:Init()

	local Frame = Create("Frame", {
		Name = "notification",
		BorderSizePixel = 0,
		Size = UDim2.new(0, 200, 0, NotificationHeight),
		Visible = false,
		ZIndex = 8,
		Active = true,
	}, self.Holder)
	Themed(Frame, { BackgroundColor3 = "Panel" })
	Corner(Frame, 10)
	Stroke(Frame, "Outline")
	Padding(Frame, 5, 10, 15, 5)

	local Visual = Create("Frame", {
		Name = "visual",
		BorderSizePixel = 0,
		BackgroundColor3 = White,
		Size = UDim2.new(0, 3, 1, 0),
		Position = UDim2.new(0, -8, 0, 0),
	}, Frame)
	Corner(Visual, 10)
	Stroke(Visual, "Outline")
	Gradient(Visual, 90)

	local TitleLabel = MakeLabel(Frame, {
		Name = "title",
		Bold = true,
		TextSize = 16,
		Text = Title or "Title",
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 20),
	})
	Gradient(TitleLabel, 180)

	MakeLabel(Frame, {
		Name = "desc",
		Bold = true,
		ColorKey = "SubText",
		Text = Description or "description",
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 1, -20),
		Position = UDim2.new(0, 0, 0, 20),
	})

	return Frame
end

local function HiddenPosition(Position)
	return UDim2.new(Position.X.Scale, Position.X.Offset - 300, Position.Y.Scale, Position.Y.Offset)
end

function Library:GetNotificationSlot(Index)
	local Base = self.NotificationAnchor
	local Start = self.AnchorVisible and 1 or 0

	return UDim2.new(
		Base.X.Scale, Base.X.Offset,
		Base.Y.Scale, Base.Y.Offset + (Index - 1 + Start) * (NotificationHeight + NotificationGap)
	)
end

function Library:UpdateNotifications()
	for Index, Entry in ipairs(self.Notifications) do
		Tween(Entry.Frame, { Position = self:GetNotificationSlot(Index) })
	end
end

function Library:SetAnchorVisible(Value)
	self.AnchorVisible = Value

	if self.AnchorFrame then
		if Value then
			self.AnchorFrame.Position = HiddenPosition(self.NotificationAnchor)
			self.AnchorFrame.Visible = true
			Tween(self.AnchorFrame, { Position = self.NotificationAnchor })
		else
			self.AnchorFrame.Visible = false
		end
	end

	self:UpdateNotifications()
end

function Library:Notify(Title, Description, Duration)
	Duration = Duration or 3

	local Entry = { Frame = self:MakeNotification(Title, Description) }
	table.insert(self.Notifications, Entry)

	local Slot = self:GetNotificationSlot(#self.Notifications)
	Entry.Frame.Position = HiddenPosition(Slot)
	Entry.Frame.Visible = true
	Tween(Entry.Frame, { Position = Slot })

	self:Thread(function()
		task.wait(self.Animation.Time + Duration)

		local Out = Tween(Entry.Frame, { Position = HiddenPosition(Entry.Frame.Position) })
		local Index = table.find(self.Notifications, Entry)
		if Index then
			table.remove(self.Notifications, Index)
		end
		self:UpdateNotifications()

		if Out then
			Out.Completed:Connect(function()
				Entry.Frame:Destroy()
			end)
		else
			Entry.Frame:Destroy()
		end
	end)

	return Entry.Frame
end

--// Color picker (shared by Toggle:Color and Section:AddColorpicker) ----------

local function MakeColorPicker(Square, Options)
	local CP = {
		Value = Options.Default or White,
		Flag = Options.Flag,
		Callback = Options.Callback or function() end,
		IsOpen = false,
		Type = "Colorpicker",
	}

	local H, S, V = CP.Value:ToHSV()
	local CursorInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local Popup = Create("Frame", {
		Name = "colorpickerPopup",
		BorderSizePixel = 0,
		Size = UDim2.new(0, 180, 0, 150),
		Visible = false,
		ZIndex = 1000,
		Active = true,
	}, Library.Holder)
	Themed(Popup, { BackgroundColor3 = "Panel" })
	Corner(Popup, 10)
	Stroke(Popup, "OutlineLight")
	local PopupScale = Create("UIScale", { Scale = 0 }, Popup)
	table.insert(Library.Popups, Popup)

	local SV = Create("ImageLabel", {
		Name = "svSquare",
		BorderSizePixel = 0,
		BackgroundColor3 = White,
		Image = "rbxassetid://122155142257844",
		Size = UDim2.new(0, 130, 0, 130),
		Position = UDim2.new(0, 10, 0, 10),
		Active = true,
	}, Popup)
	Corner(SV, 5)
	Stroke(SV, "OutlineLight")

	local SVMarker = Create("Frame", {
		Name = "marker",
		BorderSizePixel = 0,
		BackgroundColor3 = White,
		Size = UDim2.new(0, 8, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, SV)
	Corner(SVMarker, 0, { CornerRadius = UDim.new(1, 0) })
	Create("UIStroke", { Color = White, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, SVMarker)

	local Hue = Create("Frame", {
		Name = "hueBar",
		BorderSizePixel = 0,
		BackgroundColor3 = White,
		Size = UDim2.new(0, 20, 0, 130),
		Position = UDim2.new(1, -30, 0, 10),
		Active = true,
	}, Popup)
	Corner(Hue, 5)
	Stroke(Hue, "OutlineLight")
	Create("UIGradient", {
		Rotation = 270,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.000, Color3.fromRGB(255, 0, 4)),
			ColorSequenceKeypoint.new(0.140, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(0.280, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(0.420, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(0.560, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.700, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.840, Color3.fromRGB(255, 140, 0)),
			ColorSequenceKeypoint.new(1.000, Color3.fromRGB(255, 0, 0)),
		}),
	}, Hue)

	local HueMarker = Create("Frame", {
		Name = "marker",
		BorderSizePixel = 0,
		BackgroundColor3 = White,
		Size = UDim2.new(1, 4, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
	}, Hue)
	Corner(HueMarker, 2)
	Create("UIStroke", { Color = White, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, HueMarker)

	local function Update(Silent)
		local Color = Color3.fromHSV(H, S, V)
		CP.Value = Color

		Square.BackgroundColor3 = Color
		SV.BackgroundColor3 = Color3.fromHSV(H, 1, 1)
		Tween(SVMarker, { Position = UDim2.new(S, 0, 1 - V, 0) }, CursorInfo)
		Tween(HueMarker, { Position = UDim2.new(0.5, 0, H, 0) }, CursorInfo)

		if CP.Flag then
			Library.Flags[CP.Flag] = Color
		end

		if not Silent then
			Library:Call(CP.Callback, Color)
		end
	end

	local DraggingSV, DraggingHue = false, false

	local function ApplyMouse()
		local Mouse = Library:GetMouse()

		if DraggingSV then
			local Position, Size = SV.AbsolutePosition, SV.AbsoluteSize
			S = math.clamp((Mouse.X - Position.X) / Size.X, 0, 1)
			V = 1 - math.clamp((Mouse.Y - Position.Y) / Size.Y, 0, 1)
			Update()
		elseif DraggingHue then
			local Position, Size = Hue.AbsolutePosition, Hue.AbsoluteSize
			H = math.clamp((Mouse.Y - Position.Y) / Size.Y, 0, 1)
			Update()
		end
	end

	Library:OnClick(SV, function()
		DraggingSV = true
		ApplyMouse()
	end)

	Library:OnClick(Hue, function()
		DraggingHue = true
		ApplyMouse()
	end)

	Library:Connect(UserInputService.InputChanged, function(Input)
		if IsMove(Input) and (DraggingSV or DraggingHue) then
			ApplyMouse()
		end
	end)

	Library:Connect(UserInputService.InputEnded, function(Input)
		if IsClick(Input) then
			DraggingSV, DraggingHue = false, false
		end
	end)

	function CP:Open()
		if Library.ActivePopup and Library.ActivePopup ~= self then
			Library.ActivePopup:Close()
		end

		Library.ActivePopup = self
		self.IsOpen = true

		local Mouse = Library:GetMouse()
		local Viewport = workspace.CurrentCamera.ViewportSize
		local X = math.clamp(Mouse.X, 0, math.max(Viewport.X - 180, 0))
		local Y = math.clamp(Mouse.Y, 0, math.max(Viewport.Y - 150, 0))

		Popup.Position = UDim2.new(0, X, 0, Y)
		Popup.Visible = true
		PopupScale.Scale = 0
		Tween(PopupScale, { Scale = 1 })
	end

	function CP:Close()
		self.IsOpen = false

		if Library.ActivePopup == self then
			Library.ActivePopup = nil
		end

		local Closing = Tween(PopupScale, { Scale = 0 })
		Closing.Completed:Connect(function()
			if not CP.IsOpen then
				Popup.Visible = false
			end
		end)
	end

	function CP:Toggle()
		if self.IsOpen then
			self:Close()
		else
			self:Open()
		end
	end

	--- Accepts a Color3, a hex string ("#RRGGBB") or { Color = "RRGGBB" } (config format).
	function CP:Set(Value, Silent)
		if type(Value) == "table" then
			Value = Value.Color
		end

		if type(Value) == "string" then
			Value = HexToColor(Value)
		end

		if typeof(Value) == "Color3" then
			H, S, V = Value:ToHSV()
			Update(Silent)
		end
	end

	Library:OnClick(Square, function()
		CP:Toggle()
	end)

	Library:Connect(UserInputService.InputBegan, function(Input)
		if not IsClick(Input) or not CP.IsOpen then
			return
		end

		if Library:IsOver(Popup) or Library:IsOver(Square) then
			return
		end

		CP:Close()
	end)

	if CP.Flag then
		Library.SetFlags[CP.Flag] = function(Value)
			CP:Set(Value)
		end
	end

	Update(true)
	return CP
end

--// Section elements ----------------------------------------------------------

local SectionMethods = {}

function SectionMethods:AddToggle(Config)
	Config = Config or {}

	local Toggle = {
		Title = Config.Title or "Toggle",
		Flag = Config.Flag,
		Value = Config.Default or false,
		Callback = Config.Callback or function() end,
		Type = "Toggle",
	}

	local Row = Create("Frame", {
		Name = "toggle",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 15),
		Active = true,
	}, self.Content)

	MakeLabel(Row, {
		Name = "label",
		Text = Toggle.Title,
		Size = UDim2.new(1, -60, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local Switch = Create("Frame", {
		Name = "toggleSwitch",
		BorderSizePixel = 0,
		Size = UDim2.new(0, 30, 1, 1),
		Position = UDim2.new(1, -30, 0, 1),
	}, Row)
	Themed(Switch, { BackgroundColor3 = "Section" })
	Corner(Switch, 5)
	Padding(Switch, 2, 3, 3, 0)

	local Circle = Create("Frame", {
		Name = "circle",
		BorderSizePixel = 0,
		BackgroundColor3 = White,
		Size = UDim2.new(0, 10, 0, 10),
	}, Switch)
	Corner(Circle, 5)

	local SwitchStroke = Stroke(Switch, "Outline")
	local SwitchGradient = Gradient(Switch, 180)
	SwitchGradient.Transparency = NumberSequence.new(1)

	function Toggle:Set(Value, Silent)
		self.Value = Value and true or false

		if self.Value then
			Tween(Circle, { Position = UDim2.new(1, -10, 0, 0) })
			Tween(SwitchStroke, { Color = Library.Theme.ToggleOn })
			Tween(Switch, { BackgroundColor3 = White })
			Library:TweenGradient(SwitchGradient, 0)
		else
			Tween(Circle, { Position = UDim2.new(0, 0, 0, 0) })
			Tween(SwitchStroke, { Color = Library.Theme.Outline })
			Tween(Switch, { BackgroundColor3 = Library.Theme.Section })
			Library:TweenGradient(SwitchGradient, 1)
		end

		if self.Flag then
			Library.Flags[self.Flag] = self.Value
		end

		if not Silent then
			Library:Call(self.Callback, self.Value)
		end
	end

	-- Optional colorpicker next to the switch
	local Square
	if Config.Color then
		Square = Create("Frame", {
			Name = "colorSquare",
			BorderSizePixel = 0,
			BackgroundColor3 = Config.Color,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, -50, 0.5, 0),
			Size = UDim2.new(0, 15, 0, 15),
			Active = true,
		}, Row)
		Corner(Square, 5)
		Stroke(Square, "Outline")

		Toggle.Colorpicker = MakeColorPicker(Square, {
			Default = Config.Color,
			Flag = Config.ColorFlag,
			Callback = Config.ColorCallback,
		})
	end

	Library:OnClick(Row, function()
		if Square and Library:IsOver(Square) then
			return
		end

		if Toggle.Colorpicker and Toggle.Colorpicker.IsOpen then
			return
		end

		Toggle:Set(not Toggle.Value)
	end)

	if Toggle.Flag then
		Library.SetFlags[Toggle.Flag] = function(Value)
			Toggle:Set(Value)
		end
		Library.Flags[Toggle.Flag] = Toggle.Value
	end

	table.insert(Library.ThemeHooks, function()
		Toggle:Set(Toggle.Value, true)
	end)

	Toggle.Instance = Row
	Toggle:Set(Toggle.Value, true)
	return Toggle
end

function SectionMethods:AddSlider(Config)
	Config = Config or {}

	local Slider = {
		Title = Config.Title or "Slider",
		Flag = Config.Flag,
		Min = Config.Min or 0,
		Max = Config.Max or 100,
		Decimals = Config.Decimals or 0,
		Prefix = Config.Prefix or "",
		Suffix = Config.Suffix or "",
		Value = Config.Default or Config.Min or 0,
		Callback = Config.Callback or function() end,
		Type = "Slider",
	}

	local Row = Create("Frame", {
		Name = "slider",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 30),
	}, self.Content)

	MakeLabel(Row, { Name = "title", Text = Slider.Title, Size = UDim2.new(1, 0, 0, 10) })
	local ValueLabel = MakeLabel(Row, {
		Name = "value",
		Bold = true,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 10),
	})

	local Pill = Create("Frame", {
		Name = "sliderPill",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 15),
		Position = UDim2.new(0, 0, 0, 15),
		Active = true,
		ClipsDescendants = true,
	}, Row)
	Themed(Pill, { BackgroundColor3 = "Element" })
	Corner(Pill, 5)
	Stroke(Pill, "Outline")

	local Fill = Create("ImageLabel", {
		Name = "fill",
		BorderSizePixel = 0,
		BackgroundColor3 = White,
		Image = "rbxassetid://100840949142258",
		Size = UDim2.new(0, 0, 1, 0),
	}, Pill)
	Corner(Fill, 5)
	Gradient(Fill, 180)

	local SliderInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function Format(Value)
		if Slider.Decimals > 0 then
			return string.format("%." .. Slider.Decimals .. "f", Value)
		end

		return tostring(math.floor(Value))
	end

	function Slider:Set(Value, Silent)
		Value = math.clamp(Value, self.Min, self.Max)

		if self.Decimals > 0 then
			local Multiplier = 10 ^ self.Decimals
			Value = math.floor(Value * Multiplier + 0.5) / Multiplier
		else
			Value = math.floor(Value + 0.5)
		end

		self.Value = Value

		local Alpha = (self.Max == self.Min) and 0 or (Value - self.Min) / (self.Max - self.Min)
		Tween(Fill, { Size = UDim2.new(Alpha, 0, 1, 0) }, SliderInfo)
		ValueLabel.Text = self.Prefix .. Format(Value) .. self.Suffix

		if self.Flag then
			Library.Flags[self.Flag] = Value
		end

		if not Silent then
			Library:Call(self.Callback, Value)
		end
	end

	local Dragging = false

	local function FromMouse()
		local Mouse = Library:GetMouse()
		local Position, Size = Pill.AbsolutePosition, Pill.AbsoluteSize
		local Alpha = math.clamp((Mouse.X - Position.X) / Size.X, 0, 1)
		Slider:Set(Slider.Min + Alpha * (Slider.Max - Slider.Min))
	end

	Library:OnClick(Pill, function()
		Dragging = true
		FromMouse()
	end)

	Library:Connect(UserInputService.InputChanged, function(Input)
		if Dragging and IsMove(Input) then
			FromMouse()
		end
	end)

	Library:Connect(UserInputService.InputEnded, function(Input)
		if IsClick(Input) then
			Dragging = false
		end
	end)

	if Slider.Flag then
		Library.SetFlags[Slider.Flag] = function(Value)
			Slider:Set(tonumber(Value) or Slider.Min)
		end
	end

	Slider.Instance = Row
	Slider:Set(Slider.Value, true)
	return Slider
end

function SectionMethods:AddDropdown(Config)
	Config = Config or {}

	local Dropdown = {
		Title = Config.Title or "Dropdown",
		Flag = Config.Flag,
		Options = Config.Options or {},
		Multi = Config.Multi or false,
		IsOpen = false,
		Callback = Config.Callback or function() end,
		Type = "Dropdown",
	}

	if Dropdown.Multi then
		Dropdown.Value = {}

		if type(Config.Default) == "table" then
			for _, Option in ipairs(Config.Default) do
				table.insert(Dropdown.Value, Option)
			end
		elseif type(Config.Default) == "string" then
			Dropdown.Value = { Config.Default }
		end
	else
		Dropdown.Value = Config.Default or Dropdown.Options[1]
	end

	local Row = Create("Frame", {
		Name = "dropdown",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 40),
	}, self.Content)

	MakeLabel(Row, { Name = "title", Text = Dropdown.Title, Size = UDim2.new(1, 0, 0, 10) })

	local Pill = Create("Frame", {
		Name = "dropdownPill",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 25),
		Position = UDim2.new(0, 0, 0, 15),
		Active = true,
	}, Row)
	Themed(Pill, { BackgroundColor3 = "Element" })
	Corner(Pill, 5)
	Stroke(Pill, "Outline")
	Padding(Pill, 5, 5, 5, 5)

	local Items = MakeLabel(Pill, {
		Name = "items",
		Text = "",
		Size = UDim2.new(1, -15, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local Arrow = Create("ImageLabel", {
		Name = "arrow",
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 15, 0, 15),
		Image = "rbxassetid://116827751679514",
	}, Pill)

	local ListFrame = Create("Frame", {
		Name = "dropdownList",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.new(0, 0, 0, 45),
		Visible = false,
	}, Row)
	Themed(ListFrame, { BackgroundColor3 = "Element" })
	Corner(ListFrame, 5)
	Stroke(ListFrame, "Outline")
	Padding(ListFrame, 5, 5, 5, 5)
	List(ListFrame, 5, { HorizontalFlex = Enum.UIFlexAlignment.Fill })

	local ItemLabels = {}

	local function IsSelected(Option)
		if Dropdown.Multi then
			return table.find(Dropdown.Value, Option) ~= nil
		end

		return Dropdown.Value == Option
	end

	local function RefreshPill()
		if Dropdown.Multi then
			Items.Text = (#Dropdown.Value == 0) and "None" or table.concat(Dropdown.Value, ", ")
		else
			Items.Text = Dropdown.Value and tostring(Dropdown.Value) or "None"
		end
	end

	local function RefreshItems()
		for Option, Label in pairs(ItemLabels) do
			Label.FontFace = IsSelected(Option) and Library.FontBold or Library.Font
		end
	end

	function Dropdown:Set(Value, Silent)
		if self.Multi then
			local Copy = {}

			if type(Value) == "table" then
				for _, Option in ipairs(Value) do
					table.insert(Copy, Option)
				end
			elseif type(Value) == "string" then
				Copy = { Value }
			end

			self.Value = Copy
		else
			self.Value = Value
		end

		RefreshPill()
		RefreshItems()

		if self.Flag then
			Library.Flags[self.Flag] = self.Value
		end

		if not Silent then
			Library:Call(self.Callback, self.Value)
		end
	end

	function Dropdown:Open()
		self.IsOpen = true
		ListFrame.AutomaticSize = Enum.AutomaticSize.Y
		ListFrame.Visible = true
		Tween(Arrow, { Rotation = 180 })
	end

	function Dropdown:Close()
		self.IsOpen = false
		ListFrame.AutomaticSize = Enum.AutomaticSize.None
		ListFrame.Size = UDim2.new(1, 0, 0, 0)
		ListFrame.Visible = false
		Tween(Arrow, { Rotation = 0 })
	end

	function Dropdown:Toggle()
		if self.IsOpen then
			self:Close()
		else
			self:Open()
		end
	end

	function Dropdown:ToggleOption(Option)
		if self.Multi then
			local Index = table.find(self.Value, Option)
			if Index then
				table.remove(self.Value, Index)
			else
				table.insert(self.Value, Option)
			end

			self:Set(self.Value)
		else
			self:Set(Option)
			self:Close()
		end
	end

	local function BuildItems()
		for _, Label in pairs(ItemLabels) do
			Label:Destroy()
		end
		ItemLabels = {}

		for _, Option in ipairs(Dropdown.Options) do
			local Item = MakeLabel(ListFrame, {
				Name = "item",
				Text = tostring(Option),
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				Active = true,
			})

			Library:OnClick(Item, function()
				Dropdown:ToggleOption(Option)
			end)

			ItemLabels[Option] = Item
		end

		RefreshItems()
	end

	--- Replace the option list (and optionally the selection).
	function Dropdown:Refresh(Options, Default)
		self.Options = Options or {}
		BuildItems()

		if Default ~= nil then
			self:Set(Default, true)
		elseif not self.Multi and not table.find(self.Options, self.Value) then
			self:Set(self.Options[1], true)
		else
			RefreshPill()
		end
	end

	Library:OnClick(Pill, function()
		Dropdown:Toggle()
	end)

	Library:Connect(UserInputService.InputBegan, function(Input)
		if IsClick(Input) and Dropdown.IsOpen then
			if not Library:IsOver(Pill) and not Library:IsOver(ListFrame) then
				Dropdown:Close()
			end
		end
	end)

	BuildItems()
	RefreshPill()

	if Dropdown.Flag then
		Library.SetFlags[Dropdown.Flag] = function(Value)
			Dropdown:Set(Value)
		end
		Library.Flags[Dropdown.Flag] = Dropdown.Value
	end

	Dropdown.Instance = Row
	return Dropdown
end

function SectionMethods:AddTextbox(Config)
	Config = Config or {}

	local Textbox = {
		Title = Config.Title or "Textbox",
		Flag = Config.Flag,
		Value = Config.Default or "",
		Callback = Config.Callback or function() end,
		Type = "Textbox",
	}

	local Row = Create("Frame", {
		Name = "textbox",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 25),
	}, self.Content)

	local Box = Create("TextBox", {
		Name = "input",
		BorderSizePixel = 0,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Library.Font,
		ClearTextOnFocus = false,
		PlaceholderText = Config.Placeholder or "text...",
		Size = UDim2.new(1, 0, 1, 0),
		Text = Textbox.Value,
	}, Row)
	Themed(Box, { BackgroundColor3 = "Element", TextColor3 = "Text" })
	Corner(Box, 5)
	Stroke(Box, "Outline")
	Padding(Box, 5, 5, 5, 5)

	if Config.Icon then
		Create("ImageLabel", {
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -15, 0, 0),
			Size = UDim2.new(0, 15, 0, 15),
			Image = Config.Icon,
		}, Box)
	end

	function Textbox:Set(Value, Animate, Silent)
		Value = tostring(Value)

		if Animate then
			Library:Thread(function()
				for Index = 1, #Value do
					Box.Text = string.sub(Value, 1, Index)
					task.wait(0.02)
				end
			end)
		else
			Box.Text = Value
		end

		self.Value = Value

		if self.Flag then
			Library.Flags[self.Flag] = Value
		end

		if not Silent then
			Library:Call(self.Callback, Value)
		end
	end

	Library:Connect(Box.FocusLost, function()
		Textbox:Set(Box.Text, false)
	end)

	if Textbox.Flag then
		Library.SetFlags[Textbox.Flag] = function(Value)
			Textbox:Set(Value, false)
		end
		Library.Flags[Textbox.Flag] = Textbox.Value
	end

	Textbox.Instance = Row
	return Textbox
end

function SectionMethods:AddTextIndicator(Config)
	Config = Config or {}

	local Indicator = {
		Title = Config.Title or "Indicator",
		Flag = Config.Flag,
		Value = Config.Default or "",
		Type = "TextIndicator",
	}

	local Row = Create("Frame", {
		Name = "textindication",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 25),
	}, self.Content)

	local Box = Create("TextBox", {
		Name = "input",
		BorderSizePixel = 0,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Library.Font,
		ClearTextOnFocus = false,
		TextEditable = false,
		Active = false,
		Selectable = false,
		PlaceholderText = Config.Placeholder or "",
		Size = UDim2.new(1, 0, 1, 0),
		Text = Indicator.Value,
	}, Row)
	Themed(Box, { BackgroundColor3 = "Element", TextColor3 = "Text" })
	Corner(Box, 5)
	Stroke(Box, "Outline")
	Padding(Box, 5, 5, 5, 5)

	if Config.Icon then
		Create("ImageLabel", {
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -15, 0, 0),
			Size = UDim2.new(0, 15, 0, 15),
			Image = Config.Icon,
		}, Box)
	end

	function Indicator:Set(Value, Animate)
		Value = tostring(Value)

		if Animate then
			Library:Thread(function()
				for Index = 1, #Value do
					Box.Text = string.sub(Value, 1, Index)
					task.wait(0.02)
				end
			end)
		else
			Box.Text = Value
		end

		self.Value = Value

		if self.Flag then
			Library.Flags[self.Flag] = Value
		end
	end

	if Indicator.Flag then
		Library.SetFlags[Indicator.Flag] = function(Value)
			Indicator:Set(Value, false)
		end
		Library.Flags[Indicator.Flag] = Indicator.Value
	end

	Indicator.Instance = Row
	return Indicator
end

function SectionMethods:AddColorpicker(Config)
	Config = Config or {}

	local Row = Create("Frame", {
		Name = "colorpicker",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 15),
	}, self.Content)

	MakeLabel(Row, { Name = "title", Text = Config.Title or "Colorpicker", Size = UDim2.new(1, -50, 1, 0) })

	local Square = Create("Frame", {
		Name = "square",
		BorderSizePixel = 0,
		BackgroundColor3 = Config.Default or White,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, -15, 0.5, 0),
		Size = UDim2.new(0, 15, 0, 15),
		Active = true,
	}, Row)
	Corner(Square, 5)
	Stroke(Square, "Outline")

	local CP = MakeColorPicker(Square, {
		Default = Config.Default,
		Flag = Config.Flag,
		Callback = Config.Callback,
	})

	CP.Title = Config.Title or "Colorpicker"
	CP.Instance = Row
	return CP
end

function SectionMethods:AddButton(Config)
	Config = Config or {}

	local Button = {
		Title = Config.Title or "Button",
		Callback = Config.Callback or function() end,
		Type = "Button",
	}

	local Frame = Create("TextButton", {
		Name = "button",
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = Library.FontBold,
		Text = Button.Title,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 25),
	}, self.Content)
	Themed(Frame, { BackgroundColor3 = "Element", TextColor3 = "Text" })
	Corner(Frame, 5)
	local FrameStroke = Stroke(Frame, "Outline")

	Library:Connect(Frame.MouseEnter, function()
		Tween(FrameStroke, { Color = Library.Theme.ToggleOn })
	end)

	Library:Connect(Frame.MouseLeave, function()
		Tween(FrameStroke, { Color = Library.Theme.Outline })
	end)

	Library:OnClick(Frame, function()
		Library:Call(Button.Callback)
	end)

	function Button:SetText(Text)
		self.Title = Text
		Frame.Text = Text
	end

	Button.Instance = Frame
	return Button
end

function SectionMethods:AddLabel(Config)
	if type(Config) == "string" then
		Config = { Title = Config }
	end
	Config = Config or {}

	local Label = { Value = Config.Title or "Label", Type = "Label" }

	local Object = MakeLabel(self.Content, {
		Name = "label",
		Text = Label.Value,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		ColorKey = Config.Dim and "SubText" or "Text",
	})

	function Label:Set(Text)
		self.Value = Text
		Object.Text = Text
	end

	Label.Instance = Object
	return Label
end

function SectionMethods:AddDivider()
	local Line = Create("Frame", {
		Name = "divider",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
	}, self.Content)
	Themed(Line, { BackgroundColor3 = "Outline" })

	return { Instance = Line, Type = "Divider" }
end

function SectionMethods:AddKeybind(Config)
	Config = Config or {}

	local Keybind = {
		Title = Config.Title or "Keybind",
		Flag = Config.Flag,
		Mode = Config.Mode or "Press", -- Press | Toggle | Hold
		Key = nil,
		State = false,
		Callback = Config.Callback or function() end,
		ChangedCallback = Config.ChangedCallback or function() end,
		Type = "Keybind",
	}

	local Row = Create("Frame", {
		Name = "keybind",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 15),
	}, self.Content)

	MakeLabel(Row, { Name = "title", Text = Keybind.Title, Size = UDim2.new(1, -60, 1, 0) })

	local Button = Create("TextButton", {
		Name = "key",
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = Library.FontBold,
		TextSize = 12,
		Text = "None",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -1),
		Size = UDim2.new(0, 0, 1, 2),
		AutomaticSize = Enum.AutomaticSize.X,
	}, Row)
	Themed(Button, { BackgroundColor3 = "Element", TextColor3 = "Text" })
	Corner(Button, 5)
	Stroke(Button, "Outline")
	Padding(Button, 0, 6, 6, 0)

	local Listening = false

	function Keybind:Set(Key, Silent)
		if type(Key) == "string" then
			Key = (Key ~= "None") and ResolveEnum(Enum.KeyCode, Key, nil) or nil
		end

		self.Key = Key
		self.State = false
		Button.Text = Key and Key.Name or "None"

		if self.Flag then
			Library.Flags[self.Flag] = Key and Key.Name or "None"
		end

		if not Silent then
			Library:Call(self.ChangedCallback, Key)
		end
	end

	function Keybind:GetState()
		return self.State
	end

	Library:OnClick(Button, function()
		if Listening then
			return
		end

		Listening = true
		Library.Listening = true
		Button.Text = "..."
	end)

	Library:Connect(UserInputService.InputBegan, function(Input, Processed)
		if Listening then
			if Input.UserInputType == Enum.UserInputType.Keyboard then
				Listening = false
				task.defer(function()
					Library.Listening = false
				end)

				if Input.KeyCode == Enum.KeyCode.Escape then
					Keybind:Set(nil)
				else
					Keybind:Set(Input.KeyCode)
				end
			end

			return
		end

		if Processed or UserInputService:GetFocusedTextBox() then
			return
		end

		if not Keybind.Key or Input.KeyCode ~= Keybind.Key then
			return
		end

		if Keybind.Mode == "Toggle" then
			Keybind.State = not Keybind.State
		elseif Keybind.Mode == "Hold" then
			Keybind.State = true
		else
			Keybind.State = true
		end

		Library:Call(Keybind.Callback, Keybind.State)

		if Keybind.Mode == "Press" then
			Keybind.State = false
		end
	end)

	Library:Connect(UserInputService.InputEnded, function(Input)
		if Keybind.Mode == "Hold" and Keybind.Key and Input.KeyCode == Keybind.Key and Keybind.State then
			Keybind.State = false
			Library:Call(Keybind.Callback, false)
		end
	end)

	if Keybind.Flag then
		Library.SetFlags[Keybind.Flag] = function(Value)
			Keybind:Set(Value)
		end
	end

	Keybind:Set(Config.Default, true)
	Keybind.Instance = Row
	return Keybind
end

function SectionMethods:AddConfigManager()
	local Manager = { Selected = nil, Type = "ConfigManager" }

	local Frame = Create("Frame", {
		Name = "configmanager",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	}, self.Content)
	List(Frame, 5)

	MakeLabel(Frame, { Text = "Config Manager", Size = UDim2.new(1, 0, 0, 10) })

	local Selected = Create("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 25) }, Frame)
	Themed(Selected, { BackgroundColor3 = "Element" })
	Corner(Selected, 5)
	Stroke(Selected, "Outline")
	Padding(Selected, 5, 5, 5, 5)

	local SelectedLabel = MakeLabel(Selected, {
		Text = "selected: none",
		Size = UDim2.new(1, 0, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local ListFrame = Create("Frame", {
		Name = "list",
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
	}, Frame)
	Themed(ListFrame, { BackgroundColor3 = "Element" })
	Corner(ListFrame, 5)
	Stroke(ListFrame, "Outline")
	Padding(ListFrame, 5, 5, 5, 5)
	List(ListFrame, 5, { HorizontalFlex = Enum.UIFlexAlignment.Fill })

	local NameBox = Create("TextBox", {
		BorderSizePixel = 0,
		FontFace = Library.Font,
		TextSize = 14,
		ClearTextOnFocus = false,
		PlaceholderText = "Config name...",
		Text = "",
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Frame)
	Themed(NameBox, { BackgroundColor3 = "Element", TextColor3 = "Text" })
	Corner(NameBox, 4)
	Stroke(NameBox, "Outline")
	Padding(NameBox, 0, 6, 6, 0)

	local function MakeRow()
		local Row = Create("Frame", {
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 20),
		}, Frame)
		List(Row, 5, {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalFlex = Enum.UIFlexAlignment.Fill,
		})
		return Row
	end

	local function MakeButton(Parent, Text, OnClick)
		local Button = Create("TextButton", {
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			FontFace = Library.FontBold,
			Text = Text,
			TextSize = 14,
			AutoButtonColor = false,
		}, Parent)
		Themed(Button, { BackgroundColor3 = "Element", TextColor3 = "Text" })
		Corner(Button, 4)
		Stroke(Button, "Outline")
		Library:OnClick(Button, OnClick)
		return Button
	end

	local function Select(Name)
		Manager.Selected = Name
		SelectedLabel.Text = "selected: " .. (Name or "none")
	end

	function Manager:Refresh()
		for _, Child in ipairs(ListFrame:GetChildren()) do
			if Child:IsA("TextLabel") then
				Child:Destroy()
			end
		end

		for _, Name in ipairs(Library:ListConfigs()) do
			local Item = MakeLabel(ListFrame, {
				Text = Name,
				Bold = (Name == Manager.Selected),
				Size = UDim2.new(1, 0, 0, 18),
				AutomaticSize = Enum.AutomaticSize.Y,
				Active = true,
			})

			Library:OnClick(Item, function()
				Select(Name)
				Manager:Refresh()
			end)
		end
	end

	local Row1 = MakeRow()
	MakeButton(Row1, "Refresh", function()
		Manager:Refresh()
	end)
	MakeButton(Row1, "Set Auto-Load", function()
		if Manager.Selected and Library:SetAutoload(Manager.Selected) then
			Library:Notify("Config", "Auto-Load set to " .. Manager.Selected)
		end
	end)

	local Row2 = MakeRow()
	MakeButton(Row2, "Delete", function()
		if Manager.Selected then
			Library:DeleteConfig(Manager.Selected)
			Select(nil)
			Manager:Refresh()
		end
	end)
	MakeButton(Row2, "New", function()
		local Name = CleanName(NameBox.Text)
		if #Name == 0 then
			Name = "config_" .. tostring(os.time())
		end

		Select(Name)
		Manager:Refresh()
	end)

	local Row3 = MakeRow()
	MakeButton(Row3, "Save", function()
		local Name = Manager.Selected or CleanName(NameBox.Text)
		local Ok, Err = Library:SaveConfig(Name)

		if not Ok then
			Library:Notify("Config", "Save failed: " .. tostring(Err))
			return
		end

		Select(Name)
		Manager:Refresh()
		Library:Notify("Config", "Saved " .. Name)
	end)
	MakeButton(Row3, "Load", function()
		if not Manager.Selected then
			Library:Notify("Config", "Select a config first")
			return
		end

		local Ok, Err = Library:LoadConfigFile(Manager.Selected)
		if Ok then
			Library:Notify("Config", "Loaded " .. Manager.Selected)
		else
			Library:Notify("Config", "Load failed: " .. tostring(Err))
		end
	end)

	Manager.Instance = Frame
	Manager:Refresh()
	return Manager
end

--// Window --------------------------------------------------------------------

function Library:Window(Config)
	Config = Config or {}
	self:Init()

	local Window = {
		Title = Config.Title or "Feral Hub",
		GameName = Config.GameName or "Some game",
		Logo = Config.Logo or "rbxassetid://121449270899000",
		Open = true,
		Tabs = {},
		OpenPosition = UDim2.new(0.5, 0, 0.5, 0),
		ClosedPosition = UDim2.new(0.5, 0, 1.4, 0),
	}

	if Config.Keybind then
		self:SetMenuKey(Config.Keybind)
	end

	--// Main frame
	local Main = Create("Frame", {
		Name = "window",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 650, 0, 450),
		Position = Window.OpenPosition,
	}, self.Holder)
	Themed(Main, { BackgroundColor3 = "Window" })
	Corner(Main, 10)
	local MainStroke = Stroke(Main, "WindowOutline")

	local Top = Create("Frame", {
		Name = "top",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 60),
	}, Main)
	Corner(Top, 10, { BottomLeftRadius = UDim.new(0, 0), BottomRightRadius = UDim.new(0, 0) })
	Stroke(Top, "OutlineLight")
	Padding(Top, 5, 5, 5, 5)
	List(Top, 5, { FillDirection = Enum.FillDirection.Horizontal })

	local HubInfo = Create("ImageLabel", {
		Name = "hubInfo",
		BorderSizePixel = 0,
		BackgroundColor3 = White,
		Image = "rbxassetid://100840949142258",
		Size = UDim2.new(0, 162, 0, 50),
	}, Top)
	Corner(HubInfo, 5)
	Padding(HubInfo, 5, 5, 5, 5)
	Gradient(HubInfo, 90)

	local HubLogo = Create("ImageLabel", {
		Name = "logo",
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Image = Window.Logo,
		Size = UDim2.new(0, 35, 0, 35),
		Position = UDim2.new(0, 0, 0, 2),
	}, HubInfo)

	local HubTitle = MakeLabel(HubInfo, {
		Name = "title",
		Bold = true,
		TextSize = 16,
		TextWrapped = true,
		Text = tostring(Window.Title),
		Size = UDim2.new(1, -40, 0, 15),
		Position = UDim2.new(0, 40, 0, 5),
	})

	local HubGame = MakeLabel(HubInfo, {
		Name = "gamename",
		Bold = true,
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = tostring(Window.GameName),
		Size = UDim2.new(1, -40, 0, 15),
		Position = UDim2.new(0, 40, 0, 20),
	})

	function Window:SetTitle(Text)
		self.Title = Text
		HubTitle.Text = tostring(Text)
	end

	function Window:SetGameName(Text)
		self.GameName = Text
		HubGame.Text = tostring(Text)
	end

	function Window:SetLogo(Image)
		self.Logo = Image
		HubLogo.Image = Image
	end

	--// Dragging (top bar)
	Draggable(Main, Top, {
		Condition = function()
			return Window.Open and not Library:IsOverPopup()
		end,
		OnStart = function()
			Tween(MainStroke, { Color = Color3.fromRGB(80, 80, 80) })
		end,
		OnEnd = function()
			Tween(MainStroke, { Color = Library.Theme.WindowOutline })
		end,
	})

	--// Show / hide
	function Window:SetVisible(Value)
		if self.Open == Value then
			return
		end

		self.Open = Value

		if Library.ActivePopup then
			Library.ActivePopup:Close()
		end

		if Value then
			Main.Visible = true
			Main.Position = self.ClosedPosition
			Tween(Main, { Position = self.OpenPosition })
		else
			local Closing = Tween(Main, { Position = self.ClosedPosition })
			Closing.Completed:Connect(function()
				if not Window.Open then
					Main.Visible = false
				end
			end)
		end

		if Config.NotificationAnchor ~= false then
			Library:SetAnchorVisible(Value)
		end
	end

	function Window:Toggle()
		self:SetVisible(not self.Open)
	end

	Library:Connect(UserInputService.InputBegan, function(Input)
		if Library.Listening or UserInputService:GetFocusedTextBox() then
			return
		end

		if Input.KeyCode == Library.Keybind then
			Window:SetVisible(not Window.Open)
		end
	end)

	--// Watermark
	local Watermark = Create("Frame", {
		Name = "watermark",
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 30),
		Position = UDim2.new(0.5, -100, 0.1, 0),
		Visible = Config.Watermark ~= false,
		ZIndex = 5,
		Active = true,
	}, self.Holder)
	Themed(Watermark, { BackgroundColor3 = "Panel" })
	Corner(Watermark, 10)
	Stroke(Watermark, "Outline")
	Padding(Watermark, 5, 10, 10, 5)
	List(Watermark, 5, { FillDirection = Enum.FillDirection.Horizontal })

	local WatermarkLogo = Create("ImageLabel", {
		Name = "logo",
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 20, 1, 0),
		Image = "rbxassetid://104479390541433",
	}, Watermark)
	Gradient(WatermarkLogo, 90)

	local WatermarkText = MakeLabel(Watermark, {
		Name = "text",
		Bold = true,
		TextSize = 16,
		Text = Window.Title,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
	})

	Draggable(Watermark, Watermark, {
		Condition = function()
			return Window.Open
		end,
	})

	function Window:SetWatermark(Text, Logo)
		if Text then
			WatermarkText.Text = Text
		end

		if Logo then
			WatermarkLogo.Image = Logo
		end
	end

	function Window:SetWatermarkVisible(Value)
		Watermark.Visible = Value
	end

	--// Notification anchor (a draggable demo notification shown while the menu is open)
	if Config.NotificationAnchor ~= false then
		local Anchor = Library:MakeNotification("Example", "Drag me to reposition")
		Anchor.Name = "notificationAnchor"
		Anchor.ZIndex = 7
		Anchor.Position = Library.NotificationAnchor
		Library.AnchorFrame = Anchor

		Draggable(Anchor, Anchor, {
			Condition = function()
				return Library.AnchorVisible
			end,
			OnMove = function(Position)
				Library.NotificationAnchor = Position
				Library:UpdateNotifications()
			end,
		})

		Library:SetAnchorVisible(true)
	end

	--// Pills (small info boxes next to the title)
	local function DarkerAccent(Color)
		return Color3.new(math.max(0, Color.R - 0.27), math.max(0, Color.G - 0.27), math.max(0, Color.B - 0.27))
	end

	function Window:AddCustomPill(Title, Description, Logo, Accent)
		Accent = Accent or Library.Theme.Accent

		local Pill = {
			Title = Title or "Pill",
			Description = Description or "",
			Logo = Logo or Window.Logo,
			AccentColor = Accent,
		}

		local Frame = Create("Frame", {
			Name = "customPill",
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, 50),
		}, Top)
		Corner(Frame, 5)
		Stroke(Frame, "Outline")
		Padding(Frame, 5, 10, 5, 5)

		local PillLogo = Create("ImageLabel", {
			Name = "logo",
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			Image = Pill.Logo,
			Size = UDim2.new(0, 35, 0, 35),
			Position = UDim2.new(0, 0, 0, 2),
		}, Frame)

		local PillGradient = Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Accent, DarkerAccent(Accent)),
		}, PillLogo)

		local PillTitle = MakeLabel(Frame, {
			Name = "title",
			Bold = true,
			TextSize = 16,
			Text = Pill.Title,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, 15),
			Position = UDim2.new(0, 40, 0, 5),
		})

		local PillDescription = MakeLabel(Frame, {
			Name = "desc",
			Bold = true,
			ColorKey = "SubText",
			Text = Pill.Description,
			TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, 15),
			Position = UDim2.new(0, 40, 0, 20),
		})

		function Pill:Set(NewTitle, NewDescription, NewLogo)
			if NewTitle ~= nil then
				self.Title = NewTitle
				PillTitle.Text = tostring(NewTitle)
			end

			if NewDescription ~= nil then
				self.Description = NewDescription
				PillDescription.Text = tostring(NewDescription)
			end

			if NewLogo ~= nil then
				self.Logo = NewLogo
				PillLogo.Image = NewLogo
			end
		end

		function Pill:SetTitle(Text) self:Set(Text, nil, nil) end
		function Pill:SetDescription(Text) self:Set(nil, Text, nil) end
		function Pill:SetLogo(Image) self:Set(nil, nil, Image) end

		function Pill:SetAccent(Color)
			self.AccentColor = Color
			PillGradient.Color = ColorSequence.new(Color, DarkerAccent(Color))
		end

		function Pill:Destroy()
			Frame:Destroy()
		end

		Pill.Instance = Frame
		return Pill
	end

	function Window:AddFPSPill(Accent)
		local Pill = self:AddCustomPill("FPS", "--", nil, Accent or Color3.fromRGB(0, 200, 100))

		local Frames, Last = 0, os.clock()
		Library:Connect(RunService.RenderStepped, function()
			Frames = Frames + 1

			local Now = os.clock()
			if Now - Last >= 0.5 then
				Pill:SetDescription(tostring(math.floor(Frames / (Now - Last) + 0.5)))
				Frames, Last = 0, Now
			end
		end)

		return Pill
	end

	function Window:AddPingPill(Accent)
		local Pill = self:AddCustomPill("Ping", "-- ms", nil, Accent or Color3.fromRGB(255, 180, 60))

		Library:Thread(function()
			while not Library.Unloaded do
				local Ok, Ping = pcall(function()
					return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
				end)

				Pill:SetDescription((Ok and Ping) and (math.floor(Ping) .. " ms") or "-- ms")
				task.wait(1)
			end
		end)

		return Pill
	end

	function Window:AddTimePill(Accent)
		local Pill = self:AddCustomPill("Time", "--:--:--", nil, Accent or Color3.fromRGB(180, 120, 255))

		Library:Thread(function()
			while not Library.Unloaded do
				local Now = os.date("*t")
				Pill:SetDescription(string.format("%02d:%02d:%02d", Now.hour, Now.min, Now.sec))
				task.wait(1)
			end
		end)

		return Pill
	end

	function Window:AddCoordsPill(Accent)
		local Pill = self:AddCustomPill("Coords", "0, 0, 0", nil, Accent or Color3.fromRGB(80, 200, 255))

		Library:Thread(function()
			while not Library.Unloaded do
				local Character = LocalPlayer.Character
				local Root = Character and Character:FindFirstChild("HumanoidRootPart")

				if Root then
					local Position = Root.Position
					Pill:SetDescription(string.format("%d, %d, %d", Position.X, Position.Y, Position.Z))
				else
					Pill:SetDescription("--")
				end

				task.wait(0.1)
			end
		end)

		return Pill
	end

	function Window:AddUsernamePill(Accent)
		return self:AddCustomPill("User", "@" .. LocalPlayer.Name, nil, Accent or Color3.fromRGB(255, 100, 150))
	end

	--// Tabs
	local MainFrame = Create("Frame", {
		Name = "main",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -60),
		Position = UDim2.new(0, 0, 0, 60),
	}, Main)

	local TabsHolder = Create("Frame", {
		Name = "tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 170, 1, 0),
	}, MainFrame)
	Padding(TabsHolder, 10, 10, 15, 10)
	List(TabsHolder, 5, { HorizontalFlex = Enum.UIFlexAlignment.Fill })

	function Window:AddTab(Title, Logo)
		local Tab = { Title = Title, Logo = Logo, Selected = false, SubTabs = {} }

		local Button = Create("TextButton", {
			Name = "tab",
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 200, 0, 30),
		}, TabsHolder)
		Themed(Button, { BackgroundColor3 = "Tab" })
		Corner(Button, 0, { TopRightRadius = UDim.new(0, 5), BottomRightRadius = UDim.new(0, 5) })
		Stroke(Button, "Outline")

		MakeLabel(Button, {
			Name = "tabname",
			Bold = true,
			TextSize = 16,
			Text = Title,
			Size = UDim2.new(1, -65, 1, 0),
			Position = UDim2.new(0, 35, 0, 0),
		})

		Create("ImageLabel", {
			Name = "indicator",
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			ImageColor3 = Color3.fromRGB(186, 186, 186),
			Image = "rbxassetid://137833980584453",
			Size = UDim2.new(0, 25, 0, 25),
			Position = UDim2.new(1, -25, 0, 3),
		}, Button)

		if Logo then
			Create("ImageLabel", {
				Name = "logo",
				BorderSizePixel = 0,
				BackgroundTransparency = 1,
				Image = Logo,
				Size = UDim2.new(0, 25, 0, 25),
				Position = UDim2.new(0, 5, 0, 2),
			}, Button)
		end

		local Visual = Create("Frame", {
			Name = "visual",
			BorderSizePixel = 0,
			BackgroundColor3 = White,
			Size = UDim2.new(0, 3, 1, 0),
			Position = UDim2.new(0, -3, 0, 0),
			Visible = false,
		}, Button)
		Corner(Visual, 10, { TopRightRadius = UDim.new(0, 0), BottomRightRadius = UDim.new(0, 0) })
		Stroke(Visual, "Outline")
		Gradient(Visual, 90)

		local Content = Create("Frame", {
			Name = "content",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -170, 1, 0),
			Position = UDim2.new(0, 170, 0, 0),
			Visible = false,
		}, MainFrame)

		local SubTabsBar = Create("Frame", {
			Name = "subtabs",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 40),
		}, Content)
		List(SubTabsBar, 10, { FillDirection = Enum.FillDirection.Horizontal })
		Padding(SubTabsBar, 5, 5, 5, 10)

		local Pages = Create("Frame", {
			Name = "maincontent",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, -40),
			Position = UDim2.new(0, 0, 0, 40),
		}, Content)

		function Tab:Select()
			self.Selected = true
			Visual.Visible = true
			Visual.Size = UDim2.new(0, 0, 1, 0)
			Content.Visible = true
			Tween(Button, { BackgroundTransparency = 0 })
			Tween(Visual, { Size = UDim2.new(0, 3, 1, 0) })
		end

		function Tab:Unselect()
			self.Selected = false
			Tween(Button, { BackgroundTransparency = 1 })
			Tween(Visual, { Size = UDim2.new(0, 0, 1, 0) })
			Content.Visible = false
		end

		function Tab:AddSubTab(SubTitle)
			local SubTab = { Title = SubTitle, Selected = false }

			local SubButton = Create("TextButton", {
				Name = "subtab",
				BorderSizePixel = 0,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				FontFace = Library.FontBold,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				Text = SubTitle,
			}, SubTabsBar)
			Themed(SubButton, { TextColor3 = "Text" })

			local SubVisual = Create("Frame", {
				Name = "visual",
				BorderSizePixel = 0,
				BackgroundColor3 = White,
				Size = UDim2.new(1, 0, 0, 5),
				Position = UDim2.new(0, 0, 1, -2),
				Visible = false,
			}, SubButton)
			Corner(SubVisual, 10)
			Gradient(SubVisual, 90)

			local Page = Create("Frame", {
				Name = "page",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
				Visible = false,
			}, Pages)
			Padding(Page, 0, 5, 0, 5)
			List(Page, 5, {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalFlex = Enum.UIFlexAlignment.Fill,
			})

			local function MakeColumn(Name)
				local Column = Create("ScrollingFrame", {
					Name = Name,
					Active = true,
					BorderSizePixel = 0,
					BackgroundTransparency = 1,
					ScrollBarImageTransparency = 1,
					ScrollBarThickness = 0,
					Size = UDim2.new(0, 235, 0, 100),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(0, 0, 0, 0),
				}, Page)
				Padding(Column, 1, 1, 1, 0)
				List(Column, 10)
				return Column
			end

			local Left = MakeColumn("left")
			local Right = MakeColumn("right")

			function SubTab:Select()
				self.Selected = true
				SubVisual.Visible = true
				SubVisual.Size = UDim2.new(0, 0, 0, 5)
				Page.Visible = true
				Tween(SubVisual, { Size = UDim2.new(1, 0, 0, 5) })
			end

			function SubTab:Unselect()
				self.Selected = false
				Tween(SubVisual, { Size = UDim2.new(0, 0, 0, 5) })
				Page.Visible = false
			end

			function SubTab:AddSection(SectionTitle, Side)
				local Parent = (type(Side) == "string" and Side:lower() == "right") and Right or Left

				local SectionFrame = Create("Frame", {
					Name = "section",
					BorderSizePixel = 0,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 0),
				}, Parent)
				Themed(SectionFrame, { BackgroundColor3 = "Section" })
				Stroke(SectionFrame, "Outline")
				Corner(SectionFrame, 3, { BottomLeftRadius = UDim.new(0, 0), BottomRightRadius = UDim.new(0, 0) })

				local SectionTop = Create("ImageLabel", {
					Name = "sectionTop",
					BorderSizePixel = 0,
					BackgroundColor3 = White,
					Image = "rbxassetid://100840949142258",
					Size = UDim2.new(1, 0, 0, 20),
				}, SectionFrame)
				Corner(SectionTop, 3, { BottomLeftRadius = UDim.new(0, 0), BottomRightRadius = UDim.new(0, 0) })
				Stroke(SectionTop, "Outline")
				Gradient(SectionTop, 180)

				MakeLabel(SectionTop, {
					Name = "title",
					Bold = true,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					Text = SectionTitle,
					Size = UDim2.new(1, 0, 1, 0),
				})

				local SectionContent = Create("Frame", {
					Name = "maincontent",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 0),
				}, SectionFrame)
				Padding(SectionContent, 26, 6, 6, 6)
				List(SectionContent, 5)

				return setmetatable({
					Title = SectionTitle,
					Instance = SectionFrame,
					Content = SectionContent,
				}, { __index = SectionMethods })
			end

			Library:OnClick(SubButton, function()
				for _, Other in ipairs(Tab.SubTabs) do
					if Other ~= SubTab then
						Other:Unselect()
					end
				end

				SubTab:Select()
			end)

			table.insert(Tab.SubTabs, SubTab)

			if #Tab.SubTabs == 1 then
				SubTab:Select()
			end

			return SubTab
		end

		Library:OnClick(Button, function()
			for _, Other in ipairs(Window.Tabs) do
				if Other ~= Tab then
					Other:Unselect()
				end
			end

			Tab:Select()
		end)

		table.insert(Window.Tabs, Tab)

		if #Window.Tabs == 1 then
			Tab:Select()
		end

		return Tab
	end

	Window.Instance = Main
	self.MainWindow = Window
	return Window
end

Genv.Library = Library
return Library
