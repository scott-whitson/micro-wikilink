VERSION = "0.2.0"

local micro   = import("micro")
local config  = import("micro/config")
local shell   = import("micro/shell")
local buffer  = import("micro/buffer")
local os      = import("os")
local filepath = import("filepath")
local strings = import("strings")
local runtime = import("runtime")
local clip    = import("micro/clipboard")

-- Navigation history stack: each entry is {path, line, col}
local history = {}

-- ---------------------------------------------------------------------------
-- preinit: register plugin options before anything else
-- ---------------------------------------------------------------------------
function preinit()
    config.RegisterCommonOption("wikilink", "vault", "")
end

-- ---------------------------------------------------------------------------
-- getVaultRoot: return the configured vault path, or cwd as fallback
-- ---------------------------------------------------------------------------
local function getVaultRoot()
    local vault = config.GetGlobalOption("wikilink.vault")
    if vault == nil or vault == "" then
        local cwd, err = os.Getwd()
        if err ~= nil then
            return ""
        end
        return cwd
    end
    return vault
end

-- ---------------------------------------------------------------------------
-- findFileInVault: recursively search the vault for a file by basename
-- Returns the full path of the first match, or "" if not found.
-- ---------------------------------------------------------------------------
local function findFileInVault(name)
    local root = getVaultRoot()
    if root == "" then
        return ""
    end

    local out, err

    if runtime.GOOS == "windows" then
        -- Use where.exe (a real executable, not a shell builtin)
        -- Each arg passed separately avoids quoting issues with spaces in paths
        out, err = shell.ExecCommand("where", "/r", root, name)
    else
        local cmd = 'find "' .. root .. '" -name "' .. name .. '" -type f 2>/dev/null'
        out, err = shell.ExecCommand("sh", "-c", cmd)
    end

    if out == nil or out == "" then
        return ""
    end

    -- Trim whitespace and take the first line
    out = strings.TrimSpace(out)
    if out == "" then
        return ""
    end

    -- If multiple results, take the first line
    local idx = strings.Index(out, "\n")
    if idx >= 0 then
        out = string.sub(out, 1, idx)
        out = strings.TrimSpace(out)
    end

    return out
end

-- ---------------------------------------------------------------------------
-- getLinkUnderCursor: extract [[wikilink]] text at cursor position
-- Returns the link text (trimmed), or "" if the cursor is not on a link.
-- ---------------------------------------------------------------------------
local function getLinkUnderCursor(bp)
    local cursor = bp.Buf:GetActiveCursor()
    local lineText = bp.Buf:Line(cursor.Y)
    local x = cursor.X

    -- Line length via Go strings package
    local lineLen = strings.Count(lineText, "") - 1
    if lineLen <= 0 then
        return ""
    end

    -- Clamp x to valid range (Lua string.sub is 1-based, cursor.X is 0-based)
    if x < 0 then x = 0 end
    if x >= lineLen then x = lineLen - 1 end

    -- Scan left from cursor position to find "[["
    local openPos = -1
    local i = x + 1  -- convert to 1-based for Lua string.sub
    while i >= 2 do
        local two = string.sub(lineText, i - 1, i)
        if two == "[[" then
            openPos = i  -- 1-based position of the second '['
            break
        end
        -- If we hit "]]" before finding "[[", we are outside a link
        if two == "]]" then
            return ""
        end
        i = i - 1
    end

    if openPos < 0 then
        return ""
    end

    -- Scan right from cursor position to find "]]"
    local closePos = -1
    local j = x + 1  -- 1-based
    while j < lineLen do
        local two = string.sub(lineText, j, j + 1)
        if two == "]]" then
            closePos = j  -- 1-based position of the first ']'
            break
        end
        -- If we hit "[[" going right (another link opening), stop
        if two == "[[" then
            return ""
        end
        j = j + 1
    end

    if closePos < 0 then
        return ""
    end

    -- Extract text between [[ and ]]
    local linkText = string.sub(lineText, openPos + 1, closePos - 1)
    linkText = strings.TrimSpace(linkText)

    return linkText
end

-- ---------------------------------------------------------------------------
-- saveIfModified: save the current buffer if it has unsaved changes
-- ---------------------------------------------------------------------------
local function saveIfModified(bp)
    if bp.Buf:Modified() then
        bp:Save()
    end
