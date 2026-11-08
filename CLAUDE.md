# CLAUDE.md - skale-cron

Read `AGENTS.md` first; everything there applies to Claude.

<!-- journal-protocol:v1 -->
## Journal (mandatory)

This app's history (what it does, how each part was built, decisions and releases) lives in its Notion Journal. It replaces the old GSD/PAUL planning flow; `.planning/` and `.paul/`, if present, are a read-only legacy archive.

- Journal hub: https://app.notion.com/p/411b7a68612181c0ab3ad992dbb895aa
- Journal Entries data source: collection://2f13e200-8c42-4a74-a019-987416231371
- Latest view: view://411b7a68-6121-816f-afe8-000cd6a3e73a
- Entry prefix: CRN
- Rules (they win on any conflict): https://app.notion.com/p/411b7a68612181b3ac36f4ce2b2c3850 (skill: `app-journal`)

**Start of session:** fetch the hub and read Identity and Current State; list the latest 20 entries with Notion query-data-sources in `view` mode on the Latest view above (`page_size` 20; view mode has no plan quota) and read only titles and summaries; use `rows` mode with a filter only to narrow down (it has a plan quota); if a read fails, say so and continue from the code, never guess journal content; open only the entries you need; never read the whole database. Cross-check with the code: the code is the fact.

**End of every task that changed code, behavior, infrastructure or a decision:**
1. Create ONE entry in the data source above (one per logical unit of work, not per commit): `Title` = `YYYY-MM-DD — <imperative summary>`, `date:Date:start` (YYYY-MM-DD, with `date:Date:is_datetime` = 0), `Type`, `Area` (JSON array of existing options), `Status`, `Summary` (max 280 characters), `Agent`, `Model`, `Repo / Branch`, `Commits / PR`, `Tests` (what ran, or "Not run"), and `Decision ID` / `Decision Status` when a choice was made.
2. Body headings: Context · What changed · How it was built · Decisions and why · Tests and evidence · Not done / risks · Next.
3. If the app changed, rewrite the affected part of the hub's Current State. Read back what you wrote; never report a write you did not see.
4. Notion unavailable: append the full entry to `docs/journal/PENDING-NOTION.md` and tell the owner.

Journal records are in English. No secrets.
<!-- /journal-protocol -->

<!-- universal-rules:v1 -->
## Universal rules (read first)

Before working, read the owner's universal agent rules: `$HOME/Dev/skaleclub-apps/agents/RULES.md`
(GitHub: https://github.com/Skale-Club/skaleclub-apps/blob/main/agents/RULES.md).
They cover model routing (the session model plans and validates, cheaper models execute), machine awareness (Surface = light mode, `machine-check.ps1`), delivery estimates with no silent stalls, and the database, login, git and language decisions. Keep it light: they help, never block.
This file adds only what is specific to this repository.
<!-- /universal-rules -->

