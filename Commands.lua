-- GuildBridge Commands Module
-- Slash command handlers

local addonName, GB = ...

SLASH_GUILDBRIDGE1 = "/gbridge"
SLASH_GUILDBRIDGE2 = "/gb"
SlashCmdList["GUILDBRIDGE"] = function(msg)
    msg = msg or ""
    msg = msg:lower()

    if msg == "" or msg == "show" then
        GB:ToggleBridgeFrame()
    elseif msg == "status" then
        GB:EnsureSavedVariables()
        print("GuildBridge: Online WoW friends (" .. #GB.onlineFriends .. "):")
        for _, friend in ipairs(GB.onlineFriends) do
            print("  |cff00ff00" .. friend.characterName .. "-" .. (friend.realmName or "") .. "|r")
        end
        if #GB.onlineFriends == 0 then
            print("  No friends online.")
        end
    elseif msg == "reload" or msg == "refresh" then
        GB:EnsureSavedVariables()
        GB:UpdateOnlineFriends()
        print("GuildBridge: Friend list refreshed. " .. #GB.onlineFriends .. " online.")
    else
        print("GuildBridge commands:")
        print("  /gb - Toggle bridge window")
        print("  /gbridge status - Show online friends")
        print("  /gbridge reload - Refresh friend list")
    end
end
