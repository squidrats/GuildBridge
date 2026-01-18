local addonName, GB = ...

GB.eventFrame:RegisterEvent("ADDON_LOADED")
GB.eventFrame:RegisterEvent("PLAYER_LOGIN")
GB.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
GB.eventFrame:RegisterEvent("CHAT_MSG_GUILD")
GB.eventFrame:RegisterEvent("BN_CHAT_MSG_ADDON")
GB.eventFrame:RegisterEvent("CHAT_MSG_ADDON")
GB.eventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
GB.eventFrame:RegisterEvent("BN_CONNECTED")
GB.eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
GB.eventFrame:RegisterEvent("PLAYER_LOGOUT")
GB.eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
GB.eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
GB.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
GB.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

GB.eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            GB:EnsureSavedVariables()
            C_ChatInfo.RegisterAddonMessagePrefix(GB.BRIDGE_ADDON_PREFIX)
            GB:CreateBridgeUI()

            C_Timer.NewTicker(120, function()
                if GB:IsInZoneTransition() then return end
                GB:ForceSendHandshake()
                GB:ForceSendWhisperHandshake()
                local now = GetTime()
                for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
                    if now - info.lastSeen > 300 then
                        GB.connectedBridgeUsers[gameAccountID] = nil
                    end
                end
                for altName, info in pairs(GB.connectedWhisperAlts) do
                    if now - info.lastSeen > 300 then
                        GB.connectedWhisperAlts[altName] = nil
                    end
                end
                for senderName, info in pairs(GB.guildRelayBridges) do
                    if now - info.lastSeen > 300 then
                        GB.guildRelayBridges[senderName] = nil
                    end
                end
                for guildClubIdStr, candidates in pairs(GB.relayCandidates) do
                    for candidateName, info in pairs(candidates) do
                        if now - info.lastSeen > GB.RELAY_CANDIDATE_TIMEOUT then
                            candidates[candidateName] = nil
                        end
                    end
                end
                GB:UpdateConnectionIndicators()
                if GB.CleanupStaleRosters then
                    GB:CleanupStaleRosters()
                end
            end)

            C_Timer.NewTicker(120, function()
                if GB:IsInZoneTransition() then return end
                if GB.RequestRosterResync then
                    GB:RequestRosterResync()
                end
            end)

            C_Timer.NewTicker(30, function()
                if GB:IsInZoneTransition() then return end
                GB:ForceSendWhisperHandshake()
                local now = GetTime()
                for altName, info in pairs(GB.connectedWhisperAlts) do
                    if now - info.lastSeen > 90 then
                        GB.connectedWhisperAlts[altName] = nil
                    end
                end
                GB:UpdateConnectionIndicators()
                if GB.ClearDisconnectedRosters then
                    GB:ClearDisconnectedRosters()
                end
            end)
        end

    elseif event == "PLAYER_LOGIN" then
        if GB.enableEventDebug then
            C_Timer.After(3, function()
                print("|cff888888[Event]|r PLAYER_LOGIN (skipped - PLAYER_ENTERING_WORLD handles it)")
            end)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...

        GB.lastPlayerEnteringWorld = GetTime()
        GB:LogDC("EVENT", "PLAYER_ENTERING_WORLD isLogin=" .. tostring(isLogin) .. " isReload=" .. tostring(isReload))

        if GB.enableEventDebug then
            print("|cffff8800[Event]|r PLAYER_ENTERING_WORLD isLogin=" .. tostring(isLogin) .. " isReload=" .. tostring(isReload))
            print("  BNet connections before: " .. GB:CountTable(GB.connectedBridgeUsers))
            print("  Whisper alts before: " .. GB:CountTable(GB.connectedWhisperAlts))
        end

        if not isLogin and not isReload then
            if GB.enableEventDebug then
                print("  |cff888888Zone change only - skipping cascade|r")
            end
            return
        end

        C_Timer.After(3, function()
            if GB:IsInZoneTransition() then return end
            if GB.enableEventDebug then
                print("|cff888888[Event]|r Delayed UpdateOnlineFriends running...")
            end
            GB:UpdateOnlineFriends()
        end)

        local clearedAlts = 0
        for altName, _ in pairs(GB.connectedWhisperAlts) do
            GB.connectedWhisperAlts[altName] = nil
            clearedAlts = clearedAlts + 1
        end
        if GB.enableEventDebug and clearedAlts > 0 then
            print("  |cffff0000Cleared " .. clearedAlts .. " whisper alt connections|r")
        end
        GB:UpdateConnectionIndicators()

        C_Timer.After(2, function()
            if GB:IsInZoneTransition() then return end
            if IsInGuild() then
                local myGuildName = GetGuildInfo("player")
                local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
                local myGuildHomeRealm = GB:GetGuildHomeRealm()
                if myGuildName and myGuildClubId and GB:IsAllowedGuildId(myGuildClubId) then
                    GB:RegisterGuild(myGuildName, myGuildHomeRealm, myGuildClubId)
                    GB:RebuildTabs()
                end
            end
        end)

        local now = GetTime()
        local timeSinceLastLogin = now - GB.loginHandshakeTimestamp

        if timeSinceLastLogin >= 60 then
            GB.loginHandshakeTimestamp = now

            C_Timer.After(5, function()
                if GB:IsInZoneTransition() then return end
                if C_GuildInfo and C_GuildInfo.GuildRoster then
                    C_GuildInfo.GuildRoster()
                elseif GuildRoster then
                    GuildRoster()
                end
            end)
            C_Timer.After(8, function()
                if GB:IsInZoneTransition() then return end
                if GB.ProcessGuildRosterUpdate then
                    GB:ProcessGuildRosterUpdate()
                end
            end)
            C_Timer.After(15, function()
                if GB:IsInZoneTransition() then return end
                GB:ForceSendHandshake()
            end)
            C_Timer.After(25, function()
                if GB:IsInZoneTransition() then return end
                GB:ForceSendWhisperHandshake()
            end)
            C_Timer.After(35, function()
                if GB:IsInZoneTransition() then return end
                if GB.ProcessPartyUpdate then
                    GB:ProcessPartyUpdate(true)
                end
            end)
            C_Timer.After(45, function()
                if GB:IsInZoneTransition() then return end
                GB:AnnounceAllRelayConnections()
                GB:StartRelayKeepalive()
            end)
        end

    elseif event == "BN_CONNECTED" then
        local now = GetTime()

        if now - GB.lastPlayerEnteringWorld < 30 then
            if GB.enableEventDebug then
                C_Timer.After(5, function()
                    print("|cff888888[Event]|r BN_CONNECTED (skipped - PLAYER_ENTERING_WORLD handled it)")
                end)
            end
            return
        end

        if now - GB.lastBNConnectedTime < 15 then
            if GB.enableEventDebug then
                C_Timer.After(5, function()
                    print("|cff888888[Event]|r BN_CONNECTED (throttled, skipped)")
                end)
            end
            return
        end
        GB.lastBNConnectedTime = now

        C_Timer.After(10, function()
            if GB:IsInZoneTransition() then return end
            if GB.enableEventDebug then
                print("|cff888888[Event]|r BN_CONNECTED delayed UpdateOnlineFriends running...")
            end
            GB:UpdateOnlineFriends()
        end)

        C_Timer.After(20, function()
            if GB:IsInZoneTransition() then return end
            if GB.enableEventDebug then
                print("|cff888888[Event]|r BN_CONNECTED delayed ForceSendHandshake running...")
            end
            GB:ForceSendHandshake()
        end)

    elseif event == "BN_FRIEND_INFO_CHANGED" then
        local now = GetTime()

        if now < 5 then
            return
        end

        GB:LogDC("EVENT", "BN_FRIEND_INFO_CHANGED")
        if GB:IsInZoneTransition() then
            GB:LogDC("EVENT", "BN_FRIEND_INFO_CHANGED skipped - zone transition")
            if GB.enableEventDebug and now > 10 then
                print("|cff888888[Event]|r BN_FRIEND_INFO_CHANGED (skipped - zone transition)")
            end
            return
        end

        if now - GB.lastFriendInfoChange < GB.FRIEND_INFO_DEBOUNCE then
            if GB.enableEventDebug and now > 10 then
                print("|cff888888[Event]|r BN_FRIEND_INFO_CHANGED (debounced, skipped)")
            end
            return
        end

        if not UnitExists("player") then
            if GB.enableEventDebug and now > 10 then
                print("|cffff0000[Event]|r BN_FRIEND_INFO_CHANGED (skipped - loading screen)")
            end
            return
        end

        GB.lastFriendInfoChange = now

        if GB.enableEventDebug and now > 10 then
            print("|cffff8800[Event]|r BN_FRIEND_INFO_CHANGED (scheduling delayed processing)")
        end

        local previousFriendIDs = {}
        local previousCount = 0
        for _, friend in ipairs(GB.onlineFriends) do
            previousFriendIDs[friend.gameAccountID] = true
            previousCount = previousCount + 1
        end

        C_Timer.After(3, function()
            if GB:IsInZoneTransition() then return end
            if GB.enableEventDebug then
                print("|cff888888[Event]|r BN_FRIEND_INFO_CHANGED delayed processing running...")
            end

            GB:UpdateOnlineFriends()

            local currentFriendIDs = {}
            local currentCount = 0
            for _, friend in ipairs(GB.onlineFriends) do
                currentFriendIDs[friend.gameAccountID] = true
                currentCount = currentCount + 1
            end

            if GB.enableEventDebug then
                print("  Online friends: " .. previousCount .. " -> " .. currentCount)
            end

            local removedCount = 0
            for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
                if not currentFriendIDs[gameAccountID] then
                    if GB.enableEventDebug then
                        print("  |cffff0000Removing bridge:|r " .. (info.characterName or "?") .. " (gameAccountID=" .. gameAccountID .. ")")
                    end
                    if MNetDB.enableGuildRelay and info.guildClubId then
                        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
                        if myGuildClubId and tostring(myGuildClubId) ~= tostring(info.guildClubId) then
                            if not GB:HasConnectionToGuild(info.guildClubId) then
                                GB:AnnounceRelayAvailability(info.guildClubId, false)
                            end
                            local metaPayload = "[GBGX]" .. tostring(info.guildClubId) .. "|" .. (info.guildName or "") .. "|" .. (info.guildHomeRealm or "")
                            if GB.RelayDataToGuildmates then
                                GB:RelayDataToGuildmates(metaPayload, info.guildClubId)
                            end
                        end
                    end
                    GB.connectedBridgeUsers[gameAccountID] = nil
                    removedCount = removedCount + 1
                end
            end

            if GB.enableEventDebug and removedCount > 0 then
                print("  |cffff0000Removed " .. removedCount .. " bridge connections|r")
            end

            GB:UpdateConnectionIndicators()
            if GB.ClearDisconnectedRosters then
                GB:ClearDisconnectedRosters()
            end

            local newFriendCount = 0
            for _, friend in ipairs(GB.onlineFriends) do
                if not previousFriendIDs[friend.gameAccountID] then
                    if GB.enableEventDebug then
                        print("  |cff00ff00New friend online:|r " .. (friend.characterName or friend.accountName or "?"))
                    end
                    GB:SendHandshakeToFriend(friend.gameAccountID)
                    newFriendCount = newFriendCount + 1
                end
            end

            if GB.enableEventDebug and newFriendCount > 0 then
                print("  |cff00ff00Sent handshakes to " .. newFriendCount .. " new friends|r")
            end
        end)

    elseif event == "PLAYER_GUILD_UPDATE" then
        if GB:IsInZoneTransition() then return end
        C_Timer.After(0.5, function()
            if GB:IsInZoneTransition() then return end
            local guildName = GetGuildInfo("player")
            local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
            if guildName and myGuildClubId and GB:IsAllowedGuildId(myGuildClubId) then
                GB:ForceSendHandshake()
                GB:ForceSendWhisperHandshake()

                if MNetDB.enableGuildRelay then
                    for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
                        if info.guildClubId and myGuildClubId and tostring(myGuildClubId) ~= tostring(info.guildClubId) then
                            GB:AnnounceRelayAvailability(info.guildClubId, true)
                            local metaPayload = "[GBGM]" .. tostring(info.guildClubId) .. "|" .. (info.guildName or "") .. "|" .. (info.guildHomeRealm or "")
                            if GB.RelayDataToGuildmates then
                                GB:RelayDataToGuildmates(metaPayload, info.guildClubId)
                            end
                        end
                    end
                end
            else
                GB:SendLeaveNotification()
                GB:SendWhisperLeaveNotification()
            end
        end)

    elseif event == "CHAT_MSG_GUILD" then
        local text, sender, _, _, _, _, _, _, _, _, _, guid = ...
        GB:LogDC("EVENT", "CHAT_MSG_GUILD from " .. tostring(sender))
        GB:HandleGuildChatMessage(text, sender, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)

    elseif event == "BN_CHAT_MSG_ADDON" then
        local prefix, message, _, senderID = ...
        if prefix == GB.BRIDGE_ADDON_PREFIX then
            local msgType = "unknown"
            if message:sub(1, 6) == "[GBHS]" then msgType = "handshake"
            elseif message:sub(1, 6) == "[GBRF]" then msgType = "roster-full"
            elseif message:sub(1, 6) == "[GBRD]" then msgType = "roster-delta"
            elseif message:sub(1, 6) == "[GBRR]" then msgType = "roster-req"
            elseif message:sub(1, 4) == "[GB]" then msgType = "chat"
            end
            GB:LogDC("RECV", "BNet " .. msgType .. " from " .. tostring(senderID) .. " size:" .. #message)
        end
        GB:HandleBNAddonMessage(prefix, message, senderID)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == GB.BRIDGE_ADDON_PREFIX then
            if channel == "WHISPER" then
                local msgType = "unknown"
                if message:sub(1, 7) == "[GBWHS]" then msgType = "handshake"
                elseif message:sub(1, 6) == "[GBRF]" then msgType = "roster-full"
                elseif message:sub(1, 6) == "[GBRD]" then msgType = "roster-delta"
                elseif message:sub(1, 4) == "[GB]" then msgType = "chat"
                end
                GB:LogDC("RECV", "Whisper " .. msgType .. " from " .. tostring(sender) .. " size:" .. #message)
                GB:HandleWhisperAddonMessage(prefix, message, sender)
            elseif channel == "GUILD" then
                GB:LogDC("RECV", "Guild msg from " .. tostring(sender) .. " size:" .. #message)
                if message:sub(1, 6) == "[GBRA]" then
                    GB:HandleRelayCandidateMessage(message, sender)
                elseif message:sub(1, 6) == "[GBGR]" then
                    if GB.HandleGuildRelayMessage then
                        GB:HandleGuildRelayMessage(message:sub(7), sender)
                    end
                elseif message:sub(1, 6) == "[GBGD]" then
                    if GB.HandleGuildRelayRoster then
                        GB:HandleGuildRelayRoster(message:sub(7), sender)
                    end
                end
            end
        end

    elseif event == "PLAYER_LOGOUT" then
        GB:WithdrawAllRelayAnnouncements()
        GB:StopRelayKeepalive()
        GB:SendLeaveNotification()
        GB:SendWhisperLeaveNotification()

        if MNetDB.enableGuildRelay and IsInGuild() then
            local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
            for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
                if info.guildClubId and myGuildClubId and tostring(myGuildClubId) ~= tostring(info.guildClubId) then
                    local metaPayload = "[GBGX]" .. tostring(info.guildClubId) .. "|" .. (info.guildName or "") .. "|" .. (info.guildHomeRealm or "")
                    if GB.RelayDataToGuildmates then
                        GB:RelayDataToGuildmates(metaPayload, info.guildClubId)
                    end
                end
            end
        end

    elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        if message then
            for altName, _ in pairs(GB.connectedWhisperAlts) do
                if message:find(altName, 1, true) then
                    GB.connectedWhisperAlts[altName] = nil
                    GB:UpdateConnectionIndicators()
                    if GB.currentPage == "status" then
                        GB:RefreshMessages()
                    end
                    break
                end
            end
        end

    elseif event == "GUILD_ROSTER_UPDATE" then
        GB:LogDC("EVENT", "GUILD_ROSTER_UPDATE")
        if GB:IsInZoneTransition() then
            GB:LogDC("EVENT", "GUILD_ROSTER_UPDATE skipped - zone transition")
            return
        end
        if not GB.rosterUpdatePending then
            GB.rosterUpdatePending = true
            C_Timer.After(1, function()
                GB.rosterUpdatePending = false
                if GB:IsInZoneTransition() then
                    GB:LogDC("EVENT", "GUILD_ROSTER_UPDATE timer skipped - zone transition")
                    return
                end
                GB:LogDC("EVENT", "GUILD_ROSTER_UPDATE processing")
                if GB.ProcessGuildRosterUpdate then
                    GB:ProcessGuildRosterUpdate()
                end
            end)
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        local numMembers = GetNumGroupMembers()
        GB:LogDC("EVENT", "GROUP_ROSTER_UPDATE members=" .. numMembers)
        if GB:IsInZoneTransition() then
            GB:LogDC("EVENT", "GROUP_ROSTER_UPDATE skipped - zone transition")
            return
        end
        if not GB.partyUpdatePending then
            GB.partyUpdatePending = true
            C_Timer.After(1, function()
                GB.partyUpdatePending = false
                if GB:IsInZoneTransition() then
                    GB:LogDC("EVENT", "GROUP_ROSTER_UPDATE timer skipped - zone transition")
                    return
                end
                if GB.ProcessPartyUpdate then
                    GB:LogDC("EVENT", "GROUP_ROSTER_UPDATE processing")
                    GB:ProcessPartyUpdate()
                end
            end)
        end

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- Protect against seamless zone transitions (flying between zones)
        -- PLAYER_ENTERING_WORLD doesn't fire for these, so we need this event
        GB.lastPlayerEnteringWorld = GetTime()
        GB:LogDC("EVENT", "ZONE_CHANGED_NEW_AREA - zone transition protection activated")
        if GB.enableEventDebug then
            print("|cffff8800[Event]|r ZONE_CHANGED_NEW_AREA - activating zone transition protection")
        end
    end
end)
