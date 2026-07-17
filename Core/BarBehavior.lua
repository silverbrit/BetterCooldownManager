local _, BCDM = ...

function BCDM:ShouldSmoothBar(barSettings, sharedSmooth)
    local mode = barSettings and barSettings.Smoothing or "INHERIT"
    if mode == "ON" then return true end
    if mode == "OFF" then return false end
    return sharedSmooth == true
end

function BCDM:FormatResourceText(current, maximum, mode)
    if self.IsSecretValue and (self:IsSecretValue(current) or self:IsSecretValue(maximum)) then
        return ""
    end
    current, maximum = tonumber(current) or 0, tonumber(maximum) or 0
    if mode == "CURRENT_MAX" then return string.format("%s / %s", current, maximum) end
    if mode == "PERCENT" then
        local percent = maximum > 0 and (current / maximum) * 100 or 0
        return string.format("%.0f%%", percent)
    end
    return tostring(current)
end

function BCDM:ApplyStatusBarDirection(statusBar, direction)
    if statusBar and statusBar.SetReverseFill then statusBar:SetReverseFill(direction == "LEFT") end
end

function BCDM:AnchorStatusBarSpark(spark, statusBar, direction)
    if not spark or not statusBar then return end
    local edge = direction == "LEFT" and "LEFT" or "RIGHT"
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", statusBar:GetStatusBarTexture(), edge, 0, 0)
end
