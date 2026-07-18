local _, BCDM = ...

local ELVUI_ANCHORS = {
    ElvUF_Player = "|cff1784d1ElvUI|r: Player Frame",
    ElvUF_Target = "|cff1784d1ElvUI|r: Target Frame",
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

function BCDM:ResolveAnchorParent(frameName)
    if frameName == nil or frameName == "NONE" then return UIParent end
    return _G[frameName] or UIParent
end
