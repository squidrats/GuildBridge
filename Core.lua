-- GuildBridge Core Module
-- Initializes the addon namespace and shared data structures

local addonName, GB = ...

-- Export addon namespace globally for other modules
GuildBridge = GB

-- Constants
GB.BRIDGE_PAYLOAD_PREFIX = "[GB]"
GB.BRIDGE_ADDON_PREFIX = "GuildBridge"
GB.MESSAGE_DEDUPE_WINDOW = 10  -- seconds
GB.HANDSHAKE_THROTTLE = 10    -- seconds

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
    if not GuildBridgeDB then
        GuildBridgeDB = {}
    end
    if GuildBridgeDB.bridgeEnabled == nil then
        GuildBridgeDB.bridgeEnabled = true
    end
    if GuildBridgeDB.muteSend == nil then
        GuildBridgeDB.muteSend = false
    end
    if GuildBridgeDB.filterNativeChat == nil then
        GuildBridgeDB.filterNativeChat = false
    end
    if GuildBridgeDB.knownGuilds == nil then
        GuildBridgeDB.knownGuilds = {}
    end
    -- Registered alts for same-account communication (Name-Realm format)
    if GuildBridgeDB.registeredAlts == nil then
        GuildBridgeDB.registeredAlts = {}
    end
    -- Window position and size
    if GuildBridgeDB.windowPos == nil then
        GuildBridgeDB.windowPos = {}
    end
    self.knownGuilds = GuildBridgeDB.knownGuilds
    self.registeredAlts = GuildBridgeDB.registeredAlts
end

-- Save window position and size
function GB:SaveWindowPosition()
    if not self.mainFrame then return end
    local point, _, relPoint, x, y = self.mainFrame:GetPoint()
    GuildBridgeDB.windowPos = {
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
    local pos = GuildBridgeDB.windowPos
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
