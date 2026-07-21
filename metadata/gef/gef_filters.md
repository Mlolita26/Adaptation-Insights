# GEF — filters applied to this corpus

Scraper: `Script/AI_grey_litterature/R/gef.R` (HTML scraping of thegef.org project database)
Metadata: `gef_all_documents.csv` (per-document catalogue, no dates — see below),
`gef_evaluation_dates.csv` (recovered year + method per evaluation file).
Last corpus update: 2026-07-20.

## 1. Query-time filters (project database facets)

| Filter | Value |
|---|---|
| Focal area | Climate Change |
| Countries | each African country (project_country facet) |
| Project approval year | >= 2000 |
| Document types targeted on project pages | terminal evaluation, mid-term review, PIR, evaluation, completion report, CEO endorsement, project document, PIF |

Note: **no agriculture filter at scrape time** — the corpus is climate-change
projects broadly (includes e.g. enabling-activity/reporting projects). An
agriculture relevance screen is still pending for GEF.

## 2. Corpus organisation (2026-07-20, after download)

Type split (by filename doc type; the 70 "unknown" files were verified against
metadata titles to be proposal/administrative docs):

- `Docs/evaluation_docs/` — 193 (TEs 123, MTRs 42, PIRs 9, evaluations 6, completion reports 3, + variants) — **candidate in-scope set**
- `Docs/proposal_stage/` — 615 (CEO endorsements, project documents, PIFs, review sheets, admin letters) — **out of scope** (team decision 2026-07-17: proposals excluded)

Date split of evaluation_docs (GEF publishes no document dates anywhere — dates
recovered from the files by `R/gef_doc_dates.R`):

- `evaluation_docs/2015_2026/` — 142 (**in scope**)
- `evaluation_docs/pre_2015/` — 15
- `evaluation_docs/undated/` — 36 (legacy doc/xls, archives, 24 dateless PDFs)

## Date-recovery rules (order of trust)

1. Month-name dates (EN/FR/PT/ES) on the first 8 PDF pages / docx body — latest year wins
2. 4-digit year in the filename (PIRs)
3. OOXML/OLE file-creation metadata (docx/xlsx/doc/xls)

Deliberately rejected: PDF creation metadata (GEF CDN regenerated files → false
2025 cluster) and numeric date formats like 06/2026 (fact-sheet tables list
*planned* closing dates). Template-file dates voided where implausible
(gef_id >= 4500 with year < 2013). Evidence per file in `gef_evaluation_dates.csv`.
