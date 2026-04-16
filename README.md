# marketplace

Skills and plugins published by the **ArtificiallySocial** organization for [Claude Code](https://claude.com/claude-code).

## Install

```
/plugin marketplace add ArtificiallySocial/marketplace
/plugin install system-check@marketplace
```

## Plugins

| Plugin | Description |
|--------|-------------|
| [`system-check`](plugins/system-check) | Quick health check of the local development environment — memory, load, disk, Claude processes — and auto-invoke `cleanup-claude-procs` if stray Claude sessions are detected. |

## Layout

```
.claude-plugin/
  marketplace.json         # catalog
plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json          # manifest + semver
    skills/
      <skill-name>/
        SKILL.md           # frontmatter + instructions
```
