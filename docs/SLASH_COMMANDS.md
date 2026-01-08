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

## Usage

1. **Type `/` in the chat input** - The command autocomplete popover will appear
2. **Continue typing** to filter commands (e.g., `/he` shows only `/help`)
3. **Click a command** or press Enter to execute it
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
