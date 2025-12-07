--================= Marf Hub (Wind UI) =================--
-- Main tab: Pets dropdown + Refresh, Auto Switch toggle, Info
-- Settings tab: Config options
--======================================================--

-- Wind UI Library
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Services
local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local UIS      = game:GetService("UserInputService")

local player   = Players.LocalPlayer
local guiRoot  = player:WaitForChild("PlayerGui")
local petsPhysical = workspace:WaitForChild("PetsPhysical")
local petMover     = petsPhysical:WaitForChild("PetMover")

-- Remotes
local Events               = RS:WaitForChild("GameEvents")
local PetCooldownsUpdated  = Events:FindFirstChild("PetCooldownsUpdated")
local RequestPetCooldowns  = Events:FindFirstChild("RequestPetCooldowns")
local PetsService          = Events:WaitForChild("PetsService")

--==============================================================--
-- Window & Tabs
--==============================================================--
local Window = WindUI:CreateWindow({
    Title = "Marf Hub",
    Icon = "zap",
    Author = "by marf",
    Folder = "MarfHub",
    Size = UDim2.fromOffset(580, 460),
    Theme = "Dark",
    Transparent = true,
})

local MainTab = Window:Tab({
    Title = "Main",
    Icon = "home",
})

local SettingsTab = Window:Tab({
    Title = "Settings", 
    Icon = "settings",
})

--==============================================================--
-- Helpers
--==============================================================--
local function setcb(s) 
    if typeof(setclipboard)=="function" then 
        setclipboard(s) 
    end 
end

local function normGuid(s) 
    return string.lower((tostring(s or "")):gsub("[{}]","")) 
end

local function swapTo(slot) 
    pcall(function() 
        PetsService:FireServer("SwapPetLoadout", slot) 
    end) 
end

local function findPetScroll()
    local ok, scroll = pcall(function()
        return guiRoot.ActivePetUI.Frame.Main.PetDisplay.ScrollingFrame
    end)
    return ok and scroll or nil
end

local function fetchPetsFromUI()
    local list, err = {}, nil
    local scroll = findPetScroll()
    if not scroll then
        err = "UI ActivePetUI belum ditemukan / belum dibuka."
        return list, err
    end
    for _,ch in ipairs(scroll:GetChildren()) do
        if ch:IsA("Frame") and ch:FindFirstChild("Main") then
            local guid = ch.Name
            local lbl  = ch.Main:FindFirstChild("PET_NAME")
            local name = (lbl and lbl:IsA("TextLabel") and lbl.Text~="") and lbl.Text or "Unknown"
            table.insert(list, {name=name, guid=guid})
        end
    end
    table.sort(list, function(a,b) return a.name:lower() < b.name:lower() end)
    return list, err
end

-- cooldown payload → ambil detik
local function pickSeconds(v)
    if type(v)=="number" then return math.max(0,v) end
    if type(v)=="table" then
        if #v>=1 and type(v[1])=="table" then
            local t=v[1]
            if t.Time then return math.max(0,t.Time) end
            if t.Remaining then return math.max(0,t.Remaining) end
            if t.Ready==true then return 0 end
        end
        if v.Time then return math.max(0,v.Time) end
        if v.Remaining then return math.max(0,v.Remaining) end
        if v.Ready==true then return 0 end
    end
    return nil
end

--==============================================================--
-- MAIN TAB UI
--==============================================================--
MainTab:Paragraph({
    Title = "Pet Auto Switch",
    Desc = "Automatically switch pets based on cooldown. Open your pet UI first, then click Refresh.",
})

MainTab:Divider()

local lastPets = {}
local selectedPetValue = nil

local PetDropdown = MainTab:Dropdown({
    Title = "Select Pet",
    Desc = "Choose pet to monitor",
    Values = {"(Click Refresh to load pets)"},
    Value = "(Click Refresh to load pets)",
    Callback = function(option) 
        selectedPetValue = option
    end
})

local function rebuildDropdown(pets)
    lastPets = pets or {}
    local values = {}
    for _,p in ipairs(lastPets) do
        table.insert(values, string.format("%s  [%s]", p.name, p.guid))
    end
    if #values==0 then 
        values = {"(No pets found - Open Pet UI first)"} 
    end
    PetDropdown:Refresh(values)
    if #values > 0 then
        PetDropdown:Select(values[1])
    end
end

