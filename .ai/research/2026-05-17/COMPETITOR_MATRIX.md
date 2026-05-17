# Competitor Matrix

Research date: 2026-05-17

## Positioning

`SysAdminDoc` should not compete as a generic profile README generator. Its defensible position is a live, trustworthy, sysadmin-oriented public project catalog plus a richer portfolio site.

| Project / Product | Source | Strength | Gap | Lesson |
|---|---|---|---|---|
| GitHub profile README | GitHub Docs | Native profile placement with no hosting. | Static, sanitized Markdown only. | Keep README static, accurate, and lightweight. |
| GitHub Profile README Generator | https://rahuldkjain.github.io/gh-profile-readme-generator/about/ | Form-based profile creation and common widgets. | Not designed for 170+ repo catalogs. | Do not chase generic templates; generate catalog truth. |
| awesome-github-profile-readme | https://github.com/abhisheknaiidu/awesome-github-profile-readme | Pattern gallery for dynamic, minimal, badge, and action-driven profiles. | Inspiration only, not a maintenance system. | Use for taste/pattern awareness. |
| github-readme-stats | https://github.com/anuraghazra/github-readme-stats | Dynamic stats cards and self-hosting option. | External widget dependency and caching/rate-limit risk. | Keep stats decorative; do not rely on widgets for catalog data. |
| readme-typing-svg | https://github.com/DenverCoder1/readme-typing-svg | Simple customizable SVG hero effect. | External dependency. | Acceptable if generator validates encoded text and width. |
| skill-icons | https://github.com/tandpfun/skill-icons | Compact skill icon row. | External dependency. | Keep decorative and low-stakes. |
| awesome-lint | https://github.com/sindresorhus/awesome-lint | CI-backed markdown/list hygiene. | Rules may not fit a profile README directly. | Borrow validation philosophy; write custom checks. |
| awesome-sysadmin | https://github.com/awesome-foss/awesome-sysadmin | Deep taxonomy and table of contents for sysadmin tools. | Huge curated list, not personal portfolio. | Use taxonomy ideas and submission targets. |
| Pagefind | https://pagefind.app/ | Static search and filtering for built sites. | Cannot run inside GitHub README. | Use for `sysadmindoc.github.io`. |
| Shields.io | https://shields.io/docs | Standard badge ecosystem. | Badge overload reduces signal. | Use only high-value generated summary badges. |
| All Contributors | https://all-contributors.github.io/ | Automates contributor recognition. | Most repos appear personal/single-maintainer. | Defer until public collaboration grows. |
| OpenSSF Scorecard | https://github.com/ossf/scorecard | Supply-chain security scoring and badge. | More useful once workflows exist. | Add after profile automation is in place. |
| zizmor | https://docs.zizmor.sh/ | Static analysis for GitHub Actions. | No workflows exist yet. | Add when `.github/workflows` is introduced. |

## Takeaways

- README is the catalog summary, not the interactive app.
- Portfolio site is the right place for search, filters, screenshots, and richer ranking.
- Generated metadata is the core differentiator.
- Privacy gates are as important as freshness for this account.
