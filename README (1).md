# Feral UI Library

A dark, animated Roblox executor UI library: window with tabs / sub-tabs / sections, toggles, sliders, dropdowns, textboxes, colorpickers, buttons, keybinds, a config manager, notifications, pills and a watermark.

- **`Library.lua`** – the library itself
- **`Example.lua`** – showcase script that uses every element
- **`README.md`** – this file

---

## Loading it

Put the files in a GitHub repo and load the library over its raw URL (same idea as Obsidian / Linoria):

```lua
local Repo = "https://raw.githubusercontent.com/<user>/<repo>/main/"
local Library = loadstring(game:HttpGet(Repo .. "Library.lua"))()
```

Running the script again automatically unloads the previous UI first, so you never get duplicates.

> Your executor needs `writefile` / `readfile` / `isfolder` / `makefolder` / `getcustomasset` for custom fonts and configs. Without them the library still works: it falls back to Gotham fonts and the config manager is simply empty.

---

## Quick start

```lua
local Library = loadstring(game:HttpGet(Repo .. "Library.lua"))()

local Window = Library:Window({
    Title = "My Hub",
    GameName = "My Game",
    Logo = "rbxassetid://121449270899000",
})

local Tab     = Window:AddTab("Main", "rbxassetid://106606600179475")
local SubTab  = Tab:AddSubTab("General")
local Section = SubTab:AddSection("Combat", "Left")   -- "Left" or "Right"

Section:AddToggle({
    Title = "Auto farm",
    Flag = "auto_farm",
    Default = false,
    Callback = function(Value)
        print("Auto farm:", Value)
    end,
})

Library:Notify("My Hub", "Loaded!", 3)
```

**Hierarchy:** `Window` → `Tab` (sidebar) → `SubTab` (row of buttons at the top) → `Section` (a box in the left or right column) → elements.

The first tab and the first sub-tab of every tab are selected automatically.

---

## Library

### Window

```lua
local Window = Library:Window({
    Title = "Feral Hub",
    GameName = "Some game",
    Logo = "rbxassetid://...",
    Keybind = Enum.KeyCode.X,     -- menu key (default X)
    NotificationAnchor = true,    -- false hides the draggable "Example" notification
    Watermark = true,             -- false hides the watermark
})
```

| Method | Description |
|---|---|
| `Window:AddTab(Title, Logo)` | Adds a sidebar tab. `Logo` is an image id (optional). |
| `Window:SetVisible(Bool)` / `Window:Toggle()` | Show or hide the menu (animated). |
| `Window:SetTitle(Text)` / `:SetGameName(Text)` / `:SetLogo(Image)` | Change the header. |
| `Window:SetWatermark(Text, Logo)` | Change watermark text / logo (both optional). |
| `Window:SetWatermarkVisible(Bool)` | Show or hide the watermark. |

The menu is dragged by its top bar. The watermark and the notification anchor can be dragged while the menu is open.

### Tab / SubTab / Section

| Call | Description |
|---|---|
| `Tab:AddSubTab(Title)` | Adds a sub-tab to the tab. |
| `SubTab:AddSection(Title, Side)` | Adds a section. `Side` is `"Left"` (default) or `"Right"`. |

### Pills (info boxes in the title bar)

```lua
Window:AddFPSPill()
Window:AddPingPill()
Window:AddTimePill()
Window:AddCoordsPill()
Window:AddUsernamePill()

local Pill = Window:AddCustomPill("Title", "Description", "rbxassetid://logo", Color3.fromRGB(255, 120, 0))
```

Each built-in pill takes an optional accent color. A pill has:
`Pill:Set(Title, Description, Logo)` · `:SetTitle()` · `:SetDescription()` · `:SetLogo()` · `:SetAccent(Color3)` · `:Destroy()`

### Notifications

```lua
Library:Notify("Title", "Description", 3)   -- duration in seconds (default 3)
```

Notifications stack automatically. While the menu is open a draggable "Example" notification is shown – drag it to choose where notifications appear.

### Flags

Every element created with a `Flag` stores its value in `Library.Flags`:

