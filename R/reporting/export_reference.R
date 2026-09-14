##############################################################################
# export_reference.R - publish the gold-set reference extractions into
# 04_Extraction_Results, next to the pipeline's own output.
#
# Three things get compared every time the pipeline is scored, and until now
# two of them lived only as working CSVs in catalogues\. They belong beside
# the results, because "what should the extraction look like" is the first
# question anyone asks when they open a results file.
#
#   reading_reference_locations   308 location rows, produced by reading the
#                                 ten gold PDFs rather than by the pipeline.
#                                 The human-analog benchmark.
#   lucy_gold_locations            60 location rows, extracted by hand (v02)
#   lucy_gold_general              10 project rows, extracted by hand (v02)
#
# Neither reference is beyond question - both have known errors, listed in
# scores\location_extraction_comparison_2026-09-09.md. They are targets to
# measure against, not truth.
#
#   Rscript R/reporting/export_reference.R
##############################################################################

suppressPackageStartupMessages({ library(openxlsx) })

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", ".."), mustWork = TRUE)
source(file.path(REPO, "R", "shared", "paths.R"))

rd <- function(f) {
  d <- read.csv(f, stringsAsFactors = FALSE, colClasses = "character",
                check.names = FALSE)
  d[is.na(d)] <- ""
  d
}
src <- function(n) file.path(REPO, "catalogues", n)

sheets <- list(
  reading_reference_locations = src("claude_locations_reference.csv"),
  lucy_gold_locations         = src("gold_v1_locations.csv"),
  lucy_gold_general           = src("gold_v1_general.csv"))
missing <- names(sheets)[!file.exists(unlist(sheets))]
if (length(missing)) stop("missing reference file(s): ", paste(missing, collapse = ", "))

wb <- createWorkbook()
hdr <- createStyle(textDecoration = "bold", fgFill = "#EEEEEE", border = "bottom")
for (nm in names(sheets)) {
  d <- rd(sheets[[nm]])
  addWorksheet(wb, nm)
  writeData(wb, nm, d, headerStyle = hdr, withFilter = TRUE)
  freezePane(wb, nm, firstRow = TRUE)
  setColWidths(wb, nm, cols = seq_along(d),
               widths = pmin(46, pmax(11, nchar(names(d)) + 4)))
  cat(sprintf("  %-28s %4d rows  (%s)\n", nm, nrow(d), basename(sheets[[nm]])))
}

about <- data.frame(
  sheet = c("reading_reference_locations", "lucy_gold_locations",
            "lucy_gold_general", "", "generated", "regenerate with", "caution"),
  what = c(
    "The ten gold PDFs read end to end and extracted by hand-equivalent reading, not by the pipeline. 308 location rows. This is the human-analog benchmark: it shows what a careful reader finds, which is what the pipeline is trying to match. qc_flag marks rows the reader was unsure about.",
    "Lucy's manual extraction, working database v02. 60 location rows. The original gold standard.",
    "Lucy's manual extraction of the general sheet, v02. One row per project.",
    "",
    format(Sys.time(), "%Y-%m-%d %H:%M"),
    "Rscript 05_Pipeline/R/reporting/export_reference.R",
    "Neither reference is truth. Both have verified errors, listed in scores/location_extraction_comparison_2026-09-09.md (sections C and D). Read that before treating a disagreement as a pipeline mistake."),
  stringsAsFactors = FALSE)
addWorksheet(wb, "about")
writeData(wb, "about", about, headerStyle = hdr)
setColWidths(wb, "about", cols = 1:2, widths = c(30, 120))

out <- file.path(RESULTS_DIR, "gold_reference.xlsx")
writable <- function(p) {
  if (!file.exists(p)) return(TRUE)
  con <- suppressWarnings(try(file(p, "ab"), silent = TRUE))
  if (inherits(con, "try-error")) return(FALSE)
  close(con); TRUE
}
if (!writable(out)) {
  out <- sub("\\.xlsx$", format(Sys.time(), "_%Y%m%d_%H%M.xlsx"), out)
  cat("  NOTE: gold_reference.xlsx is open in Excel; writing a dated copy.\n")
}
saveWorkbook(wb, out, overwrite = TRUE)
cat("written:", out, "\n")
