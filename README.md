# Adaptation Insights — Grey Literature Pipeline

Systematic retrieval, filtering, and cataloguing pipeline for grey literature
(project evaluations and completion reports) from institutional sources,
supporting the CGIAR **WP2 evidence synthesis on climate adaptation in
Africa's food and agriculture sector** and the **Adaptation Insights** data
platform.

The pipeline answers: *which adaptation actions have actually been implemented
across Africa, and with what results?* — by building a screened corpus of
project **evaluation documents** (not proposals) that downstream AI-assisted
extraction turns into a structured database.

> **This repo contains code and metadata only.** The documents themselves
> (~1.4 GB of PDFs) live on the team OneDrive under
> `WP2_Evidence Synthesis\Grey Literature\Data\Project_doc\` and are never
> committed to git.

## Pipeline overview

```
1. SCRAPE      R/{worldbank,gcf,gef}.R      query each source, filter for
                                            Africa + agriculture/adaptation,
                                            download documents, log everything
2. FILTER      (folder organisation)        keep evaluation-type documents,
                                            park proposals; keep 2015–2025,
                                            park older documents
3. DATE        R/gef_doc_dates.R            recover document dates from the
                                            files themselves where the source
                                            website publishes none (GEF)
4. CATALOGUE   R/zotero_upload.R            push metadata to the shared Zotero
                                            group library via the web API
                                            (RIS files under metadata/ for
                                            manual import as fallback)
5. EXTRACT     (separate workflow,          AI-assisted extraction of adaptation
                not in this repo)           actions & results into the WP2
                                            template (long format, with
                                            page/table provenance)