```lua
if Library.Flags.auto_farm then ... end

Library:Get("auto_farm")        -- same as Library.Flags.auto_farm
Library:Set("auto_farm", true)  -- set an element from code (runs its callback)
```

Flag names must be unique. Flagged elements are what the config system saves and loads.

### Configs

```lua
Library:SaveConfig("legit")          -- returns ok, err
Library:LoadConfigFile("legit")      -- returns ok, err
Library:DeleteConfig("legit")
Library:ListConfigs()                -- { "legit", "rage", ... }
Library:SetAutoload("legit")
Library:LoadAutoload()               -- call at the end of your script
Library:GetConfig()                  -- config as a JSON string
Library:LoadConfig(JsonString)
```

Configs live in `<Library.Directory>/Configs/`. Add the built-in UI with `Section:AddConfigManager()`.
Loading a config runs the callback of every element it changes.

### Theme

```lua
Library:SetTheme("Accent", Color3.fromRGB(255, 80, 80))
Library:SetTheme({ Accent = ..., AccentDark = ..., Window = ... })
```

Everything already on screen updates immediately. Available keys and their defaults:

| Key | Used for | Default |
|---|---|---|
| `Accent` / `AccentDark` | gradient (top / bottom) on headers, sliders, toggles, tab bars | `0,131,255` / `0,63,255` |
| `Window` | window background | `21,21,22` |
| `WindowOutline` | window outline | `61,61,61` |
| `Panel` | popups, notifications, watermark | `20,20,21` |
| `Tab` | selected tab background | `25,25,27` |
| `Section` | section background, toggle off state | `24,24,26` |
| `Element` | slider, dropdown, textbox, button background | `28,28,30` |
| `Outline` / `OutlineLight` | borders | `40,40,40` / `60,60,60` |
| `Text` / `SubText` | main / secondary text | `255,255,255` / `235,235,235` |
| `ToggleOn` | toggle and button highlight outline | `29,146,234` |

### Other settings and functions

| | |
|---|---|
| `Library.Directory` | Folder for configs and fonts (default `"feral"`). Set it before creating the window. |
| `Library.Animation` | `{ Time = 0.3, Style = "Exponential", Direction = "Out" }` – any `Enum.EasingStyle` / `Enum.EasingDirection` name. |
| `Library.FontUrls` | `{ Regular = url, Bold = url }` – TTF files that are downloaded and used as fonts. |
| `Library:SetFonts(Regular, Bold)` | Use your own `Font` objects (call before creating the window). |
| `Library:SetMenuKey(KeyCode or "Name")` | Change the menu key at runtime. |
| `Library.MouseOffset` | `Vector2` – see *Troubleshooting*. |
| `Library:OnUnload(Function)` | Runs when the UI is unloaded. |
| `Library:Unload()` | Disconnects everything, destroys the UI. |
| `Library.Unloaded` | `true` after unloading – use it to stop your own loops: `while not Library.Unloaded do ... end` |

---

## Elements

All elements are added to a section (`Section:AddX({ ... })`) and return an object. Every callback is wrapped in `pcall`, so an error in your callback never breaks the UI.

### Toggle

```lua
local Toggle = Section:AddToggle({
    Title = "Toggle",
    Flag = "my_toggle",
    Default = false,
    Callback = function(Value) end,

    -- optional colorpicker next to the switch:
    Color = Color3.fromRGB(255, 60, 60),
    ColorFlag = "my_toggle_color",
    ColorCallback = function(Color) end,
})

Toggle:Set(true)          -- Toggle:Set(Value, Silent) – Silent = true skips the callback
Toggle.Value              -- current value
Toggle.Colorpicker        -- the colorpicker object (if Color was given)
```

### Slider

```lua
local Slider = Section:AddSlider({
    Title = "Speed",
    Flag = "speed",
    Min = 0, Max = 100, Default = 50,
    Decimals = 0,          -- digits after the comma
    Prefix = "", Suffix = " studs",
    Callback = function(Value) end,
})

Slider:Set(75)             -- :Set(Value, Silent)
```

### Dropdown

