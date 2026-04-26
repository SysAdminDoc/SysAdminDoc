# SysAdminDoc Profile Roadmap

Roadmap for the SysAdminDoc GitHub profile README and companion portfolio page (`sysadmindoc.github.io`). Goal: keep the profile current, discoverable, and reflective of 170+ active repos.

## Planned Features

### Content & layout
- Star-count automation (GitHub Actions nightly cron updates `&#11088; N` badges from live API)
- Auto-regenerate repo tables from the GitHub API with frontmatter-driven category tags
- Featured Projects carousel with live screenshots (pulled from each repo's `screenshot.png`)
- "New this week" strip showing repos tagged in the last 7 days
- Top-commit-velocity strip for repos in active development

### Navigation
- TOC jump-links per category (anchor nav at top)
- Search box (client-side, fuzzy across repo names + descriptions) via a tiny inline JS snippet
- Filter chips (language, platform, status) driven by JS + data attributes
- Permalink badges per repo for easy linking in other READMEs

### Discoverability
- Link to the curated portfolio site with per-project deep pages
- Submit to Awesome lists (awesome-powershell, awesome-userscripts, awesome-android, awesome-stylus)
- Canonical LinkTree-style landing page mirroring the profile for social bios
- Pinned repo strategy revisit every quarter (rotate to currently-active projects)

### Metrics
- Per-language stars + downloads rollup
- Weekly release activity chart (from Releases API)
- Contributors + community PR counter for repos that accept PRs
- Total lines of code / total commits milestone markers

### Tooling
- One script (`scripts/sync-profile.ps1`) that:
  - Regenerates README stars/tables from the GitHub API
  - Updates the featured-project list based on star velocity
  - Commits if changed, opens PR if gated
- CI workflow that runs the sync nightly at 05:00 UTC and on-demand via `workflow_dispatch`
- Lint step that checks every mentioned repo URL responds 200

## Competitive Research

- **Awesome-lists ecosystem** - structured, badged, categorized; this profile already mirrors the feel. Add the "Awesome-list" GitHub topic tag to the main repos so they surface in cross-awesome aggregators.
- **simple-icons/skill-icons** - already used; keep icons current and expand set if new languages adopted (e.g. Zig, Rust).
- **Github-readme-stats / streak-stats** - already embedded; consider caching via the user's own server if the public instance rate-limits.
- **Standalone portfolio pages** (like hyperscript / ben awad / theo) - typography-heavy, project-first pages do better than wall-of-badges. The separate `sysadmindoc.github.io` can lean into storytelling while the profile README stays catalog-style.

## Nice-to-Haves

- GraphQL-powered "currently coding" card (latest commit timestamp + repo)
- RSS feed of profile activity for aggregation elsewhere
- Embedded Spotify "now playing" (Slunder artist link) widget
- Link to VaultBox/NeonNote release feeds as small badges
- Optional dark/light theme toggle for the portfolio site (default dark per CLAUDE.md)
- Dedicated `/press-kit` page on the portfolio site with logos, taglines, links
- Automated "retirement" marker that archives and badges stale repos (>6 months inactive per CLAUDE.md)

## Open-Source Research (Round 2)

### Related OSS Projects
- https://github.com/awesome-foss/awesome-sysadmin — canonical curated list of FOSS sysadmin tools; inspiration for portfolio categorization
- https://github.com/kahun/awesome-sysadmin — alternative taxonomy (build, configuration, monitoring, service-discovery)
- https://github.com/TemporalAgent7/awesome-windows-privacy — Windows-specific tooling curation style
- https://github.com/rickstaa/awesome-adsb — niche-focused awesome list (good "awesome-sysadmindoc" shape)
- https://github.com/abhisheknaiidu/awesome-github-profile-readme — dynamic profile READMEs, SVG typing, stat cards
- https://github.com/anuraghazra/github-readme-stats — pluggable profile cards (stars, langs, streaks)
- https://github.com/DenverCoder1/readme-typing-svg — the typing SVG already in use; worth upstream-watching for new params
- https://github.com/topics/sysadmin — live browse of what's trending in the space

### Features to Borrow
- Category-taxonomy JSON driving the portfolio site (awesome-foss/awesome-sysadmin pattern) so adding a repo auto-places it on the site
- Auto-generated "awesome-SysAdminDoc" README sourced from the same repo metadata (badges, tagline, lang, stars) — single source of truth
- Stale-repo detection via GitHub API `pushed_at` with automatic "archived" badge (borrowed from awesome-list maintenance scripts)
- Deep-link search across all 170+ repos (Pagefind static index) — borrow from awesome-local-llm style static search
- Per-repo screenshot lightbox via `github-readme-stats`-style SVG embeds to avoid heavy images
- Tag cloud driven by repo topics (GitHub Topics API) for portfolio filtering — awesome-list convention
- RSS feed of new releases across the portfolio (one-click subscribe for followers) — awesome-foss pattern
- README-diff bot that flags version-string drift across badges, CHANGELOG, and manifest (borrow `readme-typing-svg` CI pattern)

### Patterns & Architectures Worth Studying
- Awesome-list meta-format: single markdown with strict heading levels + CI linter (`awesome-lint`) — enforces link health, dedup, ordering
- Profile README composition: multiple SVG widgets stitched together (typing + stats + streak + trophies) with external renderers — zero client JS
- Topic-driven discoverability: GitHub Topics as both filter axis and SEO signal — every repo gets 5-10 canonical topics
- Shields.io dynamic badges with JSON endpoints (self-hosted on GitHub Pages) for custom metrics (build count, last-release age)
- `gh-pages` + Pagefind for static full-text search without a backend — ideal for a 170-repo portfolio
