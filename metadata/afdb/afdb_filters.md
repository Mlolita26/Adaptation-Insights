# AfDB — filters applied to this corpus

Scraper: `Script/AI_grey_litterature/R/afdb.R` (HTML scraping of www.afdb.org + idev.afdb.org, WAF session handling)
Metadata: `afdb_metadata.csv` (174 documents), `idev_taxonomy.csv` (IDEV facet IDs).
Corpus created: 2026-07-21.

## 1. Query-time filters (which listings were swept)

**www.afdb.org category listings** (evaluation-only categories, all pages):

| Category | Implied doc type |
|---|---|
| Project/Programme Completion Reports | PCR |
| Completion Report Reviews | PCREN (evaluation note) |
| Projects Performance Evaluation Reports | PPER |
| Evaluation Reports — Agriculture & Agro-industries | EVAL |

**IDEV faceted evaluation search** (field_category_doc facets):

| IDEV category (id) | |
|---|---|
| Project performance evaluation (74) | Project cluster evaluation (75) |
| Impact evaluation (80) | Evaluation report (185) |
| PCR & XSR Validation synthesis (186) | |

## 2. Post-query filters (applied in the scraper)

1. **Cross-host dedupe** (PDF filename, normalized title, URL): 4,401 → 1,712
2. **Document type**: PAR (appraisal/proposal), ESIA, IPR, ISR excluded.
   Untyped titles get the category-implied type only if a per-category
   confirmation regex matches (e.g. "completion report|pcr|rapport d'achèvement");
   otherwise they stay untyped. → 1,707
3. **Year window 2015–2025** (team decision 2026-07-17). Year precedence:
   listing publication date > year in PDF filename > IDEV dated folder path >
   year in title; unknown-year docs kept. → 1,021
4. **Relevance**: agriculture OR adaptation keyword in title (EN/FR/PT lists)
   **OR** agriculture sector letter in the AfDB project code
   (P-XX-**A**xx-NNN). Africa not required — Bank mandate. → 178
5. **One document per project** (best type by priority PPER/EER > EVAL/PCREN >
   PCR > MTR), keyed on project code, fallback normalized project name. → 174

Downloads: 174/174 PDF URLs resolved (PDFs are embedded in pdf.js viewer
iframes on afdb.org document pages), 173 unique PDFs validated and stored.

## 3. Corpus organisation

- `Docs/2015_2026/` — 123 typed evaluation docs (PCR 114, EVAL/IDEV 12* , PPER 1) — **in scope**
- `Docs/undated/` — 4 typed docs without a recoverable year
- `Docs/to_screen/` — 46 untyped docs from the evaluation categories: mixture of
  genuine French-titled reports and noise (procurement notices, feasibility
  studies) — needs manual screening

## Zotero / catalogue status

- No RIS / Zotero import yet — `afdb_metadata.csv` (174 docs) is ready to
  generate one; on the roadmap.

## Known limitations

- The 46 `to_screen` files carry `doc_type = NA` in the metadata — screen before use.
- Relevance rule keeps non-agriculture climate/infrastructure evaluations when
  titles contain adaptation keywords (e.g. resilience programmes) — same
  screening pass as other sources applies.
- Possible recall gain not yet swept: IDEV's search form has a sector facet
  (`Agriculture & Agro-industry`, id 106 in `idev_taxonomy.csv`) that could be
  added as a second sweep axis.
