local addonName = ...
local bridgePayloadPrefix = "[GB]"
local bridgeAddonPrefix = "GuildBridge"

local mainFrame
local scrollFrame
local inputBox
local tabButtons = {}
local muteCheckbox

local eventFrame = CreateFrame("Frame")

-- Current filter: nil = All, or guild-realm key
local currentFilter = nil
-- Current page: "chat" or "status"
local currentPage = "chat"
-- Store messages for filtering
local messageHistory = {}
-- Track unique guild+realm combinations we've seen
local knownGuilds = {}

-- Message deduplication
local recentMessages = {}  -- Hash -> timestamp
local MESSAGE_DEDUPE_WINDOW = 10  -- seconds

-- Track online friends
local onlineFriends = {}

-- Handshake tracking: gameAccountID -> { guildName, realmName, guildHomeRealm, lastSeen }
local connectedBridgeUsers = {}

-- Anchor character name used to identify guild home realm
-- Create a character with this name in each guild on the guild's home server
local ANCHOR_CHARACTER_NAME = "Guildbridge"

-- Get the guild's home realm by finding the anchor character
local function getGuildHomeRealm()
    if not IsInGuild() then return nil end

    local numMembers = GetNumGuildMembers()
    if not numMembers or numMembers == 0 then return nil end

    -- Iterate through guild roster to find the anchor character
    for i = 1, numMembers do
        local name = GetGuildRosterInfo(i)
        if name then
            local charName, charRealm = strsplit("-", name)
            if charName == ANCHOR_CHARACTER_NAME then
                -- Anchor character found - use their realm
                if charRealm and charRealm ~= "" then
                    return charRealm
                else
                    -- No realm suffix means they're on our realm
                    return GetRealmName()
                end
            end
        end
    end

    -- Anchor character not found
    return nil
end

local guildShortNames = {
    ["MAKE ELWYNN GREAT AGAIN"] = "MEGA",
    ["MAKE DUROTAR GREAT AGAIN"] = "MDGA",
    ["Bestiez"] = "Bestiez",
}

-- Only relay messages from these guilds
local allowedGuilds = {
    ["MAKE ELWYNN GREAT AGAIN"] = true,
    ["MAKE DUROTAR GREAT AGAIN"] = true,
    ["Bestiez"] = true,
}

local function ensureSavedVariables()
    if not GuildBridgeDB then
        GuildBridgeDB = {}
    end
    if GuildBridgeDB.bridgeEnabled == nil then
        GuildBridgeDB.bridgeEnabled = true
    end
    if GuildBridgeDB.muteSend == nil then
        GuildBridgeDB.muteSend = false
    end
    if GuildBridgeDB.filterNativeChat == nil then
        GuildBridgeDB.filterNativeChat = false
    end
    if GuildBridgeDB.knownGuilds == nil then
        GuildBridgeDB.knownGuilds = {}
    end
    knownGuilds = GuildBridgeDB.knownGuilds
end

-- Generate a hash for message deduplication
local function makeMessageHash(guildName, originName, originRealm, messageText)
    return guildName .. "|" .. originName .. "|" .. originRealm .. "|" .. messageText
end

-- Check if message is a duplicate (seen recently)
local function isDuplicateMessage(hash)
    local now = GetTime()
    -- Clean old entries
    for h, timestamp in pairs(recentMessages) do
        if now - timestamp > MESSAGE_DEDUPE_WINDOW then
            recentMessages[h] = nil
        end
    end
    -- Check if this hash exists
    if recentMessages[hash] then
        return true
    end
    -- Record this message
    recentMessages[hash] = now
    return false
end

-- Find all online WoW friends
local function findOnlineWoWFriends()
    local friends = {}

    local numFriends = BNGetNumFriends()
    if not numFriends or numFriends == 0 then
        return friends
    end

    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            local numGames = C_BattleNet.GetFriendNumGameAccounts(i)
            if numGames and numGames > 0 then
                for j = 1, numGames do
                    local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                    if gameInfo and gameInfo.isOnline and gameInfo.clientProgram == "WoW" then
                        table.insert(friends, {
                            gameAccountID = gameInfo.gameAccountID,
                            characterName = gameInfo.characterName,
                            realmName = gameInfo.realmName,
                            battleTag = accountInfo.battleTag,
                        })
                    end
                end
            end
        end
    end

    return friends
end

-- Forward declarations
local updateConnectionIndicators
local refreshMessages
local recordGuildActivity
local sendHandshake

-- Actually send the handshake payload
local function doSendHandshake(handshakeType, targetGameAccountID)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not allowedGuilds[myGuildName] then
        return
    end

    local myRealm = GetRealmName()
    local guildHomeRealm = getGuildHomeRealm()

    -- If we still don't have a guild home realm, don't send - wait for roster
    if not guildHomeRealm then
        return
    end

    -- Format: [GBHS]TYPE|guildName|playerRealm|guildHomeRealm
    local payload = "[GBHS]" .. handshakeType .. "|" .. myGuildName .. "|" .. myRealm .. "|" .. guildHomeRealm

    if targetGameAccountID then
        -- Send to specific friend (PONG response)
        pcall(BNSendGameData, targetGameAccountID, bridgeAddonPrefix, payload)
    else
        -- Broadcast to all online friends (HELLO)
        local friends = findOnlineWoWFriends()
        for _, friend in ipairs(friends) do
            pcall(BNSendGameData, friend.gameAccountID, bridgeAddonPrefix, payload)
        end
    end
end

-- Send a handshake message to all online friends
-- type: "HELLO" (announce), "PONG" (response to HELLO)
local function sendHandshakeMessage(handshakeType, targetGameAccountID)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not allowedGuilds[myGuildName] then
        return
    end

    -- Request fresh guild roster data first
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    else
        GuildRoster()
    end

    -- Small delay to allow roster data to load, then send
    C_Timer.After(0.5, function()
        doSendHandshake(handshakeType, targetGameAccountID)
    end)
