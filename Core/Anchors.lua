local _, BCDM = ...

local ELVUI_ANCHORS = {
    ElvUF_Player = "|cff1784d1ElvUI|r: Player Frame",
    ElvUF_Target = "|cff1784d1ElvUI|r: Target Frame",
}

local ANCHOR_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

function BCDM:BuildAnchorParents(source, elvUIActive, elvUIAnchors)
    if type(source) ~= "table" then return { {}, {} } end
    local labels, order = {}, {}
    for _, key in ipairs(source[2] or {}) do
        if not (elvUIActive and (key == "PlayerFrame" or key == "TargetFrame")) then
            labels[key] = source[1] and source[1][key]
            order[#order + 1] = key
        end
    end
    for key, label in pairs(source[1] or {}) do
        if labels[key] == nil and not (elvUIActive and (key == "PlayerFrame" or key == "TargetFrame")) then
            labels[key] = label
        end
    end
    if elvUIActive then
        for _, key in ipairs({ "ElvUF_Player", "ElvUF_Target" }) do
            labels[key] = elvUIAnchors[key]
            order[#order + 1] = key
        end
    end
    return { labels, order }
end

function BCDM:IsElvUIActive()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI") == true
end

function BCDM:GetAnchorParents(anchorType)
    return self:BuildAnchorParents(self.AnchorParents[anchorType], self:IsElvUIActive(), ELVUI_ANCHORS)
end

local function IsSecret(self, value)
    return type(self.IsSecretValue) == "function" and self:IsSecretValue(value)
end

local function ReadMethod(self, frame, methodName)
    local ok, method = pcall(function() return frame and frame[methodName] end)
    if not ok or IsSecret(self, method) or type(method) ~= "function" then return end
    return method
end

function BCDM:IsSafeAnchorParent(frame)
    if frame and frame == UIParent then return true end
    if not frame or IsSecret(self, frame) then return false end

    local isObjectType = ReadMethod(self, frame, "IsObjectType")
    if not isObjectType then return false end
    local okFrame, isFrame = pcall(isObjectType, frame, "Frame")
    if not okFrame or IsSecret(self, isFrame) or isFrame ~= true then return false end

    local isForbidden = ReadMethod(self, frame, "IsForbidden")
    if not isForbidden then return false end
    local okForbidden, forbidden = pcall(isForbidden, frame)
    if not okForbidden or IsSecret(self, forbidden) or forbidden ~= false then return false end

    return ReadMethod(self, frame, "SetPoint") ~= nil
end

function BCDM:SetSafeAnchorPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
    local setPoint = ReadMethod(self, frame, "SetPoint")
    if not setPoint then return false end
    point = not IsSecret(self, point) and ANCHOR_POINTS[point] and point or "CENTER"
    relativePoint = not IsSecret(self, relativePoint) and ANCHOR_POINTS[relativePoint] and relativePoint or "CENTER"
    xOffset = not IsSecret(self, xOffset) and type(xOffset) == "number" and xOffset or 0
    yOffset = not IsSecret(self, yOffset) and type(yOffset) == "number" and yOffset or 0
    local anchor = self:IsSafeAnchorParent(relativeTo) and relativeTo or UIParent
    if pcall(setPoint, frame, point, anchor, relativePoint, xOffset, yOffset) then return true end
    if anchor ~= UIParent and UIParent then
        return pcall(setPoint, frame, point, UIParent, relativePoint, xOffset, yOffset)
    end
    return false
end

function BCDM:ResolveAnchorParent(frameName)
    if type(frameName) ~= "string" or IsSecret(self, frameName)
        or frameName == "NONE" then return UIParent end
    local frame = _G[frameName]
    return self:IsSafeAnchorParent(frame) and frame or UIParent
end

local POWER_BAR_FRAMES = {
    PowerBar = "BCDM_PowerBar",
    SecondaryPowerBar = "BCDM_SecondaryPowerBar",
}

local POWER_BAR_TYPES = {
    BCDM_PowerBar = "PowerBar",
    BCDM_SecondaryPowerBar = "SecondaryPowerBar",
    BCDM_CastBar = "CastBar",
}

local function ConfiguredPowerBarTarget(self, frameName, secondaryOwnsPrimary)
    local barType = POWER_BAR_TYPES[frameName]
    if not barType then return end
    if secondaryOwnsPrimary and barType == "SecondaryPowerBar" then barType = "PowerBar" end
    local profile = self.db and self.db.profile
    local settings = profile and profile[barType]
    local layout = settings and settings.Layout
    return layout and layout[2]
end

function BCDM:ResolvePowerBarAnchorParent(barType, layout, secondaryOwnsPrimary)
    local targetName = layout and layout[2]
    local originalTarget = targetName
    local sourceFrame = POWER_BAR_FRAMES[barType]
    if sourceFrame and targetName then
        if type(targetName) ~= "string" or IsSecret(self, targetName) then return UIParent end
        local visited = { [sourceFrame] = true }
        while POWER_BAR_TYPES[targetName] do
            if visited[targetName] then return UIParent end
            visited[targetName] = true
            targetName = ConfiguredPowerBarTarget(self, targetName, secondaryOwnsPrimary)
            if not targetName then break end
            if type(targetName) ~= "string" or IsSecret(self, targetName) then return UIParent end
        end
    end
    return self:ResolveAnchorParent(originalTarget)
end

function BCDM:GetPowerBarLayout(barType, secondaryOwnsPrimary)
    local profile = self.db and self.db.profile
    local settings = profile and profile[barType]
    if barType == "SecondaryPowerBar" and secondaryOwnsPrimary then
        settings = profile and profile.PowerBar
    end
    local layout = settings and settings.Layout or {}
    return layout, self:ResolvePowerBarAnchorParent(barType, layout, secondaryOwnsPrimary)
end

function BCDM:NormalizeEssentialAnchorProfile(profile)
    local cooldownManager = type(profile) == "table" and profile.CooldownManager
    local essential = type(cooldownManager) == "table" and cooldownManager.Essential
    local layout = type(essential) == "table" and essential.Layout
    if type(layout) ~= "table" or layout[5] ~= nil or not ANCHOR_POINTS[layout[2]] then return false end
    essential.Layout = { layout[1], "NONE", layout[2], layout[3] or 0, layout[4] or 0 }
    return true
end

function BCDM:NormalizeEssentialAnchorProfiles(db)
    local profiles = db and db.sv and db.sv.profiles
    if type(profiles) ~= "table" then return false end
    local changed = false
    for _, profile in pairs(profiles) do
        if self:NormalizeEssentialAnchorProfile(profile) then changed = true end
    end
    return changed
end
