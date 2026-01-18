# Technology Stack

**Analysis Date:** 2026-01-17

## Languages

**Primary:**
- Lua 5.1 - All addon code (World of Warcraft embedded interpreter)

**Secondary:**
- None

## Runtime

**Environment:**
- World of Warcraft Retail Client (Interface version 110002 - The War Within)
- Embedded Lua 5.1 interpreter with WoW-specific extensions

**Package Manager:**
- Not applicable - WoW addons are standalone directories
- No external dependency management

## Frameworks

**Core:**
- World of Warcraft Addon API - Primary framework for all functionality
- WoW Widget/Frame system - UI construction and event handling

**Testing:**
- None - WoW addons lack formal testing frameworks
- Manual in-game testing required

**Build/Dev:**
- None - No build step required
- Direct Lua files loaded by WoW client

## Key Dependencies

**Critical (WoW Global APIs):**
- `C_BattleNet` - Battle.net friend information and messaging
- `C_Club` - Guild (Community) club ID retrieval
- `C_ChatInfo` - Addon message prefix registration and sending
- `C_Timer` - Timer scheduling (NewTicker, After)
- `C_PartyInfo` - Party/raid invitation
- `C_GuildInfo` - Guild roster operations

**UI APIs:**
- `CreateFrame` - All UI element creation
- `GameFontNormal`, `GameFontHighlight*` - Font objects
- `BackdropTemplate` - Frame backdrop styling
- `UIPanelButtonTemplate`, `UIPanelScrollFrameTemplate` - Standard UI templates

**Communication APIs:**
- `BNSendGameData` - Battle.net addon message transmission
- `BNGetNumFriends` - Friend list enumeration
- `GetGuildRosterInfo` - Guild member data

## Configuration

**Environment:**
- No environment variables (embedded in WoW client)
- No external configuration files

**Saved Variables:**
- `MNetDB` - Persisted configuration stored in WTF folder
  - `bridgeEnabled` - Enable/disable bridge functionality
  - `muteSend` - Mute outgoing messages
  - `filterNativeChat` - Filter native guild chat
  - `enableGuildRelay` - Enable guild channel relay
  - `relayRosterToGuild` - Relay roster data via guild channel
  - `knownGuilds` - Discovered guild information cache
  - `registeredAlts` - Same-account alt character names
  - `windowPos` - UI position/size persistence
  - `enableEventDebug` - Event debugging toggle
  - `enableTrafficDebug` - Traffic debugging toggle
  - `dcLog` - Disconnect debugging log

**Build:**
- No build configuration
- `MNet.toc` - Table of Contents file defines load order and metadata

## Platform Requirements

**Development:**
- World of Warcraft Retail client
- Text editor for Lua files
- `/reload` command for testing changes

**Production:**
- World of Warcraft Retail client (Interface 110002+)
- Addon installed in `Interface/AddOns/MNet/`
- Battle.net friends using the same addon for cross-guild communication

## File Load Order

Defined in `MNet.toc`:
1. `Core.lua` - Global state, constants, utility queue functions
2. `Utils.lua` - Helper functions (deduplication, friend lookup)
3. `Handshake.lua` - Connection establishment protocol
4. `Messages.lua` - Message formatting and routing
5. `RosterSync.lua` - Guild roster synchronization
6. `UI.lua` - User interface construction
7. `Events.lua` - WoW event registration and handling
8. `Commands.lua` - Slash command definitions

## WoW API Version Compatibility

**Interface Version:** 110002 (The War Within)

**Key API Dependencies:**
- `C_Club.GetGuildClubId()` - Requires Retail (not Classic)
- `C_BattleNet.GetFriendAccountInfo()` - Modern BNet API
- `C_BattleNet.GetFriendGameAccountInfo()` - Modern BNet API
- `MenuUtil.CreateContextMenu()` - Modern menu API (with fallback)

---

*Stack analysis: 2026-01-17*