end

-- Handle incoming handshake messages
local function handleHandshakeMessage(message, senderGameAccountID)
    if not message or message:sub(1, 6) ~= "[GBHS]" then
        return false
    end

    local data = message:sub(7)
    -- New format: TYPE|guildName|playerRealm|guildHomeRealm
    local handshakeType, guildName, realmName, guildHomeRealm = data:match("([^|]+)|([^|]+)|([^|]*)|?(.*)$")

    -- Fallback for old format without guildHomeRealm
    if not guildHomeRealm or guildHomeRealm == "" then
        guildHomeRealm = realmName
    end

    if not handshakeType or not guildName then
        return true -- It was a handshake message, just malformed
    end

    -- Only track if it's an allowed guild
    if not allowedGuilds[guildName] then
        return true
    end

    -- Record this bridge user with guild home realm
    connectedBridgeUsers[senderGameAccountID] = {
        guildName = guildName,
        realmName = realmName,
        guildHomeRealm = guildHomeRealm,
        lastSeen = GetTime(),
    }

    -- Update indicators
    if updateConnectionIndicators then
        updateConnectionIndicators()
    end

    -- If they sent HELLO, respond with PONG
    if handshakeType == "HELLO" then
        sendHandshakeMessage("PONG", senderGameAccountID)
    end

    return true
end

-- Check if any connected bridge user is in a specific guild
local function hasConnectedUserInGuild(filterKey)
    local now = GetTime()
    for gameAccountID, info in pairs(connectedBridgeUsers) do
        -- Consider stale after 5 minutes
        if now - info.lastSeen < 300 then
            -- filterKey is guildName-guildHomeRealm
            local theirFilterKey = info.guildName
            if info.guildHomeRealm and info.guildHomeRealm ~= "" then
                theirFilterKey = info.guildName .. "-" .. info.guildHomeRealm
            end
            if theirFilterKey == filterKey then
                return true
            end
        end
    end
    return false
end

-- Throttle handshake sending
local lastHandshakeTime = 0
local HANDSHAKE_THROTTLE = 10  -- Minimum seconds between handshakes

-- Send handshake to all friends (called on login and periodically)
sendHandshake = function()
    local now = GetTime()
    if now - lastHandshakeTime < HANDSHAKE_THROTTLE then
        return  -- Throttled
    end
    lastHandshakeTime = now
    sendHandshakeMessage("HELLO")
end

-- Update list of online friends
local function updateOnlineFriends()
    onlineFriends = findOnlineWoWFriends()

    -- Update connection indicators on tabs
    if updateConnectionIndicators then
        updateConnectionIndicators()
    end

    -- Refresh status page if it's currently displayed
    if currentPage == "status" then
        refreshMessages()
    end
end


-- Create a filter key from guild name and realm
local function makeFilterKey(guildName, realmName)
    if not guildName then return nil end
    if realmName and realmName ~= "" then
        return guildName .. "-" .. realmName
    end
    return guildName
end

-- Forward declarations
local registerGuild
local rebuildTabs

refreshMessages = function()
    if not scrollFrame then return end
    scrollFrame:Clear()

    -- If Status page is selected, show connection pairs
    if currentPage == "status" then
        scrollFrame:AddMessage("|cff88ffffBridge Connections:|r")
        scrollFrame:AddMessage("")

        -- Get my info
        local myName = UnitName("player")
        local myGuildName = GetGuildInfo("player")
        local myGuildHomeRealm = getGuildHomeRealm() or GetRealmName()
        local myShort = guildShortNames[myGuildName] or myGuildName or "No Guild"

        -- Collect connection pairs
        local connections = {}
        local now = GetTime()
        for gameAccountID, info in pairs(connectedBridgeUsers) do
            if now - info.lastSeen < 300 then
                -- Find character name from onlineFriends
                local charName = "Unknown"
                local charRealm = info.realmName or ""
                for _, friend in ipairs(onlineFriends) do
                    if friend.gameAccountID == gameAccountID then
                        charName = friend.characterName or "Unknown"
                        charRealm = friend.realmName or info.realmName or ""
                        break
                    end
                end
                local theirShort = guildShortNames[info.guildName] or info.guildName or ""
                table.insert(connections, {
                    charName = charName,
                    charRealm = charRealm,
                    guildName = info.guildName,
                    guildShort = theirShort,
                    guildHomeRealm = info.guildHomeRealm or info.realmName or "",
                })
            end
        end

        if #connections == 0 then
            scrollFrame:AddMessage("|cffff8888No bridge connections active.|r")
        else
            for _, conn in ipairs(connections) do
                local myRealmSuffix = myGuildHomeRealm and myGuildHomeRealm ~= "" and ("-" .. myGuildHomeRealm) or ""
                local theirRealmSuffix = conn.guildHomeRealm ~= "" and ("-" .. conn.guildHomeRealm) or ""

                -- Format: <MyGuild-GuildHomeRealm> MyChar  <-->  TheirChar <TheirGuild-GuildHomeRealm>
                local leftSide = "|cffffd700<" .. myShort .. myRealmSuffix .. ">|r |cff00ff00" .. myName .. "|r"
                local rightSide = "|cff00ff00" .. conn.charName .. "|r |cffffd700<" .. conn.guildShort .. theirRealmSuffix .. ">|r"

                scrollFrame:AddMessage(leftSide .. "  |cff888888<-->|r  " .. rightSide)
            end
        end
        return
    end

    -- Normal message display
    for _, msg in ipairs(messageHistory) do
        if currentFilter == nil or msg.filterKey == currentFilter then
            scrollFrame:AddMessage(msg.formatted)
        end
    end
