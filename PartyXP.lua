local addonName, addon = ...
addon = addon or {}

local PREFIX = "PartyXP"
local PROTOCOL = "1"
local MAX_PARTY_MEMBERS = 4
local STALE_SECONDS = 90
local BROADCAST_SECONDS = 30
local REFRESH_SECONDS = 0.25
local MEDIA = "Interface\\AddOns\\PartyXP\\Media\\"
local FILL_TEXTURES = {
    CLASSIC = "Interface\\TargetingFrame\\UI-StatusBar",
    FLAT = MEDIA .. "Flat.tga",
    GLOSS = MEDIA .. "Gloss.tga",
    STRIPED = MEDIA .. "Striped.tga",
}
local BORDER_STYLES = {
    THIN = { size = 1, r = 0.12, g = 0.12, b = 0.15, a = 0.9 },
    BOLD = { size = 2, r = 0, g = 0, b = 0, a = 1 },
    GOLD = { size = 2, r = 0.9, g = 0.7, b = 0.3, a = 1 },
}
local TEXT_ANCHORS = {
    CENTER = { "CENTER", "CENTER" },
    LEFT = { "LEFT", "LEFT" },
    RIGHT = { "RIGHT", "RIGHT" },
    TOP = { "TOP", "TOP" },
    BOTTOM = { "BOTTOM", "BOTTOM" },
    TOPLEFT = { "TOPLEFT", "TOPLEFT" },
    TOPRIGHT = { "TOPRIGHT", "TOPRIGHT" },
    BOTTOMLEFT = { "BOTTOMLEFT", "BOTTOMLEFT" },
    BOTTOMRIGHT = { "BOTTOMRIGHT", "BOTTOMRIGHT" },
}
local MASK_TEXTURES = {
    [1] = MEDIA .. "Rounded-1.tga",
    [2] = MEDIA .. "Rounded-2.tga",
    [4] = MEDIA .. "Rounded-4.tga",
    [8] = MEDIA .. "Rounded-8.tga",
    [16] = MEDIA .. "Rounded-16.tga",
    [32] = MEDIA .. "Rounded-32.tga",
}

