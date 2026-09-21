# AI-Assisted Data Extraction from Project Evaluation Documents

**Protocol for corpus construction, structured extraction and validation**

Adaptation Insights, WP2 Evidence Synthesis, Grey Literature

**Draft v0.2, 21 September 2026**

> Canonical version: GitHub `Mlolita26/Adaptation-Insights`, file
> `docs/AI_Extraction_Protocol.md`. The code this protocol describes is in
> the same repository, and its README explains every script.

---

## 1. Background and rationale

Evidence on what climate adaptation has actually been carried out in
Africa's food and agriculture sector, and with what results, sits in the
grey literature of development institutions: implementation completion
reports, terminal evaluations, performance evaluations and similar
documents. Existing syntheses rely almost only on peer reviewed papers, so
this evidence is missing from them (see the review protocol
`AIs_WP3_EvidenceSynthesis_GreyLit.docx`).

The WP2 grey literature synthesis fills this gap by building a structured
database from project evaluation documents: a stocktake of what was
implemented, by whom, where, and with what effects. Reading hundreds of
documents by hand is too slow. A pipeline assisted by language models
applies the extraction template at scale, under the checks this protocol
defines. The pipeline is written in R, and the code is public.

## 2. Objectives

1. **Build the document library.** Retrieve evaluation documents from
   institutional sources, by scraper where a source allows it and by hand
   where it does not. Remove duplicates. Screen every document against the
   scope rules and record the decision (in scope, out of scope, unsure).
   Store the documents on OneDrive and catalogue every one of them in
   Zotero, where the collection a document sits in shows the decision.
2. **Fill the working database.** For every in scope document, produce
   checked records in the extraction template: one project level record and
   location specific records in long format (one row per location,
   intervention and result).
3. **Record what could not be extracted.** A field with no supporting
   evidence in the document stays empty, with a reason. It is never
   guessed. The pattern of gaps (results without baselines, missing
   locations) is itself a finding for the evidence gap analysis.
4. **Test the template.** Every run is also a test of the template. Values
   that fit no option, fields that stay empty across documents and
   definitions that prove ambiguous are logged as questions for the template
   owner.

## 3. Inputs and corpus

### 3.1 Sources and retrieval

Six funders are in the corpus: the World Bank, the Global Environment
Facility (GEF), the Green Climate Fund (GCF), the African Development Bank
(AfDB), the Adaptation Fund and the Climate Investment Funds (CIF). They
were chosen because their document repositories can be read by a program,
which gave volume quickly while the method was being validated. Annex D
records, per source, which classification systems the site offers, which
categories were selected and which filters run in code.

Retrieval is deliberately generous. The scrapers take every evaluation type
document for African agriculture or adaptation projects that the source's
own filters can identify, and keep documents with evidence on either
angle. Stricter filters at query time were tested and silently lost in
scope projects. The scope decision is taken later, by the screener, on the
full text of each document (section 3.4).

Two more routes bring documents in:

- **By hand.** A team member can drop a PDF into the funder's collection in
  the Zotero group library. A script (`zotero_pull.R`) lists files in the
  library that have no record behind them, downloads them into that
  funder's `to_screen` folder, and registers them. From there they follow
  the same steps as every other file. The first run of this route brought
  in 71 GCF evaluations a teammate had added, 34 of them distinct.
- **Reserve.** The recall first sweeps also listed candidate documents with
  weak evidence that were catalogued but not downloaded (for the World Bank,
  428 documents). If the team widens the thematic scope, this reserve is
  the first pool to revisit.

### 3.2 What the corpus holds

As of 21 September 2026 the screener has judged 928 documents. Every file in
every folder was screened, including folders earlier labelled screened out
or pre 2015, so that no earlier folder decision stands unexamined. Only
proposal stage documents were left out, because a proposal describes an
intention, not what was implemented.

| Source | Screened | In scope | Out of scope | Unsure | Parked without screening |
|---|---|---|---|---|---|
| World Bank | 482 | 139 | 337 | 6 | 428 catalogue only entries not downloaded |
| GEF | 122 | 26 | 90 | 6 | 615 proposal stage documents; 28 files in Word or Excel format not yet readable by the pipeline |
| GCF | 42 | 17 | 25 | 0 | 11 approved funding proposals |
| AfDB | 172 | 58 | 104 | 10 | none |
| Adaptation Fund | 38 | 19 | 15 | 4 | 92 proposal stage documents, 208 non African project documents (catalogued only) |
| CIF | 72 | 0 | 70 | 2 | administrative papers of the Evaluation and Learning Initiative, excluded at retrieval |
| **Total** | **928** | **259** | **641** | **28** | |

The 259 in scope documents by document family (section 6): 138 World Bank
ICRs, 53 AfDB project completion reports, 43 evaluator written terminal or
mid term evaluations, 9 GEF Portal evaluation forms, 8 completion reports
that are not forms, 3 World Bank IEG reviews, 3 GCF completion documents and
2 programme evaluations. By year, the count rises from 9 documents published
in 2015 to 45 in 2025. Seven documents are in French, one is bilingual, the
rest are in English.

### 3.3 One document, one record

Before screening, every file gets a census row: its family, its kind
(terminal evaluation, mid term review, completion report and so on), the
project and report identifiers printed on its first pages, and a checksum.
The dedup step then finds identical files and the same document filed twice
(same family, same kind, same identifier). The extra copies are moved out of
the source folders into `03_Documents/duplicates/`, renamed with their source
as prefix, and an Excel register there says which copy was kept, why, and
where the other went. The kept copy is the funder's own version, then the
copy in an in scope folder, then the longer file. Nothing is deleted.

So far 57 files have been moved: 13 World Bank ICRs re hosted in the GEF
folder, 3 AfDB reports, an Adaptation Fund evaluation re hosted by the GEF,
one English and French pair of the same AfDB report (English kept), two
byte identical pairs, and 37 GCF evaluations a teammate had uploaded two or
three times.

A project with several distinct documents (a mid term review and a terminal
evaluation, say) is not a duplicate. Such clusters are reported in
`project_clusters.csv` for a protocol decision (section 12), not moved.

### 3.4 Screening

The screener (`screen_scope.R`, model gpt-5-nano) reads each document in
full, up to the first 60 pages, and returns a verdict with its evidence:

