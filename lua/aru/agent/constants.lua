---@module "aru.agent.constants"
---Shared constants for the Neovim agent integration.

local M = {}

M.DEFAULT_SURROUNDING_LINES = 50

M.RUNTIME = {
    pi = {
        JSON_ARGS = { "--mode", "json" },
        NO_SESSION = "--no-session",
        PRESET = "--preset",
        SESSION_DIR = "--session-dir",
        SESSION_ID = "--session-id",
    },
}

M.EVENT = {
    MESSAGE_UPDATE = "message_update",
    THINKING_DELTA = "thinking_delta",
    TEXT_DELTA = "text_delta",
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
        ROW = 1,
        SIDE_MARGIN = 3,
        BOTTOM_MARGIN = 3,
        HEIGHT_RATIO = 2 / 3,
        ZINDEX = 49,
    },
    PROMPT = {
        MIN_ROWS = 8,
        MAX_ROWS = 20,
        WIDTH = 100,
        LEFT_PADDING = 1,
        BORDER_ROWS = 2,
        ZINDEX = 50,
    },
}

M.NAMESPACE = {
    EDITOR = "aru_editor",
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
