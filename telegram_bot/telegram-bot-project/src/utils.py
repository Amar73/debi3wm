def format_message(text):
    return f"**{text}**"

def handle_command(command):
    commands = {
        '/start': 'Welcome to the bot! Use /help to see available commands.',
        '/help': 'Available commands: /start, /help'
    }
    return commands.get(command, 'Unknown command. Use /help to see available commands.')