end

local function addBridgeMessage(senderName, guildName, factionTag, messageText, senderRealm, guildHomeRealm)
    -- Use guildName-guildHomeRealm as the unique key to distinguish same-name guilds
    local filterKey = registerGuild(guildName, guildHomeRealm)

    local short = guildShortNames[guildName] or guildName or ""
    -- Get the manually set realm for display, or use guildHomeRealm
    local displayRealm = nil
    if knownGuilds[filterKey] and knownGuilds[filterKey].manualRealm then
        displayRealm = knownGuilds[filterKey].realmName
    elseif guildHomeRealm and guildHomeRealm ~= "" then
        displayRealm = guildHomeRealm
    end
    local realmSuffix = ""
    if displayRealm and displayRealm ~= "" then
        realmSuffix = "-" .. displayRealm
    end
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""

    local fullName = senderName
    if senderRealm and senderRealm ~= "" then
        fullName = senderName .. "-" .. senderRealm
    end
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff00ff00[" .. senderName .. "]|r|h"

    local formattedMessage = guildTag .. senderLink .. ": " .. messageText

    -- Record activity for connection indicator
    if recordGuildActivity then
        recordGuildActivity(filterKey)
    end

    table.insert(messageHistory, {
        guildName = guildName,
        guildHomeRealm = guildHomeRealm,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #messageHistory > 500 then
        table.remove(messageHistory, 1)
    end

    if scrollFrame and currentPage == "chat" and (currentFilter == nil or filterKey == currentFilter) then
        scrollFrame:AddMessage(formattedMessage)
    end

    -- Only show in native chat if filter is off, or if message matches the current filter
    if not GuildBridgeDB.filterNativeChat or currentFilter == nil or filterKey == currentFilter then
        DEFAULT_CHAT_FRAME:AddMessage(formattedMessage, 0.25, 1.0, 0.25)
    end
end

local function sendBridgePayload(originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm)
    if not messageText or messageText == "" then
        return
    end

    -- Get current online friends
    if #onlineFriends == 0 then
        onlineFriends = findOnlineWoWFriends()
    end

    if #onlineFriends == 0 then
        return
    end

    sourceType = sourceType or "U"

    local guildName = overrideGuild or GetGuildInfo("player")
    local guildRealm = overrideGuildRealm or GetRealmName()
    local guildHomeRealm = overrideGuildHomeRealm or getGuildHomeRealm() or guildRealm
    local factionGroup = select(1, UnitFactionGroup("player")) or "Unknown"

    -- Generate message ID for deduplication if not provided
    if not messageId or messageId == "" then
        messageId = guildHomeRealm .. "-" .. originName .. "-" .. GetTime()
    end

    -- Payload format: [GB]guildName|guildRealm|faction|originName|originRealm|sourceType|targetFilter|messageId|guildHomeRealm|message
    local payload = bridgePayloadPrefix
        .. (guildName or "")
        .. "|"
        .. (guildRealm or "")
        .. "|"
        .. factionGroup
        .. "|"
        .. originName
        .. "|"
        .. (originRealm or "")
        .. "|"
        .. sourceType
        .. "|"
        .. (targetFilter or "")
        .. "|"
        .. messageId
        .. "|"
        .. (guildHomeRealm or "")
        .. "|"
        .. messageText

    -- Send to all online WoW friends
    for _, friend in ipairs(onlineFriends) do
        local ok, err = pcall(BNSendGameData, friend.gameAccountID, bridgeAddonPrefix, payload)
        if not ok then
            print("GuildBridge: error sending to", friend.characterName or "unknown", ":", err)
        end
    end
end

local function sendFromUI(messageText)
    if not messageText or messageText == "" then
        return
    end

    local targetFilter = currentFilter

    local originName, originRealm = UnitName("player")
    if not originRealm or originRealm == "" then
        originRealm = GetRealmName()
    end
    local playerGuildName = GetGuildInfo("player")
    local playerGuildHomeRealm = getGuildHomeRealm() or originRealm

    -- Use guildName-guildHomeRealm as filter key
    local filterKey = registerGuild(playerGuildName, playerGuildHomeRealm)

    local short = guildShortNames[playerGuildName] or playerGuildName or ""
    -- Get the manually set realm for display, or use guildHomeRealm
    local displayRealm = nil
    if knownGuilds[filterKey] and knownGuilds[filterKey].manualRealm then
        displayRealm = knownGuilds[filterKey].realmName
    else
        displayRealm = playerGuildHomeRealm
    end
    local realmSuffix = displayRealm and displayRealm ~= "" and ("-" .. displayRealm) or ""
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""
    local fullName = originName .. "-" .. originRealm
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff00ff00[" .. originName .. "]|r|h"
    local formattedMessage = guildTag .. senderLink .. ": " .. messageText

    table.insert(messageHistory, {
        guildName = playerGuildName,
        guildHomeRealm = playerGuildHomeRealm,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #messageHistory > 500 then
        table.remove(messageHistory, 1)
    end

    if scrollFrame and (currentFilter == nil or filterKey == currentFilter) then
        scrollFrame:AddMessage(formattedMessage)
    end

    -- Record hash so we don't display it again when it comes back
    local hash = makeMessageHash(playerGuildName or "", originName, originRealm, messageText)
    isDuplicateMessage(hash)  -- This records the hash

    sendBridgePayload(originName, originRealm, messageText, "U", targetFilter)
end


local function handleGuildChatMessage(text, sender)
    if not IsInGuild() then
        return
    end
    if not text or text == "" then
        return
    end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not allowedGuilds[myGuildName] then
        return
    end

    local originName, originRealm = sender:match("([^%-]+)%-?(.*)")
    originName = originName or sender
    if not originRealm or originRealm == "" then
        originRealm = GetRealmName()
    end

    -- Get guild home realm (GM's realm) for proper identification
    local myGuildHomeRealm = getGuildHomeRealm() or originRealm

    -- Use guildName-guildHomeRealm as filter key
    local filterKey = registerGuild(myGuildName, myGuildHomeRealm)

    local short = guildShortNames[myGuildName] or myGuildName or ""
    -- Get the manually set realm for display, or use guildHomeRealm
    local displayRealm = nil
    if knownGuilds[filterKey] and knownGuilds[filterKey].manualRealm then
        displayRealm = knownGuilds[filterKey].realmName
    else
        displayRealm = myGuildHomeRealm
    end
    local realmSuffix = displayRealm and displayRealm ~= "" and ("-" .. displayRealm) or ""
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""
    local fullName = originName .. "-" .. originRealm
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff00ff00[" .. originName .. "]|r|h"
    local formattedMessage = guildTag .. senderLink .. ": " .. text

    table.insert(messageHistory, {
        guildName = myGuildName,
        guildHomeRealm = myGuildHomeRealm,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #messageHistory > 500 then
        table.remove(messageHistory, 1)
    end

    if scrollFrame and (currentFilter == nil or filterKey == currentFilter) then
        scrollFrame:AddMessage(formattedMessage)
    end

    if not GuildBridgeDB.bridgeEnabled then
        return
    end

    if GuildBridgeDB.muteSend then
        local myName = UnitName("player")
        if originName == myName then
            return
        end
    end

    -- Check for duplicate before relaying
    local hash = makeMessageHash(myGuildName, originName, originRealm, text)
    if isDuplicateMessage(hash) then
        return
    end

    sendBridgePayload(originName, originRealm, text, "G")
end

local function handleBNAddonMessage(prefix, message, senderID)
    if prefix ~= bridgeAddonPrefix then
        return
    end

    -- Check for handshake messages first
    if handleHandshakeMessage(message, senderID) then
        return
    end

    local text = message
    if not text or text:sub(1, #bridgePayloadPrefix) ~= bridgePayloadPrefix then
        return
    end

    local payload = text:sub(#bridgePayloadPrefix + 1)
    local guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, messagePart

    -- New format with guildHomeRealm: guildName|guildRealm|faction|originName|originRealm|sourceType|targetFilter|messageId|guildHomeRealm|message
    guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

    -- Fallback to old format without guildHomeRealm
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildHomeRealmPart = nil
    end

    -- Fallback for even older format
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        messageIdPart = nil
        guildHomeRealmPart = nil
    end

    if not messagePart then
        guildPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildRealmPart = originRealmPart
        messageIdPart = nil
        guildHomeRealmPart = nil
    end

    if not messagePart or not originPart or not sourcePart then
        return
    end

    if guildPart == "" then guildPart = nil end
    if guildRealmPart == "" then guildRealmPart = nil end
    if originRealmPart == "" then originRealmPart = nil end
    if targetPart == "" then targetPart = nil end
    if messageIdPart == "" then messageIdPart = nil end
    if guildHomeRealmPart == "" then guildHomeRealmPart = nil end

    -- Fallback: use guild realm as home realm if not provided
    if not guildHomeRealmPart then
        guildHomeRealmPart = guildRealmPart
    end

    -- Only accept messages from allowed guilds
    if guildPart and not allowedGuilds[guildPart] then
        return
    end

    -- Check for duplicate message using hash (include guildHomeRealm for uniqueness)
    local hash = makeMessageHash(guildPart or "", originPart, originRealmPart or "", messagePart)
    if isDuplicateMessage(hash) then
        return
    end

    -- If message has a target filter, only process if we match
    if targetPart and targetPart ~= "" then
        local myGuildName = GetGuildInfo("player")
        local myGuildHomeRealm = getGuildHomeRealm() or GetRealmName()
        local myFilterKey = myGuildName
        if myGuildHomeRealm and myGuildHomeRealm ~= "" then
            myFilterKey = myGuildName .. "-" .. myGuildHomeRealm
        end
        if myFilterKey ~= targetPart then
            return
        end
    end

    -- Display the message (pass guildHomeRealm for proper filtering)
    addBridgeMessage(originPart, guildPart, factionPart, messagePart, guildRealmPart, guildHomeRealmPart)

    -- Re-relay to other friends (mesh network) - but NOT if this came from guild chat
    -- Only re-relay if sourceType is not "G" (guild originated)
    if GuildBridgeDB.bridgeEnabled and sourcePart ~= "G" then
        sendBridgePayload(originPart, originRealmPart, messagePart, sourcePart, targetPart, messageIdPart, guildPart, guildRealmPart, guildHomeRealmPart)
    end
end

local function updateTabHighlights()
    for _, tab in pairs(tabButtons) do
        if tab.filterValue == currentFilter then
            tab.guildText:SetFontObject(GameFontHighlight)
            tab.guildText:SetTextColor(1, 0.82, 0)
            tab.bg:SetColorTexture(0.2, 0.2, 0.3, 1)
            tab.border:SetColorTexture(0.8, 0.6, 0.2, 1)
            if tab.realmText then
                tab.realmText:SetTextColor(0.7, 0.7, 0.7)
            end
            tab.selected = true
        else
            tab.guildText:SetFontObject(GameFontNormal)
            tab.guildText:SetTextColor(0.8, 0.8, 0.8)
            tab.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            tab.border:SetColorTexture(0.3, 0.3, 0.3, 1)
            if tab.realmText then
                tab.realmText:SetTextColor(0.5, 0.5, 0.5)
            end
            tab.selected = false
        end
    end
end

-- Update connection status indicators - just show if we have online friends
-- Track last message time per guild filterKey
local lastGuildActivity = {}

recordGuildActivity = function(filterKey)
    if filterKey then
        lastGuildActivity[filterKey] = GetTime()
        updateConnectionIndicators()
    end
end

local function isGuildActive(filterKey)
    if not filterKey then return false end
    local lastTime = lastGuildActivity[filterKey]
    if not lastTime then return false end
    -- Consider active if we've seen activity in the last 5 minutes
    return (GetTime() - lastTime) < 300
end

updateConnectionIndicators = function()
    for _, tab in pairs(tabButtons) do
        if tab.statusDot and tab.guildName then
            if hasConnectedUserInGuild(tab.filterValue) then
                -- Has a bridge user connected in this guild - green
                tab.statusDot:SetColorTexture(0.3, 0.8, 0.3, 1)
            else
                -- No confirmed bridge user in this guild - red
                tab.statusDot:SetColorTexture(0.8, 0.3, 0.3, 1)
            end
        end
    end
end

local function forgetGuild(filterKey)
    if not filterKey then return end
    knownGuilds[filterKey] = nil
    GuildBridgeDB.knownGuilds = knownGuilds
    if currentFilter == filterKey then
        currentFilter = nil
    end
    rebuildTabs()
    refreshMessages()
end

local contextMenu
local forgetButton
local setRealmButton
local realmInputDialog

local function setGuildRealm(guildName, newRealm)
    -- Find and update the guild entry
    for filterKey, info in pairs(knownGuilds) do
        if info.guildName == guildName then
            -- Update the realm
            info.realmName = newRealm
            info.manualRealm = true  -- Mark as manually set
            GuildBridgeDB.knownGuilds = knownGuilds
            rebuildTabs()
            return
        end
    end
end

local function showRealmInputDialog(guildName)
    if not realmInputDialog then
        realmInputDialog = CreateFrame("Frame", "GuildBridgeRealmDialog", UIParent, "BackdropTemplate")
        realmInputDialog:SetSize(220, 90)
        realmInputDialog:SetPoint("CENTER")
        realmInputDialog:SetFrameStrata("DIALOG")
        realmInputDialog:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        realmInputDialog:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        realmInputDialog:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        realmInputDialog:EnableMouse(true)
        realmInputDialog:SetMovable(true)
        realmInputDialog:RegisterForDrag("LeftButton")
        realmInputDialog:SetScript("OnDragStart", realmInputDialog.StartMoving)
        realmInputDialog:SetScript("OnDragStop", realmInputDialog.StopMovingOrSizing)

        realmInputDialog.title = realmInputDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        realmInputDialog.title:SetPoint("TOP", 0, -10)
        realmInputDialog.title:SetText("Set Realm")

        realmInputDialog.editBox = CreateFrame("EditBox", nil, realmInputDialog, "InputBoxTemplate")
        realmInputDialog.editBox:SetSize(180, 20)
        realmInputDialog.editBox:SetPoint("TOP", realmInputDialog.title, "BOTTOM", 0, -10)
        realmInputDialog.editBox:SetAutoFocus(true)

        realmInputDialog.okButton = CreateFrame("Button", nil, realmInputDialog, "UIPanelButtonTemplate")
        realmInputDialog.okButton:SetSize(60, 22)
        realmInputDialog.okButton:SetPoint("BOTTOMRIGHT", realmInputDialog, "BOTTOM", -5, 10)
        realmInputDialog.okButton:SetText("OK")

        realmInputDialog.cancelButton = CreateFrame("Button", nil, realmInputDialog, "UIPanelButtonTemplate")
        realmInputDialog.cancelButton:SetSize(60, 22)
        realmInputDialog.cancelButton:SetPoint("BOTTOMLEFT", realmInputDialog, "BOTTOM", 5, 10)
        realmInputDialog.cancelButton:SetText("Cancel")
        realmInputDialog.cancelButton:SetScript("OnClick", function()
            realmInputDialog:Hide()
        end)

        realmInputDialog.editBox:SetScript("OnEscapePressed", function()
            realmInputDialog:Hide()
        end)

        realmInputDialog:Hide()
    end

    realmInputDialog.title:SetText("Set Realm for " .. guildName)
    realmInputDialog.editBox:SetText("")

    realmInputDialog.editBox:SetScript("OnEnterPressed", function(self)
        local realm = self:GetText()
        if realm and realm ~= "" then
            setGuildRealm(realmInputDialog.guildName, realm)
        end
        realmInputDialog:Hide()
    end)

    realmInputDialog.okButton:SetScript("OnClick", function()
        local realm = realmInputDialog.editBox:GetText()
        if realm and realm ~= "" then
            setGuildRealm(realmInputDialog.guildName, realm)
        end
        realmInputDialog:Hide()
    end)

    realmInputDialog.guildName = guildName
    realmInputDialog:Show()
    realmInputDialog.editBox:SetFocus()
end

local function ensureContextMenu()
    if contextMenu then return end

    contextMenu = CreateFrame("Frame", "GuildBridgeContextMenu", UIParent, "BackdropTemplate")
    contextMenu:SetSize(120, 72)
    contextMenu:SetFrameStrata("DIALOG")
    contextMenu:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    contextMenu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    contextMenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    contextMenu:Hide()

    setRealmButton = CreateFrame("Button", nil, contextMenu)
    setRealmButton:SetSize(110, 20)
    setRealmButton:SetPoint("TOP", contextMenu, "TOP", 0, -8)
    setRealmButton.text = setRealmButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    setRealmButton.text:SetPoint("CENTER")
    setRealmButton.text:SetText("Set Realm")
    setRealmButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    setRealmButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 0.82, 0)
    end)
    setRealmButton.text:SetTextColor(1, 0.82, 0)

    forgetButton = CreateFrame("Button", nil, contextMenu)
    forgetButton:SetSize(110, 20)
    forgetButton:SetPoint("TOP", setRealmButton, "BOTTOM", 0, -2)
    forgetButton.text = forgetButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    forgetButton.text:SetPoint("CENTER")
    forgetButton.text:SetText("Forget")
    forgetButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    forgetButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 0.82, 0)
    end)
    forgetButton.text:SetTextColor(1, 0.82, 0)

    local cancelButton = CreateFrame("Button", nil, contextMenu)
    cancelButton:SetSize(110, 20)
    cancelButton:SetPoint("TOP", forgetButton, "BOTTOM", 0, -2)
    cancelButton.text = cancelButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelButton.text:SetPoint("CENTER")
    cancelButton.text:SetText("Cancel")
    cancelButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    cancelButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.7, 0.7, 0.7)
    end)
    cancelButton.text:SetTextColor(0.7, 0.7, 0.7)
    cancelButton:SetScript("OnClick", function()
        contextMenu:Hide()
    end)

    contextMenu:SetScript("OnShow", function(self)
        self:SetPropagateKeyboardInput(true)
    end)
    contextMenu:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        end
    end)
    contextMenu:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            if not MouseIsOver(self) and not (realmInputDialog and realmInputDialog:IsShown()) then
                self:Hide()
            end
        end
    end)
    contextMenu:RegisterEvent("GLOBAL_MOUSE_DOWN")
end

local function showContextMenu(filterKey, guildLabel, guildName)
    ensureContextMenu()
    setRealmButton:SetScript("OnClick", function()
        contextMenu:Hide()
        showRealmInputDialog(guildName)
    end)
    forgetButton.text:SetText("Forget " .. guildLabel)
    forgetButton:SetScript("OnClick", function()
        forgetGuild(filterKey)
        contextMenu:Hide()
    end)
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    contextMenu:ClearAllPoints()
    contextMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    contextMenu:Show()
end

local function createTab(parent, guildLabel, realmLabel, filterValue, xOffset, yOffset, guildName, tabWidth)
    tabWidth = tabWidth or 72
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetSize(tabWidth, 34)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    tab:SetFrameLevel(parent:GetFrameLevel() + 10)
    tab:EnableMouse(true)
    tab.filterValue = filterValue
    tab.guildName = guildName

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    tab.bg = bg

    local border = tab:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.4, 0.4, 0.4, 1)
    tab.border = border

    if guildName then
        tab.statusDot = tab:CreateTexture(nil, "OVERLAY")
        tab.statusDot:SetSize(8, 8)
        tab.statusDot:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -3, -3)
    end

    tab.guildText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if realmLabel and realmLabel ~= "" then
        tab.guildText:SetPoint("TOP", tab, "TOP", 0, -5)
    else
        tab.guildText:SetPoint("CENTER", tab, "CENTER", 0, 0)
    end
    tab.guildText:SetText(guildLabel)

    if realmLabel and realmLabel ~= "" then
        tab.realmText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
        tab.realmText:SetPoint("TOP", tab.guildText, "BOTTOM", 0, -2)
        tab.realmText:SetText(realmLabel)
        tab.realmText:SetTextColor(0.5, 0.5, 0.5)
    end

    tab:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" and filterValue and guildName then
            showContextMenu(filterValue, guildLabel, guildName)
        elseif button == "LeftButton" then
            currentFilter = filterValue
            updateTabHighlights()
            refreshMessages()
        end
    end)

    tab:SetScript("OnEnter", function(self)
        if not self.selected then
            self.guildText:SetTextColor(1, 1, 1)
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
            self.border:SetColorTexture(0.5, 0.5, 0.5, 1)
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if not self.selected then
            self.guildText:SetTextColor(0.8, 0.8, 0.8)
            self.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
            self.border:SetColorTexture(0.3, 0.3, 0.3, 1)
        end
    end)

    return tab
