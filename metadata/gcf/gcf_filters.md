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

## Known limitations

- Small corpus: GCF is young and few African adaptation projects have reached
  evaluation stage; expect growth on future scraper runs.
- No metadata CSV / document dates yet; the 7 evaluation docs still need a date
  check against the 2015–2025 window (all are recent by construction — GCF's
  first projects were approved 2015+).
