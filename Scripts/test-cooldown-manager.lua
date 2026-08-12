local BCDM, Check = ...

local width, height, positions = BCDM.ComputeCenteredTrackedBuffLayout({
    { width = 32, height = 32 },
    { width = 32, height = 32 },
    { width = 32, height = 32 },
}, 2, true, true)
Check(width == 100 and height == 32, "horizontal tracked buffs reserve the full visible row")
Check(positions[1][1] == -34 and positions[2][1] == 0 and positions[3][1] == 34,
    "horizontal tracked buffs are centered with native spacing")

width, height, positions = BCDM.ComputeCenteredTrackedBuffLayout({
    { width = 32, height = 24 },
    { width = 32, height = 24 },
}, 2, false, true)
Check(width == 32 and height == 50, "vertical tracked buffs reserve the full visible column")
Check(positions[1][2] == -13 and positions[2][2] == 13,
    "vertical growth preserves Blizzard's bottom-to-top order")

width, height, positions = BCDM.ComputeCenteredTrackedBuffLayout({
    { width = 32, height = 32 }, { width = 32, height = 32 },
}, 2, true, false)
Check(width == 66 and height == 32 and positions[1][1] == 17 and positions[2][1] == -17,
    "reverse horizontal growth preserves Blizzard's right-to-left order")

local frames = {
    { layoutIndex = 3, order = 2 },
    { layoutIndex = 1, order = 3 },
    { layoutIndex = 2, order = 1 },
}
BCDM.SortTrackedBuffFrames(frames)
Check(frames[1].layoutIndex == 1 and frames[2].layoutIndex == 2 and frames[3].layoutIndex == 3,
    "native tracked buff frames follow Blizzard layoutIndex order")