end

local pageTabs = {}
local updatePageVisibility  -- Forward declaration

-- Create a styled page tab
local function createPageTab(parent, label, tabIndex, pageName)
    local tab = CreateFrame("Button", "GuildBridgePageTab" .. tabIndex, parent)
    tab:SetSize(60, 24)
    tab:SetID(tabIndex)
    tab.pageName = pageName

    -- Background
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    -- Border
    tab.border = tab:CreateTexture(nil, "BORDER")
    tab.border:SetPoint("TOPLEFT", -1, 1)
    tab.border:SetPoint("BOTTOMRIGHT", 1, -1)
    tab.border:SetColorTexture(0.4, 0.4, 0.4, 1)

    -- Text
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER")
    tab.text:SetText(label)

    tab:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        currentPage = self.pageName
        updatePageVisibility()
    end)

    tab:SetScript("OnEnter", function(self)
        if currentPage ~= self.pageName then
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
            self.text:SetTextColor(1, 1, 1)
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if currentPage ~= self.pageName then
            self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
            self.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end)

    return tab
end

local function updatePageTabSelection()
    for i, tab in ipairs(pageTabs) do
        if tab.pageName == currentPage then
            -- Selected tab
            tab.bg:SetColorTexture(0.2, 0.2, 0.3, 1)
            tab.border:SetColorTexture(0.8, 0.6, 0.2, 1)
            tab.text:SetTextColor(1, 0.82, 0)
        else
            -- Unselected tab
            tab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
            tab.border:SetColorTexture(0.4, 0.4, 0.4, 1)
            tab.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end
