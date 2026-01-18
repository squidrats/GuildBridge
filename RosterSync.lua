local addonName, GB = ...

local classAbbrev = {
    WARRIOR = "WR", PALADIN = "PA", HUNTER = "HU", ROGUE = "RO",
    PRIEST = "PR", DEATHKNIGHT = "DK", SHAMAN = "SH", MAGE = "MA",
    WARLOCK = "WL", MONK = "MO", DRUID = "DR", DEMONHUNTER = "DH",
    EVOKER = "EV",
}

local classExpand = {
    WR = "WARRIOR", PA = "PALADIN", HU = "HUNTER", RO = "ROGUE",
    PR = "PRIEST", DK = "DEATHKNIGHT", SH = "SHAMAN", MA = "MAGE",
    WL = "WARLOCK", MO = "MONK", DR = "DRUID", DH = "DEMONHUNTER",
    EV = "EVOKER",
}

function GB:AbbrevClass(classFile)
    return classAbbrev[classFile] or "??"
end

function GB:ExpandClassAbbrev(abbrev)
    return classExpand[abbrev] or nil
end

function GB:GetMyGuildFilterKey()
    local myGuildName = GetGuildInfo("player")
    if not myGuildName then return nil end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local myGuildHomeRealm = self:GetGuildHomeRealm()

    if myGuildClubId then
        return myGuildName .. "-" .. myGuildClubId
    elseif myGuildHomeRealm then
        return myGuildName .. "-" .. myGuildHomeRealm
    end
    return nil
end

function GB:FindFilterKeyByClubId(guildClubId)
    for filterKey, info in pairs(self.knownGuilds) do
        if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
            return filterKey
        end
    end
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if myGuildClubId and tostring(myGuildClubId) == tostring(guildClubId) then
        return self:GetMyGuildFilterKey()
    end
    return nil
end

function GB:LookupGuildInfoByClubId(guildClubId, senderID, senderType)
    if not guildClubId then return nil, nil end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if myGuildClubId and tostring(myGuildClubId) == tostring(guildClubId) then
        local myGuildName = GetGuildInfo("player")
        local myGuildHomeRealm = self:GetGuildHomeRealm()
        return myGuildName, myGuildHomeRealm
    end

    if senderType == "bnet" then
        local info = self.connectedBridgeUsers[senderID]
        if info and tostring(info.guildClubId) == tostring(guildClubId) then
            return info.guildName, info.guildHomeRealm
        end
    elseif senderType == "whisper" then
        local info = self.connectedWhisperAlts[senderID]
        if info and tostring(info.guildClubId) == tostring(guildClubId) then
            return info.guildName, info.guildHomeRealm
        end
    elseif senderType == "guild" then
        for _, info in pairs(self.connectedBridgeUsers) do
            if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
                return info.guildName, info.guildHomeRealm
            end
        end
        for _, info in pairs(self.connectedWhisperAlts) do
            if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
                return info.guildName, info.guildHomeRealm
            end
        end
    end

    for _, info in pairs(self.knownGuilds) do
        if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
            return info.guildName, info.guildHomeRealm
        end
    end

    return nil, nil
end

function GB:GetOnlineGuildMembers()
    local members = {}
    if not IsInGuild() then return members end

    local numMembers = GetNumGuildMembers()
    local myGuildHomeRealm = self:GetGuildHomeRealm()

    for i = 1, numMembers do
        local name, _, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name and online then
            local charName, charRealm = strsplit("-", name)
            local realm = nil
            local memberKey = charName
            if charRealm and charRealm ~= myGuildHomeRealm then
                realm = charRealm
                memberKey = charName .. "-" .. charRealm
            end
            members[memberKey] = {
                name = charName,
                realm = realm,
                class = classFile,
            }
        end
    end

    return members
end

