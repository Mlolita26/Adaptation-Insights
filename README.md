# Adaptation Insights grey-literature pipeline

R code for the CGIAR WP2 grey-literature workstream: evaluation documents
about climate adaptation in African agriculture are retrieved from six
funders (World Bank, GEF, GCF, AfDB, Adaptation Fund, CIF), de-duplicated,
screened against the WP3 protocol, catalogued in Zotero, extracted into the
WP2 template by a two-session AI pipeline, harmonised, reviewed, scored
against a gold set and published.

This repo holds code and the reference data the code reads at run time.
Everything else lives next to it on OneDrive:

| What | Where |
|---|---|
| How and why, current state, open questions | `../00_Knowledge/` (start with its README) |
| Protocol, QC checklist, workflow diagram | `../01_Protocol/` |
| The template | `../02_Template/` |
| The document corpus | `../03_Documents/` (not in git) |
| Team-facing outputs and review queues | `../04_Extraction_Results/` |
| Rules and gotchas for AI sessions | `CLAUDE.md` |

## Folders follow the workflow

```
R/00_shared   R/01_retrieve   R/02_dedup   R/03_screen   R/04_catalogue
R/05_extract  R/06_harmonise  R/07_review  R/08_quality  R/09_publish
catalogues/   run-time reference data + git mirrors of each source's List folder
docs/         AI_Extraction_Protocol.md (canonical protocol text)
outputs/      gitignored scratch
```
The full map, script by script, is `../00_Knowledge/05_folder_architecture.md`.

## Running it

Once: `Rscript R/00_shared/install_packages.R`, and API keys in `.Renviron`.
Then, from this folder, one script per step:

```
Rscript R/01_retrieve/run_all.R                  # scrape all working sources
Rscript R/02_dedup/doc_census.R                  # family, ids, hash per file
Rscript R/02_dedup/dedup_corpus.R                # aliases + project clusters
Rscript R/03_screen/screen_scope.R --source=af   # protocol screening, resumable
Rscript R/04_catalogue/build_doc_index.R         # then zotero_upload.R
Rscript R/05_extract/run_corpus.R --dry          # plan and cost; drop --dry to run
Rscript R/06_harmonise/harmonize.R
Rscript R/08_quality/score_pilot.R               # accuracy vs gold, with a why column
Rscript R/09_publish/export_results.R
```
Each script's header says what it does, what it reads and what it writes.
