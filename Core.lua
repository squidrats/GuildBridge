-- MNet Core Module
-- Initializes the addon namespace and shared data structures

local addonName, GB = ...

-- Export addon namespace globally for other modules
MNet = GB

-- Constants
GB.BRIDGE_PAYLOAD_PREFIX = "[GB]"
GB.BRIDGE_ADDON_PREFIX = "MNet"
GB.MESSAGE_DEDUPE_WINDOW = 10  -- seconds
GB.HANDSHAKE_THROTTLE = 10    -- seconds
GB.SEND_THROTTLE_DELAY = 0.15  -- seconds between outgoing messages (prevents disconnect)
GB.FRIEND_INFO_DEBOUNCE = 5   -- seconds to debounce BN_FRIEND_INFO_CHANGED events
GB.lastFriendInfoChange = 0   -- timestamp of last processed friend info change

-- Shared state
GB.currentFilter = nil        -- nil = All, or guild-realm key
GB.currentPage = "chat"       -- "chat" or "status"
GB.messageHistory = {}        -- Store messages for filtering
GB.knownGuilds = {}           -- Track unique guild+realm combinations
GB.recentMessages = {}        -- Hash -> timestamp for deduplication
GB.onlineFriends = {}         -- Track online friends
GB.connectedBridgeUsers = {}  -- gameAccountID -> { guildName, realmName, guildHomeRealm, lastSeen }
GB.connectedWhisperAlts = {}  -- "Name-Realm" -> { guildName, guildHomeRealm, lastSeen }
GB.lastGuildActivity = {}     -- filterKey -> last message timestamp
GB.lastHandshakeTime = 0      -- Throttle handshake sending
GB.lastWhisperHandshakeTime = 0 -- Throttle whisper handshake sending
GB.guildChatFrames = {}       -- Track which chat frames have guild chat enabled
GB.outgoingQueue = {}         -- Queue of outgoing messages { type, target, prefix, payload }
GB.isProcessingQueue = false  -- Flag to track if queue processor is running

-- Roster sync state
GB.guildRosters = {}          -- filterKey -> { members = {}, version = 0, lastUpdate = 0 }
GB.pendingRosterChunks = {}   -- guildClubId -> { chunks = {}, total = n, version = v, startTime = t }
GB.pendingRosterDeltas = { added = {}, removed = {} }  -- Accumulate deltas during throttle
GB.rosterDeltaTimerScheduled = false  -- Prevent multiple timers
GB.ROSTER_SYNC_THROTTLE = 2   -- seconds between roster broadcasts
GB.ROSTER_CHUNK_SIZE = 200    -- bytes per chunk payload
GB.lastRosterBroadcast = 0    -- timestamp of last roster broadcast
GB.rosterUpdatePending = false -- debounce flag for roster updates

-- Party sync state
GB.partyMembers = {}          -- "Name-Realm" -> true (players in my current party)
GB.remotePartyMembers = {}    -- "Name-Realm" -> { partyLeader = "Name-Realm" } (party info from other players)
GB.lastPartySyncBroadcast = 0 -- timestamp of last party sync broadcast
GB.PARTY_SYNC_THROTTLE = 1    -- seconds between party broadcasts

-- UI references (populated by UI module)
GB.mainFrame = nil
GB.scrollFrame = nil
GB.inputBox = nil
GB.tabButtons = {}
GB.pageTabs = {}
GB.muteCheckbox = nil

-- Event frame for addon-wide events
GB.eventFrame = CreateFrame("Frame")

-- Guild configuration
GB.guildShortNames = {
    ["MAKE ELWYNN GREAT AGAIN"] = "MEGA",
    ["MAKE DUROTAR GREAT AGAIN"] = "MDGA",
    ["Bestiez"] = "Bestiez",
}

-- Guild numbers for display (based on server)
-- Format: ["GuildName-HomeRealm"] = number
GB.guildNumbers = {
    ["MAKE DUROTAR GREAT AGAIN-Tichondrius"] = 1,
    ["MAKE DUROTAR GREAT AGAIN-Illidan"] = 3,
    ["MAKE DUROTAR GREAT AGAIN-Thrall"] = 2,
    ["Bestiez-Tichondrius"] = 2,  -- Example, adjust as needed
}

-- Check if ElvUI is loaded
function GB:HasElvUI()
    return ElvUI ~= nil
end

-- Get guild number for a guild based on its home realm
function GB:GetGuildNumber(guildName, guildHomeRealm)
    if not guildName then return nil end
    local key = guildName .. "-" .. (guildHomeRealm or "")
    return self.guildNumbers[key]
