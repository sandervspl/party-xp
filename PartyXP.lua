local addonName, addon = ...
addon = addon or {}

local PREFIX = "PartyXP"
local PROTOCOL = "1"
local MAX_PARTY_MEMBERS = 4
local STALE_SECONDS = 90
local BROADCAST_SECONDS = 30
local REFRESH_SECONDS = 0.25
local TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local defaults = {
    enabled = true,
    width = 80,
    height = 8,
    side = "RIGHT",
    offsetX = 4,
    offsetY = 0,
    opacity = 1,
    color = { r = 0.45, g = 0.28, b = 0.95 },
}

local sides = { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true }
local bars = {}
local peers = {}
local clock = 0
local lastBroadcast = -BROADCAST_SECONDS
local pendingBroadcast = false
local refreshElapsed = 0

addon.defaults = defaults
addon.bars = bars

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function LoadSettings()
    if type(PartyXPDB) ~= "table" then PartyXPDB = {} end
    local db = PartyXPDB
    if type(db.enabled) ~= "boolean" then db.enabled = defaults.enabled end
    db.width = Clamp(db.width, 30, 240, defaults.width)
    db.height = Clamp(db.height, 3, 30, defaults.height)
    db.offsetX = Clamp(db.offsetX, -100, 100, defaults.offsetX)
    db.offsetY = Clamp(db.offsetY, -100, 100, defaults.offsetY)
    db.opacity = Clamp(db.opacity, 0.1, 1, defaults.opacity)
    if not sides[db.side] then db.side = defaults.side end
    if type(db.color) ~= "table" then db.color = {} end
    db.color.r = Clamp(db.color.r, 0, 1, defaults.color.r)
    db.color.g = Clamp(db.color.g, 0, 1, defaults.color.g)
    db.color.b = Clamp(db.color.b, 0, 1, defaults.color.b)
    addon.db = db
end

local function PlayerAtMaxLevel()
    local level = UnitLevel("player")
    local cap = GetMaxPlayerLevel()
    return not IsSecret(level) and not IsSecret(cap) and level >= cap
end

local function IsParty()
    return IsInGroup() and not IsInRaid()
end

local function FindUnitFrame(index)
    local unit = "party" .. index
    if CompactPartyFrame and CompactPartyFrame:IsShown() and CompactPartyFrame.memberUnitFrames then
        for _, frame in ipairs(CompactPartyFrame.memberUnitFrames) do
            if frame.unit == unit and frame:IsShown() then return frame end
        end
    end
    if PartyFrame and PartyFrame:IsShown() then
        if PartyFrame.GetPartyMemberFrame then
            local frame = PartyFrame:GetPartyMemberFrame(index)
            if frame and frame:IsShown() then return frame end
        elseif PartyFrame.PartyMemberFramePool then
            for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                if frame.layoutIndex == index and frame:IsShown() then return frame end
            end
        end
    end
    local frame = _G["PartyMemberFrame" .. index]
    if frame and frame:IsShown() then return frame end
end

local function UnitFullNameSafe(unit)
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()
        and NameUtil and NameUtil.GetUnmodifiedUnitFullName then
        local fullName = NameUtil.GetUnmodifiedUnitFullName(unit)
        if IsSecret(fullName) then return nil end
        return fullName
    end

    local name, realm
    if UnitFullName then
        name, realm = UnitFullName(unit)
    else
        name, realm = UnitName(unit)
    end
    if IsSecret(name) or IsSecret(realm) or not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

local function SenderMatchesUnit(sender, unit)
    if IsSecret(sender) then return false end
    local fullName = UnitFullNameSafe(unit)
    if not fullName then return false end
    if sender == fullName then return true end
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then return false end
    -- Same-realm addon senders may omit the realm suffix.
    local shortName, realm = fullName:match("^([^-]+)%-?(.*)$")
    if sender:find("-", 1, true) or sender ~= shortName then return false end
    local ownName = UnitFullNameSafe("player")
    local ownRealm = ownName and ownName:match("%-(.+)$")
    return realm == "" or (ownRealm and realm == ownRealm)
end

local function FindSenderUnit(sender)
    if not IsParty() then return nil end
    for index = 1, MAX_PARTY_MEMBERS do
        local unit = "party" .. index
        if UnitExists(unit) and SenderMatchesUnit(sender, unit) then return unit end
    end
end

