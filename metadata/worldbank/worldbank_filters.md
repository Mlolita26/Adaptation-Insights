# World Bank — filters applied to this corpus

Scraper: `Script/AI_grey_litterature/R/worldbank.R` (REST API: search.worldbank.org/api/v3/wds)
Metadata: `worldbank_metadata.csv` (354 documents). Last corpus update: 2026-07-20.

## 1. Query-time filters (what was requested from the API)

| Filter | Value |
|---|---|
| Document types (exact) | Implementation Completion and Results Report; Implementation Completion Report; Project Performance Assessment Review |
| Countries | each of the 54 African Union member states (one query per doc type × country) |
| Keyword sweep (2nd strategy) | 7 queries, e.g. "agriculture adaptation climate Africa", "climate smart agriculture Africa", "livestock resilience Africa drought" |

Evaluation-type documents only by construction — appraisal documents (PADs) and
proposals were never requested.

## 2. Post-query filters (applied in the scraper)

- Deduplication by API document id.
- Relevance screen on title+abstract text: must contain an **Africa term** AND
  (an **agriculture** keyword OR an **adaptation** keyword). Keyword lists (EN/FR/PT)
  in `R/00_config.R`.

## 3. Corpus organisation (2026-07-20, after download)

- Split by `doc_date` (ICR publication year, also at the end of each filename):
  - `Docs/2015_2026/` — 204 docs (**in scope**; team decision 2026-07-17: 2015–2025 to align with GCA)
  - `Docs/pre_2015/` — 115 docs (2002–2014, parked)
- 14 originally-failed downloads recovered via documents1.worldbank.org + browser
  user-agent (plain documents.worldbank.org returns 403 to scripts).
- 124 files renamed to short names (Windows 260-char path limit); map in
  `renamed_long_paths.csv`.

## Known limitations

- The keyword relevance screen admits some off-topic operations (budget-support
  DPOs/PRSCs, health/refugee projects). A dedicated relevance screening pass is
  planned before extraction.
- 32 pre-2015 documents from the metadata were never successfully downloaded
  (broken links); all in-scope (2015+) documents are complete: 204/204.
