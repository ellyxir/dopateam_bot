# DopaTeam Discord Bot

A Discord bot built with Elixir and Nostrum for the DopaTeam Discord server, providing moderation, role management, and community engagement features.

## Features

### Core Functionality

- **Automated Role Management**
  - Manages intro/no-intro role transitions based on introduction messages
  - Supports age-based roles (13-15, 16-17, 18+, 30+)
  - Closed DM role management

- **DM Request Moderation**
  - Monitors DM requests in designated channels
  - Prevents inappropriate DM requests to minors
  - Automatically deletes and logs violations
  - Exempts moderators and helpers from restrictions

- **Introduction System**
  - Monitors introduction channels for new member intros
  - Automatically upgrades users from "No Intro" to "Intro" role
  - Validates intro messages (must contain at least a space)

- **Water Reminder System** 💧
  - `/water` command for hydration reminders
  - Customizable reminder messages
  - 3-hour cooldown between pings
  - Role-based mentions for water reminders

- **Intro Report** (staff only)
  - `/intro-report` lists members who haven't done an intro
  - Pages of 25 members, oldest join first, with previous and next buttons
  - Only reads: sends no messages to members and changes no roles

- **Voice Channel Status Logging**
  - Tracks and logs voice channel status updates
  - Audit log integration for tracking changes

## Prerequisites

- Elixir 1.14 or higher
- Mix build tool
- Discord Bot Token

With Nix, `nix develop` gives a shell with Elixir 1.20 on OTP 29.

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/dopateam_bot.git
cd dopateam_bot
```

2. Install dependencies:
```bash
mix deps.get
```

3. Configure the bot token via env variable:
```bash
export DOPATEAM_TOKEN="your_discord_bot_token_here"
```

4. Compile the project:
```bash
mix compile
```

## Configuration

### Environment Variables

- `DOPATEAM_TOKEN` - Your Discord bot token (required)

### Server Configuration

The bot is configured with specific guild and channel IDs. To adapt for your server, modify the following in `lib/dopa_team/consumer.ex`:

- `@live_guild_id` - Your main Discord server ID
- `@bot_test_guild_id` - Your test server ID (optional)
- Channel IDs for:
  - DM request monitoring
  - Introduction monitoring
  - Logging channels
  - Voice status logging

### Role Names

The bot expects these exact role names in your server:
- `18+` - Adult role (18 and over)
- `30+` - Adult role (30 and over)
- `13-15` - Minor role (13-15 years)
- `16-17` - Minor role (16-17 years)
- `Closed DM` - Users who don't accept DMs
- `No Intro` - New members without introduction
- `Intro` - Members who have introduced themselves
- `Rules` - Members who have accepted rules
- `MOD` - Moderator role
- `Helpers` - Helper/assistant moderator role

## Running the Bot

### Development Mode
```bash
mix run --no-halt
```

### Production Mode
```bash
MIX_ENV=prod mix run --no-halt
```

### Using IEx (Interactive Shell)
```bash
iex -S mix
```

## Commands

### Slash Commands

- `/water [message]` - Send a water reminder ping
  - Optional: Include a custom message
  - 3-hour cooldown between uses
  - Mentions all users with the water reminder role

- `/intro-report [group]` - Staff only (Admins, MOD, Helpers)
  - Replies privately with the member counts and a page of members
  - `group` picks the list: members with the "No Intro" role (default),
    or members with neither "Intro" nor "No Intro" (bots left out)
  - The report is kept for an hour, so paging doesn't fetch the members
    again; after that, a click builds it again

## Project Structure

```
dopateam_bot/
├── config/
│   ├── config.exs        # Compile-time configuration
│   └── runtime.exs       # Runtime configuration
├── lib/
│   ├── dopa_team.ex      # Main module
│   └── dopa_team/
│       ├── application.ex # OTP Application
│       ├── consumer.ex    # Discord event consumer
│       ├── discord.ex     # Behaviour for the Discord API calls we make
│       ├── discord/
│       │   └── nostrum.ex # Production implementation over nostrum
│       ├── intro_report_command.ex # /intro-report and its page buttons
│       ├── intro_report_page.ex    # Renders a report page as an embed
│       ├── member_report.ex        # Finds members without an intro
│       ├── report_store.ex         # Keeps built reports for an hour
│       └── water_ping.ex  # Water reminder state management
├── test/                  # Test files
├── mix.exs               # Project configuration
└── mix.lock              # Dependency lock file
```

## Key Modules

- **DopaTeam.Consumer** - Main event handler for Discord events
- **DopaTeam.WaterPing** - GenServer managing water reminder cooldowns
- **DopaTeam.MemberReport** - Pages through a server's members and groups
  those without an intro
- **DopaTeam.ReportStore** - GenServer owning an ETS table of built reports
- **DopaTeam.IntroReportCommand** - Handles `/intro-report` and its buttons
- **DopaTeam.Application** - OTP application supervisor

## Logging

The bot uses Elixir's built-in Logger with configurable levels:
- `:debug` - Verbose logging
- `:info` - Informational messages
- `:warning` - Warning messages (default)
- `:error` - Error messages only

Configure in `config/runtime.exs`.

## Dependencies

- [Nostrum](https://github.com/Kraigie/nostrum) - Elixir Discord library
- [Dialyxir](https://github.com/jeremyjh/dialyxir) - Static analysis tool (dev only)

## Development

### Running Tests
```bash
mix test
```

### Static Analysis
```bash
mix dialyzer
```

### Code Formatting
```bash
mix format
```

## Deployment Considerations

1. **Environment Variables**: Ensure `DOPATEAM_TOKEN` is securely set
2. **Server IDs**: Update guild and channel IDs for your server
3. **Role Names**: Create matching roles in your Discord server
4. **Permissions**: Bot requires permissions for:
   - Read/Send Messages
   - Manage Roles
   - Delete Messages
   - View Audit Log
   - Use Slash Commands

## Security Features

- Automatic detection and prevention of inappropriate DM requests to minors
- Audit logging for accountability
- Role-based access control for sensitive features
- Moderator/Helper exemptions for DM restrictions

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues or questions, please create an issue on GitHub.

