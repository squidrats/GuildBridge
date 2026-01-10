-- MNet Roster Sync Module
-- Handles roster synchronization between connected bridge users

local addonName, GB = ...

-- Class abbreviations for compact transmission
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

-- Abbreviate class name for transmission
function GB:AbbrevClass(classFile)
    return classAbbrev[classFile] or "??"
end

-- Expand class abbreviation
function GB:ExpandClassAbbrev(abbrev)
    return classExpand[abbrev] or nil
end

-- Get my guild's filter key
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

-- Find filterKey by guildClubId
function GB:FindFilterKeyByClubId(guildClubId)
    -- Check known guilds
    for filterKey, info in pairs(self.knownGuilds) do
        if info.guildClubId and tostring(info.guildClubId) == tostring(guildClubId) then
            return filterKey
        end
    end
    -- Check if it matches our own guild
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if myGuildClubId and tostring(myGuildClubId) == tostring(guildClubId) then
        return self:GetMyGuildFilterKey()
    end
    return nil
end

-- Get online guild members from WoW API
function GB:GetOnlineGuildMembers()
    local members = {}
    if not IsInGuild() then return members end

    local numMembers = GetNumGuildMembers()
    local myGuildHomeRealm = self:GetGuildHomeRealm()

    for i = 1, numMembers do
        local name, _, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name and online then
            local charName, charRealm = strsplit("-", name)
            -- Only include realm if different from guild home realm
            local realm = nil
            if charRealm and charRealm ~= myGuildHomeRealm then
                realm = charRealm
            end
            members[charName] = {
                realm = realm,
                class = classFile,
            }
        end
    end

    return members
end

-- Chunk roster data for transmission
function GB:ChunkRosterData(members)
    local chunks = {}
    local currentChunk = ""

    for name, info in pairs(members) do
        local entry = name .. ":" .. (info.realm or "") .. ":" .. self:AbbrevClass(info.class)

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

    -- Ensure at least one empty chunk if no members
    if #chunks == 0 then
        table.insert(chunks, "")
    end

    return chunks
end

-- Send full roster to a specific target
function GB:SendFullRoster(targetGameAccountID, targetType)
    if not IsInGuild() then return end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not self.allowedGuilds[myGuildName] then return end

    local filterKey = self:GetMyGuildFilterKey()
    if not filterKey then return end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not myGuildClubId then return end

    -- Get current online members
    local members = self:GetOnlineGuildMembers()

    -- Update local roster
    local roster = self.guildRosters[filterKey]
    local version = roster and roster.version or 0

    self.guildRosters[filterKey] = {
        members = members,
        version = version,
        lastUpdate = GetTime(),
    }

    -- Chunk and send
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