end

local function createPageTabs()
    if not mainFrame then return end

    -- Clear existing page tabs
    for _, tab in pairs(pageTabs) do
        tab:Hide()
        tab:SetParent(nil)
    end
    pageTabs = {}

    -- Create Chat tab at top left (below title bar)
    pageTabs[1] = createPageTab(mainFrame, "Chat", 1, "chat")
    pageTabs[1]:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -24)

    -- Create Status tab next to Chat
    pageTabs[2] = createPageTab(mainFrame, "Status", 2, "status")
    pageTabs[2]:SetPoint("LEFT", pageTabs[1], "RIGHT", 4, 0)

    updatePageTabSelection()
end

updatePageVisibility = function()
    if not mainFrame then return end

    -- Hide/show guild filter tabs based on current page
    for key, tab in pairs(tabButtons) do
        if key:match("^guild") or key == "all" then
            if currentPage == "chat" then
                tab:Show()
            else
                tab:Hide()
            end
        end
    end

    -- Update page tab selection (native WoW style)
    updatePageTabSelection()

    -- Adjust scroll frame position
    if scrollFrame then
        local pageTabHeight = 28  -- Height of page tabs + spacing
        if currentPage == "chat" then
            -- Calculate guild tab rows
            local tabWidth = 72
            local tabSpacing = 4
            local rowHeight = 38
            local maxWidth = mainFrame:GetWidth() - 16
            local guildCount = 1  -- Start with 1 for "All" tab
            local myGuildName = GetGuildInfo("player")
            for filterKey, info in pairs(knownGuilds) do
                if info.guildName ~= myGuildName then
                    guildCount = guildCount + 1
                end
            end
            local tabsPerRow = math.floor(maxWidth / (tabWidth + tabSpacing))
            local numRows = math.ceil(guildCount / tabsPerRow)
            if numRows < 1 then numRows = 1 end
            -- Page tabs + guild filter rows
            local scrollTopOffset = 24 + pageTabHeight + (numRows * rowHeight)
            scrollFrame:SetPoint("TOPLEFT", 10, -scrollTopOffset)
        else
            -- Status page - just page tabs, no guild filter tabs
            local scrollTopOffset = 24 + pageTabHeight
            scrollFrame:SetPoint("TOPLEFT", 10, -scrollTopOffset)
        end
    end

    refreshMessages()
