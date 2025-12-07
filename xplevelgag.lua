--================= Marf Hub (Fluent Minimal) =================--
-- Main tab: Pets dropdown + Refresh, Auto Switch toggle, Info
-- Settings tab: Save/Load config (Fluent Addons)
--==============================================================--

-- Fluent libs
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Services
local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local UIS      = game:GetService("UserInputService")

local player   = Players.LocalPlayer
local guiRoot  = player:WaitForChild("PlayerGui")
local petsPhysical = workspace:WaitForChild("PetsPhysical")
local petMover     = petsPhysical:WaitForChild("PetMover")

-- Remotes (nama dari project kamu)
local Events               = RS:WaitForChild("GameEvents")
local PetCooldownsUpdated  = Events:FindFirstChild("PetCooldownsUpdated")
local RequestPetCooldowns  = Events:FindFirstChild("RequestPetCooldowns")
local PetsService          = Events:WaitForChild("PetsService")

--==============================================================--
-- Window & Tabs
--==============================================================--
local Window = Fluent:CreateWindow({
    Title = "Marf Hub " .. Fluent.Version,
    SubTitle = "by marf",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}
local Options = Fluent.Options

--==============================================================--
-- Helpers
--==============================================================--
local function setcb(s) if typeof(setclipboard)=="function" then setclipboard(s) end end
local function normGuid(s) return string.lower((tostring(s or "")):gsub("[{}]","")) end
local function swapTo(slot) pcall(function() PetsService:FireServer("SwapPetLoadout", slot) end) end

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
local PetDropdown = Tabs.Main:AddDropdown("GT_PetDropdown", {
    Title = "Pets",
    Values = {"list"},
    Multi = false,
    Default = 1,
})

local lastPets = {}
local function rebuildDropdown(pets)
    lastPets = pets or {}
    local values = {}
    for _,p in ipairs(lastPets) do
        table.insert(values, string.format("%s  [%s]", p.name, p.guid))
    end
    if #values==0 then values = {"(kosong)"} end
    PetDropdown:SetValues(values)
end

Tabs.Main:AddButton({
    Title = "Refresh",
    Callback = function()
        local list, err = fetchPetsFromUI()
        rebuildDropdown(list)
        if err and #list==0 then
            Window:Dialog({
                Title = "ActivePetUI belum ada",
                Content = err,
                Buttons = {{Title="OK"}}
            })
        else
            Fluent:Notify({Title="Refresh", Content=("Dapat %d pet."):format(#list), Duration=4})
        end
    end
})

-- Toggle Auto Switch
local AutoToggle = Tabs.Main:AddToggle("GT_Auto", {Title="Auto Switch", Default=false })
AutoToggle:OnChanged(function() end) -- nilai dibaca di loop

-- Paragraph Info (live)
local InfoPara = Tabs.Main:AddParagraph({
    Title = "Info",
    Content = "Mimic CD: —\nSlot: —\nMode: OFF"
})

--==============================================================--
-- LOGIC: Auto Switch (Strict ready 0 + hold)
--==============================================================--
-- kamu bisa ganti default Mimic GUID di sini (atau pilih dari dropdown & Copy)
local DEFAULT_MIMIC_GUID = "{75faf9ad-a365-4c3a-b379-fbe06f6623e3}"
local SLOT1, SLOT2       = 1, 2
local READY_EPS          = 0.05   -- dianggap 0 jika <= 0.05s
local READY_HOLD_SEC     = 0.30   -- harus bertahan 0s selama 0.30s
local POLL_SEC           = 2.5    -- minta update cooldown periodik
local TICK_SEC           = 0.25   -- update step

local mimicRemain, lastStamp = nil, os.clock()
local currentSlot = SLOT1
local readyHoldTimer = 0
local selectedGuid = DEFAULT_MIMIC_GUID

-- ambil GUID dari dropdown (format ... [GUID])
local function getDropdownGuid()
    local sel = Options.GT_PetDropdown.Value
    if not sel or sel=="" then return nil end
    local g = sel:match("%[(.-)%]")
    return g
end

-- event cooldown
if PetCooldownsUpdated then
    PetCooldownsUpdated.OnClientEvent:Connect(function(a,b)
        local key = normGuid(selectedGuid)
        local function try(a_, b_)
            if a_ and b_ and normGuid(a_) == key then
                local s = pickSeconds(b_)
                if s~=nil then mimicRemain=s; lastStamp=os.clock() end
                return true
            end
            return false
        end
        if try(a,b) then return end
        if type(a)=="table" and not b then
            for k,v in pairs(a) do
                if normGuid(k)==key then
                    local s = pickSeconds(v)
                    if s~=nil then mimicRemain=s; lastStamp=os.clock() end
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
swapTo(SLOT1); currentSlot = SLOT1

-- loop utama
task.spawn(function()
    while true do
        task.wait(TICK_SEC)

        -- update pilihan GUID berdasarkan dropdown bila user ganti
        local g = getDropdownGuid()
        if g and g ~= selectedGuid then
            selectedGuid = g
        end

        -- decay sederhana (biar UI tetap turun pelan2)
        if type(mimicRemain)=="number" then
            mimicRemain = math.max(0, mimicRemain - TICK_SEC)
        end

        -- status UI
        local modeTxt = Options.GT_Auto.Value and "ON" or "OFF"
        InfoPara:SetDesc(string.format(
            "Mimic CD: %s\nSlot: %d\nMode: %s",
            (mimicRemain and string.format("%.2fs", mimicRemain) or "—"),
            currentSlot,
            modeTxt
        ))

        if not Options.GT_Auto.Value then
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

-- klik kanan di dropdown? tidak ada, jadi sediakan dialog kecil untuk copy GUID terpilih
Tabs.Main:AddButton({
    Title = "Copy GUID Terpilih",
    Callback = function()
        local g = getDropdownGuid()
        if g then setcb(g); Fluent:Notify({Title="Copied", Content=g, Duration=4}) end
    end
})

--==============================================================--
-- Settings (Save/Load)
--==============================================================--
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/specific-game")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

Fluent:Notify({
    Title = "Fluent",
    Content = "The script has been loaded.",
    Duration = 8
})

SaveManager:LoadAutoloadConfig()
