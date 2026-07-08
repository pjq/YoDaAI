# Slash Commands

YoDaAI supports slash commands for quick actions in the chat interface.

## Available Commands

| Command | Description | Action |
|---------|-------------|--------|
| `/help` | Show available commands | Displays an alert with all commands and their descriptions |
| `/clear` | Clear current conversation | Deletes all messages in the active chat thread |
| `/new` | Create a new chat | Creates a fresh chat thread (Cmd+N) |
| `/models` | Show model selector | Opens the model picker to switch LLM providers |
| `/settings` | Open settings | Opens the settings window (Cmd+,) |
| `/copy` | Copy conversation | Copies the entire conversation to clipboard |

`/clear` is also bound to **Cmd+L**.

## Skills (pi agent)

When the chat uses the **pi agent** (any project chat, or a loose chat with the pi
agent enabled), the command menu also shows a **Skills** section listing the
[Agent Skills](https://agentskills.io) pi discovered for that chat's working
directory (global skills plus the project's own `.claude/skills`, `.pi/skills`,
etc.).

- Type `/` and pick a skill from the **Skills** section, or type `/skill:name`
  directly.
- Selecting a skill inserts `/skill:name ` into the composer; add arguments if
  needed and press Return. pi expands the skill invocation when the prompt is sent.

## Usage

1. **Type `/` in the chat input** - The command autocomplete popover appears
   (anchored above the composer's left edge)
2. **Continue typing** to filter commands and skills (e.g., `/he` shows only
   `/help`; `/android` narrows to matching skills)
3. **Click a command/skill** or press Enter to execute/insert it
4. **Press Escape** to dismiss the autocomplete

## Examples

```
/help          → Shows all available commands
/new           → Creates a new chat
/clear         → Clears all messages in current chat
/copy          → Copies conversation to clipboard
/models        → Opens model picker
/settings      → Opens settings window
```

## Features

- **Smart Autocomplete**: Shows matching commands as you type
- **Keyboard Navigation**: Tab through commands, Enter to select
- **Visual Feedback**: Icons and descriptions for each command
- **Non-intrusive**: Only shows when typing `/`

## Technical Architecture

### Components

1. **SlashCommand.swift**
   - `SlashCommand` enum: Defines all available commands
   - `SlashCommandParser`: Parses input and filters commands

2. **ChatViewModel**
   - Command execution logic
   - Handler closures for UI actions
   - Autocomplete state management

3. **ContentView**
   - `SlashCommandPickerPopover`: Autocomplete UI
   - Command handler wiring
   - Integration with chat composer

### Adding New Commands

To add a new slash command:

1. **Add case to `SlashCommand` enum** in `SlashCommand.swift`:
   ```swift
   case myCommand = "mycommand"
   ```

2. **Add description and icon**:
   ```swift
   var description: String {
       case .myCommand:
           return "My command description"
   }

   var icon: String {
       case .myCommand:
           return "star.fill"  // SF Symbol name
   }
   ```

3. **Add handler to `ChatViewModel.executeSlashCommand`**:
   ```swift
   case .myCommand:
       handleMyCommand()
   ```

4. **Implement the handler**:
   ```swift
   var onMyCommand: (() -> Void)?

   private func handleMyCommand() {
       onMyCommand?()
   }
   ```

5. **Wire up in `ChatDetailView.setupCommandHandlers`**:
   ```swift
   viewModel.onMyCommand = {
       // Perform UI action here
   }
   ```

## Design Patterns

- **Command Pattern**: Encapsulates actions as objects
- **Parser Pattern**: Separates input parsing from execution
- **Closure Pattern**: UI layer passes actions to ViewModel
- **Observer Pattern**: SwiftUI's `@Published` for reactive updates

## Future Enhancements

- [ ] Keyboard shortcuts (e.g., Ctrl+/ to show all commands)
- [ ] Command history (up arrow to recall previous command)
- [ ] Command arguments (e.g., `/new "Project Chat"`)
- [ ] Custom user-defined commands
- [ ] Command aliases (e.g., `/n` for `/new`)
- [ ] Rich command results (inline cards instead of alerts)
