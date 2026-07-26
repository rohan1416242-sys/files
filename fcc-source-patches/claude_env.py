"""Shared Claude Code environment policy for FCC client surfaces."""

from collections.abc import Mapping

from free_claude_code.cli.local_http import with_local_proxy_bypass
from free_claude_code.cli.proxy_auth import proxy_auth_token

# MAX-TPS PATCH: bumped from 190000 to 900000 to use inkling's 1M context
# window fully. Auto-compact only fires at 900K tokens instead of 190K,
# eliminating the constant 30-60s compaction pauses that made Claude Code
# feel "lazy". Safe because thinkingmachines/inkling has 1M context.
CLAUDE_CODE_AUTO_COMPACT_WINDOW = "900000"
CLAUDE_BINARY_NAME = "claude"


def build_claude_proxy_env(
    *,
    proxy_root_url: str,
    auth_token: str,
    base_env: Mapping[str, str],
) -> dict[str, str]:
    """Return the canonical environment for Claude Code proxy sessions."""

    # Claude's aggregate traffic flag also suppresses gateway model discovery.
    env = with_local_proxy_bypass(
        {
            key: value
            for key, value in base_env.items()
            if not key.startswith("ANTHROPIC_")
            and key != "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
        },
        proxy_root_url=proxy_root_url,
    )
    env["ANTHROPIC_BASE_URL"] = proxy_root_url
    env["ANTHROPIC_AUTH_TOKEN"] = proxy_auth_token(auth_token)
    env["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
    env["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] = CLAUDE_CODE_AUTO_COMPACT_WINDOW
    env["DISABLE_AUTOUPDATER"] = "1"
    env["DISABLE_FEEDBACK_COMMAND"] = "1"
    env["DISABLE_ERROR_REPORTING"] = "1"

    # === MAX-TPS PATCH: aggressive Claude Code env vars ===
    # Cap output tokens to inkling's max (8192) to prevent wasteful
    # "exceeded 32000 token maximum" errors that trigger retries.
    env["CLAUDE_CODE_MAX_OUTPUT_TOKENS"] = "8192"

    # Give bash commands 10 min default / 30 min max so long-running build
    # commands don't get killed mid-flight.
    env["BASH_DEFAULT_TIMEOUT_MS"] = "600000"
    env["BASH_MAX_TIMEOUT_MS"] = "1800000"

    # MCP servers: 10 min startup timeout, 100K token output cap.
    env["MCP_TIMEOUT"] = "600000"
    env["MAX_MCP_OUTPUT_TOKENS"] = "100000"

    # Maximize thinking tokens. inkling supports continuous thinking effort
    # 0.2-0.99; FCC's reasoning_effort=max already maps to the right value,
    # but MAX_THINKING_TOKENS ensures Claude Code doesn't auto-reduce it.
    env["MAX_THINKING_TOKENS"] = "8192"

    # Only auto-compact at 95% of context window (vs default ~80%) so we
    # use the full 1M inkling context before triggering compaction.
    env["CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"] = "95"

    # Disable Claude's adaptive thinking - prevents it from auto-reducing
    # thinking depth when it "feels" confident. We want max thinking always.
    env["CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING"] = "1"

    # Disable the bug-command (saves a hidden API call).
    env["DISABLE_BUG_COMMAND"] = "1"

    return env
