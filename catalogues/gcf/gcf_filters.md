# GCF — filters applied to this corpus

Scraper: `Script/AI_grey_litterature/R/gcf.R` (Drupal AJAX scraping of greenclimate.fund)
Metadata: none yet — the scraper logged downloads but never wrote a catalogue CSV
(on the roadmap). Corpus organised: 2026-07-20.

## 1. Query-time filters (project search facets)

| Filter | Value |
|---|---|
| Project status | Approved (231) + Completed (445) |
| Theme | Adaptation (235) |
| Region | Africa (318) |
| Document types targeted | funding proposal, evaluation, completion |

## 2. Corpus organisation

- `Docs/evaluation_docs/` — 7 (4 evaluation reports, 2 project completion
  summaries, 1 project completion report) — **in scope**
- `Docs/proposal_stage/` — 11 approved funding proposals — **out of scope**
  (team decision 2026-07-17: proposals excluded)

## CPE/CPR API gap-fill (2026-07-25)

The Climate Project Explorer / CPR API sweep (see `af_filters.md` for the
channel) was run against the GCF corpus as a completeness check:
- 106 GCF project families found; 561 documents catalogued
  (`gcf_cpe_metadata.csv`), of which 186 Annual Performance Reports were
  reclassified as out-of-scope progress documents.
- True evaluation documents: 4 — 3 were **md5-identical duplicates** of
  files already in this corpus (validating both channels), and **1 was new**
  (FP049 final evaluation), now promoted. Corpus: **8 evaluation documents**.

## Zotero / catalogue status

- Items synced via the API pipeline (collections GCF/included etc.).

## Planned scraper changes (agreed 2026-07-21, not yet implemented)

- Drop `funding.proposal` from the document-type patterns — evaluation and
  completion documents only.
- Write the missing metadata catalogue CSV (the scraper currently only logs
  downloads), then generate the RIS.
- The GCF projects page filters are JavaScript-rendered (no scrapable sector
  facet found); with 7 documents, relevance is checked manually. GCF tags
  projects with "result areas" (e.g. *Health, food and water security*) —
  worth using if the corpus grows.

## Known limitations

- Small corpus: GCF is young and few African adaptation projects have reached
  evaluation stage; expect growth on future scraper runs.
- No document dates yet; the 7 evaluation docs still need a date check against
  the 2015–2025 window (all are recent by construction — GCF's first projects
  were approved 2015+).