end

rebuildTabs = function()
    if not mainFrame then return end

    for key, tab in pairs(tabButtons) do
        tab:Hide()
        tab:SetParent(nil)
    end
    tabButtons = {}

    local tabSpacing = 4
    local tabWidth = 72
    local rowHeight = 38
    local pageTabHeight = 28
    local topRowY = -(24 + pageTabHeight)  -- Below title bar and page tabs

    -- Guild filter tabs (only visible on chat page)
    local myGuildName = GetGuildInfo("player")
    local xOffset = 8
    local yOffset = topRowY
    local maxWidth = mainFrame:GetWidth() - 16
    local tabIndex = 1

    -- "All" tab for chat page
    tabButtons.all = createTab(mainFrame, "All", nil, nil, xOffset, yOffset, nil, tabWidth)
    xOffset = xOffset + tabWidth + tabSpacing

    for filterKey, info in pairs(knownGuilds) do
        if info.guildName ~= myGuildName then
            -- Check if we need to wrap to next row
            if xOffset + tabWidth > maxWidth then
                xOffset = 8
                yOffset = yOffset - rowHeight
            end

            local short = guildShortNames[info.guildName] or info.guildName or "?"
            -- Show manually set realm if available, otherwise show guild home realm (from GM)
            local realmLabel = nil
            if info.manualRealm and info.realmName then
                realmLabel = info.realmName
            elseif info.guildHomeRealm then
                realmLabel = info.guildHomeRealm
            end
            tabButtons["guild" .. tabIndex] = createTab(mainFrame, short, realmLabel, filterKey, xOffset, yOffset, info.guildName, tabWidth)
            xOffset = xOffset + tabWidth + tabSpacing
            tabIndex = tabIndex + 1
        end
    end

    updatePageVisibility()
    updateTabHighlights()
    updateConnectionIndicators()
