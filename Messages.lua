-- GuildBridge Messages Module
-- Handles message sending, receiving, and display

local addonName, GB = ...

-- Get guild club ID for unique identification
local function getGuildClubId()
    if C_Club and C_Club.GetGuildClubId then
        return C_Club.GetGuildClubId()
    end
    return nil
end

-- Register a guild (for tracking discovered guilds)
-- guildClubId is REQUIRED for registration to prevent duplicate entries
function GB:RegisterGuild(guildName, guildHomeRealm, guildClubId)
    if not guildName then return nil end

    -- Normalize empty strings to nil
    if guildClubId == "" then guildClubId = nil end
    if guildHomeRealm == "" then guildHomeRealm = nil end

    -- Require clubId for registration - this ensures unique guild identification
    if not guildClubId then return nil end

    local filterKey = guildName .. "-" .. guildClubId

    if not self.knownGuilds[filterKey] then
        self.knownGuilds[filterKey] = {
            guildName = guildName,
            guildHomeRealm = guildHomeRealm,
            guildClubId = guildClubId,
            realmName = nil,
            manualRealm = false,
        }
        GuildBridgeDB.knownGuilds = self.knownGuilds

        -- Rebuild tabs to show the new guild
        if self.RebuildTabs then
            self:RebuildTabs()
        end
    elseif guildHomeRealm and not self.knownGuilds[filterKey].guildHomeRealm then
        -- Update home realm if we didn't have it
        self.knownGuilds[filterKey].guildHomeRealm = guildHomeRealm
        GuildBridgeDB.knownGuilds = self.knownGuilds
    end

    return filterKey
end

