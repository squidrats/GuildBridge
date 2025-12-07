local addonName = ...
local bridgePayloadPrefix = "[GB]"
local bridgeAddonPrefix = "GuildBridge"

local mainFrame
local scrollFrame
local inputBox

local eventFrame = CreateFrame("Frame")

local partnerBattleTag
local partnerGameAccountID
local lastEchoedGuildText

local guildShortNames = {
    ["MAKE ELWYNN GREAT AGAIN"] = "MEGA",
    ["MAKE DUROTAR GREAT AGAIN"] = "MDGA",
}

local function ensureSavedVariables()
    if not GuildBridgeDB then
        GuildBridgeDB = {}
    end
    if GuildBridgeDB.bridgeEnabled == nil then
        GuildBridgeDB.bridgeEnabled = false
    end
    if GuildBridgeDB.partnerBattleTag == nil then
        GuildBridgeDB.partnerBattleTag = ""
    end
    partnerBattleTag = GuildBridgeDB.partnerBattleTag
end

local function findPartnerGameAccount()
    partnerGameAccountID = nil
    if not partnerBattleTag or partnerBattleTag == "" then
        print("GuildBridge: no partner BattleTag configured. Use /gbridge partner Battletag#1234")
        return false
    end

    local numFriends = BNGetNumFriends()
    if not numFriends or numFriends == 0 then
        print("GuildBridge: no Battle.net friends found.")
        return false
    end

    local wanted = string.lower(partnerBattleTag)

    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.battleTag then
            local friendTag = string.lower(accountInfo.battleTag)
            if friendTag == wanted then
                local numGames = C_BattleNet.GetFriendNumGameAccounts(i)
                if numGames and numGames > 0 then
                    for j = 1, numGames do
                        local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                        if gameInfo and gameInfo.isOnline and gameInfo.clientProgram == "WoW" then
                            partnerGameAccountID = gameInfo.gameAccountID
                            print("GuildBridge: found partner relay:", gameInfo.characterName, "-" .. (gameInfo.realmName or ""), "id", gameInfo.gameAccountID)
                            return true
                        end
                    end
                end
                print("GuildBridge: partner BattleTag found, but no WoW character online.")
                return false
            end
        end
    end

    print("GuildBridge: partner BattleTag " .. partnerBattleTag .. " not found in friends list.")
    return false
end

local function addBridgeMessage(senderName, guildName, factionTag, messageText)
    if not scrollFrame then
        return
    end

    local short = guildShortNames[guildName] or guildName or ""
    local guildTag = short ~= "" and ("<" .. short .. "> ") or ""
    local senderColored = "|cff00ff00" .. senderName .. "|r"

    scrollFrame:AddMessage(guildTag .. senderColored .. ": " .. messageText)
end

local function sendBridgePayload(originName, messageText, sourceType)
    if not partnerGameAccountID then
        return
    end
    if not messageText or messageText == "" then
        return
    end
    sourceType = sourceType or "U"

    local playerGuildName = GetGuildInfo("player")
    local factionGroup = select(1, UnitFactionGroup("player")) or "Unknown"

    local payload = bridgePayloadPrefix
        .. (playerGuildName or "")
        .. "|"
        .. factionGroup
        .. "|"
        .. originName
        .. "|"
        .. sourceType
        .. "|"
        .. messageText

    local ok, err = pcall(BNSendGameData, partnerGameAccountID, bridgeAddonPrefix, payload)
    if not ok then
        print("GuildBridge: BNSendGameData error:", err)
    end
end

local function sendFromUI(messageText)
    local originName = UnitName("player")
    sendBridgePayload(originName, messageText, "U")
end

local function mirrorToGuild(senderName, guildName, factionTag, messageText, sourceType)
    if not GuildBridgeDB.bridgeEnabled then
        return
    end
    if not IsInGuild() then
        return
    end

    local myGuildName = GetGuildInfo("player")
    if not myGuildName then
        return
    end

    if sourceType == "G" and guildName == myGuildName then
        return
    end

    local short = guildShortNames[guildName] or guildName or ""
    local guildTag = short ~= "" and ("<" .. short .. "> ") or ""
    local line = guildTag .. senderName .. ": " .. messageText

    lastEchoedGuildText = line
    SendChatMessage(line, "GUILD")
end

