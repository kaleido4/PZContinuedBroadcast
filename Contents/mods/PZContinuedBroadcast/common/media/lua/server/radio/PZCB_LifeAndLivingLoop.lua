--[[
    Continued Broadcast - keeps Life and Living TV on the air forever.

    In vanilla the Life and Living channel runs a single script ("main") that airs
    real programmes for the first ~9.5 days, followed by ~2.5 days of "<bzzt>"
    static. The script has no exit options and loops only once, so when it ends
    the channel has no script left and goes silent for the rest of the game.

    This file:
      1. trims the trailing static off "main", so the script ends right after the
         last real programme (day 9, noon);
      2. reruns "main" according to the sandbox "Rerun Schedule":
           - Back to back: an exit option from "main" to itself restarts it at
             midnight after it ends, plus "Days Off Air Between Reruns";
           - Monthly: no exit option; once the script ends we schedule the next
             run to start on the 1st of the next month;
      3. restarts the channel in saves where it already went off the air.

    A script started with a future start day just waits: none of its broadcasts
    are valid to air until their timestamps come up.

    TV lines are sent without a media-line GUID, so the vanilla "already seen"
    check never applies to them: reruns give skill XP again (still capped by the
    "Media XP Level Cutoff" sandbox option) and teach any recipes not yet known.
    With the sandbox option "Reruns Give XP Again" off, we give each Life and
    Living line an ID of our own and store it in the character's known media
    lines, then strip skill codes from lines the character has already seen.

    Radio scripts only run in singleplayer and on the server, never on
    multiplayer clients, so this file sits in media/lua/server.
--]]

if isClient() then return end

local CHANNEL_GUID = "9f7e57f1-461c-4600-a8a1-0f5d2ee27889" -- "Life and Living TV" in RadioData.xml
local CHANNEL_FREQ = 203
local SCRIPT_NAME = "main"

local SCHEDULE_BACK_TO_BACK = 1
local SCHEDULE_MONTHLY = 2

local channel = nil
local contentEnd = nil -- minutes from the script's start day to the end of the last programme

local function log(msg)
    print("[PZContinuedBroadcast] " .. tostring(msg))
end

local function getOptions()
    local opts = SandboxVars and SandboxVars.PZContinuedBroadcast or {}
    return opts.Schedule or SCHEDULE_BACK_TO_BACK, math.max(0, opts.DaysOffAir or 0)
end

local function rerunsGiveXP()
    local opts = SandboxVars and SandboxVars.PZContinuedBroadcast or {}
    return opts.RerunXP ~= false
end

local function findChannel(scriptManager)
    local found = scriptManager:getRadioChannel(CHANNEL_GUID)
    if found then return found end

    -- Fallback in case the channel GUID ever changes.
    local list = scriptManager:getChannelsList()
    for i = 0, list:size() - 1 do
        local c = list:get(i)
        if c:IsTv() and c:GetFrequency() == CHANNEL_FREQ then
            return c
        end
    end
    return nil
end

-- A broadcast is "real content" if any of its lines carries interaction codes
-- (skill XP, recipes, boredom, stress...). The end-of-run static has none.
local function hasCodes(broadcast)
    local lines = broadcast:getLines()
    for i = 0, lines:size() - 1 do
        local codes = lines:get(i):getEffectsString()
        if codes and codes ~= "" then
            return true
        end
    end
    return false
end

