local addonName, GB = ...

local function SetupGuildLinkHook()
    local originalSetItemRef = SetItemRef
    SetItemRef = function(link, text, button, chatFrame)
        if link and link:match("^channel:GUILDBRIDGE") then
            if button == "RightButton" then
                return originalSetItemRef("channel:GUILD", text, button, chatFrame)
            elseif button == "LeftButton" then
                ChatFrame_OpenChat("/g ", chatFrame)
                return
            end
            return
        end
        return originalSetItemRef(link, text, button, chatFrame)
    end
end

SetupGuildLinkHook()

local function getGuildClubId()
    if C_Club and C_Club.GetGuildClubId then
        return C_Club.GetGuildClubId()
    end
    return nil
end

function GB:RegisterGuild(guildName, guildHomeRealm, guildClubId)
    if not guildName then return nil end

    if guildClubId == "" then guildClubId = nil end
    if guildHomeRealm == "" then guildHomeRealm = nil end

    if not guildClubId then return nil end

    local filterKey = guildName .. "-" .. guildClubId

    local isNewGuild = not self.knownGuilds[filterKey]

    if isNewGuild then
        self.knownGuilds[filterKey] = {
            guildName = guildName,
            guildHomeRealm = guildHomeRealm,
            guildClubId = guildClubId,
            realmName = nil,
            manualRealm = false,
        }
        MNetDB.knownGuilds = self.knownGuilds

        local tempKey = "Unknown-" .. guildClubId
        if self.guildRosters[tempKey] then
            self.guildRosters[filterKey] = self.guildRosters[tempKey]
            self.guildRosters[tempKey] = nil
        end

        if self.RebuildTabs then
            self:RebuildTabs()
        end

        if self.RefreshRoster then
            self:RefreshRoster()
        end
    elseif guildHomeRealm and not self.knownGuilds[filterKey].guildHomeRealm then
        self.knownGuilds[filterKey].guildHomeRealm = guildHomeRealm
        MNetDB.knownGuilds = self.knownGuilds
    end

    return filterKey
end

function GB:AddBridgeMessage(senderName, guildName, factionTag, messageText, senderRealm, guildHomeRealm, classFile, guildClubId, displayInTargetTab)
    local filterKey = self:RegisterGuild(guildName, guildHomeRealm, guildClubId)

    local displayFilterKey = filterKey
    if displayInTargetTab then
        local targetGuildName = displayInTargetTab:match("^(.+)%-[^%-]+$")
        if targetGuildName then
            for localFilterKey, info in pairs(self.knownGuilds) do
                if info.guildName == targetGuildName then
                    displayFilterKey = localFilterKey
                    break
                end
            end
        end
        if displayFilterKey == filterKey and displayInTargetTab ~= filterKey then
            displayFilterKey = displayInTargetTab
        end
    end

    local guildNum = self:GetGuildNumber(guildName, guildHomeRealm)
    local guildTag = ""
    if guildNum then
        if self:HasElvUI() then
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[G" .. guildNum .. "]|r|h "
        else
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[Guild-" .. guildNum .. "]|r|h "
        end
    else
        if self:HasElvUI() then
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[G]|r|h "
        else
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[Guild]|r|h "
        end
    end

    local fullName = senderName
    if senderRealm and senderRealm ~= "" then
        fullName = senderName .. "-" .. senderRealm
    end

    local classColor = self:GetClassColorFromCache(senderName, senderRealm, guildName, classFile)

    local displayName = senderName
    local myRealm = GetRealmName()
    if senderRealm and senderRealm ~= "" and senderRealm ~= myRealm then
        displayName = senderName .. "-" .. senderRealm
    end

    local senderLink = "|Hplayer:" .. fullName .. "|h|cff" .. classColor .. "[" .. displayName .. "]|r|h"

    local formattedWithTag = guildTag .. senderLink .. ": |cff40FF40" .. messageText .. "|r"
    local formattedNoTag = senderLink .. ": |cff40FF40" .. messageText .. "|r"

    self:RecordGuildActivity(displayFilterKey)

    table.insert(self.messageHistory, {
        guildName = guildName,
        guildHomeRealm = guildHomeRealm,
        filterKey = displayFilterKey,
        formatted = formattedWithTag,
        formattedNoTag = formattedNoTag,
    })
    if #self.messageHistory > 500 then
        table.remove(self.messageHistory, 1)
    end

    if self.scrollFrame and self.currentPage == "chat" and (self.currentFilter == nil or displayFilterKey == self.currentFilter) then
        local displayMsg = self.currentFilter and formattedNoTag or formattedWithTag
        self.scrollFrame:AddMessage(displayMsg)
    end

    local myGuildName = GetGuildInfo("player")
    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local myGuildHomeRealm = self:GetGuildHomeRealm()

    local myFilterKey = nil
    if myGuildName then
        if myGuildClubId then
            myFilterKey = myGuildName .. "-" .. myGuildClubId
        elseif myGuildHomeRealm then
            myFilterKey = myGuildName .. "-" .. myGuildHomeRealm
        end
    end

    local showInNativeChat = false
    if displayInTargetTab then
        showInNativeChat = myFilterKey and displayInTargetTab == myFilterKey
    else
        showInNativeChat = myGuildName and self.allowedGuilds[myGuildName]
    end

    if showInNativeChat then
        if not MNetDB.muteSend then
            if not MNetDB.filterNativeChat or self.currentFilter == nil or displayFilterKey == self.currentFilter then
                self:AddMessageToGuildChatFrames(formattedWithTag, 0.25, 1.0, 0.25)
            end
        end
    end