-- Add a bridge message to the display
-- Now includes class color support and proper realm display for cross-realm invites
-- displayInTargetTab: if set, use this filterKey for display instead of the sender's guild
function GB:AddBridgeMessage(senderName, guildName, factionTag, messageText, senderRealm, guildHomeRealm, classFile, guildClubId, displayInTargetTab)
    -- Use guildClubId or guildHomeRealm as the unique key to distinguish same-name guilds
    local filterKey = self:RegisterGuild(guildName, guildHomeRealm, guildClubId)

    -- If this is a UI message targeted to another guild, we need to find the LOCAL filterKey
    -- for that guild (the sender's filterKey may use a different clubId than we have locally)
    local displayFilterKey = filterKey
    if displayInTargetTab then
        -- Try to find a matching guild in our known guilds by parsing the target
        -- Format is "GuildName-ClubId" or "GuildName-HomeRealm"
        local targetGuildName = displayInTargetTab:match("^(.+)%-[^%-]+$")
        if targetGuildName then
            -- Look for this guild in our known guilds
            for localFilterKey, info in pairs(self.knownGuilds) do
                if info.guildName == targetGuildName then
                    displayFilterKey = localFilterKey
                    break
                end
            end
        end
        -- If no match found, use the target as-is (might still work if filterKeys happen to match)
        if displayFilterKey == filterKey and displayInTargetTab ~= filterKey then
            displayFilterKey = displayInTargetTab
        end
    end

    -- Build guild tag based on guild number and ElvUI presence
    -- Use green color (|cff40FF40) to match native guild chat
    local guildNum = self:GetGuildNumber(guildName, guildHomeRealm)
    local guildTag = ""
    if guildNum then
        -- Multiple guilds with same name - show number to distinguish
        if self:HasElvUI() then
            guildTag = "|cff40FF40[G" .. guildNum .. "]|r "
        else
            guildTag = "|cff40FF40[Guild-" .. guildNum .. "]|r "
        end
    else
        -- Single guild or no number configured - show standard format
        if self:HasElvUI() then
            guildTag = "|cff40FF40[G]|r "
        else
            guildTag = "|cff40FF40[Guild]|r "
        end
    end

    -- Build the player link with full Name-Realm for cross-realm invites
    -- The hyperlink MUST include the realm for cross-realm party invites to work
    local fullName = senderName
    if senderRealm and senderRealm ~= "" then
        fullName = senderName .. "-" .. senderRealm
    end

    -- Get class color for the player name
    local classColor = self:GetClassColorFromCache(senderName, senderRealm, guildName, classFile)

    -- Determine what to display in the bracket
    -- If sender is on a different realm than the receiver, show Name-Realm like regular guild chat
    local displayName = senderName
    local myRealm = GetRealmName()
    if senderRealm and senderRealm ~= "" and senderRealm ~= myRealm then
        displayName = senderName .. "-" .. senderRealm
    end

    -- Create clickable player link with class color
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff" .. classColor .. "[" .. displayName .. "]|r|h"

    -- Store both formats: with guild tag (for "All" view) and without (for filtered view)
    -- Message text is also green to match guild chat
    local formattedWithTag = guildTag .. senderLink .. ": |cff40FF40" .. messageText .. "|r"
    local formattedNoTag = senderLink .. ": |cff40FF40" .. messageText .. "|r"

    -- Record activity for connection indicator
    self:RecordGuildActivity(displayFilterKey)

    table.insert(self.messageHistory, {
        guildName = guildName,
        guildHomeRealm = guildHomeRealm,
        filterKey = displayFilterKey,
        formatted = formattedWithTag,      -- Full format with guild tag
        formattedNoTag = formattedNoTag,   -- Simple format without guild tag
    })
    if #self.messageHistory > 500 then
        table.remove(self.messageHistory, 1)
    end

    if self.scrollFrame and self.currentPage == "chat" and (self.currentFilter == nil or displayFilterKey == self.currentFilter) then
        -- Use format without tag when viewing a specific guild's tab
        local displayMsg = self.currentFilter and formattedNoTag or formattedWithTag
        self.scrollFrame:AddMessage(displayMsg)
    end

    -- Show in native chat based on message type:
    -- - Regular guild messages (no target): Show for ALL players in any allowed guild
    -- - UI messages targeted to a specific guild: Show ONLY for players in that targeted guild
    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local myGuildHomeRealm = self:GetGuildHomeRealm()

    -- Build my guild's filterKey
    local myFilterKey = nil
    if myGuildName then
        if myGuildClubId then
            myFilterKey = myGuildName .. "-" .. myGuildClubId
        elseif myGuildHomeRealm then
            myFilterKey = myGuildName .. "-" .. myGuildHomeRealm
        end
    end

    -- Determine if we should show in native chat
    local showInNativeChat = false
    if displayInTargetTab then
        -- UI message targeted to a specific guild - only show for players in that guild
        showInNativeChat = myFilterKey and displayInTargetTab == myFilterKey
    else
        -- Regular guild message (no target) - show for all players in allowed guilds
        showInNativeChat = myGuildName and self.allowedGuilds[myGuildName]
    end

    if showInNativeChat then
        if not GuildBridgeDB.filterNativeChat or self.currentFilter == nil or displayFilterKey == self.currentFilter then
            self:AddMessageToGuildChatFrames(formattedWithTag, 0.25, 1.0, 0.25)
        end
    end
end

-- Build a bridge payload string
local function buildBridgePayload(GB, originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile, overrideGuildClubId)
    sourceType = sourceType or "U"

    local guildName = overrideGuild or GetGuildInfo("player")
    local guildRealm = overrideGuildRealm or GetRealmName()
    local guildHomeRealm = overrideGuildHomeRealm or GB:GetGuildHomeRealm() or guildRealm
    local guildClubId = overrideGuildClubId or getGuildClubId()
    local factionGroup = select(1, UnitFactionGroup("player")) or "Unknown"

    -- Generate message ID for deduplication if not provided
    if not messageId or messageId == "" then
        messageId = guildHomeRealm .. "-" .. originName .. "-" .. GetTime()
    end

    -- Payload format: [GB]guildName|guildRealm|faction|originName|originRealm|sourceType|targetFilter|messageId|guildHomeRealm|classFile|guildClubId|message
    local payload = GB.BRIDGE_PAYLOAD_PREFIX
        .. (guildName or "")
        .. "|"
        .. (guildRealm or "")
        .. "|"
        .. factionGroup
        .. "|"
        .. originName
        .. "|"
        .. (originRealm or "")
        .. "|"
        .. sourceType
        .. "|"
        .. (targetFilter or "")
        .. "|"
        .. messageId
        .. "|"
        .. (guildHomeRealm or "")
        .. "|"
        .. (classFile or "")
        .. "|"
        .. (guildClubId or "")
        .. "|"
        .. messageText

    return payload
end

-- Send bridge payload to all online friends
function GB:SendBridgePayload(originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile, overrideGuildClubId)
    if not messageText or messageText == "" then
        return
    end

    -- Get current online friends
    if #self.onlineFriends == 0 then
        self.onlineFriends = self:FindOnlineWoWFriends()
    end

    if #self.onlineFriends == 0 then
        return
    end

    local payload = buildBridgePayload(self, originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile, overrideGuildClubId)

    -- Get my guild's clubId to skip same-guild recipients for guild messages
    local myGuildClubId = getGuildClubId()

    -- Send to all online WoW friends
    for _, friend in ipairs(self.onlineFriends) do
        -- For guild messages, skip recipients who are in the same guild (they get CHAT_MSG_GUILD directly)
        local shouldSend = true
        if sourceType == "G" and myGuildClubId then
            local connInfo = self.connectedBridgeUsers[friend.gameAccountID]
            if connInfo and connInfo.guildClubId == myGuildClubId then
                shouldSend = false
            end
        end

        if shouldSend then
            local ok, err = pcall(BNSendGameData, friend.gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
            if not ok then
                print("GuildBridge: error sending to", friend.characterName or "unknown", ":", err)
            end
        end
    end
end

-- Send bridge payload via whisper to registered alts (for same-account communication)
-- excludeSender is optional - if provided, skip that alt (to avoid echo)
function GB:SendWhisperBridgePayload(originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile, overrideGuildClubId, excludeSender)
    if not messageText or messageText == "" then
        return
    end

    -- Get my guild's clubId to skip same-guild recipients for guild messages
    local myGuildClubId = getGuildClubId()

    -- Only send to connected whisper alts that aren't in the same guild (for guild messages)
    local now = GetTime()
    local hasAlts = false
    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 300 and altName ~= excludeSender then
            -- For guild messages, skip alts in the same guild (they get CHAT_MSG_GUILD directly)
            local shouldCount = true
            if sourceType == "G" and myGuildClubId and info.guildClubId == myGuildClubId then
                shouldCount = false
            end
            if shouldCount then
                hasAlts = true
                break
            end
        end
    end

    if not hasAlts then
        return
    end

    local payload = buildBridgePayload(self, originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile, overrideGuildClubId)

    -- Send to all connected whisper alts
    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 300 and altName ~= excludeSender then
            -- For guild messages, skip alts in the same guild (they get CHAT_MSG_GUILD directly)
            local shouldSend = true
            if sourceType == "G" and myGuildClubId and info.guildClubId == myGuildClubId then
                shouldSend = false
            end
            if shouldSend then
                C_ChatInfo.SendAddonMessage(self.BRIDGE_ADDON_PREFIX, payload, "WHISPER", altName)
            end
        end
    end
end

-- Send message from UI input
function GB:SendFromUI(messageText)
    if not messageText or messageText == "" then
        return
    end

    -- Must be in an allowed guild to send messages
    local playerGuildName = GetGuildInfo("player")
    if not playerGuildName or not self.allowedGuilds[playerGuildName] then
        return
    end

    local guildClubId = getGuildClubId()
    if not guildClubId then
        return
    end

    local targetFilter = self.currentFilter

    local originName, originRealm = UnitName("player")
    if not originRealm or originRealm == "" then
        originRealm = GetRealmName()
    end
    local playerGuildHomeRealm = self:GetGuildHomeRealm() or originRealm

    -- Get player's class for coloring
    local _, classFile = UnitClass("player")

    -- Use guildClubId for unique identification
    local filterKey = self:RegisterGuild(playerGuildName, playerGuildHomeRealm, guildClubId)

    -- Build guild tag based on guild number and ElvUI presence
    -- Use green color (|cff40FF40) to match native guild chat
    local guildNum = self:GetGuildNumber(playerGuildName, playerGuildHomeRealm)
    local guildTag = ""
    if guildNum then
        -- Multiple guilds with same name - show number to distinguish
        if self:HasElvUI() then
            guildTag = "|cff40FF40[G" .. guildNum .. "]|r "
        else
            guildTag = "|cff40FF40[Guild-" .. guildNum .. "]|r "
        end
    else
        -- Single guild or no number configured - show standard format
        if self:HasElvUI() then
            guildTag = "|cff40FF40[G]|r "
        else
            guildTag = "|cff40FF40[Guild]|r "
        end
    end

    local fullName = originName .. "-" .. originRealm
    local classColor = self:GetClassColor(originName, originRealm)
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff" .. classColor .. "[" .. originName .. "]|r|h"

    -- Store both formats: with guild tag (for "All" view) and without (for filtered view)
    -- Message text is also green to match guild chat
    local formattedWithTag = guildTag .. senderLink .. ": |cff40FF40" .. messageText .. "|r"
    local formattedNoTag = senderLink .. ": |cff40FF40" .. messageText .. "|r"

    -- If we have a target filter, the message should show under that guild's tab
    -- (since we're sending TO that guild), otherwise it's a broadcast to all guilds
    local displayFilterKey = targetFilter or filterKey

    -- When sending from "All" (no target filter), mark message to show in all tabs
    local showInAllTabs = (targetFilter == nil)

    table.insert(self.messageHistory, {
        guildName = playerGuildName,
        guildHomeRealm = playerGuildHomeRealm,
        filterKey = displayFilterKey,  -- Use target filter if set, or own guild
        showInAllTabs = showInAllTabs,  -- Flag for messages sent from "All"
        formatted = formattedWithTag,
        formattedNoTag = formattedNoTag,
    })
    if #self.messageHistory > 500 then
        table.remove(self.messageHistory, 1)
    end

    if self.scrollFrame then
        -- Messages sent from "All" show in all tabs; targeted messages only show in that tab
        if self.currentFilter == nil or displayFilterKey == self.currentFilter or showInAllTabs then
            -- Use format without tag when viewing a specific guild's tab
            local displayMsg = self.currentFilter and formattedNoTag or formattedWithTag
            self.scrollFrame:AddMessage(displayMsg)
        end
    end

    -- Record hash so we don't display it again when it comes back
    local hash = self:MakeMessageHash(playerGuildName or "", originName, originRealm, messageText)
    self:IsDuplicateMessage(hash)  -- This records the hash

    self:SendBridgePayload(originName, originRealm, messageText, "U", targetFilter, nil, nil, nil, nil, classFile)
    self:SendWhisperBridgePayload(originName, originRealm, messageText, "U", targetFilter, nil, nil, nil, nil, classFile)
end

-- Handle guild chat message (from own guild)
function GB:HandleGuildChatMessage(text, sender, _, _, _, _, _, _, _, _, _, guid)
    if not IsInGuild() then
        return
    end
    if not text or text == "" then
        return
    end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not self.allowedGuilds[myGuildName] then
        return
    end

    local originName, originRealm = sender:match("([^%-]+)%-?(.*)")
    originName = originName or sender
    if not originRealm or originRealm == "" then
        originRealm = GetRealmName()
    end

    -- Get class info from GUID if available
    local classFile = nil
    if guid then
        local _, playerClass = GetPlayerInfoByGUID(guid)
        classFile = playerClass
    end

    -- Get guild home realm (GM's realm) for proper identification
    local myGuildHomeRealm = self:GetGuildHomeRealm() or originRealm
    local myGuildClubId = getGuildClubId()

    -- Use guildName-guildClubId as filter key (clubId is required for registration)
    local filterKey = self:RegisterGuild(myGuildName, myGuildHomeRealm, myGuildClubId)

    -- Build guild tag based on guild number and ElvUI presence
    -- Use green color (|cff40FF40) to match native guild chat
    local guildNum = self:GetGuildNumber(myGuildName, myGuildHomeRealm)
    local guildTag = ""
    if guildNum then
        -- Multiple guilds with same name - show number to distinguish
        if self:HasElvUI() then
            guildTag = "|cff40FF40[G" .. guildNum .. "]|r "
        else
            guildTag = "|cff40FF40[Guild-" .. guildNum .. "]|r "
        end
    else
        -- Single guild or no number configured - show standard format
        if self:HasElvUI() then
            guildTag = "|cff40FF40[G]|r "
        else
            guildTag = "|cff40FF40[Guild]|r "
        end
    end

    local fullName = originName .. "-" .. originRealm

    -- Get class color
    local classColor = self:GetClassColor(originName, originRealm)

    -- Show realm in display name if different from player's realm
    local displayName = originName
    local myRealm = GetRealmName()
    if originRealm ~= myRealm then
        displayName = originName .. "-" .. originRealm
    end

    local senderLink = "|Hplayer:" .. fullName .. "|h|cff" .. classColor .. "[" .. displayName .. "]|r|h"

    -- Store both formats: with guild tag (for "All" view) and without (for filtered view)
    -- Message text is also green to match guild chat
    local formattedWithTag = guildTag .. senderLink .. ": |cff40FF40" .. text .. "|r"
    local formattedNoTag = senderLink .. ": |cff40FF40" .. text .. "|r"

    table.insert(self.messageHistory, {
        guildName = myGuildName,
        guildHomeRealm = myGuildHomeRealm,
        filterKey = filterKey,
        formatted = formattedWithTag,
        formattedNoTag = formattedNoTag,
    })
    if #self.messageHistory > 500 then
        table.remove(self.messageHistory, 1)
    end

    if self.scrollFrame and (self.currentFilter == nil or filterKey == self.currentFilter) then
        -- Use format without tag when viewing a specific guild's tab
        local displayMsg = self.currentFilter and formattedNoTag or formattedWithTag
        self.scrollFrame:AddMessage(displayMsg)
    end

    if not GuildBridgeDB.bridgeEnabled then
        return
    end

    if GuildBridgeDB.muteSend then
        local myName = UnitName("player")
        if originName == myName then
            return
        end
    end

    -- Check for duplicate before relaying
    local hash = self:MakeMessageHash(myGuildName, originName, originRealm, text)
    if self:IsDuplicateMessage(hash) then
        return
    end

    self:SendBridgePayload(originName, originRealm, text, "G", nil, nil, nil, nil, nil, classFile)
    self:SendWhisperBridgePayload(originName, originRealm, text, "G", nil, nil, nil, nil, nil, classFile)
end

-- Handle incoming BN addon message (bridge message from another player)
function GB:HandleBNAddonMessage(prefix, message, senderID)
    if prefix ~= self.BRIDGE_ADDON_PREFIX then
        return
    end

    -- Check for handshake messages first
    if self:HandleHandshakeMessage(message, senderID) then
        return
    end

    local text = message
    if not text or text:sub(1, #self.BRIDGE_PAYLOAD_PREFIX) ~= self.BRIDGE_PAYLOAD_PREFIX then
        return
    end

    local payload = text:sub(#self.BRIDGE_PAYLOAD_PREFIX + 1)
    local guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart

    -- New format with guildClubId: guildName|guildRealm|faction|originName|originRealm|sourceType|targetFilter|messageId|guildHomeRealm|classFile|guildClubId|message
    guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

    -- Fallback to format without guildClubId
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildClubIdPart = nil
    end

    -- Fallback to format without classFile
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        classFilePart = nil
        guildClubIdPart = nil
    end

    -- Fallback to old format without guildHomeRealm
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildHomeRealmPart = nil
        classFilePart = nil
        guildClubIdPart = nil
    end

    -- Fallback for even older format
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        messageIdPart = nil
        guildHomeRealmPart = nil
        classFilePart = nil
        guildClubIdPart = nil
    end

    if not messagePart or not originPart or not sourcePart then
        return
    end

    if guildPart == "" then guildPart = nil end
    if guildRealmPart == "" then guildRealmPart = nil end
    if originRealmPart == "" then originRealmPart = nil end
    if targetPart == "" then targetPart = nil end
    if messageIdPart == "" then messageIdPart = nil end
    if guildHomeRealmPart == "" then guildHomeRealmPart = nil end
    if classFilePart == "" then classFilePart = nil end
    if guildClubIdPart == "" then guildClubIdPart = nil end

    -- Fallback: use guild realm as home realm if not provided
    if not guildHomeRealmPart then
        guildHomeRealmPart = guildRealmPart
    end

    -- Only accept messages from allowed guilds
    if guildPart and not self.allowedGuilds[guildPart] then
        return
    end

    -- Check for duplicate message using hash (include guildHomeRealm for uniqueness)
    local hash = self:MakeMessageHash(guildPart or "", originPart, originRealmPart or "", messagePart)
    if self:IsDuplicateMessage(hash) then
        return
    end

    -- If message has a target filter, handle based on source type
    -- "G" (guild chat) messages with target: only accept if we're in that guild
    -- "U" (UI) messages with target: display in that guild's tab for everyone (cross-guild messaging)
    local displayInTargetTab = nil
    if targetPart and targetPart ~= "" then
        local myGuildName = GetGuildInfo("player")
        local myGuildClubId = getGuildClubId()
        local myGuildHomeRealm = self:GetGuildHomeRealm() or GetRealmName()
        -- Build possible filter keys (clubId-based or realm-based)
        local myFilterKeyClub = myGuildName and myGuildClubId and (myGuildName .. "-" .. myGuildClubId)
        local myFilterKeyRealm = myGuildName and myGuildHomeRealm and (myGuildName .. "-" .. myGuildHomeRealm)
        local isTargetedAtMe = (targetPart == myFilterKeyClub or targetPart == myFilterKeyRealm)

        if sourcePart == "U" then
            -- UI messages: display in the target guild's tab for everyone
            -- The message should appear under the targeted guild's tab, not the sender's guild
            displayInTargetTab = targetPart
        elseif not isTargetedAtMe then
            -- Guild chat messages targeted elsewhere - skip
            return
        end
    end

    -- Update connection status - receiving a message means they're connected
    self:UpdateConnectionFromMessage(senderID, guildPart, guildHomeRealmPart, guildRealmPart, guildClubIdPart)

    -- Display the message (pass guildHomeRealm, classFile, and guildClubId for proper filtering and coloring)
    -- If this is a UI message targeted to another guild, display under that guild's tab
    self:AddBridgeMessage(originPart, guildPart, factionPart, messagePart, originRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart, displayInTargetTab)

    -- Re-relay to other friends (mesh network) - only for guild chat messages ("G")
    -- Don't re-relay UI messages ("U") or already-relayed messages ("R")
    if GuildBridgeDB.bridgeEnabled and sourcePart == "G" then
        self:SendBridgePayload(originPart, originRealmPart, messagePart, "R", targetPart, messageIdPart, guildPart, guildRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart)
    end
end

-- Handle incoming whisper addon message (from same-account alts)
function GB:HandleWhisperAddonMessage(prefix, message, sender)
    if prefix ~= self.BRIDGE_ADDON_PREFIX then
        return
    end

    -- Check for whisper handshake messages first
    if self:HandleWhisperHandshakeMessage(message, sender) then
        return
    end

    local text = message
    if not text or text:sub(1, #self.BRIDGE_PAYLOAD_PREFIX) ~= self.BRIDGE_PAYLOAD_PREFIX then
        return
    end

    -- Parse payload (same format as BNet messages)
    local payload = text:sub(#self.BRIDGE_PAYLOAD_PREFIX + 1)
    local guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart

    -- New format with guildClubId
    guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

    -- Fallback formats (same as BNet handler)
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildClubIdPart = nil
    end

    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        classFilePart = nil
        guildClubIdPart = nil
    end

    if not messagePart or not originPart or not sourcePart then
        return
    end

    -- Clean up empty strings
    if guildPart == "" then guildPart = nil end
    if guildRealmPart == "" then guildRealmPart = nil end
    if originRealmPart == "" then originRealmPart = nil end
    if targetPart == "" then targetPart = nil end
    if messageIdPart == "" then messageIdPart = nil end
    if guildHomeRealmPart == "" then guildHomeRealmPart = nil end
    if classFilePart == "" then classFilePart = nil end
    if guildClubIdPart == "" then guildClubIdPart = nil end

    if not guildHomeRealmPart then
        guildHomeRealmPart = guildRealmPart
    end

    -- Only accept messages from allowed guilds
    if guildPart and not self.allowedGuilds[guildPart] then
        return
    end

    -- If message has a target filter, handle based on source type
    local displayInTargetTab = nil
    if targetPart and targetPart ~= "" then
        local myGuildName = GetGuildInfo("player")
        local myGuildClubId = getGuildClubId()
        local myGuildHomeRealm = self:GetGuildHomeRealm() or GetRealmName()
        -- Build possible filter keys (clubId-based or realm-based)
        local myFilterKeyClub = myGuildName and myGuildClubId and (myGuildName .. "-" .. myGuildClubId)
        local myFilterKeyRealm = myGuildName and myGuildHomeRealm and (myGuildName .. "-" .. myGuildHomeRealm)
        local isTargetedAtMe = (targetPart == myFilterKeyClub or targetPart == myFilterKeyRealm)

        if sourcePart == "U" then
            -- UI messages: display in the target guild's tab for everyone
            displayInTargetTab = targetPart
        elseif not isTargetedAtMe then
            -- Guild chat messages targeted elsewhere - skip
            return
        end
    end

    -- Check for duplicate
    local hash = self:MakeMessageHash(guildPart or "", originPart, originRealmPart or "", messagePart)
    if self:IsDuplicateMessage(hash) then
        return
    end

    -- Update whisper alt connection status
    if self.connectedWhisperAlts[sender] then
        self.connectedWhisperAlts[sender].lastSeen = GetTime()
    end

    -- Display the message
    self:AddBridgeMessage(originPart, guildPart, factionPart, messagePart, originRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart, displayInTargetTab)

    -- Re-relay to other friends and alts (mesh network) - only for guild chat messages ("G")
    if GuildBridgeDB.bridgeEnabled and sourcePart == "G" then
        self:SendBridgePayload(originPart, originRealmPart, messagePart, "R", targetPart, messageIdPart, guildPart, guildRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart)
        self:SendWhisperBridgePayload(originPart, originRealmPart, messagePart, "R", targetPart, messageIdPart, guildPart, guildRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart, sender)
    end
end

-- Refresh message display
function GB:RefreshMessages()
    if not self.scrollFrame then return end
    self.scrollFrame:Clear()

    -- If Status page is selected, show bridge connections only
    if self.currentPage == "status" then
        local myName = UnitName("player")
        local myGuildName = GetGuildInfo("player")
        local myGuildHomeRealm = self:GetGuildHomeRealm() or GetRealmName()
        local myShort = self.guildShortNames[myGuildName] or myGuildName or "No Guild"
        local now = GetTime()

        -- Collect connection pairs from BNet friends
        local connections = {}
        for gameAccountID, info in pairs(self.connectedBridgeUsers) do
            if now - info.lastSeen < 300 then
                -- Use stored character name, or fall back to "Unknown"
                local charName = info.characterName or "Unknown"
                local charRealm = info.characterRealm or info.realmName or ""
                local theirShort = self.guildShortNames[info.guildName] or info.guildName or ""
                table.insert(connections, {
                    charName = charName,
                    charRealm = charRealm,
                    guildName = info.guildName,
                    guildShort = theirShort,
                    guildHomeRealm = info.guildHomeRealm or info.realmName or "",
                    connectionType = "bnet",
                })
            end
        end

        -- Also collect connections from whisper alts (same Battle.net account)
        for altName, info in pairs(self.connectedWhisperAlts) do
            if now - info.lastSeen < 300 then
                local charName, charRealm = altName:match("([^%-]+)%-?(.*)")
                charName = charName or altName
                charRealm = charRealm or info.realmName or ""
                local theirShort = self.guildShortNames[info.guildName] or info.guildName or ""
                table.insert(connections, {
                    charName = charName,
                    charRealm = charRealm,
                    guildName = info.guildName,
                    guildShort = theirShort,
                    guildHomeRealm = info.guildHomeRealm or info.realmName or "",
                    connectionType = "whisper",
                })
            end
        end

        if #connections == 0 then
            self.scrollFrame:AddMessage("|cffff8888No bridge connections active.|r")
        else
            for _, conn in ipairs(connections) do
                local myRealmSuffix = myGuildHomeRealm and myGuildHomeRealm ~= "" and ("-" .. myGuildHomeRealm) or ""
                local theirRealmSuffix = conn.guildHomeRealm ~= "" and ("-" .. conn.guildHomeRealm) or ""

                local leftSide = "|cffffd700<" .. myShort .. myRealmSuffix .. ">|r |cff00ff00" .. myName .. "|r"
                local rightSide = "|cff00ff00" .. conn.charName .. "|r |cffffd700<" .. conn.guildShort .. theirRealmSuffix .. ">|r"

                -- Add indicator for whisper (same-account) connections
                local connIndicator = conn.connectionType == "whisper" and " |cffaaaaaa(alt)|r" or ""

                self.scrollFrame:AddMessage(leftSide .. "  |cff888888<-->|r  " .. rightSide .. connIndicator)
            end
        end

        return
    end

    -- Normal message display
    for _, msg in ipairs(self.messageHistory) do
        -- Show message if:
        -- 1. We're on "All" tab (currentFilter == nil), OR
        -- 2. Message's filterKey matches current tab, OR
        -- 3. Message was sent from "All" (showInAllTabs flag) - should show in every tab
        if self.currentFilter == nil or msg.filterKey == self.currentFilter or msg.showInAllTabs then
            -- Use format without guild tag when viewing a specific guild's tab
            local displayMsg = self.currentFilter and (msg.formattedNoTag or msg.formatted) or msg.formatted
            self.scrollFrame:AddMessage(displayMsg)
        end
    end
end
