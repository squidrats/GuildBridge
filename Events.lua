-- GuildBridge Events Module
-- Handles all event registration and processing

local addonName, GB = ...

-- Register events
GB.eventFrame:RegisterEvent("ADDON_LOADED")
GB.eventFrame:RegisterEvent("PLAYER_LOGIN")
GB.eventFrame:RegisterEvent("CHAT_MSG_GUILD")
GB.eventFrame:RegisterEvent("BN_CHAT_MSG_ADDON")
GB.eventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
GB.eventFrame:RegisterEvent("BN_CONNECTED")

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
                GB:SendHandshake()
                -- Clean up stale entries
                local now = GetTime()
                for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
                    if now - info.lastSeen > 300 then
                        GB.connectedBridgeUsers[gameAccountID] = nil
                    end
                end
                GB:UpdateConnectionIndicators()
            end)
        end
    elseif event == "PLAYER_LOGIN" or event == "BN_CONNECTED" then
        GB:UpdateOnlineFriends()
        -- Send initial handshake after a short delay to ensure everything is loaded
        C_Timer.After(3, function()
            GB:SendHandshake()
        end)
    elseif event == "BN_FRIEND_INFO_CHANGED" then
        local previousFriendIDs = {}
        for _, friend in ipairs(GB.onlineFriends) do
            previousFriendIDs[friend.gameAccountID] = true
        end

        GB:UpdateOnlineFriends()

        -- Remove connectedBridgeUsers entries for friends who are no longer online
        local currentFriendIDs = {}
        for _, friend in ipairs(GB.onlineFriends) do
            currentFriendIDs[friend.gameAccountID] = true
        end
        for gameAccountID, _ in pairs(GB.connectedBridgeUsers) do
            if not currentFriendIDs[gameAccountID] then
                GB.connectedBridgeUsers[gameAccountID] = nil
            end
        end
        GB:UpdateConnectionIndicators()

        -- Only send handshake if there's a NEW friend we haven't seen
        for gameAccountID, _ in pairs(currentFriendIDs) do
            if not previousFriendIDs[gameAccountID] and not GB.connectedBridgeUsers[gameAccountID] then
                -- New friend came online, send handshake to just them
                GB:SendHandshakeMessage("HELLO", gameAccountID)
            end
        end
    elseif event == "CHAT_MSG_GUILD" then
        local text, sender, _, _, _, _, _, _, _, _, _, guid = ...
        GB:HandleGuildChatMessage(text, sender, nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)
    elseif event == "BN_CHAT_MSG_ADDON" then
        local prefix, message, _, senderID = ...
        GB:HandleBNAddonMessage(prefix, message, senderID)
    end
end)
