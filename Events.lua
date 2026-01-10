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

-- Track if we've done initial handshake
local initialHandshakeDone = false

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

        if not initialHandshakeDone then
            initialHandshakeDone = true
            -- Send handshake after short delay to let everything load
            C_Timer.After(3, function()
                GB:ForceSendHandshake()
                GB:ForceSendWhisperHandshake()
            end)
            -- Capture initial roster after a delay (guild roster needs time to load)
            -- Request fresh roster data from server first
            C_Timer.After(3, function()
                if C_GuildInfo and C_GuildInfo.GuildRoster then
                    C_GuildInfo.GuildRoster()  -- Request fresh roster from server
                elseif GuildRoster then
                    GuildRoster()  -- Fallback for older API
                end
            end)
            C_Timer.After(5, function()
                if GB.ProcessGuildRosterUpdate then
                    GB:ProcessGuildRosterUpdate()
                end
            end)
        end

    elseif event == "BN_CONNECTED" then
        -- Battle.net reconnected
        GB:UpdateOnlineFriends()
        C_Timer.After(2, function()
            GB:ForceSendHandshake()
        end)

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
        for gameAccountID, _ in pairs(GB.connectedBridgeUsers) do
            if not currentFriendIDs[gameAccountID] then
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
        -- Whisper-based addon messages for same-account alts
        local prefix, message, channel, sender = ...
        if prefix == GB.BRIDGE_ADDON_PREFIX and channel == "WHISPER" then
            GB:HandleWhisperAddonMessage(prefix, message, sender)
        end

    elseif event == "PLAYER_LOGOUT" then
        -- Send LEAVE notification to all connected peers before logging out
        -- This ensures they know we're disconnecting
        GB:SendLeaveNotification()
        GB:SendWhisperLeaveNotification()

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
    end
end)