- the verdict: in scope, out of scope or unsure;
- the reason, one sentence naming the criterion that failed;
- a quote naming the climate risk the project responds to, and a quote
  describing the adaptation action, when present;
- the document kind as the document states it, the publication year, the
  language, the countries, whether the document covers several projects,
  and whether the project is adaptation, mitigation or neither;
- the document family, confirmed or corrected against the census rule.

The five criteria, applied in this order:

| Criterion | In scope when |
|---|---|
| Source type | The document evaluates what was done: a completion report, a terminal or mid term evaluation, a performance evaluation. Proposals, appraisals and progress reports are out. |
| Timeframe | The document is dated 2015 to 2025. |
| Scope | The project is in Africa. Regional and multi country projects count if African countries are among them. |
| Sector | Agriculture and food systems are the project's primary subject: crops, livestock, fisheries, agroforestry, food security, rural livelihoods built on farming. A project in another sector (transport, energy, water supply, forest conservation, health, governance) is out even if farmers benefit. |
| Intervention | The project acts on a climate risk it names. Irrigation, value chains or productivity alone are not adaptation; a climate risk must be quoted. Mitigation only projects and emergency relief after a disaster are out. |

A second pass in code (`screen_rules.R`) checks the model's answer without
paying for another read. The year window is applied here from the model's
stored verdict, so moving the window is a two number change and a rerun. A
verdict of in scope with no climate risk quoted becomes unsure. A project
the model itself calls mitigation goes out. A programme evaluation that
covers several projects becomes unsure, because extraction needs one project
to focus on. Bare one word reasons are re asked. Documents of one project
with conflicting verdicts are listed.

A person's decision wins over all of this. The file
`scope_screen_overrides.csv` holds one row per decided document (source,
filename, verdict, note, who decided). The rules script applies it last.
This is the accepted or rejected loop in the workflow diagram: an unsure
document goes to a person, the decision is recorded there, and the next run
of the rules and of the Zotero sync carries it through.

Measured on a review of 200 judgements read against the documents (100 in,
100 out), the first pass was right on about 85 percent of in scope verdicts
and 96 percent of out of scope verdicts. The misses clustered: irrigation or
productivity read as adaptation with no climate risk named, mitigation
projects, and multi project syntheses. The rules above were written from
those misses, and 115 documents with weak reasons were re asked with a
tightened prompt; 22 moved into scope and 6 were parked as unsure for the
protocol lead. Screening the whole corpus costs about one US dollar.

The screener's verdicts are not stable on borderline documents: the same
document can be judged differently on two reads. That is why the rules live
in code, quotes are required, unsure cases go to a person, and human
decisions are recorded in a file rather than in the model's output.

### 3.5 Why documents were excluded

Of the 641 documents out of scope, 160 are dated before 2015 and 24 are dated
2026 (GEF Portal forms generated this year, and one ICR); whether the window
should apply to the document's date or the project's years is an open
question (section 12). Among the rest, the screener's reasons name the
sector in 497 cases and the intervention in 500, the source type in 65 and
geography in 56; a reason can name more than one criterion.

Where the sector was named, the sectors were (counts as of 18 September,
617 documents out): governance and public finance 75, energy 55, forestry
and conservation 38, health and social protection 35, water supply and
resources 24, urban development 21, private sector development 15,
transport 14, transparency and monitoring systems 13, disaster risk
management 12, coastal zones 10, mining 4, humanitarian 3, land
administration 2, and 135 where the reason said sector without naming
which. Three groups sit at the edge of the definition and are with the
protocol lead: water resources projects with farming communities, forest
conservation as against agroforestry, and coastal projects with fishing
communities.

Where the intervention was the only failure (114 documents on 18
September), the largest group is agriculture projects that name no climate
risk (52), then emergency relief (9) and mitigation (7).

### 3.6 Source extension roadmap

The six sources do not bound the review. The WP3 protocol's source universe
(multilateral development banks, UN agencies such as IFAD, FAO and UNDP,
African government agencies, INGOs, knowledge portals, evaluation offices)
remains the identification strategy for extension. The next candidates are
IFAD, FAO and UNDP. A source that cannot be scraped joins by manual download
into the same folder structure, or by hand additions in Zotero, and goes
through the same steps.

### 3.7 Source onboarding procedure

Every new source joins by the same path, so the extraction stage never
needs redesign:

1. **Retrieval.** A scraper following the repository pattern (one script per
   source in `R/01_retrieve`, a header block naming the site, the strategy
   and the quirks, all requests through one polite fetcher), or manual
   download. Filters as close to the scope as the source allows.
2. **Folders and paths.** The source's folders are added to `paths.R`, the
   one file that knows the layout.
3. **Census and dedup.** `doc_census.R` classifies every file into a family;
   `dedup_corpus.R` removes copies.
4. **Screening.** `screen_scope.R` and `screen_rules.R` judge every file.
5. **Catalogue.** The metadata list goes to the source's `List` folder,
   mirrored into the repository; the Zotero sync creates the records.
6. **Family check.** If the source's documents are written in a template
   the pipeline has not seen, a family is added to `doc_families.R` and, if
   needed, an extraction module to `R/05_extract/families/`.
7. **Capped extraction validation.** A small batch is extracted and reviewed
   against the section 8 metrics before the source is scaled.

### 3.8 Other inputs

- **Template:** the extraction template
  `EvidenceSynthesis_GreyLiterature_AfricanAgricultureAdaptation_UpdatedTemplate_27Aug2026.xlsx`
  in `02_Template`, released 27 August 2026 and pinned. Its readme sheet is
  the data dictionary: every field has a description, options, examples
  from project P001 and extraction instructions. Extractions declare the
  template version they follow.
- **Keyword taxonomy:** the review's keyword file
  (`Keywords_Adaptation Implementation and Effectiveness_Grey Literature.xlsx`)
  informs the retrieval filters and the vocabulary synonyms.
- **Gold set:** projects P001 to P010, extracted by hand into the earlier
  working database and then audited page by page. Source documents under
  `03_Documents/pilot/gold_set_P001-P010/`. The corrected reference is
  `catalogues/gold_v1_general.csv` and its companions.
- **Holdout set:** ten corpus documents (H001 to H010, all six sources, two
  in French) never used in tuning, with an independent reference extracted
  by reading them before the pipeline ran (`catalogues/holdout_reference.csv`).

