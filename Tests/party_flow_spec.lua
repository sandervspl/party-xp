describe("Party XP party flow", function()
    local addon, frames, widgets, members, sent, party, raid, instance
    local optionsTable, registeredPanel, openedCategory, notifications

    local function widget(kind, name)
        local frame = { kind = kind, name = name, shown = true, scripts = {}, events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(script, callback) self.scripts[script] = callback end
        function frame:CreateTexture() return widget("Texture") end
        function frame:CreateMaskTexture() return widget("MaskTexture") end
        function frame:CreateFontString() return widget("FontString") end
        function frame:IsShown() return self.shown end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetAllPoints(target) self.allPoints = target end
        function frame:ClearAllPoints() self.point = nil end
        function frame:SetSize(width, height) self.width, self.height = width, height end
        function frame:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
        function frame:SetValue(value)
            self.value = value
            if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
        end
        function frame:SetStatusBarColor(r, g, b) self.color = { r, g, b } end
        function frame:SetStatusBarTexture(path)
            self.statusBarTexture = rawget(self, "statusBarTexture") or widget("Texture")
            self.statusBarTexture.texture = path
        end
        function frame:GetStatusBarTexture() return self.statusBarTexture end
        function frame:SetTexture(path) self.texture = path end
        function frame:AddMaskTexture(mask)
            self.masks = rawget(self, "masks") or {}
            self.masks[mask] = true
        end
        function frame:RemoveMaskTexture(mask)
            local masks = rawget(self, "masks")
            if masks then masks[mask] = nil end
        end
        function frame:SetAlpha(alpha) self.alpha = alpha end
        function frame:SetText(text) self.text = text end
        function frame:SetChecked(value) self.checked = value end
        function frame:GetChecked() return self.checked end
        function frame:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
        setmetatable(frame, { __index = function() return function() end end })
        widgets[#widgets + 1] = frame
        if name then frames[name] = frame end
        return frame
    end

    local function fire(event, ...)
        addon.events.scripts.OnEvent(addon.events, event, ...)
    end

    local function advance(seconds)
        addon.events.scripts.OnUpdate(addon.events, seconds)
    end

    before_each(function()
        frames, widgets, sent = {}, {}, {}
        notifications = {}
        members = {
            player = { name = "Me", realm = "Realm", level = 25, xp = 400, maxXP = 1000 },
            party1 = { name = "Alice", realm = "Realm", level = 20 },
            party2 = { name = "Bob", realm = "Realm", level = 80 },
            party3 = { name = "Chris", realm = "Other", level = 30 },
        }
        party, raid, instance = true, false, false
        _G.PartyXPDB = nil
        _G.UIParent = widget("Frame", "UIParent")
        _G.LE_PARTY_CATEGORY_INSTANCE = 2
        _G.SlashCmdList = {}
        _G.Settings = {
            OpenToCategory = function(categoryID) openedCategory = categoryID end,
        }
        local aceLibraries = {
            ["AceConfig-3.0"] = {
                RegisterOptionsTable = function(_, name, options)
                    assert.are.equal("PartyXP", name)
                    optionsTable = options
                end,
            },
            ["AceConfigDialog-3.0"] = {
                AddToBlizOptions = function(_, name, title)
                    assert.are.equal("PartyXP", name)
                    assert.are.equal("Party XP", title)
                    registeredPanel = widget("Frame", "PartyXPOptionsFrame")
                    return registeredPanel, 731
                end,
            },
            ["AceConfigRegistry-3.0"] = {
                NotifyChange = function(_, name)
                    notifications[#notifications + 1] = name
                end,
            },
        }
        _G.LibStub = function(name) return assert(aceLibraries[name]) end
        _G.CreateFrame = function(kind, name)
            return widget(kind, name)
        end
        _G.UnitExists = function(unit) return members[unit] ~= nil end
        _G.UnitLevel = function(unit) return members[unit] and members[unit].level or 0 end
        _G.UnitFullName = function(unit)
            local member = members[unit]
            if member then return member.name, member.realm end
        end
        _G.UnitXP = function(unit) return members[unit].xp end
        _G.UnitXPMax = function(unit) return members[unit].maxXP end
        _G.GetMaxPlayerLevel = function() return 80 end
        _G.IsInGroup = function(category) return party and (not category or instance) end
        _G.IsInRaid = function() return raid end
        _G.issecretvalue = function() return false end
        _G.RegionalUniqueNamesEnabled = function() return false end
        _G.NameUtil = nil
        _G.C_ChatInfo = {
            RegisterAddonMessagePrefix = function(prefix) assert.are.equal("PartyXP", prefix) end,
            SendAddonMessage = function(prefix, message, channel)
                sent[#sent + 1] = { prefix, message, channel }
            end,
        }
        _G.PartyFrame = widget("Frame", "PartyFrame")
        PartyFrame.GetPartyMemberFrame = false
        for index = 1, 4 do
            frames["standard" .. index] = widget("Frame")
            frames["standard" .. index].layoutIndex = index
        end
        PartyFrame.PartyMemberFramePool = {
            EnumerateActive = function()
                local index = 0
                return function()
                    index = index + 1
                    return frames["standard" .. index]
                end
            end,
        }
        _G.CompactPartyFrame = nil
        addon = {}
        assert(loadfile("PartyXP.lua"))("PartyXP", addon)
        assert(loadfile("Options.lua"))("PartyXP", addon)
        fire("ADDON_LOADED", "PartyXP")
        fire("PLAYER_ENTERING_WORLD")
    end)

    it("tracks validated peer XP through Blizzard frame changes and settings", function()
        advance(1)
        assert.are.same({ "PartyXP", "1:25:400:1000", "PARTY" }, sent[1])

        fire("CHAT_MSG_ADDON", "PartyXP", "1:20:350:1000", "PARTY", "Stranger-Realm")
        fire("CHAT_MSG_ADDON", "PartyXP", "1:20:350:1000", "PARTY", "Alice-Realm")
        fire("CHAT_MSG_ADDON", "PartyXP", "1:80:500:1000", "PARTY", "Bob-Realm")
        assert.is_true(addon.bars[1].shown)
        assert.are.equal(350, addon.bars[1].fill.value)
        assert.are.equal(1000, addon.bars[1].fill.maximum)
        assert.is_false(addon.bars[2].shown)
        assert.is_false(addon.bars[3].shown)

        -- Edit Mode's raid-style party frames may sort members independently.
        PartyFrame:Hide()
        _G.CompactPartyFrame = widget("Frame", "CompactPartyFrame")
        CompactPartyFrame.memberUnitFrames = {
            widget("Frame"), widget("Frame"), widget("Frame"), widget("Frame"), widget("Frame"),
        }
        CompactPartyFrame.memberUnitFrames[1].unit = "player"
        CompactPartyFrame.memberUnitFrames[2].unit = "party3"
        CompactPartyFrame.memberUnitFrames[3].unit = "party1"
        CompactPartyFrame.memberUnitFrames[4].unit = "party2"
        CompactPartyFrame.memberUnitFrames[5].unit = "party4"
        advance(0.3)
        assert.are.equal(CompactPartyFrame.memberUnitFrames[3], addon.bars[1].point[2])

        fire("CHAT_MSG_ADDON", "PartyXP", "1:20:700:1000", "PARTY", "Alice-Realm")
        assert.are.equal(700, addon.bars[1].fill.value)
        fire("CHAT_MSG_ADDON", "PartyXP", "1:20:1000000001:1000000002", "PARTY", "Alice-Realm")
        assert.are.equal(700, addon.bars[1].fill.value)

        -- A leveling party member reaching the cap loses their bar immediately.
        members.party1.level = 80
        fire("UNIT_LEVEL", "party1")
        assert.is_false(addon.bars[1].shown)
        members.party1.level = 20
        fire("UNIT_LEVEL", "party1")
        assert.is_true(addon.bars[1].shown)

        SlashCmdList.PARTYXP("off")
        assert.is_false(addon.bars[1].shown)
        SlashCmdList.PARTYXP("on")
        assert.is_true(addon.bars[1].shown)
        assert.is_true(PartyXPDB.enabled)
        assert.are.same({ "PartyXP", "PartyXP" }, notifications)

        SlashCmdList.PARTYXP("")
        assert.are.equal(registeredPanel, addon.optionsPanel)
        assert.are.equal(731, openedCategory)
        assert.are.equal("group", optionsTable.type)
        assert.are.equal("toggle", optionsTable.args.enabled.type)
        assert.are.equal("select", optionsTable.args.position.args.side.type)
        assert.are.equal("range", optionsTable.args.size.args.width.type)
        assert.are.equal("color", optionsTable.args.appearance.args.color.type)
        assert.are.equal("select", optionsTable.args.appearance.args.fillStyle.type)
        assert.are.equal("select", optionsTable.args.appearance.args.borderStyle.type)
        assert.are.equal("toggle", optionsTable.args.appearance.args.rounded.type)

        optionsTable.set({ "size", "width" }, 122)
        optionsTable.set({ "position", "side" }, "LEFT")
        optionsTable.args.appearance.args.color.set(nil, 0.2, 0.6, 0.8)
        assert.are.equal(122, PartyXPDB.width)
        assert.are.equal("LEFT", PartyXPDB.side)
        assert.are.equal("RIGHT", addon.bars[1].point[1])
        assert.are.same({ 0.2, 0.6, 0.8 }, addon.bars[1].fill.color)
        assert.are.equal(122, optionsTable.get({ "size", "width" }))
        assert.are.same({ 0.2, 0.6, 0.8 }, { optionsTable.args.appearance.args.color.get() })

        local bar = addon.bars[1]
        assert.is_true(optionsTable.args.appearance.args.borderStyle.disabled())
        optionsTable.set({ "appearance", "fillStyle" }, "STRIPED")
        optionsTable.set({ "appearance", "borderEnabled" }, true)
        optionsTable.set({ "appearance", "borderStyle" }, "GOLD")
        optionsTable.set({ "appearance", "rounded" }, true)
        assert.are.equal("Interface\\AddOns\\PartyXP\\Media\\Striped.tga", bar.fillTexture.texture)
        assert.is_false(optionsTable.args.appearance.args.borderStyle.disabled())
        assert.is_true(bar.borderSurface.shown)
        assert.are.same({ 0.9, 0.7, 0.3, 1 }, bar.borderSurface.color)
        assert.are.equal(2, bar.borderInset)
        assert.is_true(bar.borderSurface.masks[bar.outerMask])
        assert.is_true(bar.background.masks[bar.backgroundMask])
        assert.is_true(bar.fillTexture.masks[bar.fillMask])
        assert.are.equal("Interface\\AddOns\\PartyXP\\Media\\Rounded-16.tga", bar.fillMask.texture)
        assert.are.near(82.6, bar.fillMask.width, 0.001)
        assert.are.equal(4, bar.fillMask.height)

        -- Appearance remains attached to the same peer when its XP and frame change.
        fire("CHAT_MSG_ADDON", "PartyXP", "1:20:100:1000", "PARTY", "Alice-Realm")
        assert.are.equal("Interface\\AddOns\\PartyXP\\Media\\Rounded-2.tga", bar.fillMask.texture)
        assert.are.near(11.8, bar.fillMask.width, 0.001)
        assert.are.equal(100, bar.fill.value)
        optionsTable.set({ "appearance", "fillStyle" }, "GLOSS")
        assert.are.equal("Interface\\AddOns\\PartyXP\\Media\\Gloss.tga", bar.fillTexture.texture)
        assert.is_true(bar.fillTexture.masks[bar.fillMask])
        assert.is_true(bar.shown)

        optionsTable.set({ "appearance", "opacity" }, 0.5)
        assert.are.equal(0.5, addon.bars[1].alpha)
        optionsTable.args.reset.func()
        assert.are.equal(80, PartyXPDB.width)
        assert.are.equal("RIGHT", PartyXPDB.side)
        assert.are.equal(1, addon.bars[1].alpha)
        assert.are.equal("LEFT", addon.bars[1].point[1])
        assert.are.same({ 0.45, 0.28, 0.95 }, addon.bars[1].fill.color)
        assert.are.equal("CLASSIC", PartyXPDB.fillStyle)
        assert.is_false(PartyXPDB.borderEnabled)
        assert.is_false(PartyXPDB.rounded)
        assert.is_false(bar.borderSurface.shown)
        assert.is_nil(bar.fillTexture.masks[bar.fillMask])
        assert.are.equal("PartyXP", notifications[#notifications])

        -- Old messages must stop driving bars when a peer goes silent.
        advance(91)
        assert.is_false(addon.bars[1].shown)
        instance = true
        members.player.xp = 800
        fire("PLAYER_XP_UPDATE")
        advance(1)
        assert.are.same({ "PartyXP", "1:25:800:1000", "INSTANCE_CHAT" }, sent[#sent])
    end)

    it("matches Forever party members by full first name and surname", function()
        members.party1.surname = "Brightvale"
        members.party3.name = "Alice"
        members.party3.surname = "Stone"
        _G.RegionalUniqueNamesEnabled = function() return true end
        _G.NameUtil = {
            GetUnmodifiedUnitFullName = function(unit)
                local member = members[unit]
                if not member then return nil end
                return member.surname and (member.name .. " " .. member.surname) or member.name
            end,
        }

        fire("CHAT_MSG_ADDON", "PartyXP", "1:20:350:1000", "PARTY", "Alice")
        fire("CHAT_MSG_ADDON", "PartyXP", "1:20:350:1000", "PARTY", "Alice-Brightvale")
        assert.is_false(addon.bars[1].shown)
        assert.is_false(addon.bars[3].shown)

        fire("CHAT_MSG_ADDON", "PartyXP", "1:20:350:1000", "PARTY", "Alice Brightvale")
        fire("CHAT_MSG_ADDON", "PartyXP", "1:30:700:1200", "PARTY", "Alice Stone")
        assert.is_true(addon.bars[1].shown)
        assert.are.equal(350, addon.bars[1].fill.value)
        assert.is_true(addon.bars[3].shown)
        assert.are.equal(700, addon.bars[3].fill.value)
        assert.are.equal(frames.standard1, addon.bars[1].point[2])
        assert.are.equal(frames.standard3, addon.bars[3].point[2])
    end)
end)
