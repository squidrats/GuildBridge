-- MNet Commands Module
-- Slash command handlers

local addonName, GB = ...

SLASH_MDGANET1 = "/mn"
SLASH_MDGANET2 = "/mdganet"
SlashCmdList["MDGANET"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()

    if cmd == "" then
        -- No argument, toggle UI
        GB:ToggleBridgeFrame()

    elseif cmd == "alt" or cmd == "addalt" then
        -- Register an alt character for same-account communication
        if arg == "" then
            print("|cff00ff00MNet:|r Usage: /mn alt CharacterName-Realm")
            print("  Example: /mn alt Myalt-Illidan")
            return
        end

        -- Ensure Name-Realm format
        if not arg:find("-") then
            -- Try to add player's realm if none specified
            local realm = GetRealmName()
            arg = arg .. "-" .. realm
        end

        MNetDB.registeredAlts = MNetDB.registeredAlts or {}
        GB.registeredAlts = MNetDB.registeredAlts

        if GB.registeredAlts[arg] then
            print("|cff00ff00MNet:|r Alt '" .. arg .. "' is already registered.")
        else
            GB.registeredAlts[arg] = true
            MNetDB.registeredAlts = GB.registeredAlts
            print("|cff00ff00MNet:|r Registered alt: " .. arg)
            print("  Handshakes will be sent to this character when online.")
            -- Send handshake immediately to new alt
            GB:SendWhisperHandshakeToAlt(arg)
        end

    elseif cmd == "removealt" or cmd == "delalt" then
        -- Remove a registered alt
        if arg == "" then
            print("|cff00ff00MNet:|r Usage: /mn removealt CharacterName-Realm")
            return
        end

        if not arg:find("-") then
            local realm = GetRealmName()
            arg = arg .. "-" .. realm
        end

        MNetDB.registeredAlts = MNetDB.registeredAlts or {}
        GB.registeredAlts = MNetDB.registeredAlts

        if GB.registeredAlts[arg] then
            GB.registeredAlts[arg] = nil
            GB.connectedWhisperAlts[arg] = nil
            MNetDB.registeredAlts = GB.registeredAlts
            print("|cff00ff00MNet:|r Removed alt: " .. arg)
            GB:UpdateConnectionIndicators()
        else
            print("|cff00ff00MNet:|r Alt '" .. arg .. "' is not registered.")
        end

    elseif cmd == "alts" or cmd == "listalt" or cmd == "listalts" then
        -- List all registered alts
        MNetDB.registeredAlts = MNetDB.registeredAlts or {}
        GB.registeredAlts = MNetDB.registeredAlts

        local count = 0
        for _ in pairs(GB.registeredAlts) do
            count = count + 1
        end

        if count == 0 then
            print("|cff00ff00MNet:|r No alts registered.")
            print("  Use |cffffd700/mn alt CharacterName-Realm|r to register an alt.")
        else
            print("|cff00ff00MNet:|r Registered alts (" .. count .. "):")
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
        print("|cff00ff00MNet Debug Info:|r")

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

    elseif cmd == "relay" or cmd == "guildrelay" then
        -- Toggle guild relay feature
        MNetDB.enableGuildRelay = not MNetDB.enableGuildRelay
        if MNetDB.enableGuildRelay then
            print("|cff00ff00MNet:|r Guild relay |cff00ff00ENABLED|r - Guildmates without BNet connections will see cross-guild messages.")
            print("  |cffff0000WARNING:|r This feature sends messages on the GUILD addon channel and may cause disconnects with heavy traffic.")
        else
            print("|cff00ff00MNet:|r Guild relay |cffff0000DISABLED|r - Only you will see cross-guild messages from your BNet friends.")
        end

    elseif cmd == "relayroster" then
        -- Toggle roster relay to guild
        MNetDB.relayRosterToGuild = not MNetDB.relayRosterToGuild
        if MNetDB.relayRosterToGuild then
            print("|cff00ff00MNet:|r Roster relay to guild |cff00ff00ENABLED|r")
            print("  |cffff0000WARNING:|r Roster data is LARGE and is the #1 cause of disconnects. Use at your own risk!")
        else
            print("|cff00ff00MNet:|r Roster relay to guild |cffff0000DISABLED|r - Roster updates stay on BNet only (recommended)")
        end

    elseif cmd == "party" or cmd == "partysync" then
        -- Party sync is now always local-only (no network traffic)
        print("|cff00ff00MNet:|r Party indicators are now |cff00ff00LOCAL-ONLY|r")
        print("  Party icons show only members in |cffffd700YOUR|r party/raid")
        print("  |cff888888No network traffic - eliminates party sync disconnects!|r")

    elseif cmd == "traffic" then
        -- Toggle traffic debugging
        GB.enableTrafficDebug = not GB.enableTrafficDebug
        MNetDB.enableTrafficDebug = GB.enableTrafficDebug  -- Persist across reloads
        if GB.enableTrafficDebug then
            print("|cff00ff00MNet:|r Traffic debugging |cff00ff00ENABLED|r (persists across reloads)")
            print("  You'll see real-time traffic stats in chat. Use /mn traffic again to disable.")
            -- Reset stats when enabling
            GB.trafficStats = {
                bnet = 0, whisper = 0, guild = 0, lastReset = GetTime(),
                handshakes = 0, rosterFull = 0, rosterDelta = 0, rosterRequest = 0, party = 0, chat = 0
            }
        else
            print("|cff00ff00MNet:|r Traffic debugging |cffff0000DISABLED|r")
        end

    elseif cmd == "stats" then
        -- Show traffic stats
        local now = GetTime()
        local elapsed = now - GB.trafficStats.lastReset
        if GB.trafficStats.lastReset == 0 then
            print("|cff00ff00MNet:|r Traffic stats not available yet. Use |cffffd700/mn traffic|r to enable tracking.")
            return
        end

        local total = GB.trafficStats.bnet + GB.trafficStats.whisper + GB.trafficStats.guild
        print("|cff00ff00MNet Traffic Stats|r (last " .. math.floor(elapsed) .. "s):")
        print("  BNet messages: " .. GB.trafficStats.bnet .. " (" .. string.format("%.2f", GB.trafficStats.bnet / elapsed) .. "/sec)")
        print("  Whisper messages: " .. GB.trafficStats.whisper .. " (" .. string.format("%.2f", GB.trafficStats.whisper / elapsed) .. "/sec)")
        print("  Guild relay: " .. GB.trafficStats.guild .. " (" .. string.format("%.2f", GB.trafficStats.guild / elapsed) .. "/sec)")
        print("  |cffffd700Total:|r " .. total .. " messages in " .. math.floor(elapsed) .. " seconds")
        print("  |cffffd700Rate:|r " .. string.format("%.1f", total/elapsed) .. " msg/sec")
        print("  |cffffd700Queue:|r BNet=" .. #GB.outgoingQueue .. ", Guild=" .. #GB.guildRelayQueue)

    elseif cmd == "events" then
        -- Toggle event debugging (connection/disconnection tracking)
        GB.enableEventDebug = not GB.enableEventDebug
        MNetDB.enableEventDebug = GB.enableEventDebug  -- Persist across reloads
        if GB.enableEventDebug then
            print("|cff00ff00MNet:|r Event debugging |cff00ff00ENABLED|r (persists across reloads)")
            print("  You'll see connection/disconnection events in chat.")
            print("  Useful for debugging zone change disconnects.")
            print("  Use /mn events again to disable.")
        else
            print("|cff00ff00MNet:|r Event debugging |cffff0000DISABLED|r")
        end

    elseif cmd == "help" then
        print("|cff00ff00MNet Commands:|r")
        print("  |cffffd700/mn|r - Toggle MNet window")
        print("  |cffffd700/mn traffic|r - Toggle traffic debugging")
        print("  |cffffd700/mn events|r - Toggle event debugging (zone change, connect/disconnect)")
        print("  |cffffd700/mn stats|r - Show traffic statistics")
        print("  |cffffd700/mn relay|r - Toggle guild chat relay (default ON)")
        print("  |cffffd700/mn relayroster|r - Toggle roster relay to guild (default ON)")
        print("  |cffffd700/mn alt <Name-Realm>|r - Register a same-account alt")
        print("  |cffffd700/mn removealt <Name-Realm>|r - Remove a registered alt")
        print("  |cffffd700/mn alts|r - List registered alts")
        print("  |cffffd700/mn debug|r - Show debug info")
        print("  |cffffd700/mn help|r - Show this help")

    else
        print("|cff00ff00MNet:|r Unknown command '" .. cmd .. "'. Use |cffffd700/mn help|r for commands.")
    end
end