## 4. Data management and infrastructure

Three pillars, each with one job:

| Pillar | Location | Holds | How it is kept in step |
|---|---|---|---|
| **OneDrive** | `WP2_Evidence Synthesis/Grey Literature/` | The documents (`03_Documents`, one folder per source, plus `pilot/` and `duplicates/`), the protocol and template (`01_Protocol`, `02_Template`), the outputs for people (`04_Extraction_Results`), the knowledge base (`00_Knowledge`, twelve short notes on what the project is and how it works) | The scripts read and write here directly |
| **Zotero** | Group library "Adaptation Insights 2" | The catalogue and the record of decisions: one record per screened document, with metadata, the file attached, and a place in its funder's `included`, `to screen`, `screened out` or `duplicates` collection | `zotero_upload.R`, idempotent; run after every screening change |
| **GitHub** | `github.com/Mlolita26/Adaptation-Insights` (public) | Everything programmatic: scrapers, screening, catalogue, extraction, scoring and publishing code; the metadata mirrors and reference tables (`catalogues/`); this protocol. No PDFs, no keys | Commit and push |

**Folders inside a source.** Each source has `Docs/` with an in scope
working folder (`2015_2026` or `evaluation_docs`), parked folders
(`to_screen`, `screened_out`, `pre_2015`, `proposal_stage`, `undated`) and
`List/` for its metadata. The folder a file sits in is where it was put at
retrieval. Since September 2026 the decision that counts is the screening
verdict, not the folder: the extraction driver takes any file the screener
judged in scope, wherever it sits, and never takes one judged out. Moving
files to match verdicts is possible but not done, so that nothing is lost
if a criterion changes.

**Zotero fields.** Report Number holds the document's own number where the
funder gives one (a World Bank ICR number). Call Number holds the project
identifier (World Bank P code, GEF id, AfDB project code, GCF FP code),
because Zotero has no project number field. Extra holds the file name and
the screening verdict with its reason. Tags carry the family
(`family:wb_icr`), the verdict (`screen:in scope`) and an internal document
tag that lets the sync recognise its own records.

**Hand additions and duplicate reconciliation.** Team members may add items
to the library by hand. Before creating a record the sync looks for a hand
made item that is the same document (shared identifier, same URL, or the
same file checksum) and adopts it, adding the pipeline's tags and status
while keeping the member's own tags and notes. A bare file with no record is
pulled into the corpus (section 3.1) and, once screened, placed under the
record made for it. Records of files the dedup step moved out go to the
`duplicates` collection. Nothing is deleted from the library by the
pipeline; a tidy up script that moves a record's second identical copy of a
file to Zotero's trash exists and is run by a person.

**Outputs.** Working files of every run (Session 1 CSVs, verification
reports, harmonised CSVs, raw JSON per document) stay in
`05_Pipeline/outputs/`, which is not tracked in git. Copies for people go to
`04_Extraction_Results/`: the results workbooks, the review lists, the
scores, the cost workbook. Nothing overwrites the hand curated working
database; merging is a reviewed step (section 7, phase 6).

**Conventions.** File paths are kept under 240 characters where possible;
the scripts handle longer ones. Document file names carry source, project
code, document type and year. Every catalogue row keys on the source's own
document identifier.

## 5. Extraction target: the data model

The template of 27 August 2026 defines two linked tables. Its readme sheet is
the authority on every field.

**`project_data_general`**, one record per project: identity
(`project_code`, `project_title`, `project_id`, `project_lead`), years
(publication, start, closure; actual, not planned), `project_scale`,
location count and notes, project rationale, target beneficiary,
`GESI_project` (gender and social inclusion, free text), up to three
headline results (value, metric, unit), budget, disbursed and currency,
`funding_mechanism` and `funding_mechanism_portion`, funder and implementor
(actor codes), `document_type`, `resource_id`, `evidence_depth`,
`reference_link_1` to `3`.

**`project_data_location-specific`**, long format, one record per location,
intervention and result: location code, `subsector_stated` and coded
`subsector type`, `intervention_stated`, `rationale_stated`,
`target_beneficiary`, result (`result_stated`, `result_value`,
`result_unit` as free text, `result_level` coded), evidence
(`evidence_methodology`, how the result was assessed; `evidence_source`,
what it rests on; both free text), `resource_id`, `evidence_depth`,
`resource_link`, notes. At this level only `subsector type`,
`result_level` and `target_beneficiary` are coded; everything else is
verbatim.

The rules the pipeline enforces:

- **Coded and stated pairs.** Nearly every coded field pairs with a
  `_stated` field carrying the document's words, and every stated value
  carries its page reference.
- **Two sessions.** Session 1 extracts the document's own words: quotes,
  literal values and page numbers, for each field group (identity,
  geography, rationale, results, finance). No categories. Session 2 maps
  each verified extract to the controlled vocabularies, seeing only the
  extract and the field's options, never the document. The vocabularies
  come from the template readme (document_type 19 options, project_scale 6,
  subsector type 7, result_level 5, funding_mechanism 5, result metric 27,
  result unit 12, target_beneficiary 24, location_type 9, actor_type 21,
  evidence_depth 3). Codes are validated in code: a value not on the list
  goes to a batched repair step, then to the candidate log.
- **The rationale is the document's words.** The template asks for a
  sentence of about 100 words covering all climatic and non climatic
  drivers. A composed sentence can never pass the verbatim check, so the
  pipeline stores the passages in which the document states the drivers,
  with their pages. Whether the template should ask for a composed summary
  as a separate, unchecked field is an open decision (section 12).
- **Registries.** The model outputs actor and location names; codes are
  assigned in R against the template registries (1,372 coded actors, 677
  location codes), never by the model. Matching is tiered: exact name or
  acronym, then unique substring (an ambiguous name is refused, not
  guessed), then a fuzzy shortlist, and only then one batched model call
  that may pick from the shortlist or answer NEW. Every extracted name is
  string checked against the document, so only organisations the document
  names reach the matcher. A synonym table built from each organisation's
  own website widens the match, under one rule: a synonym points at exactly
  one institution.
