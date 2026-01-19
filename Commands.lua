local addonName, GB = ...

SLASH_MDGANET1 = "/mn"
SLASH_MDGANET2 = "/mdganet"
SlashCmdList["MDGANET"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()

    if cmd == "" then
        GB:ToggleBridgeFrame()

    elseif cmd == "alt" or cmd == "addalt" then
        if arg == "" then
            print("|cff00ff00MNet:|r Usage: /mn alt CharacterName-Realm")
            print("  Example: /mn alt Myalt-Illidan")
            return
        end

        if not arg:find("-") then
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
            GB:SendWhisperHandshakeToAlt(arg)
        end

    elseif cmd == "removealt" or cmd == "delalt" then
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
        print("|cff00ff00MNet Debug Info:|r")

        local myGuildName = GetGuildInfo("player")
        local myGuildHomeRealm = GB:GetGuildHomeRealm()
        local myGuildClubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        print("|cffffd700My Guild:|r " .. (myGuildName or "none"))
        print("  Home Realm: " .. (myGuildHomeRealm or "nil"))
        print("  Club ID: " .. tostring(myGuildClubId or "nil"))

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

        print("|cffffd700Current Filter:|r " .. (GB.currentFilter or "All"))

    elseif cmd == "relay" or cmd == "guildrelay" then
        MNetDB.enableGuildRelay = not MNetDB.enableGuildRelay
        if MNetDB.enableGuildRelay then
            print("|cff00ff00MNet:|r Guild relay |cff00ff00ENABLED|r - Guildmates without BNet connections will see cross-guild messages.")
            print("  |cffff0000WARNING:|r This feature sends messages on the GUILD addon channel and may cause disconnects with heavy traffic.")
        else
            print("|cff00ff00MNet:|r Guild relay |cffff0000DISABLED|r - Only you will see cross-guild messages from your BNet friends.")
        end

    elseif cmd == "relayroster" then
        MNetDB.relayRosterToGuild = not MNetDB.relayRosterToGuild
        if MNetDB.relayRosterToGuild then
            print("|cff00ff00MNet:|r Roster relay to guild |cff00ff00ENABLED|r")
            print("  |cffff0000WARNING:|r Roster data is LARGE and is the #1 cause of disconnects. Use at your own risk!")
        else
            print("|cff00ff00MNet:|r Roster relay to guild |cffff0000DISABLED|r - Roster updates stay on BNet only (recommended)")
        end

    elseif cmd == "party" or cmd == "partysync" then
        print("|cff00ff00MNet:|r Party indicators are now |cff00ff00LOCAL-ONLY|r")
        print("  Party icons show only members in |cffffd700YOUR|r party/raid")
        print("  |cff888888No network traffic - eliminates party sync disconnects!|r")

    elseif cmd == "traffic" then
        GB.enableTrafficDebug = not GB.enableTrafficDebug
        MNetDB.enableTrafficDebug = GB.enableTrafficDebug
        if GB.enableTrafficDebug then
            print("|cff00ff00MNet:|r Traffic debugging |cff00ff00ENABLED|r (persists across reloads)")
            print("  You'll see real-time traffic stats in chat. Use /mn traffic again to disable.")
            GB.trafficStats = {
                bnet = 0, whisper = 0, guild = 0, lastReset = GetTime(),
                handshakes = 0, rosterFull = 0, rosterDelta = 0, rosterRequest = 0, party = 0, chat = 0
            }
        else
            print("|cff00ff00MNet:|r Traffic debugging |cffff0000DISABLED|r")
        end

    elseif cmd == "stats" then
        local now = GetTime()
        local elapsed = now - GB.trafficStats.lastReset
        if GB.trafficStats.lastReset == 0 then
            print("|cff00ff00MNet:|r Traffic stats not available yet. Use |cffffd700/mn traffic|r to enable tracking.")
            return
        end

        local total = GB.trafficStats.bnet + GB.trafficStats.whisper + GB.trafficStats.guild
        local bytesPerSec, _ = GB:GetBytesPerSecond()
        local bytesColor = bytesPerSec > GB.BYTES_WARNING_THRESHOLD and "|cffff0000" or "|cff00ff00"

        print("|cff00ff00MNet Traffic Stats|r (last " .. math.floor(elapsed) .. "s):")
        print("  BNet messages: " .. GB.trafficStats.bnet .. " (" .. string.format("%.2f", GB.trafficStats.bnet / elapsed) .. "/sec)")
        print("  Whisper messages: " .. GB.trafficStats.whisper .. " (" .. string.format("%.2f", GB.trafficStats.whisper / elapsed) .. "/sec)")
        print("  Guild relay: " .. GB.trafficStats.guild .. " (" .. string.format("%.2f", GB.trafficStats.guild / elapsed) .. "/sec)")
        print("  |cffffd700Total:|r " .. total .. " messages in " .. math.floor(elapsed) .. " seconds")
        print("  |cffffd700Rate:|r " .. string.format("%.1f", total/elapsed) .. " msg/sec")
        print("  |cffffd700Queue:|r BNet=" .. #GB.outgoingQueue .. ", Guild=" .. #GB.guildRelayQueue)
        print("  |cffffd700Bytes:|r " .. GB.trafficStats.bytesOut .. " total, " .. bytesColor .. string.format("%.0f", bytesPerSec) .. " B/s|r (warn: " .. GB.BYTES_WARNING_THRESHOLD .. ")")

    elseif cmd == "events" then
        GB.enableEventDebug = not GB.enableEventDebug
        MNetDB.enableEventDebug = GB.enableEventDebug
        if GB.enableEventDebug then
            print("|cff00ff00MNet:|r Event debugging |cff00ff00ENABLED|r (persists across reloads)")
            print("  You'll see connection/disconnection events in chat.")
            print("  Useful for debugging zone change disconnects.")
            print("  Use /mn events again to disable.")
        else
            print("|cff00ff00MNet:|r Event debugging |cffff0000DISABLED|r")
        end

    elseif cmd == "relaystatus" or cmd == "rs" then
        print("|cff00ff00MNet Relay Status:|r")
        local myFullName = GB:GetMyFullName()
        print("  My name: |cffffd700" .. myFullName .. "|r")
        print("  Guild relay enabled: " .. (MNetDB.enableGuildRelay and "|cff00ff00YES|r" or "|cffff0000NO|r"))

        local connectedGuilds = GB:GetConnectedGuildClubIds()
        local guildCount = 0
        for _ in pairs(connectedGuilds) do guildCount = guildCount + 1 end

        if guildCount == 0 then
            print("  |cff888888No connections to other guilds|r")
        else
            print("  |cffffd700Connected to " .. guildCount .. " other guild(s):|r")
            local now = GetTime()
            for guildClubIdStr, _ in pairs(connectedGuilds) do
                local isPrimary = GB:AmIPrimaryRelayForGuild(guildClubIdStr)
                local guildName = "Unknown"
                for filterKey, info in pairs(GB.knownGuilds) do
                    if info.guildClubId and tostring(info.guildClubId) == guildClubIdStr then
                        guildName = info.guildName or "Unknown"
                        break
                    end
                end

                local candidates = {}
                table.insert(candidates, myFullName)
                local guildCandidates = GB.relayCandidates[guildClubIdStr]
                if guildCandidates then
                    for candidateName, info in pairs(guildCandidates) do
                        if candidateName ~= myFullName and now - info.lastSeen < GB.RELAY_CANDIDATE_TIMEOUT then
                            table.insert(candidates, candidateName)
                        end
                    end
                end
                table.sort(candidates)

                local statusColor = isPrimary and "|cff00ff00" or "|cffff8800"
                local statusText = isPrimary and "PRIMARY" or "STANDBY"
                print("    [" .. guildName .. "] " .. statusColor .. statusText .. "|r (" .. #candidates .. " candidates)")

                if #candidates > 1 then
                    for i, name in ipairs(candidates) do
                        local marker = (i == 1) and " <- primary" or ""
                        local meMarker = (name == myFullName) and " (me)" or ""
                        print("      " .. i .. ". " .. name .. meMarker .. marker)
                    end
                end
            end
        end

    elseif cmd == "help" then
        print("|cff00ff00MNet Commands:|r")
        print("  |cffffd700/mn|r - Toggle MNet window")
        print("  |cffffd700/mn traffic|r - Toggle traffic debugging")
        print("  |cffffd700/mn events|r - Toggle event debugging (zone change, connect/disconnect)")
        print("  |cffffd700/mn stats|r - Show traffic statistics")
        print("  |cffffd700/mn throttle|r - Show throttle/recovery mode status")
        print("  |cffffd700/mn relay|r - Toggle guild chat relay (default ON)")
        print("  |cffffd700/mn relayroster|r - Toggle roster relay to guild (default ON)")
        print("  |cffffd700/mn relaystatus|r - Show relay election status")
        print("  |cffffd700/mn alt <Name-Realm>|r - Register a same-account alt")
        print("  |cffffd700/mn removealt <Name-Realm>|r - Remove a registered alt")
        print("  |cffffd700/mn alts|r - List registered alts")
        print("  |cffffd700/mn debug|r - Show debug info")
        print("  |cffffd700/mn help|r - Show this help")
        print("  |cffffd700/mnstress|r - Stress test commands (for D/C debugging)")

    elseif cmd == "throttle" then
        print("|cff00ff00MNet Throttle Status:|r")
        local now = GetTime()
        local timeSinceZone = now - GB.lastPlayerEnteringWorld
        local timeSinceSend = now - GB.lastGlobalSendTime
        local inTransition = GB:IsInZoneTransition()
        local bytesPerSec = GB:GetBytesPerSecond()
        local isDataThrottled = bytesPerSec > GB.BYTES_THROTTLE_THRESHOLD
        local currentDelay = GB:GetCurrentThrottleDelay()

        local mode = "normal"
        if inTransition then
            mode = "|cffff0000PAUSED (zone transition)|r"
        elseif isDataThrottled then
            mode = "|cffff8800DATA THROTTLE|r"
        else
            mode = "|cff00ff00NORMAL|r"
        end

        print("  Mode: " .. mode)
        print("  Data rate: " .. string.format("%.0f", bytesPerSec) .. " B/s (throttle at " .. GB.BYTES_THROTTLE_THRESHOLD .. ")")
        print("  Time since zone change: " .. string.format("%.1f", timeSinceZone) .. "s")
        print("  Time since last send: " .. string.format("%.1f", timeSinceSend) .. "s")
        print("  Current throttle delay: " .. currentDelay .. "s")
        print("  Can send now: " .. (GB:CanSendGlobally() and "|cff00ff00YES|r" or "|cffff0000NO|r"))
        print("  Queue sizes: BNet=" .. #GB.outgoingQueue .. ", Guild=" .. #GB.guildRelayQueue)

    else
        print("|cff00ff00MNet:|r Unknown command '" .. cmd .. "'. Use |cffffd700/mn help|r for commands.")
    end
end

-- Stress test command for debugging D/C issues
GB.stressTestTimer = nil
GB.stressTestRunning = false

SLASH_MNSTRESS1 = "/mnstress"
SlashCmdList["MNSTRESS"] = function(msg)
    msg = msg:lower():trim()

    if msg == "" or msg == "help" then
        print("|cffff8800[MNet Stress Test]|r Commands:")
        print("  |cffffd700/mnstress status|r - Show current state and queue sizes")
        print("  |cffffd700/mnstress burst|r - Trigger handshakes + roster requests to all connections")
        print("  |cffffd700/mnstress continuous|r - Keep queuing messages until stopped")
        print("  |cffffd700/mnstress stop|r - Stop continuous mode")
        print("  |cffffd700/mnstress handshake|r - Send handshakes to all connections")
        print("  |cffffd700/mnstress roster|r - Request full rosters from all connections")
        print("")
        print("  |cffff0000Usage:|r Run continuous on all accounts, zone whenever, then stop")
        if GB.stressTestRunning then
            print("")
            print("  |cff00ff00>>> CONTINUOUS MODE ACTIVE <<<|r")
        end
        return
    end

    if msg == "status" then
        print("|cffff8800[MNet Stress Test]|r Current State:")
        local now = GetTime()

        -- Continuous mode status
        if GB.stressTestRunning then
            print("  |cff00ff00>>> CONTINUOUS MODE ACTIVE <<<|r")
        end

        -- Connection counts
        local bnetCount = 0
        for _ in pairs(GB.connectedBridgeUsers) do bnetCount = bnetCount + 1 end
        local altCount = 0
        for _ in pairs(GB.connectedWhisperAlts) do altCount = altCount + 1 end

        print("  BNet connections: " .. bnetCount)
        print("  Whisper alt connections: " .. altCount)
        print("  BNet queue: " .. #GB.outgoingQueue)
        print("  Guild relay queue: " .. #GB.guildRelayQueue)

        -- Throttle state
        local inTransition = GB:IsInZoneTransition()
        local bytesPerSec = GB:GetBytesPerSecond()
        local isDataThrottled = bytesPerSec > GB.BYTES_THROTTLE_THRESHOLD
        local mode = inTransition and "|cffff0000PAUSED|r" or (isDataThrottled and "|cffff8800DATA THROTTLE|r" or "|cff00ff00NORMAL|r")
        print("  Throttle mode: " .. mode)
        print("  Data rate: " .. string.format("%.0f", bytesPerSec) .. " B/s")
        print("  Current delay: " .. GB:GetCurrentThrottleDelay() .. "s")

        -- Roster sizes
        local rosterCount = 0
        local totalMembers = 0
        for filterKey, roster in pairs(GB.guildRosters) do
            rosterCount = rosterCount + 1
            local memberCount = 0
            if roster.members then
                for _ in pairs(roster.members) do memberCount = memberCount + 1 end
            end
            totalMembers = totalMembers + memberCount
        end
        print("  Rosters tracked: " .. rosterCount .. " (" .. totalMembers .. " total members)")

        return
    end

    if msg == "handshake" then
        print("|cffff8800[MNet Stress Test]|r Sending handshakes to all connections...")

        local count = 0
        -- Force handshakes to BNet friends
        GB:ForceSendHandshake()
        for _ in pairs(GB.connectedBridgeUsers) do count = count + 1 end

        -- Force handshakes to whisper alts
        GB:ForceSendWhisperHandshake()
        for _ in pairs(GB.connectedWhisperAlts) do count = count + 1 end

        print("  Queued handshakes to " .. count .. " connections")
        print("  Queue size now: " .. #GB.outgoingQueue)
        return
    end

    if msg == "roster" then
        print("|cffff8800[MNet Stress Test]|r Requesting full rosters from all connections...")

        local count = 0
        for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
            if info.guildClubId then
                GB:RequestFullRoster(gameAccountID, info.guildClubId, "bnet")
                count = count + 1
            end
        end

        for altName, info in pairs(GB.connectedWhisperAlts) do
            if info.guildClubId then
                GB:RequestFullRoster(altName, info.guildClubId, "whisper")
                count = count + 1
            end
        end

        print("  Queued " .. count .. " roster requests")
        print("  Queue size now: " .. #GB.outgoingQueue)
        return
    end

    if msg == "burst" then
        print("|cffff8800[MNet Stress Test]|r BURST MODE - Triggering all activity...")

        -- Count connections first
        local bnetCount = 0
        for _ in pairs(GB.connectedBridgeUsers) do bnetCount = bnetCount + 1 end
        local altCount = 0
        for _ in pairs(GB.connectedWhisperAlts) do altCount = altCount + 1 end

        print("  Step 1: Sending handshakes...")
        GB:ForceSendHandshake()
        GB:ForceSendWhisperHandshake()

        print("  Step 2: Requesting rosters...")
        local rosterCount = 0
        for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
            if info.guildClubId then
                GB:RequestFullRoster(gameAccountID, info.guildClubId, "bnet")
                rosterCount = rosterCount + 1
            end
        end
        for altName, info in pairs(GB.connectedWhisperAlts) do
            if info.guildClubId then
                GB:RequestFullRoster(altName, info.guildClubId, "whisper")
                rosterCount = rosterCount + 1
            end
        end

        print("  Step 3: Broadcasting roster delta...")
        if GB.ProcessGuildRosterUpdate then
            GB:ProcessGuildRosterUpdate()
        end

        print("")
        print("|cffff8800[MNet Stress Test]|r Burst complete!")
        print("  Handshakes queued to: " .. (bnetCount + altCount) .. " connections")
        print("  Roster requests queued: " .. rosterCount)
        print("  BNet queue size: " .. #GB.outgoingQueue)
        print("  Guild queue size: " .. #GB.guildRelayQueue)
        print("")
        print("|cffff0000NOW ZONE IMMEDIATELY|r to test for D/C!")
        return
    end

    if msg == "continuous" or msg == "start" then
        if GB.stressTestRunning then
            print("|cffff8800[MNet Stress Test]|r Continuous mode already running!")
            print("  Use |cffffd700/mnstress stop|r to stop it first.")
            return
        end

        GB.stressTestRunning = true
        local interval = 3 -- Queue new messages every 3 seconds

        print("|cffff8800[MNet Stress Test]|r Starting CONTINUOUS MODE...")
        print("  Queuing handshakes + roster requests every " .. interval .. " seconds")
        print("  Use |cffffd700/mnstress stop|r to stop")
        print("")
        print("|cff00ff00Zone whenever you want - traffic will keep flowing!|r")

        local function stressLoop()
            if not GB.stressTestRunning then
                return
            end

            -- Queue handshakes
            GB:ForceSendHandshake()
            GB:ForceSendWhisperHandshake()

            -- Queue roster requests
            for gameAccountID, info in pairs(GB.connectedBridgeUsers) do
                if info.guildClubId then
                    GB:RequestFullRoster(gameAccountID, info.guildClubId, "bnet")
                end
            end
            for altName, info in pairs(GB.connectedWhisperAlts) do
                if info.guildClubId then
                    GB:RequestFullRoster(altName, info.guildClubId, "whisper")
                end
            end

            -- Log queue size
            if GB.enableTrafficDebug then
                print("|cffff8800[Stress]|r Queued burst - BNet: " .. #GB.outgoingQueue .. ", Guild: " .. #GB.guildRelayQueue)
            end

            -- Schedule next burst
            GB.stressTestTimer = C_Timer.After(interval, stressLoop)
        end

        -- Start immediately
        stressLoop()
        return
    end

    if msg == "stop" then
        if not GB.stressTestRunning then
            print("|cffff8800[MNet Stress Test]|r Continuous mode is not running.")
            return
        end

        GB.stressTestRunning = false
        if GB.stressTestTimer then
            GB.stressTestTimer:Cancel()
            GB.stressTestTimer = nil
        end

        print("|cffff8800[MNet Stress Test]|r Continuous mode |cffff0000STOPPED|r")
        print("  Remaining queue: BNet=" .. #GB.outgoingQueue .. ", Guild=" .. #GB.guildRelayQueue)
        return
    end

    print("|cffff8800[MNet Stress Test]|r Unknown command. Use |cffffd700/mnstress help|r")
end
