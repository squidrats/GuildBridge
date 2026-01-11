-- MNet Handshake Module
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
        -- Send to specific friend (PONG response) - NOW QUEUED to prevent burst
        GB:QueueBNetMessage(targetGameAccountID, GB.BRIDGE_ADDON_PREFIX, payload)
    else
        -- Broadcast handshakes to all online WoW friends
        -- Handshakes are small and infrequent, so we send to everyone
        -- The receiver will only respond if THEY are in an allowed guild
        -- This solves the chicken-and-egg problem of needing guild info before connecting
        local friends = GB:FindOnlineWoWFriends()
        for _, friend in ipairs(friends) do
            GB:QueueBNetMessage(friend.gameAccountID, GB.BRIDGE_ADDON_PREFIX, payload)
        end
    end
end

-- Get guild home realm from club ID (helper for LEAVE processing)
function GB:GetGuildHomeRealmFromClubId(guildClubId)
    -- Check known guilds for matching club ID
    for filterKey, info in pairs(self.knownGuilds) do
        if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
            return info.guildHomeRealm
        end
    end
    -- Check connected users
    for _, info in pairs(self.connectedBridgeUsers) do
        if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
            return info.guildHomeRealm
        end
    end
    for _, info in pairs(self.connectedWhisperAlts) do
        if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
            return info.guildHomeRealm
        end
    end
    return nil
end