-- Request full roster from a peer
function GB:RequestFullRoster(targetGameAccountID, guildClubId, targetType)
    if not guildClubId then return end

    local payload = "[GBRR]" .. guildClubId

    if targetType == "whisper" then
        self:QueueWhisperMessage(self.BRIDGE_ADDON_PREFIX, payload, targetGameAccountID)
    else
        self:QueueBNetMessage(targetGameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
    end
end

-- Actually send the accumulated deltas (called after throttle delay)
local function doSendRosterDeltas()
    if not IsInGuild() then return end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not GB.allowedGuilds[myGuildName] then return end

    local filterKey = GB:GetMyGuildFilterKey()
    if not filterKey then return end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not myGuildClubId then return end

    local roster = GB.guildRosters[filterKey]
    if not roster then return end

    local deltas = GB.pendingRosterDeltas

    -- Build delta string from accumulated changes
    local deltaStr = ""
    local seenRemoved = {}
    for _, name in ipairs(deltas.removed or {}) do
        -- Skip if this person was also added (they logged in then out, net effect is removed)
        -- But only include in removed if they're not also in added
        if not deltas.added[name] and not seenRemoved[name] then
            seenRemoved[name] = true
            if deltaStr ~= "" then deltaStr = deltaStr .. "," end
            deltaStr = deltaStr .. "-" .. name
        end
    end
    for name, info in pairs(deltas.added or {}) do
        -- Skip if this person was removed after being added (net effect depends on order)
        -- Since we track final state in roster, check if they're currently online
        if roster.members[name] then
            if deltaStr ~= "" then deltaStr = deltaStr .. "," end
            deltaStr = deltaStr .. "+" .. name .. ":" .. (info.realm or "") .. ":" .. GB:AbbrevClass(info.class)
        end
    end

    -- Clear pending deltas
    GB.pendingRosterDeltas = { added = {}, removed = {} }

    if deltaStr == "" then return end

    local payload = "[GBRD]" .. roster.version .. "|" .. myGuildClubId .. "|" .. deltaStr

    -- Send to all connected bridge users in OTHER guilds
    for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
        -- Skip users in same guild
        if info.guildClubId ~= myGuildClubId then
            GB:QueueBNetMessage(gameAccountID, GB.BRIDGE_ADDON_PREFIX, payload)
        end
    end

    -- Send to whisper alts in other guilds
    for altName, info in pairs(GB.connectedWhisperAlts) do
        if info.guildClubId ~= myGuildClubId then
            GB:QueueWhisperMessage(GB.BRIDGE_ADDON_PREFIX, payload, altName)
        end
    end
end

-- Broadcast roster delta to all connected bridge users in other guilds
-- Accumulates deltas and sends after throttle delay to batch rapid changes
function GB:BroadcastRosterDelta(deltas)
    if not IsInGuild() then return end

    -- Accumulate the deltas
    for _, name in ipairs(deltas.removed or {}) do
        table.insert(self.pendingRosterDeltas.removed, name)
        -- If they were pending to be added, remove from added
        self.pendingRosterDeltas.added[name] = nil
    end
    for name, info in pairs(deltas.added or {}) do
        self.pendingRosterDeltas.added[name] = info
    end

    -- Throttle: schedule send after delay if not already scheduled
    local now = GetTime()
    if now - self.lastRosterBroadcast >= self.ROSTER_SYNC_THROTTLE then
        -- Can send immediately
        self.lastRosterBroadcast = now
        self.rosterDeltaTimerScheduled = false
        doSendRosterDeltas()
    elseif not self.rosterDeltaTimerScheduled then
        -- Schedule send after throttle period (only if not already scheduled)
        self.rosterDeltaTimerScheduled = true
        local delay = self.ROSTER_SYNC_THROTTLE - (now - self.lastRosterBroadcast)
        C_Timer.After(delay, function()
            self.rosterDeltaTimerScheduled = false
            self.lastRosterBroadcast = GetTime()
            doSendRosterDeltas()
        end)
    end
    -- If timer is already scheduled, deltas will be sent when it fires
end

-- Process guild roster update event
function GB:ProcessGuildRosterUpdate()
    if not IsInGuild() then return end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not self.allowedGuilds[myGuildName] then return end

    local filterKey = self:GetMyGuildFilterKey()
    if not filterKey then return end

    -- Get current online members
    local currentOnline = self:GetOnlineGuildMembers()

    -- Compare with previous roster to find changes
    local previousRoster = self.guildRosters[filterKey]
    local deltas = { added = {}, removed = {} }
    local hasChanges = false

    if previousRoster and previousRoster.members then
        -- Find removed members
        for name, _ in pairs(previousRoster.members) do
            if not currentOnline[name] then
                table.insert(deltas.removed, name)
                hasChanges = true
            end
        end

        -- Find added members
        for name, info in pairs(currentOnline) do
            if not previousRoster.members[name] then
                deltas.added[name] = info
                hasChanges = true
            end
        end
    else
        -- First roster capture - everything is "added"
        for name, info in pairs(currentOnline) do
            deltas.added[name] = info
        end
        hasChanges = true
    end

    -- Update local roster
    local newVersion = (previousRoster and previousRoster.version or 0) + (hasChanges and 1 or 0)
    self.guildRosters[filterKey] = {
        members = currentOnline,
        version = newVersion,
        lastUpdate = GetTime(),
    }

    -- Broadcast deltas if any changes
    if hasChanges and (next(deltas.removed) or next(deltas.added)) then
        self:BroadcastRosterDelta(deltas)
    end

    -- Refresh UI
    if self.RefreshRoster then
        self:RefreshRoster()
    end
end

-- Handle incoming roster request
function GB:HandleRosterRequest(payload, senderID, senderType)
    local guildClubId = payload
    if not guildClubId then return end

    -- Check if this request is for our guild
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not myGuildClubId or tostring(myGuildClubId) ~= tostring(guildClubId) then
        return
    end

    -- Send our full roster
    self:SendFullRoster(senderID, senderType)
end

-- Handle incoming full roster message
function GB:HandleRosterFullMessage(payload, senderID, senderType)
    local version, guildClubId, chunkIndex, totalChunks, data =
        payload:match("([^|]+)|([^|]+)|(%d+)|(%d+)|(.*)$")

    if not version or not guildClubId then return end

    -- Relay to guildmates if this is from another guild (via BNet or whisper, not guild relay)
    if senderType ~= "guild" and self.RelayDataToGuildmates then
        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        if myGuildClubId and tostring(myGuildClubId) ~= tostring(guildClubId) then
            self:RelayDataToGuildmates("[GBRF]" .. payload)
        end
    end

    chunkIndex = tonumber(chunkIndex)
    totalChunks = tonumber(totalChunks)
    version = tonumber(version)

    -- Initialize pending chunks tracker
    if not self.pendingRosterChunks[guildClubId] then
        self.pendingRosterChunks[guildClubId] = {
            expectedTotal = totalChunks,
            version = version,
            chunks = {},
            startTime = GetTime(),
        }
    end

    local pending = self.pendingRosterChunks[guildClubId]

    -- Check if this is an older version
    if version < pending.version then
        return
    end

    -- If newer version, reset chunks
    if version > pending.version then
        pending.version = version
        pending.expectedTotal = totalChunks
        pending.chunks = {}
        pending.startTime = GetTime()
    end

    -- Store this chunk
    pending.chunks[chunkIndex] = data

    -- Check if we have all chunks
    local receivedCount = 0
    for _ in pairs(pending.chunks) do
        receivedCount = receivedCount + 1
    end

    if receivedCount == pending.expectedTotal then
        -- Reassemble and parse
        self:AssembleAndApplyRoster(guildClubId, pending)
        self.pendingRosterChunks[guildClubId] = nil
    end
end

-- Assemble chunks and apply roster
function GB:AssembleAndApplyRoster(guildClubId, pending)
    -- Reassemble data from chunks
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

    -- Parse members
    local members = {}
    if fullData ~= "" then
        for entry in fullData:gmatch("[^,]+") do
            local name, realm, classAbbr = entry:match("([^:]*):([^:]*):([^:]*)")
            if name and name ~= "" then
                members[name] = {
                    realm = realm ~= "" and realm or nil,
                    class = self:ExpandClassAbbrev(classAbbr),
                }
            end
        end
    end

    -- Find or create filterKey for this guild
    local filterKey = self:FindFilterKeyByClubId(guildClubId)
    if not filterKey then
        -- Create a temporary filterKey
        filterKey = "Unknown-" .. guildClubId
    end

    -- Store roster
    self.guildRosters[filterKey] = {
        members = members,
        version = pending.version,
        lastUpdate = GetTime(),
        guildClubId = guildClubId,
    }

    -- Refresh UI
    if self.RefreshRoster then
        self:RefreshRoster()
    end
end

-- Handle incoming roster delta message
function GB:HandleRosterDeltaMessage(payload, senderID, senderType)
    local version, guildClubId, changes = payload:match("([^|]+)|([^|]+)|(.+)")
    if not version or not guildClubId or not changes then return end

    -- Relay to guildmates if this is from another guild (via BNet or whisper, not guild relay)
    if senderType ~= "guild" and self.RelayDataToGuildmates then
        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        if myGuildClubId and tostring(myGuildClubId) ~= tostring(guildClubId) then
            self:RelayDataToGuildmates("[GBRD]" .. payload)
        end
    end

    version = tonumber(version)

    -- Find the filterKey for this guild
    local filterKey = self:FindFilterKeyByClubId(guildClubId)
    if not filterKey then
        -- We don't know this guild, request full roster
        if senderType == "whisper" then
            self:RequestFullRoster(senderID, guildClubId, "whisper")
        else
            self:RequestFullRoster(senderID, guildClubId, "bnet")
        end
        return
    end

    local roster = self.guildRosters[filterKey]
    if not roster then
        -- We don't have this roster yet, request full sync
        if senderType == "whisper" then
            self:RequestFullRoster(senderID, guildClubId, "whisper")
        else
            self:RequestFullRoster(senderID, guildClubId, "bnet")
        end
        return
    end

    -- Only apply if version is newer
    if version <= roster.version then return end

    -- Parse and apply changes
    for change in changes:gmatch("[^,]+") do
        local prefix = change:sub(1, 1)
        local data = change:sub(2)

        if prefix == "+" then
            -- Add member
            local name, realm, classAbbr = data:match("([^:]*):([^:]*):([^:]*)")
            if name and name ~= "" then
                roster.members[name] = {
                    realm = realm ~= "" and realm or nil,
                    class = self:ExpandClassAbbrev(classAbbr),
                }
            end
        elseif prefix == "-" then
            -- Remove member
            roster.members[data] = nil
        end
    end

    roster.version = version
    roster.lastUpdate = GetTime()

    -- Refresh UI
    if self.RefreshRoster then
        self:RefreshRoster()
    end
end

-- Clear rosters for guilds that no longer have active connections
-- Called when connection status changes (user disconnects, LEAVE received, etc.)
function GB:ClearDisconnectedRosters()
    local myFilterKey = self:GetMyGuildFilterKey()
    local clearedAny = false

    for filterKey, roster in pairs(self.guildRosters) do
        -- Skip our own guild's roster
        if filterKey ~= myFilterKey then
            -- Remove if we don't have an active connection to this guild
            if not self:HasConnectedUserInGuild(filterKey) then
                self.guildRosters[filterKey] = nil
                clearedAny = true
            end
        end
    end

    -- Refresh UI if we cleared any rosters
    if clearedAny and self.RefreshRoster then
        self:RefreshRoster()
    end
end

-- Cleanup stale roster data (call periodically)
function GB:CleanupStaleRosters()
    local now = GetTime()
    for filterKey, roster in pairs(self.guildRosters) do
        -- Skip our own guild's roster
        local myFilterKey = self:GetMyGuildFilterKey()
        if filterKey ~= myFilterKey then
            -- Remove rosters not updated in 10 minutes
            if now - roster.lastUpdate > 600 then
                -- Only remove if we don't have an active connection to this guild
                if not self:HasConnectedUserInGuild(filterKey) then
                    self.guildRosters[filterKey] = nil
                end
            end
        end
    end

    -- Cleanup stale pending chunks (older than 30 seconds)
    for guildClubId, pending in pairs(self.pendingRosterChunks) do
        if now - pending.startTime > 30 then
            self.pendingRosterChunks[guildClubId] = nil
        end
    end
end

-- Request roster re-sync from all connected users in other guilds
-- Called periodically to recover from missed deltas
function GB:RequestRosterResync()
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()

    -- Request from BNet bridge users
    for gameAccountID, info in pairs(self.connectedBridgeUsers) do
        if info.guildClubId and info.guildClubId ~= myGuildClubId then
            self:RequestFullRoster(gameAccountID, info.guildClubId, "bnet")
        end
    end

    -- Request from whisper alts
    for altName, info in pairs(self.connectedWhisperAlts) do
        if info.guildClubId and info.guildClubId ~= myGuildClubId then
            self:RequestFullRoster(altName, info.guildClubId, "whisper")
        end
    end
end

-- ============================================================================
-- Party Sync Functions
-- ============================================================================

-- Get current party/raid members as a table of "Name-Realm" keys
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

-- Process party update event - detect changes and broadcast
function GB:ProcessPartyUpdate()
    local currentMembers = self:GetPartyMemberKeys()
    local previousMembers = self.partyMembers or {}

    -- Check if there are any changes
    local hasChanges = false

    -- Check for new members
    for key, _ in pairs(currentMembers) do
        if not previousMembers[key] then
            hasChanges = true
            break
        end
    end

    -- Check for removed members
    if not hasChanges then
        for key, _ in pairs(previousMembers) do
            if not currentMembers[key] then
                hasChanges = true
                break
            end
        end
    end

    -- Update local state
    self.partyMembers = currentMembers

    -- Broadcast if changes detected
    if hasChanges then
        self:BroadcastPartyStatus()
    end

    -- Refresh UI
    if self.RefreshRoster then
        self:RefreshRoster()
    end
end

-- Build party status payload string
-- Format: [GBPY]senderKey|member1,member2,member3
function GB:BuildPartyStatusPayload()
    -- Include our own name as the sender so relayed messages preserve attribution
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local senderKey = myName .. "-" .. myRealm

    local memberList = ""
    for key, _ in pairs(self.partyMembers) do
        if memberList ~= "" then
            memberList = memberList .. ","
        end
        memberList = memberList .. key
    end
    return "[GBPY]" .. senderKey .. "|" .. memberList
end

-- Send party status to a specific target (used on new connections, bypasses throttle)
function GB:SendPartyStatusTo(targetID, targetType)
    local payload = self:BuildPartyStatusPayload()

    if targetType == "whisper" then
        self:QueueWhisperMessage(self.BRIDGE_ADDON_PREFIX, payload, targetID)
    else
        self:QueueBNetMessage(targetID, self.BRIDGE_ADDON_PREFIX, payload)
    end
end

-- Broadcast current party status to all connected bridge users
function GB:BroadcastPartyStatus()
    local now = GetTime()

    -- Throttle broadcasts
    if now - self.lastPartySyncBroadcast < self.PARTY_SYNC_THROTTLE then
        return
    end
    self.lastPartySyncBroadcast = now

    local payload = self:BuildPartyStatusPayload()

    -- Send to all connected bridge users
    for gameAccountID, info in pairs(self.connectedBridgeUsers) do
        self:QueueBNetMessage(gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
    end

    -- Send to whisper alts
    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 300 then
            self:QueueWhisperMessage(self.BRIDGE_ADDON_PREFIX, payload, altName)
        end
    end
end

-- Handle incoming party status message
-- Format: senderKey|member1,member2,member3 (new format)
-- Or: member1,member2,member3 (old format, for backwards compatibility)
function GB:HandlePartyMessage(payload, senderID, senderType)
    -- Relay to guildmates if this is from another player (via BNet or whisper, not guild relay)
    if senderType ~= "guild" and self.RelayDataToGuildmates then
        self:RelayDataToGuildmates("[GBPY]" .. payload)
    end

    -- Parse the payload - check for new format with sender key
    local senderKey, memberListStr
    local pipePos = payload:find("|")
    if pipePos then
        -- New format: senderKey|members
        senderKey = payload:sub(1, pipePos - 1)
        memberListStr = payload:sub(pipePos + 1)
    else
        -- Old format: just members (backwards compatibility)
        memberListStr = payload
        -- Fall back to deriving sender from senderID
        if senderType == "bnet" then
            local info = self.connectedBridgeUsers[senderID]
            if info and info.characterName then
                local realm = info.characterRealm or info.realmName or GetRealmName()
                senderKey = info.characterName .. "-" .. realm
            end
        elseif senderType == "whisper" or senderType == "guild" then
            senderKey = senderID
            if senderKey and not senderKey:find("-") then
                senderKey = senderKey .. "-" .. GetRealmName()
            end
        end
    end

    if not senderKey then return end

    -- Parse the member list
    local members = {}
    if memberListStr and memberListStr ~= "" then
        for key in memberListStr:gmatch("[^,]+") do
            members[key] = true
        end
    end

    -- Clear old party data from this sender (collect keys first to avoid modifying while iterating)
    local keysToRemove = {}
    for memberKey, partyInfo in pairs(self.remotePartyMembers) do
        if partyInfo.partyLeader == senderKey then
            table.insert(keysToRemove, memberKey)
        end
    end
    for _, key in ipairs(keysToRemove) do
        self.remotePartyMembers[key] = nil
    end

    -- Store new party data (if sender is in a party)
    if next(members) then
        for memberKey, _ in pairs(members) do
            self.remotePartyMembers[memberKey] = {
                partyLeader = senderKey,
            }
        end
    end

    -- Refresh UI
    if self.RefreshRoster then
        self:RefreshRoster()
    end
end

-- Clear party data for a specific sender (when they disconnect)
function GB:ClearPartyDataForSender(senderKey)
    if not senderKey then return end

    local keysToRemove = {}
    for memberKey, partyInfo in pairs(self.remotePartyMembers) do
        if partyInfo.partyLeader == senderKey then
            table.insert(keysToRemove, memberKey)
        end
    end

    for _, key in ipairs(keysToRemove) do
        self.remotePartyMembers[key] = nil
    end

    if #keysToRemove > 0 and self.RefreshRoster then
        self:RefreshRoster()
    end
end

-- Clear all stale party data (for senders no longer connected)
function GB:CleanupStalePartyData()
    -- Build set of currently connected sender keys
    local connectedSenders = {}

    for gameAccountID, info in pairs(self.connectedBridgeUsers) do
        if info.characterName then
            local realm = info.characterRealm or info.realmName or GetRealmName()
            local key = info.characterName .. "-" .. realm
            connectedSenders[key] = true
        end
    end

    local now = GetTime()
    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 300 then
            connectedSenders[altName] = true
        end
    end

    -- Remove party data for senders no longer connected
    local keysToRemove = {}
    for memberKey, partyInfo in pairs(self.remotePartyMembers) do
        if not connectedSenders[partyInfo.partyLeader] then
            table.insert(keysToRemove, memberKey)
        end
    end

    for _, key in ipairs(keysToRemove) do
        self.remotePartyMembers[key] = nil
    end

    if #keysToRemove > 0 and self.RefreshRoster then
        self:RefreshRoster()
    end
end

-- Check if a player is in the local player's party
function GB:IsInMyParty(name, realm)
    local key = name .. "-" .. (realm or GetRealmName())
    return self.partyMembers[key] == true
end

-- Check if a player is in any synced party (including my own)
function GB:IsInAnyParty(name, realm)
    local key = name .. "-" .. (realm or GetRealmName())
    return self.partyMembers[key] == true or self.remotePartyMembers[key] ~= nil
end
