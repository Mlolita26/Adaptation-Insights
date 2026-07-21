# World Bank — how the corpus is built and filtered

Scraper: `Script/AI_grey_litterature/R/worldbank.R` (REST API: search.worldbank.org/api/v3/wds).
Method finalised 2026-07-21 after a corpus comparison exposed gaps in earlier
versions (details at the bottom).

## The pipeline in one glance

```
1. QUERY (recall-first — nothing filtered away at the API)
   evaluation doc types only: ICR, Implementation Completion Report, PPAR
   × each of the 54 African countries
   × regional values ("Africa", "Eastern Africa", ..., "World" — multi-country
     projects are NOT filed under their member countries)
   + 7 agriculture/adaptation keyword queries as a recall net
   The WB's own topic classification (teratopic) is fetched with every doc.

2. FILTER (client-side, in order; every count reported)
   a. dedup by document id
   b. date floor: document date >= 2015  (team decision 2026-07-17)
   c. Africa check on the country FIELD (abstract mentions once admitted
      Yemen/Lebanon docs); count='World' docs pass via African country in title
   d. three-way scope rule (screen_status column):
        in_scope  = WB topics include "Agriculture" OR agriculture/adaptation
                    keywords in the TITLE
        to_screen = neither, but keywords in the ABSTRACT — weak evidence,
                    kept and flagged for manual/LLM screening
        dropped   = no positive signal in topics, title, or abstract
   e. budget-support instruments dropped (DPO/DPF/DPL/PRSC/"Development
      Policy" titles) — policy lending implements nothing on the ground

3. DEDUP to one document per project (P-code): prefer in_scope > doc-type
   priority (ICR > ICR Report > PPAR) > English > most recent revision.

4. DOWNLOAD via documents1.worldbank.org with a browser User-Agent
   (documents.worldbank.org returns 403 to scripts); remaining failures are
   dead legacy links.
```

## What "to_screen" means

Documents whose only agriculture/adaptation evidence is in the abstract —
typically true borderline cases (watershed management, land administration,
nutrition, rural infrastructure) mixed with false positives whose abstracts
merely mention "resilience" or "drought". They are kept in the catalogue with
`screen_status = "to_screen"` and must pass a screening step (team review or
batched LLM) before extraction. Nothing is silently discarded: `dropped` rows
had no positive signal in any field the World Bank publishes.

## Corpus status

- **On disk** (`Docs/2015_2026/`, 204 files): the corpus from the original
  2026-07 scrape, date-filtered only — it still contains ~43 documents the new
  rule excludes (17 DPOs, 4 non-African, off-topic) and misses ~163 in-scope
  projects the new method finds.
- **New-method catalogue** (2026-07-21, verified): 275 in-scope projects
  (112 already on disk + 163 to download) + 476 to_screen projects.
  Gold-standard projects (TerrAfrica P149269, Kenya KACCAL, Uganda ACDP) all
  confirmed present.
- `renamed_long_paths.csv` maps 124 files renamed for the Windows 260-char
  path limit.

## Why the method changed (2026-07-21 comparison findings)

- Using the WB topic as a **query** filter lost real projects — topic coverage
  is incomplete on recent documents (Uganda ACDP, TerrAfrica). It is now
  fetched as **evidence** instead, and combined with title keywords.
- Regional projects are filed under `count="Africa"/"Eastern Africa"/...`, and
  some docs under `count="World"` (e.g. DRC Agriculture Rehabilitation) —
  country-only queries can never find them.
- The old abstract-based Africa screen admitted Yemen/Lebanon documents.
- The API's `strdate` date parameter returns wrong results when combined with
  other filters — dates are filtered client-side.
