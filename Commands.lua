-- GuildBridge Commands Module
-- Slash command handlers

local addonName, GB = ...

SLASH_GUILDBRIDGE1 = "/gbridge"
SLASH_GUILDBRIDGE2 = "/gb"
SlashCmdList["GUILDBRIDGE"] = function(msg)
    GB:ToggleBridgeFrame()
end
