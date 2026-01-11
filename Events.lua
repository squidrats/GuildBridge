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
        GB:UpdateOnlineFriends()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- This fires after login and after every loading screen
        -- Good time to refresh friends and send handshake
        GB:UpdateOnlineFriends()

        -- Clear stale whisper alt connections on login/reload
        -- We can't know if they're still online, so start fresh and let handshakes repopulate
        for altName, _ in pairs(GB.connectedWhisperAlts) do
            GB.connectedWhisperAlts[altName] = nil
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
        -- Battle.net reconnected
        GB:UpdateOnlineFriends()
        -- CRITICAL: Use same delay as login to prevent reconnect flood (disconnects often trigger immediate BN_CONNECTED)
        -- Throttle to prevent rapid reconnect attempts from queuing hundreds of messages
        local now = GetTime()
        if now - GB.loginHandshakeTimestamp >= 60 then
            GB.loginHandshakeTimestamp = now
            C_Timer.After(5, function()
                GB:ForceSendHandshake()
            end)
        end

    elseif event == "BN_FRIEND_INFO_CHANGED" then
        -- Debounce: This event fires VERY frequently (zone changes, level ups, etc.)
        -- Only process once every FRIEND_INFO_DEBOUNCE seconds
        local now = GetTime()
        if now - GB.lastFriendInfoChange < GB.FRIEND_INFO_DEBOUNCE then
            return
        end
        GB.lastFriendInfoChange = now

        -- Build set of previous friend IDs
        local previousFriendIDs = {}
        for _, friend in ipairs(GB.onlineFriends) do
            previousFriendIDs[friend.gameAccountID] = true
        end

        -- Update friends list
        GB:UpdateOnlineFriends()

        -- Build set of current friend IDs
        local currentFriendIDs = {}
        for _, friend in ipairs(GB.onlineFriends) do
            currentFriendIDs[friend.gameAccountID] = true
        end

        -- Remove connectedBridgeUsers entries for friends who are no longer online
        -- Notify guildmates if we lose a cross-guild bridge connection
        for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
            if not currentFriendIDs[gameAccountID] then
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
            end
        end
        GB:UpdateConnectionIndicators()
        -- Clear rosters for guilds that no longer have connections
        if GB.ClearDisconnectedRosters then
            GB:ClearDisconnectedRosters()
        end

        -- Send handshake to any NEW friends
        -- We send to all friends - they'll only respond if they're in an allowed guild
        for _, friend in ipairs(GB.onlineFriends) do
            if not previousFriendIDs[friend.gameAccountID] then
                GB:SendHandshakeToFriend(friend.gameAccountID)
            end
        end

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