MainTab:Button({
    Title = "Refresh Pet List",
    Desc = "Load pets from UI",
    Icon = "refresh-cw",
    Callback = function()
        local list, err = fetchPetsFromUI()
        rebuildDropdown(list)
        if err and #list==0 then
            WindUI:Notify({
                Title = "Error",
                Content = err,
                Duration = 5,
                Icon = "alert-circle",
            })
        else
            WindUI:Notify({
                Title = "Success",
                Content = string.format("Loaded %d pets", #list),
                Duration = 4,
                Icon = "check-circle",
            })
        end
    end
})

MainTab:Divider()

-- Toggle Auto Switch
local autoSwitchEnabled = false
local AutoToggle = MainTab:Toggle({
    Title = "Auto Switch",
    Desc = "Automatically switch between slots",
    Icon = "repeat",
    Value = false,
    Callback = function(state)
        autoSwitchEnabled = state
        if state then
            WindUI:Notify({
                Title = "Auto Switch",
                Content = "Enabled",
                Duration = 3,
                Icon = "play",
            })
        else
            WindUI:Notify({
                Title = "Auto Switch",
                Content = "Disabled",
                Duration = 3,
                Icon = "pause",
            })
        end
    end
})

MainTab:Divider()

-- Info Display
local InfoParagraph = MainTab:Paragraph({
    Title = "Status Information",
    Desc = "Mimic CD: —\nSlot: —\nMode: OFF",
    Color = "Blue",
})

MainTab:Button({
    Title = "Copy Selected GUID",
    Desc = "Copy pet GUID to clipboard",
    Icon = "copy",
    Callback = function()
        if selectedPetValue and selectedPetValue ~= "(Click Refresh to load pets)" then
            local g = selectedPetValue:match("%[(.-)%]")
            if g then 
                setcb(g)
                WindUI:Notify({
                    Title = "Copied",
                    Content = g,
                    Duration = 4,
                    Icon = "clipboard-check",
                })
            end
        else
            WindUI:Notify({
                Title = "Error",
                Content = "No pet selected",
                Duration = 3,
                Icon = "alert-triangle",
            })
        end
    end
})

--==============================================================--
-- LOGIC: Auto Switch (Strict ready 0 + hold)
--==============================================================--
local DEFAULT_MIMIC_GUID = "{75faf9ad-a365-4c3a-b379-fbe06f6623e3}"
local SLOT1, SLOT2       = 1, 2
local READY_EPS          = 0.05
local READY_HOLD_SEC     = 0.30
local POLL_SEC           = 2.5
local TICK_SEC           = 0.25

local mimicRemain, lastStamp = nil, os.clock()
local currentSlot = SLOT1
local readyHoldTimer = 0
local selectedGuid = DEFAULT_MIMIC_GUID

-- ambil GUID dari dropdown
local function getDropdownGuid()
    if not selectedPetValue or selectedPetValue == "(Click Refresh to load pets)" then 
        return nil 
    end
    local g = selectedPetValue:match("%[(.-)%]")
    return g
end

-- event cooldown
if PetCooldownsUpdated then
    PetCooldownsUpdated.OnClientEvent:Connect(function(a,b)
        local key = normGuid(selectedGuid)
        local function try(a_, b_)
            if a_ and b_ and normGuid(a_) == key then
                local s = pickSeconds(b_)
                if s~=nil then 
                    mimicRemain=s
                    lastStamp=os.clock() 
                end
                return true
            end
            return false
        end
        if try(a,b) then return end
        if type(a)=="table" and not b then
            for k,v in pairs(a) do
                if normGuid(k)==key then
                    local s = pickSeconds(v)
                    if s~=nil then 
                        mimicRemain=s
                        lastStamp=os.clock() 
                    end
                end
            end
        end
    end)
end

-- polling cooldown periodik
task.spawn(function()
    while true do
        if RequestPetCooldowns then
            pcall(function() RequestPetCooldowns:FireServer() end)
            pcall(function() RequestPetCooldowns:FireServer(selectedGuid) end)
        end
        task.wait(POLL_SEC)
    end
end)

-- mulai di SLOT1
swapTo(SLOT1)
currentSlot = SLOT1

-- loop utama
task.spawn(function()
    while true do
        task.wait(TICK_SEC)

        -- update pilihan GUID berdasarkan dropdown bila user ganti
        local g = getDropdownGuid()
        if g and g ~= selectedGuid then
            selectedGuid = g
        end

        -- decay sederhana
        if type(mimicRemain)=="number" then
            mimicRemain = math.max(0, mimicRemain - TICK_SEC)
        end

        -- status UI
        local modeTxt = autoSwitchEnabled and "🟢 ON" or "🔴 OFF"
        local cdTxt = (mimicRemain and string.format("%.2fs", mimicRemain) or "—")
        local slotTxt = string.format("Slot %d", currentSlot)
        
        InfoParagraph:SetDesc(string.format(
            "Mimic CD: %s\n%s\nMode: %s",
            cdTxt,
            slotTxt,
            modeTxt
        ))

        if not autoSwitchEnabled then
            readyHoldTimer = 0
        else
            -- Auto Switch strict: tunggu 0 → hold → switch
            if currentSlot == SLOT1 then
                if mimicRemain and mimicRemain <= READY_EPS then
                    readyHoldTimer = readyHoldTimer + TICK_SEC
                    if readyHoldTimer >= READY_HOLD_SEC then
                        swapTo(SLOT2)
                        currentSlot = SLOT2
                        readyHoldTimer = 0
                    end
                else
                    readyHoldTimer = 0
                end
            elseif currentSlot == SLOT2 then
                -- begitu Mimic mulai cooldown lagi → balik SLOT1
                if mimicRemain and mimicRemain > READY_EPS then
                    swapTo(SLOT1)
                    currentSlot = SLOT1
                    readyHoldTimer = 0
                end
            end
        end
    end
end)

--==============================================================--
-- Settings Tab
--==============================================================--
SettingsTab:Paragraph({
    Title = "Configuration",
    Desc = "Adjust script settings and timing parameters",
})

SettingsTab:Divider()

-- Timing Settings
local TimingSlider = SettingsTab:Slider({
    Title = "Ready Hold Time",
    Desc = "How long to wait before switching (seconds)",
    Step = 0.05,
    Value = {
        Min = 0.1,
        Max = 2.0,
        Default = READY_HOLD_SEC,
    },
    Callback = function(value)
        READY_HOLD_SEC = value
    end
})

local PollSlider = SettingsTab:Slider({
    Title = "Poll Interval",
    Desc = "How often to request cooldown updates (seconds)",
    Step = 0.5,
    Value = {
        Min = 1.0,
        Max = 10.0,
        Default = POLL_SEC,
    },
    Callback = function(value)
        POLL_SEC = value
    end
})

SettingsTab:Divider()

-- Manual GUID Input
local ManualGuidInput = SettingsTab:Input({
    Title = "Manual GUID",
    Desc = "Enter pet GUID manually (optional)",
    Value = "",
    Placeholder = "{guid-here}",
    Callback = function(input) 
        if input and input ~= "" then
            selectedGuid = input
            WindUI:Notify({
                Title = "GUID Updated",
                Content = "Manual GUID set",
                Duration = 3,
                Icon = "check",
            })
        end
    end
})

SettingsTab:Divider()

-- Keybind
local ToggleKeybind = SettingsTab:Keybind({
    Title = "Toggle UI Keybind",
    Desc = "Key to open/close the UI",
    Value = "LeftControl",
    Callback = function(v)
        Window:SetToggleKey(Enum.KeyCode[v])
    end
})

SettingsTab:Divider()

-- Actions
SettingsTab:Button({
    Title = "Reset to Default",
    Desc = "Reset all settings to default values",
    Icon = "rotate-ccw",
    Color = Color3.fromRGB(255, 200, 100),
    Callback = function()
        READY_HOLD_SEC = 0.30
        POLL_SEC = 2.5
        TimingSlider:Set(0.30)
        PollSlider:Set(2.5)
        WindUI:Notify({
            Title = "Reset",
            Content = "Settings reset to default",
            Duration = 3,
            Icon = "refresh-cw",
        })
    end
})

SettingsTab:Space()

SettingsTab:Button({
    Title = "Unload Script",
    Desc = "Destroy the UI",
    Icon = "x-circle",
    Color = Color3.fromRGB(255, 100, 100),
    Callback = function()
        local Dialog = Window:Dialog({
            Icon = "alert-triangle",
            Title = "Unload Script",
            Content = "Are you sure you want to unload the script?",
            Buttons = {
                {
                    Title = "Yes",
                    Callback = function()
                        WindUI:Notify({
                            Title = "Goodbye",
                            Content = "Script unloaded",
                            Duration = 2,
                            Icon = "log-out",
                        })
                        task.wait(2)
                        Window:Destroy()
                    end,
                },
                {
                    Title = "Cancel",
                    Callback = function()
                        -- do nothing
                    end,
                },
            },
        })
        Dialog:Show()
    end
})

--==============================================================--
-- Initialize
--==============================================================--
WindUI:Notify({
    Title = "Marf Hub",
    Content = "Script loaded successfully! Open your pet UI and click Refresh.",
    Duration = 6,
    Icon = "zap",
})

-- Auto select Main tab
MainTab:Select()