- **New registry entries are audited before anyone reads them.** An
  unmatched actor or location becomes a row in a proposals file with a
  suggested code following the registry's own numbering, and an audit
  script gives each row a verdict (probably new, probably a known actor
  under another name, probably noise). Of 75 actors proposed on the gold
  set, 30 were genuinely new. A code becomes real only when a team member
  adds the row to the registry; the next harmonisation run then resolves
  the placeholders. No document is re read. The pipeline proposes, the team
  decides.
- **Decisions are remembered.** Every vocabulary and actor decision Session
  2 takes is written to `catalogues/vocab_decisions.csv` (field, a
  fingerprint of the option list, the extract, the choice) and reused on
  the next run. This is what makes reruns reproducible: before it, the same
  extraction harmonised once to 25 matched actors and once to 18. A person
  can correct a row and the correction survives; deleting a row sends that
  extract back to the model; changing an option list retires the decisions
  taken under the old one.
- **Saying nothing is allowed.** Session 2 may answer NOT STATED and leave
  the cell empty. Before this it had to pick the nearest option, which
  turned a results line naming nobody into a beneficiary. On the gold set
  32 cells took this route. An empty cell with a flag is a finding; an
  invented one is a defect.
- **No extraction values.** Absent evidence gives an explicit empty value
  with a reason: not present in the document, present but not quantifiable,
  or ambiguous and flagged for review.
- **Field hygiene in code** (`clean_fields.R`): titles without capitals or
  codes, counts as bare digits, whole digit results, a percent sign for
  percentages, an explicit sentence when a document says nothing on gender,
  and one gate that keeps ratings, money, durations, dates, coverage counts,
  administrative counts and yes or no indicators out of the results slots.
  Start and closure years are derived from an explicit implementation
  period; `evidence_depth` is derived from what was found, never asked of
  the model.

## 6. Document families

A funder is not a document type. The GEF folder alone held World Bank ICRs,
AfDB completion reports, GEF Portal forms, UNEP forms, evaluator written
evaluations and World Bank progress reports. What decides where a field
sits and how the tables are laid out is the template the document was
written in. The pipeline calls this the document family, recognises it from
the first three pages, and routes extraction by it. Seventeen families are
defined in one place (`doc_families.R`); the working document
`01_Protocol/Document_Families.docx` describes each one: cover words,
structure, where each template field sits, how the results tables are
printed, and traps.

| Family | Document | Extraction module | Notes |
|---|---|---|---|
| `wb_icr` | World Bank Implementation Completion and Results Report | `wb_icr` | Two template generations: from 2018 the results framework is Annex 1; before, section F of the data sheet. Tables lose their headers in the text layer; the table reader restores them. |
| `wb_icrr` | World Bank IEG review of an ICR | `agency_evaluation` | Ratings rather than values; the ICR carries the data. |
| `wb_isr` | World Bank Implementation Status Report | none | Progress document. |
| `afdb_pcr` | AfDB project completion report form | `afdb_pcr` | Outcome indicator table with baseline, most recent value, end target and progress; amounts in units of account. |
| `afdb_pper` | AfDB project performance evaluation report | `agency_evaluation` | |
| `gef_portal_form` | GEF Portal terminal evaluation or mid term review form | `gef_portal_form` | Fixed field labels; the form date is the generation date, not the evaluation date. |
| `unep_completion_form` | UNEP operational completion form | `gef_portal_form` | |
| `gef_pir` | GEF project implementation report | none | Progress document. |
| `gef_indicator_sheet` | GEF-7 core indicator worksheet | none | Spreadsheet, no narrative. |
| `gcf_completion_summary` | GCF project completion summary | `gcf_completion` | |
| `gcf_pcr` | GCF project completion report | `gcf_completion` | |
| `af_ppr` | Adaptation Fund project performance report | none | Progress document. |
| `cif_country_me` | CIF country monitoring and evaluation report | `cif_country_me` | Covers several projects; needs a focus project. |
| `agency_evaluation` | Terminal evaluation, mid term review or final evaluation written by an evaluator | `agency_evaluation` | Sub templates: UNDP (project information table, mid term matrix), FAO (results matrix, co financing annex), UNEP validated terminal review, WFP (evaluation questions), UNIDO (fact sheet), Adaptation Fund consultants. |
| `completion_report` | Completion, terminal or final report that is not a form | `agency_evaluation` | |
| `programme_evaluation` | Programme, portfolio or thematic evaluation | `programme_evaluation` | Covers several projects; unsure at screening until a focus project is named. |
| `generic` | Not recognised | `generic` | The general prompt with no family guidance. |

**Field applicability.** A field is Expected for a family when the template
carries it (its absence is a finding and counts against recall), Secondary
when it may be present (absence is neutral), and Not expected when the
document type cannot carry it (excluded from recall scoring). Completion
reports, terminal evaluations and performance evaluations are Expected on
project basics and budget, interventions, results with values and the
evidence fields. Mid term reviews are Secondary on results (interim values
only). Progress documents and indicator sheets are not extracted: progress
reports are screened out by rule, and the protocol lead has been asked to
confirm this (section 12).

**Documents and projects do not map one to one.** A programme evaluation
carries several projects; one project's evidence can be spread over several
documents. A document covering several projects is held as unsure until a
focus project is named in the extraction manifest, and every prompt then
carries that focus line. Combining several documents of one project into one
record is designed but not built (section 12).

## 7. Methodology

### 7.0 The workflow at a glance

![The extraction workflow, from retrieval to publication](workflow_diagram.png)

The picture is `01_Protocol/Workflow_diagram.docx`, kept by hand and
exported to this image. Ten boxes:

1. **Retrieve**, one scraper per source. Files added by hand in Zotero join
   here.
2. **One document, one record.** Census and dedup.
3. **Screen every document**, in full, for scope and for family, then the
   rules pass.
4. **Verdict**, one of three, one destination each. In scope goes to Zotero
   included and on to extraction. Unsure goes to Zotero to screen and to a
   person's queue; the person accepts or rejects, and the decision is
   recorded in the overrides file. Out of scope goes to Zotero screened out
   and is never extracted.
5. **Catalogue and Zotero.** One record per screened document; its status
   follows the verdict.
6. **Route** by document family, not by source.
7. **Extract**, one module per family, all through the same Session 1 script
   and the same table reader.
8. **Combine the families** into one set of verified extracts. Nothing is
   interpreted yet.
