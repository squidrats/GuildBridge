local addonName, GB = ...

MNet = GB

GB.BRIDGE_PAYLOAD_PREFIX = "[GB]"
GB.BRIDGE_ADDON_PREFIX = "MNet"
GB.MESSAGE_DEDUPE_WINDOW = 10
GB.HANDSHAKE_THROTTLE = 10
GB.SEND_THROTTLE_DELAY = 1.0
GB.FRIEND_INFO_DEBOUNCE = 5
GB.lastFriendInfoChange = 0
GB.lastBNConnectedTime = 0
GB.lastBNetAPICall = 0
GB.BNET_API_THROTTLE = 5
GB.lastPlayerEnteringWorld = 0

GB.currentFilter = nil
GB.currentPage = "chat"
GB.messageHistory = {}
GB.knownGuilds = {}
GB.recentMessages = {}
GB.onlineFriends = {}
GB.connectedBridgeUsers = {}
GB.connectedWhisperAlts = {}
GB.guildRelayBridges = {}
GB.lastGuildActivity = {}
GB.lastHandshakeTime = 0
GB.lastWhisperHandshakeTime = 0
GB.guildChatFrames = {}
GB.outgoingQueue = {}
GB.isProcessingQueue = false

GB.guildRosters = {}
GB.pendingRosterChunks = {}
GB.pendingRosterDeltas = { added = {}, removed = {} }
GB.rosterDeltaTimerScheduled = false
GB.ROSTER_SYNC_THROTTLE = 10
GB.ROSTER_CHUNK_SIZE = 200
GB.lastRosterBroadcast = 0
GB.rosterUpdatePending = false
GB.rosterRequestQueue = {}
GB.isProcessingRosterRequests = false
GB.ROSTER_REQUEST_THROTTLE = 5.0

GB.partyMembers = {}

GB.loginHandshakeTimestamp = 0

GB.GUILD_RELAY_THROTTLE = 2.0
GB.lastGuildRelayTime = 0
GB.guildRelayQueue = {}
GB.isProcessingGuildRelay = false
GB.recentGuildRelays = {}

GB.trafficStats = {
    bnet = 0,
    whisper = 0,
    guild = 0,
    lastReset = GetTime(),
    handshakes = 0,
    rosterFull = 0,
    rosterDelta = 0,
    rosterRequest = 0,
    party = 0,
    chat = 0,
}
GB.enableTrafficDebug = false
GB.enableEventDebug = false

GB.mainFrame = nil
GB.scrollFrame = nil
GB.inputBox = nil
GB.tabButtons = {}
GB.pageTabs = {}
GB.muteCheckbox = nil

GB.eventFrame = CreateFrame("Frame")

GB.guildShortNames = {
    ["MAKE ELWYNN GREAT AGAIN"] = "MEGA",
    ["MAKE DUROTAR GREAT AGAIN"] = "MDGA",
    ["Bestiez"] = "Bestiez",
}

GB.guildNumbers = {
    ["MAKE DUROTAR GREAT AGAIN-Tichondrius"] = 1,
    ["MAKE DUROTAR GREAT AGAIN-Illidan"] = 3,
    ["MAKE DUROTAR GREAT AGAIN-Thrall"] = 2,
    ["Bestiez-Tichondrius"] = 2,
}

function GB:HasElvUI()
    return ElvUI ~= nil
end

function GB:GetGuildNumber(guildName, guildHomeRealm)
    if not guildName then return nil end
    local key = guildName .. "-" .. (guildHomeRealm or "")
    return self.guildNumbers[key]
end

GB.allowedGuilds = {
    ["MAKE DUROTAR GREAT AGAIN"] = true,
    ["Bestiez"] = true,
}

GB.classColors = {
    ["WARRIOR"] = "C69B6D",
    ["PALADIN"] = "F48CBA",
    ["HUNTER"] = "AAD372",
    ["ROGUE"] = "FFF468",
    ["PRIEST"] = "FFFFFF",
    ["DEATHKNIGHT"] = "C41E3A",
    ["SHAMAN"] = "0070DD",
    ["MAGE"] = "3FC7EB",
    ["WARLOCK"] = "8788EE",
    ["MONK"] = "00FF98",
    ["DRUID"] = "FF7C0A",
    ["DEMONHUNTER"] = "A330C9",
    ["EVOKER"] = "33937F",
}

function GB:EnsureSavedVariables()
    if not MNetDB then
        MNetDB = {}
    end
    if MNetDB.bridgeEnabled == nil then
        MNetDB.bridgeEnabled = true
    end
    if MNetDB.muteSend == nil then
        MNetDB.muteSend = false
    end
    if MNetDB.filterNativeChat == nil then
        MNetDB.filterNativeChat = false
    end
    if MNetDB.enableGuildRelay == nil then
        MNetDB.enableGuildRelay = true
    end
    if MNetDB.relayRosterToGuild == nil then
        MNetDB.relayRosterToGuild = true
    end
    if MNetDB.knownGuilds == nil then
        MNetDB.knownGuilds = {}
    end
    if MNetDB.registeredAlts == nil then
        MNetDB.registeredAlts = {}
    end
    if MNetDB.windowPos == nil then
        MNetDB.windowPos = {}
    end
    if MNetDB.enableEventDebug == nil then
        MNetDB.enableEventDebug = false
    end
    if MNetDB.enableTrafficDebug == nil then
        MNetDB.enableTrafficDebug = false
    end
    self.knownGuilds = MNetDB.knownGuilds
    self.registeredAlts = MNetDB.registeredAlts
    self.enableEventDebug = MNetDB.enableEventDebug
    self.enableTrafficDebug = MNetDB.enableTrafficDebug
