##############################################################################
# run_corpus.R — resumable driver for full-corpus Session-1 extraction.
#
# Builds the corpus-wide manifest (all in-scope files, same folders as
# build_doc_index.R), SKIPS documents already extracted (any session1_*.csv
# in the corpus output folder counts), and processes the remainder in chunks
# by invoking R/extract_verbatim.R per chunk — so an interrupted run loses at
# most one chunk and simply resumes on the next invocation.
#
# Outputs land in data/extraction/corpus/ (isolated from pilot/holdout).
#
# Usage:
#   Rscript R/run_corpus.R                    # everything not yet extracted
#   Rscript R/run_corpus.R --source=af        # one source only
#   Rscript R/run_corpus.R --limit=20         # at most 20 documents this run
#   Rscript R/run_corpus.R --dry               # show plan + cost, extract nothing
#
# COST: ~USD 0.08-0.12 per document on gpt-5-mini (5 calls + occasional
# vision), so the full ~656-document corpus is roughly USD 55-75 run live.
# TODO (next iteration): OpenAI Batch API wiring would halve that (50%
# batch discount, 24h turnaround). It needs either ellmer >= 0.3
# (batch_chat_structured) or a request-JSONL builder; not wired yet to
# avoid upgrading ellmer under the validated 0.2.1 pipeline.
##############################################################################

suppressPackageStartupMessages({ library(readr) })

GL   <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature"
DATA <- file.path(GL, "03_Documents")
full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..")) else getwd()
OUT  <- file.path(REPO, "data", "extraction", "corpus")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
RSCRIPT <- file.path(R.home("bin"), "Rscript.exe")
EXTRACT <- file.path(REPO, "R", "extract_verbatim.R")
CHUNK <- 8

CORPUS_DIRS <- c(
  worldbank = "Worldbank/Docs/2015_2026",
  gef       = "gef/Docs/evaluation_docs/2015_2026",
  gcf       = "gcf/Docs/evaluation_docs",
  afdb      = "afdb/Docs/2015_2026",
  af        = "af/Docs/evaluation_docs",
  cif       = "cif/Docs/evaluation_docs")

args <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default = "") {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[1]) else default
}
SRC   <- opt("source")
LIMIT <- suppressWarnings(as.integer(opt("limit", "0")))
DRY   <- any(args == "--dry")

# manifest of the whole corpus
mf <- do.call(rbind, lapply(names(CORPUS_DIRS), function(s) {
  if (nzchar(SRC) && s != SRC) return(NULL)
  d <- file.path(DATA, CORPUS_DIRS[s])
  fs <- list.files(d, pattern = "\\.(pdf|PDF)$")
  if (!length(fs)) return(NULL)
  data.frame(project_code = paste0(s, ":", fs),
             pdf = file.path(d, fs), focus = "", stringsAsFactors = FALSE)
}))
cat("corpus files in scope:", nrow(mf), "\n")

# resume: skip documents already present in any session1 output here
done <- character(0)
for (f in list.files(OUT, pattern = "^session1_.*\\.csv$", full.names = TRUE)) {
  d <- tryCatch(read.csv(f, stringsAsFactors = FALSE), error = function(e) NULL)
  if (!is.null(d) && "document" %in% names(d)) done <- c(done, d$document)
}
mf <- mf[!basename(mf$pdf) %in% unique(done), , drop = FALSE]
cat("already extracted:", length(unique(done)), "| remaining:", nrow(mf), "\n")
if (LIMIT > 0 && nrow(mf) > LIMIT) mf <- mf[seq_len(LIMIT), , drop = FALSE]
cat("this run:", nrow(mf), "documents in", ceiling(nrow(mf) / CHUNK),
    sprintf("chunks | est. cost ~USD %.2f | est. time ~%d min\n",
            nrow(mf) * 0.10, ceiling(nrow(mf) * 3.5)))
if (DRY || !nrow(mf)) { cat(if (DRY) "dry run - stopping.\n" else "nothing to do.\n"); quit(save = "no") }

# child Rscript inherits these (system2's env= is unreliable on Windows)
Sys.setenv(EXTRACT_OUT_DIR = OUT, EXTRACT_MODE = "pilot")
chunks <- split(seq_len(nrow(mf)), ceiling(seq_len(nrow(mf)) / CHUNK))
for (ci in seq_along(chunks)) {
  cm <- mf[chunks[[ci]], , drop = FALSE]
  tmp <- file.path(OUT, sprintf("chunk_manifest_%03d.csv", ci))
  write.csv(cm, tmp, row.names = FALSE)
  cat(sprintf("\n#### chunk %d/%d (%d docs) ####\n", ci, length(chunks), nrow(cm)))
  status <- system2(RSCRIPT, args = shQuote(c(EXTRACT, tmp)), stdout = "", stderr = "")
  if (!identical(status, 0L)) cat("chunk", ci, "exited with status", status,
                                  "- continuing (resume will retry missing docs)\n")
  unlink(tmp)
}
cat("\ncorpus run pass complete. Re-run this script to resume/verify nothing is missing.\n")
