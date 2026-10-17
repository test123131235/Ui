--[[
    Feral UI Library
    Visuals = your original Feral library (window, tabs, subtabs, sections, toggles, sliders,
    dropdowns, textboxes, image-based colorpicker, pills, watermark, notifications).
    On top of it: Linoria-style API (CreateWindow, Toggles/Options, Idx + Info elements,
    Toggle:AddColorPicker / AddKeyPicker, AddButton, AddLabel, Groupbox aliases) so SaveManager works.
    Custom cursor (rbxassetid://92522094773590) is restored to the default Roblox cursor on unload.

    MOBILE SCALING (new):
      Library:CreateWindow({ ScreenFill = 0.55 })  -- max share of the screen the window may use (default 0.65 mobile / 0.95 desktop)
      Library:CreateWindow({ Scale = 0.5 })        -- hard override of the scale
      Window:SetScale(0.5)                         -- change at runtime
]]

local cRF = cloneref or function(Object) return Object end
local Players = cRF(game:GetService("Players"))
local UserInputService = cRF(game:GetService("UserInputService"))
local RunService = cRF(game:GetService("RunService"))
local HttpService = cRF(game:GetService("HttpService"))
local TweenService = cRF(game:GetService("TweenService"))
local GuiService = cRF(game:GetService("GuiService"))
local CoreGui = cRF(game:GetService("CoreGui"))

local env = (getgenv and getgenv()) or _G
if env.Library and env.Library.Exit then
    pcall(function() env.Library:Exit() end)
end

local GETH = gethui or function() return CoreGui end
local LocalPlayer = Players.LocalPlayer
local GuiInset = GuiService:GetGuiInset().Y
local Mouse = cRF(LocalPlayer:GetMouse())
local IsMobile = (function()
    -- same approach as Obsidian: ask Roblox for the platform (works on cloud phones that also report a keyboard)
    local ok, platform = pcall(function() return UserInputService:GetPlatform() end)
    if ok and (platform == Enum.Platform.Android or platform == Enum.Platform.IOS) then
        return true
    end
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end)()

local Toggles, Options = {}, {}
env.Toggles = Toggles
env.Options = Options

local Library
Library = {
    Flags = {},
    Keybind = Enum.KeyCode.X,
    ToggleKeybind = nil, -- optional: set to an Options key picker (Library.ToggleKeybind = Options.MenuKeybind)

    Directory = "feral",
    Folders = { Assets = "/Assets", Configs = "/Configs" },
    Animation = { Time = 0.3, Style = "Exponential", Direction = "Out" },
    ZIndexOrder = { OptionHolder = 4, KeybindWindow = 4, ColorpickerWindow = 6 },
    Theme = nil,
    Threads = {},
    Connections = {},
    SetFlags = {},
    ThemingStuff = {},
    ThemeMap = {},
    OpenFrames = {},
    KeyPickers = {},
    UnloadCallbacks = {},
    Unloaded = false,
    Toggles = Toggles,
    Options = Options,
    Holder = nil,
    UnusedHolder = nil,
    Font = nil,
    FontBold = nil,
}
Library.__index = Library
env.Library = Library

pcall(function()
    if not isfolder(Library.Directory) then makefolder(Library.Directory) end
    for _, Folder in pairs(Library.Folders) do
        if not isfolder(Library.Directory .. Folder) then makefolder(Library.Directory .. Folder) end
    end
end)

local Themes = {
    Preset = {
        Background = Color3.fromRGB(23, 23, 23), Inline = Color3.fromRGB(22, 22, 22), Content = Color3.fromRGB(21, 21, 21),
        Text = Color3.fromRGB(200, 200, 200),
        ["Outline 1"] = Color3.fromRGB(35, 35, 35), ["Outline 2"] = Color3.fromRGB(30, 30, 30),
        ["Outline 3"] = Color3.fromRGB(15, 15, 15), ["Outline 4"] = Color3.fromRGB(10, 10, 10),
        ["Inactive Text"] = Color3.fromRGB(135, 135, 135), Accent = Color3.fromRGB(126, 192, 255),
        ["Hovered Element"] = Color3.fromRGB(35, 35, 35),
    },
}

local EasingStyleMap = {
    Linear = Enum.EasingStyle.Linear, Sine = Enum.EasingStyle.Sine, Back = Enum.EasingStyle.Back,
    Quad = Enum.EasingStyle.Quad, Quart = Enum.EasingStyle.Quart, Quint = Enum.EasingStyle.Quint,
    Bounce = Enum.EasingStyle.Bounce, Elastic = Enum.EasingStyle.Elastic, Exponential = Enum.EasingStyle.Exponential,
    Circular = Enum.EasingStyle.Circular, Cubic = Enum.EasingStyle.Cubic,
}
local EasingDirectionMap = { In = Enum.EasingDirection.In, Out = Enum.EasingDirection.Out, InOut = Enum.EasingDirection.InOut }

Library.GetEasingStyle = function(Self, Style)
    if typeof(Style) == "EnumItem" then return Style end
    return EasingStyleMap[Style] or Enum.EasingStyle.Exponential
end
Library.GetEasingDirection = function(Self, Direction)
    if typeof(Direction) == "EnumItem" then return Direction end
    return EasingDirectionMap[Direction] or Enum.EasingDirection.Out
end

Library.Theme = Themes.Preset

----------------------------------------------------------------------
-- Fonts (same Inter files as the original)
----------------------------------------------------------------------
local CustomFont = {}
function CustomFont.New(self, Name, Weight, Style, FileData)
    local ok, result = pcall(function()
        if not isfile(FileData.Id) then
            writefile(FileData.Id, game:HttpGet(FileData.Url))
        end
        local Data = {
            name = Name,
            faces = { { name = Name, weight = Weight, style = Style, assetId = getcustomasset(FileData.Id) } },
        }
        local FontPath = Library.Directory .. Library.Folders.Assets .. "/" .. Name .. ".font"
        writefile(FontPath, HttpService:JSONEncode(Data))
        return Font.new(getcustomasset(FontPath))
    end)
    if ok and result then return result end
    return Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
end

Library.Font = CustomFont:New("InterMedium", 400, "Regular", {
    Id = "InterMedium", Url = "https://github.com/ilxypp/assets/raw/refs/heads/main/InterMedium.ttf",
})
Library.FontBold = CustomFont:New("InterBold", 400, "Regular", {
    Id = "InterBold", Url = "https://github.com/ilxypp/assets/raw/refs/heads/main/InterBold.ttf",
})

----------------------------------------------------------------------
-- Core functions (original)
----------------------------------------------------------------------
Library.Exit = function(Self)
    Self.Unloaded = true
    if Self.RestoreCursor then Self:RestoreCursor() end -- restores the original Roblox cursor
    for _, fn in ipairs(Self.UnloadCallbacks) do pcall(fn) end
    for _, Connection in pairs(Library.Connections) do pcall(function() Connection:Disconnect() end) end
    for _, Thread in pairs(Library.Threads) do pcall(coroutine.close, Thread) end
    if Self.Holder then Self.Holder:Destroy() end
    if Self.UnusedHolder then Self.UnusedHolder:Destroy() end
    Library = nil
    env.Library = nil
    env.Toggles = nil
    env.Options = nil
end
Library.Unload = Library.Exit

function Library.OnUnload(Self, fn) table.insert(Self.UnloadCallbacks, fn) end

Library.Thread = function(Self, Function)
    local NewThread = coroutine.create(Function)
    coroutine.wrap(function() coroutine.resume(NewThread) end)()
    table.insert(Library.Threads, NewThread)
    return NewThread
end

Library.Connect = function(Self, Signal, Callback)
    local Connection
    if Self.Instance then
        if Self.Instance[Signal] then
            if IsMobile and Signal == "MouseButton1Down" then
                Connection = Self.Instance.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
                        Callback(Input)
                    end
                end)
                return
            end
            Connection = Self.Instance[Signal]:Connect(Callback)
        else
            Connection = Signal:Connect(Callback)
        end
    else
        Connection = Signal:Connect(Callback)
    end
    table.insert(Library.Connections, Connection)
    return Connection
end

Library.ActiveGradientTweens = Library.ActiveGradientTweens or {}

Library.TweenGradient = function(Self, Gradient, Target, Info)
    Info = Info or TweenInfo.new(
        Library.Animation.Time,
        Library:GetEasingStyle(Library.Animation.Style),
        Library:GetEasingDirection(Library.Animation.Direction)
    )
    if not Gradient then return end

    local Existing = Library.ActiveGradientTweens[Gradient]
    if Existing then
        Existing:Disconnect()
        Library.ActiveGradientTweens[Gradient] = nil
    end

    local StartTime = os.clock()
    local StartValue = Gradient.Transparency.Keypoints[1].Value
    local Duration = Info.Time
    local EasingStyle = Info.EasingStyle
    local EasingDirection = Info.EasingDirection
    local Connection

    Connection = RunService.RenderStepped:Connect(function()
        local Alpha = Duration > 0 and math.clamp((os.clock() - StartTime) / Duration, 0, 1) or 1
        local Eased = TweenService:GetValue(Alpha, EasingStyle, EasingDirection)
        Gradient.Transparency = NumberSequence.new(StartValue + (Target - StartValue) * Eased)
        if Alpha >= 1 then
            Connection:Disconnect()
            Library.ActiveGradientTweens[Gradient] = nil
        end
    end)

    Library.ActiveGradientTweens[Gradient] = Connection
    table.insert(Library.Connections, Connection)
    return Connection
end

Library.Tween = function(Self, Properties, Info, IsRawItem)
    local Object = Self.Instance or IsRawItem
    Info = Info or TweenInfo.new(
        Library.Animation.Time,
        Library:GetEasingStyle(Library.Animation.Style),
        Library:GetEasingDirection(Library.Animation.Direction)
    )
    if not Object then return end

    local NewTween = TweenService:Create(Object, Info, Properties)
    NewTween:Play()

    if Object:IsA("TextLabel") then
        local Stroke = Object:FindFirstChildOfClass("UIStroke")
        if Stroke and Properties.TextTransparency then
            TweenService:Create(Stroke, Info, { Transparency = Properties.TextTransparency }):Play()
        end
    end
    return NewTween
end

Library.GetTweenProperty = function(Self, IsRawItem)
    local Object = Self.Instance or IsRawItem
    if not Object then return {} end
    if Object:IsA("Frame") then return { "BackgroundTransparency" }
    elseif Object:IsA("TextLabel") or Object:IsA("TextButton") then return { "TextTransparency", "BackgroundTransparency" }
    elseif Object:IsA("ImageLabel") or Object:IsA("ImageButton") then return { "BackgroundTransparency", "ImageTransparency" }
    elseif Object:IsA("ScrollingFrame") then return { "BackgroundTransparency", "ScrollBarImageTransparency" }
    elseif Object:IsA("TextBox") then return { "TextTransparency", "BackgroundTransparency" }
    elseif Object:IsA("UIStroke") then return { "Transparency" } end
end

Library.IsMouseOverFrame = function(Self)
    if not Self.Instance then return end
    local Object = Self.Instance
    local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
    return MousePosition.X >= Object.AbsolutePosition.X and MousePosition.X <= Object.AbsolutePosition.X + Object.AbsoluteSize.X
        and MousePosition.Y >= Object.AbsolutePosition.Y and MousePosition.Y <= Object.AbsolutePosition.Y + Object.AbsoluteSize.Y
end

Library.SafeCall = function(Self, Function, ...)
    local Arguements = { ... }
    local Success, Result = pcall(Function, table.unpack(Arguements))
    if not Success then
        warn(Result)
        return false
    end
    return Success, Result
end

