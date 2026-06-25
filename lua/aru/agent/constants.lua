---@module "aru.agent.constants"
---Shared constants for the Neovim agent integration.

local M = {}

M.DEFAULT_SURROUNDING_LINES = 50

M.DESTINATION = {
    CURRENT = "current",
    SESSION = "session",
    READ = "read",
    SCRATCH = "scratch",
    GENERATE = "generate",
}

M.EVENT = {
    MESSAGE_UPDATE = "message_update",
    THINKING_DELTA = "thinking_delta",
    TEXT_DELTA = "text_delta",
}

M.PAYLOAD = {
    VERSION = 1,
    SOURCE = "nvim",
}

M.RUNTIME = {
    LEGACY_TUI_COMMAND = "pi",
    JSON_ARGS = { "--mode", "json", "--print", "--no-session", "--no-tools" },
    SCRATCH_ARGS = { "--no-session" },
}

M.TMUX = {
    COMMAND = "tmux",
    SUBMIT_KEY = "C-m",
    BUFFER_PREFIX = "aru-agent-",
    FORMATS = {
        SESSION_NAME = "#{session_name}",
        WINDOWS = "#{window_id}\t#{window_name}",
        PANES = "#{pane_id}\t#{pane_active}\t#{pane_current_command}",
    },
}

M.UI = {
    FILETYPE_MARKDOWN = "markdown",
    HIGHLIGHT_COMMENT = "Comment",
    STYLE_MINIMAL = "minimal",
    BORDER_ROUNDED = "rounded",
    TITLE_POS_LEFT = "left",
    READ_FLOAT = {
        WIDTH = 60,
        ROW = 1,
        RIGHT_MARGIN = 3,
        BOTTOM_MARGIN = 3,
        HEIGHT_RATIO = 2 / 3,
        ZINDEX = 49,
    },
    PROMPT = {
        MAX_ROWS = 10,
        WIDTH = 58,
        LEFT_PADDING = 1,
        DECORATION_ROWS = 2,
        BORDER_ROWS = 2,
        BELOW_CURSOR_MARGIN = 1,
        ABOVE_CURSOR_MARGIN = 2,
        RIGHT_MARGIN = 4,
        ZINDEX = 50,
    },
}

M.NAMESPACE = {
    GENERATE = "aru_generate",
    READ_FLOAT = "aru_read_float",
    PROMPT_FOOTER = "aru_agent_prompt_footer",
}

M.AUGROUP = {
    READ_FLOAT = "AruReadFloat",
    PROMPT = "AruAgentPrompt",
}

M.SESSION = {
    TEMP_CLEANUP_DELAY_MS = 60000,
}

return M
