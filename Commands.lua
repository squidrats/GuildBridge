-- GuildBridge Commands Module
-- Slash command handlers

local addonName, GB = ...

SLASH_GUILDBRIDGE1 = "/gbridge"
SLASH_GUILDBRIDGE2 = "/gb"
SlashCmdList["GUILDBRIDGE"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()

    if cmd == "" then
        -- No argument, toggle UI
        GB:ToggleBridgeFrame()

    elseif cmd == "alt" or cmd == "addalt" then
        -- Register an alt character for same-account communication
        if arg == "" then
            print("|cff00ff00GuildBridge:|r Usage: /gb alt CharacterName-Realm")
            print("  Example: /gb alt Myalt-Illidan")
            return
        end

        -- Ensure Name-Realm format
        if not arg:find("-") then
            -- Try to add player's realm if none specified
            local realm = GetRealmName()
            arg = arg .. "-" .. realm
        end

        GuildBridgeDB.registeredAlts = GuildBridgeDB.registeredAlts or {}
        GB.registeredAlts = GuildBridgeDB.registeredAlts

        if GB.registeredAlts[arg] then
            print("|cff00ff00GuildBridge:|r Alt '" .. arg .. "' is already registered.")
        else
            GB.registeredAlts[arg] = true
            GuildBridgeDB.registeredAlts = GB.registeredAlts
            print("|cff00ff00GuildBridge:|r Registered alt: " .. arg)
            print("  Handshakes will be sent to this character when online.")
            -- Send handshake immediately to new alt
            GB:SendWhisperHandshakeToAlt(arg)
        end

    elseif cmd == "removealt" or cmd == "delalt" then
        -- Remove a registered alt
        if arg == "" then
            print("|cff00ff00GuildBridge:|r Usage: /gb removealt CharacterName-Realm")
            return
        end

        if not arg:find("-") then
            local realm = GetRealmName()
            arg = arg .. "-" .. realm
        end

        GuildBridgeDB.registeredAlts = GuildBridgeDB.registeredAlts or {}
        GB.registeredAlts = GuildBridgeDB.registeredAlts

        if GB.registeredAlts[arg] then
            GB.registeredAlts[arg] = nil
            GB.connectedWhisperAlts[arg] = nil
            GuildBridgeDB.registeredAlts = GB.registeredAlts
            print("|cff00ff00GuildBridge:|r Removed alt: " .. arg)
            GB:UpdateConnectionIndicators()
        else
            print("|cff00ff00GuildBridge:|r Alt '" .. arg .. "' is not registered.")
        end

    elseif cmd == "alts" or cmd == "listalt" or cmd == "listalts" then
        -- List all registered alts
        GuildBridgeDB.registeredAlts = GuildBridgeDB.registeredAlts or {}
        GB.registeredAlts = GuildBridgeDB.registeredAlts

        local count = 0
        for _ in pairs(GB.registeredAlts) do
            count = count + 1
        end

        if count == 0 then
            print("|cff00ff00GuildBridge:|r No alts registered.")
            print("  Use |cffffd700/gb alt CharacterName-Realm|r to register an alt.")
        else
            print("|cff00ff00GuildBridge:|r Registered alts (" .. count .. "):")
            for altName, _ in pairs(GB.registeredAlts) do
                local status = ""
                if GB.connectedWhisperAlts[altName] then
                    status = " |cff00ff00(connected)|r"
                end
                print("  - " .. altName .. status)
            end
        end

    elseif cmd == "debug" then
        -- Debug info for troubleshooting
        print("|cff00ff00GuildBridge Debug Info:|r")

        -- My guild info
        local myGuildName = GetGuildInfo("player")
        local myGuildHomeRealm = GB:GetGuildHomeRealm()
        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        print("|cffffd700My Guild:|r " .. (myGuildName or "none"))
        print("  Home Realm: " .. (myGuildHomeRealm or "nil"))
        print("  Club ID: " .. tostring(myGuildClubId or "nil"))

        -- Known guilds
        print("|cffffd700Known Guilds:|r")
        local guildCount = 0
        for filterKey, info in pairs(GB.knownGuilds) do
            guildCount = guildCount + 1
            print("  [" .. filterKey .. "]")
            print("    guildName: " .. (info.guildName or "nil"))
            print("    guildHomeRealm: " .. (info.guildHomeRealm or "nil"))
            print("    guildClubId: " .. tostring(info.guildClubId or "nil"))
        end
        if guildCount == 0 then
            print("  (none)")
        end

        -- BNet connections
        print("|cffffd700BNet Connections:|r")
        local bnetCount = 0
        local now = GetTime()
        for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
            bnetCount = bnetCount + 1
            local age = math.floor(now - info.lastSeen)
            print("  [" .. tostring(gameAccountID) .. "] " .. (info.characterName or "Unknown"))
            print("    guildName: " .. (info.guildName or "nil"))
            print("    guildHomeRealm: " .. (info.guildHomeRealm or "nil"))
            print("    guildClubId: " .. tostring(info.guildClubId or "nil"))
            print("    lastSeen: " .. age .. "s ago")
        end
        if bnetCount == 0 then
            print("  (none)")
        end

        -- Whisper alt connections
        print("|cffffd700Whisper Alt Connections:|r")
        local altCount = 0
        for altName, info in pairs(GB.connectedWhisperAlts) do
            altCount = altCount + 1
            local age = math.floor(now - info.lastSeen)
            print("  [" .. altName .. "]")
            print("    guildName: " .. (info.guildName or "nil"))
            print("    guildHomeRealm: " .. (info.guildHomeRealm or "nil"))
            print("    guildClubId: " .. tostring(info.guildClubId or "nil"))
            print("    lastSeen: " .. age .. "s ago")
        end
        if altCount == 0 then
            print("  (none)")
        end

        -- Current filter
        print("|cffffd700Current Filter:|r " .. (GB.currentFilter or "All"))

    elseif cmd == "help" then
        print("|cff00ff00GuildBridge Commands:|r")
        print("  |cffffd700/gb|r - Toggle GuildBridge window")
        print("  |cffffd700/gb alt <Name-Realm>|r - Register a same-account alt")
        print("  |cffffd700/gb removealt <Name-Realm>|r - Remove a registered alt")
        print("  |cffffd700/gb alts|r - List registered alts")
        print("  |cffffd700/gb debug|r - Show debug info")
        print("  |cffffd700/gb help|r - Show this help")

    else
        print("|cff00ff00GuildBridge:|r Unknown command '" .. cmd .. "'. Use |cffffd700/gb help|r for commands.")
    end
end