end

registerGuild = function(guildName, guildHomeRealm)
    if not guildName then return end
    -- Use guildName-guildHomeRealm as the unique key to distinguish same-name guilds on different server clusters
    local filterKey = guildName
    if guildHomeRealm and guildHomeRealm ~= "" then
        filterKey = guildName .. "-" .. guildHomeRealm
    end
    if not knownGuilds[filterKey] then
        knownGuilds[filterKey] = {
            guildName = guildName,
            guildHomeRealm = guildHomeRealm,  -- GM's realm = guild's home server
            realmName = nil,  -- Display realm, can be set manually by user
            manualRealm = false,
        }
        GuildBridgeDB.knownGuilds = knownGuilds
        rebuildTabs()
    end
    return filterKey
end

local function createBridgeUI()
    if mainFrame then
        return
    end

    mainFrame = CreateFrame("Frame", "GuildBridgeFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(420, 300)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainFrame.title:SetPoint("LEFT", mainFrame.TitleBg, "LEFT", 5, 0)
    mainFrame.title:SetText("Guild Bridge")

    -- Create native WoW-style page tabs at the bottom
    createPageTabs()

    rebuildTabs()

    muteCheckbox = CreateFrame("CheckButton", nil, mainFrame, "UICheckButtonTemplate")
    muteCheckbox:SetSize(24, 24)
    muteCheckbox:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -10, -22)
    muteCheckbox.text = muteCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    muteCheckbox.text:SetPoint("RIGHT", muteCheckbox, "LEFT", -2, 0)
    muteCheckbox.text:SetText("Mute Send")
    muteCheckbox:SetChecked(GuildBridgeDB.muteSend or false)
    muteCheckbox:SetScript("OnClick", function(self)
        GuildBridgeDB.muteSend = self:GetChecked()
    end)

    local filterChatCheckbox = CreateFrame("CheckButton", nil, mainFrame, "UICheckButtonTemplate")
    filterChatCheckbox:SetSize(24, 24)
    filterChatCheckbox:SetPoint("RIGHT", muteCheckbox.text, "LEFT", -10, 0)
    filterChatCheckbox.text = filterChatCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    filterChatCheckbox.text:SetPoint("RIGHT", filterChatCheckbox, "LEFT", -2, 0)
    filterChatCheckbox.text:SetText("Filter Native Chat Also")
    filterChatCheckbox:SetChecked(GuildBridgeDB.filterNativeChat or false)
    filterChatCheckbox:SetScript("OnClick", function(self)
        GuildBridgeDB.filterNativeChat = self:GetChecked()
    end)

    scrollFrame = CreateFrame("ScrollingMessageFrame", nil, mainFrame)
    scrollFrame:SetPoint("TOPLEFT", 10, -90)  -- Default: page tabs (28) + 1 row of guild filter tabs (38) + title bar (24)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 40)
    scrollFrame:SetFontObject(GameFontHighlightSmall)
    scrollFrame:SetJustifyH("LEFT")
    scrollFrame:SetFading(false)
    scrollFrame:SetMaxLines(500)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetHyperlinksEnabled(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        elseif delta < 0 then
            self:ScrollDown()
        end
    end)
    scrollFrame:SetScript("OnHyperlinkClick", function(self, link, text, button)
        SetItemRef(link, text, button)
    end)

    inputBox = CreateFrame("EditBox", nil, mainFrame, "InputBoxTemplate")
    inputBox:SetPoint("BOTTOMLEFT", 10, 10)
    inputBox:SetPoint("BOTTOMRIGHT", -10, 10)
    inputBox:SetHeight(20)
    inputBox:SetAutoFocus(false)
    inputBox:SetFontObject(GameFontHighlightSmall)

    inputBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        sendFromUI(text)
        self:SetText("")
    end)

    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    mainFrame:Hide()