function GB:ChunkRosterData(members)
    local chunks = {}
    local currentChunk = ""

    for memberKey, info in pairs(members) do
        local charName = info.name or memberKey
        local entry = charName .. ":" .. (info.realm or "") .. ":" .. self:AbbrevClass(info.class)

        if #currentChunk + #entry + 1 > self.ROSTER_CHUNK_SIZE then
            if currentChunk ~= "" then
                table.insert(chunks, currentChunk)
            end
            currentChunk = entry
        else
            if currentChunk ~= "" then
                currentChunk = currentChunk .. "," .. entry
            else
                currentChunk = entry
            end
        end
    end

    if currentChunk ~= "" then
        table.insert(chunks, currentChunk)
    end

    if #chunks == 0 then
        table.insert(chunks, "")
    end

    return chunks
end

function GB:SendFullRoster(targetGameAccountID, targetType)
    if not IsInGuild() then return end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName then return end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not myGuildClubId or not self:IsAllowedGuildId(myGuildClubId) then return end

    local filterKey = self:GetMyGuildFilterKey()
    if not filterKey then return end

    local members = self:GetOnlineGuildMembers()

    local roster = self.guildRosters[filterKey]
    local version = roster and roster.version or 0

    self.guildRosters[filterKey] = {
        members = members,
        version = version,
        lastUpdate = GetTime(),
    }

    local chunks = self:ChunkRosterData(members)
    local totalChunks = #chunks

    for i, chunkData in ipairs(chunks) do
        local payload = "[GBRF]" .. version .. "|" .. myGuildClubId .. "|" .. i .. "|" .. totalChunks .. "|" .. chunkData

        if targetType == "whisper" then
            self:QueueWhisperMessage(self.BRIDGE_ADDON_PREFIX, payload, targetGameAccountID)
        else
            self:QueueBNetMessage(targetGameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
        end
    end
end

function GB:QueueRosterRequest(targetID, guildClubId, targetType)
    if not guildClubId then return end

    for _, req in ipairs(self.rosterRequestQueue) do
        if tostring(req.guildClubId) == tostring(guildClubId) then
            return
        end
    end

    table.insert(self.rosterRequestQueue, {
        targetID = targetID,
        guildClubId = guildClubId,
        targetType = targetType,
        timestamp = GetTime(),
    })

    self:ProcessRosterRequestQueue()
end

function GB:ProcessRosterRequestQueue()
    if self.isProcessingRosterRequests or #self.rosterRequestQueue == 0 then
        return
    end

    self.isProcessingRosterRequests = true

    local function processNext()
        if #GB.rosterRequestQueue == 0 then
            GB.isProcessingRosterRequests = false
            return
        end

        -- Pause queue processing during zone transitions
        if GB:IsInZoneTransition() then
            C_Timer.After(GB.ZONE_TRANSITION_COOLDOWN, processNext)
            return
        end

        local req = table.remove(GB.rosterRequestQueue, 1)

        local payload = "[GBRR]" .. req.guildClubId
        if req.targetType == "whisper" then
            GB:QueueWhisperMessage(GB.BRIDGE_ADDON_PREFIX, payload, req.targetID)
        else
            GB:QueueBNetMessage(req.targetID, GB.BRIDGE_ADDON_PREFIX, payload)
        end

        if #GB.rosterRequestQueue > 0 then
            C_Timer.After(GB.ROSTER_REQUEST_THROTTLE, processNext)
        else
            GB.isProcessingRosterRequests = false
        end
    end

    processNext()
end

function GB:RequestFullRoster(targetGameAccountID, guildClubId, targetType)
    if not guildClubId then return end

    local payload = "[GBRR]" .. guildClubId

    if targetType == "whisper" then
        self:QueueWhisperMessage(self.BRIDGE_ADDON_PREFIX, payload, targetGameAccountID)
    else
        self:QueueBNetMessage(targetGameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
    end
end

local function doSendRosterDeltas()
    if not IsInGuild() then return end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName then return end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not myGuildClubId or not GB:IsAllowedGuildId(myGuildClubId) then return end

    local filterKey = GB:GetMyGuildFilterKey()
    if not filterKey then return end

    local roster = GB.guildRosters[filterKey]
    if not roster then return end

    local deltas = GB.pendingRosterDeltas

    local deltaStr = ""
    local seenRemoved = {}
    for _, name in ipairs(deltas.removed or {}) do
        if not deltas.added[name] and not seenRemoved[name] then
            seenRemoved[name] = true
            if deltaStr ~= "" then deltaStr = deltaStr .. "," end
            deltaStr = deltaStr .. "-" .. name
        end
    end
    for memberKey, info in pairs(deltas.added or {}) do
        if roster.members[memberKey] then
            if deltaStr ~= "" then deltaStr = deltaStr .. "," end
            local charName = info.name or memberKey
            deltaStr = deltaStr .. "+" .. charName .. ":" .. (info.realm or "") .. ":" .. GB:AbbrevClass(info.class)
        end
    end

    GB.pendingRosterDeltas = { added = {}, removed = {} }

    if deltaStr == "" then return end

    -- Count current members for sync validation
    local memberCount = 0
    for _ in pairs(roster.members) do
        memberCount = memberCount + 1
    end

    local payload = "[GBRD]" .. roster.version .. "|" .. myGuildClubId .. "|" .. memberCount .. "|" .. deltaStr

    for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
        if info.guildClubId ~= myGuildClubId then
            GB:QueueBNetMessage(gameAccountID, GB.BRIDGE_ADDON_PREFIX, payload)
        end
    end

    for altName, info in pairs(GB.connectedWhisperAlts) do
        if info.guildClubId ~= myGuildClubId then
            GB:QueueWhisperMessage(GB.BRIDGE_ADDON_PREFIX, payload, altName)
        end
    end
end

function GB:BroadcastRosterDelta(deltas)
    if not IsInGuild() then return end

    for _, name in ipairs(deltas.removed or {}) do
        table.insert(self.pendingRosterDeltas.removed, name)
        self.pendingRosterDeltas.added[name] = nil
    end
    for name, info in pairs(deltas.added or {}) do
        self.pendingRosterDeltas.added[name] = info
    end

    if not self.rosterDeltaTimerScheduled then
        self.rosterDeltaTimerScheduled = true
        local function tryBroadcast()
            GB.rosterDeltaTimerScheduled = false
            if GB:IsInZoneTransition() then
                -- Reschedule if in zone transition
                GB.rosterDeltaTimerScheduled = true
                C_Timer.After(GB.ZONE_TRANSITION_COOLDOWN, tryBroadcast)
                return
            end
            GB.lastRosterBroadcast = GetTime()
            doSendRosterDeltas()
        end
        C_Timer.After(self.ROSTER_DELTA_BATCH_INTERVAL, tryBroadcast)
    end
end

function GB:ProcessGuildRosterUpdate()
    if not IsInGuild() then return end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName then return end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not myGuildClubId or not self:IsAllowedGuildId(myGuildClubId) then return end

    local filterKey = self:GetMyGuildFilterKey()
    if not filterKey then return end

    local currentOnline = self:GetOnlineGuildMembers()

    local previousRoster = self.guildRosters[filterKey]
    local deltas = { added = {}, removed = {} }
    local hasChanges = false

    if previousRoster and previousRoster.members then
        for name, _ in pairs(previousRoster.members) do
            if not currentOnline[name] then
                table.insert(deltas.removed, name)
                hasChanges = true
            end
        end

        for name, info in pairs(currentOnline) do
            if not previousRoster.members[name] then
                deltas.added[name] = info
                hasChanges = true
            end
        end
    else
        hasChanges = false
    end

    local newVersion = (previousRoster and previousRoster.version or 0) + (hasChanges and 1 or 0)
    self.guildRosters[filterKey] = {
        members = currentOnline,
        version = newVersion,
        lastUpdate = GetTime(),
    }

    if hasChanges and (next(deltas.removed) or next(deltas.added)) then
        self:BroadcastRosterDelta(deltas)
    end

    if self.ScheduleRefreshRoster then
        self:ScheduleRefreshRoster()
    end
end

function GB:HandleRosterRequest(payload, senderID, senderType)
    local guildClubId = payload
    if not guildClubId then return end

    -- Skip sending roster during zone transitions
    if self:IsInZoneTransition() then return end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not myGuildClubId or tostring(myGuildClubId) ~= tostring(guildClubId) then
        return
    end

    self:SendFullRoster(senderID, senderType)
end

function GB:HandleRosterFullMessage(payload, senderID, senderType)
    local version, guildClubId, chunkIndex, totalChunks, data =
        payload:match("([^|]+)|([^|]+)|(%d+)|(%d+)|(.*)$")

    if not version or not guildClubId then return end

    if not self:IsAllowedGuildId(guildClubId) then return end

    if senderType ~= "guild" and self.RelayDataToGuildmates and MNetDB.relayRosterToGuild then
        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        if myGuildClubId and tostring(myGuildClubId) ~= tostring(guildClubId) then
            local guildName, guildHomeRealm = self:LookupGuildInfoByClubId(guildClubId, senderID, senderType)
            if guildName then
                local metaPayload = "[GBGM]" .. guildClubId .. "|" .. guildName .. "|" .. (guildHomeRealm or "")
                self:RelayDataToGuildmates(metaPayload, guildClubId)
            end
            self:RelayDataToGuildmates("[GBRF]" .. payload, guildClubId)
        end
    end

    chunkIndex = tonumber(chunkIndex)
    totalChunks = tonumber(totalChunks)
    version = tonumber(version)

    if not self.pendingRosterChunks[guildClubId] then
        self.pendingRosterChunks[guildClubId] = {
            expectedTotal = totalChunks,
            version = version,
            chunks = {},
            startTime = GetTime(),
        }
    end

    local pending = self.pendingRosterChunks[guildClubId]

    if version < pending.version then
        return
    end

    if version > pending.version then
        pending.version = version
        pending.expectedTotal = totalChunks
        pending.chunks = {}
        pending.startTime = GetTime()
    end

    pending.chunks[chunkIndex] = data

    local receivedCount = 0
    for _ in pairs(pending.chunks) do
        receivedCount = receivedCount + 1
    end

    if receivedCount == pending.expectedTotal then
        self:AssembleAndApplyRoster(guildClubId, pending)
        self.pendingRosterChunks[guildClubId] = nil
    end
end

function GB:AssembleAndApplyRoster(guildClubId, pending)
    local fullData = ""
    for i = 1, pending.expectedTotal do
        if pending.chunks[i] then
            if fullData ~= "" and pending.chunks[i] ~= "" then
                fullData = fullData .. "," .. pending.chunks[i]
            elseif pending.chunks[i] ~= "" then
                fullData = pending.chunks[i]
            end
        end
    end

    local members = {}
    if fullData ~= "" then
        for entry in fullData:gmatch("[^,]+") do
            local name, realm, classAbbr = entry:match("([^:]*):([^:]*):([^:]*)")
            if name and name ~= "" then
                local memberKey = name
                local realmValue = realm ~= "" and realm or nil
                if realmValue then
                    memberKey = name .. "-" .. realmValue
                end
                members[memberKey] = {
                    name = name,
                    realm = realmValue,
                    class = self:ExpandClassAbbrev(classAbbr),
                }
            end
        end
    end

    local filterKey = self:FindFilterKeyByClubId(guildClubId)
    if not filterKey then
        local guildName, guildHomeRealm = nil, nil

        for _, info in pairs(self.connectedBridgeUsers) do
            if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
                guildName = info.guildName
                guildHomeRealm = info.guildHomeRealm
                break
            end
        end

        if not guildName then
            for _, info in pairs(self.connectedWhisperAlts) do
                if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
                    guildName = info.guildName
                    guildHomeRealm = info.guildHomeRealm
                    break
                end
            end
        end

        if not guildName then
            for _, info in pairs(self.guildRelayBridges) do
                if info.guilds and info.guilds[tostring(guildClubId)] then
                    break
                end
            end
        end

        if guildName then
            self:RegisterGuild(guildName, guildHomeRealm, guildClubId)
            filterKey = self:FindFilterKeyByClubId(guildClubId)
        end

        if not filterKey then
            filterKey = "Unknown-" .. guildClubId
        end
    end

    self.guildRosters[filterKey] = {
        members = members,
        version = pending.version,
        lastUpdate = GetTime(),
        guildClubId = guildClubId,
    }

    if self.ScheduleRefreshRoster then
        self:ScheduleRefreshRoster()
    end
end

function GB:HandleRosterDeltaMessage(payload, senderID, senderType)
    -- Try new format first: version|guildClubId|memberCount|changes
    local version, guildClubId, remoteMemberCount, changes = payload:match("([^|]+)|([^|]+)|(%d+)|(.+)")

    -- Fall back to old format: version|guildClubId|changes
    if not changes then
        version, guildClubId, changes = payload:match("([^|]+)|([^|]+)|(.+)")
        remoteMemberCount = nil
    end

    if not version or not guildClubId or not changes then return end

    if not self:IsAllowedGuildId(guildClubId) then return end

    if senderType ~= "guild" and self.RelayDataToGuildmates and MNetDB.relayRosterToGuild then
        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        if myGuildClubId and tostring(myGuildClubId) ~= tostring(guildClubId) then
            local guildName, guildHomeRealm = self:LookupGuildInfoByClubId(guildClubId, senderID, senderType)
            if guildName then
                local metaPayload = "[GBGM]" .. guildClubId .. "|" .. guildName .. "|" .. (guildHomeRealm or "")
                self:RelayDataToGuildmates(metaPayload, guildClubId)
            end
            self:RelayDataToGuildmates("[GBRD]" .. payload, guildClubId)
        end
    end

    version = tonumber(version)
    remoteMemberCount = remoteMemberCount and tonumber(remoteMemberCount) or nil

    local filterKey = self:FindFilterKeyByClubId(guildClubId)
    if not filterKey then
        if senderType == "whisper" then
            self:RequestFullRoster(senderID, guildClubId, "whisper")
        else
            self:RequestFullRoster(senderID, guildClubId, "bnet")
        end
        return
    end

    local roster = self.guildRosters[filterKey]
    if not roster or not roster.members then
        if senderType == "whisper" then
            self:RequestFullRoster(senderID, guildClubId, "whisper")
        else
            self:RequestFullRoster(senderID, guildClubId, "bnet")
        end
        return
    end

    if version <= roster.version then return end

    -- Count local members and compare with remote count
    if remoteMemberCount then
        local localMemberCount = 0
        for _ in pairs(roster.members) do
            localMemberCount = localMemberCount + 1
        end

        -- Count how many adds/removes are in the delta
        local deltaAdds, deltaRemoves = 0, 0
        for change in changes:gmatch("[^,]+") do
            local prefix = change:sub(1, 1)
            if prefix == "+" then
                deltaAdds = deltaAdds + 1
            elseif prefix == "-" then
                deltaRemoves = deltaRemoves + 1
            end
        end

        -- Expected local count after applying delta should match remote count
        local expectedCount = localMemberCount + deltaAdds - deltaRemoves
        local countDiff = math.abs(expectedCount - remoteMemberCount)

        -- If counts differ by more than 5, roster is out of sync - request full roster
        if countDiff > 5 then
            if self.enableTrafficDebug then
                print("|cffff8800[Roster]|r Count mismatch: local=" .. localMemberCount .. " expected=" .. expectedCount .. " remote=" .. remoteMemberCount .. " - requesting full roster")
            end
            if senderType == "whisper" then
                self:RequestFullRoster(senderID, guildClubId, "whisper")
            else
                self:RequestFullRoster(senderID, guildClubId, "bnet")
            end
            return
        end
    end

    for change in changes:gmatch("[^,]+") do
        local prefix = change:sub(1, 1)
        local data = change:sub(2)

        if prefix == "+" then
            local name, realm, classAbbr = data:match("([^:]*):([^:]*):([^:]*)")
            if name and name ~= "" then
                local memberKey = name
                local realmValue = realm ~= "" and realm or nil
                if realmValue then
                    memberKey = name .. "-" .. realmValue
                end
                roster.members[memberKey] = {
                    name = name,
                    realm = realmValue,
                    class = self:ExpandClassAbbrev(classAbbr),
                }
            end
        elseif prefix == "-" then
            roster.members[data] = nil
        end
    end

    roster.version = version
    roster.lastUpdate = GetTime()

    if self.ScheduleRefreshRoster then
        self:ScheduleRefreshRoster()
    end
end

function GB:ClearDisconnectedRosters()
    local myFilterKey = self:GetMyGuildFilterKey()
    local clearedAny = false

    for filterKey, roster in pairs(self.guildRosters) do
        if filterKey ~= myFilterKey then
            if not self:HasConnectedUserInGuild(filterKey) then
                self.guildRosters[filterKey] = {
                    members = {},
                    version = 0,
                    lastUpdate = GetTime(),
                }
                clearedAny = true
            end
        end
    end

    if clearedAny then
        if self.ScheduleRefreshRoster then
            self:ScheduleRefreshRoster()
        end
    end
end

function GB:CleanupStaleRosters()
    local now = GetTime()
    for filterKey, roster in pairs(self.guildRosters) do
        local myFilterKey = self:GetMyGuildFilterKey()
        if filterKey ~= myFilterKey then
            if now - roster.lastUpdate > 600 then
                if not self:HasConnectedUserInGuild(filterKey) then
                    self.guildRosters[filterKey] = nil
                end
            end
        end
    end

    for guildClubId, pending in pairs(self.pendingRosterChunks) do
        if now - pending.startTime > 30 then
            self.pendingRosterChunks[guildClubId] = nil
        end
    end
end

function GB:RequestRosterResync()
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()

    local missingGuilds = {}

    for gameAccountID, info in pairs(self.connectedBridgeUsers) do
        if info.guildClubId and info.guildClubId ~= myGuildClubId then
            local filterKey = self:MakeFilterKey(info.guildName, info.guildHomeRealm)
            local roster = self.guildRosters[filterKey]

            if not roster or not roster.members or (GetTime() - roster.lastUpdate > 600) then
                if not missingGuilds[info.guildClubId] then
                    missingGuilds[info.guildClubId] = true
                    self:QueueRosterRequest(gameAccountID, info.guildClubId, "bnet")
                end
            end
        end
    end

    for altName, info in pairs(self.connectedWhisperAlts) do
        if info.guildClubId and info.guildClubId ~= myGuildClubId then
            local filterKey = self:MakeFilterKey(info.guildName, info.guildHomeRealm)
            local roster = self.guildRosters[filterKey]

            if not roster or not roster.members or (GetTime() - roster.lastUpdate > 600) then
                if not missingGuilds[info.guildClubId] then
                    missingGuilds[info.guildClubId] = true
                    self:QueueRosterRequest(altName, info.guildClubId, "whisper")
                end
            end
        end
    end
end

function GB:GetPartyMemberKeys()
    local members = {}

    if not IsInGroup() then
        return members
    end

    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()

    for i = 1, numMembers do
        local unit = isRaid and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
        if UnitExists(unit) then
            local name, realm = UnitName(unit)
            if name then
                realm = realm or GetRealmName()
                local key = name .. "-" .. realm
                members[key] = true
            end
        end
    end

    return members
end

function GB:ProcessPartyUpdate(skipBroadcast)
    local currentMembers = self:GetPartyMemberKeys()
    self.partyMembers = currentMembers

    if self.ScheduleRefreshRoster then
        self:ScheduleRefreshRoster()
    end
end

function GB:IsInMyParty(name, realm)
    local key = name .. "-" .. (realm or GetRealmName())
    return self.partyMembers[key] == true
end

function GB:IsInAnyParty(name, realm)
    return self:IsInMyParty(name, realm)
end