end

local function buildBridgePayload(GB, originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile, overrideGuildClubId)
    sourceType = sourceType or "U"

    local guildName = overrideGuild or GetGuildInfo("player")
    local guildRealm = overrideGuildRealm or GetRealmName()
    local guildHomeRealm = overrideGuildHomeRealm or GB:GetGuildHomeRealm() or guildRealm
    local guildClubId = overrideGuildClubId or getGuildClubId()
    local factionGroup = select(1, UnitFactionGroup("player")) or "Unknown"

    if not messageId or messageId == "" then
        messageId = guildHomeRealm .. "-" .. originName .. "-" .. GetTime()
    end

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

function GB:SendBridgePayload(originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile, overrideGuildClubId)
    if not messageText or messageText == "" then
        return
    end

    if #self.onlineFriends == 0 then
        self.onlineFriends = self:FindOnlineWoWFriends()
    end

    if #self.onlineFriends == 0 then
        return
    end

    local payload = buildBridgePayload(self, originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile, overrideGuildClubId)

    local myGuildClubId = getGuildClubId()

    local myGuildName = GetGuildInfo("player")

    for _, friend in ipairs(self.onlineFriends) do
        local shouldSend = false
        local connInfo = self.connectedBridgeUsers[friend.gameAccountID]

        if connInfo then
            shouldSend = true
            if sourceType == "G" and myGuildClubId and connInfo.guildClubId == myGuildClubId then
                shouldSend = false
            end
        elseif friend.guildName and self.allowedGuilds[friend.guildName] then
            shouldSend = true
            if sourceType == "G" and friend.guildName == myGuildName then
                shouldSend = false
            end
        end

        if shouldSend then
            self:QueueBNetMessage(friend.gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
        end
    end
end

function GB:SendWhisperBridgePayload(originName, originRealm, messageText, sourceType, targetFilter, messageId, overrideGuild, overrideGuildRealm, overrideGuildHomeRealm, classFile, overrideGuildClubId, excludeSender)
    if not messageText or messageText == "" then
        return
    end

    local myGuildClubId = getGuildClubId()

    local now = GetTime()
    local hasAlts = false
    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 300 and altName ~= excludeSender then
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

    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 300 and altName ~= excludeSender then
            if not info.guildName or not self.allowedGuilds[info.guildName] then
            else
                local shouldSend = true
                if sourceType == "G" and myGuildClubId and info.guildClubId == myGuildClubId then
                    shouldSend = false
                end
                if shouldSend then
                    self:QueueWhisperMessage(self.BRIDGE_ADDON_PREFIX, payload, altName)
                end
            end
        end
    end
end

function GB:SendFromUI(messageText)
    if not messageText or messageText == "" then
        return
    end

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

    local _, classFile = UnitClass("player")

    local filterKey = self:RegisterGuild(playerGuildName, playerGuildHomeRealm, guildClubId)

    local guildNum = self:GetGuildNumber(playerGuildName, playerGuildHomeRealm)
    local guildTag = ""
    if guildNum then
        if self:HasElvUI() then
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[G" .. guildNum .. "]|r|h "
        else
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[Guild-" .. guildNum .. "]|r|h "
        end
    else
        if self:HasElvUI() then
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[G]|r|h "
        else
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[Guild]|r|h "
        end
    end

    local fullName = originName .. "-" .. originRealm
    local classColor = self:GetClassColor(originName, originRealm)
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff" .. classColor .. "[" .. originName .. "]|r|h"

    local formattedWithTag = guildTag .. senderLink .. ": |cff40FF40" .. messageText .. "|r"
    local formattedNoTag = senderLink .. ": |cff40FF40" .. messageText .. "|r"

    local displayFilterKey = targetFilter or filterKey

    local showInAllTabs = (targetFilter == nil)

    table.insert(self.messageHistory, {
        guildName = playerGuildName,
        guildHomeRealm = playerGuildHomeRealm,
        filterKey = displayFilterKey,
        showInAllTabs = showInAllTabs,
        formatted = formattedWithTag,
        formattedNoTag = formattedNoTag,
    })
    if #self.messageHistory > 500 then
        table.remove(self.messageHistory, 1)
    end

    if self.scrollFrame then
        if self.currentFilter == nil or displayFilterKey == self.currentFilter or showInAllTabs then
            local displayMsg = self.currentFilter and formattedNoTag or formattedWithTag
            self.scrollFrame:AddMessage(displayMsg)
        end
    end

    local hash = self:MakeMessageHash(playerGuildName or "", originName, originRealm, messageText)
    self:IsDuplicateMessage(hash)

    self:SendBridgePayload(originName, originRealm, messageText, "U", targetFilter, nil, nil, nil, nil, classFile)
    self:SendWhisperBridgePayload(originName, originRealm, messageText, "U", targetFilter, nil, nil, nil, nil, classFile)
end

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

    local classFile = nil
    if guid then
        local _, playerClass = GetPlayerInfoByGUID(guid)
        classFile = playerClass
    end

    local myGuildHomeRealm = self:GetGuildHomeRealm() or originRealm
    local myGuildClubId = getGuildClubId()

    local filterKey = self:RegisterGuild(myGuildName, myGuildHomeRealm, myGuildClubId)

    local guildNum = self:GetGuildNumber(myGuildName, myGuildHomeRealm)
    local guildTag = ""
    if guildNum then
        if self:HasElvUI() then
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[G" .. guildNum .. "]|r|h "
        else
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[Guild-" .. guildNum .. "]|r|h "
        end
    else
        if self:HasElvUI() then
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[G]|r|h "
        else
            guildTag = "|Hchannel:GUILDBRIDGE|h|cff40FF40[Guild]|r|h "
        end
    end

    local fullName = originName .. "-" .. originRealm

    local classColor = self:GetClassColor(originName, originRealm)

    local displayName = originName
    local myRealm = GetRealmName()
    if originRealm ~= myRealm then
        displayName = originName .. "-" .. originRealm
    end

    local senderLink = "|Hplayer:" .. fullName .. "|h|cff" .. classColor .. "[" .. displayName .. "]|r|h"

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
        local displayMsg = self.currentFilter and formattedNoTag or formattedWithTag
        self.scrollFrame:AddMessage(displayMsg)
    end

    if not MNetDB.bridgeEnabled then
        return
    end

    if MNetDB.muteSend then
        local myName = UnitName("player")
        if originName == myName then
            return
        end
    end

    local hash = self:MakeMessageHash(myGuildName, originName, originRealm, text)
    if self:IsDuplicateMessage(hash) then
        return
    end

    self:SendBridgePayload(originName, originRealm, text, "G", nil, nil, nil, nil, nil, classFile)
    self:SendWhisperBridgePayload(originName, originRealm, text, "G", nil, nil, nil, nil, nil, classFile)
end

function GB:HandleBNAddonMessage(prefix, message, senderID)
    if prefix ~= self.BRIDGE_ADDON_PREFIX then
        return
    end

    if self:HandleHandshakeMessage(message, senderID) then
        return
    end

    if message:sub(1, 6) == "[GBRF]" then
        if self.HandleRosterFullMessage then
            self:HandleRosterFullMessage(message:sub(7), senderID, "bnet")
        end
        return
    elseif message:sub(1, 6) == "[GBRD]" then
        if self.HandleRosterDeltaMessage then
            self:HandleRosterDeltaMessage(message:sub(7), senderID, "bnet")
        end
        return
    elseif message:sub(1, 6) == "[GBRR]" then
        if self.HandleRosterRequest then
            self:HandleRosterRequest(message:sub(7), senderID, "bnet")
        end
        return
    elseif message:sub(1, 6) == "[GBPY]" then
        return
    end

    local text = message
    if not text or text:sub(1, #self.BRIDGE_PAYLOAD_PREFIX) ~= self.BRIDGE_PAYLOAD_PREFIX then
        return
    end

    local payload = text:sub(#self.BRIDGE_PAYLOAD_PREFIX + 1)
    local guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart

    guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

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

    if not messagePart then
        guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildHomeRealmPart = nil
        classFilePart = nil
        guildClubIdPart = nil
    end

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

    if not guildHomeRealmPart then
        guildHomeRealmPart = guildRealmPart
    end

    if guildPart and not self.allowedGuilds[guildPart] then
        return
    end

    local hash = self:MakeMessageHash(guildPart or "", originPart, originRealmPart or "", messagePart)
    if self:IsDuplicateMessage(hash) then
        return
    end

    local displayInTargetTab = nil
    if targetPart and targetPart ~= "" then
        local myGuildName = GetGuildInfo("player")
        local myGuildClubId = getGuildClubId()
        local myGuildHomeRealm = self:GetGuildHomeRealm() or GetRealmName()
        local myFilterKeyClub = myGuildName and myGuildClubId and (myGuildName .. "-" .. myGuildClubId)
        local myFilterKeyRealm = myGuildName and myGuildHomeRealm and (myGuildName .. "-" .. myGuildHomeRealm)
        local isTargetedAtMe = (targetPart == myFilterKeyClub or targetPart == myFilterKeyRealm)

        if sourcePart == "U" then
            displayInTargetTab = targetPart
        elseif not isTargetedAtMe then
            return
        end
    end

    self:UpdateConnectionFromMessage(senderID, guildPart, guildHomeRealmPart, guildRealmPart, guildClubIdPart)

    self:AddBridgeMessage(originPart, guildPart, factionPart, messagePart, originRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart, displayInTargetTab)

    if MNetDB.bridgeEnabled and sourcePart == "G" then
        self:RelayToOtherGuilds(originPart, originRealmPart, messagePart, targetPart, messageIdPart, guildPart, guildRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart)
    end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if MNetDB.bridgeEnabled and guildClubIdPart and myGuildClubId and tostring(guildClubIdPart) ~= tostring(myGuildClubId) then
        self:RelayToGuildmates(payload, guildClubIdPart)
    end
end

function GB:RelayToOtherGuilds(originName, originRealm, messageText, targetFilter, messageId, originGuild, originGuildRealm, originGuildHomeRealm, classFile, originGuildClubId)
    if not messageText or messageText == "" then
        return
    end

    local payload = buildBridgePayload(self, originName, originRealm, messageText, "R", targetFilter, messageId, originGuild, originGuildRealm, originGuildHomeRealm, classFile, originGuildClubId)

    for _, friend in ipairs(self.onlineFriends) do
        local connInfo = self.connectedBridgeUsers[friend.gameAccountID]
        local friendGuildName = connInfo and connInfo.guildName or friend.guildName

        if friendGuildName and friendGuildName ~= originGuild then
            if connInfo or (friend.guildName and self.allowedGuilds[friend.guildName]) then
                self:QueueBNetMessage(friend.gameAccountID, self.BRIDGE_ADDON_PREFIX, payload)
            end
        end
    end

    local now = GetTime()
    for altName, info in pairs(self.connectedWhisperAlts) do
        if now - info.lastSeen < 300 then
            if info.guildName and info.guildName ~= originGuild and self.allowedGuilds[info.guildName] then
                self:QueueWhisperMessage(self.BRIDGE_ADDON_PREFIX, payload, altName)
            end
        end
    end
end

function GB:HandleWhisperAddonMessage(prefix, message, sender)
    if prefix ~= self.BRIDGE_ADDON_PREFIX then
        return
    end

    if self:HandleWhisperHandshakeMessage(message, sender) then
        return
    end

    if message:sub(1, 6) == "[GBRF]" then
        if self.HandleRosterFullMessage then
            self:HandleRosterFullMessage(message:sub(7), sender, "whisper")
        end
        return
    elseif message:sub(1, 6) == "[GBRD]" then
        if self.HandleRosterDeltaMessage then
            self:HandleRosterDeltaMessage(message:sub(7), sender, "whisper")
        end
        return
    elseif message:sub(1, 6) == "[GBRR]" then
        if self.HandleRosterRequest then
            self:HandleRosterRequest(message:sub(7), sender, "whisper")
        end
        return
    elseif message:sub(1, 6) == "[GBPY]" then
        return
    end

    local text = message
    if not text or text:sub(1, #self.BRIDGE_PAYLOAD_PREFIX) ~= self.BRIDGE_PAYLOAD_PREFIX then
        return
    end

    local payload = text:sub(#self.BRIDGE_PAYLOAD_PREFIX + 1)
    local guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart

    guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

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

    if guildPart and not self.allowedGuilds[guildPart] then
        return
    end

    local displayInTargetTab = nil
    if targetPart and targetPart ~= "" then
        local myGuildName = GetGuildInfo("player")
        local myGuildClubId = getGuildClubId()
        local myGuildHomeRealm = self:GetGuildHomeRealm() or GetRealmName()
        local myFilterKeyClub = myGuildName and myGuildClubId and (myGuildName .. "-" .. myGuildClubId)
        local myFilterKeyRealm = myGuildName and myGuildHomeRealm and (myGuildName .. "-" .. myGuildHomeRealm)
        local isTargetedAtMe = (targetPart == myFilterKeyClub or targetPart == myFilterKeyRealm)

        if sourcePart == "U" then
            displayInTargetTab = targetPart
        elseif not isTargetedAtMe then
            return
        end
    end

    local hash = self:MakeMessageHash(guildPart or "", originPart, originRealmPart or "", messagePart)
    if self:IsDuplicateMessage(hash) then
        return
    end

    if self.connectedWhisperAlts[sender] then
        self.connectedWhisperAlts[sender].lastSeen = GetTime()
    end

    self:AddBridgeMessage(originPart, guildPart, factionPart, messagePart, originRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart, displayInTargetTab)

    if MNetDB.bridgeEnabled and sourcePart == "G" then
        self:RelayToOtherGuilds(originPart, originRealmPart, messagePart, targetPart, messageIdPart, guildPart, guildRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart)
    end

    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if MNetDB.bridgeEnabled and guildClubIdPart and myGuildClubId and tostring(guildClubIdPart) ~= tostring(myGuildClubId) then
        self:RelayToGuildmates(payload, guildClubIdPart)
    end
end

function GB:RefreshMessages()
    if not self.scrollFrame then return end
    self.scrollFrame:Clear()

    if self.currentPage == "status" then
        local myName = UnitName("player")
        local myGuildName = GetGuildInfo("player")
        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        local myGuildHomeRealm = self:GetGuildHomeRealm() or GetRealmName()
        local myShort = self.guildShortNames[myGuildName] or myGuildName or "No Guild"
        local now = GetTime()

        self.scrollFrame:AddMessage("|cffffd700My Guild:|r " .. (myGuildName or "None") .. " |cff888888(ID: " .. tostring(myGuildClubId or "nil") .. ")|r")
        self.scrollFrame:AddMessage("")

        local connections = {}
        local seenGuildIds = {}
        local debugTotal = 0
        local debugSameGuild = 0
        local debugStale = 0

        for gameAccountID, info in pairs(self.connectedBridgeUsers) do
            debugTotal = debugTotal + 1
            local age = now - info.lastSeen

            if age >= 300 then
                debugStale = debugStale + 1
            elseif info.guildClubId and myGuildClubId and tostring(info.guildClubId) == tostring(myGuildClubId) then
                debugSameGuild = debugSameGuild + 1
            else
                local charName = info.characterName or "Unknown"
                local charRealm = info.characterRealm or info.realmName or ""
                local theirShort = self.guildShortNames[info.guildName] or info.guildName or ""
                table.insert(connections, {
                    charName = charName,
                    charRealm = charRealm,
                    guildName = info.guildName,
                    guildShort = theirShort,
                    guildHomeRealm = info.guildHomeRealm or info.realmName or "",
                    guildClubId = info.guildClubId,
                    connectionType = "bnet",
                })
                if info.guildClubId then
                    seenGuildIds[tostring(info.guildClubId)] = {
                        guildName = info.guildName,
                        guildHomeRealm = info.guildHomeRealm,
                    }
                end
            end
        end

        for altName, info in pairs(self.connectedWhisperAlts) do
            if now - info.lastSeen < 300 then
                if not info.guildClubId or not myGuildClubId or tostring(info.guildClubId) ~= tostring(myGuildClubId) then
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
                        guildClubId = info.guildClubId,
                        connectionType = "whisper",
                    })
                    if info.guildClubId then
                        seenGuildIds[tostring(info.guildClubId)] = {
                            guildName = info.guildName,
                            guildHomeRealm = info.guildHomeRealm,
                        }
                    end
                end
            end
        end

        for senderName, info in pairs(self.guildRelayBridges) do
            if now - info.lastSeen < 300 and info.guilds then
                for guildClubIdStr, _ in pairs(info.guilds) do
                    if not myGuildClubId or tostring(guildClubIdStr) ~= tostring(myGuildClubId) then
                        local guildName, guildHomeRealm = self:LookupGuildInfoByClubId(guildClubIdStr, senderName, "guild")
                        if guildName then
                            local charName, charRealm = senderName:match("([^%-]+)%-?(.*)")
                            charName = charName or senderName
                            charRealm = charRealm ~= "" and charRealm or ""
                            local theirShort = self.guildShortNames[guildName] or guildName or ""
                            table.insert(connections, {
                                charName = charName,
                                charRealm = charRealm,
                                guildName = guildName,
                                guildShort = theirShort,
                                guildHomeRealm = guildHomeRealm or "",
                                guildClubId = guildClubIdStr,
                                connectionType = "guild-relay",
                            })
                            seenGuildIds[guildClubIdStr] = {
                                guildName = guildName,
                                guildHomeRealm = guildHomeRealm,
                            }
                        end
                    end
                end
            end
        end

        if #connections == 0 then
            self.scrollFrame:AddMessage("|cffff8888No cross-guild bridge connections active.|r")
            if debugTotal > 0 then
                self.scrollFrame:AddMessage("|cff888888(Total: " .. debugTotal .. ", Same Guild: " .. debugSameGuild .. ", Stale: " .. debugStale .. ")|r")
            end
        else
            self.scrollFrame:AddMessage("|cffffd700Connected Guilds:|r")
            for guildIdStr, guildInfo in pairs(seenGuildIds) do
                local guildDisplay = guildInfo.guildName or "Unknown"
                if guildInfo.guildHomeRealm then
                    guildDisplay = guildDisplay .. "-" .. guildInfo.guildHomeRealm
                end
                self.scrollFrame:AddMessage("  |cff00ff00" .. guildDisplay .. "|r |cff888888(ID: " .. guildIdStr .. ")|r")
            end
            self.scrollFrame:AddMessage("")

            self.scrollFrame:AddMessage("|cffffd700Connections:|r")
            for _, conn in ipairs(connections) do
                local connIndicator = ""
                if conn.connectionType == "whisper" then
                    connIndicator = " |cffaaaaaa(alt)|r"
                elseif conn.connectionType == "guild-relay" then
                    connIndicator = " |cffaaaaaa(guild relay)|r"
                end

                local charDisplay = conn.charName
                if conn.charRealm and conn.charRealm ~= "" then
                    charDisplay = charDisplay .. "-" .. conn.charRealm
                end

                self.scrollFrame:AddMessage("  |cff00ff00" .. charDisplay .. "|r in |cffffd700<" .. conn.guildShort .. ">|r" .. connIndicator)
            end
        end

        if self.updateScrollBar then
            self.updateScrollBar()
        end
        return
    end

    for _, msg in ipairs(self.messageHistory) do
        if self.currentFilter == nil or msg.filterKey == self.currentFilter or msg.showInAllTabs then
            local displayMsg = self.currentFilter and (msg.formattedNoTag or msg.formatted) or msg.formatted
            self.scrollFrame:AddMessage(displayMsg)
        end
    end

    if self.updateScrollBar then
        self.updateScrollBar()
    end
end

function GB:IsRecentGuildRelay(hash)
    local now = GetTime()
    for h, timestamp in pairs(self.recentGuildRelays) do
        if now - timestamp > self.MESSAGE_DEDUPE_WINDOW then
            self.recentGuildRelays[h] = nil
        end
    end

    if self.recentGuildRelays[hash] then
        return true
    end
    self.recentGuildRelays[hash] = now
    return false
end

function GB:RelayToGuildmates(payload, sourceGuildClubId)
    if not IsInGuild() then return end

    if not MNetDB.bridgeEnabled or not MNetDB.enableGuildRelay then return end

    if sourceGuildClubId and not self:AmIPrimaryRelayForGuild(sourceGuildClubId) then
        if self.enableTrafficDebug then
            print("|cffff8800[Relay]|r Skipping relay - not primary for guild " .. tostring(sourceGuildClubId))
        end
        return
    end

    local hash = self:MakeMessageHash("relay", payload, "", "")
    if self:IsRecentGuildRelay(hash) then
        return
    end

    if self.enableTrafficDebug then
        print("|cff00ff00[Relay]|r Relaying as PRIMARY for guild " .. tostring(sourceGuildClubId))
        if #self.guildRelayQueue > 10 then
            print("|cffff8800[Relay]|r Guild queue size: " .. #self.guildRelayQueue)
        end
    end

    table.insert(self.guildRelayQueue, payload)
    self:ProcessGuildRelayQueue()
end

function GB:ProcessGuildRelayQueue()
    if self.isProcessingGuildRelay or #self.guildRelayQueue == 0 then
        return
    end

    self.isProcessingGuildRelay = true

    local function processNext()
        if #GB.guildRelayQueue == 0 then
            GB.isProcessingGuildRelay = false
            return
        end

        local payload = table.remove(GB.guildRelayQueue, 1)

        local msgType
        if payload:sub(1, 10) == "_ANNOUNCE_" then
            local announcePayload = payload:sub(11)
            C_ChatInfo.SendAddonMessage(GB.BRIDGE_ADDON_PREFIX, announcePayload, "GUILD")
            msgType = "ANNOUNCE"
        elseif payload:sub(1, 6) == "_DATA_" then
            local dataPayload = payload:sub(7)
            C_ChatInfo.SendAddonMessage(GB.BRIDGE_ADDON_PREFIX, "[GBGD]" .. dataPayload, "GUILD")
            msgType = "DATA"
        else
            C_ChatInfo.SendAddonMessage(GB.BRIDGE_ADDON_PREFIX, "[GBGR]" .. payload, "GUILD")
            msgType = "CHAT"
        end

        GB.trafficStats.guild = GB.trafficStats.guild + 1
        if GB.enableTrafficDebug then
            print("|cffff8800[Traffic]|r Guild " .. msgType .. " relay (queue: " .. #GB.guildRelayQueue .. ", size: " .. #payload .. " bytes)")
        end

        if #GB.guildRelayQueue > 0 then
            C_Timer.After(GB.GUILD_RELAY_THROTTLE, processNext)
        else
            GB.isProcessingGuildRelay = false
        end
    end

    processNext()
end

function GB:HandleGuildRelayMessage(payload, sender)
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm

    local senderFullName = sender
    if not sender:find("-") then
        senderFullName = sender .. "-" .. myRealm
    end

    if senderFullName == myFullName then
        return
    end

    local guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart

    guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messageIdPart, guildHomeRealmPart, classFilePart, guildClubIdPart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

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

    if not messagePart or not originPart then
        return
    end

    if guildPart == "" then guildPart = nil end
    if guildRealmPart == "" then guildRealmPart = nil end
    if originRealmPart == "" then originRealmPart = nil end
    if guildHomeRealmPart == "" then guildHomeRealmPart = nil end
    if classFilePart == "" then classFilePart = nil end
    if guildClubIdPart == "" then guildClubIdPart = nil end

    if not guildHomeRealmPart then
        guildHomeRealmPart = guildRealmPart
    end

    if guildPart and not self.allowedGuilds[guildPart] then
        return
    end

    local hash = self:MakeMessageHash(guildPart or "", originPart, originRealmPart or "", messagePart)
    if self:IsDuplicateMessage(hash) then
        return
    end

    if guildClubIdPart then
        self:TrackGuildRelayBridge(sender, guildClubIdPart)
    end

    self:AddBridgeMessage(originPart, guildPart, factionPart, messagePart, originRealmPart, guildHomeRealmPart, classFilePart, guildClubIdPart, nil)
end

function GB:TrackGuildRelayBridge(sender, guildClubId)
    if not sender or not guildClubId then return end

    local senderKey = sender
    if not sender:find("-") then
        senderKey = sender .. "-" .. GetRealmName()
    end

    if not self.guildRelayBridges[senderKey] then
        self.guildRelayBridges[senderKey] = {
            guilds = {},
            lastSeen = GetTime(),
        }
    end

    self.guildRelayBridges[senderKey].guilds[tostring(guildClubId)] = true
    self.guildRelayBridges[senderKey].lastSeen = GetTime()

    self:UpdateConnectionIndicators()
end

function GB:HandleGuildRelayRoster(payload, sender)
    local myName = UnitName("player")
    local myRealm = GetRealmName()
    local myFullName = myName .. "-" .. myRealm

    local senderFullName = sender
    if not sender:find("-") then
        senderFullName = sender .. "-" .. myRealm
    end

    if senderFullName == myFullName then
        return
    end

    local msgType = payload:sub(1, 6)
    local msgData = payload:sub(7)

    if msgType == "[GBGM]" then
        local guildClubId, guildName, guildHomeRealm = msgData:match("([^|]+)|([^|]+)|([^|]*)")
        if guildClubId and guildName then
            guildHomeRealm = guildHomeRealm ~= "" and guildHomeRealm or nil
            guildClubId = tonumber(guildClubId) or guildClubId
            self:RegisterGuild(guildName, guildHomeRealm, guildClubId)

            self:TrackGuildRelayBridge(sender, guildClubId)
        end
    elseif msgType == "[GBGX]" then
        local guildClubId = msgData:match("([^|]+)")
        if guildClubId then
            guildClubId = tonumber(guildClubId) or guildClubId
            if self.guildRelayBridges[sender] and self.guildRelayBridges[sender].guilds then
                self.guildRelayBridges[sender].guilds[tostring(guildClubId)] = nil
                local hasAnyGuilds = false
                for _ in pairs(self.guildRelayBridges[sender].guilds) do
                    hasAnyGuilds = true
                    break
                end
                if not hasAnyGuilds then
                    self.guildRelayBridges[sender] = nil
                end
            end
            self:UpdateConnectionIndicators()
            if self.currentPage == "status" then
                self:RefreshMessages()
            end
        end
    elseif msgType == "[GBRF]" and self.HandleRosterFullMessage then
        local _, guildClubId = msgData:match("([^|]+)|([^|]+)")
        if guildClubId then
            guildClubId = tonumber(guildClubId) or guildClubId
            self:TrackGuildRelayBridge(sender, guildClubId)
        end
        self:HandleRosterFullMessage(msgData, sender, "guild")
    elseif msgType == "[GBRD]" and self.HandleRosterDeltaMessage then
        local _, guildClubId = msgData:match("([^|]+)|([^|]+)")
        if guildClubId then
            guildClubId = tonumber(guildClubId) or guildClubId
            self:TrackGuildRelayBridge(sender, guildClubId)
        end
        self:HandleRosterDeltaMessage(msgData, sender, "guild")
    elseif msgType == "[GBPY]" then
    end
end

function GB:RelayDataToGuildmates(payload, sourceGuildClubId)
    if not IsInGuild() then return end
    if not MNetDB.bridgeEnabled or not MNetDB.enableGuildRelay then return end

    if sourceGuildClubId and not self:AmIPrimaryRelayForGuild(sourceGuildClubId) then
        if self.enableTrafficDebug then
            print("|cffff8800[Relay]|r Skipping data relay - not primary for guild " .. tostring(sourceGuildClubId))
        end
        return
    end

    local hash = self:MakeMessageHash("data_relay", payload, "", "")
    if self:IsRecentGuildRelay(hash) then
        return
    end

    if self.enableTrafficDebug and #self.guildRelayQueue > 10 then
        print("|cffff8800[Relay]|r Guild queue size: " .. #self.guildRelayQueue)
    end

    table.insert(self.guildRelayQueue, "_DATA_" .. payload)
    self:ProcessGuildRelayQueue()
end
