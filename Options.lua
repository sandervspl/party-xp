local addonName, addon = ...

local function GetSetting(info)
    return addon.db[info[#info]]
end

local function SetSetting(info, value)
    addon.db[info[#info]] = value
    addon:RefreshBars()
end

local function ResetDefaults()
    for key, value in pairs(addon.defaults) do
        if type(value) == "table" then
            addon.db[key] = { r = value.r, g = value.g, b = value.b }
        else
            addon.db[key] = value
        end
    end
    addon:RefreshBars()
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

local options = {
    type = "group",
    name = "Party XP",
    get = GetSetting,
    set = SetSetting,
    args = {
        enabled = {
            type = "toggle",
            name = "Show party XP bars",
            order = 1,
            width = "full",
        },
        note = {
            type = "description",
            name = "Party members need Party XP installed to share their progress.",
            order = 2,
            width = "full",
        },
        size = {
            type = "group",
            name = "Size",
            inline = true,
            order = 3,
            args = {
                width = {
                    type = "range",
                    name = "Width",
                    order = 1,
                    width = "double",
                    min = 30, max = 240, step = 1,
                },
                height = {
                    type = "range",
                    name = "Height",
                    order = 2,
                    width = "double",
                    min = 3, max = 30, step = 1,
                },
            },
        },
        position = {
            type = "group",
            name = "Position",
            inline = true,
            order = 4,
            args = {
                side = {
                    type = "select",
                    name = "Attach to",
                    order = 1,
                    width = "double",
                    values = { LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" },
                    sorting = { "LEFT", "RIGHT", "TOP", "BOTTOM" },
                },
                sideHelp = {
                    type = "description",
                    name = "Choose the edge of each party frame.",
                    order = 2,
                    width = "double",
                },
                offsetX = {
                    type = "range",
                    name = "Horizontal offset",
                    order = 3,
                    width = "double",
                    min = -100, max = 100, step = 1,
                },
                offsetY = {
                    type = "range",
                    name = "Vertical offset",
                    order = 4,
                    width = "double",
                    min = -100, max = 100, step = 1,
                },
            },
        },
        appearance = {
            type = "group",
            name = "Appearance",
            inline = true,
            order = 5,
            args = {
                opacity = {
                    type = "range",
                    name = "Opacity",
                    order = 1,
                    width = "double",
                    min = 0.1, max = 1, step = 0.05,
                    isPercent = true,
                },
                color = {
                    type = "color",
                    name = "Bar color",
                    order = 2,
                    width = "double",
                    hasAlpha = false,
                    get = function()
                        local color = addon.db.color
                        return color.r, color.g, color.b
                    end,
                    set = function(_, r, g, b)
                        local color = addon.db.color
                        color.r, color.g, color.b = r, g, b
                        addon:RefreshBars()
                    end,
                },
            },
        },
        reset = {
            type = "execute",
            name = "Reset defaults",
            order = 6,
            func = ResetDefaults,
        },
    },
}

function addon:InitializeOptions()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, options)
    self.optionsPanel, self.optionsCategoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "Party XP")
end

function addon:OpenOptions()
    if self.optionsCategoryID then
        Settings.OpenToCategory(self.optionsCategoryID)
    end
end

SLASH_PARTYXP1 = "/partyxp"
SLASH_PARTYXP2 = "/pxp"
SlashCmdList.PARTYXP = function(message)
    if not addon.db then return end
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "on" or message == "off" then
        addon.db.enabled = message == "on"
        addon:RefreshBars()
        LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
    else
        addon:OpenOptions()
    end
end
