# Contributing to kevnord-plugins

Thanks for your interest in contributing! This guide covers how to create, test, and submit plugins to the marketplace.

## Plugin Specification

Every plugin must include:

| File | Required | Purpose |
|------|----------|---------|
| `.claude-plugin/plugin.json` | Yes | Plugin manifest (name, description, version) |
| `README.md` | Yes | Documentation with usage examples |
| `commands/*.md` | * | Slash command definitions |
| `skills/*/SKILL.md` | * | Skill definitions |
| `agents/*.md` | * | Agent definitions |

*A plugin must have at least one command, skill, or agent.

### Plugin Manifest (`plugin.json`)

The manifest in the plugin directory should be minimal -- metadata like author, license, and category belong in the marketplace entry, not in the plugin manifest.

```json
{
  "name": "my-plugin",
  "description": "What the plugin does in one sentence",
  "version": "1.0.0"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Kebab-case plugin name, unique across the marketplace |
| `description` | string | Yes | One-sentence description |
| `version` | string | Yes | Semver version (e.g., `1.0.0`) |

Additional fields like `commands`, `agents`, `hooks`, `mcpServers`, and `lspServers` can be specified to override default discovery. See the [plugin reference](https://code.claude.com/docs/en/plugins-reference) for the full manifest schema.

### Marketplace Entry

When adding your plugin to `.claude-plugin/marketplace.json`, you can include richer metadata:

```json
{
  "name": "my-plugin",
  "source": "./plugins/my-plugin",
  "description": "What the plugin does",
  "version": "1.0.0",
  "author": {
    "name": "your-github-username"
  },
  "license": "MIT",
  "category": "code-quality",
  "keywords": ["keyword1", "keyword2"],
  "tags": ["tag1", "tag2"]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Kebab-case plugin name |
| `source` | string or object | Yes | Where to fetch the plugin (relative path, GitHub, git URL, npm, pip) |
| `description` | string | No | Brief plugin description |
| `version` | string | No | Plugin version |
| `author` | object | No | `{ "name": "...", "email": "..." }` |
| `license` | string | No | SPDX license identifier (e.g., `MIT`) |
| `category` | string | No | Plugin category for organization |
| `keywords` | string[] | No | Tags for plugin discovery |
| `tags` | string[] | No | Tags for searchability |
| `homepage` | string | No | Plugin homepage or docs URL |
| `repository` | string | No | Source code repository URL |

### Command Format

Commands are markdown files with YAML frontmatter:

```markdown
---
description: What the command does
argument-hint: "[--flag <value>]"
---

# Command Name

Instructions for Claude to follow when the command is invoked.
```

### Skill Format

Skills are markdown files with YAML frontmatter:

```markdown
---
name: skill-name
description: What the skill does and when to use it. Include keywords that help agents identify relevant tasks.
---

# Skill Name

## Purpose
What this skill does.

## Evaluation Criteria
What to look for and how to assess it.
```

## Creating a New Plugin

### 1. Scaffold from template

```bash
cp -r templates/plugin plugins/my-plugin
```

### 2. Fill in the template

Replace all `{{placeholder}}` values in:
- `.claude-plugin/plugin.json`
- `README.md`
- `commands/example.md` (rename to match your command)
- `skills/example-skill/SKILL.md` (rename directory and file)

### 3. Register in the marketplace

Add your plugin to `.claude-plugin/marketplace.json` in the `plugins` array:

```json
{
  "name": "my-plugin",
  "source": "./plugins/my-plugin",
  "description": "What the plugin does",
  "version": "1.0.0",
  "author": {
    "name": "your-github-username"
  },
  "license": "MIT",
  "category": "developer-tools",
  "keywords": ["keyword1", "keyword2"]
}
```

### 4. Test locally

```bash
# Validate the marketplace structure
/plugin validate .

# Add the local marketplace
/plugin marketplace add ./path/to/claude-plugins

# Install your plugin
/plugin install my-plugin@kevnord-plugins

# Test your commands
/my-command
```

### 5. Submit a pull request

```bash
git checkout -b add-my-plugin
git add plugins/my-plugin .claude-plugin/marketplace.json
git commit -m "Add my-plugin: short description"
```

Open a PR with:
- What the plugin does
- Example output
- Which repos you tested against

## Extending an Existing Plugin

See the plugin's own README for extension points. Common patterns:

- **Adding criteria** -- drop a config file in the plugin's designated directory
- **Adding stack support** -- add `references/<stack>.md` files
- **Adding commands** -- add markdown files to `commands/` and register in `plugin.json`

## Quality Guidelines

- **Test on real repos** before submitting
- **Keep commands focused** -- each command should do one thing well
- **Document everything** -- users should be able to get started from the README alone
- **No secrets or credentials** -- never commit API keys, tokens, or sensitive data
- **No external dependencies** -- plugins are pure markdown; don't require npm install or pip install
- **Idempotent commands** -- running a command twice should produce the same result
- **Graceful failures** -- commands should handle edge cases (empty repos, missing files) without crashing

## Review Criteria

PRs are reviewed for:

1. **Correctness** -- does the plugin do what it claims?
2. **Quality** -- are commands well-structured with clear instructions?
3. **Documentation** -- is the README complete with usage examples?
4. **Safety** -- no destructive actions without user confirmation
5. **Uniqueness** -- does this add something the marketplace doesn't already have?
