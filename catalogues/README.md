# catalogues/

Git-tracked MIRROR of the per-source document catalogues that live next to
the documents in `03_Documents/{source}/List/` (the originals), plus
pipeline-wide reference files: `doc_index.csv` (filename -> catalogue row,
feeds extraction prefill), the corrected gold standard, the holdout
reference, and the corpus screening results.

Do not edit the per-source files here - edit the List/ originals and run
`Rscript R/sync_metadata.R` to refresh this mirror.
