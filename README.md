# orchestrate

A Claude Code skill that turns the current session into a lead orchestrator
inside [Paseo](https://paseo.sh): it delegates every unit of real work to
subagents via `create_agent`, routes each task to the cheapest capable model
tier, and reviews the result before reporting back. It never edits files or
writes code itself.

## Requirements

- Claude Code
- Paseo, with the daemon config described below
- `jq` (only needed for the install script's config merge)

Ensure Paseo MCP tool injection is enabled in `~/.paseo/config.json`:

```json
{
  "daemon": {
    "mcp": {
      "enabled": true,
      "injectIntoAgents": true
    }
  }
}
```

Without `injectIntoAgents: true`, the Lead agent will not have the `create_agent` tool.

## Install

### Paseo built-in skills

You do **not** need to install Paseo's built-in skills (Settings → Skills: `paseo`, `paseo-committee`, `paseo-advisor`, `paseo-handoff`, …). `/orchestrate` only requires the `create_agent` MCP tool, which comes from `daemon.mcp.injectIntoAgents`. Paseo's former `paseo-orchestrate` skill is deprecated and no longer shipped; this skill replaces it. Leave the built-in skills uninstalled to avoid the Lead picking up a competing delegation workflow.

### Option A: plugin marketplace

Run these as two separate commands in Claude Code (they cannot be combined in one turn):

1. Add the marketplace:

```
/plugin marketplace add yanmad27/my-orchestrate-skill
```

2. Install the plugin:

```
/plugin install orchestrate@my-orchestrate-skill
```

Then configure Paseo:

```sh
curl -fsSL https://raw.githubusercontent.com/yanmad27/my-orchestrate-skill/main/install.sh | bash -s -- --paseo-only
```

This skips the skill copy (already installed via plugin) and merges the Paseo
config (downloading `paseo/config.snippet.json` on the fly). Or merge
`paseo/config.snippet.json` into `~/.paseo/config.json` manually.

### Option B: clone + script

```sh
git clone https://github.com/yanmad27/my-orchestrate-skill.git
cd my-orchestrate-skill
./install.sh
```

This copies `skills/orchestrate` to `~/.claude/skills/orchestrate` and merges
`paseo/config.snippet.json` into `~/.paseo/config.json` (backing up the
original first). Use `./install.sh --skill-only` to skip the Paseo merge, or
`./install.sh --paseo-only` to skip the skill copy (e.g. if you installed
via the plugin marketplace and only need the config).

## Paseo configuration

The skill assumes four agent profiles and one provider exist in
`~/.paseo/config.json` (`daemon.agentProfiles` and `agents.providers`):

- **Lead** — provider `claude`, model `claude-opus-4-8`. The orchestrator
  profile; it has `create_agent` and delegates instead of implementing. Open
  a Paseo agent with this profile to run `/orchestrate`.
- **Cheap worker** — provider `claude-worker`, model `claude-haiku-4-5`. For
  extraction, formatting, log triage, mechanical refactors — the default
  down-tier target.
- **Worker** — provider `claude-worker`, model `claude-sonnet-5`. The default
  tier for implementation, debugging, and research.
- **Reviewer** — provider `claude-worker`, model `claude-sonnet-5`, plan mode.
  Read-only review of a worker's diff against the original acceptance
  criteria.

`claude-worker` (`agents.providers.claude-worker`) is a separate provider,
extending `claude`, with `create_agent`, `send_agent_prompt`, `cancel_agent`,
and other agent-control tools disabled. Workers must run under this provider
so a delegated subagent can't spawn or control further agents — only the Lead
profile (plain `claude` provider) can.

### Manual merge

If you'd rather not run `install.sh`, open `paseo/config.snippet.json` and
merge its `daemon.agentProfiles` entries and `agents.providers.claude-worker`
into `~/.paseo/config.json` by hand, then run `paseo daemon reload`.

## Restart the daemon

After any install path, reload the Paseo daemon to load the new profiles and
provider:

```sh
paseo daemon reload
```

If profiles still don't appear, restart instead:

```sh
paseo daemon restart
```

Or quit the Paseo desktop app and restart it.

## Verify

After reload, the Paseo agent creation dialog should show four profiles:
**Lead**, **Cheap worker**, **Worker**, and **Reviewer**.

## Troubleshooting

**`/orchestrate` replies "This chat's provider has create_agent disabled"**

You are not running in a Lead-profile agent, or `daemon.mcp.injectIntoAgents`
is not set to `true` in `~/.paseo/config.json`. Check the config and verify
the MCP settings in [Requirements](#requirements).

**Profiles missing after install**

The daemon was not reloaded, or `~/.paseo/config.json` has invalid JSON.
Verify the config with:

```sh
jq . ~/.paseo/config.json
```

Then run `paseo daemon reload`.

## Usage

### Start a Lead agent

- In Paseo, open (or create) an agent and select the **Lead** profile (provider `claude`, model `claude-opus-4-8`).
- Ensure Paseo MCP injection is enabled and the daemon has been reloaded (see [Verify](#verify)).

### Invoke

**Slash command:**
```
/orchestrate <task>
```

**Auto-trigger:** The skill activates when you ask for delegation in natural language:
- `orchestrate this bug fix`
- `giao cho worker fix cái bug này`
- `delegate the refactor across agents`
- `spawn subagents to investigate why CI fails`

### Examples

- `/orchestrate rename UserSvc to UserService across the repo` → **Cheap worker** (mechanical refactor)
- `/orchestrate add rate limiting to the POST /login endpoint` → **Worker**, then **Reviewer** (implementation + review)
- `/orchestrate why does CI keep timing out on main?` → **Worker** (investigation), then **Worker** (apply fix), then **Reviewer**
- `/orchestrate review PR #42 for security issues` → **Reviewer** only (read-only audit)

### What happens

1. Lead agent receives the task; plans and decomposes it (≤3 tool calls to locate files/services).
2. For each unit of work, Lead chooses the lowest capable tier: Cheap worker, Worker, or escalates to Opus only if a same-tier retry fails for capability reasons.
3. Lead delegates via `create_agent` with a sharp spec, acceptance criteria, and output format; a worktree is created only if 2+ workers must edit files at the same time (sidebar tabs appear).
4. Lead surfaces any permission prompts to you; destructive actions never self-approve.
5. Implementation work gets an independent **Reviewer** pass (plan mode, read-only) before the Lead reports.
6. Lead reports outcome, files changed, and any unresolved findings.

### Tips

- **Give acceptance criteria:** "rename to snake_case and update all imports" beats "refactor this". The subagent sees none of this conversation.
- **Say "read-only"** if you want an audit, investigation, or code review without file changes.
- **Mention constraints:** If a file or area must not be touched, state it in the task.
- **Watch the sidebar:** If a task spawns multiple concurrent workers on files, worktree tabs appear — avoid switching tabs while they run.
- **Permission prompts are yours:** The Lead never auto-approves destructive actions; it surfaces them to you for confirmation.
