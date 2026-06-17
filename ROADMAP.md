# Roadmap

## Research-Driven Additions (2026-06-09)

### Later (backlog, larger effort or lower priority)

- [ ] **Investigate PowerShell 7 native JSON Schema validation** -- `Test-Json -SchemaFile` in PowerShell 7.4+ uses JsonSchema.NET natively. Evaluate whether the custom `Test-JsonSchemaContract` function in sync-profile.ps1 can be replaced with the built-in cmdlet, reducing custom validation code. Known caveat: some PowerShell 7.4.0 schema bugs (GitHub issue #20743). Impact: 2, Effort: M.

- [ ] **Add sync-profile.ps1 function-level documentation** -- The script exports 100+ functions via the test seam but lacks parameter-level documentation or synopsis comments. Adding `[CmdletBinding()]` and `.SYNOPSIS`/`.PARAMETER` blocks to key public functions would improve maintainability and enable auto-generated docs. Impact: 2, Effort: L.

- [ ] **Add contribution-graph or streak visualization** -- Self-hosted (committed SVG) contribution visualization similar to Platane/snk or github-readme-stats streak. Would require a new GitHub Action step to generate the SVG from the contributions API. Lower priority because the current profile focuses on project catalog rather than activity metrics. Impact: 1, Effort: M.

## Research-Driven Additions (2026-06-10)


### P3 — accessibility / discoverability

- [ ] P3 — Add opt-in topic-apply mode with allowlist
  Why: GitHub Topics drive 99% of discovery searches. The sync report already tracks `metadataHygiene.missingTopics` with generated `topicHints`, but the policy is non-mutating. An opt-in apply mode with an explicit allowlist would close the discoverability gap for repos that haven't had topics set.
  Evidence: GitHub Topics documentation (max 20/repo, 50 chars, lowercase + hyphens); current `topicHintPolicy` states "does not mutate repositories"; `metadataHygiene.missingTopics` identifies 69 repos with missing topics; GitHub SEO research showing topic pages dominate discovery.
  Touches: `scripts/sync-profile.ps1` (add `-ApplyTopics` parameter with allowlist file/inline list, `gh api` topic mutation calls), `data/` (optional topic-allowlist file), `tests/sync-profile.Tests.ps1`
  Acceptance: `-ApplyTopics` with an allowlist applies generated topic hints to listed repos only; dry-run mode shows what would change; non-allowlisted repos are never mutated.
  Complexity: M


