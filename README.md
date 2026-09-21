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

### Option A: plugin marketplace

```
/plugin marketplace add yanmad27/my-orchestrate-skill
/plugin install orchestrate@my-orchestrate-skill
```

Then configure Paseo:

```sh
git clone https://github.com/yanmad27/my-orchestrate-skill.git /tmp/my-orchestrate-skill
/tmp/my-orchestrate-skill/install.sh --paseo-only
rm -rf /tmp/my-orchestrate-skill
```

This skips the skill copy (already installed via plugin) and merges the Paseo
config. Or merge `paseo/config.snippet.json` into `~/.paseo/config.json` manually.

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

1. In Paseo, open (or create) an agent using the **Lead** profile.
2. Run `/orchestrate <task>`.

The Lead agent will plan, delegate to Cheap worker / Worker / Reviewer as
appropriate, and report back with the outcome and files changed.
