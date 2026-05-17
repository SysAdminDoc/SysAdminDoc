# Dataset, Model, And Integration Review

Research date: 2026-05-17

## Applicability

This project does not need an ML model for its core roadmap. It needs structured metadata and deterministic generation.

## Data Sources

| Source | Fields | Use |
|---|---|---|
| GitHub repo metadata | name, URL, visibility, default branch, description, topics, stars, forks, language, pushedAt, archived status | README generation, privacy gates, sorting, topic reports. |
| GitHub releases | latest release, tag, publish date, assets | Download buttons and release views. |
| Raw GitHub URLs | userscript files, setup script | Install-link validation. |
| Local catalog file | category, inclusion, entrypoint, install kind, overrides, sensitive-domain flags | Human curation. |
| Portfolio site | static HTML and generated JSON | Rich browsing and search. |
| Security tools | Scorecard, zizmor output | Future trust signals. |

## Proposed Catalog Fields

- `repo`
- `canonicalRepo`
- `aliases`
- `category`
- `includeInReadme`
- `includeInPortfolio`
- `omitReason`
- `descriptionOverride`
- `branch`
- `entrypoint`
- `installKind`
- `downloadKind`
- `releaseAssetPatterns`
- `featured`
- `currentlyBuilding`
- `platforms`
- `languages`
- `topicHints`
- `sensitiveDomain`
- `privateReason`
- `notes`

## Optional Model Use

Potential later uses:

- Suggest short descriptions from repo READMEs.
- Suggest topics from repo name, language, and README.
- Semantic search on the portfolio if Pagefind is insufficient.

Guardrails:

- Human review before publishing descriptions or topics.
- No model-driven public/private decisions.
- No inferred private-domain details in public outputs.
- Keep README generation deterministic.

## Evaluation Metrics

- Active public repos counted.
- Listed README repos counted.
- Omitted public repos counted with reason.
- Private README links: zero.
- Sensitive medical-imaging public links: zero unless allowlisted.
- Star drift: zero after generation.
- Branch mismatches: zero.
- Release-link gaps for qualifying artifacts: zero.
- Missing topics tracked and reduced.
- Empty descriptions tracked and reduced.
