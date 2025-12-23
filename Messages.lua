-- GuildBridge Messages Module
-- Handles message sending, receiving, and display

local addonName, GB = ...

-- Register a guild (for tracking discovered guilds)
function GB:RegisterGuild(guildName, guildHomeRealm)
    if not guildName then return end
    -- Use guildName-guildHomeRealm as the unique key to distinguish same-name guilds on different server clusters
    local filterKey = guildName
    if guildHomeRealm and guildHomeRealm ~= "" then
        filterKey = guildName .. "-" .. guildHomeRealm
    end
    if not self.knownGuilds[filterKey] then
        self.knownGuilds[filterKey] = {
            guildName = guildName,
            guildHomeRealm = guildHomeRealm,  -- GM's realm = guild's home server
            realmName = nil,  -- Display realm, can be set manually by user
            manualRealm = false,
        }
        GuildBridgeDB.knownGuilds = self.knownGuilds
        -- Rebuild tabs to show the new guild
        if self.RebuildTabs then
            self:RebuildTabs()
        end
    end
    return filterKey
end

-- Add a bridge message to the display
-- Now includes class color support and proper realm display for cross-realm invites
function GB:AddBridgeMessage(senderName, guildName, factionTag, messageText, senderRealm, guildHomeRealm, classFile)
    -- Use guildName-guildHomeRealm as the unique key to distinguish same-name guilds
    local filterKey = self:RegisterGuild(guildName, guildHomeRealm)

    local short = self.guildShortNames[guildName] or guildName or ""
    -- Get the manually set realm for display, or use guildHomeRealm
    local displayRealm = nil
    if self.knownGuilds[filterKey] and self.knownGuilds[filterKey].manualRealm then
        displayRealm = self.knownGuilds[filterKey].realmName
    elseif guildHomeRealm and guildHomeRealm ~= "" then
        displayRealm = guildHomeRealm
    end
    local realmSuffix = ""
    if displayRealm and displayRealm ~= "" then
        realmSuffix = "-" .. displayRealm
    end
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""

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

    local formattedMessage = guildTag .. senderLink .. ": " .. messageText

    -- Record activity for connection indicator
    self:RecordGuildActivity(filterKey)

    table.insert(self.messageHistory, {
        guildName = guildName,
        guildHomeRealm = guildHomeRealm,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #self.messageHistory > 500 then
        table.remove(self.messageHistory, 1)
    end

    if self.scrollFrame and self.currentPage == "chat" and (self.currentFilter == nil or filterKey == self.currentFilter) then
        self.scrollFrame:AddMessage(formattedMessage)
    end

    -- Only show in native chat if filter is off, or if message matches the current filter
    if not GuildBridgeDB.filterNativeChat or self.currentFilter == nil or filterKey == self.currentFilter then
        DEFAULT_CHAT_FRAME:AddMessage(formattedMessage, 0.25, 1.0, 0.25)
    end
end

-- Send bridge payload to all online friends
function GB:SendBridgePayload(originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile)
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

    sourceType = sourceType or "U"

    local guildName = overrideGuild or GetGuildInfo("player")
    local guildRealm = overrideGuildRealm or GetRealmName()
    local guildHomeRealm = overrideGuildHomeRealm or self:GetGuildHomeRealm() or guildRealm
    local factionGroup = select(1, UnitFactionGroup("player")) or "Unknown"

    -- Generate message ID for deduplication if not provided
    if not messageId or messageId == "" then
        messageId = guildHomeRealm .. "-" .. originName .. "-" .. GetTime()
    end

    -- Payload format: [GB]guildName|guildRealm|faction|originName|originRealm|sourceType|targetFilter|messageId|guildHomeRealm|classFile|message
    local payload = self.BRIDGE_PAYLOAD_PREFIX
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
        .. messageText

    -- Send to all online WoW friends
    for _, friend in ipairs(self.onlineFriends) do
        local ok, err = pcall(BNSendGameData, friend.gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
        if not ok then
            print("GuildBridge: error sending to", friend.characterName or "unknown", ":", err)
        end
    end
end

-- Send message from UI input
function GB:SendFromUI(messageText)
    if not messageText or messageText == "" then
        return
    end

    local targetFilter = self.currentFilter

    local originName, originRealm = UnitName("player")
    if not originRealm or originRealm == "" then
        originRealm = GetRealmName()
    end
    local playerGuildName = GetGuildInfo("player")
    local playerGuildHomeRealm = self:GetGuildHomeRealm() or originRealm

    -- Get player's class for coloring
    local _, classFile = UnitClass("player")

    -- Use guildName-guildHomeRealm as filter key
    local filterKey = self:RegisterGuild(playerGuildName, playerGuildHomeRealm)

    local short = self.guildShortNames[playerGuildName] or playerGuildName or ""
    -- Get the manually set realm for display, or use guildHomeRealm
    local displayRealm = nil
    if self.knownGuilds[filterKey] and self.knownGuilds[filterKey].manualRealm then
        displayRealm = self.knownGuilds[filterKey].realmName
    else
        displayRealm = playerGuildHomeRealm
    end
    local realmSuffix = displayRealm and displayRealm ~= "" and ("-" .. displayRealm) or ""
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""

    local fullName = originName .. "-" .. originRealm
    local classColor = self:GetClassColor(originName, originRealm)
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff" .. classColor .. "[" .. originName .. "]|r|h"
    local formattedMessage = guildTag .. senderLink .. ": " .. messageText

    table.insert(self.messageHistory, {
        guildName = playerGuildName,
        guildHomeRealm = playerGuildHomeRealm,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #self.messageHistory > 500 then
        table.remove(self.messageHistory, 1)
    end

    if self.scrollFrame and (self.currentFilter == nil or filterKey == self.currentFilter) then
        self.scrollFrame:AddMessage(formattedMessage)
    end

    -- Record hash so we don't display it again when it comes back
    local hash = self:MakeMessageHash(playerGuildName or "", originName, originRealm, messageText)
    self:IsDuplicateMessage(hash)  -- This records the hash

    self:SendBridgePayload(originName, originRealm, messageText, "U", targetFilter, nil, nil, nil, nil, classFile)
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

    -- Use guildName-guildHomeRealm as filter key
    local filterKey = self:RegisterGuild(myGuildName, myGuildHomeRealm)

    local short = self.guildShortNames[myGuildName] or myGuildName or ""
    -- Get the manually set realm for display, or use guildHomeRealm
    local displayRealm = nil
    if self.knownGuilds[filterKey] and self.knownGuilds[filterKey].manualRealm then
        displayRealm = self.knownGuilds[filterKey].realmName
    else
        displayRealm = myGuildHomeRealm
    end
    local realmSuffix = displayRealm and displayRealm ~= "" and ("-" .. displayRealm) or ""
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""

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
    local formattedMessage = guildTag .. senderLink .. ": " .. text

    table.insert(self.messageHistory, {
        guildName = myGuildName,
        guildHomeRealm = myGuildHomeRealm,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #self.messageHistory > 500 then
        table.remove(self.messageHistory, 1)
    end

    if self.scrollFrame and (self.currentFilter == nil or filterKey == self.currentFilter) then
        self.scrollFrame:AddMessage(formattedMessage)
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
    local guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, messagePart

    -- New format with classFile: guildName|guildRealm|faction|originName|originRealm|sourceType|targetFilter|messageId|guildHomeRealm|classFile|message
    guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

    -- Fallback to format without classFile
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        classFilePart = nil
    end

    -- Fallback to old format without guildHomeRealm
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildHomeRealmPart = nil
        classFilePart = nil
    end

    -- Fallback for even older format
    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        messageIdPart = nil
        guildHomeRealmPart = nil
        classFilePart = nil
    end

    if not messagePart then
        guildPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildRealmPart = originRealmPart
        messageIdPart = nil
        guildHomeRealmPart = nil
        classFilePart = nil
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

    -- If message has a target filter, only process if we match
    if targetPart and targetPart ~= "" then
        local myGuildName = GetGuildInfo("player")
        local myGuildHomeRealm = self:GetGuildHomeRealm() or GetRealmName()
        local myFilterKey = myGuildName
        if myGuildHomeRealm and myGuildHomeRealm ~= "" then
            myFilterKey = myGuildName .. "-" .. myGuildHomeRealm
        end
        if myFilterKey ~= targetPart then
            return
        end
    end

    -- Display the message (pass guildHomeRealm and classFile for proper filtering and coloring)
    self:AddBridgeMessage(originPart, guildPart, factionPart, messagePart, originRealmPart, guildHomeRealmPart, classFilePart)

    -- Re-relay to other friends (mesh network) - but NOT if this came from guild chat
    -- Only re-relay if sourceType is not "G" (guild originated)
    if GuildBridgeDB.bridgeEnabled and sourcePart ~= "G" then
        self:SendBridgePayload(originPart, originRealmPart, messagePart, sourcePart, targetPart, messageIdPart, guildPart, guildRealmPart, guildHomeRealmPart, classFilePart)
    end
end

-- Refresh message display
function GB:RefreshMessages()
    if not self.scrollFrame then return end
    self.scrollFrame:Clear()

    -- If Status page is selected, show connection pairs
    if self.currentPage == "status" then
        self.scrollFrame:AddMessage("|cff88ffffBridge Connections:|r")
        self.scrollFrame:AddMessage("")

        -- Get my info
        local myName = UnitName("player")
        local myGuildName = GetGuildInfo("player")
        local myGuildHomeRealm = self:GetGuildHomeRealm() or GetRealmName()
        local myShort = self.guildShortNames[myGuildName] or myGuildName or "No Guild"

        -- Collect connection pairs
        local connections = {}
        local now = GetTime()
        for gameAccountID, info in pairs(self.connectedBridgeUsers) do
            if now - info.lastSeen < 300 then
                -- Find character name from onlineFriends
                local charName = "Unknown"
                local charRealm = info.realmName or ""
                for _, friend in ipairs(self.onlineFriends) do
                    if friend.gameAccountID == gameAccountID then
                        charName = friend.characterName or "Unknown"
                        charRealm = friend.realmName or info.realmName or ""
                        break
                    end
                end
                local theirShort = self.guildShortNames[info.guildName] or info.guildName or ""
                table.insert(connections, {
                    charName = charName,
                    charRealm = charRealm,
                    guildName = info.guildName,
                    guildShort = theirShort,
                    guildHomeRealm = info.guildHomeRealm or info.realmName or "",
                })
            end
        end

        if #connections == 0 then
            self.scrollFrame:AddMessage("|cffff8888No bridge connections active.|r")
        else
            for _, conn in ipairs(connections) do
                local myRealmSuffix = myGuildHomeRealm and myGuildHomeRealm ~= "" and ("-" .. myGuildHomeRealm) or ""
                local theirRealmSuffix = conn.guildHomeRealm ~= "" and ("-" .. conn.guildHomeRealm) or ""

                -- Format: <MyGuild-GuildHomeRealm> MyChar  <-->  TheirChar <TheirGuild-GuildHomeRealm>
                local leftSide = "|cffffd700<" .. myShort .. myRealmSuffix .. ">|r |cff00ff00" .. myName .. "|r"
                local rightSide = "|cff00ff00" .. conn.charName .. "|r |cffffd700<" .. conn.guildShort .. theirRealmSuffix .. ">|r"

                self.scrollFrame:AddMessage(leftSide .. "  |cff888888<-->|r  " .. rightSide)
            end
        end
        return
    end

    -- Normal message display
    for _, msg in ipairs(self.messageHistory) do
        if self.currentFilter == nil or msg.filterKey == self.currentFilter then
            self.scrollFrame:AddMessage(msg.formatted)
        end
    end
end
