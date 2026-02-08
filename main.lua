VERSION = "0.1.0"

local micro   = import("micro")
local config  = import("micro/config")
local shell   = import("micro/shell")
local buffer  = import("micro/buffer")
local os      = import("os")
local filepath = import("filepath")
local strings = import("strings")
local runtime = import("runtime")

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
        local cmd = 'dir /s /b "' .. root .. '\\' .. name .. '" 2>nul'
        out, err = shell.ExecCommand("cmd", "/c", cmd)
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

    -- Save current position before navigating
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
        cmd = 'cd /d "' .. root .. '" && dir /s /b *.md | fzf'
    else
        cmd = 'cd "' .. root .. '" && find . -name "*.md" -type f | fzf'
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

    pushHistory(bp)

    local buf, bufErr = buffer.NewBufferFromFile(fullPath)
    if bufErr ~= nil then
        micro.InfoBar():Message("Error opening file: " .. tostring(bufErr))
        return
    end
    bp:OpenBuffer(buf)
end

-- ---------------------------------------------------------------------------
-- init: register commands and key bindings
-- ---------------------------------------------------------------------------
function init()
    config.MakeCommand("wikilink.follow", followLink, config.NoComplete)
    config.MakeCommand("wikilink.back", goBack, config.NoComplete)
    config.MakeCommand("wikilink.open", openNote, config.NoComplete)

    config.TryBindKey("Alt-g", "command:wikilink.follow", false)
    config.TryBindKey("Alt-b", "command:wikilink.back", false)
    config.TryBindKey("Alt-o", "command:wikilink.open", false)

    config.AddRuntimeFile("wikilink", config.RTSyntax, "wikilink.yaml")

    micro.Log("wikilink plugin v" .. VERSION .. " loaded")
end
