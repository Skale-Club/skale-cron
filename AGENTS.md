# AGENTS.md - skale-cron

<!-- journal-protocol:v1 -->
## Journal (mandatory)

This app's history (what it does, how each part was built, decisions and releases) lives in its Notion Journal. It replaces the old GSD/PAUL planning flow; `.planning/` and `.paul/`, if present, are a read-only legacy archive.

- Journal hub: https://app.notion.com/p/411b7a68612181c0ab3ad992dbb895aa
- Journal Entries data source: collection://2f13e200-8c42-4a74-a019-987416231371
- Latest view: view://411b7a68-6121-816f-afe8-000cd6a3e73a
- Entry prefix: CRN
- Rules (they win on any conflict): https://app.notion.com/p/411b7a68612181b3ac36f4ce2b2c3850 (skill: `app-journal`)

**Start of session:** fetch the hub and read Identity and Current State; list the latest 20 entries (Notion query-data-sources, `rows` mode, sort `Date` descending, `limit` 20) and read only titles and summaries; open only the entries you need; never read the whole database. Cross-check with the code: the code is the fact.

**End of every task that changed code, behavior, infrastructure or a decision:**
1. Create ONE entry in the data source above (one per logical unit of work, not per commit): `Title` = `YYYY-MM-DD — <imperative summary>`, `Date`, `Type`, `Area`, `Status`, `Summary` (max 280 characters), `Agent`, `Model`, `Repo / Branch`, `Commits / PR`, `Tests` (what ran, or "Not run"), and `Decision ID` / `Decision Status` when a choice was made.
2. Body headings: Context · What changed · How it was built · Decisions and why · Tests and evidence · Not done / risks · Next.
3. If the app changed, rewrite the affected part of the hub's Current State. Read back what you wrote; never report a write you did not see.
4. Notion unavailable: append the full entry to `docs/journal/PENDING-NOTION.md` and tell the owner.

Journal records are in English. No secrets.
<!-- /journal-protocol -->
