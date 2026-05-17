# Prioritization Matrix

Research date: 2026-05-17

Scoring: `(Impact + Urgency + Risk reduction) - Effort`, each dimension 1-5.

| ID | Candidate | Impact | Urgency | Effort | Risk Reduction | Score | Tier |
|---|---|---:|---:|---:|---:|---:|---|
| P001 | Canonical catalog file | 5 | 5 | 3 | 5 | 12 | P0 |
| P002 | `scripts/sync-profile.ps1 -Check` | 5 | 5 | 4 | 5 | 11 | P0 |
| P003 | Privacy and sensitive-domain gate | 5 | 5 | 2 | 5 | 13 | P0 |
| P004 | Rename/deleted repo detection | 4 | 4 | 2 | 4 | 10 | P0 |
| P005 | Generated v4.8.0 README refresh | 5 | 4 | 3 | 4 | 10 | P0 |
| P006 | Release/download taxonomy | 4 | 4 | 3 | 3 | 8 | P1 |
| P007 | Check-only profile-sync workflow | 4 | 3 | 3 | 4 | 8 | P1 |
| P008 | Workflow hardening | 4 | 3 | 3 | 5 | 9 | P1 |
| P009 | Topic coverage report | 3 | 3 | 2 | 2 | 6 | P1 |
| P010 | Empty description report | 3 | 3 | 1 | 2 | 7 | P1 |
| P011 | Portfolio `projects.json` export | 5 | 3 | 4 | 3 | 7 | P1 |
| P012 | Pagefind portfolio search | 4 | 3 | 3 | 2 | 6 | P1 |
| P013 | setup.ps1 inspect-before-run docs | 3 | 3 | 1 | 3 | 8 | P1 |
| P014 | setup.ps1 `-CheckOnly` mode | 2 | 2 | 2 | 2 | 4 | P2 |
| P015 | OpenSSF Scorecard | 3 | 2 | 2 | 4 | 7 | P2 after workflows |
| P016 | Awesome-list submissions | 3 | 2 | 3 | 1 | 3 | P2 after metadata cleanup |
| P017 | All Contributors | 2 | 1 | 2 | 1 | 2 | P3 |

## Recommended Order

1. `data/profile-catalog.json`
2. `scripts/sync-profile.ps1 -Check`
3. Privacy and sensitive-domain gates
4. Rename/deleted repo detection
5. Release/download taxonomy
6. Generated README v4.8.0
7. Check-only GitHub Actions workflow
8. Workflow hardening
9. Portfolio data export
10. Portfolio search/filter
