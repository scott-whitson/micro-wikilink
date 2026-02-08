# micro-wikilink

Obsidian-style `[[wikilinks]]` for the [micro](https://micro-editor.github.io/) terminal text editor.

Navigate between markdown files in a vault directory using `[[link]]` syntax, just like Obsidian — but from your terminal.

## Features

- **Follow links** — Place your cursor on a `[[link]]` and press `Alt-g` to open it
- **Auto-create** — If the linked file doesn't exist, it's created automatically
- **Back navigation** — Press `Alt-b` to return to the previous file (cursor position restored)
- **Fuzzy finder** — Press `Alt-o` to search all notes in your vault with fzf
- **Syntax highlighting** — `[[wikilinks]]` are highlighted in markdown files
- **Auto-save** — Modified files are saved automatically when navigating

## Installation

### From source

```bash
git clone https://github.com/scott/micro-wikilink.git
```

Copy the plugin into micro's plugin directory:

```bash
# Windows
xcopy /E /I micro-wikilink "%USERPROFILE%\.config\micro\plug\wikilink"

# Linux/macOS
cp -r micro-wikilink ~/.config/micro/plug/wikilink
```

Or create a symlink for development:

```bash
# Windows (run as admin)
mklink /D "%USERPROFILE%\.config\micro\plug\wikilink" "C:\path\to\micro-wikilink"

# Linux/macOS
ln -s /path/to/micro-wikilink ~/.config/micro/plug/wikilink
```

### Requirements

- [micro](https://micro-editor.github.io/) >= 2.0.0
- [fzf](https://github.com/junegunn/fzf) (only needed for `Alt-o` fuzzy finder)

## Setup

Set your vault directory (the root folder containing your markdown notes):

Open micro, press `Ctrl-e`, and run:

```
set wikilink.vault /path/to/your/vault
```

This is saved permanently in `~/.config/micro/settings.json`. If not set, the current working directory is used as the vault.

## Usage

### Follow a link (`Alt-g`)

Type a wikilink in any markdown file:

```markdown
Check out [[my note]] for more details.
```

Place your cursor anywhere inside `[[my note]]` and press `Alt-g`. The plugin will:

1. Search your vault recursively for `my note.md`
2. Open it in the current buffer
3. If the file doesn't exist, create it at the vault root and open it

### Go back (`Alt-b`)

Press `Alt-b` to return to the previous file. Your cursor position is restored exactly where you left off. The history is stack-based, so you can follow several links deep and unwind back through all of them.

### Open any note (`Alt-o`)

Press `Alt-o` to launch fzf with all `.md` files in your vault. Select a note to open it. Press `Escape` to cancel.

### Help

Inside micro, press `Ctrl-e` and run:

```
help wikilink
```

## Keybindings

| Key     | Command            | Action                                |
|---------|--------------------|---------------------------------------|
| `Alt-g` | `wikilink.follow`  | Follow the `[[link]]` under cursor    |
| `Alt-b` | `wikilink.back`    | Go back to previous file              |
| `Alt-o` | `wikilink.open`    | Fuzzy-find a note in the vault        |

Keybindings won't overwrite your existing bindings. To customize them, add entries to `~/.config/micro/bindings.json`:

```json
{
    "Alt-g": "command:wikilink.follow",
    "Alt-b": "command:wikilink.back",
    "Alt-o": "command:wikilink.open"
}
```

## Settings

| Setting          | Default | Description                          |
|------------------|---------|--------------------------------------|
| `wikilink.vault` | `""`    | Path to your vault directory. Falls back to cwd if empty. |

## How it works

- Notes are plain `.md` files — no proprietary format, fully compatible with Obsidian
- Each file in the vault must have a unique filename (just like Obsidian)
- `[[link name]]` resolves to `link name.md` anywhere in the vault directory tree
- Navigation history is kept in memory as a stack of `{file, line, col}` entries
- On Windows, file search uses `where /r`; on Unix, `find`

## Platform support

- **Windows** — Fully tested
- **Linux** — Should work (uses `find` and `sh` for file operations)
- **macOS** — Should work (same as Linux)

## License

MIT
