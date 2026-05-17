# Source Register

Research date: 2026-05-17

## Local Sources

| ID | Source | Use |
|---|---|---|
| L001 | `README.md` | Public profile structure, widgets, snippets, project sections, counts, release links. |
| L002 | Previous `ROADMAP.md` | Prior ideas and unsupported README-JS item. |
| L003 | `CHANGELOG.md` | Version history, prior one-liner repairs, private-repo removals, download-button audit. |
| L004 | `setup.ps1` | Bootstrap review. |
| L005 | `.gitignore` | Confirmed `CLAUDE.md` ignored. |
| L006 | `AGENTS.md` | Repo instruction pointer. |
| L007 | `CLAUDE.md` | Local project notes, version, gotchas, catalog standards. |
| L008 | `git log -10 --oneline --decorate` | Recent release context. |
| L009 | `git status --short --branch` | Branch state. |
| L010 | `git ls-files` | Tracked file set. |
| L011 | `git status --short --ignored` | Ignored instruction file state. |
| L012 | `gh auth status` | Verified GitHub CLI auth. |
| L013 | `gh repo view SysAdminDoc/SysAdminDoc --json ...` | Repo visibility, license, branch, topics, stars. |
| L014 | `gh repo list SysAdminDoc --limit 300 --visibility public --json ...` | Live public catalog metadata. |
| L015 | `gh repo list SysAdminDoc --limit 300 --visibility private --json ...` | Privacy-gate context. |
| L016 | README PowerShell regex audit | Counts, star drift, branch drift, release-link gaps. |
| L017 | `gh repo view SysAdminDoc/EspressoMonkey --json ...` | Rename/redirect evidence. |
| L018 | `C:/Users/--/.claude/CLAUDE.md` | Global behavior and privacy rules. |
| L019 | `C:/Users/--/CLAUDE.md` | Working protocol, git delivery, stack conventions. |
| L020 | Claude memory `MEMORY.md` | Shared memory index check. |
| L021 | `stack-powershell.md` | PowerShell conventions for `setup.ps1`. |
| L022 | `stack-web.md` | Static web/portfolio conventions. |

## External Sources

| ID | Source | URL | Use |
|---|---|---|---|
| E001 | GitHub profile README docs | https://docs.github.com/en/account-and-profile/how-tos/profile-customization/managing-your-profile-readme | Profile README prerequisites. |
| E002 | GitHub repository README docs | https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes | README behavior and relative links. |
| E003 | GitHub REST repos API | https://docs.github.com/en/rest/repos/repos | Repository metadata automation. |
| E004 | GitHub Actions events | https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows | Schedule behavior. |
| E005 | GitHub workflow syntax | https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax | Token permissions. |
| E006 | GitHub topics docs | https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics | Discoverability and topic limits. |
| E007 | GitHub Markup | https://github.com/github/markup | README sanitization and no inline JS. |
| E008 | GitHub Actions secure use | https://docs.github.com/en/actions/reference/security/secure-use | CODEOWNERS, Dependabot, Scorecard guidance. |
| E009 | Microsoft WinGet install docs | https://learn.microsoft.com/en-us/windows/package-manager/winget/install | Exact/silent/agreement install flags. |
| E010 | PowerShell execution policies | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies | `irm|iex` and zone behavior. |
| E011 | PowerShell Gallery getting started | https://learn.microsoft.com/en-us/powershell/gallery/getting-started | Inspect-before-install precedent. |
| E012 | Pagefind | https://pagefind.app/ | Static portfolio search. |
| E013 | Shields.io | https://shields.io/docs | Badge opportunities and risks. |
| E014 | awesome-lint | https://github.com/sindresorhus/awesome-lint | Awesome-list linting/CI pattern. |
| E015 | GitHub Profile README Generator | https://rahuldkjain.github.io/gh-profile-readme-generator/about/ | Competitor. |
| E016 | awesome-github-profile-readme | https://github.com/abhisheknaiidu/awesome-github-profile-readme | Competitor/pattern gallery. |
| E017 | awesome-sysadmin | https://github.com/awesome-foss/awesome-sysadmin | Sysadmin taxonomy. |
| E018 | All Contributors | https://all-contributors.github.io/ | Contributor recognition option. |
| E019 | OpenSSF Scorecard | https://github.com/ossf/scorecard | Security score option. |
| E020 | zizmor | https://docs.zizmor.sh/ | GitHub Actions security scanner. |
| E021 | readme-typing-svg | https://github.com/DenverCoder1/readme-typing-svg | Current widget dependency. |
| E022 | github-readme-stats | https://github.com/anuraghazra/github-readme-stats | Current widget dependency and self-hosting option. |
| E023 | skill-icons | https://github.com/tandpfun/skill-icons | Current widget dependency. |
