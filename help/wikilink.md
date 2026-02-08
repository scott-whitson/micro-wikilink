# Wikilink Plugin

Navigate between markdown files using Obsidian-style [[wikilinks]].

## Usage

Type [[note name]] in any markdown file. Place your cursor inside the
brackets and press Alt-g to follow the link. The plugin will search your
vault directory for a file named "note name.md" and open it. If the file
does not exist, it will be created at the vault root.

Press Alt-b to go back to the previous file (with cursor position restored).

Press Alt-o to open any note from the vault using fzf fuzzy finder.

## Commands

- wikilink.follow: Follow the [[link]] under the cursor (Alt-g)
- wikilink.back: Go back to the previous file (Alt-b)
- wikilink.open: Fuzzy-find and open a note from the vault (Alt-o)

## Settings

- wikilink.vault: Absolute path to your vault directory.
  Defaults to the current working directory if not set.

  Set it with: > set wikilink.vault /path/to/vault

## Requirements

- fzf (for the wikilink.open command only)
