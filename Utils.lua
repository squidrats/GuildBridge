-- GuildBridge Utilities Module
-- Helper functions for message handling, friend management, and deduplication

local addonName, GB = ...

-- Generate a hash for message deduplication
function GB:MakeMessageHash(guildName, originName, originRealm, messageText)
    return guildName .. "|" .. originName .. "|" .. originRealm .. "|" .. messageText
end

-- Check if message is a duplicate (seen recently)
function GB:IsDuplicateMessage(hash)
    local now = GetTime()
    -- Clean old entries
    for h, timestamp in pairs(self.recentMessages) do
        if now - timestamp > self.MESSAGE_DEDUPE_WINDOW then
            self.recentMessages[h] = nil
        end
    end
    -- Check if this hash exists
    if self.recentMessages[hash] then
        return true
    end
    -- Record this message
    self.recentMessages[hash] = now
    return false
end

-- Find all online WoW friends
function GB:FindOnlineWoWFriends()
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

-- Update list of online friends
function GB:UpdateOnlineFriends()
    self.onlineFriends = self:FindOnlineWoWFriends()

    -- Update connection indicators on tabs
    if self.UpdateConnectionIndicators then
        self:UpdateConnectionIndicators()
    end

    -- Refresh status page if it's currently displayed
    if self.currentPage == "status" then
        self:RefreshMessages()
    end
end

-- Check if any connected bridge user is in a specific guild
function GB:HasConnectedUserInGuild(filterKey)
    local now = GetTime()

    -- Check BNet friends
    for gameAccountID, info in pairs(self.connectedBridgeUsers) do
        -- Consider stale after 5 minutes
        if now - info.lastSeen < 300 then
            -- Try matching with clubId first, then homeRealm
            if info.guildClubId then
                local theirFilterKey = info.guildName .. "-" .. info.guildClubId
                if theirFilterKey == filterKey then
                    return true
                end
            end
            if info.guildHomeRealm then
                local theirFilterKey = info.guildName .. "-" .. info.guildHomeRealm
                if theirFilterKey == filterKey then
                    return true
                end
            end
        end
    end

    -- Also check whisper alts (shorter timeout since we can't detect their logout reliably)
    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 90 then
            if info.guildClubId then
                local theirFilterKey = info.guildName .. "-" .. info.guildClubId
                if theirFilterKey == filterKey then
                    return true
                end
            end
            if info.guildHomeRealm then
                local theirFilterKey = info.guildName .. "-" .. info.guildHomeRealm
                if theirFilterKey == filterKey then
                    return true
                end
            end
        end
    end

    return false
end

-- Record guild activity for connection indicators
function GB:RecordGuildActivity(filterKey)
    if filterKey then
        self.lastGuildActivity[filterKey] = GetTime()
        self:UpdateConnectionIndicators()
    end
end

-- Check if guild is active (had recent messages)
function GB:IsGuildActive(filterKey)
    if not filterKey then return false end
    local lastTime = self.lastGuildActivity[filterKey]
    if not lastTime then return false end
    -- Consider active if we've seen activity in the last 5 minutes
    return (GetTime() - lastTime) < 300
end

-- Get class color code for a player
-- playerName should be just the name, or Name-Realm format
-- Returns hex color string (e.g., "C69B6D" for warrior)
function GB:GetClassColor(playerName, playerRealm)
    -- Try to find the class from guild roster first
    if IsInGuild() then
        local numMembers = GetNumGuildMembers()
        local searchName = playerName
        if playerRealm and playerRealm ~= "" then
            searchName = playerName .. "-" .. playerRealm
        end

        for i = 1, numMembers do
            local name, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
            if name then
                -- Strip realm from roster name for comparison
                local rosterName = strsplit("-", name)
                if rosterName == playerName or name == searchName then
                    if classFile and self.classColors[classFile] then
                        return self.classColors[classFile]
                    end
                end
            end
        end
    end

    -- Default to green if class not found
    return "00FF00"
end

-- Look up class info from connected bridge users or cached data
-- This is called for messages from OTHER guilds where we don't have roster access
function GB:GetClassColorFromCache(playerName, playerRealm, guildName, classFile)
    -- If we have a class file provided, use it directly
    if classFile and self.classColors[classFile] then
        return self.classColors[classFile]
    end

    -- For messages from own guild, try roster lookup
    local myGuildName = GetGuildInfo("player")
    if guildName == myGuildName then
        return self:GetClassColor(playerName, playerRealm)
    end

    -- Default to green for unknown classes
    return "00FF00"
end

-- Find all chat frames that have guild chat enabled
function GB:FindGuildChatFrames()
    local frames = {}
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            -- Check if this frame has guild messages enabled
            local messageTypes = {GetChatWindowMessages(i)}
            for _, msgType in ipairs(messageTypes) do
                if msgType == "GUILD" then
                    table.insert(frames, chatFrame)
                    break
                end
            end
        end
    end
    self.guildChatFrames = frames
    return frames
end

-- Add a message to all chat frames that have guild chat enabled
function GB:AddMessageToGuildChatFrames(formattedMessage, r, g, b)
    -- Refresh the list of guild chat frames
    local frames = self:FindGuildChatFrames()

    if #frames == 0 then
        -- Fallback to default chat frame if no guild frames found
        DEFAULT_CHAT_FRAME:AddMessage(formattedMessage, r or 0.25, g or 1.0, b or 0.25)
    else
        for _, chatFrame in ipairs(frames) do
            chatFrame:AddMessage(formattedMessage, r or 0.25, g or 1.0, b or 0.25)
        end
    end
end
