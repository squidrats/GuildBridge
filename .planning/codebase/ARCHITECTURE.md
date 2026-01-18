# Architecture

**Analysis Date:** 2026-01-17

## Pattern Overview

**Overall:** Event-Driven Message Relay System

**Key Characteristics:**
- Single global addon object (`GB`/`MNet`) shared across all Lua files via vararg initialization
- Event-driven architecture using WoW's frame event system
- Multi-channel communication (Battle.net, Whisper, Guild relay)
- Message queuing with throttling to prevent disconnects
- Persistent state via `SavedVariables` (MNetDB)

## Layers

**Core/State Layer:**
- Purpose: Global state management, configuration, message queuing infrastructure
- Location: `Core.lua`
- Contains: Global constants, throttle settings, state tables (connectedBridgeUsers, guildRosters, etc.), queue processors
- Depends on: WoW API (C_Timer, GetTime, BNSendGameData)
- Used by: All other layers

**Event Layer:**
- Purpose: WoW event handling and routing to appropriate handlers
- Location: `Events.lua`
- Contains: Event registration, event dispatch via OnEvent script, periodic timers for keepalives/cleanup
- Depends on: Core layer, Messages layer, Handshake layer
- Used by: Entry point for all game events

**Communication Layer:**
- Purpose: Handle all cross-guild message transmission and reception
- Location: `Messages.lua`, `Handshake.lua`, `RosterSync.lua`
- Contains: Payload builders, message parsers, protocol handlers, relay logic
- Depends on: Core layer, Utils layer
- Used by: Event layer triggers handlers here

**Presentation Layer:**
- Purpose: User interface rendering and interaction
- Location: `UI.lua`
- Contains: Frame creation, tab management, roster display, input handling
- Depends on: Core layer, Utils layer
- Used by: Commands layer, Event layer (for refresh triggers)

**Commands Layer:**
- Purpose: Slash command parsing and execution
- Location: `Commands.lua`
- Contains: /mn command handler with subcommands (alt, debug, relay, etc.)
- Depends on: Core layer, UI layer
- Used by: User input only

**Utilities Layer:**
- Purpose: Shared helper functions
- Location: `Utils.lua`
- Contains: Deduplication, friend list scanning, class color lookup, chat frame integration
- Depends on: Core layer (for state access)
- Used by: All layers

## Data Flow

**Outgoing Guild Chat Message:**

1. User sends guild chat in WoW
2. `CHAT_MSG_GUILD` event fires, handled in `Events.lua`
3. `HandleGuildChatMessage()` in `Messages.lua` validates allowed guild
4. Message is hashed for deduplication via `Utils.lua`
5. `SendBridgePayload()` builds payload, calls `QueueBNetMessage()` for each connected friend
6. `SendWhisperBridgePayload()` queues to whisper-connected alts
7. `ProcessQueue()` in `Core.lua` throttles and sends via BNSendGameData/C_ChatInfo
8. Guild relay: `RelayToGuildmates()` queues for local guildmates without connections

**Incoming Message from Bridge:**

1. `BN_CHAT_MSG_ADDON` event fires with prefix "MNet"
2. `HandleBNAddonMessage()` in `Messages.lua` parses message type
3. If chat message: parse payload, check deduplication, call `AddBridgeMessage()`
4. `AddBridgeMessage()` formats display, adds to history, updates scrollframe
5. Message optionally relayed to other guilds via `RelayToOtherGuilds()`
6. If relay enabled: `RelayToGuildmates()` sends via GUILD addon channel

**State Management:**
- All state lives on global `GB` object
- `MNetDB` (SavedVariable) persists settings across sessions
- Connection state (connectedBridgeUsers, connectedWhisperAlts) is ephemeral
- Rosters sync via delta updates, full syncs on request

## Key Abstractions

**Message Payload Format:**
- Purpose: Serialized cross-guild message
- Examples: `Messages.lua` lines 171-210 (buildBridgePayload)
- Pattern: Pipe-delimited fields: `[GB]guild|realm|faction|sender|senderRealm|source|target|msgId|homeRealm|class|clubId|text`

**Handshake Protocol:**
- Purpose: Connection establishment and presence tracking
- Examples: `Handshake.lua` `[GBHS]` and `[GBWHS]` prefixes
- Pattern: HELLO/PONG exchange establishes bidirectional connection

**Roster Sync Protocol:**
- Purpose: Share online guild members across bridges
- Examples: `RosterSync.lua` `[GBRF]` (full), `[GBRD]` (delta), `[GBRR]` (request)
- Pattern: Chunked full rosters, incremental deltas with version tracking

**Relay Election:**
- Purpose: Prevent duplicate guild relay messages
- Examples: `Core.lua` `AmIPrimaryRelayForGuild()`, `TrackRelayCandidate()`
- Pattern: Alphabetically sorted candidates, first name wins primary

## Entry Points

**Addon Load:**
- Location: `Events.lua` lines 19-80 (ADDON_LOADED handler)
- Triggers: Game loading addon
- Responsibilities: Initialize SavedVariables, register prefix, create UI, start timers

**Player Login:**
- Location: `Events.lua` lines 89-178 (PLAYER_ENTERING_WORLD handler)
- Triggers: Login, reload, zone change
- Responsibilities: Guild roster refresh, handshake cascade, relay setup

**Slash Commands:**
- Location: `Commands.lua` lines 3-275
- Triggers: User typing /mn or /mdganet
- Responsibilities: Toggle UI, manage alts, debug output, toggle features

**UI Toggle:**
- Location: `UI.lua` `ToggleBridgeFrame()` function
- Triggers: /mn command or minimap button
- Responsibilities: Show/hide main window

## Error Handling

**Strategy:** Defensive programming with pcall wrapping critical WoW API calls

**Patterns:**
- Zone transition protection: Skip operations during `IsInZoneTransition()` to prevent disconnects
- BNet API throttling: `BNET_API_THROTTLE` (5s) prevents excessive friend list queries
- Queue pausing: Message queues pause during zone transitions
- Stale connection cleanup: 300s timeout on bridge connections
- pcall wrapping: `BNGetNumFriends`, `C_BattleNet.GetFriendGameAccountInfo` wrapped

## Cross-Cutting Concerns

**Logging:**
- DC logging via `LogDC()` to MNetDB.dcLog (persistent across crashes)
- Traffic debugging via `enableTrafficDebug` flag
- Event debugging via `enableEventDebug` flag

**Validation:**
- Guild whitelist: `IsAllowedGuildId()` checks hardcoded club IDs
- Realm validation: `IsAllowedGuildIdAndRealm()` verifies guild-realm match
- Message deduplication: Hash-based with 10s window

**Throttling:**
- Send throttle: 1.0s between queued messages
- Handshake throttle: 10s minimum between handshakes
- Guild relay throttle: 4.0s between guild channel messages
- Roster broadcast throttle: 30s minimum
- Zone transition cooldown: 8s after entering world

---

*Architecture analysis: 2026-01-17*
