# CIF (Climate Investment Funds) — filters applied to this corpus

Scraper: `Script/AI_grey_litterature/R/cif.R`. Retrieval channel: **cif.org
directly** — the CIF corpus on Climate Project Explorer is effectively empty
(verified 2026-07-23: one Bangladesh proposal), so the fund's own Drupal site
is the source. Corpus created: 2026-07-23.

## 1. Retrieval (query-time)

| Aspect | Value |
|---|---|
| Enumeration | The sitemap index (`cif.org/sitemap.xml?page=1..6`, ~10,400 URLs) — the /knowledge listing page is a static "featured" view whose pager does not advance |
| Candidates | Document pages (`/knowledge-documents/{slug}`, `/documents/{slug}`) whose slug matches evaluation terms (evaluat, mid-term, completion, performance-review, learning-review, lessons-learned, impact-assessment) |
| Excluded upfront | The Evaluation & Learning Initiative's own admin papers: annual reports, work/business plans, presentations, concept notes, ToRs, workshop/meeting/session documents, joint-mission notes |
| PDFs | `cif.org/sites/cif_enc/files/knowledge-documents/{slug}.pdf` |

## 2. Filters in code

- **Document type from page title** (independent evaluation, mid-term/final
  evaluation, learning review, completion/performance, impact evaluation).
- **Geography, three-way**: `kept` = names an African country or
  Africa/Sahel; `out_of_scope_geo` = names ONLY a non-African CIF pilot
  country (Mexico, Brazil, India, Indonesia…); **`kept_global`** = no
  country named — CIF evaluations are typically program/portfolio-level
  (PPCR/FIP/SREP-wide) and cover African pilot countries *within* global
  scope, so these are kept and flagged.
- **Date**: page year (or year in the PDF name); known pre-2015 → `parked_old`.

## 3. Corpus (as of 2026-07-23)

- `Docs/evaluation_docs/` — **72 documents**: 19 African-specific + 57
  program-level (`kept_global`) minus 4 failed downloads.
- Catalogue `cif_metadata.csv`: 110 candidates — kept 19 / kept_global 57 /
  out_of_scope_geo 20 / parked_old 13 / parked 1.

## Known limitations

- Most CIF evaluation material is **program/portfolio-level** (multi-country
  syntheses) — like the AfDB cluster evaluations, these pose the
  multi-project extraction question; country-attributable content must be
  located within the documents.
- `kept_global` documents need a screening look: their Africa content varies
  from substantial (PPCR independent evaluation) to incidental.
- Older independent evaluations live on archive sites (cifevaluation.org,
  IEG, IADB) — not swept.
