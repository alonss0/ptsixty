local _, addon = ...
local route, talents, weapons
local state, loaded, review

local frame = CreateFrame("Frame", "OrcTo60Frame", UIParent, "BackdropTemplate")
frame:SetSize(390, 244)
frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -185)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 32, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    state.x, state.y = x, y
end)
frame:Hide()

local function label(font, y, right)
    local line = frame:CreateFontString(nil, "OVERLAY", font)
    line:SetPoint("TOPLEFT", 14, y)
    line:SetPoint("TOPRIGHT", right or -14, y)
    line:SetJustifyH("LEFT")
    return line
end

local heading = label("GameFontNormal", -13, -36)
local clock = label("GameFontHighlightSmall", -32)
local talent = label("GameFontNormalSmall", -48)
local weapon = label("GameFontHighlightSmall", -65)
local action = label("GameFontHighlight", -73)
action:SetMaxLines(5)
local nextSteps = label("GameFontDisableSmall", -162)
nextSteps:SetMaxLines(3)

local function button(title, x, width, onClick)
    local control = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    control:SetSize(width, 22)
    control:SetPoint("BOTTOMLEFT", x, 12)
    control:SetText(title)
    control:SetScript("OnClick", onClick)
    return control
end

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)
close:SetScript("OnClick", function()
    state.hidden = true
    frame:Hide()
end)

local function now()
    return GetServerTime()
end

local function showTime()
    local seconds = state.finished and (state.finished - state.started) or (now() - state.started)
    seconds = math.max(0, seconds)
    local elapsed = ("%02d:%02d:%02d"):format(
        math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    clock:SetText(elapsed .. " elapsed" .. (state.partial and " (partial run)" or ""))
end

local function current()
    return review or state.step
end

local function canWaypoint(step)
    return step and step.map and TomTom and type(TomTom.AddWaypoint) == "function"
end

local back, nextButton, waypoint, resume
local function render(level)
    local index = current()
    local step = route[index]
    level = level or UnitLevel("player")
    heading:SetText(step.section .. "  |  " .. index .. "/" .. #route)
    local point = talents[level]
    talent:SetText(point and ("Lv " .. level .. " talent: " .. point) or "")
    if weapons then
        local recommendation = weapons[level]
        weapon:SetText(recommendation and ("Weapons: " .. recommendation) or "")
    end
    local text = step.text
    if step.map then
        text = text .. ("\n%s  %.1f, %.1f"):format(step.zone, step.x, step.y)
    end
    action:SetText(text)

    local upcoming = {}
    for following = index + 1, math.min(index + 2, #route) do
        local preview = route[following].text
        upcoming[#upcoming + 1] = preview:len() > 58 and preview:sub(1, 55) .. "..." or preview
    end
    nextSteps:SetText(#upcoming > 0 and ("Up next\n" .. table.concat(upcoming, "\n")) or "")
    back:SetEnabled(index > 1)
    nextButton:SetEnabled(index < #route and (review ~= nil or step.level ~= 60 or level >= 60))
    waypoint:SetEnabled(not not canWaypoint(step))
    resume:SetShown(review ~= nil)
    showTime()
end

local function isDone(step, level)
    if step.level then
        return level >= step.level
    end
    local quest = step.quest
    if not quest or not C_QuestLog then return false end
    if step.kind == "objectives" then
        for _, id in ipairs(quest) do
            local turnedIn = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)
            local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
            if not turnedIn and not complete then return false end
        end
        return true
    end
    if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(quest) then
        return true
    end
    if step.kind == "accept" then
        if C_QuestLog.GetLogIndexForQuestID then
            return (C_QuestLog.GetLogIndexForQuestID(quest) or 0) > 0
        end
        return C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(quest)
    end
    return false
end

local function advance(level)
    level = level or UnitLevel("player")
    while state.step < #route and isDone(route[state.step], level) do
        state.step = state.step + 1
    end
    render(level)
end

back = button("Back", 13, 61, function()
    review = current() - 1
    render()
end)
nextButton = button("Next", 79, 61, function()
    if review then
        review = review + 1
        if review >= state.step then review = nil end
        render()
    else
        state.step = state.step + 1
        advance()
    end
end)
local pin, pinOwner
waypoint = button("Waypoint", 145, 88, function()
    local step = route[current()]
    if not canWaypoint(step) then return end
    if pin and pinOwner == TomTom and TomTom.RemoveWaypoint then
        TomTom:RemoveWaypoint(pin)
    end
    pinOwner = TomTom
    pin = TomTom:AddWaypoint(step.map, step.x / 100, step.y / 100, {
        title = "OrcTo60 - " .. step.text, source = "OrcTo60", persistent = false,
        crazy = true,
    })
end)
resume = button("Current step", 238, 96, function()
    review = nil
    render()
end)

local function start()
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    if race ~= "Orc" or UnitFactionGroup("player") ~= "Horde" then
        return
    end

    if class == "HUNTER" then
        route, talents = addon.route, addon.talents
    elseif class == "ROGUE" then
        route, talents, weapons = addon.rogueRoute, addon.rogueTalents, addon.rogueWeapons
        frame:SetHeight(260)
        action:ClearAllPoints()
        action:SetPoint("TOPLEFT", 14, -89)
        action:SetPoint("TOPRIGHT", -14, -89)
        nextSteps:ClearAllPoints()
        nextSteps:SetPoint("TOPLEFT", 14, -178)
        nextSteps:SetPoint("TOPRIGHT", -14, -178)
    else
        return
    end

    OrcTo60DB = OrcTo60DB or {}
    state = OrcTo60DB
    local level = UnitLevel("player")
    if not state.started then
        state.started = now()
        state.partial = level ~= 1 or UnitXP("player") > 0
        state.step = 1
        if state.partial then
            for index, step in ipairs(route) do
                if step.entry and level >= step.entry then state.step = index end
            end
        end
    elseif class == "ROGUE" and not state.rogueRouteVersion then
        local oldStep = tonumber(state.step) or 1
        local chapter = 1
        for index, start in ipairs(addon.legacyRogueStarts) do
            if start > oldStep then break end
            chapter = index
        end
        for index, step in ipairs(route) do
            if step.entry then
                chapter = chapter - 1
                if chapter == 0 then
                    state.step = index
                    break
                end
            end
        end
    end
    if class == "ROGUE" then state.rogueRouteVersion = 1 end
    state.step = math.min(#route, math.max(1, tonumber(state.step) or 1))
    if state.x and state.y then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", state.x, state.y)
    end
    loaded = true
    if not state.hidden then frame:Show() end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then start() end
    if not loaded then return end
    local level = event == "PLAYER_LEVEL_UP" and arg1 or UnitLevel("player")
    if level >= 60 then
        state.finished = state.finished or now()
        state.step = #route
        review = nil
    end
    advance(level)
end)

C_Timer.NewTicker(1, function()
    if loaded and frame:IsShown() then showTime() end
end)

SLASH_ORCTO601 = "/orc60"
SlashCmdList.ORCTO60 = function()
    if not loaded then
        print("OrcTo60 is for Horde Orc Hunters and Rogues.")
        return
    end
    state.hidden = frame:IsShown()
    frame:SetShown(not state.hidden)
    if frame:IsShown() then render() end
end
