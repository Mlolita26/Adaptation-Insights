# Adaptation Fund — filters applied to this corpus

Scraper: `Script/AI_grey_litterature/R/af.R`. Retrieval channel: the **public
Climate Policy Radar REST API** (`api.climatepolicyradar.org`) that powers
Climate Project Explorer — the Multilateral Climate Funds' joint document
platform. Corpus created: 2026-07-23.

## 1. Retrieval (query-time)

| Aspect | Value |
|---|---|
| Channel | CPR API: `GET /search/documents` (top-100 per query, no deeper pagination) + `GET /families/{import_id}` (project + all its documents, with direct PDF URLs) |
| Enumeration | Country-targeted query templates ("{country} final evaluation report", "…mid-term evaluation", "…project completion evaluation") × the AFRICA_COUNTRIES_EN list — a country's fund documents rank at the top of its own query; family IDs taken from the `member_of` relation |
| Corpus restriction | Families checked against `MCF.corpus.AF.n0000` (project corpus); `.Guidance` families (policies) skipped |
| PDFs | Preferred from the CPR CDN (`cdn.climatepolicyradar.org/navigator/…`), fallback to the fund's own store (`fifspubprd.azureedge.net/afdocuments/…`) |

Rejected routes (verified): the token-gated `POST /api/v1/searches` (origin-bound
JWT, not obtainable) and CPR's HuggingFace dataset (contains no MCF documents).

## 2. Filters in code

- **Geography**: family geographies must intersect the 54 African ISO3 codes
  → non-African families' documents recorded as `out_of_scope_geo`.
- **Document type from TITLE** (the API's document_type field is null):
  kept = final/mid-term/terminal evaluation, performance/completion report;
  parked = project documents, proposals, inception reports, gender plans.
- **Date**: only the FAMILY year (project approval era) is known at scrape
  time; families >10 years before the 2015 scope floor are parked as
  `parked_old`. **Document-level dates need the PDF date-recovery pass**
  (same method as GEF) before the strict 2015–2025 cut — evaluations are
  published years after project approval, so family year underestimates.

## 3. Corpus (as of 2026-07-25)

- `Docs/evaluation_docs/` — **~34 evaluation documents** (final evaluations
  13, mid-term evaluations 14, completion reports 8 — 1 failed download) of
  African AF projects.
- `Docs/progress_reports/` — 4 (annual) Performance Reports, parked:
  progress documents are out of scope as standalone sources.
- Catalogue `af_metadata.csv`: 340 documents across 131 African + non-African
  project families — kept 35 / parked_progress 5 / parked 92 (proposal-stage,
  not downloaded) / out_of_scope_geo 208.

## Known limitations

- CPE is an aggregator: adaptation-fund.org remains authoritative; its
  project pages also carry Performance Progress Reports and DOCX evaluations
  not always mirrored — a completeness pass against the AF site is a
  possible follow-up.
- Document dates pending PDF date recovery (filenames carry the family year).
- Enumeration relies on relevance-ranked search (no corpus listing endpoint);
  coverage was boosted by cross-country spillover but is not provably total.
