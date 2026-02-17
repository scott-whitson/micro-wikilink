# Wikilink Plugin

Obsidian-style vault toolkit for micro. Navigate [[wikilinks]], search
your vault, view backlinks, link images, and find orphaned notes.

## Commands

- wikilink.follow:    Follow the [[link]] under the cursor (Alt-g)
- wikilink.back:      Go back to the previous file (Alt-b)
- wikilink.open:      Fuzzy-find and open a note from the vault (Alt-o)
- wikilink.search:    Full-text search across the vault (Alt-s)
- wikilink.path:      Copy current file path to clipboard (Alt-p)
- wikilink.random:    Open a random note from the vault (Alt-r)
- wikilink.image:     Link an image — copies to media/ and inserts markdown (Alt-i)
- wikilink.backlinks: Show all notes linking to this note (Alt-l)
- wikilink.unlinked:  Show notes with no incoming links (Alt-u)

## Auto-Reload

Files are automatically reloaded when modified externally (e.g., by
Claude Code, vim, or any other tool editing the same file). The cursor
stays on the same line. If you have unsaved changes, a warning is shown
instead of reloading.

## Settings

- wikilink.vault: Absolute path to your vault directory.
  Defaults to the current working directory if not set.

  Set it with: > set wikilink.vault /path/to/vault

## Requirements

- fzf (for wikilink.open and wikilink.search)
- grep (for wikilink.search, wikilink.backlinks, wikilink.unlinked)
- shuf (for wikilink.random — part of GNU coreutils)
- stat (for auto-reload — part of GNU coreutils)
