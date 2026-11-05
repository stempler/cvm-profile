#!/usr/bin/env bash
#
# code-vm profile hook: ensure fisher is installed, (re)install the
# stempler/config.fish plugin, install the Starship binary, and install the
# Claude Code plugins the shipped skill and command depend on.
#
# Runs as the agent user (devuser), through the egress proxy, on every boot
# and every `code-vm profile apply`. It must therefore be idempotent.

set -euo pipefail

FISH_BIN=/usr/bin/fish

# Fisher is pinned to a specific commit so the curl-piped bootstrap fetches a
# byte-for-byte known payload (raw.githubusercontent.com/<SHA>/... is
# content-addressed by commit) rather than whatever `main` happens to be.
# Bump both the version comment and the SHA together.
#
# renovate: fisher 4.4.8
FISHER_REF=a04308be92daa6cfecdbb0ca58b1e8508664cff2
FISHER_RAW="https://raw.githubusercontent.com/jorgebucaran/fisher/${FISHER_REF}/functions/fisher.fish"

# 1. Ensure fisher is installed. `functions -q fisher` triggers fish's
#    autoloader, so this is true once the function file is on disk.
if ! "$FISH_BIN" -c 'functions -q fisher'; then
    echo "hook: installing fisher (${FISHER_REF})"
    curl -fsSL "$FISHER_RAW" \
        | "$FISH_BIN" -c "source /dev/stdin && fisher install jorgebucaran/fisher@${FISHER_REF}"
else
    echo "hook: fisher already present"
fi

# 2. Install stempler/config.fish, or update it to latest if already installed.
#    `fisher install` is idempotent and refreshes the plugin on each run.
#
#    stdin is closed explicitly: when stdin is not a TTY, fisher reads plugin
#    names from it until EOF. `code-vm profile apply` can hand the hook an open
#    pipe that never closes, and fisher then blocks forever.
echo "hook: installing/updating stempler/config.fish"
"$FISH_BIN" -c 'fisher install stempler/config.fish' < /dev/null

# 3. Install the Starship prompt (https://starship.rs).
#
# Pinned to a specific release and verified against its published SHA256 so the
# download is a byte-for-byte known payload rather than tracking latest — the
# same discipline as the fisher bootstrap above. Bump the version comment, the
# renovate marker, and STARSHIP_VERSION together.
#
# renovate: starship 1.26.0
STARSHIP_VERSION=v1.26.0
STARSHIP_BIN="$HOME/.local/bin/starship"
STARSHIP_ASSET=starship-x86_64-unknown-linux-gnu.tar.gz
STARSHIP_BASE="https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}"

install_starship() {
    local arch tmp expected
    arch=$(uname -m)
    if [ "$arch" != "x86_64" ]; then
        echo "hook: unsupported architecture '$arch'; the starship asset is x86_64-only" >&2
        return 1
    fi

    tmp=$(mktemp -d)

    echo "hook: downloading starship ${STARSHIP_VERSION}"
    if ! curl -fsSL "${STARSHIP_BASE}/${STARSHIP_ASSET}" -o "$tmp/starship.tar.gz" \
        || ! curl -fsSL "${STARSHIP_BASE}/${STARSHIP_ASSET}.sha256" -o "$tmp/starship.sha256"; then
        rm -rf "$tmp"
        echo "hook: failed to download starship" >&2
        return 1
    fi

    # The published .sha256 asset is a bare hash; sha256sum -c wants "<hash>  <file>".
    expected=$(cut -d' ' -f1 < "$tmp/starship.sha256")
    if ! echo "${expected}  $tmp/starship.tar.gz" | sha256sum -c - >/dev/null 2>&1; then
        rm -rf "$tmp"
        echo "hook: starship checksum verification FAILED; aborting" >&2
        return 1
    fi
    echo "hook: starship checksum verified"

    mkdir -p "$HOME/.local/bin"
    tar -xzf "$tmp/starship.tar.gz" -C "$HOME/.local/bin" starship
    chmod +x "$STARSHIP_BIN"
    rm -rf "$tmp"
}

# Install only when missing or when the pinned version differs, so boots and
# `profile apply` don't re-download an already-current binary.
#
# The fish loader (conf.d/starship.fish) and prompt config (starship.toml) are
# NOT installed here: they are static files, shipped through the profile's
# files/ tree and installed into the agent home by code-vm before this hook
# runs. Only the binary — which must be downloaded, verified and extracted —
# needs the hook.
if [ -x "$STARSHIP_BIN" ] && "$STARSHIP_BIN" --version 2>/dev/null | grep -qF "${STARSHIP_VERSION#v}"; then
    echo "hook: starship ${STARSHIP_VERSION} already present"
else
    install_starship
fi

# 4. Claude Code plugins.
#
# The profile ships a `review-loop` skill and an `/rl` command (files/.claude)
# that depend on two plugins from the official marketplace: superpowers (the
# review skills the loop calls) and ralph-loop (the stop hook that re-feeds the
# prompt). Plugins live under ~/.claude/plugins, which persists on the guest
# disk, so only what is missing gets installed; a boot with both present does
# no network I/O here.
#
# Presence is checked as `<plugin>@*`, not `<plugin>@claude-plugins-official`:
# a copy installed from another source (e.g. the in-app plugin directory, which
# registers as `@anthropic-plugin-directory`) counts. A second copy of the same
# plugin would register its hooks twice — ralph-loop's stop hook would then
# bump the iteration counter twice per turn.
#
# Unlike fisher and Starship above, plugins are NOT pinned: `claude plugin
# install` takes whatever the marketplace currently offers. The CLI has no
# version selector, and the marketplace clone it keeps is updated on its own
# schedule.
#
# Note: `claude plugin install` rewrites ~/.claude/settings.json (enabledPlugins)
# by replacing the file, so after a boot that actually installs something the
# file is agent-owned until the next boot or `code-vm config apply` relocks it.
# The lock step preserves enabledPlugins across that relock.
CLAUDE_BIN="$HOME/.local/bin/claude"
if [ ! -x "$CLAUDE_BIN" ]; then
    CLAUDE_BIN=$(command -v claude || true)
fi

plugin_installed() {
    "$CLAUDE_BIN" plugin list --json < /dev/null 2>/dev/null \
        | jq -e --arg p "$1" 'any(.[]?; .id | startswith($p + "@"))' >/dev/null
}

if [ -z "$CLAUDE_BIN" ] || [ ! -x "$CLAUDE_BIN" ]; then
    echo "hook: claude CLI not found; skipping plugin install" >&2
else
    for plugin in superpowers ralph-loop; do
        if plugin_installed "$plugin"; then
            echo "hook: plugin ${plugin} already present"
        else
            echo "hook: installing plugin ${plugin} from anthropics/claude-plugins-official"
            # --marketplace adds the marketplace first when it is not known yet.
            "$CLAUDE_BIN" plugin install "$plugin" --marketplace anthropics/claude-plugins-official < /dev/null
        fi
    done
fi

echo "hook: done"
