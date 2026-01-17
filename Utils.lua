local addonName, GB = ...

function GB:CountTable(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function GB:MakeMessageHash(guildName, originName, originRealm, messageText)
    return guildName .. "|" .. originName .. "|" .. originRealm .. "|" .. messageText
end

function GB:IsDuplicateMessage(hash)
    local now = GetTime()
    for h, timestamp in pairs(self.recentMessages) do
        if now - timestamp > self.MESSAGE_DEDUPE_WINDOW then
            self.recentMessages[h] = nil
        end
    end
    if self.recentMessages[hash] then
        return true
    end
    self.recentMessages[hash] = now
    return false
end

function GB:FindOnlineWoWFriends()
    local friends = {}
    local now = GetTime()

    if not UnitExists("player") then
        if self.enableEventDebug then
            print("  |cff888888[FindOnlineWoWFriends]|r Skipped - player not loaded yet")
        end
        return friends
    end

    if now - self.lastBNetAPICall < self.BNET_API_THROTTLE then
        if self.enableEventDebug then
            print("  |cff888888[FindOnlineWoWFriends]|r Skipped - global throttle (" .. string.format("%.1f", now - self.lastBNetAPICall) .. "s < " .. self.BNET_API_THROTTLE .. "s)")
        end
        return self.onlineFriends or friends
    end
    self.lastBNetAPICall = now

    local success, numFriends = pcall(BNGetNumFriends)
    if not success or not numFriends or numFriends == 0 then
        if self.enableEventDebug then
            print("  |cff888888[FindOnlineWoWFriends]|r BNGetNumFriends returned " .. tostring(numFriends))
        end
        return friends
    end

    local debugSkippedOffline = 0
    local debugSkippedNonWoW = 0

    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            local numGames = C_BattleNet.GetFriendNumGameAccounts(i)
            if numGames and numGames > 0 then
                for j = 1, numGames do
                    local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                    if gameInfo then
                        if gameInfo.clientProgram == "WoW" then
                            if gameInfo.isOnline then
                                local guildName = nil
                                if gameInfo.richPresence then
                                    guildName = gameInfo.richPresence:match("^In <(.+)>$")
                                end
                                table.insert(friends, {
                                    gameAccountID = gameInfo.gameAccountID,
                                    characterName = gameInfo.characterName,
                                    realmName = gameInfo.realmName,
                                    battleTag = accountInfo.battleTag,
                                    guildName = guildName,
                                })
                            else
                                debugSkippedOffline = debugSkippedOffline + 1
                                if self.enableEventDebug then
                                    print("  |cffff8800[FindOnlineWoWFriends]|r " .. (gameInfo.characterName or "?") .. " isOnline=false (skipped)")
                                end
                            end
                        else
                            debugSkippedNonWoW = debugSkippedNonWoW + 1
                        end
                    end
                end
            end
        end
    end

    if self.enableEventDebug then
        print("  |cff888888[FindOnlineWoWFriends]|r Found " .. #friends .. " online WoW friends (skipped: " .. debugSkippedOffline .. " offline, " .. debugSkippedNonWoW .. " non-WoW)")
    end

    return friends
end

function GB:UpdateOnlineFriends()
    self.onlineFriends = self:FindOnlineWoWFriends()

    if self.UpdateConnectionIndicators then
        self:UpdateConnectionIndicators()
    end

    if self.currentPage == "status" then
        self:RefreshMessages()
    end
end

function GB:HasConnectedUserInGuild(filterKey)
    local now = GetTime()

    for gameAccountID, info in pairs(self.connectedBridgeUsers) do
        if now - info.lastSeen < 300 then
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

    for senderName, info in pairs(self.guildRelayBridges) do
        if now - info.lastSeen < 300 and info.guilds then
            for guildClubIdStr, _ in pairs(info.guilds) do
                local candidateFilterKey = filterKey:match("^(.+)%-(%d+)$")
                if candidateFilterKey then
                    local keyGuildName, keyClubId = filterKey:match("^(.+)%-(%d+)$")
                    if tostring(guildClubIdStr) == keyClubId then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function GB:RecordGuildActivity(filterKey)
    if filterKey then
        self.lastGuildActivity[filterKey] = GetTime()
        self:UpdateConnectionIndicators()
    end
end

function GB:IsGuildActive(filterKey)
    if not filterKey then return false end
    local lastTime = self.lastGuildActivity[filterKey]
    if not lastTime then return false end
    return (GetTime() - lastTime) < 300
end

function GB:GetClassColor(playerName, playerRealm)
    if IsInGuild() then
        local numMembers = GetNumGuildMembers()
        local searchName = playerName
        if playerRealm and playerRealm ~= "" then
            searchName = playerName .. "-" .. playerRealm
        end

        for i = 1, numMembers do
            local name, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
            if name then
                local rosterName = strsplit("-", name)
                if rosterName == playerName or name == searchName then
                    if classFile and self.classColors[classFile] then
                        return self.classColors[classFile]
                    end
                end
            end
        end
    end

    return "00FF00"
end

function GB:GetClassColorFromCache(playerName, playerRealm, guildName, classFile)
    if classFile and self.classColors[classFile] then
        return self.classColors[classFile]
    end

    local myGuildName = GetGuildInfo("player")
    if guildName == myGuildName then
        return self:GetClassColor(playerName, playerRealm)
    end

    return "00FF00"
end

function GB:FindGuildChatFrames()
    local frames = {}
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
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

function GB:AddMessageToGuildChatFrames(formattedMessage, r, g, b)
    local frames = self:FindGuildChatFrames()

    if #frames == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(formattedMessage, r or 0.25, g or 1.0, b or 0.25)
    else
        for _, chatFrame in ipairs(frames) do
            chatFrame:AddMessage(formattedMessage, r or 0.25, g or 1.0, b or 0.25)
        end
    end
end
