-- GuildBridge Events Module
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
            end)
        end

    elseif event == "PLAYER_LOGIN" then
        GB:UpdateOnlineFriends()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- This fires after login and after every loading screen
        -- Good time to refresh friends and send handshake
        GB:UpdateOnlineFriends()

        if not initialHandshakeDone then
            initialHandshakeDone = true
            -- Send handshake after short delay to let everything load
            C_Timer.After(2, function()
                GB:ForceSendHandshake()
                GB:ForceSendWhisperHandshake()  -- Also ping registered alts
            end)
            -- Send again after 5 seconds for reliability
            C_Timer.After(7, function()
                GB:ForceSendHandshake()
                GB:ForceSendWhisperHandshake()
            end)
        end

    elseif event == "BN_CONNECTED" then
        -- Battle.net reconnected
        GB:UpdateOnlineFriends()
        C_Timer.After(2, function()
            GB:ForceSendHandshake()
        end)

    elseif event == "BN_FRIEND_INFO_CHANGED" then
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

        -- Send handshake to any NEW friends
        for gameAccountID, _ in pairs(currentFriendIDs) do
            if not previousFriendIDs[gameAccountID] then
                -- New friend came online, send handshake to them
                GB:SendHandshakeToFriend(gameAccountID)
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
    end
end)
