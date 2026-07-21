local BCDM, Check = ...

local width, height, positions = BCDM.ComputeTrackedBuffLayout(3, 32, 24, 2, true)
Check(width == 100 and height == 24, "horizontal tracked buffs use a tight container")
Check(positions[1][1] == 0 and positions[2][1] == 34 and positions[3][1] == 68,
    "horizontal tracked buffs grow from the container's left edge")
Check(positions[1][2] == 0 and positions[3][2] == 0,
    "horizontal tracked buffs remain on one row")

width, height, positions = BCDM.ComputeTrackedBuffLayout(3, 32, 24, 2, false)
Check(width == 32 and height == 76, "vertical tracked buffs use a tight container")
Check(positions[1][2] == 0 and positions[2][2] == -26 and positions[3][2] == -52,
    "vertical tracked buffs grow from the container's top edge")
Check(positions[1][1] == 0 and positions[3][1] == 0,
    "vertical tracked buffs remain in one column")

width, height, positions = BCDM.ComputeTrackedBuffLayout(0, 32, 24, 2, true)
Check(width == 0 and height == 0 and #positions == 0,
    "empty tracked buff groups do not invent layout slots")

width, height, positions = BCDM.ComputeTrackedBuffLayout(2, 32, 24, -1, true)
Check(width == 63 and height == 24 and positions[2][1] == 31,
    "tracked buff layout preserves Blizzard's negative padding")

local frameWidth, frameHeight, xOffset, yOffset = BCDM.ScaleTrackedBuffGeometry(32, 24, 34, -26, 0.5)
Check(frameWidth == 64 and frameHeight == 48 and xOffset == 68 and yOffset == -52,
    "tracked buff geometry compensates for Blizzard frame scale")

frameWidth, frameHeight, xOffset, yOffset = BCDM.ScaleTrackedBuffGeometry(32, 24, 34, -26, 0)
Check(frameWidth == 32 and frameHeight == 24 and xOffset == 34 and yOffset == -26,
    "invalid tracked buff frame scales safely fall back to one")

local frames = BCDM.SortTrackedBuffFrames({
    { layoutIndex = 3 }, { layoutIndex = 1 }, { layoutIndex = 2 },
})
Check(frames[1].layoutIndex == 1 and frames[2].layoutIndex == 2 and frames[3].layoutIndex == 3,
    "tracked buff frames retain Blizzard's layout order")

local function TrackedBuffFrame(layoutIndex, shown, cooldownID)
    return {
        Icon = {},
        cooldownID = cooldownID,
        includeAsLayoutChildWhenHidden = true,
        layoutIndex = layoutIndex,
        IsShown = function() return shown end,
    }
end

local visibleFrame = TrackedBuffFrame(7, true, 1007)
frames = BCDM.CollectRenderableTrackedBuffFrames({
    TrackedBuffFrame(1, false, 1001),
    visibleFrame,
    TrackedBuffFrame(3, false, 1003),
    TrackedBuffFrame(4, true, nil),
})
Check(#frames == 1 and frames[1] == visibleFrame,
    "hidden Blizzard layout children and empty edit-mode slots do not reserve centering space")

width = BCDM.ComputeTrackedBuffLayout(#frames, 32, 32, 0, true)
Check(width == 32, "one rendered tracked buff produces a one-icon-wide centering container")
