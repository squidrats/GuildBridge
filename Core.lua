-- GuildBridge Core Module
-- Initializes the addon namespace and shared data structures

local addonName, GB = ...

-- Export addon namespace globally for other modules
GuildBridge = GB

-- Constants
GB.BRIDGE_PAYLOAD_PREFIX = "[GB]"
GB.BRIDGE_ADDON_PREFIX = "GuildBridge"
GB.ANCHOR_CHARACTER_NAME = "Guildbridge"
GB.USE_FALLBACK_REALM = true
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
GB.lastGuildActivity = {}     -- filterKey -> last message timestamp
GB.lastHandshakeTime = 0      -- Throttle handshake sending

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
    self.knownGuilds = GuildBridgeDB.knownGuilds
end

-- Create a filter key from guild name and realm
function GB:MakeFilterKey(guildName, realmName)
    if not guildName then return nil end
    if realmName and realmName ~= "" then
        return guildName .. "-" .. realmName
    end
    return guildName
end

-- Get the guild's home realm by finding the anchor character
function GB:GetGuildHomeRealm()
    if not IsInGuild() then return nil end

    local numMembers = GetNumGuildMembers()
    if not numMembers or numMembers == 0 then
        if self.USE_FALLBACK_REALM then
            return GetRealmName()
        end
        return nil
    end

    -- Iterate through guild roster to find the anchor character
    for i = 1, numMembers do
        local name = GetGuildRosterInfo(i)
        if name then
            local charName, charRealm = strsplit("-", name)
            if charName == self.ANCHOR_CHARACTER_NAME then
                -- Anchor character found - use their realm
                if charRealm and charRealm ~= "" then
                    return charRealm
                else
                    -- No realm suffix means they're on our realm
                    return GetRealmName()
                end
            end
        end
    end

    -- Anchor character not found - use fallback if enabled
    if self.USE_FALLBACK_REALM then
        return GetRealmName()
    end
    return nil
end
