-- MNet Events Module
-- Handles all event registration and processing

local addonName, GB = ...

-- Register events
GB.eventFrame:RegisterEvent("ADDON_LOADED")
GB.eventFrame:RegisterEvent("PLAYER_LOGIN")
GB.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
GB.eventFrame:RegisterEvent("CHAT_MSG_GUILD")
GB.eventFrame:RegisterEvent("BN_CHAT_MSG_ADDON")
GB.eventFrame:RegisterEvent("CHAT_MSG_ADDON")  -- For whisper-based addon messages (same-account alts)
GB.eventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
GB.eventFrame:RegisterEvent("BN_CONNECTED")
GB.eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
GB.eventFrame:RegisterEvent("PLAYER_LOGOUT")
GB.eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")  -- For detecting offline alts
GB.eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")  -- For roster sync
GB.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")  -- For party sync

-- Main event handler
GB.eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            GB:EnsureSavedVariables()
            C_ChatInfo.RegisterAddonMessagePrefix(GB.BRIDGE_ADDON_PREFIX)
            GB:CreateBridgeUI()

            -- Periodic handshake every 2 minutes to keep connection status fresh
            C_Timer.NewTicker(120, function()
                GB:ForceSendHandshake()
                GB:ForceSendWhisperHandshake()  -- Also ping registered alts
                -- Clean up stale entries
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
                GB:UpdateConnectionIndicators()
                -- Clean up stale roster data
                if GB.CleanupStaleRosters then
                    GB:CleanupStaleRosters()
                end
            end)

            -- Periodic roster re-sync every 2 minutes to recover from any missed deltas
            C_Timer.NewTicker(120, function()
                if GB.RequestRosterResync then
                    GB:RequestRosterResync()
                end
            end)

            -- More frequent ping for whisper alts (every 30 seconds) since we can't detect their logout
            C_Timer.NewTicker(30, function()
                GB:ForceSendWhisperHandshake()
                -- Shorter stale timeout for whisper alts (90 seconds = 3 missed pings)
                local now = GetTime()
                for altName, info in pairs(GB.connectedWhisperAlts) do
                    if now - info.lastSeen > 90 then
                        GB.connectedWhisperAlts[altName] = nil
                    end
                end
                GB:UpdateConnectionIndicators()
                -- Clear rosters for guilds that no longer have connections
                if GB.ClearDisconnectedRosters then
                    GB:ClearDisconnectedRosters()
                end
                -- Party data cleanup removed (party sync is now local-only)
            end)
        end

    elseif event == "PLAYER_LOGIN" then
        -- PLAYER_ENTERING_WORLD also fires on login and handles UpdateOnlineFriends
        -- So we skip it here to avoid duplicate BNet API calls at the same time
        -- Just mark that we've logged in
        if GB.enableEventDebug then
            C_Timer.After(3, function()
                print("|cff888888[Event]|r PLAYER_LOGIN (skipped - PLAYER_ENTERING_WORLD handles it)")
            end)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- This fires after login and after every loading screen
        -- IMPORTANT: Delay BNet API calls to avoid disconnect during loading screen transition
        local isLogin, isReload = ...

        -- Mark when this event fired so BN_CONNECTED can skip if we just handled it
        GB.lastPlayerEnteringWorld = GetTime()

        if GB.enableEventDebug then
            print("|cffff8800[Event]|r PLAYER_ENTERING_WORLD isLogin=" .. tostring(isLogin) .. " isReload=" .. tostring(isReload))
            print("  BNet connections before: " .. GB:CountTable(GB.connectedBridgeUsers))
            print("  Whisper alts before: " .. GB:CountTable(GB.connectedWhisperAlts))
        end

        -- Delay friend list update to avoid calling BNet APIs during loading screen
        -- This prevents potential disconnects from API calls during transition
        -- Use 3 seconds to give loading screen plenty of time to complete
        C_Timer.After(3, function()
            if GB.enableEventDebug then
                print("|cff888888[Event]|r Delayed UpdateOnlineFriends running...")
            end
            GB:UpdateOnlineFriends()
        end)

        -- Clear stale whisper alt connections on login/reload
        -- We can't know if they're still online, so start fresh and let handshakes repopulate
        local clearedAlts = 0
        for altName, _ in pairs(GB.connectedWhisperAlts) do
            GB.connectedWhisperAlts[altName] = nil
            clearedAlts = clearedAlts + 1
        end
        if GB.enableEventDebug and clearedAlts > 0 then
            print("  |cffff0000Cleared " .. clearedAlts .. " whisper alt connections|r")
        end
        GB:UpdateConnectionIndicators()

        -- Register own guild on login/reload so it appears in the tab list immediately
        C_Timer.After(1, function()
            if IsInGuild() then
                local myGuildName = GetGuildInfo("player")
                local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
                local myGuildHomeRealm = GB:GetGuildHomeRealm()
                if myGuildName and GB.allowedGuilds[myGuildName] and myGuildClubId then
                    GB:RegisterGuild(myGuildName, myGuildHomeRealm, myGuildClubId)
                    -- Rebuild tabs after registering own guild to ensure it shows first
                    GB:RebuildTabs()
                end
            end
        end)

        -- STAGGER initial messages to prevent login disconnect burst
        -- Use time-based throttle to prevent rapid reconnects from flooding (60s cooldown)
        local now = GetTime()
        local timeSinceLastLogin = now - GB.loginHandshakeTimestamp

        if timeSinceLastLogin >= 60 then
            GB.loginHandshakeTimestamp = now

            -- Request roster data first (no network traffic, just local API call)
            C_Timer.After(2, function()
                if C_GuildInfo and C_GuildInfo.GuildRoster then
                    C_GuildInfo.GuildRoster()  -- Request fresh roster from server
                elseif GuildRoster then
                    GuildRoster()  -- Fallback for older API
                end
            end)
            -- Process roster (won't broadcast due to initial capture skip)
            C_Timer.After(3, function()
                if GB.ProcessGuildRosterUpdate then
                    GB:ProcessGuildRosterUpdate()
                end
            end)
            -- BNet handshake - queues messages to 50+ friends at 1 msg/sec
            C_Timer.After(5, function()
                GB:ForceSendHandshake()
            end)
            -- Whisper handshake slightly later
            C_Timer.After(10, function()
                GB:ForceSendWhisperHandshake()
            end)
            -- Party sync is now local-only (no network traffic)
            C_Timer.After(15, function()
                if GB.ProcessPartyUpdate then
                    GB:ProcessPartyUpdate(true)  -- true = skip initial broadcast
                end
            end)
        end

    elseif event == "BN_CONNECTED" then
        -- Battle.net reconnected (fires during BG entry, zone changes, etc.)
        local now = GetTime()

        -- Skip if PLAYER_ENTERING_WORLD fired recently (within 30 seconds)
        -- It already handles everything we need
        if now - GB.lastPlayerEnteringWorld < 30 then
            if GB.enableEventDebug then
                C_Timer.After(5, function()
                    print("|cff888888[Event]|r BN_CONNECTED (skipped - PLAYER_ENTERING_WORLD handled it)")
                end)
            end
            return
        end

        -- Throttle: Only process once per 15 seconds to prevent disconnect from burst calls
        if now - GB.lastBNConnectedTime < 15 then
            if GB.enableEventDebug then
                C_Timer.After(5, function()
                    print("|cff888888[Event]|r BN_CONNECTED (throttled, skipped)")
                end)
            end
            return
        end
        GB.lastBNConnectedTime = now

        -- Space out BNet API calls: 10s for UI update, 20s for handshakes
        -- (handshakes also call FindOnlineWoWFriends, so 10 seconds apart now)
        C_Timer.After(10, function()
            if GB.enableEventDebug then
                print("|cff888888[Event]|r BN_CONNECTED delayed UpdateOnlineFriends running...")
            end
            GB:UpdateOnlineFriends()
        end)

        C_Timer.After(20, function()
            if GB.enableEventDebug then
                print("|cff888888[Event]|r BN_CONNECTED delayed ForceSendHandshake running...")
            end
            GB:ForceSendHandshake()
        end)

    elseif event == "BN_FRIEND_INFO_CHANGED" then
        -- Debounce: This event fires VERY frequently (zone changes, level ups, etc.)
        -- Only process once every FRIEND_INFO_DEBOUNCE seconds
        local now = GetTime()

        -- Extra safety: Don't process during first 5 seconds after login
        -- This prevents disconnect loops from BNet API calls during startup
        if now < 5 then
            return
        end

        if now - GB.lastFriendInfoChange < GB.FRIEND_INFO_DEBOUNCE then
            if GB.enableEventDebug and now > 10 then  -- Only debug print after 10 seconds
                print("|cff888888[Event]|r BN_FRIEND_INFO_CHANGED (debounced, skipped)")
            end
            return
        end

        -- Extra safety: Don't process during loading screens
        -- Check if we're in a loading screen by testing if player exists
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

        -- Capture previous friend IDs NOW (before delay), then process after delay
        local previousFriendIDs = {}
        local previousCount = 0
        for _, friend in ipairs(GB.onlineFriends) do
            previousFriendIDs[friend.gameAccountID] = true
            previousCount = previousCount + 1
        end

        -- Delay the actual BNet API calls to avoid disconnect during transitions
        C_Timer.After(3, function()
            if GB.enableEventDebug then
                print("|cff888888[Event]|r BN_FRIEND_INFO_CHANGED delayed processing running...")
            end

            -- Update friends list (this calls BNet APIs)
            GB:UpdateOnlineFriends()

            -- Build set of current friend IDs
            local currentFriendIDs = {}
            local currentCount = 0
            for _, friend in ipairs(GB.onlineFriends) do
                currentFriendIDs[friend.gameAccountID] = true
                currentCount = currentCount + 1
            end

            if GB.enableEventDebug then
                print("  Online friends: " .. previousCount .. " -> " .. currentCount)
            end

            -- Remove connectedBridgeUsers entries for friends who are no longer online
            -- Notify guildmates if we lose a cross-guild bridge connection
            local removedCount = 0
            for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
                if not currentFriendIDs[gameAccountID] then
                    if GB.enableEventDebug then
                        print("  |cffff0000Removing bridge:|r " .. (info.characterName or "?") .. " (gameAccountID=" .. gameAccountID .. ")")
                    end
                    -- Notify guildmates that this bridge connection was lost
                    if MNetDB.enableGuildRelay and info.guildClubId then
                        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
                        if myGuildClubId and tostring(myGuildClubId) ~= tostring(info.guildClubId) then
                            -- Send disconnection metadata to guildmates
                            local metaPayload = "[GBGX]" .. tostring(info.guildClubId) .. "|" .. (info.guildName or "") .. "|" .. (info.guildHomeRealm or "")
                            if GB.RelayDataToGuildmates then
                                GB:RelayDataToGuildmates(metaPayload)
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
            -- Clear rosters for guilds that no longer have connections
            if GB.ClearDisconnectedRosters then
                GB:ClearDisconnectedRosters()
            end

            -- Send handshake to any NEW friends
            -- We send to all friends - they'll only respond if they're in an allowed guild
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
        -- Fires when player joins or leaves a guild
        -- Small delay to let guild info update
        C_Timer.After(0.5, function()
            local guildName = GetGuildInfo("player")
            if guildName and GB.allowedGuilds[guildName] then
                -- Joined an allowed guild - send handshake to all friends and alts
                GB:ForceSendHandshake()
                GB:ForceSendWhisperHandshake()

                -- Also notify new guildmates about any existing cross-guild bridge connections
                -- This happens when switching guilds
                if MNetDB.enableGuildRelay then
                    local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
                    for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
                        if info.guildClubId and myGuildClubId and tostring(myGuildClubId) ~= tostring(info.guildClubId) then
                            -- Notify new guildmates about this bridge connection
                            local metaPayload = "[GBGM]" .. tostring(info.guildClubId) .. "|" .. (info.guildName or "") .. "|" .. (info.guildHomeRealm or "")
                            if GB.RelayDataToGuildmates then
                                GB:RelayDataToGuildmates(metaPayload)
                            end
                        end
                    end
                end
            else
                -- Left guild or joined non-allowed guild - notify peers we're gone
                -- Send a "LEAVE" message so peers remove us from their connections
                GB:SendLeaveNotification()
                GB:SendWhisperLeaveNotification()
            end
        end)

    elseif event == "CHAT_MSG_GUILD" then
        local text, sender, _, _, _, _, _, _, _, _, _, guid = ...
        GB:HandleGuildChatMessage(text, sender, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)

    elseif event == "BN_CHAT_MSG_ADDON" then
        local prefix, message, _, senderID = ...
        GB:HandleBNAddonMessage(prefix, message, senderID)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == GB.BRIDGE_ADDON_PREFIX then
            if channel == "WHISPER" then
                -- Whisper-based addon messages for same-account alts
                GB:HandleWhisperAddonMessage(prefix, message, sender)
            elseif channel == "GUILD" then
                -- Intra-guild relay messages from guildmates
                if message:sub(1, 6) == "[GBGR]" then
                    -- Guild relay of cross-guild chat message
                    if GB.HandleGuildRelayMessage then
                        GB:HandleGuildRelayMessage(message:sub(7), sender)
                    end
                elseif message:sub(1, 6) == "[GBGD]" then
                    -- Guild relay of roster/party data
                    if GB.HandleGuildRelayRoster then
                        GB:HandleGuildRelayRoster(message:sub(7), sender)
                    end
                end
            end
        end

    elseif event == "PLAYER_LOGOUT" then
        -- Send LEAVE notification to all connected peers before logging out
        -- This ensures they know we're disconnecting
        GB:SendLeaveNotification()
        GB:SendWhisperLeaveNotification()

        -- Notify guildmates that we're losing all our cross-guild bridge connections
        if MNetDB.enableGuildRelay and IsInGuild() then
            local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
            for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
                if info.guildClubId and myGuildClubId and tostring(myGuildClubId) ~= tostring(info.guildClubId) then
                    -- Send disconnection metadata to guildmates
                    local metaPayload = "[GBGX]" .. tostring(info.guildClubId) .. "|" .. (info.guildName or "") .. "|" .. (info.guildHomeRealm or "")
                    if GB.RelayDataToGuildmates then
                        GB:RelayDataToGuildmates(metaPayload)
                    end
                end
            end
        end

    elseif event == "CHAT_MSG_SYSTEM" then
        -- Detect when a whisper alt goes offline
        -- System messages like "No player named 'X' is currently playing" indicate offline
        local message = ...
        if message then
            -- Check for offline player messages (multiple locales possible)
            -- English: "No player named 'Name-Realm' is currently playing."
            -- Also: "Player not found."
            for altName, _ in pairs(GB.connectedWhisperAlts) do
                -- Check if this system message mentions our connected alt
                if message:find(altName, 1, true) then
                    -- Alt appears to be offline, remove from connections
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
        -- Debounce roster updates (this event can fire rapidly)
        if not GB.rosterUpdatePending then
            GB.rosterUpdatePending = true
            C_Timer.After(1, function()
                GB.rosterUpdatePending = false
                if GB.ProcessGuildRosterUpdate then
                    GB:ProcessGuildRosterUpdate()
                end
            end)
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Party composition changed - update party members and broadcast
        if GB.ProcessPartyUpdate then
            GB:ProcessPartyUpdate()
        end
    end
end)