end

-- ---------------------------------------------------------------------------
-- pushHistory: save current position onto the history stack
-- ---------------------------------------------------------------------------
local function pushHistory(bp)
    local cursor = bp.Buf:GetActiveCursor()
    local entry = {
        path = bp.Buf.Path,
        line = cursor.Y,
        col  = cursor.X,
    }
    history[#history + 1] = entry
end

-- ---------------------------------------------------------------------------
-- followLink: navigate to the wikilink under the cursor
-- ---------------------------------------------------------------------------
function followLink(bp)
    local link = getLinkUnderCursor(bp)
    if link == "" then
        micro.InfoBar():Message("No wikilink under cursor")
        return
    end

    local filename = link .. ".md"

    local fullPath = findFileInVault(filename)

    if fullPath == "" then
        -- Create the file at the vault root
        local root = getVaultRoot()
        fullPath = filepath.Join(root, filename)
        local f, err = os.Create(fullPath)
        if err ~= nil then
            micro.InfoBar():Message("Error creating file: " .. tostring(err))
            return
        end
        f:Close()
    end

    -- Save and record position before navigating
    saveIfModified(bp)
    pushHistory(bp)

    local buf, err = buffer.NewBufferFromFile(fullPath)
    if err ~= nil then
        micro.InfoBar():Message("Error opening file: " .. tostring(err))
        return
    end

    bp:OpenBuffer(buf)
    micro.InfoBar():Message("Followed link to: " .. link)
end

-- ---------------------------------------------------------------------------
-- goBack: return to the previous position in the history stack
-- ---------------------------------------------------------------------------
function goBack(bp)
    if #history == 0 then
        micro.InfoBar():Message("No history to go back to")
        return
    end

    local entry = history[#history]
    history[#history] = nil

    saveIfModified(bp)

    local buf, err = buffer.NewBufferFromFile(entry.path)
    if err ~= nil then
        micro.InfoBar():Message("Error opening file: " .. tostring(err))
        return
    end

    bp:OpenBuffer(buf)

    -- Restore cursor position
    local cursor = bp.Buf:GetActiveCursor()
    cursor.Y = entry.line
    cursor.X = entry.col
    cursor:Relocate()
    bp:Center()

    micro.InfoBar():Message("Returned to: " .. entry.path)
end

-- ---------------------------------------------------------------------------
-- openNote: fuzzy-find and open a note from the vault using fzf
-- ---------------------------------------------------------------------------
function openNote(bp)
    local root = getVaultRoot()
    if root == "" then
        micro.InfoBar():Message("Vault directory not set")
        return
    end

    local cmd
    if runtime.GOOS == "windows" then
        cmd = 'cmd /c dir /s /b "' .. root .. '\\*.md" | fzf'
    else
        cmd = 'find "' .. root .. '" -name "*.md" -type f | fzf'
    end

    local output, err = shell.RunInteractiveShell(cmd, false, true)

    if err ~= nil then
        -- User likely pressed Escape in fzf
        return
    end

    output = strings.TrimSpace(output)
    if output == "" then return end

    -- On Windows, dir /s /b returns absolute paths; on Unix, find returns relative
    local fullPath
    if runtime.GOOS == "windows" then
        fullPath = output
    else
        fullPath = filepath.Join(root, output)
    end

    saveIfModified(bp)
    pushHistory(bp)

    local buf, bufErr = buffer.NewBufferFromFile(fullPath)
    if bufErr ~= nil then
        micro.InfoBar():Message("Error opening file: " .. tostring(bufErr))
        return
    end
    bp:OpenBuffer(buf)
end

-- ---------------------------------------------------------------------------
-- showBacklinks: show all notes that link to the current note in a VSplit
-- ---------------------------------------------------------------------------
function showBacklinks(bp)
    local root = getVaultRoot()
    if root == "" then
        micro.InfoBar():Message("Vault directory not set")
        return
    end

    -- Get current note name (basename without .md)
    local path = bp.Buf.Path
    local name = path
    local slashIdx = strings.LastIndex(path, "/")
    if slashIdx >= 0 then
        name = string.sub(path, slashIdx + 2)
    end
    -- Remove .md extension
    if strings.HasSuffix(name, ".md") then
        name = string.sub(name, 1, #name - 3)
    end

    if name == "" then
        micro.InfoBar():Message("Cannot determine current note name")
        return
    end

    -- Search for [[notename]] in all vault .md files using grep
    local pattern = '\\[\\[' .. name .. '\\]\\]'
    local cmd = 'grep -rl "' .. pattern .. '" "' .. root .. '" --include="*.md" 2>/dev/null'
    local out, err = shell.ExecCommand("sh", "-c", cmd)

    local content = "# Backlinks to [[" .. name .. "]]\n\n"

    if out == nil or strings.TrimSpace(out) == "" then
        content = content .. "(no backlinks found)\n"
    else
        out = strings.TrimSpace(out)
        -- Split by newline and format each result
        local remaining = out
        while remaining ~= "" do
            local nlIdx = strings.Index(remaining, "\n")
            local line
            if nlIdx >= 0 then
                line = string.sub(remaining, 1, nlIdx)
                remaining = string.sub(remaining, nlIdx + 2)
            else
                line = remaining
                remaining = ""
            end
            line = strings.TrimSpace(line)
            if line ~= "" then
                -- Extract just the filename for display
                local lineSlashIdx = strings.LastIndex(line, "/")
                local displayName = line
                if lineSlashIdx >= 0 then
                    displayName = string.sub(line, lineSlashIdx + 2)
                end
                content = content .. "- [[" .. string.sub(displayName, 1, #displayName - 3) .. "]]  " .. line .. "\n"
            end
        end
    end

    content = content .. "\n---\nAlt-g to follow a link | Alt-b to go back\n"

    -- Create a scratch buffer and show in a VSplit
    local backlinkBuf = buffer.NewBuffer(content, "backlinks")
    backlinkBuf.Type.Readonly = true

    -- Open in a vertical split (true = right side)
    bp:VSplitIndex(backlinkBuf, true)
end

-- ---------------------------------------------------------------------------
-- showUnlinked: show all notes with no incoming links
-- ---------------------------------------------------------------------------
function showUnlinked(bp)
    local root = getVaultRoot()
    if root == "" then
        micro.InfoBar():Message("Vault directory not set")
        return
    end

    -- Step 1: Get all wikilink targets mentioned anywhere in the vault
    local linkCmd = 'grep -roh "\\[\\[[^]]*\\]\\]" "' .. root .. '" --include="*.md" 2>/dev/null | sort -u'
    local linkOut, _ = shell.ExecCommand("sh", "-c", linkCmd)

    -- Build a set of linked note names (lowercased for case-insensitive matching)
    local linkedSet = {}
    if linkOut ~= nil and linkOut ~= "" then
        local remaining = strings.TrimSpace(linkOut)
        while remaining ~= "" do
            local nlIdx = strings.Index(remaining, "\n")
            local line
            if nlIdx >= 0 then
                line = string.sub(remaining, 1, nlIdx)
                remaining = string.sub(remaining, nlIdx + 2)
            else
                line = remaining
                remaining = ""
            end
            line = strings.TrimSpace(line)
            -- Strip [[ and ]]
            if #line > 4 then
                local linkName = string.sub(line, 3, #line - 2)
                linkedSet[string.lower(linkName)] = true
            end
        end
    end

    -- Step 2: Get all .md files in the vault
    local fileCmd = 'find "' .. root .. '" -name "*.md" -type f 2>/dev/null'
    local fileOut, _ = shell.ExecCommand("sh", "-c", fileCmd)

    local content = "# Unlinked Notes\n\nNotes with no incoming [[links]] from other notes:\n\n"
    local count = 0

    if fileOut ~= nil and fileOut ~= "" then
        local remaining = strings.TrimSpace(fileOut)
        while remaining ~= "" do
            local nlIdx = strings.Index(remaining, "\n")
            local line
            if nlIdx >= 0 then
                line = string.sub(remaining, 1, nlIdx)
                remaining = string.sub(remaining, nlIdx + 2)
            else
                line = remaining
                remaining = ""
            end
            line = strings.TrimSpace(line)
            if line ~= "" then
                -- Extract basename without .md
                local lineSlashIdx = strings.LastIndex(line, "/")
                local basename = line
                if lineSlashIdx >= 0 then
                    basename = string.sub(line, lineSlashIdx + 2)
                end
                if strings.HasSuffix(basename, ".md") then
                    basename = string.sub(basename, 1, #basename - 3)
                end

                -- Check if this note is linked from anywhere
                if not linkedSet[string.lower(basename)] then
                    content = content .. "- [[" .. basename .. "]]  " .. line .. "\n"
                    count = count + 1
                end
            end
        end
    end

    if count == 0 then
        content = content .. "(all notes have at least one incoming link)\n"
    else
        content = content .. "\n(" .. count .. " unlinked notes)\n"
    end

    content = content .. "\n---\nAlt-g to follow a link | Alt-b to go back\n"

    local unlinkBuf = buffer.NewBuffer(content, "unlinked")
    unlinkBuf.Type.Readonly = true

    bp:VSplitIndex(unlinkBuf, true)
end

-- ---------------------------------------------------------------------------
-- imageLink: copy an image to vault media dir and insert markdown link
-- ---------------------------------------------------------------------------
function imageLink(bp)
    local root = getVaultRoot()
    if root == "" then
        micro.InfoBar():Message("Vault directory not set")
        return
    end

    micro.InfoBar():Prompt("Image path: ", "", "file", function(input, cancelled)
        if cancelled or input == nil or input == "" then
            return
        end

        local srcPath = strings.TrimSpace(input)

        -- Extract the original filename
        local name = srcPath
        local slashIdx = strings.LastIndex(srcPath, "/")
        if slashIdx >= 0 then
            name = string.sub(srcPath, slashIdx + 2)
        end
        -- Also handle backslash for Windows paths
        local bslashIdx = strings.LastIndex(name, "\\")
        if bslashIdx >= 0 then
            name = string.sub(name, bslashIdx + 2)
        end

        -- Create date prefix
        local time = import("time")
        local now = time.Now()
        local dateStr = now:Format("2006-01-02")
        local destName = dateStr .. "-" .. name

        -- Ensure media directory exists
        local mediaDir = filepath.Join(root, "media")
        shell.ExecCommand("sh", "-c", 'mkdir -p "' .. mediaDir .. '"')

        -- Copy the file
        local destPath = filepath.Join(mediaDir, destName)
        local _, cpErr = shell.ExecCommand("sh", "-c", 'cp "' .. srcPath .. '" "' .. destPath .. '"')
        if cpErr ~= nil then
            micro.InfoBar():Message("Error copying image: " .. tostring(cpErr))
            return
        end

        -- Insert markdown image link at cursor
        local cursor = bp.Buf:GetActiveCursor()
        local linkText = "![" .. name .. "](media/" .. destName .. ")"
        bp.Buf:Insert(buffer.Loc(cursor.X, cursor.Y), linkText)

        micro.InfoBar():Message("Image linked: media/" .. destName)
    end)
end

-- ---------------------------------------------------------------------------
-- vaultSearch: full-text search across vault using grep + fzf
-- ---------------------------------------------------------------------------
function vaultSearch(bp)
    local root = getVaultRoot()
    if root == "" then
        micro.InfoBar():Message("Vault directory not set")
        return
    end

    -- Use grep -rn for recursive search with line numbers, piped to fzf
    local cmd = 'grep -rn --include="*.md" "" "' .. root .. '" | fzf --delimiter=: --preview="head -n {2} {1} | tail -n 20"'

    local output, err = shell.RunInteractiveShell(cmd, false, true)

    if err ~= nil then
        -- User likely pressed Escape in fzf
        return
    end

    output = strings.TrimSpace(output)
    if output == "" then return end

    -- Parse output: /path/to/file.md:42:matching line content
    local colonIdx = strings.Index(output, ":")
    if colonIdx < 0 then return end

    local filePath = string.sub(output, 1, colonIdx)
    local rest = string.sub(output, colonIdx + 2)

    local lineNum = 0
    local colonIdx2 = strings.Index(rest, ":")
    if colonIdx2 >= 0 then
        local lineStr = string.sub(rest, 1, colonIdx2)
        lineNum = tonumber(lineStr) or 0
    end

    saveIfModified(bp)
    pushHistory(bp)

    local buf, bufErr = buffer.NewBufferFromFile(filePath)
    if bufErr ~= nil then
        micro.InfoBar():Message("Error opening file: " .. tostring(bufErr))
        return
    end
    bp:OpenBuffer(buf)

    -- Jump to the matched line (lineNum is 1-based from grep, cursor.Y is 0-based)
    if lineNum > 0 then
        local cursor = bp.Buf:GetActiveCursor()
        cursor.Y = lineNum - 1
        cursor.X = 0
        cursor:Relocate()
        bp:Center()
    end
end

-- ---------------------------------------------------------------------------
-- randomNote: open a random markdown file from the vault
-- ---------------------------------------------------------------------------
function randomNote(bp)
    local root = getVaultRoot()
    if root == "" then
        micro.InfoBar():Message("Vault directory not set")
        return
    end

    local cmd
    if runtime.GOOS == "windows" then
        cmd = 'powershell -Command "Get-ChildItem -Path \'' .. root .. '\' -Recurse -Filter *.md | Get-Random | Select-Object -ExpandProperty FullName"'
    else
        cmd = 'find "' .. root .. '" -name "*.md" -type f | shuf -n 1'
    end

    local out, err = shell.ExecCommand("sh", "-c", cmd)
    if err ~= nil or out == nil or out == "" then
        micro.InfoBar():Message("No notes found in vault")
        return
    end

    local fullPath = strings.TrimSpace(out)
    if fullPath == "" then return end

    saveIfModified(bp)
    pushHistory(bp)

    local buf, bufErr = buffer.NewBufferFromFile(fullPath)
    if bufErr ~= nil then
        micro.InfoBar():Message("Error opening file: " .. tostring(bufErr))
        return
    end
    bp:OpenBuffer(buf)

    -- Extract just the filename for the message
    local name = fullPath
    local slashIdx = strings.LastIndex(fullPath, "/")
    if slashIdx >= 0 then
        name = string.sub(fullPath, slashIdx + 2)
    end
    micro.InfoBar():Message("Random note: " .. name)
end

-- ---------------------------------------------------------------------------
-- copyPath: copy the current file's absolute path to clipboard
-- ---------------------------------------------------------------------------
function copyPath(bp)
    local path = bp.Buf.AbsPath
    if path == "" or path == nil then
        path = bp.Buf.Path
    end

    clip.WriteAll(path, "clipboard")

    micro.InfoBar():Message("Copied: " .. path)
end

-- ---------------------------------------------------------------------------
-- init: register commands and key bindings
-- ---------------------------------------------------------------------------
function init()
    config.MakeCommand("wikilink.follow", followLink, config.NoComplete)
    config.MakeCommand("wikilink.back", goBack, config.NoComplete)
    config.MakeCommand("wikilink.open", openNote, config.NoComplete)
    config.MakeCommand("wikilink.path", copyPath, config.NoComplete)
    config.MakeCommand("wikilink.random", randomNote, config.NoComplete)
    config.MakeCommand("wikilink.search", vaultSearch, config.NoComplete)
    config.MakeCommand("wikilink.image", imageLink, config.NoComplete)
    config.MakeCommand("wikilink.backlinks", showBacklinks, config.NoComplete)
    config.MakeCommand("wikilink.unlinked", showUnlinked, config.NoComplete)

    config.TryBindKey("Alt-g", "command:wikilink.follow", false)
    config.TryBindKey("Alt-b", "command:wikilink.back", false)
    config.TryBindKey("Alt-o", "command:wikilink.open", false)
    config.TryBindKey("Alt-p", "command:wikilink.path", false)
    config.TryBindKey("Alt-r", "command:wikilink.random", false)
    config.TryBindKey("Alt-s", "command:wikilink.search", false)
    config.TryBindKey("Alt-i", "command:wikilink.image", false)
    config.TryBindKey("Alt-l", "command:wikilink.backlinks", false)
    config.TryBindKey("Alt-u", "command:wikilink.unlinked", false)

    config.AddRuntimeFile("wikilink", config.RTSyntax, "wikilink.yaml")
    config.AddRuntimeFile("wikilink", config.RTHelp, "help/wikilink.md")

    micro.Log("wikilink plugin v" .. VERSION .. " loaded")
end