local defaults = {
    enabled = true,
    width = 80,
    height = 8,
    side = "RIGHT",
    offsetX = 4,
    offsetY = 0,
    opacity = 1,
    color = { r = 0.45, g = 0.28, b = 0.95 },
    fillStyle = "CLASSIC",
    borderEnabled = false,
    borderStyle = "THIN",
    rounded = false,
    showXPText = false,
    textPosition = "CENTER",
    textOffsetX = 0,
    textOffsetY = 0,
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
    if not FILL_TEXTURES[db.fillStyle] then db.fillStyle = defaults.fillStyle end
    if type(db.borderEnabled) ~= "boolean" then db.borderEnabled = defaults.borderEnabled end
    if not BORDER_STYLES[db.borderStyle] then db.borderStyle = defaults.borderStyle end
    if type(db.rounded) ~= "boolean" then db.rounded = defaults.rounded end
    if type(db.showXPText) ~= "boolean" then db.showXPText = defaults.showXPText end
    if not TEXT_ANCHORS[db.textPosition] then db.textPosition = defaults.textPosition end
    db.textOffsetX = Clamp(db.textOffsetX, -100, 100, defaults.textOffsetX)
    db.textOffsetY = Clamp(db.textOffsetY, -100, 100, defaults.textOffsetY)
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

local function MaskAspect(width, height)
    local ratio = width / height
    if ratio < 1.5 then return 1 end
    if ratio < 3 then return 2 end
    if ratio < 6 then return 4 end
    if ratio < 12 then return 8 end
    if ratio < 24 then return 16 end
    return 32
end

local function SetMaskTexture(mask, width, height, previousAspect)
    local aspect = MaskAspect(width, height)
    if aspect ~= previousAspect then mask:SetTexture(MASK_TEXTURES[aspect]) end
    return aspect
end

local function CreateBar(index)
    local bar = CreateFrame("Frame", "PartyXPBar" .. index, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:EnableMouse(false)

    local borderSurface = bar:CreateTexture(nil, "BACKGROUND")
    borderSurface:SetAllPoints(bar)
    borderSurface:Hide()
    bar.borderSurface = borderSurface

    local fill = CreateFrame("StatusBar", nil, bar)
    fill:SetAllPoints(bar)
    fill:SetStatusBarTexture(FILL_TEXTURES.CLASSIC)
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    bar.fill = fill
    bar.fillTexture = fill:GetStatusBarTexture()
    bar.fillStyle = "CLASSIC"
    bar.borderInset = 0
    bar.rounded = false

    local xpText = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xpText:SetTextColor(1, 1, 1)
    xpText:Hide()
    bar.xpText = xpText

    local background = fill:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(fill)
    background:SetColorTexture(0, 0, 0, 0.75)
    bar.background = background

    bar.outerMask = bar:CreateMaskTexture()
    bar.outerMask:SetAllPoints(bar)
    bar.backgroundMask = fill:CreateMaskTexture()
    bar.backgroundMask:SetAllPoints(fill)
    bar.fillMask = fill:CreateMaskTexture()
    bar.fillMask:SetPoint("LEFT", fill, "LEFT", 0, 0)
    bar.fillMask:SetSize(1, 1)

    bar:Hide()
    bars[index] = bar
    return bar
end

local function ApplyAppearance(bar, db, progress)
    if bar.fillStyle ~= db.fillStyle then
        if bar.rounded then bar.fillTexture:RemoveMaskTexture(bar.fillMask) end
        bar.fill:SetStatusBarTexture(FILL_TEXTURES[db.fillStyle])
        bar.fillTexture = bar.fill:GetStatusBarTexture()
        if bar.rounded then bar.fillTexture:AddMaskTexture(bar.fillMask) end
        bar.fillStyle = db.fillStyle
    end

    local borderStyle = BORDER_STYLES[db.borderStyle]
    if bar.borderStyle ~= db.borderStyle then
        bar.borderSurface:SetColorTexture(borderStyle.r, borderStyle.g, borderStyle.b, borderStyle.a)
        bar.borderStyle = db.borderStyle
    end
    if bar.borderEnabled ~= db.borderEnabled then
        if db.borderEnabled then bar.borderSurface:Show() else bar.borderSurface:Hide() end
        bar.borderEnabled = db.borderEnabled
    end

    local inset = db.borderEnabled and math.min(borderStyle.size, math.floor((db.height - 1) / 2)) or 0
    if bar.borderInset ~= inset then
        bar.fill:ClearAllPoints()
        bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", inset, -inset)
        bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -inset, inset)
        bar.borderInset = inset
    end

    if bar.rounded ~= db.rounded then
        if db.rounded then
            bar.borderSurface:AddMaskTexture(bar.outerMask)
            bar.background:AddMaskTexture(bar.backgroundMask)
            bar.fillTexture:AddMaskTexture(bar.fillMask)
        else
            bar.borderSurface:RemoveMaskTexture(bar.outerMask)
            bar.background:RemoveMaskTexture(bar.backgroundMask)
            bar.fillTexture:RemoveMaskTexture(bar.fillMask)
        end
        bar.rounded = db.rounded
    end

    if db.rounded then
        local innerWidth = db.width - 2 * inset
        local innerHeight = db.height - 2 * inset
        bar.fillMask:SetSize(math.max(innerWidth * progress, 0.01), innerHeight)
        bar.outerMaskAspect = SetMaskTexture(bar.outerMask, db.width, db.height, bar.outerMaskAspect)
        bar.backgroundMaskAspect = SetMaskTexture(bar.backgroundMask, innerWidth, innerHeight, bar.backgroundMaskAspect)
        bar.fillMaskAspect = SetMaskTexture(bar.fillMask, innerWidth * progress, innerHeight, bar.fillMaskAspect)
    end
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

local function PositionText(bar, db)
    if bar.textPosition == db.textPosition and bar.textX == db.textOffsetX
        and bar.textY == db.textOffsetY then return end
    local anchors = TEXT_ANCHORS[db.textPosition]
    bar.xpText:ClearAllPoints()
    bar.xpText:SetPoint(anchors[1], bar, anchors[2], db.textOffsetX, db.textOffsetY)
    bar.textPosition, bar.textX, bar.textY = db.textPosition, db.textOffsetX, db.textOffsetY
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
                    ApplyAppearance(bar, db, state.xp / state.maxXP)
                    bar:SetAlpha(db.opacity)
                    bar.fill:SetStatusBarColor(db.color.r, db.color.g, db.color.b)
                    bar.fill:SetMinMaxValues(0, state.maxXP)
                    bar.fill:SetValue(state.xp)
                    if db.showXPText then
                        PositionText(bar, db)
                        bar.xpText:SetText(state.xp .. " / " .. state.maxXP)
                        bar.xpText:Show()
                    else
                        bar.xpText:Hide()
                    end
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

local function ShowFirstLoginNotice()
    if not addon.db or addon.db.introShown == true or not StaticPopupDialogs or not StaticPopup_Show then
        return
    end

    StaticPopupDialogs.PARTYXP_FIRST_LOGIN_NOTICE = {
        text = "Party XP only shows another party member's XP bar when they also have Party XP installed. Ask your party members to install the addon to share their XP progress.",
        button1 = OKAY,
        timeout = 0,
        whileDead = true,
    }
    if StaticPopup_Show("PARTYXP_FIRST_LOGIN_NOTICE") then
        addon.db.introShown = true
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
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
    elseif event == "PLAYER_LOGIN" then
        ShowFirstLoginNotice()
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
