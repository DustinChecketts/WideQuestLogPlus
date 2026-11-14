# WideQuestLogPlus AI development guidance

Follow the shared [StormCore engineering standards](https://github.com/DustinChecketts/StormCore/blob/main/AGENTS.md) and its standards documents. This addon is independently installable and must not depend on StormCore at runtime.

## Mandatory research-first workflow
1. Before unfamiliar features or bug fixes, search maintained WoW addons that solve the same or similar problem. Inspect their source code and Blizzard UI implementations when relevant; document the applicable APIs, compatibility constraints, and tradeoffs. Respect licenses and credit adaptations.
2. If no proven implementation exists, consult Blizzard UI source, API documentation, and reliable technical references. Separate facts from hypotheses; use minimal read-only diagnostics and targeted in-game tests to gather evidence. Do not cycle through speculative fixes.
3. Before substantial changes, define module responsibilities and preserve clear boundaries between compatibility, data, logic, UI, events, and options where useful. Prefer existing Blizzard APIs and simple reusable helpers over duplication or needless abstractions.
4. Review code for consistency, dead code, oversized modules, performance costs, and unintended client regressions. Run applicable StormCore lint, format, syntax, TOC, and packaging checks. Clearly distinguish offline checks from in-game verification.
5. Work on dedicated branches, preserve known-good behavior, and do not open PRs during iteration, merge, tag, or publish without maintainer approval. Report evidence, changes, checks, remaining uncertainty, and exact test instructions.

Priority: correctness and compatibility > architecture and maintainability > portfolio consistency > lightweight simplicity > optional visual polish.

## WideQuestLogPlus-specific rules
- Preserve Blizzard's native Quest Log on Classic Era and Anniversary TBC. On Forever, faithfully recreate the familiar Classic two-pane interface where the native frame is absent.
- Preserve the proven Forever right-edge artwork geometry, vertical-only resizing, quest selection, objective/reward behavior, and quest-log key handling.
- Keep Forever-specific rendering separate from Classic.lua. Centralize client/API capability decisions in Compat.lua; avoid over-sharing UI implementations.
- For Forever quest difficulty colors, prefer the native player-rated quest difficulty API when available; validate against Blizzard's native quest map list.
- Preserve SavedVariables, existing commands, addon metadata, and compatibility with all three clients. Test all affected clients before release.
- The active Forever work originated on prototype/forever-unified; do not merge or publish without approval.
- Keep AGENTS.md, CI, tests, and development documents out of CurseForge player ZIPs.