-- Removes the static after the last real programme. Returns the minute (from the
-- script's start day) at which the remaining broadcasts end.
local function trimStatic(script)
    local list = script:getBroadcastList()
    if list:size() == 0 then return 0 end

    local lastCoded = nil
    for i = 0, list:size() - 1 do
        local bc = list:get(i)
        if hasCodes(bc) then
            lastCoded = bc:getEndStamp()
        end
    end
    if not lastCoded then
        log("no coded broadcasts found in '" .. SCRIPT_NAME .. "', leaving it untrimmed")
        return list:get(list:size() - 1):getEndStamp()
    end

    local keep = {}
    for i = 0, list:size() - 1 do
        local bc = list:get(i)
        if bc:getStartStamp() < lastCoded then
            keep[#keep + 1] = bc
        end
    end
    if #keep < list:size() then
        local removed = list:size() - #keep
        list:clear()
        for _, bc in ipairs(keep) do
            script:AddBroadcast(bc)
        end
        log("trimmed " .. removed .. " static broadcasts, programmes end at minute " .. lastCoded
            .. " (day " .. math.floor(lastCoded / 1440) .. ")")
    end
    return lastCoded
end

local function hasExitTo(script, name)
    local options = script:getExitOptions()
    for i = 0, options:size() - 1 do
        if options:get(i):getScriptname() == name then
            return true
        end
    end
    return false
end

local function makeLoop(script, daysOffAir)
    if hasExitTo(script, SCRIPT_NAME) then return end
    script:AddExitOption(SCRIPT_NAME, 100, daysOffAir)
    if hasExitTo(script, SCRIPT_NAME) then
        log("'" .. SCRIPT_NAME .. "' reruns back to back, " .. daysOffAir .. " day(s) off air between runs")
    else
        log("could not add exit option to '" .. SCRIPT_NAME .. "' (another mod may already use its exit chances)")
    end
end

-- Fired from ZomboidRadio.Init after all channels are loaded, but before the
-- saved radio state is restored or a new game is simulated forward.
local function onLoadRadioScripts(scriptManager, isNewGame)
    channel = findChannel(scriptManager)
    if not channel then
        log("Life and Living channel not found, nothing to do")
        return
    end

    local script = channel:getRadioScript(SCRIPT_NAME)
    if not script then
        log("script '" .. SCRIPT_NAME .. "' not found on " .. channel:GetName() .. ", nothing to do")
        channel = nil
        return
    end

    contentEnd = trimStatic(script)

    local schedule, daysOffAir = getOptions()
    if schedule == SCHEDULE_MONTHLY then
        log("'" .. SCRIPT_NAME .. "' reruns monthly, from the 1st of each month")
    else
        makeLoop(script, daysOffAir)
    end
end

-- Radio day on which the next monthly run should start. If this month's run
-- would still be in progress, returns this month's 1st so the schedule resumes
-- mid-way on the correct dates.
local function monthlyStartDay(today)
    local gt = getGameTime()
    local dayOfMonth = gt:getDay() -- 0 = the 1st
    local minutesIntoMonth = dayOfMonth * 1440 + gt:getHour() * 60 + gt:getMinutes()
    if minutesIntoMonth < contentEnd then
        return today - dayOfMonth
    end
    return today + gt:daysInMonth(gt:getYear(), gt:getMonth()) - dayOfMonth
end

-- Called when the channel has no active script: either the monthly run just
-- ended, or the save already went off the air before the mod was added.
local function scheduleNextRun()
    if not channel or channel:getCurrentScript() ~= nil then return end

    local today = getZomboidRadio():getDaysSinceStart()
    local schedule = getOptions()
    local startDay = today
    if schedule == SCHEDULE_MONTHLY then
        startDay = monthlyStartDay(today)
    end

    channel:setActiveScript(SCRIPT_NAME, startDay)
    log("channel off the air, next run scheduled for radio day " .. startDay .. " (today is " .. today .. ")")
end

--------------------------------------------------------------------------------
-- XP once per character ("Reruns Give XP Again" off)
--------------------------------------------------------------------------------

-- Interaction codes handled as stats by ISRadioInteractions. Everything else
-- except recipes ("RCP") is treated as skill XP, so new skills are covered too.
local STAT_CODES = {
    ANG = true, BOR = true, END = true, FAT = true, FIT = true, HUN = true, MOR = true, STS = true,
    PAN = true, SAN = true, SIC = true, PAI = true, DRU = true, THI = true, UHP = true, RCP = true,
}

local function stripSkillCodes(codes)
    local kept = {}
    for code in string.gmatch(codes, "[^,]+") do
        if STAT_CODES[string.sub(code, 1, 3)] then
            kept[#kept + 1] = code
        end
    end
    return table.concat(kept, ",")
end

-- ID of the Life and Living line that is airing right now, set while the
-- vanilla OnDeviceText handler runs for it.
local currentLineId = nil

-- OnDeviceText fires synchronously while the channel sends a line, so the
-- channel's airing broadcast and line counter point at the line being sent.
local function identifyLine(codes, device)
    if not channel or not device or not codes or codes == "" then return nil end

    local data = device
    if not instanceof(device, "DeviceData") then
        local ok, result = pcall(function() return device:getDeviceData() end)
        data = ok and result or nil
    end
    if not data or not data:getIsTelevision() or data:getChannel() ~= channel:GetFrequency() then
        return nil
    end

    local bc = channel:getAiringBroadcast()
    if not bc then return nil end
    local lines = bc:getLines()
    local index = bc:getCurrentLineNumber() -- 1-based once a line has been sent
    if index < 1 or index > lines:size() then return nil end
    -- ad segments don't advance the counter, so make sure this really is that line
    if lines:get(index - 1):getEffectsString() ~= codes then return nil end

    return "PZCB:" .. bc:getID() .. ":" .. index
end

-- Mirrors the early returns in ISRadioInteractions.checkPlayer, so a line only
-- counts as watched when the character actually takes it in.
local function canReceive(player, x, y, z)
    if player:isAsleep() then return false end
    if not (x == -1 and y == -1 and z == -1) then
        local source = getCell():getGridSquare(x, y, z)
        local square = player:getSquare()
        if source and square and source:isOutside() ~= square:isOutside() then
            return false
        end
    end
    return true
end

local xpHooksInstalled = false

local function installXPHooks()
    if xpHooksInstalled or not ISRadioInteractions then return end
    xpHooksInstalled = true

    local radio = ISRadioInteractions:getInstance()

    local vanillaCheckPlayer = radio.checkPlayer
    radio.checkPlayer = function(player, guid, codes, x, y, z, line, source)
        if currentLineId and codes and canReceive(player, x, y, z) then
            local statCodes = stripSkillCodes(codes)
            if statCodes ~= codes then -- only lines that teach skills are tracked
                if not player:isKnownMediaLine(currentLineId) then
                    player:addKnownMediaLine(currentLineId)
                elseif not rerunsGiveXP() then
                    codes = statCodes
                end
            end
        end
        return vanillaCheckPlayer(player, guid, codes, x, y, z, line, source)
    end

    -- The vanilla handler ignores the 7th argument (the device), which we need,
    -- so swap it for a wrapper that remembers which line is airing.
    local vanillaOnDeviceText = radio.OnDeviceText
    Events.OnDeviceText.Remove(vanillaOnDeviceText)
    Events.OnDeviceText.Add(function(guid, codes, x, y, z, line, device)
        -- set on every call, so a vanilla error can't leave a stale ID behind
        currentLineId = (guid == nil or guid == "") and identifyLine(codes, device) or nil
        vanillaOnDeviceText(guid, codes, x, y, z, line)
        currentLineId = nil
    end)
    log("XP hooks installed")
end

Events.OnGameBoot.Add(installXPHooks)
Events.OnGameStart.Add(installXPHooks)
Events.OnServerStarted.Add(installXPHooks)
Events.OnLoadRadioScripts.Add(onLoadRadioScripts)
Events.OnGameStart.Add(scheduleNextRun)     -- singleplayer
Events.OnServerStarted.Add(scheduleNextRun) -- dedicated / co-op host
Events.EveryHours.Add(scheduleNextRun)      -- picks up the end of each monthly run
