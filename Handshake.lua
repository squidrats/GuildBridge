-- GuildBridge Handshake Module
-- Handles handshake protocol for bridge connection discovery

local addonName, GB = ...

-- Get guild club ID for unique identification
local function getGuildClubId()
    if C_Club and C_Club.GetGuildClubId then
        return C_Club.GetGuildClubId()
    end
    return nil
end

-- Actually send the handshake payload (internal, no throttle)
local function doSendHandshake(handshakeType, targetGameAccountID)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not GB.allowedGuilds[myGuildName] then
        return
    end

    local myRealm = GetRealmName()
    local guildHomeRealm = GB:GetGuildHomeRealm()
    local guildClubId = getGuildClubId()

    -- If we still don't have a guild home realm, don't send - wait for roster
    if not guildHomeRealm then
        return
    end

    -- Format: [GBHS]TYPE|guildName|playerRealm|guildHomeRealm|guildClubId
    local payload = "[GBHS]" .. handshakeType .. "|" .. myGuildName .. "|" .. myRealm .. "|" .. guildHomeRealm .. "|" .. (guildClubId or "")

    if targetGameAccountID then
        -- Send to specific friend (PONG response)
        pcall(BNSendGameData, targetGameAccountID, GB.BRIDGE_ADDON_PREFIX, payload)
    else
        -- Broadcast to all online friends (HELLO)
        local friends = GB:FindOnlineWoWFriends()
        for _, friend in ipairs(friends) do
            pcall(BNSendGameData, friend.gameAccountID, GB.BRIDGE_ADDON_PREFIX, payload)
        end
    end
end

-- Send a handshake message - this is the direct send (no throttle for PONG responses)
-- type: "HELLO" (announce), "PONG" (response to HELLO)
function GB:SendHandshakeMessage(handshakeType, targetGameAccountID)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not self.allowedGuilds[myGuildName] then
        return
    end

    doSendHandshake(handshakeType, targetGameAccountID)
end

-- Look up character name for a gameAccountID from Battle.net friends
local function lookupCharacterName(gameAccountID)
    local numFriends = BNGetNumFriends()
    if not numFriends or numFriends == 0 then
        return nil, nil
    end

    for i = 1, numFriends do
        local numGames = C_BattleNet.GetFriendNumGameAccounts(i)
        if numGames and numGames > 0 then
            for j = 1, numGames do
                local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameInfo and gameInfo.gameAccountID == gameAccountID then
                    return gameInfo.characterName, gameInfo.realmName
                end
            end
        end
    end
    return nil, nil
end

-- Handle incoming handshake messages
function GB:HandleHandshakeMessage(message, senderGameAccountID)
    if not message or message:sub(1, 6) ~= "[GBHS]" then
        return false
    end

    local data = message:sub(7)
    -- New format: TYPE|guildName|playerRealm|guildHomeRealm|guildClubId
    local handshakeType, guildName, realmName, guildHomeRealm, guildClubId = data:match("([^|]+)|([^|]+)|([^|]*)|([^|]*)|?(.*)$")

    -- Fallback for old format without guildHomeRealm
    if not guildHomeRealm or guildHomeRealm == "" then
        guildHomeRealm = realmName
    end

    if not handshakeType or not guildName then
        return true -- It was a handshake message, just malformed
    end

    -- Only track if it's an allowed guild
    if not self.allowedGuilds[guildName] then
        return true
    end

    -- Clean up empty strings
    if guildClubId == "" then guildClubId = nil end

    -- Look up the sender's character name directly from Battle.net API
    local charName, charRealm = lookupCharacterName(senderGameAccountID)

    -- Record this bridge user with guild info and character name
    self.connectedBridgeUsers[senderGameAccountID] = {
        guildName = guildName,
        realmName = realmName,
        guildHomeRealm = guildHomeRealm,
        guildClubId = guildClubId,
        characterName = charName,      -- Store character name directly
        characterRealm = charRealm,    -- Store character realm directly
        lastSeen = GetTime(),
    }

    -- Register guild so it appears in tabs (include clubId for unique identification)
    self:RegisterGuild(guildName, guildHomeRealm, guildClubId)

    -- Update indicators immediately
    self:UpdateConnectionIndicators()

    -- Refresh status page if viewing it
    if self.currentPage == "status" then
        self:RefreshMessages()
    end

    -- If they sent HELLO, respond with PONG immediately
    if handshakeType == "HELLO" then
        self:SendHandshakeMessage("PONG", senderGameAccountID)
    end

    return true
end

-- Send handshake to all friends (called on login and periodically)
-- This is throttled to prevent spam
function GB:SendHandshake()
    local now = GetTime()
    if now - self.lastHandshakeTime < self.HANDSHAKE_THROTTLE then
        return  -- Throttled
    end
    self.lastHandshakeTime = now
    self:SendHandshakeMessage("HELLO")
end

-- Force send handshake without throttle
function GB:ForceSendHandshake()
    self.lastHandshakeTime = 0
    self:SendHandshake()
end

-- Send handshake to a specific friend (used when a new friend comes online)
function GB:SendHandshakeToFriend(gameAccountID)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not self.allowedGuilds[myGuildName] then
        return
    end

    local myRealm = GetRealmName()
    local guildHomeRealm = self:GetGuildHomeRealm()
    local guildClubId = getGuildClubId()

    local payload = "[GBHS]HELLO|" .. myGuildName .. "|" .. myRealm .. "|" .. guildHomeRealm .. "|" .. (guildClubId or "")
    pcall(BNSendGameData, gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
end

-- Update connection status from a received bridge message
-- This keeps connections "alive" even without explicit handshakes
function GB:UpdateConnectionFromMessage(senderGameAccountID, guildName, guildHomeRealm, realmName, guildClubId)
    if not senderGameAccountID or not guildName then
        return
    end

    -- Only track if it's an allowed guild
    if not self.allowedGuilds[guildName] then
        return
    end

    -- Update or create the connection entry
    local existing = self.connectedBridgeUsers[senderGameAccountID]
    if existing then
        -- Update lastSeen and any new info
        existing.lastSeen = GetTime()
        if guildClubId then
            existing.guildClubId = guildClubId
        end
        -- Update character name if we don't have it yet
        if not existing.characterName then
            local charName, charRealm = lookupCharacterName(senderGameAccountID)
            if charName then
                existing.characterName = charName
                existing.characterRealm = charRealm
            end
        end
    else
        -- New connection discovered via message - look up character name
        local charName, charRealm = lookupCharacterName(senderGameAccountID)
        self.connectedBridgeUsers[senderGameAccountID] = {
            guildName = guildName,
            realmName = realmName or guildHomeRealm,
            guildHomeRealm = guildHomeRealm,
            guildClubId = guildClubId,
            characterName = charName,
            characterRealm = charRealm,
            lastSeen = GetTime(),
        }
        -- Register guild so it appears in tabs
        self:RegisterGuild(guildName, guildHomeRealm, guildClubId)
    end

    -- Update indicators
    self:UpdateConnectionIndicators()
end
