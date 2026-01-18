# External Integrations

**Analysis Date:** 2026-01-17

## APIs & External Services

**Battle.net Social API:**
- Purpose: Cross-realm, cross-guild communication backbone
- Implementation: `BNSendGameData()` for addon messages between BNet friends
- Location: `Core.lua` (QueueBNetMessage), `Handshake.lua`, `Messages.lua`
- Auth: Automatic via logged-in Battle.net account
- Rate Limiting: 1.0 second throttle (`SEND_THROTTLE_DELAY`) between queued messages

**WoW Addon Communication:**
- Purpose: In-game addon message protocol
- Implementation: `C_ChatInfo.SendAddonMessage()` for WHISPER and GUILD channels
- Location: `Core.lua` (ProcessQueue, ProcessGuildRelayQueue)
- Prefix: `MNet` (registered via `C_ChatInfo.RegisterAddonMessagePrefix`)
- Channels Used:
  - `WHISPER` - Same-account alt communication
  - `GUILD` - Guild-wide relay for non-BNet-connected members

**WoW Guild API:**
- Purpose: Guild membership and roster data
- Implementation: `GetGuildRosterInfo()`, `C_Club.GetGuildClubId()`, `C_GuildInfo.GuildRoster()`
- Location: `RosterSync.lua` (GetOnlineGuildMembers), `Utils.lua`
- Data Retrieved: Member names, classes, online status, realms

**WoW Social API:**
- Purpose: BNet friend enumeration and presence
- Implementation: `C_BattleNet.GetFriendAccountInfo()`, `C_BattleNet.GetFriendGameAccountInfo()`
- Location: `Utils.lua` (FindOnlineWoWFriends)
- Rate Limiting: 5 second global throttle (`BNET_API_THROTTLE`)

## Data Storage

**Databases:**
- SavedVariables (`MNetDB`) - WoW client-managed persistent storage
  - Location: `WTF/Account/{account}/SavedVariables/MNet.lua`
  - Format: Lua table serialization (automatic)
  - No external database

**File Storage:**
- Local filesystem only (WoW WTF folder)
- Automatically managed by WoW client

**Caching:**
- In-memory only
- `GB.connectedBridgeUsers` - BNet connection cache (300s TTL)
- `GB.connectedWhisperAlts` - Whisper alt cache (90s TTL)
- `GB.guildRosters` - Remote guild roster cache (600s TTL)
- `GB.recentMessages` - Message deduplication cache (10s window)

## Authentication & Identity

**Auth Provider:**
- Battle.net (automatic via WoW client login)

**Implementation:**
- No manual auth required
- Guild membership validated via `C_Club.GetGuildClubId()`
- Whitelist validation: `allowedGuildIds` table in `Core.lua`
  - `490681231` - MDGA 1 (Tichondrius)
  - `494845151` - MDGA 2 (Thrall)
  - `496284011` - MDGA 3 (Illidan)

**Access Control:**
- `IsAllowedGuildId()` - Validates guild club ID against whitelist
- `IsAllowedGuildIdAndRealm()` - Validates guild ID + realm combination
- Only whitelisted guilds can participate in the network

## Monitoring & Observability

**Error Tracking:**
- None (relies on WoW's built-in Lua error handler)
- `pcall()` wrapping for critical BNet API calls

**Logs:**
- Debug logging via `/mn traffic`, `/mn events` commands
- Persistent DC logging via `/mndclog` commands
- Output to WoW chat frame with color-coded prefixes
- DC log stored in `MNetDB.dcLog` (survives disconnects)

**Traffic Statistics:**
- `GB.trafficStats` - In-memory counters for:
  - `bnet` - BNet messages sent
  - `whisper` - Whisper addon messages sent
  - `guild` - Guild relay messages sent
  - `handshakes`, `rosterFull`, `rosterDelta`, `rosterRequest`, `party`, `chat`

## CI/CD & Deployment

**Hosting:**
- Local installation in WoW addons folder
- No external hosting/distribution

**CI Pipeline:**
- None
- Manual deployment via file copy

**Distribution:**
- Manual copy to `Interface/AddOns/MNet/`
- Git repository for version control

## Environment Configuration

**Required env vars:**
- None (embedded in WoW client)

**Secrets location:**
- No secrets required
- All auth handled by Battle.net client

**Configuration Constants (Core.lua):**
```lua
BRIDGE_PAYLOAD_PREFIX = "[GB]"
BRIDGE_ADDON_PREFIX = "MNet"
MESSAGE_DEDUPE_WINDOW = 10
HANDSHAKE_THROTTLE = 10
SEND_THROTTLE_DELAY = 1.0
ZONE_TRANSITION_COOLDOWN = 8
ROSTER_SYNC_THROTTLE = 30
ROSTER_CHUNK_SIZE = 200
GUILD_RELAY_THROTTLE = 4.0
```

## Webhooks & Callbacks

**Incoming:**
- WoW Events (registered in `Events.lua`):
  - `ADDON_LOADED` - Initialization trigger
  - `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD` - Session events
  - `CHAT_MSG_GUILD` - Guild chat interception
  - `BN_CHAT_MSG_ADDON` - BNet addon message reception
  - `CHAT_MSG_ADDON` - In-game addon message reception
  - `BN_FRIEND_INFO_CHANGED` - Friend list updates
  - `GUILD_ROSTER_UPDATE` - Guild membership changes
  - `GROUP_ROSTER_UPDATE` - Party/raid changes
  - `ZONE_CHANGED_NEW_AREA` - Zone transition protection

**Outgoing:**
- None (no external webhook calls)

## Protocol Details

**Message Types (prefixes):**
- `[GB]` - Chat message payload
- `[GBHS]` - BNet handshake (HELLO, PONG, LEAVE)
- `[GBWHS]` - Whisper handshake
- `[GBRF]` - Roster full sync
- `[GBRD]` - Roster delta update
- `[GBRR]` - Roster request
- `[GBRA]` - Relay availability announcement
- `[GBGR]` - Guild relay chat
- `[GBGD]` - Guild relay data
- `[GBGM]` - Guild metadata
- `[GBGX]` - Guild disconnect notification

**Payload Format (chat messages):**
```
[GB]guildName|guildRealm|faction|originName|originRealm|sourceType|targetFilter|messageId|guildHomeRealm|classFile|guildClubId|messageText
```

---

*Integration audit: 2026-01-17*