9. **Harmonise once for everything**, with the shared vocabulary and the
   shared decision file.
10. **Review queues, then publish.** Actors, locations and vocabulary terms
    go to a person; a ruling is applied by re harmonising, never by re
    reading.

The pink boxes mark where the pipeline grows: a new source enters at box 1
with a new scraper; a change of inclusion criteria (the year window, new
topics) enters at box 3 and reruns the rules; a new document template enters
at box 6 and 7 with a new family and module; a template or vocabulary change
enters at box 9.

**The gate in the middle is the point.** Accuracy is measured on the gold
and holdout documents before anything runs on the corpus. Below threshold,
the response is one of three things: change the prompts, sharpen a field
definition that proved ambiguous, or add to the registries the actors and
locations the documents name. Then the subset runs again.

### 7.1 Phases

**Phase 1, corpus consolidation and screening. Done.** All 928 documents
screened with the method of section 3.4; 259 in scope, 28 with a person.
Zotero mirrors the verdicts. The extraction queue is the set of documents
judged in scope, read by the extraction driver from the screening file.

**Phase 2, machine readable template. Done.** Field definitions,
instructions and vocabulary options are read from the template readme sheet
of 27 August 2026; registries are loaded for code assignment in R. The
template version is stamped on every record.

**Phase 3, extraction rules and prompts. Done, being extended by family.**
Session 1 runs one structured output call per field group over the page
tagged text of the sections the family module names, with the results
framework pages also attached as images because table text scrambles when
extracted. Temperature zero. A near empty first page (a picture cover)
triggers one small vision call to read the title. Session 2 runs in batched
calls that see only the extracts and the options. Metadata fields (title,
identifiers, dates, document type, links) are prefilled from the catalogue
at no model cost, and a catalogue value beats an extracted one. Prompt
version s1-v2.0 loads a family module (section 6); the location sheet runs
prompt loc-v1.4. The family modules are written and probe tested; their
regression against the gold set is the next step.

**Phase 4, iterative validation. Done.**

- Round 1: gold standard P001 to P010 extracted by hand into the earlier
  working database. The canonical worked example is P001, TerrAfrica (World
  Bank P149269, ICR00004643); every example in the template readme comes
  from it. The manual records were then audited page by page against the
  documents; the corrected reference has alternates where two readings are
  defensible, and the audit measured the original human extraction at about
  77 percent on the same yardstick.
- Round 2: the pipeline extracted the gold documents blind, was compared
  field by field, and prompts and rules were iterated. Result: 88 percent
  agreement over 208 field checks (19 fields, ten documents, metric and
  unit included).
- Round 3: ten holdout documents from all six sources, two in French, never
  used in tuning, with an independent reference read before the pipeline
  ran. Result: 83 percent. Instead of two blind human extractors, the
  comparison was three way (the manual gold, a second careful read, and the
  pipeline), which separates template ambiguity from pipeline error at
  lower cost.

**Phase 5, scale up. Next.** The extraction driver runs the in scope
documents by family, in batches, resumable. A sample of records per batch
is reviewed by a person (proposed 10 percent, to be agreed); metrics are
tracked per batch and per family; a material drop on a new family or source
pauses that family for a small re validation. The full run is priced at
about 60 US dollars live or about 30 through a batch API; the batch API is
deliberately not wired yet, to avoid upgrading the model library past the
validated version.

**Phase 6, outputs and database merge.** Validated records are merged into
the working database by a reviewed R step, never a raw overwrite. The gap
report (what could not be extracted, and why) and the candidate vocabulary
log go to the template owner. A methods summary with the final metrics goes
into the synthesis write up.

## 8. Quality assurance and performance metrics

The two sessions are scored separately. Session 1 is scored on recall and
provenance (did we capture what the document states, faithfully). Session 2
is scored on coded field accuracy (given a correct extract, was the right
option chosen). A coded field error counts against Session 2 only when the
extract was right. Metrics are always read against the applicability
profile of section 6: a field a document type cannot carry never counts
against recall.

The thresholds were proposed in July 2026 and fixed after Round 2.

| Metric | Measured how | Target | Measured |
|---|---|---|---|
| Field accuracy, general sheet | Exact or normalised match against the corrected gold reference, per field; the scorer normalises numbers, expands actor codes to names, accepts alternates and classes each check as match, partial, candidate or mismatch | 80 percent before scale up | 88 percent on the gold set (208 checks), 83 percent on the holdout; human baseline 77 percent |
| Field accuracy, free text (stated fields, rationale) | Human judgement: faithful and complete against the source | Reviewed qualitatively; systematic paraphrase triggers a prompt fix | Reviewed in Rounds 2 and 3 |
| Provenance | Automated: every quoted passage, number and name must be found on the cited page, whitespace normalised | Every value checked; a value that fails is dropped from the data and reported | No fabricated quote observed in any measured run. Last location run: 651 verified, 163 found on another page, 18 not verbatim, 2 not found |
| Recall, location and intervention rows | Share of the reference long format rows the pipeline found (Expected fields only) | 80 percent before scale up | Scored against 60 manual rows; the location sheet is the weaker of the two |
| Screening precision | Verdicts read against the documents | Misses fixed by rule, not by re asking | 85 percent of in scope and 96 percent of out of scope verdicts right on the first pass; rules and re ask applied since |
| No extraction accuracy | A random sample of empty fields per batch re checked by a person | False empty rate monitored per family | To run at scale up |
| Stability | The same input run twice gives the same output | Session 1: exhaustive extraction then deterministic ranking in code. Session 2: the decision file | Three consecutive Session 2 runs byte identical |
| Stability across batches | Accuracy per batch during scale up | No material drop on a new family or source; else pause and re validate | To run at scale up |

**How a value that fails provenance is handled.** The July draft said such
records auto reject. In practice they are flagged and kept in the working
output with their flag, because an auto reject silently loses a correct
extraction whose page reference was off by one. A flagged value is withheld
from the merge into the database until a reviewer has looked at it. The
flag categories are: verified, found on another page, not verbatim, not
found.

**Known failure modes and their fixes.** Rationale extraction missed climate
hazards: the prompt now asks separately for the climate stressor and the
perceived benefit. Result selection varied between runs: extraction is
exhaustive and ranking is done in code. Vocabulary mismatch on metrics and
units: fixed in the template of 27 August 2026. Session 2 chose different
codes on identical input: the decision file. Irrigation and productivity
read as adaptation at screening: a climate risk must be quoted, enforced by
rule.