```lua
local Dropdown = Section:AddDropdown({
    Title = "Mode",
    Flag = "mode",
    Options = { "One", "Two", "Three" },
    Default = "One",       -- Multi: a table, e.g. { "One", "Two" }
    Multi = false,         -- true = several selections, value is a table (array)
    Callback = function(Value) end,
})

Dropdown:Set("Two")        -- :Set(Value, Silent)
Dropdown:Refresh({ "A", "B" }, "A")   -- replace the options (default optional)
Dropdown:Open() / :Close() / :Toggle()
```

### Textbox

```lua
local Textbox = Section:AddTextbox({
    Title = "Name",
    Flag = "name",
    Default = "",
    Placeholder = "Type here...",
    Icon = "rbxassetid://...",           -- optional small icon on the right
    Callback = function(Text) end,       -- fires when the box loses focus (enter / click away)
})

Textbox:Set("text", Animate, Silent)     -- Animate = type it out letter by letter
```

### Text indicator

A read-only box for displaying text.

```lua
local Indicator = Section:AddTextIndicator({
    Title = "Status",
    Flag = "status",
    Default = "Idle",
    Placeholder = "",
    Icon = "rbxassetid://...",
})

Indicator:Set("Farming...", true)        -- second argument = animate
```

### Colorpicker

```lua
local Picker = Section:AddColorpicker({
    Title = "ESP color",
    Flag = "esp_color",
    Default = Color3.fromRGB(0, 170, 255),
    Callback = function(Color) end,
})

Picker:Set(Color3.new(1, 0, 0))          -- also accepts "#RRGGBB"; :Set(Value, Silent)
Picker.Value                             -- Color3
```

Click the square to open the popup: drag in the square for saturation / brightness and on the bar for hue.

### Button

```lua
local Button = Section:AddButton({
    Title = "Teleport",
    Callback = function() end,
})

Button:SetText("New text")
```

### Keybind

```lua
local Keybind = Section:AddKeybind({
    Title = "Fly",
    Flag = "fly_key",
    Default = Enum.KeyCode.F,    -- or "F", or nil for none
    Mode = "Toggle",             -- "Press" | "Toggle" | "Hold"
    Callback = function(State) end,
    ChangedCallback = function(Key) end,   -- fires when the user binds a new key
})

Keybind:GetState()               -- Toggle: on/off, Hold: currently held
Keybind:Set(Enum.KeyCode.G)      -- :Set(Key, Silent)
```

Click the key box, then press a key. **Escape** clears the binding.
`Press` calls the callback on every press, `Toggle` flips a state on every press, `Hold` calls it with `true` on press and `false` on release.

### Label

```lua
local Label = Section:AddLabel("Some text")
local Label = Section:AddLabel({ Title = "Dim text", Dim = true })

Label:Set("New text")
```

Labels wrap and grow with their content.

### Divider

```lua
Section:AddDivider()
```

### Config manager

```lua
Section:AddConfigManager()
```

Adds a list of saved configs with **Refresh**, **Set Auto-Load**, **Delete**, **New**, **Save** and **Load**. Call `Library:LoadAutoload()` at the end of your script to load the auto-load config.

---

## Config file format

Configs are plain JSON, one entry per flag. Colors are stored as `{ "Color": "RRGGBB" }`, keybinds as the key name, multi dropdowns as arrays. Flags that no longer exist are ignored when loading.

---

## Troubleshooting

**Clicks on dropdowns / colorpickers are shifted up or down.**
The library uses `IgnoreGuiInset` and reads the mouse with `GetMouseLocation()`, so both should be in the same coordinate space. If your executor handles the top-bar inset differently, correct it with:

```lua
Library.MouseOffset = Vector2.new(0, -36)   -- or +36
```

**Fonts look like Gotham.**
Font download failed (no `writefile` / `getcustomasset`, or the URL is blocked). Set your own with `Library:SetFonts(Font.fromEnum(Enum.Font.Gotham), Font.fromEnum(Enum.Font.GothamBold))` or change `Library.FontUrls` before creating the window.

**The menu key types into a textbox / does nothing while binding.**
That is intended: the menu key is ignored while a textbox is focused or a keybind is waiting for a key.

**My loop keeps running after unloading.**
Loop on `while not Library.Unloaded do` or clean up in `Library:OnUnload(function() ... end)`.

---

## Credits

Made for Feral Hub.
