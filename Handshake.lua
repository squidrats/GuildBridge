local addonName, GB = ...

local function getGuildClubId()
    if C_Club and C_Club.GetGuildClubId then
        return C_Club.GetGuildClubId()
    end
    return nil
end

local function doSendHandshake(handshakeType, targetGameAccountID)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName then
        return
    end

    local myRealm = GetRealmName()
    local guildHomeRealm = GB:GetGuildHomeRealm()
    local guildClubId = getGuildClubId()

    if not guildHomeRealm then
        return
    end

    if not guildClubId or not GB:IsAllowedGuildId(guildClubId) then
        return
    end

    local payload = "[GBHS]" .. handshakeType .. "|" .. myGuildName .. "|" .. myRealm .. "|" .. guildHomeRealm .. "|" .. (guildClubId or "")

    if targetGameAccountID then
        GB:QueueBNetMessage(targetGameAccountID, GB.BRIDGE_ADDON_PREFIX, payload)
    else
        local friends = GB:FindOnlineWoWFriends()
        local sentCount = 0
        for _, friend in ipairs(friends) do
            local shouldSend = false
            local connInfo = GB.connectedBridgeUsers[friend.gameAccountID]
            if connInfo then
                shouldSend = true
            elseif friend.guildName and GB.allowedGuilds[friend.guildName] then
                shouldSend = true
            end

            if shouldSend then
                GB:QueueBNetMessage(friend.gameAccountID, GB.BRIDGE_ADDON_PREFIX, payload)
                sentCount = sentCount + 1
            end
        end
        if GB.enableTrafficDebug and sentCount > 0 then
            print("|cff00ff00[Handshake]|r Sent to " .. sentCount .. " of " .. #friends .. " online friends")
        end
    end
end

function GB:GetGuildHomeRealmFromClubId(guildClubId)
    for filterKey, info in pairs(self.knownGuilds) do
        if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
            return info.guildHomeRealm
        end
    end
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

function GB:SendLeaveNotification()
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()

    self:WithdrawAllRelayAnnouncements()
    self:StopRelayKeepalive()

    local payload = "[GBHS]LEAVE|" .. myName .. "|" .. myRealm .. "|" .. (myGuildName or "") .. "|" .. (myGuildClubId or "")

    for gameAccountID, _ in pairs(self.connectedBridgeUsers) do
        self:QueueBNetMessage(gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
    end
end

function GB:SendHandshakeMessage(handshakeType, targetGameAccountID)
    doSendHandshake(handshakeType, targetGameAccountID)
end

local function lookupCharacterName(gameAccountID)
    if not UnitExists("player") then
        return nil, nil
    end

    local success, numFriends = pcall(BNGetNumFriends)
    if not success or not numFriends or numFriends == 0 then
        return nil, nil
    end

    for i = 1, numFriends do
        local success2, numGames = pcall(C_BattleNet.GetFriendNumGameAccounts, i)
        if success2 and numGames and numGames > 0 then
            for j = 1, numGames do
                local success3, gameInfo = pcall(C_BattleNet.GetFriendGameAccountInfo, i, j)
                if success3 and gameInfo and gameInfo.gameAccountID == gameAccountID then
                    return gameInfo.characterName, gameInfo.realmName
                end
            end
        end
    end
    return nil, nil
end

function GB:HandleHandshakeMessage(message, senderGameAccountID)
    if not message or message:sub(1, 6) ~= "[GBHS]" then
        return false
    end

    local data = message:sub(7)

    if data:sub(1, 5) == "LEAVE" then
        local parts = {strsplit("|", data)}
        local charName = parts[2]
        local charRealm = parts[3]
        local guildName = parts[4]
        local guildClubId = parts[5]

        local leavingUserGuildClubId = self.connectedBridgeUsers[senderGameAccountID] and self.connectedBridgeUsers[senderGameAccountID].guildClubId
        self.connectedBridgeUsers[senderGameAccountID] = nil

        if leavingUserGuildClubId and not self:HasConnectionToGuild(leavingUserGuildClubId) then
            self:AnnounceRelayAvailability(leavingUserGuildClubId, false)
        end

        self:UpdateConnectionIndicators()

        if charName and guildName and guildName ~= "" and guildClubId and guildClubId ~= "" then
            local filterKey = self:MakeFilterKey(guildName, self:GetGuildHomeRealmFromClubId(guildClubId))
            local roster = self.guildRosters[filterKey]
            if roster and roster.members then
                local guildHomeRealm = self:GetGuildHomeRealmFromClubId(guildClubId)
                local memberKey = charName
                if charRealm and charRealm ~= "" and charRealm ~= guildHomeRealm then
                    memberKey = charName .. "-" .. charRealm
                end

                if roster.members[memberKey] then
                    roster.members[memberKey] = nil
                    roster.version = roster.version + 1
                    roster.lastUpdate = GetTime()
                    self.guildRosters[filterKey] = roster

                    if self.ScheduleRefreshRoster then
                        self:ScheduleRefreshRoster()
                    end
                end
            end
        end

        if self.ClearDisconnectedRosters then
            self:ClearDisconnectedRosters()
        end
        if self.currentPage == "status" then
            self:RefreshMessages()
        end
        return true
    end

    local handshakeType, guildName, realmName, guildHomeRealm, guildClubId = data:match("([^|]+)|([^|]+)|([^|]*)|([^|]*)|?(.*)$")

    if not guildHomeRealm or guildHomeRealm == "" then
        guildHomeRealm = realmName
    end

    if not handshakeType or not guildName then
        return true
    end

    if guildClubId == "" then guildClubId = nil end

    if not guildClubId or not self:IsAllowedGuildId(guildClubId) then
        return true
    end

    local charName, charRealm = lookupCharacterName(senderGameAccountID)

    self.connectedBridgeUsers[senderGameAccountID] = {
        guildName = guildName,
        realmName = realmName,
        guildHomeRealm = guildHomeRealm,
        guildClubId = guildClubId,
        characterName = charName,
        characterRealm = charRealm,
        lastSeen = GetTime(),
    }

    self:RegisterGuild(guildName, guildHomeRealm, guildClubId)

    self:UpdateConnectionIndicators()

    if self.currentPage == "status" then
        self:RefreshMessages()
    end

    if MNetDB.enableGuildRelay and guildClubId then
        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        if myGuildClubId and tostring(myGuildClubId) ~= tostring(guildClubId) then
            self:AnnounceRelayAvailability(guildClubId, true)

            local metaPayload = "[GBGM]" .. tostring(guildClubId) .. "|" .. guildName .. "|" .. (guildHomeRealm or "")
            if self.RelayDataToGuildmates then
                self:RelayDataToGuildmates(metaPayload, guildClubId)
            end
        end
    end

    if handshakeType == "HELLO" then
        self:SendHandshakeMessage("PONG", senderGameAccountID)
    end

    if guildClubId and self.QueueRosterRequest then
        local filterKey = self:MakeFilterKey(guildName, guildHomeRealm)
        local roster = self.guildRosters[filterKey]

        if not roster or not roster.members then
            self:QueueRosterRequest(senderGameAccountID, guildClubId, "bnet")
        end
    end

    return true
end

function GB:SendHandshake()
    local now = GetTime()
    if now - self.lastHandshakeTime < self.HANDSHAKE_THROTTLE then
        return
    end
    self.lastHandshakeTime = now
    self:SendHandshakeMessage("HELLO")
end

function GB:ForceSendHandshake()
    self.lastHandshakeTime = 0
    self:SendHandshake()
end

function GB:SendHandshakeToFriend(gameAccountID)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName then
        return
    end

    local myRealm = GetRealmName()
    local guildHomeRealm = self:GetGuildHomeRealm()
    local guildClubId = getGuildClubId()

    if not guildClubId or not self:IsAllowedGuildId(guildClubId) then
        return
    end

    local payload = "[GBHS]HELLO|" .. myGuildName .. "|" .. myRealm .. "|" .. guildHomeRealm .. "|" .. (guildClubId or "")
    self:QueueBNetMessage(gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
end

local function doSendWhisperHandshake(handshakeType, targetName)
    local myGuildName = GetGuildInfo("player")
    if not myGuildName then
        return
    end

    local myRealm = GetRealmName()
    local guildHomeRealm = GB:GetGuildHomeRealm()
    local guildClubId = getGuildClubId()

    if not guildHomeRealm then
        return
    end

    if not guildClubId or not GB:IsAllowedGuildId(guildClubId) then
        return
    end

    local payload = "[GBWHS]" .. handshakeType .. "|" .. myGuildName .. "|" .. myRealm .. "|" .. guildHomeRealm .. "|" .. (guildClubId or "")

    if targetName then
        GB:QueueWhisperMessage(GB.BRIDGE_ADDON_PREFIX, payload, targetName)
    else
        for altName, _ in pairs(GB.registeredAlts or {}) do
            GB:QueueWhisperMessage(GB.BRIDGE_ADDON_PREFIX, payload, altName)
        end
    end
end

function GB:SendWhisperHandshake()
    local now = GetTime()
    if now - self.lastWhisperHandshakeTime < self.HANDSHAKE_THROTTLE then
        return
    end
    self.lastWhisperHandshakeTime = now
    doSendWhisperHandshake("HELLO")
end

function GB:ForceSendWhisperHandshake()
    self.lastWhisperHandshakeTime = 0
    self:SendWhisperHandshake()
end

function GB:SendWhisperHandshakeToAlt(altName)
    doSendWhisperHandshake("HELLO", altName)
end

function GB:HandleWhisperHandshakeMessage(message, senderName)
    if not message or message:sub(1, 7) ~= "[GBWHS]" then
        return false
    end

    local data = message:sub(8)

    if data:sub(1, 5) == "LEAVE" then
        local parts = {strsplit("|", data)}
        local charName = parts[2]
        local charRealm = parts[3]
        local guildName = parts[4]
        local guildClubId = parts[5]

        local leavingUserGuildClubId = self.connectedWhisperAlts[senderName] and self.connectedWhisperAlts[senderName].guildClubId
        self.connectedWhisperAlts[senderName] = nil

        if leavingUserGuildClubId and not self:HasConnectionToGuild(leavingUserGuildClubId) then
            self:AnnounceRelayAvailability(leavingUserGuildClubId, false)
        end

        self:UpdateConnectionIndicators()

        if charName and guildName and guildName ~= "" and guildClubId and guildClubId ~= "" then
            local filterKey = self:MakeFilterKey(guildName, self:GetGuildHomeRealmFromClubId(guildClubId))
            local roster = self.guildRosters[filterKey]
            if roster and roster.members then
                local guildHomeRealm = self:GetGuildHomeRealmFromClubId(guildClubId)
                local memberKey = charName
                if charRealm and charRealm ~= "" and charRealm ~= guildHomeRealm then
                    memberKey = charName .. "-" .. charRealm
                end

                if roster.members[memberKey] then
                    roster.members[memberKey] = nil
                    roster.version = roster.version + 1
                    roster.lastUpdate = GetTime()
                    self.guildRosters[filterKey] = roster

                    if self.ScheduleRefreshRoster then
                        self:ScheduleRefreshRoster()
                    end
                end
            end
        end

        if self.ClearDisconnectedRosters then
            self:ClearDisconnectedRosters()
        end
        if self.currentPage == "status" then
            self:RefreshMessages()
        end
        return true
    end

    local handshakeType, guildName, realmName, guildHomeRealm, guildClubId = data:match("([^|]+)|([^|]+)|([^|]*)|([^|]*)|?(.*)$")

    if not guildHomeRealm or guildHomeRealm == "" then
        guildHomeRealm = realmName
    end

    if not handshakeType or not guildName then
        return true
    end

    if guildClubId == "" then guildClubId = nil end

    if not guildClubId or not self:IsAllowedGuildId(guildClubId) then
        return true
    end

    self.connectedWhisperAlts[senderName] = {
        guildName = guildName,
        realmName = realmName,
        guildHomeRealm = guildHomeRealm,
        guildClubId = guildClubId,
        lastSeen = GetTime(),
    }

    self:RegisterGuild(guildName, guildHomeRealm, guildClubId)

    self:UpdateConnectionIndicators()

    if self.currentPage == "status" then
        self:RefreshMessages()
    end

    if MNetDB.enableGuildRelay and guildClubId then
        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        if myGuildClubId and tostring(myGuildClubId) ~= tostring(guildClubId) then
            self:AnnounceRelayAvailability(guildClubId, true)
        end
    end

    if handshakeType == "HELLO" then
        doSendWhisperHandshake("PONG", senderName)
    end

    if guildClubId and self.QueueRosterRequest then
        local filterKey = self:MakeFilterKey(guildName, guildHomeRealm)
        local roster = self.guildRosters[filterKey]

        if not roster or not roster.members then
            self:QueueRosterRequest(senderName, guildClubId, "whisper")
        end
    end

    return true
end

function GB:SendWhisperLeaveNotification()
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()

    local payload = "[GBWHS]LEAVE|" .. myName .. "|" .. myRealm .. "|" .. (myGuildName or "") .. "|" .. (myGuildClubId or "")

    for altName, _ in pairs(self.registeredAlts or {}) do
        self:QueueWhisperMessage(self.BRIDGE_ADDON_PREFIX, payload, altName)
    end
end

function GB:UpdateConnectionFromMessage(senderGameAccountID, guildName, guildHomeRealm, realmName, guildClubId)
    if not senderGameAccountID or not guildName then
        return
    end

    if not guildClubId or not self:IsAllowedGuildId(guildClubId) then
        return
    end

    local existing = self.connectedBridgeUsers[senderGameAccountID]
    if existing then
        existing.lastSeen = GetTime()
        if guildClubId then
            existing.guildClubId = guildClubId
        end
        if not existing.characterName then
            local charName, charRealm = lookupCharacterName(senderGameAccountID)
            if charName then
                existing.characterName = charName
                existing.characterRealm = charRealm
            end
        end
    else
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
        self:RegisterGuild(guildName, guildHomeRealm, guildClubId)
    end

    self:UpdateConnectionIndicators()
end