## 9. Responsible AI use

Anchored to the IAES Technical Note *Considerations and Practical
Applications for Using AI in Evaluations* (2025).

- **Human oversight.** No record enters the working database unreviewed
  during scale up sampling. Thresholds and scope decisions are human
  decisions, recorded in files the pipeline reads (the overrides file, the
  registries, the decision file). The template owner arbitrates contested
  values.
- **Against fabrication.** Verbatim provenance is mandatory and checked
  mechanically. A value that fails the check is flagged and withheld from
  the merge. Saying nothing is a correct and valued answer.
- **Data handling.** Only public institutional documents are processed. No
  personal data is sent to a model provider. The models are OpenAI's
  gpt-5-mini (extraction and harmonisation) and gpt-5-nano (screening),
  called through the R package ellmer, version 0.2.1, under the provider's
  API terms.
- **Transparency and replicability.** Every output row is stamped with the
  template version, the prompt version, the model and the run date. Every
  prompt version ever sent is kept (`prompt_history.R`). The code is
  public. Session 1 outputs from a probabilistic model are not claimed to be
  exactly reproducible; everything after them (verification, ranking, code
  assignment, harmonisation with the decision file) is.

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| The template vocabulary does not match the documents' language, so codes are forced or missed | NOT STATED is allowed; a term outside the list is logged as a candidate for the template owner; the synonym table widens actor matching |
| A template revision invalidates earlier extractions | Template version stamped on every record. Because coding is a separate session over stored extracts, a vocabulary change reruns Session 2 only, and the decision file retires decisions taken under the old option list |
| Performance drops on a new family or source | Metrics per batch and per family; pause and re validate; a family module is written from a structure scan before extraction |
| A document covers several projects, or a project spans several documents | Screening marks multi project documents unsure until a focus is named; the manifest carries the focus into every prompt; multi document merging is designed, not built |
| Screening verdicts vary on borderline documents | Rules in code, quotes required, unsure queue, human overrides recorded in a file |
| Hand additions and re uploads create duplicates | Dedup by checksum and identifier before screening; Zotero adoption by identifier, URL or checksum; nothing deleted, a register kept |
| French documents extract less well than English | Language recorded per document; French documents in the holdout; results stratified by language at scale up |
| Non PDF formats break the text pipeline | 28 Word and Excel files in the GEF folder wait for a conversion step; spreadsheet indicator sheets are a family that is not extracted |
| The gold standard itself is inconsistent | It was audited page by page; the reference carries alternates and an adjudication file records who was right where the two readings differed |
| Cost overrun at scale | Deterministic first (catalogue prefill, code side validation); the five calls per document share one document text, priced at a tenth by the provider; the decision file makes reruns almost free; screening the corpus costs about one dollar, extraction about ten cents per document |
| The OneDrive path limit (260 characters) | Handled in the scripts; documented for anyone opening files another way |

## 11. Timeline

| Period | Milestones |
|---|---|
| Q3 2026, done | Template released and read by the pipeline (27 August). Two session extraction built, scored on the gold set (88 percent) and the holdout (83 percent). Decision file, synonym table, proposal audits, field hygiene. Document families defined; census, dedup and whole corpus screening run (928 documents). Zotero follows the screening. Hand additions loop. Family extraction modules written. Repository public with a full README. |
| Q4 2026 | Protocol lead's answers to the open questions (section 12) applied as rules and overrides, then rules rerun and Zotero re synced. Gold regression of the family based extractor. Full run of the 259 in scope documents by family, with per batch review. Merge into the working database, gap report, candidate vocabulary log. Conversion step for Word and Excel files. Onboarding of the next source (IFAD) by the section 3.7 procedure. |
| 2027 | Extension sources per the WP3 universe; periodic reruns for newly published evaluations; handover. |

**Dependencies:** the protocol lead's decisions in section 12; reviewer time
for the per batch samples; the budget decision between a live run and a
batch API run.

## 12. Open decisions

Questions with the protocol lead, collected in `01_Protocol/QC_Common_Mistakes.docx`
(sixteen questions) and in the knowledge base:

1. **Sector criterion.** Are water resources projects with farming
   communities, forest conservation as against agroforestry, and coastal
   projects with fishing communities in or out? Is a safety net programme
   with public works against drought part of food systems? The question in
   the QC document links five documents per sector so they can be read.
2. **Intervention criterion.** Emergency food relief after a flood or
   drought responds to a climate hazard but is not adaptation; the screener
   excludes it. Confirm.
3. **Timeframe.** Documents dated 2026 fall out of the 2015 to 2025 window
   although the projects ran inside it. Is the window about the document's
   date or the project's years? One constant, re applied without re reading.
4. **Progress documents** (World Bank ISR, GEF PIR, Adaptation Fund PPR)
   are screened out by rule. Confirm, or admit them as secondary evidence.
5. **A project with a mid term review and a terminal evaluation.** Is the
   terminal evaluation authoritative, the mid term review used only when no
   terminal evaluation exists?
6. **The same report in English and French.** Treated as one document,
   English kept. Agree?
7. **Rationale field.** The document's words (checkable) or a composed
   sentence covering all drivers (not checkable)? Or both, as two fields?
8. **Provenance failures.** Flagged and withheld from the merge until
   reviewed, as now, or rejected outright, as the July draft said?
9. **Where the controlled vocabularies live.** The template readme is the
   reference; the code carries a copy checked against it at each template
   release; the dropdowns in the template point at a sheet that does not
   exist. Name one source of truth.
10. **`location_count` granularity** (countries or named sites) and the
    definition of `project_lead` when funder, coordinator and executing
    agency differ; the funder of a self published evaluation; financing
    arms (IDA, the African Development Fund, the GEF Trust Fund) as their
    own actor or as the parent; overlapping beneficiary options with no
    definitions. Each is a numbered question in the QC document.

Team decisions: live run or batch API for the full corpus; approval of the
proposed actor and location codes; when to onboard IFAD. Every screening
decision is recorded in Zotero, so the rejected documents can be looked at
there; a new criterion means a rerun of the rules and the sync, and nothing
is lost.

---

## Annex A. What a run produces