local function handleGuildChatMessage(text, sender)
    if not GuildBridgeDB.bridgeEnabled then
        return
    end
    if not IsInGuild() then
        return
    end
    if not partnerGameAccountID then
        return
    end
    if not text or text == "" then
        return
    end

    local originName = sender:match("([^%-]+)") or sender
    local myName = UnitName("player")

    if lastEchoedGuildText and text == lastEchoedGuildText and originName == myName then
        lastEchoedGuildText = nil
        return
    end

    sendBridgePayload(originName, text, "G")
end

local function handleBNAddonMessage(prefix, message)
    if prefix ~= bridgeAddonPrefix then
        return
    end

    local text = message
    if not text or text:sub(1, #bridgePayloadPrefix) ~= bridgePayloadPrefix then
        return
    end

    local payload = text:sub(#bridgePayloadPrefix + 1)
    local guildPart, factionPart, originPart, sourcePart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

    if not messagePart or not originPart or not sourcePart then
        return
    end

    if guildPart == "" then
        guildPart = nil
    end

    addBridgeMessage(originPart, guildPart, factionPart, messagePart)
    mirrorToGuild(originPart, guildPart, factionPart, messagePart, sourcePart)
end

local function createBridgeUI()
    if mainFrame then
        return
    end

    mainFrame = CreateFrame("Frame", "GuildBridgeFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(420, 260)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainFrame.title:SetPoint("LEFT", mainFrame.TitleBg, "LEFT", 5, 0)
    mainFrame.title:SetText("Guild Bridge")

    scrollFrame = CreateFrame("ScrollingMessageFrame", nil, mainFrame)
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 40)
    scrollFrame:SetFontObject(GameFontHighlightSmall)
    scrollFrame:SetJustifyH("LEFT")
    scrollFrame:SetFading(false)
    scrollFrame:SetMaxLines(500)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        elseif delta < 0 then
            self:ScrollDown()
        end
    end)

    inputBox = CreateFrame("EditBox", nil, mainFrame, "InputBoxTemplate")
    inputBox:SetPoint("BOTTOMLEFT", 10, 10)
    inputBox:SetPoint("BOTTOMRIGHT", -10, 10)
    inputBox:SetHeight(20)
    inputBox:SetAutoFocus(false)
    inputBox:SetFontObject(GameFontHighlightSmall)

    inputBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        sendFromUI(text)
        self:SetText("")
    end)

    inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
end

local function toggleBridgeFrame()
    if not mainFrame then
        return
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")
eventFrame:RegisterEvent("BN_CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            ensureSavedVariables()
            C_ChatInfo.RegisterAddonMessagePrefix(bridgeAddonPrefix)
            createBridgeUI()
        end
    elseif event == "PLAYER_LOGIN" then
        findPartnerGameAccount()
    elseif event == "CHAT_MSG_GUILD" then
        local text, sender = ...
        handleGuildChatMessage(text, sender)
    elseif event == "BN_CHAT_MSG_ADDON" then
        local prefix, message = ...
        handleBNAddonMessage(prefix, message)
    end
end)

SLASH_GUILDBRIDGE1 = "/gbridge"
SlashCmdList["GUILDBRIDGE"] = function(msg)
    msg = msg or ""
    msg = msg:lower()

    if msg == "" or msg == "show" then
        toggleBridgeFrame()
    elseif msg == "enable" then
        ensureSavedVariables()
        GuildBridgeDB.bridgeEnabled = true
        print("GuildBridge: mirroring enabled on this character.")
    elseif msg == "disable" then
        ensureSavedVariables()
        GuildBridgeDB.bridgeEnabled = false
        print("GuildBridge: mirroring disabled on this character.")
    elseif msg == "status" then
        ensureSavedVariables()
        local status = GuildBridgeDB.bridgeEnabled and "enabled" or "disabled"
        print("GuildBridge: mirroring is " .. status .. " on this character.")
    elseif msg:sub(1, 7) == "partner" then
        local btag = msg:match("^partner%s+(.+)$")
        ensureSavedVariables()
        if btag and btag ~= "" then
            GuildBridgeDB.partnerBattleTag = btag
            partnerBattleTag = btag
            print("GuildBridge: partner BattleTag set to " .. btag)
            findPartnerGameAccount()
        else
            print("GuildBridge: usage: /gbridge partner Battletag#1234")
        end
    elseif msg == "reload" then
        ensureSavedVariables()
        findPartnerGameAccount()
        print("GuildBridge: partner info refreshed.")
    else
        print("GuildBridge: /gbridge, /gbridge show, /gbridge enable, /gbridge disable, /gbridge status, /gbridge partner Battletag#1234, /gbridge reload")
    end
end
