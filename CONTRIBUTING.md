# Contributing

`scripts/validate.sh` enforces the plugin's core invariants. Run it before
pushing: `bash scripts/validate.sh`.

Invariants it checks:

- SKILL.md frontmatter: valid YAML, exactly `name`/`description`,
  `name == "orchestrate"`, one-line description mentioning `create_agent`,
  orchestrate, delegate.
- SKILL.md body keeps: `create_agent`, the ban on the built-in `Agent` tool,
  `list_profiles`, the opus-escalation rule, `Reviewer`, `$ARGUMENTS`.
- `.claude-plugin/plugin.json` + `marketplace.json`: valid JSON, matching
  `name`, semver `version`, and `description`.
- `paseo/config.snippet.json`: exactly the `Lead`/`Cheap worker`/`Worker`/
  `Reviewer` profiles and the `claude-worker` provider.
- `install.sh`: valid syntax/lint, works locally and piped.
- `README.md`: keeps `## Install`/`## Usage`/`## Troubleshooting` and
  mentions `/orchestrate`.

Bump the version in **both** `.claude-plugin` JSON files whenever SKILL.md
or install.sh changes. PRs need the `validate` check green before merge.
