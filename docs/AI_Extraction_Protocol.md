# AI-Assisted Data Extraction from Project Evaluation Documents

**Protocol for corpus construction, structured extraction, and validation**

Adaptation Insights | WP2 Evidence Synthesis — Grey Literature
**Draft v0.1 — July 2026**

> Canonical version: GitHub `Mlolita26/Adaptation-Insights` →
> `docs/AI_Extraction_Protocol.md`.

---

## 1. Background and rationale

Evidence on what climate adaptation has been implemented in Africa's food
and agriculture sector — and with what results — sits scattered across the
grey literature of development institutions: implementation completion
reports, terminal evaluations, performance evaluations, or other grey
literature documents. Existing syntheses rely almost exclusively on
peer-reviewed literature, leaving a recognised evidence gap (see the
review-methods protocol, `AIs_WP3_EvidenceSynthesis_GreyLit.docx`, and
*Beyond Academia — A Case for Reviews of Gray Literature*, in `Resources\`).

The WP2 grey-literature evidence synthesis answers this by building a
structured database — *a stocktake of what has been implemented, by whom,
where, and with what effects* — from project evaluation documents. Manual
extraction across hundreds of documents is too slow; a living LLM-assisted
pipeline operationalises the extraction template at scale, under the
validation and quality regime this protocol defines.

## 2. Objectives

1. **Build the project document library.** Assemble a screened corpus of
   project evaluation documents from institutional sources: retrieve
   documents programmatically (scrapers per source website) or manually
   where a source cannot be scraped; then **screen** every document against
   the scope rules and **classify** it into a corpus state
   (`in_scope` / `to_screen` / `screened_out` — Section 3). The library is
   stored on OneDrive, catalogued in Zotero, and documented per source.
2. **Populate the working database.** For every in-scope document, produce
   validated records in the extraction template: one project-level record
   plus location-specific records in long format (one row per
   location × intervention × result).
3. **Record what could not be extracted.** Fields with no supporting
   evidence in the document are recorded as explicit no-extraction values
   with a reason — never guessed. The pattern of gaps (e.g. results reported
   without baselines, missing locations) is itself a deliverable that feeds
   the evidence-gap analysis.
4. **Stress-test the template.** Every extraction run is also a test of the
   template: values that do not fit any controlled-vocabulary option, fields
   that are systematically empty, and vocabulary ambiguities are logged as
   candidate template revisions for the template owner.

## 3. Inputs and corpus

### 3.1 Pilot corpus (as of now)

The current corpus is a **pilot**: four sources chosen because their document
repositories are programmatically retrievable, providing volume quickly while
the method is validated. Corpus construction is fully documented per source
in `metadata/{source}/{source}_filters.md` (query filters, post-filters,
screening rules, known limitations).

Scope rules applied to all sources (team decision 2026-07-17):
**evaluation-type documents only** (completion reports, terminal/mid-term
evaluations, performance evaluations — proposals excluded because they do
not describe what was actually implemented); **document date 2015–2025**
(GCA alignment); African agriculture/adaptation relevance. The strict
agriculture × adaptation intersection is deliberately **not** enforced by
the coarse filters — documents with evidence on either angle are kept
(recall-first: stricter query-time filters were tested and silently lose
in-scope projects), and the final relevance decision falls to screening and
to extraction itself.

The master table on the following page summarises, per source: what is in
scope, which filters run on the source's website/API versus in our code,
what was screened out and why, and why the remaining `to_screen` documents
cannot be decided automatically.

**Eligibility for extraction:** `in_scope` documents only. `to_screen`
documents must first pass the screening step (Section 7, Phase 1):
deterministic rules first (e.g. WB sector codes from the projects API, GEF
adaptation-fund membership), one batched LLM screen for the remainder, human
adjudication of disagreements — verdicts recorded per source; nothing is
silently discarded. `screened_out` and `pre_2015` documents are parked,
never deleted.

```{=openxml}
<w:p><w:pPr><w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/><w:cols w:space="708"/></w:sectPr></w:pPr></w:p>
```

**Master corpus and filter table (pilot sources, as of now)**

| Source | In scope | Filters on the website / API (query time) | Filters in code (after retrieval) | Screened out — count and reasons | To screen — count and why uncertain |
|:-----|:------|:------------------------|:------------------------|:-----------------------|:-----------------------|
| World Bank | 276 files (≈275 projects) | Evaluation doc types only (ICR, ICR Report, PPAR); each African country + regional groupings ("Africa", "Eastern Africa", "World") | Date ≥ 2015; country field must be African; keep if WB's own topic classification includes *Agriculture* OR title carries agriculture/adaptation keywords; budget-support instruments excluded | 43 excluded: 17 budget-support DPOs/PRSCs (policy lending — nothing implemented), 4 non-African (Yemen/Lebanon, had entered via abstract mentions of "Africa"), ~22 with no agriculture/adaptation signal in topics, title, or abstract (statistics, disease surveillance, education, public-sector ICRs). +115 pre-2015 parked | 48 on disk (+428 catalogued, not downloaded): **abstract-only evidence** — not WB-classified as Agriculture, no title keywords; mixes genuine borderline projects (watershed, land administration, rural infrastructure) with false positives whose abstracts mention "resilience"/"drought" in passing. Content check needed |
| GEF | 142 | Climate Change focal area (adaptation-side selection, but includes mitigation); African countries; projects approved ≥ 2000 | Evaluation-type docs kept, proposal-stage parked; document year recovered from the files (site publishes no dates), 2015–2025 kept. **No agriculture filter yet** — planned via LDCF/SCCF adaptation-fund membership + content screen | 615 proposal-stage (CEO endorsements, project documents, PIFs, review sheets — describe intentions, not implementation); 15 pre-2015 parked | 36 undated: uncertainty is the **date**, not the theme — no publication year recoverable (legacy Word/Excel formats, scanned annexes), so the 2015–2025 rule cannot be applied yet |
| GCF | 7 | Adaptation theme + Africa region + approved/completed status | Evaluation/completion documents kept, funding proposals parked | 11 approved funding proposals (proposal-stage) | — |
| AfDB | 123 | Evaluation-only document categories (completion reports, completion report reviews, PPERs, agriculture evaluation reports) + IDEV evaluation search facets | Cross-host dedupe; date 2015–2025 (listing date → filename → title); **agriculture** via title keywords OR the sector letter embedded in AfDB project codes (P-XX-**A**xx-…); appraisal (PAR), ESIA and progress reports excluded; one best document per project | Appraisal/progress types and administrative noise excluded at scraper level (4,401 raw → 174 kept); 4 undated parked | 46 untyped: titles carry **no document-type marker** — cannot tell from metadata whether they are genuine evaluation reports (several French-titled completion reports) or noise (procurement notices, feasibility studies); sampling confirmed a mixture |
| **Total** | **~548** | | | | **~94 on disk (+428 catalogued)** |

```{=openxml}
<w:p><w:pPr><w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="708" w:footer="708" w:gutter="0"/><w:cols w:space="708"/></w:sectPr></w:pPr></w:p>
```

### 3.2 Source extension roadmap

The pilot does not bound the review. The WP3 protocol's source universe
(multilateral development banks, UN agencies — IFAD, FAO, UNDP —, the
Adaptation Fund, African government agencies, INGOs and consortia, knowledge
portals, IEO/IEG evaluation portals) remains the identification strategy for
extension. Next candidates per the pipeline roadmap: IFAD, Adaptation Fund,
FAO, UNDP. Sources that cannot be scraped join through **manual download**
into the same folder structure and the same screening states.

### 3.3 Source onboarding procedure

Every new source joins by the same path (so the extraction stage never needs
redesign):

1. **Retrieval** — scraper following the repo pattern (`R/{source}.R`; see
   the `new-scraper` checklist), or manual download where scraping is not
   feasible — with filters as close to the scope as the source allows.
2. **Filters documentation** — `{source}_filters.md`: query filters,
   post-filters, screening rule, known limitations.
3. **Screening states** — documents land as
   `in_scope` / `to_screen` / `screened_out` with recorded evidence.
4. **Catalogue** — metadata CSV in `List\`, mirrored to GitHub
   (`R/sync_metadata.R`), records pushed to Zotero.
5. **Field-applicability profile** — a row per document type in the
   Section 6 table, based on a structure scan of sample documents.
6. **Capped extraction validation** — a small extraction batch reviewed
   against Section 8 metrics before the source is scaled.

### 3.4 Other inputs

- **Template**: working database **v02** (pinned; extractions declare the
  template version they follow). The refined template (long format, tagging
  columns removed, provenance added) supersedes v02 on release and triggers
  a schema regeneration (Section 7, Phase 2).
- **Keyword taxonomy**: the live keyword file
  (`Keywords_implementation_updated_032026.xlsx`, SharePoint) informs
  screening rules and vocabulary synonyms; a local copy of the earlier
  version sits in `Evidence Extraction\`.
- **Gold standard**: P001–P010 hand-extracted records in template v02;
  source documents under `Data\Docs\Selection_mixed stakeholders\`.

## 4. Data management and infrastructure

Three pillars, each with a single job:

| Pillar | Location | Holds | Sync |
|---|---|---|---|
| **OneDrive** | `WP2_Evidence Synthesis\Grey Literature\Data\Project_doc\{source}\` | The **documents** (canonical store). Folder semantics: `Docs\2015_2026` (or `evaluation_docs\2015_2026`) = in-scope working set; `to_screen\`, `screened_out\`, `pre_2015\`, `proposal_stage\` = parked states; `List\` = per-source metadata, filters docs, screening evidence | Manual promotion from scraper inbox |
| **Zotero** | Shared group library *(to be created; API key pending)* | The **catalogue**: one record per corpus document with metadata, source URL, and a link to the OneDrive PDF. Team-browsable; duplicate detection via source-ID tags | RIS import now; automated idempotent push via `R/zotero_upload.R` once the group library exists |
| **GitHub** | `github.com/Mlolita26/Adaptation-Insights` | Everything **programmatic**: scrapers, screening/extraction code, metadata mirrors (`metadata/{source}/`), filters docs, this protocol. No PDFs, no secrets (`.Renviron` gitignored) | `R/sync_metadata.R` copies `List\` → `metadata/`; commit + push |

**Extraction outputs** are written as versioned files (per batch, stamped
with template/prompt/model versions — Annex A) to a dedicated output area;
they **never overwrite** the hand-curated working database. Merging into the
database is a reviewed step (Section 7, Phase 6).

**Conventions:** file names short (Windows 260-character path limit — keep
full paths ≤ 240); document filenames carry source, project code, document
type, and year; every catalogue row keys on the source's document ID.

## 5. Extraction target: the data model

The template (v02 `readme` sheet is the authoritative data dictionary — every
field has a description, options, examples from P001, and extraction
instructions) defines two linked tables:

**`project_data_general`** — one record per project: identity
(`project_code`, `project_title`, `project_lead`), years
(publication/start/closure — *actual*, not planned), `project_scale`,
location count/notes, project rationale (≤50 words), target beneficiary,
up to three headline results (value + metric + unit), budget/disbursed/
currency, funding mechanism, funder/implementor (actor codes),
`document_type`, `resource_id`, `evidence_depth`, `project_id`, links.

**`project_data_location-specific`** — long format, one record per
location × intervention × result: location code, `sector` +
`subsector_stated`, `intervention_type` + `intervention_stated`, rationale
(`rationale_level`/`_type`/`_subtype` + `rationale_stated`),
`target_beneficiary`, result (`result_level`/`result_type`/`result_value`/
`result_metric`/`result_unit`/`result_qual` + `result_stated`), evidence
(`evidence_type`/`evidence_subtype` + `evidence_stated`), notes,
`evidence_depth`, resource link.

Key rules the pipeline enforces:

- **Coded + stated pairs.** Nearly every coded field pairs with a `_stated`
  field carrying the verbatim source text. Under the provenance requirement,
  each `_stated` value also carries its **page/table reference**.
- **Controlled vocabularies** (v02 `lists` sheet, sizes as of v02):
  document_type 19 · scale 6 · sector 7 · intervention type 25 ·
  rationale_level 2 · rationale_type 2 · rationale_subtype 5 ·
  beneficiary_unit 13 · result_level 8 · result_type 8 · evidence_type 3 ·
  evidence_subtype 28 · location_type 10 · actor_type 21 ·
  funding_mechanism 5 · result_unit 28 · result_metric 13 ·
  target_beneficiary 26. Validation happens **in code**, not by trusting the
  prompt; invalid labels go to a batched repair step, then to the candidate
  log.
- **Known template gotcha:** in the v02 `lists` sheet the `result_metric`
  and `result_unit` columns are labelled opposite to their use in the data
  sheets (real data holds categorical metrics like "total beneficiaries" in
  `result*_metric` and counting units like "individual" in `result*_unit`).
  The schema maps vocabularies to actual usage; a rename is proposed for the
  next template revision.
- **Registries.** The model outputs actor/location **names**; R code matches
  or creates registry entries and assigns codes. The model never invents a
  code.
- **No-extraction values.** Absent evidence → explicit empty value with
  reason category (not present in document / present but not quantifiable /
  ambiguous — flagged for review).

## 6. Field applicability by document type

Not every document type can supply every field: **Expected** (absence is a
finding and counts against recall), **Secondary** (extract if present,
absence neutral), **Not expected** (structurally absent; excluded from recall
scoring). Profiles are validated during Phase 4 and grow as sources onboard.

| Document type (source) | Project basics & budget | Interventions | Results with values | Evidence type |
|---|---|---|---|---|
| ICR — Implementation Completion & Results Report (WB) | Expected (Data Sheet) | Expected (components; Annex "Key Outputs") | Expected (Results Framework annex: baseline/target/actual) | Expected (M&E section) |
| PPAR (WB, IEG) | Expected | Expected | Expected | Expected |
| Terminal Evaluation (GEF) | Expected | Expected | Expected | Expected |
| Mid-Term Review (GEF/AfDB) | Expected | Expected | Secondary (interim results only) | Expected |
| PIR — Project Implementation Report (GEF) | Secondary | Expected | Secondary | Secondary |
| PCR / completion summary (AfDB, GCF) | Expected | Expected | Expected | Secondary |
| PCR Evaluation Note / validation (AfDB IDEV) | Secondary | Secondary | Secondary (ratings, not values) | Expected |
| xls/xlsx rating sheets (GEF TE ratings) | Not expected | Not expected | Secondary (ratings only) | Not expected |

Practical notes from the corpus structure scans: WB ICRs follow two
standardized generations (pre/post ~2018) with fixed section maps — the
pipeline extracts from the Data Sheet, Project Context, Outcome section,
Results Framework annex, and cost annex, skipping boilerplate annexes.
French-language documents (GEF/AfDB) are extracted in-language with English
coded values. Non-PDF formats (docx) are converted; xls rating sheets are
handled as structured tables.

## 7. Methodology

Six phases; 1–3 are preparatory, 4 is the iterative core, 5–6 scale and
deliver.

**Phase 1 — Corpus consolidation & screening resolution.** Resolve
`to_screen` piles per source: deterministic rules first (e.g. WB topic
classification, GEF LDCF/SCCF membership), one batched LLM screen for the
remainder, human adjudication of disagreements; verdicts recorded per source.
Output: a frozen extraction queue of `in_scope` documents.

**Phase 2 — Machine-readable template.** Generate the extraction schema
(JSON Schema) from the template workbook: field definitions and instructions
from the `readme`, vocabularies from `lists` (with the metric/unit mapping
fix), registries loaded for post-hoc code assignment. The schema is
version-stamped from the template version; regenerating on template release
is a one-step script.

**Phase 3 — Extraction rules & prompts.** One structured-output LLM call
per document *(model and cost per document recorded; deterministic-first:
metadata fields — title, IDs, dates, document type, links — are prefilled
from the catalogues at zero LLM cost)*. Inputs: page-tagged text
(`[page N]` markers) of the mapped relevant sections. Rules: extract **all**
results exhaustively, rank/pick headline results deterministically in code
(eliminates run-to-run selection variance); rationale prompts ask explicitly
for the climate stressor vs perceived benefit; temperature 0; verbatim
quote + page required per coded value. Vocabulary passed in-prompt but
enforced in code.

**Phase 4 — Iterative validation.**
*Round 1 (done):* gold standard P001–P010 hand-extracted in template v02.
The canonical worked example is **P001 — TerrAfrica (WB P149269, ICR
ICR00004643)**: every example value in the template readme comes from it.
*Round 2:* AI extracts the gold-standard documents blind; field-level
comparison against human records; iterate prompts/rules until Section 8
thresholds are met. Inter-rater agreement measured on a shared subset to
separate template ambiguity from AI error (Annex B guide).
*Round 3:* AI-first on a small fresh batch (~15 WB ICRs); human review of
every record; confirm thresholds hold beyond the tuning set.

**Phase 5 — Scale-up.** Source by source (WB → GEF → AfDB → GCF), in
batches. Per-batch sampling review (proposed 10% of records,
*(to be agreed)*); per-batch metrics tracked; a material drop on a new
source/document type pauses that source for mini re-validation
(pause-and-revalidate rule).

**Phase 6 — Outputs & database merge.** Validated records merged into the
working database by a reviewed R step (never a raw overwrite); no-extraction
gap report; candidate-vocabulary log to the template owner; methods summary
with final metrics for the synthesis write-up.

## 8. Quality assurance and performance metrics

All thresholds are proposed working values, to be confirmed after Round 2 and
**fixed before scale-up**. Metrics are always interpreted against the
Section 6 applicability profile — a field that is Not expected for a document
type never counts against recall.

| Metric | Measured how | Proposed working target |
|---|---|---|
| Field accuracy — coded fields | Exact match vs gold standard (Round 2) / human review batches (Round 3+), per field and per source type | **≥80% before scale-up (to be agreed)**; fields below threshold get rule/prompt rework |
| Field accuracy — free-text (`_stated`, rationale) | Human judgement: faithful and complete vs source | Reviewed qualitatively; systematic paraphrase drift triggers prompt fix |
| Provenance validity | **Automated:** quoted passage must exist verbatim (whitespace-normalised) at the claimed page of the source | **100% mechanical gate** — records failing auto-reject before human review |
| Recall — location-intervention records | Share of gold-standard long-format rows the AI found (Expected fields only) | **≥80% before scale-up (to be agreed)** |
| No-extraction accuracy | Random sample of empty fields per batch re-checked by a human | False-empty rate monitored per source type |
| Result-selection stability | Same document run twice → identical extracted result set | Deterministic by design (exhaustive-then-rank); any diff is a defect |
| Inter-rater agreement (human) | Two blind extractors, shared subset, per field | Fields below threshold flagged for template definition rework before AI tuning |
| Stability across batches | Per-batch accuracy during scale-up | No material drop on a new source/type; else pause-and-revalidate |

**Known failure modes** (from the first pilot, 2026 Q2) and their design
responses: rationale extraction missed climate hazards → explicit
stressor/benefit distinction in prompt + `rationale_level` field; result
selection varied between runs → exhaustive-then-rank; vocabulary mismatch on
metrics/units → mapping fixed in schema (Section 5).

## 9. Responsible AI use

Anchored to the IAES Technical Note *Considerations and Practical
Applications for Using AI in Evaluations* (2025):

- **Human oversight.** No AI record enters the working database unreviewed
  during Phases 4–5 sampling; thresholds and scope decisions are human
  decisions; the template owner arbitrates contested values.
- **Anti-hallucination.** Verbatim provenance is mandatory and mechanically
  verified; outputs without valid provenance are auto-rejected (Section 8).
  "No extraction" is a correct, valued answer.
- **Data handling.** Only public institutional documents are processed; no
  personal data is sent to third-party AI services; API terms of the model
  provider are checked before use.
- **Transparency & replicability.** Every output row is stamped with
  template version, prompt version, model name/version, and run date
  (Annex A). Exact replicability is not claimed for probabilistic outputs;
  the deterministic post-processing (ranking, code assignment, validation)
  is fully replicable.

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Template vocabulary doesn't match documents' language → forced or missed codes | Candidate-value flag in output schema; candidate log reviewed by template owner each batch; synonym notes added to schema |
| Template revision invalidates earlier extractions | Template version stamped on every record; changed fields identified by diff; re-extraction of affected fields only |
| Performance drops on a new source/document type | Per-batch metrics + pause-and-revalidate rule; applicability profile set from a structure scan before extraction |
| Screening backlog blocks corpus growth (WB 428 catalogued to_screen) | Screening is Phase 1 with its own deliverable; extraction proceeds on `in_scope` while screening runs |
| French/other-language extraction quality lags English | Language recorded per document; language-stratified metrics in Round 2/3; French gold-standard documents included in review samples |
| Non-PDF formats (docx, xls rating sheets) break the text pipeline | Format-specific ingestion (docx conversion, table parsing); xls sheets profiled as Not expected for narrative fields |
| Gold standard itself inconsistent (single-extractor bias) | Inter-rater agreement round on a shared subset; ambiguous fields fixed in template before AI tuning |
| Cost overrun at scale | Deterministic-first design (metadata prefill, code-side validation, one call/document); per-document cost tracked from Round 2; batch API for scale-up *(model tier decision pending)* |

## 11. Timeline and dependencies *(indicative — to be confirmed)*

| Period | Milestones |
|---|---|
| Q3 2026 | Refined template released and schema generated (Ph2); screening of to_screen piles resolved (Ph1); prompts + extraction rules (Ph3); Round 2 AI-vs-gold-standard iterations; thresholds confirmed; Round 3 AI-first batch on WB ICRs |
| Q4 2026 | Scale-up WB → GEF → AfDB → GCF (Ph5); validated records merged; gap report + candidate-vocabulary log delivered (Ph6); onboarding of next source (IFAD or Adaptation Fund) using Section 3.3 |
| 2027 | Extension sources per WP3 universe; periodic re-runs for newly published evaluations; handover per no-cost-extension staffing plan |

**Dependencies:** the refined template (blocks Ph2); team decisions on QA
thresholds and the land/forest scope boundary; Zotero group library + API
key (catalogue automation); reviewer time for Rounds 2–3; model/budget
decision for scale-up.

---

## Annex A — Extraction output schema (per document)

Every extraction run emits, per document:

- `document_ref`: source, source document ID, resource_id, file path/URL
- `versions`: template version, prompt variant + version, model name/version,
  run date, pipeline commit hash
- `project_record`: all `project_data_general` fields, each coded value as
  `{value, quote, page_or_table, confidence (high/med/low)}`
- `location_records[]`: all `project_data_location-specific` fields, same
  value structure
- `no_extraction[]`: field, reason category (not in document / present but
  not codable / ambiguous)
- `candidate_values[]`: field, source wording, proposed vocabulary addition,
  quote
- `provenance_check`: pass/fail per quoted value (mechanical)
- `review_status`: unreviewed / human-validated / human-corrected

## Annex B — Disagreement diagnosis guide

When AI output disagrees with the gold standard or a reviewer:

| Pattern | Diagnosis | Fix / destination |
|---|---|---|
| AI picked a clearly wrong vocabulary option | Prompt/rules defect | Refine field instructions in prompt; retest on gold standard |
| AI's wording is right but the code differs from the human's; humans also split | Ambiguous field definition | Template owner rewords definition/options; log to template revision |
| Correct concept, but no vocabulary option fits | Missing vocabulary option | Candidate log → template owner |
| AI extracted a value the document doesn't support | Hallucination / evidence failure | Should be caught by the provenance gate — if it passed, tighten the gate (paraphrase leakage) |
| AI missed content a human found | Recall failure | Check section map coverage first (was the passage in the model's input?), then prompt |
| Source text too vague for any extractor | Reporting-quality problem | No-extraction with reason; feeds the gap report, not a defect |

## Annex C — Required updates to the WP3 review protocol

For the template owner to action in `AIs_WP3_EvidenceSynthesis_GreyLit.docx`
(this protocol does not modify that document):

1. **Timeframe 2000–2025 → 2015–2025** everywhere: Background framing
   ("quarter-century"), PICOS Sources (S), Table 1 inclusion, Table 2
   exclusion ("before 2000" → "before 2015"), §IV retrieval step 3, §VII
   trend analysis, Appendix document-metadata variables (Year, Timeframe).
2. **Evaluation-type documents only; proposals excluded** (team decision
   2026-07-17): narrow PICOS Sources (S) and Table 1 source types (currently
   admit output/budget/monitoring reporting); in the Appendix document-type
   repository, mark PADs, appraisal documents, and concept notes as out of
   scope, and progress/status/monitoring reports as out of scope as
   standalone bases.
3. **Retrieval implementation update** (§III–IV): for the pilot sources
   (World Bank, GEF, GCF, AfDB) the manual registry/download/tracking
   procedure has been implemented as an automated scraper pipeline with
   evidence-based screening states (`in_scope` / `to_screen` /
   `screened_out`) documented per source. The wider source universe of §III
   and Annex I/II **remains valid as the extension roadmap** — it is the
   identification strategy for onboarding future sources, not outdated
   content. Zotero remains the reference-management layer.
4. **Extraction template** (§VI, Annexes III–XIV): superseded by working
   database v02 (project-level + location-specific long format, controlled
   vocabularies, actor/location registries) and, on release, by the refined
   template (tagging columns removed, provenance fields added).
5. **Editorial:** research questions Q3/Q5 and Q7/Q10 are duplicates —
   deduplicate the list.

---

*Change log:*
v0.1 (2026-07-22) — first draft; revised same day per team edits: corpus
building added as Objective 1, definitions and roles sections removed,
corpus section expanded with filter locations, screening-out reasons, and
to_screen rationale.