Every run of the pipeline leaves these behind. The first is the data; the
rest are its audit trail and its questions.

| Output | Where | Who acts on it |
|---|---|---|
| Session 1 extracts with page references, one CSV per field group, and a raw JSON per document | `05_Pipeline/outputs/extraction/<run>/` | the pipeline |
| Verification report: every quote, number and name with its status (verified, found on another page, not verbatim, not found) | same folder | reviewer, for flagged values |
| Harmonised records in template shape, general and location sheets | `04_Extraction_Results/extracted_records_latest.xlsx`, `location_records_latest.xlsx`; each with a `needs_review` sheet and an `about` sheet naming the run | feeds the synthesis |
| Proposed new actors and locations, audited | `04_Extraction_Results/review/proposed_new_actors_AUDIT.xlsx`, `proposed_new_locations_AUDIT.xlsx` | team: accept, merge or reject each |
| Candidate vocabulary terms | `04_Extraction_Results/review/candidate_vocab_log.csv` | template owner |
| Decisions taken, reused next time | `05_Pipeline/catalogues/vocab_decisions.csv` | a person may correct a row |
| Scores against gold and holdout, with a reason per disagreement | `04_Extraction_Results/scores/` | pipeline maintainer |
| Cost of the run and projected cost of the corpus | `04_Extraction_Results/extraction_costs.xlsx` | budget tracking |

**Version stamping.** Every record carries the template version, the Session
1 prompt version and model, the Session 2 prompt version and the run date. A
template revision invalidates only the codes, never the verbatim layer.

## Annex B. Disagreement diagnosis guide

When the pipeline disagrees with the gold standard or a reviewer:

