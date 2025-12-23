-- GuildBridge Handshake Module
-- Handles handshake protocol for bridge connection discovery

local addonName, GB = ...

-- Actually send the handshake payload
local function doSendHandshake(handshakeType, targetGameAccountID)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not GB.allowedGuilds[myGuildName] then
        return
    end

    local myRealm = GetRealmName()
    local guildHomeRealm = GB:GetGuildHomeRealm()

    -- If we still don't have a guild home realm, don't send - wait for roster
    if not guildHomeRealm then
        return
    end

    -- Format: [GBHS]TYPE|guildName|playerRealm|guildHomeRealm
    local payload = "[GBHS]" .. handshakeType .. "|" .. myGuildName .. "|" .. myRealm .. "|" .. guildHomeRealm

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

-- Send a handshake message to all online friends
-- type: "HELLO" (announce), "PONG" (response to HELLO)
function GB:SendHandshakeMessage(handshakeType, targetGameAccountID)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not self.allowedGuilds[myGuildName] then
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
function GB:HandleHandshakeMessage(message, senderGameAccountID)
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
    if not self.allowedGuilds[guildName] then
        return true
    end

    -- Record this bridge user with guild home realm
    self.connectedBridgeUsers[senderGameAccountID] = {
        guildName = guildName,
        realmName = realmName,
        guildHomeRealm = guildHomeRealm,
        lastSeen = GetTime(),
    }

    -- Update indicators
    if self.UpdateConnectionIndicators then
        self:UpdateConnectionIndicators()
    end

    -- If they sent HELLO, respond with PONG
    if handshakeType == "HELLO" then
        self:SendHandshakeMessage("PONG", senderGameAccountID)
    end

    return true
end

-- Send handshake to all friends (called on login and periodically)
function GB:SendHandshake()
    local now = GetTime()
    if now - self.lastHandshakeTime < self.HANDSHAKE_THROTTLE then
        return  -- Throttled
    end
    self.lastHandshakeTime = now
    self:SendHandshakeMessage("HELLO")
end
