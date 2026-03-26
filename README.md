# kevnord-plugins

A curated marketplace of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugins -- community-built skills and commands that extend what Claude can do in your codebase.

## Plugin Catalog

### Code Quality

| Plugin | Description | Commands | Version |
|--------|-------------|----------|---------|
| [scorecard](plugins/scorecard/) | Scored code quality assessment across 10 dimensions (security, performance, testability, etc.) | `/scorecard` | 1.0.0 |

### Workflow

| Plugin | Description | Commands | Version |
|--------|-------------|----------|---------|
| [guided-dev](plugins/guided-dev/) | Structured development workflow with intake, clarification, planning, implementation, verification, and PR creation | `/guided-dev` | 2.3.0 |

> More plugins coming soon. [Submit yours!](CONTRIBUTING.md)

## Installation

### Add the marketplace

```
/plugin marketplace add kevnord/claude-plugins
```

### Install a plugin

```
/plugin install scorecard@kevnord-plugins
```

### Update plugins

```
/plugin marketplace update kevnord-plugins
```

### Require for your team

Add to your project's `.claude/settings.json` so team members are prompted to install automatically:

```json
{
  "extraKnownMarketplaces": {
    "kevnord-plugins": {
      "source": {
        "source": "github",
        "repo": "kevnord/claude-plugins"
      }
    }
  },
  "enabledPlugins": {
    "scorecard@kevnord-plugins": true
  }
}
```

## Usage

Once installed, plugins expose slash commands in Claude Code:

```bash
# Run a full repo audit
/scorecard

# Audit specific categories
/scorecard --categories security,performance

# Audit only uncommitted changes
/scorecard --scope uncommitted

# Set a quality gate
/scorecard --min-score 7
```

See each plugin's README for full usage details and options.

## Repository Structure

```
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json        # Plugin registry (marketplace catalog)
├── plugins/
│   └── scorecard/             # Individual plugin
│       ├── .claude-plugin/
│       │   └── plugin.json     # Plugin manifest
│       ├── commands/           # Slash commands (markdown)
│       ├── skills/             # Reusable skills (markdown)
│       └── README.md
├── templates/
│   └── plugin/                 # Starter template for new plugins
├── install.sh                  # Standalone installer (alternative to /plugin install)
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

## Creating a Plugin

Use the included template to scaffold a new plugin:

```bash
cp -r templates/plugin plugins/my-plugin
```

Then fill in the `{{placeholders}}` in the template files. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide and plugin specification.

## Contributing

We welcome new plugins! See [CONTRIBUTING.md](CONTRIBUTING.md) for:

- Plugin specification and required files
- How to scaffold from the template
- Submission and review process
- Quality guidelines

## License

MIT License. See [LICENSE](LICENSE) for details.
