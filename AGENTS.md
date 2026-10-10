# AGENTS.md

This repository follows the NoCapRx build pack. The single source of truth for
agents and GitHub Copilot is:

- [`.github/copilot-instructions.md`](.github/copilot-instructions.md) — master prompt
- [`concept.md`](concept.md) — product concept and current implementation boundary
- [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md) — behavioral spec
- [`docs/RULEPACK_SCHEMA.md`](docs/RULEPACK_SCHEMA.md) — signed clinical rule pack
- [`docs/EXPLANATION_LAYER.md`](docs/EXPLANATION_LAYER.md) — safe LLM explanation layer
- [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) — data model
- [`docs/SECURITY.md`](docs/SECURITY.md) and [`docs/REGULATORY.md`](docs/REGULATORY.md)

Scoped rules live in `.github/instructions/*.instructions.md` (applied by glob).
Phase prompts live in `.github/prompts/*.prompt.md`.

Non-negotiables: the LLM never makes clinical decisions; copy is advisory, never
directive; raw VCF never leaves the device; clinical content is ingested from
CPIC, never invented; unknown input returns a safe indeterminate result.