```

## Corpus status (as of 2026-07-20)

| Source | In scope (evaluation docs, 2015–2025) | Parked | Notes |
|---|---|---|---|
| World Bank | **204** ICRs (complete vs. metadata) | 115 pre-2015 | dates from API metadata |
| GEF | **142** TEs / MTRs / PIRs / completion reports | 15 pre-2015, 36 undated, 615 proposal-stage | dates recovered from documents |
| GCF | **7** evaluation / completion reports | 11 funding proposals | small but complete for Africa+adaptation filter |
| **Total** | **353** | | |

Scope rules (team decision, 2026-07-17): evaluation-type documents only —
proposals are excluded because they do not reflect what was actually
implemented; time frame 2015–2025 to align with GCA data; excluded documents
are parked in clearly named folders, never deleted.

## Repository layout

```
├── R/
│   ├── 00_config.R              paths, HTTP settings, country/keyword lists
│   ├── 01_utils.R               shared HTTP, download, logging helpers
│   ├── worldbank.R              World Bank Documents & Reports API scraper ✅
│   ├── gcf.R                    Green Climate Fund scraper (Drupal AJAX) ✅
│   ├── gef.R                    Global Environment Facility scraper (HTML) ✅
│   ├── afdb.R                   AfDB scraper (PCRs, PCR reviews, PPERs, IDEV) ✅
│   ├── ifad.R                   stub — to build 🔲
│   ├── worldbank_project_info.R project-level metadata from WB project pages
│   ├── gef_doc_dates.R          document date recovery (see below)
│   ├── zotero_upload.R          push catalogue to Zotero group library (API)
│   ├── sync_metadata.R          refresh metadata/ from the OneDrive corpus
│   ├── run_all.R                master runner
│   └── install_packages.R      dependency installer
├── metadata/                    per-source catalogues — the git-tracked mirror
│   ├── worldbank/               metadata CSV (354 docs), download log,
│   │                            RIS file, filename-rename map, project info
│   ├── gef/                     document list, recovered dates (+ method
│   │                            per file), RIS file
│   └── gcf/                     (no metadata CSV yet — see Known issues)
├── docs/                        protocol notes
├── data/                        pipeline scratch (gitignored)
├── downloads/                   scraper output inbox (gitignored)
└── .claude/                     Claude Code agents & skills for this repo
```

## Setup

1. Install R (≥ 4.4) and dependencies:
   ```
   Rscript R/install_packages.R
   ```
   (`pdftools` additionally required for `gef_doc_dates.R`.)

2. For Zotero upload, create `~/.Renviron` with:
   ```
   ZOTERO_API_KEY=...     # zotero.org/settings/keys — write access to the group
   ZOTERO_LIBRARY_ID=...  # number in the group's URL
   ```
   Never commit the key (`.Renviron` is gitignored).

## Usage

```bash
Rscript R/worldbank.R        # scrape one source
Rscript R/run_all.R          # scrape all working sources
Rscript R/gef_doc_dates.R    # recover GEF document dates
Rscript R/zotero_upload.R    # push new items to the Zotero group library
Rscript R/sync_metadata.R    # refresh metadata/ from OneDrive, then commit
```

Scrapers download into `downloads/{source}/` and write catalogues to `data/`.
Vetted documents are then promoted to the OneDrive corpus
(`Data\Project_doc\{source}\Docs\...`) and the catalogue CSVs to
`...\{source}\List\` — `sync_metadata.R` mirrors those back into this repo.

## Cataloguing in Zotero

Two routes:

- **Automated (preferred):** `R/zotero_upload.R` pushes items to the shared
  Zotero group library. Each item is tagged `wbdoc:{id}` (or source
  equivalent), and the script checks existing tags first — it is idempotent
  and safe to re-run; only new documents upload.
- **Manual fallback:** import `metadata/{source}/{source}_2015_2026.ris` in
  Zotero via File → Import → *"Link to files in original location"*. The RIS
  links attachments to the OneDrive paths, so this works only on a machine
  with the same OneDrive layout.

## Hard-won lessons & known issues

- **World Bank 403s:** `documents.worldbank.org` PDF links return
  `403 Forbidden` to non-browser clients. Fix: fetch from
  `documents1.worldbank.org` with a browser User-Agent (not yet patched into
  `worldbank.R`).
- **Windows 260-char path limit:** long WB report titles + deep OneDrive paths
  broke downloads *and* Zotero imports. 124 files were renamed to compact
  names (`worldbank_{Pcodes}_{docid}_ICR_{year}.pdf`); the old→new map is
  `metadata/worldbank/renamed_long_paths.csv`. New code should keep filenames
  short.
- **GEF publishes no document dates** — not in page HTML, no API. Dates are
  recovered from the files: month-name dates (EN/FR/PT/ES) on the first pages,
  filename year hints, and OOXML/OLE creation metadata, in that order of
  trust. Numeric dates (06/2026) are deliberately ignored — evaluation
  fact-sheets list *planned* closing dates that would win otherwise. PDF
  creation metadata is untrustworthy (the GEF CDN regenerated files in 2025).
  See `metadata/gef/gef_evaluation_dates.csv` for per-file method + year.
- **GEF xls/xlsx "Terminal Evaluations"** are often rating-sheet templates;
  their file-creation dates can predate the project itself and were voided
  where implausible.
- **No GCF metadata CSV exists yet** — the GCF scraper logs downloads but
  never wrote a document catalogue. Worth adding on the next scraper run.
- **Relevance filtering is keyword-based** and lets through some off-topic
  projects (budget-support DPOs, non-agriculture GEF enabling activities).
  A screening pass is planned before extraction.

## Roadmap

- [ ] Patch `worldbank.R`: documents1 host + browser UA; min-year 2015; drop PADs
- [ ] Align `gef.R` / `gcf.R` to scope (evaluation doc types only)
- [ ] Write GCF document catalogue CSV + RIS
- [ ] Relevance screening (rules first, LLM for the ambiguous remainder)
- [x] AfDB scraper (category listings + IDEV faceted search, WAF session handling, evaluation-only scope 2015–2025)
- [ ] Remaining scrapers: IFAD, Adaptation Fund, FAO, UNDP
- [ ] Automate the full flow for newly published documents

## Contributing

1. Branch: `git checkout -b feat/{source-name}`
2. Build the scraper following the pattern in `worldbank.R`
   (see `.claude/skills/new-scraper/` for the checklist)
3. Test, commit (`feat: add {source} scraper`), push, open a PR
