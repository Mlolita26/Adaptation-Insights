##############################################################################
# sync_metadata.R — Refresh the repo's metadata/ folder from the corpus
#
# The document corpus (PDFs) lives on OneDrive and is NOT in git. This script
# copies the per-source metadata (CSV catalogues, download logs, RIS files)
# from the canonical location Data/Project_doc/{source}/List into the repo's
# metadata/ folder so GitHub always carries an up-to-date catalogue of what
# the corpus contains.
#
# Run after any scraper run or corpus reorganisation:
#   Rscript R/sync_metadata.R
##############################################################################

DATA_ROOT <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature/Data/Project_doc"

# repo root = parent of this script's directory (same logic as 00_config.R)
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
REPO <- if (length(file_arg) > 0) {
  normalizePath(file.path(dirname(sub("^--file=", "", file_arg[1])), ".."))
} else {
  getwd()
}

SOURCES <- c(worldbank = "Worldbank", gef = "gef", gcf = "gcf", afdb = "afdb")

for (i in seq_along(SOURCES)) {
  src  <- names(SOURCES)[i]
  from <- file.path(DATA_ROOT, SOURCES[i], "List")
  to   <- file.path(REPO, "metadata", src)
  dir.create(to, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(from)) {
    cat(sprintf("%-10s no List folder at %s — skipped\n", src, from))
    next
  }
  files <- list.files(from, full.names = TRUE)
  ok <- file.copy(files, to, overwrite = TRUE)
  cat(sprintf("%-10s copied %d/%d files\n", src, sum(ok), length(files)))
}
cat("Done. Review with git status, then commit.\n")
