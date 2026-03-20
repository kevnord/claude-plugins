# CLAUDE.md

## Project Overview

This is a Claude Code plugin marketplace named `kevnord-plugins` -- a curated registry of community-built plugins that extend Claude Code with specialized skills and slash commands.

Users add this marketplace with `/plugin marketplace add kevnord/claude-plugins` and install individual plugins with `/plugin install <name>@kevnord-plugins`.

## Repository Structure

- `.claude-plugin/marketplace.json` -- marketplace catalog listing all plugins with metadata and sources
- `plugins/<name>/` -- individual plugin directories, each containing:
  - `.claude-plugin/plugin.json` -- plugin manifest (name, description, version)
  - `commands/` -- slash command definitions (markdown with YAML frontmatter)
  - `skills/` -- reusable skill definitions (markdown with YAML frontmatter)
  - `README.md` -- plugin-specific documentation
- `templates/plugin/` -- starter template for creating new plugins
- `install.sh` -- standalone installer script (alternative to `/plugin install`)

## Conventions

- Marketplace name: `kevnord-plugins`
- Plugin names use kebab-case (e.g., `scorecard`)
- Commands are markdown files in `commands/` with `description` and `argument-hint` frontmatter
- Skills are markdown files in `skills/<skill-name>/SKILL.md` with `name` and `description` frontmatter
- Each skill may have a `references/` subdirectory for tech-stack-specific extensions
- Plugin manifests (`plugin.json`) should be minimal -- rich metadata belongs in the marketplace entry
- The `source` field for in-repo plugins uses relative paths starting with `./`