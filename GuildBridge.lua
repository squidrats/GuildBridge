local addonName = ...
local bridgePayloadPrefix = "[GB]"
local bridgeAddonPrefix = "GuildBridge"

local mainFrame
local scrollFrame
local inputBox
local tabButtons = {}
local muteCheckbox

local eventFrame = CreateFrame("Frame")

-- Current filter: nil = All, or guild-realm key
local currentFilter = nil
-- Store messages for filtering
local messageHistory = {}
-- Track unique guild+realm combinations we've seen
local knownGuilds = {}

local partnerBattleTag
local partnerGameAccountID

local guildShortNames = {
    ["MAKE ELWYNN GREAT AGAIN"] = "MEGA",
    ["MAKE DUROTAR GREAT AGAIN"] = "MDGA",
    ["Bestiez"] = "Bestiez",
}

-- Only relay messages from these guilds
local allowedGuilds = {
    ["MAKE ELWYNN GREAT AGAIN"] = true,
    ["MAKE DUROTAR GREAT AGAIN"] = true,
    ["Bestiez"] = true,
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
    if GuildBridgeDB.muteSend == nil then
        GuildBridgeDB.muteSend = false
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


-- Create a filter key from guild name and realm
local function makeFilterKey(guildName, realmName)
    if not guildName then return nil end
    if realmName and realmName ~= "" then
        return guildName .. "-" .. realmName
    end
    return guildName
end

-- Forward declaration
local registerGuild

local function refreshMessages()
    if not scrollFrame then return end
    scrollFrame:Clear()
    for _, msg in ipairs(messageHistory) do
        if currentFilter == nil or msg.filterKey == currentFilter then
            scrollFrame:AddMessage(msg.formatted)
        end
    end
end

local function addBridgeMessage(senderName, guildName, factionTag, messageText, realmName)
    local short = guildShortNames[guildName] or guildName or ""
    -- Include realm in the tag to distinguish same-name guilds
    local realmSuffix = ""
    if realmName and realmName ~= "" then
        realmSuffix = "-" .. realmName
    end
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""

    -- Create a clickable player link for inviting
    local fullName = senderName
    if realmName and realmName ~= "" then
        fullName = senderName .. "-" .. realmName
    end
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff00ff00[" .. senderName .. "]|r|h"

    local formattedMessage = guildTag .. senderLink .. ": " .. messageText
    local filterKey = makeFilterKey(guildName, realmName)

    -- Register this guild for tab creation
    registerGuild(guildName, realmName)

    -- Store message for filtering
    table.insert(messageHistory, {
        guildName = guildName,
        realmName = realmName,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    -- Keep history limited
    if #messageHistory > 500 then
        table.remove(messageHistory, 1)
    end

    -- Add to the bridge UI if it matches current filter
    if scrollFrame and (currentFilter == nil or filterKey == currentFilter) then
        scrollFrame:AddMessage(formattedMessage)
    end

    -- Add to the default chat frame (guild chat color: green)
    DEFAULT_CHAT_FRAME:AddMessage(formattedMessage, 0.25, 1.0, 0.25)
end

local function sendBridgePayload(originName, originRealm, messageText, sourceType, targetFilter)
    if not partnerGameAccountID then
        return
    end
    if not messageText or messageText == "" then
        return
    end
    sourceType = sourceType or "U"

    local playerGuildName = GetGuildInfo("player")
    local playerRealm = GetRealmName()
    local factionGroup = select(1, UnitFactionGroup("player")) or "Unknown"

    -- Payload format: guild|guildRealm|faction|originName|originRealm|sourceType|targetFilter|message
    local payload = bridgePayloadPrefix
        .. (playerGuildName or "")
        .. "|"
        .. (playerRealm or "")
        .. "|"
        .. factionGroup
        .. "|"
        .. originName
        .. "|"
        .. (originRealm or "")
        .. "|"
        .. sourceType
        .. "|"
        .. (targetFilter or "")
        .. "|"
        .. messageText

    local ok, err = pcall(BNSendGameData, partnerGameAccountID, bridgeAddonPrefix, payload)
    if not ok then
        print("GuildBridge: BNSendGameData error:", err)
    end
end

local function sendFromUI(messageText)
    if not messageText or messageText == "" then
        return
    end

    -- If a filter is selected, only send to that guild+realm
    -- If no filter (All), send to all
    local targetFilter = currentFilter

    local originName, originRealm = UnitName("player")
    if not originRealm or originRealm == "" then
        originRealm = GetRealmName()
    end
    local playerGuildName = GetGuildInfo("player")

    -- Show in bridge window only (not default chat) for messages we send from the UI
    local short = guildShortNames[playerGuildName] or playerGuildName or ""
    local realmSuffix = ""
    if originRealm and originRealm ~= "" then
        realmSuffix = "-" .. originRealm
    end
    local guildTag = short ~= "" and ("<" .. short .. realmSuffix .. "> ") or ""
    local fullName = originName .. "-" .. originRealm
    local senderLink = "|Hplayer:" .. fullName .. "|h|cff00ff00[" .. originName .. "]|r|h"
    local formattedMessage = guildTag .. senderLink .. ": " .. messageText
    local filterKey = makeFilterKey(playerGuildName, originRealm)

    -- Store message for filtering
    table.insert(messageHistory, {
        guildName = playerGuildName,
        realmName = originRealm,
        filterKey = filterKey,
        formatted = formattedMessage,
    })
    if #messageHistory > 500 then
        table.remove(messageHistory, 1)
    end

    if scrollFrame and (currentFilter == nil or filterKey == currentFilter) then
        scrollFrame:AddMessage(formattedMessage)
    end

    sendBridgePayload(originName, originRealm, messageText, "U", targetFilter)
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

    -- Check if mute send is enabled
    if GuildBridgeDB.muteSend then
        return
    end

    -- Only relay from allowed guilds
    local myGuildName = GetGuildInfo("player")
    if not myGuildName or not allowedGuilds[myGuildName] then
        return
    end

    local originName, originRealm = sender:match("([^%-]+)%-?(.*)")
    originName = originName or sender
    if not originRealm or originRealm == "" then
        originRealm = GetRealmName()
    end

    sendBridgePayload(originName, originRealm, text, "G")
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
    -- New format: guild|guildRealm|faction|originName|originRealm|sourceType|targetFilter|message
    local guildPart, guildRealmPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messagePart =
        payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")

    -- Fallback for old format
    if not messagePart then
        guildPart, factionPart, originPart, originRealmPart, sourcePart, targetPart, messagePart =
            payload:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.+)")
        guildRealmPart = originRealmPart -- best guess for old format
    end

    if not messagePart or not originPart or not sourcePart then
        return
    end

    if guildPart == "" then
        guildPart = nil
    end
    if guildRealmPart == "" then
        guildRealmPart = nil
    end
    if originRealmPart == "" then
        originRealmPart = nil
    end
    if targetPart == "" then
        targetPart = nil
    end

    -- Only accept messages from allowed guilds
    if guildPart and not allowedGuilds[guildPart] then
        return
    end

    -- If message has a target filter (guild-realm), only process if we match
    if targetPart and targetPart ~= "" then
        local myGuildName = GetGuildInfo("player")
        local myRealm = GetRealmName()
        local myFilterKey = makeFilterKey(myGuildName, myRealm)
        if myFilterKey ~= targetPart then
            return
        end
    end

    -- Use guild realm for the message display (to distinguish same-name guilds)
    addBridgeMessage(originPart, guildPart, factionPart, messagePart, guildRealmPart)
end

local function updateTabHighlights()
    for _, tab in pairs(tabButtons) do
        if tab.filterValue == currentFilter then
            tab.guildText:SetFontObject(GameFontHighlight)
            tab.selected = true
        else
            tab.guildText:SetFontObject(GameFontNormal)
            tab.selected = false
        end
    end
end

local function createTab(parent, guildLabel, realmLabel, filterValue, xOffset)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(70, 32)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, -22)
    tab.filterValue = filterValue

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    -- Guild name (main label)
    tab.guildText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.guildText:SetPoint("TOP", tab, "TOP", 0, -4)
    tab.guildText:SetText(guildLabel)

    -- Realm name (smaller, below)
    if realmLabel and realmLabel ~= "" then
        tab.realmText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tab.realmText:SetPoint("TOP", tab.guildText, "BOTTOM", 0, -1)
        tab.realmText:SetText(realmLabel)
        tab.realmText:SetTextColor(0.6, 0.6, 0.6)
    end

    tab:SetScript("OnClick", function()
        currentFilter = filterValue
        updateTabHighlights()
        refreshMessages()
    end)

    tab:SetScript("OnEnter", function(self)
        self.guildText:SetFontObject(GameFontHighlight)
    end)

    tab:SetScript("OnLeave", function(self)
        if not self.selected then
            self.guildText:SetFontObject(GameFontNormal)
        end
    end)

    return tab
end

local function rebuildTabs()
    if not mainFrame then return end

    -- Clear existing tabs
    for key, tab in pairs(tabButtons) do
        tab:Hide()
        tab:SetParent(nil)
    end
    tabButtons = {}

    -- Create "All" tab
    local xOffset = 10
    tabButtons.all = createTab(mainFrame, "All", nil, nil, xOffset)
    xOffset = xOffset + 50

    -- Create tabs for each known guild
    local tabIndex = 1
    for filterKey, info in pairs(knownGuilds) do
        local short = guildShortNames[info.guildName] or info.guildName or "?"
        local realmLabel = info.realmName
        tabButtons["guild" .. tabIndex] = createTab(mainFrame, short, realmLabel, filterKey, xOffset)
        xOffset = xOffset + 75
        tabIndex = tabIndex + 1
    end

    updateTabHighlights()
end

registerGuild = function(guildName, realmName)
    if not guildName then return end
    local filterKey = makeFilterKey(guildName, realmName)
    if not knownGuilds[filterKey] then
        knownGuilds[filterKey] = {
            guildName = guildName,
            realmName = realmName,
        }
        rebuildTabs()
    end
end

local function createBridgeUI()
    if mainFrame then
        return
    end

    mainFrame = CreateFrame("Frame", "GuildBridgeFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(420, 300)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainFrame.title:SetPoint("LEFT", mainFrame.TitleBg, "LEFT", 5, 0)
    mainFrame.title:SetText("Guild Bridge")

    -- Create initial "All" tab - more tabs added dynamically as guilds are seen
    rebuildTabs()

    -- Mute own guild checkbox
    muteCheckbox = CreateFrame("CheckButton", nil, mainFrame, "UICheckButtonTemplate")
    muteCheckbox:SetSize(24, 24)
    muteCheckbox:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -10, -22)
    muteCheckbox.text = muteCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    muteCheckbox.text:SetPoint("RIGHT", muteCheckbox, "LEFT", -2, 0)
    muteCheckbox.text:SetText("Mute Send")
    muteCheckbox:SetChecked(GuildBridgeDB.muteSend or false)
    muteCheckbox:SetScript("OnClick", function(self)
        GuildBridgeDB.muteSend = self:GetChecked()
    end)

    scrollFrame = CreateFrame("ScrollingMessageFrame", nil, mainFrame)
    scrollFrame:SetPoint("TOPLEFT", 10, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 40)
    scrollFrame:SetFontObject(GameFontHighlightSmall)
    scrollFrame:SetJustifyH("LEFT")
    scrollFrame:SetFading(false)
    scrollFrame:SetMaxLines(500)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetHyperlinksEnabled(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        elseif delta < 0 then
            self:ScrollDown()
        end
    end)
    scrollFrame:SetScript("OnHyperlinkClick", function(self, link, text, button)
        SetItemRef(link, text, button)
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

    mainFrame:Hide() -- start hidden, show with /gb
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
SLASH_GUILDBRIDGE2 = "/gb"
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