local function CreateBar(index)
    local bar = CreateFrame("StatusBar", "PartyXPBar" .. index, UIParent)
    bar:SetStatusBarTexture(TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameStrata("MEDIUM")
    bar:EnableMouse(false)
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    background:SetColorTexture(0, 0, 0, 0.75)
    bar.background = background
    bar:Hide()
    bars[index] = bar
    return bar
end

local function PositionBar(bar, frame)
    local db = addon.db
    if bar.anchor == frame and bar.side == db.side and bar.x == db.offsetX and bar.y == db.offsetY then
        return
    end
    bar:ClearAllPoints()
    if db.side == "LEFT" then
        bar:SetPoint("RIGHT", frame, "LEFT", db.offsetX, db.offsetY)
    elseif db.side == "TOP" then
        bar:SetPoint("BOTTOM", frame, "TOP", db.offsetX, db.offsetY)
    elseif db.side == "BOTTOM" then
        bar:SetPoint("TOP", frame, "BOTTOM", db.offsetX, db.offsetY)
    else
        bar:SetPoint("LEFT", frame, "RIGHT", db.offsetX, db.offsetY)
    end
    bar.anchor, bar.side, bar.x, bar.y = frame, db.side, db.offsetX, db.offsetY
end

function addon:RefreshBars()
    local db = self.db
    if not db then return end
    for index = 1, MAX_PARTY_MEMBERS do
        local bar = bars[index]
        if not bar then bar = CreateBar(index) end
        local visible = false
        local unit = "party" .. index
        if db.enabled and IsParty() and UnitExists(unit) then
            local level = UnitLevel(unit)
            local cap = GetMaxPlayerLevel()
            local frame = FindUnitFrame(index)
            if frame and not IsSecret(level) and not IsSecret(cap) and level > 0 and level < cap then
                local name = UnitFullNameSafe(unit)
                local state = name and peers[name]
                if state and clock - state.seen <= STALE_SECONDS and state.level == level then
                    PositionBar(bar, frame)
                    bar:SetSize(db.width, db.height)
                    bar:SetAlpha(db.opacity)
                    bar:SetStatusBarColor(db.color.r, db.color.g, db.color.b)
                    bar:SetMinMaxValues(0, state.maxXP)
                    bar:SetValue(state.xp)
                    visible = true
                end
            end
        end
        if visible then
            if not bar:IsShown() then bar:Show() end
        elseif bar:IsShown() then
            bar:Hide()
        end
    end
end

local function Broadcast()
    lastBroadcast = clock
    pendingBroadcast = false
    if not IsParty() or PlayerAtMaxLevel() then return end
    local xp, maxXP, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if IsSecret(xp) or IsSecret(maxXP) or IsSecret(level) then return end
    if type(xp) ~= "number" or type(maxXP) ~= "number" or type(level) ~= "number" or maxXP <= 0 then return end
    local channel = LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        and "INSTANCE_CHAT" or "PARTY"
    local message = table.concat({ PROTOCOL, math.floor(level), math.floor(xp), math.floor(maxXP) }, ":")
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, message, channel)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, message, channel)
    end
end

local function Receive(prefix, message, distribution, sender)
    if prefix ~= PREFIX or (distribution ~= "PARTY" and distribution ~= "INSTANCE_CHAT") then return end
    if type(message) ~= "string" or #message > 64 or type(sender) ~= "string" then return end
    local unit = FindSenderUnit(sender)
    if not unit then return end
    local version, levelText, xpText, maxText = message:match("^(%d+):(%d+):(%d+):(%d+)$")
    if version ~= PROTOCOL then return end
    local level, xp, maxXP = tonumber(levelText), tonumber(xpText), tonumber(maxText)
    if not level or not xp or not maxXP or maxXP < 1 or maxXP > 1000000000 or xp >= maxXP then return end
    local unitLevel, cap = UnitLevel(unit), GetMaxPlayerLevel()
    if IsSecret(unitLevel) or IsSecret(cap) or level ~= unitLevel or level >= cap then return end
    local name = UnitFullNameSafe(unit)
    if not name then return end
    peers[name] = { level = level, xp = xp, maxXP = maxXP, seen = clock }
    addon:RefreshBars()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("UNIT_LEVEL")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        LoadSettings()
        addon:InitializeOptions()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(PREFIX)
        end
        addon:RefreshBars()
    elseif event == "CHAT_MSG_ADDON" then
        Receive(...)
    elseif event == "UNIT_LEVEL" then
        local unit = ...
        if unit == "player" then pendingBroadcast = true end
        addon:RefreshBars()
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        pendingBroadcast = true
        addon:RefreshBars()
    else
        if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
            pendingBroadcast = true
        end
        addon:RefreshBars()
    end
end)
events:SetScript("OnUpdate", function(_, elapsed)
    clock = clock + elapsed
    refreshElapsed = refreshElapsed + elapsed
    if refreshElapsed >= REFRESH_SECONDS then
        refreshElapsed = 0
        addon:RefreshBars()
    end
    if pendingBroadcast and clock - lastBroadcast >= 1 then
        Broadcast()
    elseif clock - lastBroadcast >= BROADCAST_SECONDS then
        Broadcast()
    end
end)

addon.events = events
