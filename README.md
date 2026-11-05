# cvm-profile

A [code-vm](https://github.com/wetransform-os/code-vm) profile that makes
[fish](https://fishshell.com) the agent's default shell, installs
[fisher](https://github.com/jorgebucaran/fisher), installs/updates the
`stempler/config.fish` fish configuration, installs and configures the
[Starship](https://starship.rs) prompt, activates [mise](https://mise.jdx.dev),
and ships a Claude Code review-loop skill and `/rl` command together with
the plugins they depend on.

## What it does

| Requirement | How |
|---|---|
| fish is installed | `packages: [fish]` in `profile.yaml` (apt, as root) |
| fisher is installed | `hook.sh` bootstraps fisher from a **pinned commit** |
| fish is the default shell | `shell: /usr/bin/fish` in `profile.yaml` |
| `stempler/config.fish` installed/updated | `hook.sh` runs `fisher install stempler/config.fish` |
| Starship is installed | `hook.sh` downloads a **pinned, SHA256-verified** release binary to `~/.local/bin` |
| Starship is enabled + configured | `files/` ships the fish loader and `starship.toml` into the agent home |
| mise is activated in fish | `files/.config/fish/conf.d/mise.fish` runs `mise activate fish` |
| active mise env shown in prompt | `starship.toml` main prompt reuses `stempler/config.fish`'s `__mise_env_active` |
| agent worktree folders are git-ignored | `files/.config/git/ignore` ships a global gitignore |
| `review-loop` skill available to Claude | `files/.claude/skills/review-loop/SKILL.md` |
| `/rl` starts a bounded review loop | `files/.claude/commands/rl.md` |
| superpowers + ralph-loop plugins installed | `hook.sh` runs `claude plugin install` for each when missing |

The hook runs as the agent user on every boot and every `code-vm profile
apply`, and is idempotent: fisher is only bootstrapped when missing,
`fisher install stempler/config.fish` both installs and refreshes to latest,
Starship is only re-downloaded when missing or when the pinned version
changes, and Claude Code plugins are only installed when absent. The `files/`
tree is (re)installed by code-vm on every apply, so the shipped config is
canonical.

## Starship prompt

Starship is delivered two ways, each suited to what it ships:

**Binary — via `hook.sh`.** The hook downloads the pinned Starship release
tarball and its published `.sha256` from GitHub, verifies the checksum
(aborting on any mismatch), and extracts the `starship` binary to
`~/.local/bin`. Only the `x86_64-unknown-linux-gnu` asset is fetched; the hook
fails loudly on any other architecture rather than installing the wrong binary.

**Config — via the `files/` tree.** code-vm installs every path under a
profile's `files/` directory into the agent home (mirroring the layout), before
hooks run. This profile ships:

- `files/.config/fish/conf.d/starship.fish` → `~/.config/fish/conf.d/starship.fish`
  — the loader: ensures `~/.local/bin` is on `PATH`, then runs
  `starship init fish | source`. It lives in `conf.d` so it loads independently
  of `stempler/config.fish`.
- `files/.config/starship.toml` → `~/.config/starship.toml` — a prompt tuned
  for the sandbox (host name, directory, git state, command duration,
  success/failure indicator; Nerd-Font-free symbols).

## mise

mise is provided by the base sandbox image, so this profile only wires it in:

- **Activation** — `files/.config/fish/conf.d/mise.fish` runs
  `mise activate fish | source` (guarded by `type -q mise`), so shims, the
  managed environment, and the `mise` helper are available in every fish shell.
- **Prompt indicator** — the Starship main prompt shows the active mise
  environment(s) inline as `mise:<envs>`, e.g. `mise:dev` (comma-joined for
  several), between the git and command-duration segments. Rather than duplicate
  the detection, the `custom.mise_env` module reuses `stempler/config.fish`'s
  `__mise_env_active` (which reads `mise config ls` and lists loaded
  `mise.<env>.toml` / `config.<env>.toml` files, excluding `local`). When no
  named environment is active the module renders nothing.

  Three Starship subtleties are load-bearing here:
  - The module's `shell` list is `["fish", "--no-config"]` with **no** `-c`:
    Starship pipes the command in on stdin, and `--no-config` avoids re-running
    `conf.d` (which would re-activate mise and re-init Starship) on every prompt.
  - Display is gated with `when` (not `when = true`): when no env is active it
    exits non-zero and Starship drops the whole module, so the trailing space in
    `format` never leaks and the neighbouring segments keep single-spacing.
  - The separator space must live in `format`, not in the command output —
    Starship strips trailing whitespace from `$output`.

## Claude Code: review loop

The profile ships two files into `~/.claude` and installs the plugins they
need. code-vm forbids a profile from shipping `.claude/settings.json` and
`.claude/settings.local.json` (those are root-locked); every other path under
`.claude/` is an ordinary profile file, re-installed on each boot and apply.

**`review-loop` skill** — `files/.claude/skills/review-loop/SKILL.md` →
`~/.claude/skills/review-loop/SKILL.md`. One round of review-and-fix on the
current branch: request a review (superpowers:requesting-code-review), triage
(superpowers:receiving-code-review), fix only Critical/Important findings,
record decisions in `REVIEW_NOTES.md` at the repo root (working state, never
committed), and emit `<promise>REVIEW_CONVERGED</promise>` once a round brings
nothing new.

**`/rl` command** — `files/.claude/commands/rl.md` → `~/.claude/commands/rl.md`.
Starts a [Ralph loop](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-loop)
in the current session with the prompt fixed to *"Use the review-loop skill for
one round."* and the completion promise fixed to `REVIEW_CONVERGED`, so the
loop ends when the skill reports convergence. The only argument is the maximum
number of iterations, default 4:

```
/rl        # up to 4 rounds
/rl 8      # up to 8 rounds
```

The command is named `/rl` rather than `/review-loop` because user skills are
also exposed as slash commands, so `/review-loop` already belongs to the skill.

The command locates ralph-loop's `setup-ralph-loop.sh` at run time: it reads
`~/.claude/plugins/installed_plugins.json` for any plugin id starting with
`ralph-loop@` (whichever marketplace it came from) and falls back to the newest
`~/.claude/plugins/cache/*/ralph-loop/*/` directory. Plugin install paths carry
the version (and, for some sources, a commit hash), so a hard-coded path would
break on every plugin update.

**Plugins** — `hook.sh` installs `superpowers` and `ralph-loop` from the
official marketplace (`anthropics/claude-plugins-official`) when no
`<plugin>@*` entry is installed yet. The match is deliberately loose: a copy
installed by hand from another source (the in-app plugin directory registers
as `@anthropic-plugin-directory`) counts, because a second copy would register
the plugin's hooks twice and ralph-loop's stop hook would advance the
iteration counter twice per turn. Plugins persist under `~/.claude/plugins` on
the guest disk, so a boot with both present makes no network requests here.

Two things to know:

- Plugins are **not pinned**, unlike fisher and Starship: the Claude CLI has
  no version selector, so an install takes what the marketplace offers.
- `claude plugin install` records enablement in `~/.claude/settings.json` by
  replacing the file. After a boot that actually installs a plugin, that file
  is agent-owned until the next boot or `code-vm config apply` relocks it;
  code-vm's lock step preserves `enabledPlugins` across the relock. Boots that
  install nothing leave the lock untouched.

## Global gitignore

`files/.config/git/ignore` is installed as `~/.config/git/ignore`, git's
default global ignore file (used when `core.excludesFile` is unset). It ignores
the folders where agent sessions keep their worktrees, at repo roots only:

- `/.claude/worktrees/` — narrowed so other `.claude/` content (settings,
  commands, skills) that repos commit is not affected
- `/.orca/`

Hiding these from `git status` makes it less likely that an agent mistakes a
worktree created by another session for leftover clutter and removes it;
`git clean -fd` also skips ignored paths. It is not a hard guarantee:
`git clean -fdx` and a plain `rm -rf` still delete them.

## Egress domains

The profile adds these to the code-vm allowlist (in `profile.yaml`):

- `raw.githubusercontent.com` — fisher bootstrap script
- `api.github.com` — fisher plugin tarball endpoint (`owner/repo`)
- `codeload.github.com` — where `api.github.com` redirects tarball downloads
- `github.com` — Starship release download URL (issues the 302 redirect)
- `release-assets.githubusercontent.com` — where the Starship asset bytes are served

Plugin installs clone the marketplace and plugin repositories from
`github.com`, which is already listed; no extra domain is needed.

## Usage

```bash
code-vm profile add git@github.com:stempler/cvm-profile.git stempler
```

Then activate it in `~/.config/code-vm/config.yaml`:

```yaml
profiles:
  - stempler
```

Apply to a running VM (boots apply it automatically):

```bash
code-vm profile apply
```

## Pinned fisher version

fisher is pinned to a commit SHA in `hook.sh` (currently **4.4.8**,
`a04308be92daa6cfecdbb0ca58b1e8508664cff2`) so the curl-piped bootstrap
fetches a known payload rather than tracking `main`. To upgrade, update both
the `FISHER_REF` SHA and the accompanying version comment.

## Pinned Starship version

Starship is pinned to a release tag in `hook.sh` (currently **1.26.0**,
`STARSHIP_VERSION=v1.26.0`) and the downloaded tarball is verified against the
release's published `.sha256`, so the install is a byte-for-byte known payload.
To upgrade, bump `STARSHIP_VERSION`, the accompanying version comment, and the
`# renovate: starship <version>` marker together.