end

function GB:SaveWindowPosition()
    if not self.mainFrame then return end
    local point, _, relPoint, x, y = self.mainFrame:GetPoint()
    MNetDB.windowPos = {
        point = point,
        relPoint = relPoint,
        x = x,
        y = y,
        width = self.mainFrame:GetWidth(),
        height = self.mainFrame:GetHeight(),
        rosterWidth = self.rosterWidth,
    }
end

function GB:RestoreWindowPosition()
    if not self.mainFrame then return end
    local pos = MNetDB.windowPos
    if pos and pos.point then
        self.mainFrame:ClearAllPoints()
        self.mainFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
    if pos and pos.width and pos.height then
        self.mainFrame:SetSize(pos.width, pos.height)
    end
    if pos and pos.rosterWidth then
        self.rosterWidth = pos.rosterWidth
    end
end

function GB:MakeFilterKey(guildName, realmName)
    if not guildName then return nil end
    if realmName and realmName ~= "" then
        return guildName .. "-" .. realmName
    end
    return guildName
end

function GB:GetGuildHomeRealm()
    if not IsInGuild() then return nil end

    local guildName, _, _, guildRealm = GetGuildInfo("player")
    if guildName then
        if guildRealm and guildRealm ~= "" then
            return guildRealm
        else
            return GetRealmName()
        end
    end

    return GetRealmName()
end

function GB:QueueBNetMessage(gameAccountID, prefix, payload)
    table.insert(self.outgoingQueue, {
        type = "bnet",
        target = gameAccountID,
        prefix = prefix,
        payload = payload,
    })
    self:ProcessQueue()
end

function GB:QueueWhisperMessage(prefix, payload, targetName)
    table.insert(self.outgoingQueue, {
        type = "whisper",
        target = targetName,
        prefix = prefix,
        payload = payload,
    })
    self:ProcessQueue()
end

function GB:ProcessQueue()
    if self.isProcessingQueue or #self.outgoingQueue == 0 then
        return
    end

    self.isProcessingQueue = true

    local function processNext()
        if #GB.outgoingQueue == 0 then
            GB.isProcessingQueue = false
            return
        end

        local msg = table.remove(GB.outgoingQueue, 1)

        local msgType = "unknown"
        if msg.payload then
            if msg.payload:sub(1, 6) == "[GBHS]" then
                msgType = "handshake"
                GB.trafficStats.handshakes = GB.trafficStats.handshakes + 1
            elseif msg.payload:sub(1, 6) == "[GBRF]" then
                msgType = "roster-full"
                GB.trafficStats.rosterFull = GB.trafficStats.rosterFull + 1
            elseif msg.payload:sub(1, 6) == "[GBRD]" then
                msgType = "roster-delta"
                GB.trafficStats.rosterDelta = GB.trafficStats.rosterDelta + 1
            elseif msg.payload:sub(1, 6) == "[GBRR]" then
                msgType = "roster-req"
                GB.trafficStats.rosterRequest = GB.trafficStats.rosterRequest + 1
            elseif msg.payload:sub(1, 6) == "[GBPY]" then
                msgType = "party"
                GB.trafficStats.party = GB.trafficStats.party + 1
            elseif msg.payload:sub(1, 4) == "[GB]" then
                msgType = "chat"
                GB.trafficStats.chat = GB.trafficStats.chat + 1
            end
        end

        if msg.type == "bnet" then
            pcall(BNSendGameData, msg.target, msg.prefix, msg.payload)
            GB.trafficStats.bnet = GB.trafficStats.bnet + 1
            if GB.enableTrafficDebug then
                print(string.format("|cff00ff00[Traffic]|r BNet %s (queue: %d)", msgType, #GB.outgoingQueue))
            end
        elseif msg.type == "whisper" then
            C_ChatInfo.SendAddonMessage(msg.prefix, msg.payload, "WHISPER", msg.target)
            GB.trafficStats.whisper = GB.trafficStats.whisper + 1
            if GB.enableTrafficDebug then
                print(string.format("|cff00ff00[Traffic]|r Whisper %s (queue: %d)", msgType, #GB.outgoingQueue))
            end
        end

        if #GB.outgoingQueue > 0 then
            C_Timer.After(GB.SEND_THROTTLE_DELAY, processNext)
        else
            GB.isProcessingQueue = false
        end
    end

    processNext()
end

SLASH_MNDEBUG1 = "/mndebug"
SlashCmdList["MNDEBUG"] = function()
    print("=== MNet Debug ===")

    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    print("My guild: " .. (myGuildName or "nil") .. " (clubId: " .. tostring(myGuildClubId) .. ")")
    print("In allowedGuilds: " .. tostring(myGuildName and GB.allowedGuilds[myGuildName] or false))

    local friends = GB:FindOnlineWoWFriends()
    print("Online WoW friends: " .. #friends)
    for i, friend in ipairs(friends) do
        if i <= 5 then
            print("  " .. (friend.characterName or "?") .. "-" .. (friend.realmName or "?") .. " | guildName: " .. tostring(friend.guildName))
        end
    end
    if #friends > 5 then
        print("  ... and " .. (#friends - 5) .. " more")
    end

    local connCount = 0
    for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
        connCount = connCount + 1
        if connCount <= 5 then
            print("  Connected: " .. (info.characterName or "?") .. " in <" .. (info.guildName or "?") .. ">")
        end
    end
    print("Connected bridge users: " .. connCount)

    print("Queue size: " .. #GB.outgoingQueue .. " | Processing: " .. tostring(GB.isProcessingQueue))

    print("=========================")
end