function Library.SafeCallback(Self, fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then warn("[Library] callback error: " .. tostring(err)) end
end

Library.Round = function(Self, Number, Float)
    local Multiplier = 1 / (Float or 1)
    return math.floor(Number * Multiplier) / Multiplier
end

Library.GetConfig = function(Self)
    local Config = {}
    local Success, Result = Library:SafeCall(function()
        for Index, Value in pairs(Library.Flags) do
            if type(Value) == "table" and Value.Key then
                Config[Index] = { Key = tostring(Value.Key), Mode = Value.Mode }
            elseif type(Value) == "table" and Value.Color then
                Config[Index] = { Color = "#" .. Value.HexValue, Alpha = Value.Alpha }
            elseif typeof(Value) == "Color3" then
                Config[Index] = "#" .. Value:ToHex()
            else
                Config[Index] = Value
            end
        end
    end)
    if not Success then
        warn("Failed to get config:\n" .. tostring(Result))
        return
    end
    local EncodeSuccess, EncodeResult = pcall(function() return HttpService:JSONEncode(Config) end)
    if not EncodeSuccess then
        warn("Failed to encode config:\n" .. tostring(EncodeResult))
        return
    end
    return EncodeResult
end

Library.LoadConfig = function(Self, Config)
    local DecodeSuccess, Decoded = pcall(function() return HttpService:JSONDecode(Config) end)
    if not DecodeSuccess then
        warn("Failed to decode config:\n" .. tostring(Decoded))
        return false
    end
    local Success, Result = Library:SafeCall(function()
        for Index, Value in pairs(Decoded) do
            local SetFunction = Library.SetFlags[Index]
            if SetFunction then
                if type(Value) == "table" and Value.Key then
                    SetFunction(Value)
                elseif type(Value) == "table" and Value.Color then
                    SetFunction(Value.Color, Value.Alpha)
                elseif type(Value) == "string" and Value:sub(1, 1) == "#" then
                    local hex = Value:gsub("#", "")
                    if #hex == 6 then
                        local r = tonumber(hex:sub(1, 2), 16)
                        local g = tonumber(hex:sub(3, 4), 16)
                        local b = tonumber(hex:sub(5, 6), 16)
                        if r and g and b then SetFunction(Color3.fromRGB(r, g, b)) end
                    end
                else
                    SetFunction(Value)
                end
            end
        end
    end)
    return Success, Result
end

Library.GetConfigsList = function(Self, Element)
    local ReturnList = {}
    local List = listfiles(Library.Directory .. Library.Folders.Configs)
    for Index = 1, #List do
        local File = List[Index]
        if File:sub(-5) == ".json" then
            local Position = File:find(".json", 1, true)
            local StartPosition = Position
            local Character = File:sub(Position, Position)
            while Character ~= "/" and Character ~= "\\" and Character ~= "" do
                Position = Position - 1
                Character = File:sub(Position, Position)
            end
            if Character == "/" or Character == "\\" then
                table.insert(ReturnList, File:sub(Position + 1, StartPosition - 1))
            end
        end
    end
    Element:Refresh(ReturnList)
end

Library.AddToTheme = function(Self, Properties)
    local Object = Self.Instance
    local ThemeData = { Item = Object, Properties = Properties }
    for Property, Value in pairs(ThemeData.Properties) do
        if type(Value) == "string" then
            if not Library.Theme[Value] then Object[Property] = Value end
            Object[Property] = Library.Theme[Value]
        else
            Object[Property] = Value()
        end
    end
    table.insert(Library.ThemingStuff, ThemeData)
    Library.ThemeMap[Object] = ThemeData
    return Self
end

Library.ChangeItemTheme = function(Self, Properties)
    local Object = Self.Instance
    if not Library.ThemeMap[Object] then return end
    Library.ThemeMap[Object].Properties = Properties
end

Library.ChangeTheme = function(Self, Theme, Color)
    Library.Theme[Theme] = Color
    for _, Item in pairs(Library.ThemingStuff) do
        for Property, Value in pairs(Item.Properties) do
            if type(Value) == "string" and Value == Theme then
                Item.Item[Property] = Color
            elseif type(Value) == "function" then
                Item.Item[Property] = Value()
            end
        end
    end
end

Library.OnHover = function(Self, OnHoverEnter, OnHoverLeave)
    local Object = Self.Instance
    if not Object then return end
    Library:Connect(Object.MouseEnter, OnHoverEnter)
    Library:Connect(Object.MouseLeave, OnHoverLeave)
end

Library.Holder = Instance.new("ScreenGui")
Library.Holder.IgnoreGuiInset = true
Library.Holder.Name = "\0"
Library.Holder.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Library.Holder.ResetOnSpawn = false
Library.Holder.Parent = GETH()

----------------------------------------------------------------------
-- Custom cursor
----------------------------------------------------------------------
Library.CursorImage = "rbxassetid://92522094773590"
Library.CursorSize = 32 -- change if the image looks too big/small

local OriginalMouseIconEnabled = UserInputService.MouseIconEnabled

local CursorGui, CursorLabel

-- remove cursors left behind by older versions of the lib
pcall(function()
    for _, g in ipairs(GETH():GetChildren()) do
        if g:IsA("ScreenGui") and g:FindFirstChild("cursor") then g:Destroy() end
    end
end)

-- everything cursor-related is wrapped so it can never stop the library from loading
local CursorOk, CursorErr = pcall(function()
    if IsMobile then return end -- no custom cursor on touch devices
    CursorGui = Instance.new("ScreenGui")
    CursorGui.Name = "\0"
    CursorGui.IgnoreGuiInset = true
    CursorGui.DisplayOrder = 999999
    CursorGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    CursorGui.ResetOnSpawn = false
    CursorGui.Parent = GETH()

    CursorLabel = Instance.new("ImageLabel")
    CursorLabel.Name = "cursor"
    CursorLabel.BackgroundTransparency = 1
    CursorLabel.BorderSizePixel = 0
    CursorLabel.Image = Library.CursorImage
    CursorLabel.Size = UDim2.fromOffset(Library.CursorSize, Library.CursorSize)
    CursorLabel.ZIndex = 10000
    CursorLabel.Active = false
    CursorLabel.Parent = CursorGui

    Library.CursorGui = CursorGui
end)
if not CursorOk then warn("[Library] custom cursor disabled: " .. tostring(CursorErr)) end

function Library.SetCursorImage(Self, Image, Size)
    if not CursorLabel then return end
    CursorLabel.Image = Image
    if Size then CursorLabel.Size = UDim2.fromOffset(Size, Size) end
end

-- Brings back the original Roblox cursor and removes ours
function Library.RestoreCursor(Self)
    pcall(function() UserInputService.MouseIconEnabled = OriginalMouseIconEnabled end)
    if CursorGui then pcall(function() CursorGui:Destroy() end) end
    CursorGui, CursorLabel = nil, nil
end

if CursorOk and CursorLabel then
    Library:Connect(RunService.RenderStepped, function()
        if not CursorLabel then return end
        pcall(function()
            -- hide ours while the game locks the mouse to the screen centre (shiftlock / first person)
            if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
                CursorLabel.Visible = false
                UserInputService.MouseIconEnabled = OriginalMouseIconEnabled
                return
            end
            local m = UserInputService:GetMouseLocation()
            CursorLabel.Position = UDim2.fromOffset(m.X, m.Y)
            CursorLabel.Visible = true
            UserInputService.MouseIconEnabled = false -- keeps the game from re-enabling the default cursor
            Mouse.Icon = "" -- stops games from forcing their own cursor icon
        end)
    end)
end

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function N(class, props, parent)
    local o = Instance.new(class)
    if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local function Corner(p, r) return N("UICorner", { CornerRadius = UDim.new(0, r) }, p) end
local function Stroke(p, c) return N("UIStroke", { Color = c, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p) end
local function Pad(p, t, r, b, l)
    return N("UIPadding", {
        PaddingTop = UDim.new(0, t or 0), PaddingRight = UDim.new(0, r or 0),
        PaddingBottom = UDim.new(0, b or 0), PaddingLeft = UDim.new(0, l or 0),
    }, p)
end
local BLUE0, BLUE1 = Color3.fromRGB(0, 131, 255), Color3.fromRGB(0, 63, 255)
local function BlueGrad(p, rot, c1)
    return N("UIGradient", {
        Rotation = rot,
        Color = ColorSequence.new { ColorSequenceKeypoint.new(0, BLUE0), ColorSequenceKeypoint.new(1, c1 or BLUE1) },
    }, p)
end
local WHITE = Color3.fromRGB(255, 255, 255)
local OUTLINE = Color3.fromRGB(40, 40, 40)
local ELEMENT = Color3.fromRGB(28, 28, 30)

-- Pointer position in the same convention as GetMouseLocation(). Touch inputs use their own position
-- (GetMouseLocation is unreliable on phones/tablets).
local function PointerLocation(Input)
    if Input and Input.UserInputType == Enum.UserInputType.Touch then
        return Vector2.new(Input.Position.X, Input.Position.Y + GuiInset)
    end
    return UserInputService:GetMouseLocation()
end

local function IsMouseOverFrame(Frame, Input)
    local MousePos = PointerLocation(Input)
    local mx, my = MousePos.X, MousePos.Y - GuiInset
    local p, sz = Frame.AbsolutePosition, Frame.AbsoluteSize
    return mx >= p.X and mx <= p.X + sz.X and my >= p.Y and my <= p.Y + sz.Y
end

local function Norm(a, b)
    if type(a) == "table" then return a.Flag, a end
    return a, b or {}
end

local function FireChanged(obj, ...)
    for _, fn in ipairs(obj.Changed) do Library:SafeCallback(fn, ...) end
end

local function InputName(i)
    if i.UserInputType == Enum.UserInputType.Keyboard then return i.KeyCode.Name
    elseif i.UserInputType == Enum.UserInputType.MouseButton1 then return "MB1"
    elseif i.UserInputType == Enum.UserInputType.MouseButton2 then return "MB2"
    elseif i.UserInputType == Enum.UserInputType.MouseButton3 then return "MB3" end
end

-- Roblox asset id helper: accepts 123456789, "123456789", "rbxassetid://123456789" (or any other image url)
local DefaultPillLogo = "rbxassetid://121449270899000"
local function ToAsset(Id, Fallback)
    if type(Id) == "number" then return "rbxassetid://" .. tostring(math.floor(Id)) end
    if type(Id) == "string" then
        local trimmed = Id:match("^%s*(.-)%s*$")
        if trimmed:match("^%d+$") then return "rbxassetid://" .. trimmed end
        if trimmed ~= "" then return trimmed end
    end
    return Fallback
end
Library.ToAsset = function(Self, Id, Fallback) return ToAsset(Id, Fallback) end

local function IsPress(Input)
    return Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch
end

local function IsMove(Input)
    return Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch
end

-- stops the column scrolling while a slider / picker is dragged with a finger
local function SetScrollLock(From, Locked)
    local sf = From and From:FindFirstAncestorOfClass("ScrollingFrame")
    if sf then sf.ScrollingEnabled = not Locked end
end

-- touch sizing (only used on phones/tablets without a keyboard)
local TOUCH = IsMobile
local H_TOGGLE   = TOUCH and 24 or 14
local H_SLIDER   = TOUCH and 44 or 30
local H_BAR      = TOUCH and 26 or 15
local H_DROPDOWN = TOUCH and 32 or 25
local H_INPUT    = TOUCH and 32 or 25
local H_BUTTON   = TOUCH and 30 or 20
local H_TAB      = TOUCH and 36 or 30
local S_SQUARE   = TOUCH and 22 or 15
local PAD_ROWS   = TOUCH and 8 or 5
local POPUP_SCALE = TOUCH and 1.3 or 1

----------------------------------------------------------------------
-- Global key picker input
----------------------------------------------------------------------
Library:Connect(UserInputService.InputBegan, function(input, gp)
    local name = InputName(input)
    if not name then return end
    for _, kp in ipairs(Library.KeyPickers) do
        if kp.Picking then
            kp.Picking = false
            Library.LastPick = os.clock()
            kp:SetValue({ name == "Escape" and "None" or name, kp.Mode })
            return
        end
    end
    if gp then return end
    for _, kp in ipairs(Library.KeyPickers) do
        if kp.Value == name then kp:Press() end
    end
end)
Library:Connect(UserInputService.InputEnded, function(input)
    local name = InputName(input)
    if not name then return end
    for _, kp in ipairs(Library.KeyPickers) do
        if kp.Value == name then kp:Release() end
    end
end)

----------------------------------------------------------------------
-- Colorpicker popup (original look: image SV square, hue bar, scale animation)
----------------------------------------------------------------------
local function MakeColorpicker(square, Cfg)
    local Colorpicker = {
        Type = "ColorPicker",
        Title = Cfg.Title,
        Flag = Cfg.Flag,
        Value = Cfg.Default or Color3.fromRGB(255, 255, 255),
        Callback = Cfg.Callback or function() end,
        Changed = {},
        IsOpen = false,
    }

    local popup = N("Frame", {
        BackgroundColor3 = Color3.fromRGB(20, 20, 21), Size = UDim2.new(0, 180, 0, 150),
        Position = UDim2.new(0.5, -80, 0.5, -70), Name = "colorpickerPopup", Visible = false, ZIndex = 1000, Active = true,
    }, Library.Holder)
    Colorpicker.Popup = popup
    Corner(popup, 10)
    Stroke(popup, Color3.fromRGB(60, 60, 60))
    local popupScale = N("UIScale", { Scale = 0 }, popup)

    local svSquare = N("ImageLabel", {
        BackgroundColor3 = WHITE, Image = "rbxassetid://122155142257844", Size = UDim2.new(0, 130, 0, 130),
        Position = UDim2.new(0, 10, 0, 10), Name = "svSquare", Active = true,
    }, popup)
    Corner(svSquare, 5)
    Stroke(svSquare, Color3.fromRGB(60, 60, 60))

    local svMarker = N("Frame", {
        BackgroundColor3 = WHITE, Size = UDim2.new(0, 8, 0, 8), Position = UDim2.new(0, 0, 0, 0),
        AnchorPoint = Vector2.new(0.5, 0.5), Name = "marker",
    }, svSquare)
    Corner(svMarker, 0).CornerRadius = UDim.new(1, 0)
    N("UIStroke", { Color = WHITE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, svMarker)

    local hueBar = N("Frame", {
        BackgroundColor3 = WHITE, Size = UDim2.new(0, 20, 0, 130), Position = UDim2.new(1, -30, 0, 10),
        Name = "hueBar", Active = true,
    }, popup)
    Corner(hueBar, 5)
    N("UIGradient", {
        Rotation = 270,
        Color = ColorSequence.new {
            ColorSequenceKeypoint.new(0.000, Color3.fromRGB(255, 0, 4)),
            ColorSequenceKeypoint.new(0.140, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(0.280, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(0.420, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(0.560, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.700, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(0.840, Color3.fromRGB(255, 140, 0)),
            ColorSequenceKeypoint.new(1.000, Color3.fromRGB(255, 0, 0)),
        },
    }, hueBar)
    Stroke(hueBar, Color3.fromRGB(60, 60, 60))

    local hueMarker = N("Frame", {
        BackgroundColor3 = WHITE, Size = UDim2.new(1, 4, 0, 4), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, 0), Name = "marker",
    }, hueBar)
    Corner(hueMarker, 2)
    Stroke(hueMarker, WHITE)

    local h, s, v = Colorpicker.Value:ToHSV()
    local CursorInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function UpdateColor(Silent)
        local color = Color3.fromHSV(h, s, v)
        Colorpicker.Value = color
        square.BackgroundColor3 = color
        svSquare.ImageColor3 = Color3.fromHSV(h, 1, 1)
        svSquare.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        Library:Tween({ Position = UDim2.new(s, 0, 1 - v, 0) }, CursorInfo, svMarker)
        Library:Tween({ Position = UDim2.new(0.5, 0, h, 0) }, CursorInfo, hueMarker)
        if Colorpicker.Flag then Library.Flags[Colorpicker.Flag] = color end
        if not Silent then
            Library:SafeCallback(Colorpicker.Callback, color)
            FireChanged(Colorpicker, color)
        end
    end

    local svDragging, hueDragging = false, false
    local dragInput = nil

    local function UpdateSVFromMouse(mousePos)
        local p, sz = svSquare.AbsolutePosition, svSquare.AbsoluteSize
        local mx, my = mousePos.X, mousePos.Y - GuiInset
        s = math.clamp((mx - p.X) / sz.X, 0, 1)
        v = 1 - math.clamp((my - p.Y) / sz.Y, 0, 1)
        UpdateColor()
    end
    local function UpdateHueFromMouse(mousePos)
        local p, sz = hueBar.AbsolutePosition, hueBar.AbsoluteSize
        local my = mousePos.Y - GuiInset
        h = math.clamp((my - p.Y) / sz.Y, 0, 1)
        UpdateColor()
    end

    Library:Connect(svSquare.InputBegan, function(Input)
        if IsPress(Input) then
            svDragging = true
            dragInput = Input
            UpdateSVFromMouse(PointerLocation(Input))
        end
    end)
    Library:Connect(hueBar.InputBegan, function(Input)
        if IsPress(Input) then
            hueDragging = true
            dragInput = Input
            UpdateHueFromMouse(PointerLocation(Input))
        end
    end)
    Library:Connect(UserInputService.InputChanged, function(Input)
        if not IsMove(Input) then return end
        if not svDragging and not hueDragging then return end
        if Input.UserInputType == Enum.UserInputType.Touch and Input ~= dragInput then return end
        local mousePos = PointerLocation(Input)
        if svDragging then UpdateSVFromMouse(mousePos)
        elseif hueDragging then UpdateHueFromMouse(mousePos) end
    end)
    Library:Connect(UserInputService.InputEnded, function(Input)
        if not IsPress(Input) then return end
        if Input.UserInputType == Enum.UserInputType.Touch and Input ~= dragInput then return end
        svDragging = false; hueDragging = false
    end)

    function Colorpicker.Open(self)
        self.IsOpen = true
        local mousePos = UserInputService:GetMouseLocation()
        local viewport = workspace.CurrentCamera.ViewportSize
        local popupW, popupH = 180 * POPUP_SCALE, 150 * POPUP_SCALE
        local x = mousePos.X
        local y = mousePos.Y - GuiInset
        if TOUCH then
            -- centred on touch devices so the finger never covers it
            x = (viewport.X - popupW) / 2
            y = (viewport.Y - popupH) / 2
        end
        if x + popupW > viewport.X then x = viewport.X - popupW end
        if y + popupH > viewport.Y then y = viewport.Y - popupH end
        if x < 0 then x = 0 end
        if y < 0 then y = 0 end
        popup.Position = UDim2.new(0, x, 0, y)
        popup.Visible = true
        popupScale.Scale = 0
        Library:Tween({ Scale = POPUP_SCALE }, nil, popupScale)
    end

    function Colorpicker.Close(self)
        self.IsOpen = false
        local tween = Library:Tween({ Scale = 0 }, nil, popupScale)
        tween.Completed:Connect(function()
            if not Colorpicker.IsOpen then popup.Visible = false end
        end)
    end

    function Colorpicker.TogglePopup(self)
        if self.IsOpen then self:Close() else self:Open() end
    end

    function Colorpicker.Set(self, Value, Silent)
        if typeof(Value) == "Color3" then
            h, s, v = Value:ToHSV()
            UpdateColor(Silent)
        elseif type(Value) == "string" then
            local hex = Value:gsub("#", "")
            if #hex == 6 then
                local r = tonumber(hex:sub(1, 2), 16)
                local g = tonumber(hex:sub(3, 4), 16)
                local b = tonumber(hex:sub(5, 6), 16)
                if r and g and b then
                    h, s, v = Color3.fromRGB(r, g, b):ToHSV()
                    UpdateColor(Silent)
                end
            end
        end
    end
    function Colorpicker.SetValue(self, Value) self:Set(Value) end
    function Colorpicker.SetValueRGB(self, Value) self:Set(Value) end
    function Colorpicker.OnChanged(self, fn) table.insert(self.Changed, fn); Library:SafeCallback(fn, self.Value) end

    Library:Connect(square.InputBegan, function(Input)
        if IsPress(Input) then Colorpicker:TogglePopup() end
    end)

    Library:Connect(UserInputService.InputBegan, function(Input)
        if not IsPress(Input) then return end
        if not Colorpicker.IsOpen then return end
        if IsMouseOverFrame(popup, Input) then return end
        if IsMouseOverFrame(square, Input) then return end
        Colorpicker:Close()
    end)

    if Colorpicker.Flag then
        Library.SetFlags[Colorpicker.Flag] = function(Value) Colorpicker:Set(Value, true) end
        Library.Flags[Colorpicker.Flag] = Colorpicker.Value
        Options[Colorpicker.Flag] = Colorpicker
    end

    UpdateColor(true)
    return Colorpicker
end

local function MakeColorSquare(parent, color, order)
    local sq = N("Frame", {
        BackgroundColor3 = color, Size = UDim2.new(0, S_SQUARE, 0, S_SQUARE), Name = "colorSquare", Active = true, LayoutOrder = order or 2,
    }, parent)
    Corner(sq, 5)
    Stroke(sq, OUTLINE)
    return sq
end

----------------------------------------------------------------------
-- Key picker (same style as the colour square)
----------------------------------------------------------------------
local ModeCycle = { Always = "Toggle", Toggle = "Hold", Hold = "Always" }

local function MakeKeypicker(parent, Idx, Info, parentToggle)
    Info = Info or {}
    local KP = {
        Type = "KeyPicker", Flag = Idx, Value = Info.Default or "None", Mode = Info.Mode or "Toggle",
        Toggled = false, Holding = false, Picking = false, Callback = Info.Callback,
        Changed = {}, Clicked = {}, Sync = Info.SyncToggleState, ParentToggle = parentToggle,
    }

    local box = N("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = ELEMENT, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 0, S_SQUARE), LayoutOrder = 1, Name = "keypicker",
    }, parent)
    Corner(box, 5)
    Stroke(box, OUTLINE)
    Pad(box, 0, 5, 0, 5)
    local label = N("TextLabel", {
        BackgroundTransparency = 1, FontFace = Library.FontBold, TextSize = 12, TextColor3 = WHITE,
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Text = "",
    }, box)
    KP.Instance = box

    local function Display()
        if KP.Picking then label.Text = "..."
        else label.Text = "[" .. tostring(KP.Value) .. (KP.Mode ~= "Toggle" and (" · " .. KP.Mode) or "") .. "]" end
    end

    function KP.GetState(self)
        if self.Mode == "Always" then return true
        elseif self.Mode == "Hold" then return self.Holding end
        return self.Toggled
    end
    function KP.Notify(self)
        local st = self:GetState()
        if self.Sync and self.ParentToggle then self.ParentToggle:Set(st) end
        Library:SafeCallback(self.Callback, st)
        for _, fn in ipairs(self.Clicked) do Library:SafeCallback(fn, st) end
    end
    function KP.Press(self)
        if self.Mode == "Toggle" then self.Toggled = not self.Toggled
        elseif self.Mode == "Hold" then self.Holding = true end
        self:Notify()
    end
    function KP.Release(self)
        if self.Mode == "Hold" and self.Holding then self.Holding = false; self:Notify() end
    end
    function KP.SetValue(self, data)
        if type(data) == "table" then
            self.Value = data[1] or data.key or data.Key or self.Value
            self.Mode = data[2] or data.mode or data.Mode or self.Mode
        elseif type(data) == "string" then
            self.Value = data
        end
        Display()
        if self.Flag then Library.Flags[self.Flag] = { Key = self.Value, Mode = self.Mode } end
        FireChanged(self, self.Value)
    end
    function KP.Set(self, data) self:SetValue(data) end
    function KP.OnClick(self, fn) table.insert(self.Clicked, fn) end
    function KP.OnChanged(self, fn) table.insert(self.Changed, fn); Library:SafeCallback(fn, self.Value) end

    Library:Connect(box.MouseButton1Click, function()
        if IsMobile then
            KP.Mode = ModeCycle[KP.Mode] or "Toggle"
            Display()
        else
            KP.Picking = true
            Display()
        end
    end)
    Library:Connect(box.MouseButton2Click, function() KP.Mode = ModeCycle[KP.Mode] or "Toggle"; Display() end)

    if Idx then
        Library.SetFlags[Idx] = function(Value) KP:SetValue({ Value.Key, Value.Mode }) end
        Library.Flags[Idx] = { Key = KP.Value, Mode = KP.Mode }
        Options[Idx] = KP
    end

    Display()
    table.insert(Library.KeyPickers, KP)
    return KP
end

local function GetAddons(holder, rightOffset)
    local box = holder:FindFirstChild("addons")
    if box then return box end
    box = N("Frame", {
        Name = "addons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -rightOffset, 0.5, 0), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, S_SQUARE),
    }, holder)
    N("UIListLayout", {
        Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center,
    }, box)
    return box
end

----------------------------------------------------------------------
-- Elements (original visuals) - shared by every section / groupbox
----------------------------------------------------------------------
local function ApplyElements(Section, sectionContent)
    -- Toggle -------------------------------------------------------
    function Section.AddToggle(self, a, b)
        local Idx, Config = Norm(a, b)
        local Toggle = {
            Type = "Toggle",
            Title = Config.Title or Config.Text or "Toggle",
            Flag = Idx or Config.Flag,
            Value = Config.Default or false,
            Callback = Config.Callback or function() end,
            Changed = {},
            Addons = {},
        }

        local toggleHolder = N("Frame", {
            BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, H_TOGGLE), Name = "toggle", BackgroundTransparency = 1, Active = true,
        }, sectionContent)

        N("TextLabel", {
            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = WHITE, FontFace = Library.Font,
            TextColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.new(0, 113, 1, 0), Text = Toggle.Title, Name = "label",
        }, toggleHolder)

        local toggleSwitch = N("Frame", {
            BackgroundColor3 = Color3.fromRGB(24, 24, 26), Size = TOUCH and UDim2.new(0, 30, 0, 15) or UDim2.new(0, 30, 1, 1),
            Position = TOUCH and UDim2.new(1, -30, 0.5, -7) or UDim2.new(1, -30, 0, 1), Name = "toggleSwitch",
        }, toggleHolder)
        Corner(toggleSwitch, 5)
        local toggleCircle = N("Frame", { BackgroundColor3 = WHITE, Size = UDim2.new(0, 10, 0, 10), Name = "circle" }, toggleSwitch)
        Corner(toggleCircle, 5)
        N("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3) }, toggleSwitch)
        local toggleSwitchStroke = Stroke(toggleSwitch, OUTLINE)
        local toggleSwitchGradient = BlueGrad(toggleSwitch, 180)
        toggleSwitchGradient.Transparency = NumberSequence.new(1)

        function Toggle.Set(self, Value, Silent)
            self.Value = Value
            if Value then
                Library:Tween({ Position = UDim2.new(1, -10, 0, 0) }, nil, toggleCircle)
                Library:Tween({ Color = Color3.fromRGB(29, 146, 234) }, nil, toggleSwitchStroke)
                Library:Tween({ BackgroundColor3 = WHITE }, nil, toggleSwitch)
                Library:TweenGradient(toggleSwitchGradient, 0)
            else
                Library:Tween({ Position = UDim2.new(0, 0, 0, 0) }, nil, toggleCircle)
                Library:Tween({ Color = OUTLINE }, nil, toggleSwitchStroke)
                Library:Tween({ BackgroundColor3 = Color3.fromRGB(24, 24, 26) }, nil, toggleSwitch)
                Library:TweenGradient(toggleSwitchGradient, 1)
            end
            if self.Flag then Library.Flags[self.Flag] = Value end
            if not Silent then
                Library:SafeCallback(self.Callback, Value)
                FireChanged(self, Value)
            end
        end
        function Toggle.SetValue(self, Value) self:Set(Value) end
        function Toggle.OnChanged(self, fn) table.insert(self.Changed, fn); Library:SafeCallback(fn, self.Value) end

        function Toggle.AddColorPicker(self, cIdx, Info)
            Info = Info or {}
            local box = GetAddons(toggleHolder, 35)
            local sq = MakeColorSquare(box, Info.Default or Color3.fromRGB(255, 255, 255), 2)
            local cp = MakeColorpicker(sq, { Title = Info.Title or self.Title, Flag = cIdx, Default = Info.Default, Callback = Info.Callback })
            table.insert(self.Addons, { Frame = sq, Object = cp })
            self.Colorpicker = self.Colorpicker or cp
            return cp
        end
        function Toggle.AddKeyPicker(self, kIdx, Info)
            local box = GetAddons(toggleHolder, 35)
            local kp = MakeKeypicker(box, kIdx, Info, self)
            table.insert(self.Addons, { Frame = kp.Instance, Object = kp })
            return kp
        end

        if Config.Color then
            Toggle:AddColorPicker(Config.ColorFlag, { Default = Config.Color, Callback = Config.ColorCallback })
        end

        Library:Connect(toggleHolder.InputBegan, function(Input)
            if not IsPress(Input) then return end
            for _, addon in ipairs(Toggle.Addons) do
                if IsMouseOverFrame(addon.Frame, Input) then return end
                if addon.Object.IsOpen or addon.Object.Picking then return end
            end
            Toggle:Set(not Toggle.Value)
        end)

        if Toggle.Flag then
            Library.SetFlags[Toggle.Flag] = function(Value)
                if type(Value) == "table" then Toggle:Set(Value.Value, true) else Toggle:Set(Value, true) end
            end
            Library.Flags[Toggle.Flag] = Toggle.Value
            Toggles[Toggle.Flag] = Toggle
        end

        Toggle:Set(Toggle.Value, true)
        return Toggle
    end

    -- Slider -------------------------------------------------------
    function Section.AddSlider(self, a, b)
        local Idx, Config = Norm(a, b)
        local Slider = {
            Type = "Slider",
            Title = Config.Title or Config.Text or "Slider",
            Flag = Idx or Config.Flag,
            Min = Config.Min or 0,
            Max = Config.Max or 100,
            Decimals = Config.Decimals or Config.Rounding or 0,
            Prefix = Config.Prefix or "",
            Suffix = Config.Suffix or "",
            Value = Config.Default or Config.Min or 0,
            Callback = Config.Callback or function() end,
            Changed = {},
        }

        local sliderHolder = N("Frame", {
            BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, H_SLIDER), Name = "slider", BackgroundTransparency = 1,
        }, sectionContent)
        N("TextLabel", {
            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = WHITE, FontFace = Library.Font,
            TextColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), Text = Slider.Title, Name = "title",
        }, sliderHolder)
        local sliderValue = N("TextLabel", {
            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, BackgroundColor3 = WHITE, FontFace = Library.FontBold,
            TextColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), Text = "", Name = "value",
        }, sliderHolder)

        local sliderPill = N("Frame", {
            BackgroundColor3 = ELEMENT, Size = UDim2.new(1, 0, 0, H_BAR), Position = UDim2.new(0, 0, 0, 15),
            Name = "sliderPill", Active = true, ClipsDescendants = true,
        }, sliderHolder)
        Corner(sliderPill, 5)
        Stroke(sliderPill, OUTLINE)

        local sliderFill = N("ImageLabel", {
            BackgroundColor3 = WHITE, Size = UDim2.new(0, 0, 1, 0), Name = "fill", Image = "rbxassetid://100840949142258",
        }, sliderPill)
        Corner(sliderFill, 5)
        BlueGrad(sliderFill, 180)

        local SliderInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local function FormatValue(Value)
            if Slider.Decimals > 0 then return string.format("%." .. Slider.Decimals .. "f", Value) end
            return tostring(math.floor(Value))
        end

        function Slider.Set(self, Value, Silent)
            Value = math.clamp(Value, self.Min, self.Max)
            if self.Decimals > 0 then
                local Mult = 10 ^ self.Decimals
                Value = math.floor(Value * Mult + 0.5) / Mult
            else
                Value = math.floor(Value + 0.5)
            end
            self.Value = Value
            local Alpha = (self.Max == self.Min) and 0 or (Value - self.Min) / (self.Max - self.Min)
            Library:Tween({ Size = UDim2.new(Alpha, 0, 1, 0) }, SliderInfo, sliderFill)
            sliderValue.Text = self.Prefix .. FormatValue(Value) .. self.Suffix
            if self.Flag then Library.Flags[self.Flag] = Value end
            if not Silent then
                Library:SafeCallback(self.Callback, Value)
                FireChanged(self, Value)
            end
        end
        function Slider.SetValue(self, Value) self:Set(tonumber(Value) or self.Value) end
        function Slider.OnChanged(self, fn) table.insert(self.Changed, fn); Library:SafeCallback(fn, self.Value) end

        local dragging, dragInput = false, nil
        local function UpdateValueFromMouse(Input)
            local m = PointerLocation(Input)
            local p, sz = sliderPill.AbsolutePosition, sliderPill.AbsoluteSize
            local Alpha = math.clamp((m.X - p.X) / sz.X, 0, 1)
            Slider:Set(Slider.Min + Alpha * (Slider.Max - Slider.Min))
        end
        Library:Connect(sliderPill.InputBegan, function(Input)
            if IsPress(Input) then
                dragging = true
                dragInput = Input
                SetScrollLock(sliderPill, true)
                UpdateValueFromMouse(Input)
            end
        end)
        Library:Connect(UserInputService.InputChanged, function(Input)
            if not dragging or not IsMove(Input) then return end
            if Input.UserInputType == Enum.UserInputType.Touch and Input ~= dragInput then return end
            UpdateValueFromMouse(Input)
        end)
        Library:Connect(UserInputService.InputEnded, function(Input)
            if not IsPress(Input) then return end
            if Input.UserInputType == Enum.UserInputType.Touch and Input ~= dragInput then return end
            if dragging then
                dragging = false
                SetScrollLock(sliderPill, false)
            end
        end)

        if Slider.Flag then
            Library.SetFlags[Slider.Flag] = function(Value) Slider:Set(Value, true) end
            Library.Flags[Slider.Flag] = Slider.Value
            Options[Slider.Flag] = Slider
        end

        Slider:Set(Slider.Value, true)
        return Slider
    end

    -- Dropdown -----------------------------------------------------
    function Section.AddDropdown(self, a, b)
        local Idx, Config = Norm(a, b)
        local Dropdown = {
            Type = "Dropdown",
            Title = Config.Title or Config.Text or "Dropdown",
            Flag = Idx or Config.Flag,
            Options = Config.Options or Config.Values or {},
            Multi = Config.Multi or false,
            AllowNull = Config.AllowNull or false,
            IsOpen = false,
            Callback = Config.Callback or function() end,
            Changed = {},
        }

        local function Resolve(def)
            if def == nil then return nil end
            if type(def) == "number" then return Dropdown.Options[def] end
            return def
        end

        if Dropdown.Multi then
            Dropdown.Value = {}
            if type(Config.Default) == "table" then
                for _, d in ipairs(Config.Default) do
                    local r = Resolve(d)
                    if r then table.insert(Dropdown.Value, r) end
                end
            elseif Config.Default ~= nil then
                local r = Resolve(Config.Default)
                if r then Dropdown.Value = { r } end
            end
        else
            if Config.Default ~= nil then Dropdown.Value = Resolve(Config.Default)
            elseif not Dropdown.AllowNull then Dropdown.Value = Dropdown.Options[1] end
        end

        local dropdownHolder = N("Frame", {
            BackgroundColor3 = WHITE, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 15 + H_DROPDOWN),
            Name = "dropdown", BackgroundTransparency = 1,
        }, sectionContent)
        N("TextLabel", {
            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = WHITE, FontFace = Library.Font,
            TextColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), Text = Dropdown.Title, Name = "title",
        }, dropdownHolder)

        local dropdownPill = N("Frame", {
            BackgroundColor3 = ELEMENT, Size = UDim2.new(1, 0, 0, H_DROPDOWN), Position = UDim2.new(0, 0, 0, 15),
            Name = "dropdownPill", Active = true,
        }, dropdownHolder)
        Corner(dropdownPill, 5)
        Stroke(dropdownPill, OUTLINE)
        Pad(dropdownPill, 5, 5, 5, 5)

        local dropdownItems = N("TextLabel", {
            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = WHITE, FontFace = Library.Font,
            TextColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.new(1, -15, 1, 0), Text = "",
            TextTruncate = Enum.TextTruncate.AtEnd, Name = "items",
        }, dropdownPill)

        local arrowDown = N("ImageLabel", {
            BackgroundColor3 = WHITE, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 15, 0, 15), Image = "rbxassetid://116827751679514", Name = "arrow",
        }, dropdownPill)

        local dropdownList = N("Frame", {
            BackgroundColor3 = ELEMENT, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 0),
            Position = UDim2.new(0, 0, 0, 20 + H_DROPDOWN), Name = "dropdownList", Visible = false,
        }, dropdownHolder)
        Corner(dropdownList, 5)
        Stroke(dropdownList, OUTLINE)
        Pad(dropdownList, 5, 5, 5, 5)
        N("UIListLayout", {
            Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalFlex = Enum.UIFlexAlignment.Fill,
        }, dropdownList)

        local itemLabels = {}

        local function IsSelected(Option)
            if Dropdown.Multi then
                for _, V in ipairs(Dropdown.Value) do if V == Option then return true end end
                return false
            end
            return Dropdown.Value == Option
        end
        local function RefreshPill()
            if Dropdown.Multi then
                if #Dropdown.Value == 0 then dropdownItems.Text = "None"
                else
                    local t = {}
                    for _, v in ipairs(Dropdown.Value) do t[#t + 1] = tostring(v) end
                    dropdownItems.Text = table.concat(t, ", ")
                end
            else
                dropdownItems.Text = Dropdown.Value ~= nil and tostring(Dropdown.Value) or "None"
            end
        end
        local function RefreshItems()
            for Option, Lbl in pairs(itemLabels) do
                Lbl.FontFace = IsSelected(Option) and Library.FontBold or Library.Font
            end
        end

        function Dropdown.Set(self, Value, Silent)
            if self.Multi then
                if type(Value) == "table" then self.Value = Value
                elseif type(Value) == "string" then self.Value = { Value }
                else self.Value = {} end
            else
                self.Value = Value
            end
            RefreshPill()
            RefreshItems()
            if self.Flag then Library.Flags[self.Flag] = self.Value end
            if not Silent then
                Library:SafeCallback(self.Callback, self.Value)
                FireChanged(self, self.Value)
            end
        end
        function Dropdown.SetValue(self, Value) self:Set(Value) end
        function Dropdown.OnChanged(self, fn) table.insert(self.Changed, fn); Library:SafeCallback(fn, self.Value) end

        function Dropdown.ToggleOption(self, Option)
            if self.Multi then
                local Found = false
                for i, V in ipairs(self.Value) do
                    if V == Option then table.remove(self.Value, i); Found = true; break end
                end
                if not Found then table.insert(self.Value, Option) end
                self:Set(self.Value)
            else
                if self.AllowNull and self.Value == Option then self:Set(nil) else self:Set(Option) end
                self:Close()
            end
        end

        function Dropdown.Open(self)
            self.IsOpen = true
            dropdownList.AutomaticSize = Enum.AutomaticSize.Y
            dropdownList.Visible = true
            Library:Tween({ Rotation = 180 }, nil, arrowDown)
        end
        function Dropdown.Close(self)
            self.IsOpen = false
            dropdownList.AutomaticSize = Enum.AutomaticSize.None
            dropdownList.Size = UDim2.new(1, 0, 0, 0)
            dropdownList.Visible = false
            Library:Tween({ Rotation = 0 }, nil, arrowDown)
        end
        function Dropdown.Toggle(self)
            if self.IsOpen then self:Close() else self:Open() end
        end

        local function BuildItems()
            for _, l in pairs(itemLabels) do l:Destroy() end
            itemLabels = {}
            for i, Option in ipairs(Dropdown.Options) do
                local item = N("TextLabel", {
                    TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = WHITE, BackgroundTransparency = 1,
                    TextColor3 = WHITE, FontFace = Library.Font, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, TOUCH and 22 or 0),
                    Text = tostring(Option), Name = "item", Active = true, LayoutOrder = i,
                }, dropdownList)
                Library:Connect(item.InputBegan, function(Input)
                    if IsPress(Input) then Dropdown:ToggleOption(Option) end
                end)
                itemLabels[Option] = item
            end
            RefreshPill()
            RefreshItems()
        end

        function Dropdown.SetValues(self, list)
            self.Options = list
            if self.Multi then
                local keep = {}
                for _, v in ipairs(self.Value) do if table.find(list, v) then table.insert(keep, v) end end
                self.Value = keep
            elseif self.Value ~= nil and not table.find(list, self.Value) then
                self.Value = nil
            end
            BuildItems()
        end
        Dropdown.SetOptions = Dropdown.SetValues
        Dropdown.Refresh = Dropdown.SetValues

        BuildItems()

        Library:Connect(dropdownPill.InputBegan, function(Input)
            if IsPress(Input) then Dropdown:Toggle() end
        end)

        Library:Connect(UserInputService.InputBegan, function(Input)
            if not IsPress(Input) then return end
            if not Dropdown.IsOpen then return end
            if not IsMouseOverFrame(dropdownPill, Input) and not IsMouseOverFrame(dropdownList, Input) then Dropdown:Close() end
        end)

        if Dropdown.Flag then
            Library.SetFlags[Dropdown.Flag] = function(Value) Dropdown:Set(Value, true) end
            Library.Flags[Dropdown.Flag] = Dropdown.Value
            Options[Dropdown.Flag] = Dropdown
        end

        return Dropdown
    end

    -- Textbox ------------------------------------------------------
    function Section.AddTextbox(self, a, b)
        local Idx, Config = Norm(a, b)
        local Textbox = {
            Type = "Input",
            Title = Config.Title or Config.Text or "Textbox",
            Flag = Idx or Config.Flag,
            Placeholder = Config.Placeholder or "text...",
            Icon = Config.Icon,
            Value = Config.Default or "",
            Callback = Config.Callback or function() end,
            Changed = {},
        }

        local holder = N("Frame", {
            BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, H_INPUT), Name = "textbox", BackgroundTransparency = 1,
        }, sectionContent)
        local box = N("TextBox", {
            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = ELEMENT, FontFace = Library.Font,
            TextColor3 = WHITE, ClearTextOnFocus = false, PlaceholderText = Textbox.Placeholder, Size = UDim2.new(1, 0, 1, 0),
            Text = Textbox.Value, Name = "input",
        }, holder)
        Corner(box, 5)
        Stroke(box, OUTLINE)
        Pad(box, 5, 5, 5, 5)

        if Textbox.Icon then
            N("ImageLabel", {
                BackgroundTransparency = 1, Position = UDim2.new(1, -15, 0, 0), Size = UDim2.new(0, 15, 0, 15), Image = Textbox.Icon,
            }, box)
        end

        function Textbox.Set(self, Value, Animate)
            Value = tostring(Value or "")
            if Animate then
                task.spawn(function()
                    for i = 1, #Value do
                        box.Text = string.sub(Value, 1, i)
                        task.wait(0.02)
                    end
                end)
            else
                box.Text = Value
            end
            self.Value = Value
            if self.Flag then Library.Flags[self.Flag] = Value end
            Library:SafeCallback(self.Callback, Value)
            FireChanged(self, Value)
        end
        function Textbox.SetValue(self, Value) self:Set(Value, false) end
        function Textbox.OnChanged(self, fn) table.insert(self.Changed, fn); Library:SafeCallback(fn, self.Value) end

        Library:Connect(box.FocusLost, function() Textbox:Set(box.Text, false) end)

        if Textbox.Flag then
            Library.SetFlags[Textbox.Flag] = function(V) Textbox:Set(V, false) end
            Library.Flags[Textbox.Flag] = Textbox.Value
            Options[Textbox.Flag] = Textbox
        end
        return Textbox
    end
    Section.AddInput = Section.AddTextbox

    -- Text indicator -----------------------------------------------
    function Section.AddTextIndicator(self, a, b)
        local Idx, Config = Norm(a, b)
        local Indicator = {
            Type = "Indicator",
            Title = Config.Title or Config.Text or "Indicator",
            Flag = Idx or Config.Flag,
            Value = Config.Default or "",
            Icon = Config.Icon,
        }

        local holder = N("Frame", {
            BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 25), Name = "textindication", BackgroundTransparency = 1,
        }, sectionContent)
        local box = N("TextBox", {
            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = ELEMENT, FontFace = Library.Font,
            TextColor3 = WHITE, ClearTextOnFocus = false, TextEditable = false, Active = false, Selectable = false,
            PlaceholderText = Config.Placeholder or "", Size = UDim2.new(1, 0, 1, 0), Text = Indicator.Value, Name = "input",
        }, holder)
        Corner(box, 5)
        Stroke(box, OUTLINE)
        Pad(box, 5, 5, 5, 5)

        if Indicator.Icon then
            N("ImageLabel", {
                BackgroundTransparency = 1, Position = UDim2.new(1, -15, 0, 0), Size = UDim2.new(0, 15, 0, 15), Image = Indicator.Icon,
            }, box)
        end

        function Indicator.Set(self, Value, Animate)
            Value = tostring(Value or "")
            if Animate then
                task.spawn(function()
                    for i = 1, #Value do
                        box.Text = string.sub(Value, 1, i)
                        task.wait(0.02)
                    end
                end)
            else
                box.Text = Value
            end
            self.Value = Value
            if self.Flag then Library.Flags[self.Flag] = Value end
        end
        Indicator.SetValue = Indicator.Set

        if Indicator.Flag then
            Library.SetFlags[Indicator.Flag] = function(V) Indicator:Set(V, false) end
            Library.Flags[Indicator.Flag] = Indicator.Value
        end
        return Indicator
    end

    -- Standalone colorpicker --------------------------------------
    function Section.AddColorpicker(self, a, b)
        local Idx, Config = Norm(a, b)
        local Title = Config.Title or Config.Text or "Colorpicker"

        local holder = N("Frame", {
            BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, S_SQUARE), Name = "colorpicker", BackgroundTransparency = 1, Active = false,
        }, sectionContent)
        N("TextLabel", {
            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, FontFace = Library.Font,
            TextColor3 = WHITE, Size = UDim2.new(1, -50, 1, 0), Text = Title, Name = "title",
        }, holder)

        local square = N("Frame", {
            BackgroundColor3 = Config.Default or WHITE, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, -S_SQUARE, 0.5, 0),
            Size = UDim2.new(0, S_SQUARE, 0, S_SQUARE), Name = "square", Active = true,
        }, holder)
        Corner(square, 5)
        Stroke(square, OUTLINE)

        return MakeColorpicker(square, { Title = Title, Flag = Idx or Config.Flag, Default = Config.Default, Callback = Config.Callback })
    end
    Section.AddColorPicker = Section.AddColorpicker

    -- Label --------------------------------------------------------
    function Section.AddLabel(self, text, wrap)
        local L = {}
        local holder = N("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15), Name = "label",
            AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        }, sectionContent)
        local lbl = N("TextLabel", {
            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            BackgroundTransparency = 1, FontFace = Library.Font, TextColor3 = WHITE, Text = tostring(text),
            Size = wrap and UDim2.new(1, 0, 0, 15) or UDim2.new(1, 0, 1, 0), TextWrapped = wrap and true or false,
            AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
            TextTruncate = wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
        }, holder)
        L.TextLabel = lbl
        function L.SetText(self, t) lbl.Text = tostring(t) end
        function L.AddColorPicker(self, cIdx, Info)
            Info = Info or {}
            local sq = MakeColorSquare(GetAddons(holder, 0), Info.Default or WHITE, 2)
            return MakeColorpicker(sq, { Title = Info.Title or text, Flag = cIdx, Default = Info.Default, Callback = Info.Callback })
        end
        function L.AddKeyPicker(self, kIdx, Info)
            return MakeKeypicker(GetAddons(holder, 0), kIdx, Info, nil)
        end
        return L
    end

    function Section.AddDivider(self)
        local holder = N("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 7), Name = "divider" }, sectionContent)
        N("Frame", { BackgroundColor3 = OUTLINE, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 1) }, holder)
    end

    -- Button (same style as the original config manager buttons) ---
    function Section.AddButton(self, a, b)
        local Info = a
        if type(a) == "string" then Info = { Text = a, Func = b } end

        local row = N("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, H_BUTTON), Name = "buttonrow" }, sectionContent)
        N("UIListLayout", {
            Padding = UDim.new(0, 5), FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalFlex = Enum.UIFlexAlignment.Fill,
        }, row)

        local function Make(inf)
            local B = { Text = inf.Text or "Button", Func = inf.Func or inf.Callback, DoubleClick = inf.DoubleClick }
            local btn = N("TextButton", {
                BackgroundColor3 = ELEMENT, Size = UDim2.new(1, 0, 1, 0), FontFace = Library.FontBold, Text = B.Text,
                TextColor3 = WHITE, TextSize = 14, AutoButtonColor = false,
            }, row)
            Corner(btn, 4)
            Stroke(btn, OUTLINE)
            B.Instance = btn
            local armed = false
            Library:Connect(btn.MouseButton1Down, function()
                if B.DoubleClick then
                    if not armed then
                        armed = true
                        btn.Text = "Click again to confirm"
                        task.delay(2, function() armed = false; if btn.Parent then btn.Text = B.Text end end)
                        return
                    end
                    armed = false
                    btn.Text = B.Text
                end
                Library:SafeCallback(B.Func)
            end)
            function B.SetText(self, t) self.Text = t; btn.Text = t end
            function B.AddButton(self, a2, b2)
                if type(a2) == "string" then a2 = { Text = a2, Func = b2 } end
                return Make(a2)
            end
            return B
        end
        return Make(Info)
    end

    -- Config manager (original) ------------------------------------
    function Section.AddConfigManager(self)
        if Library._ConfigManagerMade then
            warn("[Library] Config manager already exists — only one is allowed.")
            return
        end
        Library._ConfigManagerMade = true

        local CM = { Selected = nil }

        local manager = N("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), Name = "configmanager" }, sectionContent)
        N("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, manager)

        N("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), FontFace = Library.Font, Text = "Config Manager",
            TextColor3 = WHITE, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
        }, manager)

        local selected = N("Frame", { BackgroundColor3 = ELEMENT, Size = UDim2.new(1, 0, 0, 25) }, manager)
        Corner(selected, 5)
        Stroke(selected, OUTLINE)
        Pad(selected, 5, 5, 5, 5)
        local selLabel = N("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), FontFace = Library.Font, Text = "selected: none",
            TextColor3 = WHITE, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left,
        }, selected)

        local listFrame = N("Frame", { BackgroundColor3 = ELEMENT, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), Name = "list" }, manager)
        Corner(listFrame, 5)
        Stroke(listFrame, OUTLINE)
        Pad(listFrame, 5, 5, 5, 5)
        N("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalFlex = Enum.UIFlexAlignment.Fill }, listFrame)

        local nameBox = N("TextBox", {
            BackgroundColor3 = ELEMENT, FontFace = Library.Font, TextColor3 = WHITE, TextSize = 14, ClearTextOnFocus = false,
            PlaceholderText = "Config name...", Text = "", Size = UDim2.new(1, 0, 0, H_BUTTON), TextXAlignment = Enum.TextXAlignment.Left,
        }, manager)
        Corner(nameBox, 4)
        Stroke(nameBox, OUTLINE)
        N("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, nameBox)

        local function MakeRow()
            local row = N("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, H_BUTTON) }, manager)
            N("UIListLayout", {
                Padding = UDim.new(0, 5), FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
                HorizontalFlex = Enum.UIFlexAlignment.Fill,
            }, row)
            return row
        end
        local function MakeButton(parent, text, onClick)
            local b = N("TextButton", {
                BackgroundColor3 = ELEMENT, Size = UDim2.new(1, 0, 1, 0), FontFace = Library.FontBold, Text = text,
                TextColor3 = WHITE, TextSize = 14, AutoButtonColor = false,
            }, parent)
            Corner(b, 4)
            Stroke(b, OUTLINE)
            Library:Connect(b.MouseButton1Down, onClick)
            return b
        end
        local function GetConfigFolder()
            local folder = Library.Directory .. Library.Folders.Configs
            if not isfolder(folder) then makefolder(folder) end
            return folder
        end
        local function ConfigPath(Name) return GetConfigFolder() .. "/" .. Name .. ".json" end

        function CM.Refresh(self)
            for _, c in pairs(listFrame:GetChildren()) do
                if c:IsA("TextLabel") then c:Destroy() end
            end
            local folder = GetConfigFolder()
            local ok, files = pcall(function() return listfiles(folder) end)
            if not ok then
                warn("[ConfigManager] listfiles failed:", tostring(files))
                return
            end
            for _, f in ipairs(files) do
                local s = tostring(f)
                if s:sub(-5) == ".json" then
                    local name = s:match("([^/\\]+)%.json$")
                    if name then
                        local item = N("TextLabel", {
                            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.Y,
                            FontFace = (name == CM.Selected) and Library.FontBold or Library.Font, Text = name, TextColor3 = WHITE,
                            TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Active = true,
                        }, listFrame)
                        Library:Connect(item.InputBegan, function(I)
                            if IsPress(I) then
                                CM.Selected = name
                                selLabel.Text = "selected: " .. name
                                CM:Refresh()
                            end
                        end)
                    end
                end
            end
        end

        local row1 = MakeRow()
        MakeButton(row1, "Refresh", function() CM:Refresh() end)
        MakeButton(row1, "Set Auto-Load", function()
            if CM.Selected then
                writefile(Library.Directory .. "/AutoLoad.json", CM.Selected)
                Library:Notify("Config", "Auto-Load set to " .. CM.Selected)
            end
        end)

        local row2 = MakeRow()
        MakeButton(row2, "Delete", function()
            if CM.Selected then
                local path = ConfigPath(CM.Selected)
                if isfile(path) then delfile(path) end
                CM.Selected = nil
                selLabel.Text = "selected: none"
                CM:Refresh()
            end
        end)
        MakeButton(row2, "New", function()
            local name = nameBox.Text
            if not name or #name == 0 then name = "config_" .. tostring(os.time()) end
            CM.Selected = name
            selLabel.Text = "selected: " .. name
            CM:Refresh()
        end)

        local row3 = MakeRow()
        MakeButton(row3, "Save", function()
            local name = CM.Selected or nameBox.Text
            if not name or #name == 0 then Library:Notify("Config", "Enter a name first"); return end
            local encoded = Library:GetConfig()
            if not encoded then Library:Notify("Config", "Failed to encode"); return end
            local ok, err = pcall(writefile, ConfigPath(name), encoded)
            if not ok then Library:Notify("Config", "Save failed: " .. tostring(err)); return end
            CM.Selected = name
            selLabel.Text = "selected: " .. name
            CM:Refresh()
            Library:Notify("Config", "Saved " .. name)
        end)
        MakeButton(row3, "Load", function()
            if not CM.Selected then Library:Notify("Config", "Select a config first"); return end
            local path = ConfigPath(CM.Selected)
            if isfile(path) then
                Library:LoadConfig(readfile(path))
                Library:Notify("Config", "Loaded " .. CM.Selected)
            end
        end)

        CM:Refresh()
        return CM
    end
end

----------------------------------------------------------------------
-- Window (original)
----------------------------------------------------------------------
do
    function Library.CreateWindow(Self, Data)
        Data = Data or {}
        if Data.SubTitle and not Data.GameName then Data.GameName = Data.SubTitle end
        return Library:Window(Data)
    end

    Library.Window = function(Self, Data)
        local Window = {
            Title = "Feral Hub",
            GameName = "Some game",
            Logo = "rbxassetid://121449270899000",
        }
        for Index, Value in pairs(Data or {}) do Window[Index] = Value end
        Library.MainWindow = Window

        -- the window sits inside a scaler so it always fits the screen (phones, small windows)
        local BaseSize = Window.Size or UDim2.new(0, 650, 0, 450)
        local WindowScale = 1
        local scaler = N("Frame", {
            BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0), Name = "scaler",
        }, Library.Holder)
        local scaleObj = N("UIScale", { Scale = 1 }, scaler)

        local function UpdateScale()
            local vs = Library.Holder.AbsoluteSize
            if vs.X <= 0 or vs.Y <= 0 then
                local cam = workspace.CurrentCamera
                vs = cam and cam.ViewportSize or Vector2.new(1920, 1080)
            end

            local s
            if Window.Scale then
                -- manual override: Window.Scale = 0.5 in the window options, or Window:SetScale(0.5)
                s = Window.Scale
            else
                -- fraction of the screen the window is allowed to take up
                local SmallScreen = IsMobile or vs.X < 1100 or vs.Y < 700
                local Fill = Window.ScreenFill or (SmallScreen and 0.5 or 0.95)
                local bw, bh = BaseSize.X.Offset, BaseSize.Y.Offset
                s = Window.MaxScale or (IsMobile and 0.8 or 1)
                if bw > 0 then s = math.min(s, (vs.X * Fill) / bw) end
                if bh > 0 then s = math.min(s, (vs.Y * Fill) / bh) end
            end

            s = math.clamp(s, 0.3, 3)
            WindowScale = s
            scaleObj.Scale = s
            scaler.Size = UDim2.fromScale(1 / s, 1 / s)
        end
        UpdateScale()
        Library:Connect(Library.Holder:GetPropertyChangedSignal("AbsoluteSize"), UpdateScale)
        function Window.UpdateScale(self) UpdateScale() end
        function Window.SetScale(self, Value) self.Scale = Value; UpdateScale() end

        local main = N("Frame", {
            BackgroundColor3 = Color3.fromRGB(21, 21, 22), AnchorPoint = Vector2.new(0.5, 0.5),
            Size = BaseSize, Position = UDim2.new(0.5, 0, 0.5, 0), Name = "window",
        }, scaler)
        local windowUiStrok1 = Stroke(main, Color3.fromRGB(61, 61, 61))
        Corner(main, 10)

        local top = N("Frame", {
            BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 60), Name = "top", BackgroundTransparency = 1,
        }, main)
        local topCorner = Corner(top, 10)
        topCorner.BottomLeftRadius = UDim.new(0, 0)
        topCorner.BottomRightRadius = UDim.new(0, 0)
        Stroke(top, Color3.fromRGB(60, 60, 60))
        Pad(top, 5, 5, 5, 5)
        N("UIListLayout", {
            Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal,
        }, top)

        local hubInfo = N("ImageLabel", {
            BackgroundColor3 = WHITE, Image = "rbxassetid://100840949142258", Size = UDim2.new(0, 162, 0, 50), Name = "hubInfo",
        }, top)
        Corner(hubInfo, 5)
        Pad(hubInfo, 5, 5, 5, 5)

        N("ImageLabel", {
            BackgroundColor3 = WHITE, Image = Window.Logo, Size = UDim2.new(0, 35, 0, 35), BackgroundTransparency = 1,
            Name = "logo", Position = UDim2.new(0, 0, 0, 2),
        }, hubInfo)

        N("TextLabel", {
            TextWrapped = true, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = WHITE,
            FontFace = Library.FontBold, TextColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 15),
            Text = tostring(Window.Title), Name = "title", Position = UDim2.new(0, 40, 0, 5),
        }, hubInfo)

        N("TextLabel", {
            TextWrapped = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            BackgroundColor3 = WHITE, FontFace = Library.FontBold, TextColor3 = WHITE, BackgroundTransparency = 1,
            Size = UDim2.new(1, -40, 0, 15), Text = Window.GameName, Name = "gamename", Position = UDim2.new(0, 40, 0, 20),
        }, hubInfo)

        BlueGrad(hubInfo, 90)

        -- Close (X) button in the window's top-right corner. Shown on touch devices by default.
        -- Window options: CloseButton = true/false
        do
            local ShowClose = Window.CloseButton
            if ShowClose == nil then ShowClose = IsMobile or UserInputService.TouchEnabled end

            local closeBtn = N("TextButton", {
                BackgroundColor3 = Color3.fromRGB(28, 28, 30), AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -8, 0, 8), Size = UDim2.new(0, 28, 0, 28), Text = "X",
                FontFace = Library.FontBold, TextSize = 16, TextColor3 = WHITE, AutoButtonColor = false,
                Name = "closeButton", ZIndex = 20, Visible = ShowClose and true or false,
            }, main)
            Corner(closeBtn, 6)
            Stroke(closeBtn, OUTLINE)
            Window.CloseButtonInstance = closeBtn
            Library:Connect(closeBtn.Activated, function() Window:SetVisible(false) end)
            function Window.SetCloseButtonVisible(self, Value) closeBtn.Visible = Value and true or false end
        end

        local DragInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

        do
            local Dragging = false
            local DragStart, StartPos, DragInput

            Library:Connect(UserInputService.InputBegan, function(Input)
                if not IsPress(Input) then return end
                if not IsMouseOverFrame(top, Input) then return end
                if Window.CloseButtonInstance and Window.CloseButtonInstance.Visible and IsMouseOverFrame(Window.CloseButtonInstance, Input) then return end
                for _, Child in pairs(Library.Holder:GetChildren()) do
                    if Child:IsA("Frame") and Child.Name == "colorpickerPopup" and Child.Visible and IsMouseOverFrame(Child, Input) then
                        return
                    end
                end
                Dragging = true
                DragInput = Input
                DragStart = Input.Position
                StartPos = main.Position
                Library:Tween({ Color = Color3.fromRGB(80, 80, 80) }, nil, windowUiStrok1)
            end)

            Library:Connect(UserInputService.InputChanged, function(Input)
                if not Dragging or not IsMove(Input) then return end
                if Input.UserInputType == Enum.UserInputType.Touch and Input ~= DragInput then return end
                -- offsets inside the scaler are in scaled units
                local Delta = (Input.Position - DragStart) / WindowScale
                local TargetPos = UDim2.new(
                    StartPos.X.Scale, StartPos.X.Offset + Delta.X,
                    StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y
                )
                Library:Tween({ Position = TargetPos }, DragInfo, main)
            end)

            Library:Connect(UserInputService.InputEnded, function(Input)
                if not IsPress(Input) then return end
                if Input.UserInputType == Enum.UserInputType.Touch and Input ~= DragInput then return end
                if Dragging then
                    Dragging = false
                    Library:Tween({ Color = Color3.fromRGB(61, 61, 61) }, nil, windowUiStrok1)
                end
            end)
        end

        Window.Open = true
        Window.OpenPosition = UDim2.new(0.5, 0, 0.5, 0)
        Window.ClosedPosition = UDim2.new(0.5, 0, 1.4, 0)

        function Window.SetVisible(self, Value)
            if self.Open == Value then return end
            self.Open = Value
            if Value then
                main.Visible = true
                main.Position = self.ClosedPosition
                Library:Tween({ Position = self.OpenPosition }, nil, main)
            else
                Library:ClosePopups()
                local T = Library:Tween({ Position = self.ClosedPosition }, nil, main)
                T.Completed:Connect(function()
                    if not self.Open then main.Visible = false end
                end)
            end
            if self.Watermark then self.Watermark.Active = Value end
        end
        function Window.Toggle(self) self:SetVisible(not self.Open) end

        -- Floating open/close button (phones have no keyboard to press the menu key).
        -- Tap = show/hide the UI, hold and drag = move the button.
        -- Window:Create options: MobileButton = true/false (default: true on touch-only devices).
        do
            local ShowButton = Window.MobileButton
            if ShowButton == nil then ShowButton = IsMobile or UserInputService.TouchEnabled end

            local btn = N("Frame", {
                BackgroundColor3 = Color3.fromRGB(20, 20, 21), Size = UDim2.new(0, 46, 0, 46),
                Position = UDim2.new(1, -62, 0.35, 0), Name = "mobileToggle", Active = true, ZIndex = 50, Visible = ShowButton and true or false,
            }, Library.Holder)
            Corner(btn, 23)
            Stroke(btn, Color3.fromRGB(61, 61, 61))
            N("ImageLabel", {
                BackgroundTransparency = 1, Image = Window.Logo, AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 30, 0, 30), ZIndex = 51, Name = "logo",
            }, btn)
            Library.MobileButton = btn

            local btnDown, btnInput, btnMoved = false, nil, false
            local btnStartIn, btnStartPos

            Library:Connect(btn.InputBegan, function(Input)
                if not IsPress(Input) then return end
                btnDown, btnInput, btnMoved = true, Input, false
                btnStartIn = Input.Position
                btnStartPos = btn.Position
            end)
            Library:Connect(UserInputService.InputChanged, function(Input)
                if not btnDown or not IsMove(Input) then return end
                if Input.UserInputType == Enum.UserInputType.Touch and Input ~= btnInput then return end
                local d = Input.Position - btnStartIn
                if d.Magnitude > 8 then btnMoved = true end
                if btnMoved then
                    btn.Position = UDim2.new(btnStartPos.X.Scale, btnStartPos.X.Offset + d.X, btnStartPos.Y.Scale, btnStartPos.Y.Offset + d.Y)
                end
            end)
            Library:Connect(UserInputService.InputEnded, function(Input)
                if not btnDown or not IsPress(Input) then return end
                if Input.UserInputType == Enum.UserInputType.Touch and Input ~= btnInput then return end
                btnDown = false
                if not btnMoved then Window:SetVisible(not Window.Open) end
            end)

            function Library.SetMobileButtonVisible(Self, Value) btn.Visible = Value and true or false end
        end
        function Library.Toggle(Self) Window:SetVisible(not Window.Open) end

        function Library.ClosePopups(Self)
            for _, Child in pairs(Library.Holder:GetChildren()) do
                if Child:IsA("Frame") and Child.Name == "colorpickerPopup" then Child.Visible = false end
            end
        end

        Library:Connect(UserInputService.InputBegan, function(Input, gp)
            if gp or UserInputService:GetFocusedTextBox() then return end
            if os.clock() - (Library.LastPick or 0) < 0.15 then return end
            for _, kp in ipairs(Library.KeyPickers) do if kp.Picking then return end end
            if Input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local tk = Library.ToggleKeybind
            local want
            if tk then want = tk.Value
            elseif typeof(Library.Keybind) == "EnumItem" then want = Library.Keybind.Name
            else want = tostring(Library.Keybind) end
            if Input.KeyCode.Name == want then Window:SetVisible(not Window.Open) end
        end)

        -- Watermark ------------------------------------------------
        local watermark = N("Frame", {
            BackgroundColor3 = Color3.fromRGB(20, 20, 21), AnchorPoint = Vector2.new(0, 0), AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.new(0, 0, 0, 30), Position = UDim2.new(0.5, -100, 0.1, 0), Name = "watermark", Active = true, ZIndex = 5,
        }, Library.Holder)
        Corner(watermark, 10)
        Stroke(watermark, OUTLINE)
        Pad(watermark, 5, 10, 5, 10)
        N("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal }, watermark)

        local wmLogo = N("ImageLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(0, 20, 1, 0), Image = "rbxassetid://104479390541433", Name = "logo",
        }, watermark)
        BlueGrad(wmLogo, 90)

        local wmText = N("TextLabel", {
            BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), FontFace = Library.FontBold,
            Text = Window.Title, TextColor3 = WHITE, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Name = "text",
        }, watermark)

        do
            local wmDragging = false
            local wmDragStart, wmStartPos, wmInput

            Library:Connect(UserInputService.InputBegan, function(Input)
                if not Window.Open then return end
                if not IsPress(Input) then return end
                if not IsMouseOverFrame(watermark, Input) then return end
                wmDragging = true
                wmInput = Input
                wmDragStart = Input.Position
                wmStartPos = watermark.Position
            end)
            Library:Connect(UserInputService.InputChanged, function(Input)
                if not wmDragging then return end
                if not IsMove(Input) then return end
                if Input.UserInputType == Enum.UserInputType.Touch and Input ~= wmInput then return end
                local Delta = Input.Position - wmDragStart
                local TargetPos = UDim2.new(
                    wmStartPos.X.Scale, wmStartPos.X.Offset + Delta.X,
                    wmStartPos.Y.Scale, wmStartPos.Y.Offset + Delta.Y
                )
                Library:Tween({ Position = TargetPos }, DragInfo, watermark)
            end)
            Library:Connect(UserInputService.InputEnded, function(Input)
                if not IsPress(Input) then return end
                if Input.UserInputType == Enum.UserInputType.Touch and Input ~= wmInput then return end
                wmDragging = false
            end)
        end

        Window.Watermark = watermark

        function Window.SetWatermark(self, Text, Logo)
            if Text then wmText.Text = Text end
            if Logo then wmLogo.Image = Logo end
        end
        function Library.SetWatermark(Self, Text, Logo) Window:SetWatermark(Text, Logo) end
        function Library.SetWatermarkVisibility(Self, Value) watermark.Visible = Value end

        -- Notifications --------------------------------------------
        function Window.CreateNotification(self, Title, Description)
            local n = N("Frame", {
                BackgroundColor3 = Color3.fromRGB(20, 20, 21), Size = UDim2.new(0, 200, 0, 60), Name = "notification",
                Visible = false, ZIndex = 8, Active = true, AnchorPoint = Vector2.new(0, 0),
            }, Library.Holder)
            Corner(n, 10)
            Stroke(n, OUTLINE)
            Pad(n, 5, 10, 5, 15)

            local v = N("Frame", { BackgroundColor3 = WHITE, Size = UDim2.new(0, 3, 1, 0), Position = UDim2.new(0, -8, 0, 0), Name = "visual" }, n)
            Corner(v, 10)
            Stroke(v, OUTLINE)
            BlueGrad(v, 90)

            local t = N("TextLabel", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 0), FontFace = Library.FontBold,
                Text = Title or "Title", TextColor3 = WHITE, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top, Name = "title",
            }, n)
            BlueGrad(t, 180)

            N("TextLabel", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -20), Position = UDim2.new(0, 0, 0, 20), FontFace = Library.FontBold,
                Text = Description or "description", TextColor3 = Color3.fromRGB(235, 235, 235), TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Name = "desc",
            }, n)
            return n
        end

        Window.NotificationAnchor = UDim2.new(0, 100, 0, 100)

        -- notifications slide in from the left at NotificationAnchor
        local function NotifHiddenPos()
            local a = Window.NotificationAnchor
            return UDim2.new(a.X.Scale, a.X.Offset - 300, a.Y.Scale, a.Y.Offset)
        end

        -- Library:Notify(Title, Description, Duration)  or  Library:Notify(Text, Duration)
        function Library.Notify(Self, Title, Description, Duration)
            if type(Description) ~= "string" then
                Duration = Description
                Description = tostring(Title)
                Title = "Notification"
            end
            Duration = Duration or 3

            local n = Window:CreateNotification(Title, Description)
            n.Position = NotifHiddenPos()
            n.Visible = true
            Library:Tween({ Position = Window.NotificationAnchor }, nil, n)

            task.spawn(function()
                task.wait(Library.Animation.Time + Duration)
                local t = Library:Tween({ Position = NotifHiddenPos() }, nil, n)
                t.Completed:Connect(function() n:Destroy() end)
            end)
        end

        -- Pills ----------------------------------------------------
        function Window.AddCustomPill(self, Title, Description, Logo, AccentColor)
            AccentColor = AccentColor or Color3.fromRGB(255, 255, 255)

            local Pill = {
                Title = Title or "Pill",
                Description = Description or "",
                Logo = ToAsset(Logo, DefaultPillLogo),
                AccentColor = AccentColor,
            }

            local customPill = N("Frame", {
                BackgroundColor3 = WHITE, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 50),
                Name = "customPill", BackgroundTransparency = 1,
            }, top)
            Corner(customPill, 5)

            local pillLogo = N("ImageLabel", {
                BackgroundColor3 = WHITE, Image = Pill.Logo, Size = UDim2.new(0, 35, 0, 35), BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, 2), Name = "logo",
            }, customPill)
            local pillLogoGrad = N("UIGradient", {
                Rotation = 90,
                Color = ColorSequence.new { ColorSequenceKeypoint.new(0, AccentColor), ColorSequenceKeypoint.new(1, AccentColor) },
            }, pillLogo)

            Pad(customPill, 5, 10, 5, 5)

            local pillTitle = N("TextLabel", {
                TextWrapped = true, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = WHITE,
                FontFace = Library.FontBold, TextColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 15),
                Text = Pill.Title, AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(0, 40, 0, 5), Name = "title",
            }, customPill)
            local pillDesc = N("TextLabel", {
                TextWrapped = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                BackgroundColor3 = WHITE, FontFace = Library.FontBold, TextColor3 = Color3.fromRGB(235, 235, 235),
                BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 15), Text = Pill.Description,
                AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(0, 40, 0, 20), Name = "desc",
            }, customPill)
            Stroke(customPill, Color3.fromRGB(41, 41, 41))

            function Pill.Set(self, NewTitle, NewDesc, NewLogo)
                if NewTitle ~= nil then self.Title = NewTitle; pillTitle.Text = NewTitle end
                if NewDesc ~= nil then self.Description = NewDesc; pillDesc.Text = NewDesc end
                if NewLogo ~= nil then self.Logo = ToAsset(NewLogo, self.Logo); pillLogo.Image = self.Logo end
            end
            function Pill.SetTitle(self, t) self:Set(t, nil, nil) end
            function Pill.SetDescription(self, d) self:Set(nil, d, nil) end
            function Pill.SetLogo(self, l) self:Set(nil, nil, l) end
            function Pill.SetAccent(self, color)
                self.AccentColor = color
                pillLogoGrad.Color = ColorSequence.new { ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(1, color) }
            end
            function Pill.Destroy(self) customPill:Destroy() end

            Pill.Instance = customPill
            return Pill
        end

        function Window.AddFPSPill(self, AccentColor, Logo)
            local pill = self:AddCustomPill("FPS", "--", Logo, AccentColor or Color3.fromRGB(255, 255, 255))
            task.spawn(function()
                local frames = 0
                local last = os.clock()
                while Library do
                    frames = frames + 1
                    local now = os.clock()
                    if now - last >= 0.5 then
                        pill:SetDescription(tostring(math.floor(frames / (now - last) + 0.5)))
                        frames = 0
                        last = now
                    end
                    RunService.RenderStepped:Wait()
                end
            end)
            return pill
        end

        function Window.AddPingPill(self, AccentColor, Logo)
            local pill = self:AddCustomPill("Ping", "-- ms", Logo, AccentColor or Color3.fromRGB(255, 255, 255))
            local Stats = game:GetService("Stats")
            task.spawn(function()
                while Library do
                    local ok, ping = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
                    if ok and ping then pill:SetDescription(math.floor(ping) .. " ms") else pill:SetDescription("-- ms") end
                    task.wait(1)
                end
            end)
            return pill
        end

        function Window.AddTimePill(self, AccentColor, Logo)
            local pill = self:AddCustomPill("Time", "--:--:--", Logo, AccentColor or Color3.fromRGB(255, 255, 255))
            task.spawn(function()
                while Library do
                    local t = os.date("*t")
                    pill:SetDescription(string.format("%02d:%02d:%02d", t.hour, t.min, t.sec))
                    task.wait(1)
                end
            end)
            return pill
        end

        function Window.AddCoordsPill(self, AccentColor, Logo)
            local pill = self:AddCustomPill("Coords", "0, 0, 0", Logo, AccentColor or Color3.fromRGB(255, 255, 255))
            task.spawn(function()
                while Library do
                    local char = LocalPlayer.Character
                    if char and char:FindFirstChild("HumanoidRootPart") then
                        local pos = char.HumanoidRootPart.Position
                        pill:SetDescription(string.format("%d, %d, %d", pos.X, pos.Y, pos.Z))
                    else
                        pill:SetDescription("--")
                    end
                    task.wait(0.1)
                end
            end)
            return pill
        end

        function Window.AddUsernamePill(self, AccentColor, Logo)
            local pill = self:AddCustomPill("User", LocalPlayer.DisplayName, Logo, AccentColor or Color3.fromRGB(255, 255, 255))
            task.spawn(function()
                while Library do
                    pill:SetDescription("@" .. LocalPlayer.Name)
                    task.wait(2)
                end
            end)
            return pill
        end

        -- Main frame + sidebar tabs --------------------------------
        local mainFrame = N("Frame", {
            BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 1, -60), Position = UDim2.new(0, 0, 0, 60), Name = "main", BackgroundTransparency = 1,
        }, main)

        local tabs = N("Frame", {
            BackgroundColor3 = WHITE, Size = UDim2.new(0, 170, 1, 0), Name = "tabs", BackgroundTransparency = 1,
        }, mainFrame)

        Window.TabsList = {}

        Corner(tabs, 0)
        Pad(tabs, 10, 10, 10, 15)
        N("UIListLayout", {
            HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
        }, tabs)

        function Window.AddTab(self, Title, Logo)
            local Tab = { Title = Title, Logo = Logo, Selected = false, SubTabsList = {} }

            local tabButton = N("TextButton", {
                TextSize = 14, AutoButtonColor = false, TextColor3 = Color3.fromRGB(0, 0, 0), BackgroundColor3 = Color3.fromRGB(25, 25, 27),
                FontFace = Library.FontBold, BackgroundTransparency = 1, Size = UDim2.new(0, 200, 0, H_TAB), Text = "", Name = "tab",
            }, tabs)
            local tabButtonCorner = Corner(tabButton, 0)
            tabButtonCorner.BottomLeftRadius = UDim.new(0, 0)
            tabButtonCorner.BottomRightRadius = UDim.new(0, 5)
            tabButtonCorner.TopLeftRadius = UDim.new(0, 0)
            tabButtonCorner.TopRightRadius = UDim.new(0, 5)

            N("TextLabel", {
                TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = WHITE, FontFace = Library.FontBold,
                TextColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.new(1, -65, 1, 0), Text = Title, Name = "tabname",
                Position = UDim2.new(0, 35, 0, 0),
            }, tabButton)

            N("ImageLabel", {
                BackgroundColor3 = Color3.fromRGB(126, 126, 126), ImageColor3 = Color3.fromRGB(186, 186, 186),
                Image = "rbxassetid://137833980584453", Size = UDim2.new(0, 25, 0, 25), BackgroundTransparency = 1,
                Name = "", Position = UDim2.new(1, -25, 0, 3),
            }, tabButton)

            N("ImageLabel", {
                BackgroundColor3 = WHITE, Image = Logo or "", Size = UDim2.new(0, 25, 0, 25), BackgroundTransparency = 1,
                Name = "logo", Position = UDim2.new(0, 5, 0, 2),
            }, tabButton)

            local visual = N("Frame", {
                BackgroundColor3 = WHITE, Size = UDim2.new(0, 3, 1, 0), Position = UDim2.new(0, -3, 0, 0), Name = "visual", Visible = false,
            }, tabButton)
            local visualCorner = Corner(visual, 10)
            visualCorner.BottomRightRadius = UDim.new(0, 0)
            visualCorner.TopRightRadius = UDim.new(0, 0)
            Stroke(visual, Color3.fromRGB(41, 41, 41))
            BlueGrad(visual, 90)

            Corner(tabButton, 0)
            Stroke(tabButton, Color3.fromRGB(41, 41, 41))

            local content = N("Frame", {
                BackgroundColor3 = WHITE, Size = UDim2.new(1, -170, 1, 0), Position = UDim2.new(0, 170, 0, 0), Name = "content",
                BackgroundTransparency = 1, Visible = false,
            }, mainFrame)
            Corner(content, 0)

            local subtabs = N("Frame", {
                BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 40), Name = "subtabs", BackgroundTransparency = 1,
            }, content)
            N("UIListLayout", {
                Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal,
            }, subtabs)
            Pad(subtabs, 5, 5, 10, 5)

            local maincontent = N("Frame", {
                BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 1, -40), Position = UDim2.new(0, 0, 0, 40), Name = "maincontent",
                BackgroundTransparency = 1,
            }, content)

            Tab.Content = content
            Tab.SubTabsHolder = maincontent
            Tab.SubtabsFrame = subtabs

            function Tab.Select(self)
                self.Selected = true
                tabButton.BackgroundColor3 = Color3.fromRGB(25, 25, 27)
                visual.Visible = true
                visual.Size = UDim2.new(0, 0, 1, 0)
                content.Visible = true
                Library:Tween({ BackgroundTransparency = 0 }, nil, tabButton)
                Library:Tween({ Size = UDim2.new(0, 3, 1, 0) }, nil, visual)
            end

            function Tab.Unselect(self)
                self.Selected = false
                Library:Tween({ BackgroundTransparency = 1 }, nil, tabButton)
                Library:Tween({ Size = UDim2.new(0, 0, 1, 0) }, nil, visual)
                content.Visible = false
            end

            function Tab.AddSubTab(self, SubTitle, Internal)
                -- an explicit subtab turns the subtab bar back on if a groupbox was added directly to the tab
                if not Internal and self.DefaultSubTab and self.DefaultHidden then
                    self.DefaultHidden = false
                    subtabs.Visible = true
                    maincontent.Position = UDim2.new(0, 0, 0, 40)
                    maincontent.Size = UDim2.new(1, 0, 1, -40)
                    self.DefaultSubTab.Button.Visible = false
                end

                local SubTab = { Title = SubTitle, Selected = false }

                local subTabButton = N("TextButton", {
                    TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = WHITE, BackgroundColor3 = WHITE,
                    FontFace = Library.FontBold, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X,
                    Size = UDim2.new(0, 0, 1, 0), Text = SubTitle, Name = "subtab",
                }, subtabs)

                local subVisual = N("Frame", {
                    BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 5), Position = UDim2.new(0, 0, 1, -2), Name = "visual", Visible = false,
                }, subTabButton)
                Corner(subVisual, 10)
                BlueGrad(subVisual, 90, Color3.fromRGB(0, 103, 255))

                local page = N("Frame", {
                    BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 1, 0), Name = "page", BackgroundTransparency = 1, Visible = false,
                }, maincontent)
                Pad(page, 0, 5, 5, 0)
                N("UIListLayout", {
                    VerticalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
                    FillDirection = Enum.FillDirection.Horizontal,
                }, page)

                local function Column(name)
                    local sf = N("ScrollingFrame", {
                        Active = true, Name = name, ScrollBarImageTransparency = 1, BackgroundColor3 = WHITE,
                        Size = UDim2.new(0, 235, 0, 100), ScrollBarImageColor3 = Color3.fromRGB(0, 0, 0), ScrollBarThickness = 0,
                        BackgroundTransparency = 1, AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    }, page)
                    Pad(sf, 1, 1, 0, 1)
                    N("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
                    return sf
                end
                local left = Column("left")
                local right = Column("right")

                SubTab.Button = subTabButton
                SubTab.Page = page
                SubTab.Left = left
                SubTab.Right = right

                function SubTab.Select(self)
                    self.Selected = true
                    subVisual.Visible = true
                    subVisual.Size = UDim2.new(0, 0, 0, 5)
                    page.Visible = true
                    Library:Tween({ Size = UDim2.new(1, 0, 0, 5) }, nil, subVisual)
                end

                function SubTab.Unselect(self)
                    self.Selected = false
                    Library:Tween({ Size = UDim2.new(0, 0, 0, 5) }, nil, subVisual)
                    page.Visible = false
                end

                function SubTab.AddSection(self, Title, Side)
                    Side = Side or "Left"
                    local Parent = (Side == "Right") and SubTab.Right or SubTab.Left

                    local Section = { Title = Title }

                    local section = N("Frame", {
                        BackgroundColor3 = Color3.fromRGB(24, 24, 26), AutomaticSize = Enum.AutomaticSize.Y,
                        Size = UDim2.new(1, 0, 0, 0), Name = "section",
                    }, Parent)
                    Stroke(section, OUTLINE)
                    local sectionCorner = Corner(section, 3)
                    sectionCorner.BottomLeftRadius = UDim.new(0, 0)
                    sectionCorner.BottomRightRadius = UDim.new(0, 0)

                    local sectionTop = N("ImageLabel", {
                        BackgroundColor3 = WHITE, Image = "rbxassetid://100840949142258", Size = UDim2.new(1, 0, 0, 20), Name = "sectionTop",
                    }, section)
                    local sectionTopCorner = Corner(sectionTop, 3)
                    sectionTopCorner.BottomLeftRadius = UDim.new(0, 0)
                    sectionTopCorner.BottomRightRadius = UDim.new(0, 0)
                    Stroke(sectionTop, Color3.fromRGB(41, 41, 41))

                    N("TextLabel", {
                        TextWrapped = true, TextSize = 14, BackgroundColor3 = WHITE, FontFace = Library.FontBold, TextColor3 = WHITE,
                        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = Title, Name = "title",
                    }, sectionTop)
                    BlueGrad(sectionTop, 180)

                    local sectionContent = N("Frame", {
                        BackgroundColor3 = WHITE, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0),
                        Name = "maincontent", BackgroundTransparency = 1,
                    }, section)
                    Pad(sectionContent, 26, 6, 6, 6)
                    N("UIListLayout", { Padding = UDim.new(0, PAD_ROWS), SortOrder = Enum.SortOrder.LayoutOrder }, sectionContent)

                    Section.Instance = section
                    Section.Content = sectionContent

                    ApplyElements(Section, sectionContent)
                    return Section
                end
                function SubTab.AddLeftGroupbox(self, Title) return self:AddSection(Title, "Left") end
                function SubTab.AddRightGroupbox(self, Title) return self:AddSection(Title, "Right") end

                Library:Connect(subTabButton.MouseButton1Down, function()
                    for _, OtherSubTab in pairs(Tab.SubTabsList) do
                        if OtherSubTab ~= SubTab then OtherSubTab:Unselect() end
                    end
                    SubTab:Select()
                end)

                table.insert(Tab.SubTabsList, SubTab)
                if #Tab.SubTabsList == 1 then SubTab:Select() end
                return SubTab
            end

            -- Linoria-style: groupboxes directly on a tab (single hidden default subtab)
            function Tab.GetDefaultSubTab(self)
                if not self.DefaultSubTab then
                    local st = self:AddSubTab(self.Title, true)
                    st.Button.Visible = false
                    subtabs.Visible = false
                    maincontent.Position = UDim2.new(0, 0, 0, 0)
                    maincontent.Size = UDim2.new(1, 0, 1, 0)
                    self.DefaultSubTab = st
                    self.DefaultHidden = true
                end
                return self.DefaultSubTab
            end
            function Tab.AddSection(self, Title, Side) return self:GetDefaultSubTab():AddSection(Title, Side) end
            function Tab.AddLeftGroupbox(self, Title) return self:GetDefaultSubTab():AddSection(Title, "Left") end
            function Tab.AddRightGroupbox(self, Title) return self:GetDefaultSubTab():AddSection(Title, "Right") end

            Library:Connect(tabButton.MouseButton1Down, function()
                for _, OtherTab in pairs(Window.TabsList) do
                    if OtherTab ~= Tab then OtherTab:Unselect() end
                end
                Tab:Select()
            end)

            table.insert(Window.TabsList, Tab)
            if #Window.TabsList == 1 then Tab:Select() end
            return Tab
        end

        return Window
    end
end

return Library