end

local function toggleBridgeFrame()
    if not mainFrame then
        return
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")
eventFrame:RegisterEvent("BN_CHAT_MSG_ADDON")
eventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
eventFrame:RegisterEvent("BN_CONNECTED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            ensureSavedVariables()
            C_ChatInfo.RegisterAddonMessagePrefix(bridgeAddonPrefix)
            createBridgeUI()

            -- Periodic handshake every 2 minutes to keep connection status fresh
            C_Timer.NewTicker(120, function()
                sendHandshake()
                -- Clean up stale entries
                local now = GetTime()
                for gameAccountID, info in pairs(connectedBridgeUsers) do
                    if now - info.lastSeen > 300 then
                        connectedBridgeUsers[gameAccountID] = nil
                    end
                end
                updateConnectionIndicators()
            end)
        end
    elseif event == "PLAYER_LOGIN" or event == "BN_CONNECTED" then
        updateOnlineFriends()
        -- Send initial handshake after a short delay to ensure everything is loaded
        C_Timer.After(3, sendHandshake)
    elseif event == "BN_FRIEND_INFO_CHANGED" then
        local previousFriendIDs = {}
        for _, friend in ipairs(onlineFriends) do
            previousFriendIDs[friend.gameAccountID] = true
        end

        updateOnlineFriends()

        -- Remove connectedBridgeUsers entries for friends who are no longer online
        local currentFriendIDs = {}
        for _, friend in ipairs(onlineFriends) do
            currentFriendIDs[friend.gameAccountID] = true
        end
        for gameAccountID, _ in pairs(connectedBridgeUsers) do
            if not currentFriendIDs[gameAccountID] then
                connectedBridgeUsers[gameAccountID] = nil
            end
        end
        updateConnectionIndicators()

        -- Only send handshake if there's a NEW friend we haven't seen
        for gameAccountID, _ in pairs(currentFriendIDs) do
            if not previousFriendIDs[gameAccountID] and not connectedBridgeUsers[gameAccountID] then
                -- New friend came online, send handshake to just them
                sendHandshakeMessage("HELLO", gameAccountID)
            end
        end
    elseif event == "CHAT_MSG_GUILD" then
        local text, sender = ...
        handleGuildChatMessage(text, sender)
    elseif event == "BN_CHAT_MSG_ADDON" then
        local prefix, message, _, senderID = ...
        handleBNAddonMessage(prefix, message, senderID)
    end
end)

SLASH_GUILDBRIDGE1 = "/gbridge"
SLASH_GUILDBRIDGE2 = "/gb"
SlashCmdList["GUILDBRIDGE"] = function(msg)
    msg = msg or ""
    msg = msg:lower()

    if msg == "" or msg == "show" then
        toggleBridgeFrame()
    elseif msg == "status" then
        ensureSavedVariables()
        print("GuildBridge: Online WoW friends (" .. #onlineFriends .. "):")
        for _, friend in ipairs(onlineFriends) do
            print("  |cff00ff00" .. friend.characterName .. "-" .. (friend.realmName or "") .. "|r")
        end
        if #onlineFriends == 0 then
            print("  No friends online.")
        end
    elseif msg == "reload" or msg == "refresh" then
        ensureSavedVariables()
        updateOnlineFriends()
        print("GuildBridge: Friend list refreshed. " .. #onlineFriends .. " online.")
    else
        print("GuildBridge commands:")
        print("  /gb - Toggle bridge window")
        print("  /gbridge status - Show online friends")
        print("  /gbridge reload - Refresh friend list")
    end
end
