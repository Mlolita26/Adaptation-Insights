##############################################################################
# gcf_gapfill.R — GCF evaluation-document gap-fill via the CPR API
#
# Our GCF corpus (scraped from greenclimate.fund) holds only 7 evaluation
# documents. The Climate Project Explorer / CPR index carries the GCF corpus
# too — this runner reuses the MCF client in af.R (same country sweep, cached)
# with prefix "GCF.", catalogues African GCF evaluation documents, and
# reports the diff against the existing on-disk GCF corpus before download.
#
# Usage: Rscript R/gcf_gapfill.R    (run AFTER a full af.R run so the family
#        sweep cache data/mcf_family_ids.csv exists)
##############################################################################

Sys.setenv(AF_MODE = "load")
.this_dir <- tryCatch({
  args <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", args, value = TRUE)
  if (length(fa)) dirname(sub("^--file=", "", fa[1])) else "R"
}, error = function(e) "R")
source(file.path(.this_dir, "00_config.R"))
source(file.path(.this_dir, "01_utils.R"))
source(file.path(.this_dir, "af.R"))

GCF_EXISTING_DIR <- file.path(
  "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature",
  "Data/Project_doc/gcf/Docs/evaluation_docs")

results <- run_mcf_scraper(prefix = "GCF.", source_name = "gcf_cpe")

# diff against the existing GCF corpus (codes like FP023 / SAP033 in filenames)
existing_codes <- unique(sub("^gcf_([A-Z0-9]+)_.*$", "\\1",
                             basename(list.files(GCF_EXISTING_DIR))))
kept <- results[results$status == "kept", ]
kept_codes <- unique(toupper(kept$project_id))
cli::cli_h2("Gap-fill diff")
cli::cli_alert_info("existing GCF evaluation docs cover projects: {paste(existing_codes, collapse=', ')}")
cli::cli_alert_info("CPE/CPR kept docs cover projects: {paste(head(kept_codes, 30), collapse=', ')}")
cli::cli_alert_success("new projects gained: {length(setdiff(kept_codes, existing_codes))}")