end

-- Only relay messages from these guilds
GB.allowedGuilds = {
    -- ["MAKE ELWYNN GREAT AGAIN"] = true,
    ["MAKE DUROTAR GREAT AGAIN"] = true,
    ["Bestiez"] = true,
}

-- Class colors for WoW classes (used for colored player names)
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

-- Initialize saved variables
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
    if MNetDB.knownGuilds == nil then
        MNetDB.knownGuilds = {}
    end
    -- Registered alts for same-account communication (Name-Realm format)
    if MNetDB.registeredAlts == nil then
        MNetDB.registeredAlts = {}
    end
    -- Window position and size
    if MNetDB.windowPos == nil then
        MNetDB.windowPos = {}
    end
    self.knownGuilds = MNetDB.knownGuilds
    self.registeredAlts = MNetDB.registeredAlts
end

-- Save window position and size
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
    }
end

-- Restore window position and size
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
end

-- Create a filter key from guild name and realm
function GB:MakeFilterKey(guildName, realmName)
    if not guildName then return nil end
    if realmName and realmName ~= "" then
        return guildName .. "-" .. realmName
    end
    return guildName
end

-- Get the guild's home realm using the API
-- GetGuildInfo returns the guild's realm as the 4th value (nil if same as player's realm)
function GB:GetGuildHomeRealm()
    if not IsInGuild() then return nil end

    -- GetGuildInfo returns: guildName, guildRankName, guildRankIndex, guildRealm
    -- guildRealm is nil if the guild is on the same realm as the player
    local guildName, _, _, guildRealm = GetGuildInfo("player")
    if guildName then
        if guildRealm and guildRealm ~= "" then
            return guildRealm
        else
            -- Guild is on player's realm
            return GetRealmName()
        end
    end

    -- GetGuildInfo not ready yet, use player's realm as fallback
    return GetRealmName()
end

-- Queue a BNet message for throttled sending
function GB:QueueBNetMessage(gameAccountID, prefix, payload)
    table.insert(self.outgoingQueue, {
        type = "bnet",
        target = gameAccountID,
        prefix = prefix,
        payload = payload,
    })
    self:ProcessQueue()
end

-- Queue a whisper addon message for throttled sending
function GB:QueueWhisperMessage(prefix, payload, targetName)
    table.insert(self.outgoingQueue, {
        type = "whisper",
        target = targetName,
        prefix = prefix,
        payload = payload,
    })
    self:ProcessQueue()
end

-- Process the outgoing message queue with throttling
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
        if msg.type == "bnet" then
            pcall(BNSendGameData, msg.target, msg.prefix, msg.payload)
        elseif msg.type == "whisper" then
            C_ChatInfo.SendAddonMessage(msg.prefix, msg.payload, "WHISPER", msg.target)
        end

        -- Schedule next message with delay
        if #GB.outgoingQueue > 0 then
            C_Timer.After(GB.SEND_THROTTLE_DELAY, processNext)
        else
            GB.isProcessingQueue = false
        end
    end

    processNext()
end

-- Debug command to show diagnostic info
SLASH_MNDEBUG1 = "/mndebug"
SlashCmdList["MNDEBUG"] = function()
    print("=== MNet Debug ===")

    -- My guild info
    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    print("My guild: " .. (myGuildName or "nil") .. " (clubId: " .. tostring(myGuildClubId) .. ")")
    print("In allowedGuilds: " .. tostring(myGuildName and GB.allowedGuilds[myGuildName] or false))

    -- Online friends
    local friends = GB:FindOnlineWoWFriends()
    print("Online WoW friends: " .. #friends)
    for i, friend in ipairs(friends) do
        if i <= 5 then -- Only show first 5
            print("  " .. (friend.characterName or "?") .. "-" .. (friend.realmName or "?") .. " | guildName: " .. tostring(friend.guildName))
        end
    end
    if #friends > 5 then
        print("  ... and " .. (#friends - 5) .. " more")
    end

    -- Connected bridge users
    local connCount = 0
    for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
        connCount = connCount + 1
        if connCount <= 5 then
            print("  Connected: " .. (info.characterName or "?") .. " in <" .. (info.guildName or "?") .. ">")
        end
    end
    print("Connected bridge users: " .. connCount)

    -- Queue status
    print("Queue size: " .. #GB.outgoingQueue .. " | Processing: " .. tostring(GB.isProcessingQueue))

    print("=========================")
end