| Pattern | Diagnosis | Fix and destination |
|---|---|---|
| The pipeline picked a clearly wrong option | Prompt or rules defect | Refine the field instruction; retest on the gold set |
| The pipeline's extract is right but its code differs from the human's, and humans also split | Ambiguous field definition | Template owner rewords the definition or options; logged as a template question |
| Correct concept, no option fits | Missing vocabulary option | Candidate log to the template owner |
| The pipeline extracted a value the document does not support | Fabrication or evidence failure | The provenance check should catch it; if it passed, tighten the check (paraphrase leaking through) |
| The pipeline missed content a human found | Recall failure | Check the family module first (was the passage in the model's input?), then the prompt |
| The source text is too vague for any extractor | Reporting quality problem | No extraction with a reason; feeds the gap report, not a defect |
| Two runs of Session 2 disagree on identical input | Missing decision | Check the decision file was read; a new option list retires old decisions by design |

## Annex C. Required updates to the WP3 review protocol

For the template owner to action in `AIs_WP3_EvidenceSynthesis_GreyLit.docx`
(this protocol does not modify that document):

1. **Timeframe 2000 to 2025 becomes 2015 to 2025** everywhere: background
   framing, PICOS sources, inclusion table, exclusion table ("before 2000"
   becomes "before 2015"), retrieval step 3, trend analysis, appendix
   metadata variables. Pending the section 12 decision on document date
   against project years.
2. **Evaluation type documents only; proposals excluded** (team decision of
   17 July 2026). Narrow the PICOS sources and the source types in the
   inclusion table; mark appraisal documents, project documents and concept
   notes out of scope in the document type repository; progress and status
   reports out of scope as standalone evidence, pending question 4.
3. **Screening criteria as implemented** (section 3.4): five criteria in a
   fixed order, applied to the full text by a model and checked by rules,
   with human overrides recorded. The sector criterion needs the boundary
   decisions of section 12.
4. **Retrieval implementation.** For the six sources the manual registry,
   download and tracking procedure has been implemented as scrapers with a
   census, a dedup step and recorded screening verdicts. The wider source
   universe of the WP3 protocol remains valid as the extension roadmap.
   Zotero remains the reference layer, and now records every decision.
5. **Extraction template.** The WP3 template and annexes are superseded by
   the template of 27 August 2026 (project level and location specific long
   format, controlled vocabularies, actor and location registries, provenance
   fields).
6. **Document families** as the unit of extraction design, in place of the
   document type list.
7. **Editorial:** research questions Q3 and Q5, and Q7 and Q10, are
   duplicates.

## Annex D. Per source retrieval details

The filters below run at retrieval and decide what is downloaded. They are
recall filters: the scope decision is taken by the screener on the full text
(section 3.4). Each source's own site is authoritative; the metadata lists
live in `03_Documents/{source}/List/` and are mirrored in the repository's
`catalogues/` folder.

### D.1 World Bank

**Document types.** The Documents and Reports API classifies every document
by type. Three evaluation types are requested: Implementation Completion and
Results Report, Implementation Completion Report, Project Performance
Assessment Review. Nothing else is fetched.

**Sector.** Every document carries the Bank's own topic classification,
usually two to five topics. Only Agriculture is taken as positive evidence.
Neighbouring topics (Rural Development, Environment, Water Resources) proved
too broad. Topics are used as evidence after retrieval, never as a query
filter, because topic coverage is incomplete on recent documents and query
side filtering lost in scope projects.

**Geography.** One query per document type and African country, plus the
regional and global values under which multi country projects are filed
(Africa, Eastern, Western, Southern and Central Africa, Western and Central
Africa, Eastern and Southern Africa, World). After retrieval the country
field must be African; World filed documents pass only if the title names an
African country.

**Other filters in code.** Document date 2015 or later (the API date
parameter is unreliable with other filters). Budget support instruments
dropped by title pattern (Development Policy, DPO, DPF, DPL, Poverty
Reduction Support, Budget Support, PRSC).

**Abstracts.** The Bank's catalogue summary of each document is stored with
the metadata. A title keyword match is strong evidence; an abstract only
match is weak, because summaries mention scope words in passing. Only the
World Bank provides abstracts.

### D.2 GEF

**Focal area.** Climate Change selected (project counts observed in July
2026: Biodiversity 2,514; Chemicals and Waste 807; Climate Change 2,686;
International Waters 542; Land Degradation 1,064). Climate Change includes
mitigation, which is why the screener's sector and intervention criteria
matter most here.

**Funding sources.** The Least Developed Countries Fund (395 projects) and
the Special Climate Change Fund (103) are the two adaptation implementation
funds. They are the primary sweep, not the perimeter: adaptation work also
sits in the GEF Trust Fund (sustainable land management, integrated
programmes). Gold projects P002 to P004 are Trust Fund financed and would be
invisible to a fund only filter. Future GEF runs sweep the union of the two
funds, the Land Degradation focal area and the Climate Change focal area.

**Document types** on project pages: terminal evaluation, mid term review,
project implementation report, evaluation and completion report are kept;
CEO endorsement, project document, project identification form and review
sheet are parked as proposal stage.

**Dates.** The GEF site publishes no document dates. The year is recovered
from the files: month name dates on the first pages (English, French,
Portuguese, Spanish; latest year), then the year in the file name, then file
metadata for Word and Excel files only. PDF creation dates and numeric date
formats are rejected on purpose (regenerated files and planned closing dates
give false years).

### D.3 GCF

**Facets** on greenclimate.fund: project status Approved and Completed;
theme Adaptation; region Africa. Evaluation and completion documents kept;
approved funding proposals parked. GCF evaluations are also published
through a gap fill from the Climate Policy Radar API, and most of the GCF
corpus arrived through the hand additions route (section 3.1).

### D.4 AfDB

**Category listings swept** on afdb.org: Project and Programme Completion
Reports; Completion Report Reviews; Project Performance Evaluation Reports;
Evaluation Reports, Agriculture and Agro industries.

**IDEV categories** (idev.afdb.org, about 30 in all): the five project
evaluation categories are selected: project performance evaluation, project
cluster evaluation, impact evaluation, evaluation report, PCR and XSR
validation synthesis. The full taxonomy with facet identifiers is cached in
`catalogues/afdb/idev_taxonomy.csv`.

**Excluded by name** even when listed: appraisal reports (proposals),
environmental and social impact assessments, progress reports. When one
document is kept per project the order is: performance evaluation, then
evaluation or completion report validation, then completion report, then mid
term review.

**Sector.** AfDB project codes embed a sector letter (an A in the third
group means agriculture); a document qualifies by that letter or by title
keywords. Dates: listing publication date, then the year in the file name,
then the dated folder path, then the year in the title.

### D.5 Adaptation Fund and CIF, through the Climate Project Explorer

The Climate Project Explorer (climateprojectexplorer.org) is the multilateral
climate funds' joint document platform, built by Climate Policy Radar.
Retrieval uses its public REST API: a document search (top 100 per query)
and a per project fetch that returns all documents of one project with
direct PDF links. Enumeration is by country targeted queries over the
African country list; projects are checked against the Adaptation Fund
project corpus so guidance and policy documents are skipped. Document types
are read from the title, because the API's type field is empty. Performance
reports are parked as progress documents.

The CIF corpus on the platform is empty, so CIF evaluations are scraped from
cif.org directly: sitemap enumeration to document pages, then the PDF link
on each page. The Evaluation and Learning Initiative's administrative papers
are excluded. CIF material is mostly programme level; the screener judged 70
of 72 documents out of scope, most for not being country attributable
agriculture evaluations.

The funds' own sites remain authoritative. A completeness pass against
adaptation-fund.org project pages, which also carry Word evaluations and
performance reports, is a known follow up.

### D.6 Shared keyword lists

The retrieval filters match any single term, case insensitive, in English,
French and Portuguese. A title match keeps the document; an abstract only
match parks it as to screen. The agriculture list covers farming, crops,
livestock, fisheries, agroforestry, food security, value chains, irrigation,
soils, named staple and cash crops, rural livelihoods, extension. The
adaptation list covers adaptation, resilience, climate smart agriculture,
drought, flood, rainfall variability, water scarcity, land degradation,
climate risk and vulnerability, early warning, index insurance, disaster
risk reduction, climate information services, conservation agriculture,
heat stress, sea level rise, salinisation, pests, food crises, and the fund
and plan acronyms (LDCF, SCCF, NAP, NAPA, NDC). The full lists are in
`R/00_shared/00_config.R`. Since September 2026 these lists only decide what
is downloaded; the screener decides scope.

## Annex E. Growing the corpus and the pipeline

**A new source.** A scraper in `R/01_retrieve`, the source's folders in
`paths.R`, then the same steps as every other source (section 3.7).

**A wider timeframe** (documents from 2000, say). Change the two year
constants in `screen_rules.R` and rerun it. No document is read again,
because the model's verdict is stored separately from the year rule. Then
rerun the Zotero sync and the extraction driver. Documents before 2015 are
already in the corpus and already screened on the other criteria.

**A new or changed criterion.** Add the rule to `screen_rules.R`, or change
the screener prompt and re ask the affected documents. Every earlier
decision stays in the screening file beside the new one.

**A new document template.** One entry in `doc_families.R` (label,
detection words, module) and, if the existing modules do not fit, one module
in `R/05_extract/families/`. `doc_census.R --redetect` reclassifies the
corpus from cached covers in seconds.

**A template or vocabulary change.** Session 2 reruns against the new
options at almost no cost. Decisions taken under the old options retire on
their own, because each is keyed to a fingerprint of the option list.
Session 1 reruns only if a new field needs new evidence from the documents.

---

*Change log*

v0.1, 22 July 2026: first draft, revised the same day with team edits.
23 July: GEF recall safeguard, two session design, Adaptation Fund and CIF
onboarded. 8 September: data model synced to the template of 27 August 2026;
registry procedure operationalised.

v0.2, 21 September 2026: the protocol brought in line with the pipeline as
built and run. New: document families (section 6, annex D notes), dedup step
(3.3), whole text screening with rules, overrides and the unsure queue (3.4),
exclusion reasons (3.5), the hand additions route (3.1, 4), Zotero as the
record of decisions (4), decision file, NOT STATED, synonym table, audited
proposals and field hygiene (5), measured results and costs (7, 8, 10), the
handling of provenance failures as flags (8), the three way comparison
method (7), the open decisions (12), what a run produces (annex A) and how
the pipeline grows (annex E). Corrected: six sources and current counts
(3.2), Zotero created and populated, gold set path, rounds 2 and 3 done,
thresholds fixed, timeline, scale up covering all six sources, the registry
size (1,372 coded actors). Removed: the folder based screening states as the
decision of record, the master filter table, the JSON output schema that
was never emitted. Workflow figure replaced by the hand kept diagram. Plain
language throughout.