-- Send leave notification to confirmed bridge users (when leaving guild or logging out)
function GB:SendLeaveNotification()
    -- Include character name and guild info so receivers can update their rosters
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()

    -- Format: [GBHS]LEAVE|charName|charRealm|guildName|guildClubId
    local payload = "[GBHS]LEAVE|" .. myName .. "|" .. myRealm .. "|" .. (myGuildName or "") .. "|" .. (myGuildClubId or "")

    -- Only need to notify confirmed bridge users - they're the only ones tracking us
    for gameAccountID, _ in pairs(self.connectedBridgeUsers) do
        self:QueueBNetMessage(gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
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

    -- Handle LEAVE message (player logged out or left their guild)
    if data:sub(1, 5) == "LEAVE" then
        -- Parse LEAVE data: LEAVE|charName|charRealm|guildName|guildClubId
        local parts = {strsplit("|", data)}
        local charName = parts[2]
        local charRealm = parts[3]
        local guildName = parts[4]
        local guildClubId = parts[5]

        -- Remove from connected users
        self.connectedBridgeUsers[senderGameAccountID] = nil
        self:UpdateConnectionIndicators()

        -- If we have guild info, remove this character from their guild's roster
        if charName and guildName and guildName ~= "" and guildClubId and guildClubId ~= "" then
            local filterKey = self:MakeFilterKey(guildName, self:GetGuildHomeRealmFromClubId(guildClubId))
            local roster = self.guildRosters[filterKey]
            if roster and roster.members and roster.members[charName] then
                -- Remove the character from the roster
                roster.members[charName] = nil
                roster.version = roster.version + 1
                roster.lastUpdate = GetTime()
                self.guildRosters[filterKey] = roster

                -- Refresh UI to show updated roster
                if self.RefreshRoster then
                    self:RefreshRoster()
                end
            end
        end

        -- Clear rosters for guilds that no longer have connections
        if self.ClearDisconnectedRosters then
            self:ClearDisconnectedRosters()
        end
        if self.currentPage == "status" then
            self:RefreshMessages()
        end
        return true
    end

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

    -- Throttled roster request: Only request if we don't have this guild's roster yet
    -- Uses QueueRosterRequest which throttles at 1 request per 5 seconds to prevent burst
    if guildClubId and self.QueueRosterRequest then
        local filterKey = self:MakeFilterKey(guildName, guildHomeRealm)
        local roster = self.guildRosters[filterKey]

        -- Only request if we don't have this guild's roster yet
        if not roster or not roster.members then
            -- Queue the request (throttled to prevent login burst)
            self:QueueRosterRequest(senderGameAccountID, guildClubId, "bnet")
        end
    end

    -- Party sync removed - now local-only (no network traffic)

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
    -- NOW QUEUED to prevent burst when multiple friends come online
    self:QueueBNetMessage(gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
end

-- ============================================================================
-- WHISPER-BASED HANDSHAKE FOR SAME-ACCOUNT ALTS
-- BNSendGameData only works between different Battle.net accounts.
-- For same-account alts (different WoW licenses on same Battle.net), we use
-- addon whispers via C_ChatInfo.SendAddonMessage with WHISPER channel.
-- ============================================================================

-- Send whisper handshake to registered alts
local function doSendWhisperHandshake(handshakeType, targetName)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not GB.allowedGuilds[myGuildName] then
        return
    end

    local myRealm = GetRealmName()
    local guildHomeRealm = GB:GetGuildHomeRealm()
    local guildClubId = getGuildClubId()

    if not guildHomeRealm then
        return
    end

    -- Format: [GBWHS]TYPE|guildName|playerRealm|guildHomeRealm|guildClubId
    local payload = "[GBWHS]" .. handshakeType .. "|" .. myGuildName .. "|" .. myRealm .. "|" .. guildHomeRealm .. "|" .. (guildClubId or "")

    if targetName then
        -- Send to specific alt (PONG response) - NOW QUEUED to prevent burst
        GB:QueueWhisperMessage(GB.BRIDGE_ADDON_PREFIX, payload, targetName)
    else
        -- Broadcast to all registered alts - use queue to throttle
        for altName, _ in pairs(GB.registeredAlts or {}) do
            GB:QueueWhisperMessage(GB.BRIDGE_ADDON_PREFIX, payload, altName)
        end
    end
end

-- Send whisper handshake to all registered alts (throttled)
function GB:SendWhisperHandshake()
    local now = GetTime()
    if now - self.lastWhisperHandshakeTime < self.HANDSHAKE_THROTTLE then
        return  -- Throttled
    end
    self.lastWhisperHandshakeTime = now
    doSendWhisperHandshake("HELLO")
end

-- Force send whisper handshake without throttle
function GB:ForceSendWhisperHandshake()
    self.lastWhisperHandshakeTime = 0
    self:SendWhisperHandshake()
end

-- Send whisper handshake to a specific alt
function GB:SendWhisperHandshakeToAlt(altName)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not self.allowedGuilds[myGuildName] then
        return
    end
    doSendWhisperHandshake("HELLO", altName)
end

-- Handle incoming whisper handshake messages
function GB:HandleWhisperHandshakeMessage(message, senderName)
    if not message or message:sub(1, 7) ~= "[GBWHS]" then
        return false
    end

    local data = message:sub(8)

    -- Handle LEAVE message (player logged out or left their guild)
    if data:sub(1, 5) == "LEAVE" then
        -- Parse LEAVE data: LEAVE|charName|charRealm|guildName|guildClubId
        local parts = {strsplit("|", data)}
        local charName = parts[2]
        local charRealm = parts[3]
        local guildName = parts[4]
        local guildClubId = parts[5]

        -- Remove from connected alts
        self.connectedWhisperAlts[senderName] = nil
        self:UpdateConnectionIndicators()

        -- If we have guild info, remove this character from their guild's roster
        if charName and guildName and guildName ~= "" and guildClubId and guildClubId ~= "" then
            local filterKey = self:MakeFilterKey(guildName, self:GetGuildHomeRealmFromClubId(guildClubId))
            local roster = self.guildRosters[filterKey]
            if roster and roster.members and roster.members[charName] then
                -- Remove the character from the roster
                roster.members[charName] = nil
                roster.version = roster.version + 1
                roster.lastUpdate = GetTime()
                self.guildRosters[filterKey] = roster

                -- Refresh UI to show updated roster
                if self.RefreshRoster then
                    self:RefreshRoster()
                end
            end
        end

        -- Clear rosters for guilds that no longer have connections
        if self.ClearDisconnectedRosters then
            self:ClearDisconnectedRosters()
        end
        if self.currentPage == "status" then
            self:RefreshMessages()
        end
        return true
    end

    -- Format: TYPE|guildName|playerRealm|guildHomeRealm|guildClubId
    local handshakeType, guildName, realmName, guildHomeRealm, guildClubId = data:match("([^|]+)|([^|]+)|([^|]*)|([^|]*)|?(.*)$")

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

    if guildClubId == "" then guildClubId = nil end

    -- Record this whisper alt connection
    self.connectedWhisperAlts[senderName] = {
        guildName = guildName,
        realmName = realmName,
        guildHomeRealm = guildHomeRealm,
        guildClubId = guildClubId,
        lastSeen = GetTime(),
    }

    -- Register guild so it appears in tabs
    self:RegisterGuild(guildName, guildHomeRealm, guildClubId)

    -- Update indicators
    self:UpdateConnectionIndicators()

    if self.currentPage == "status" then
        self:RefreshMessages()
    end

    -- If they sent HELLO, respond with PONG
    if handshakeType == "HELLO" then
        doSendWhisperHandshake("PONG", senderName)
    end

    -- Throttled roster request: Only request if we don't have this guild's roster yet
    if guildClubId and self.QueueRosterRequest then
        local filterKey = self:MakeFilterKey(guildName, guildHomeRealm)
        local roster = self.guildRosters[filterKey]

        if not roster or not roster.members then
            self:QueueRosterRequest(senderName, guildClubId, "whisper")
        end
    end

    -- Party sync removed - now local-only (no network traffic)

    return true
end

-- Send leave notification via whisper to registered alts
function GB:SendWhisperLeaveNotification()
    -- Include character name and guild info so receivers can update their rosters
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()

    -- Format: [GBWHS]LEAVE|charName|charRealm|guildName|guildClubId
    local payload = "[GBWHS]LEAVE|" .. myName .. "|" .. myRealm .. "|" .. (myGuildName or "") .. "|" .. (myGuildClubId or "")

    for altName, _ in pairs(self.registeredAlts or {}) do
        self:QueueWhisperMessage(self.BRIDGE_ADDON_PREFIX, payload, altName)
    end
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
