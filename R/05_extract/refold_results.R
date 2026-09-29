# Re-apply the headline results rule to a finished Session 1 run without any
# new API call. Session 1 saves every result the model found in
# <out dir>/raw/s1_<document>_results.json; this script reads those files,
# runs results_gate() and choose_headline() again and rewrites the three result
# slots, result_notes, results_all_n and evidence_depth of the Session 1 CSV.
#
#   Rscript R/05_extract/refold_results.R --session1=<session1.csv> --manifest=<manifest.csv> [--out=<csv>]
#
# The manifest gives the PDF of each document so the AfDB dot-thousands repair
# can look at the page text (pdftotext). Output defaults to
# <session1 name>_refold.csv next to the input. (28 Sep 2026)

args <- commandArgs(trailingOnly = TRUE)
opt <- function(k, default = "") { v <- sub(paste0("^--", k, "="), "", grep(paste0("^--", k, "="), args, value = TRUE)); if (length(v)) v[1] else default }
s1_f <- opt("session1"); mf_f <- opt("manifest"); out_f <- opt("out")
stopifnot(nzchar(s1_f), nzchar(mf_f))
if (!nzchar(out_f)) out_f <- sub("\\.csv$", "_refold.csv", s1_f)
full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", "..")) else getwd()
suppressPackageStartupMessages(library(jsonlite))
source(file.path(REPO, "R", "00_shared", "clean_fields.R"))
source(file.path(REPO, "R", "00_shared", "results_rank.R"))

s1 <- read.csv(s1_f, check.names = FALSE, stringsAsFactors = FALSE, colClasses = "character"); s1[is.na(s1)] <- ""
mf <- read.csv(mf_f, stringsAsFactors = FALSE, colClasses = "character"); mf[is.na(mf)] <- ""
raw_dir <- file.path(dirname(s1_f), "raw")
pdf_of <- setNames(mf$pdf, basename(mf$pdf))

page_text <- function(pdf) {
  if (!nzchar(pdf) || !file.exists(pdf)) return(NULL)
  txt <- tryCatch(system2("pdftotext", c("-layout", shQuote(pdf), "-"), stdout = TRUE, stderr = FALSE), error = function(e) NULL)
  if (is.null(txt)) return(NULL)
  # pdftotext writes UTF-8; bytes the R locale cannot read would break the
  # page split and every grepl, and only ASCII digits matter here
  txt <- iconv(txt, from = "UTF-8", to = "ASCII", sub = " ")
  strsplit(paste(txt, collapse = "\n"), "\f", fixed = TRUE)[[1]]
}
# several focus projects can share one document (the GEF Food Systems
# evaluation is P002, P003 and P004): their raw files collide, so those rows
# keep the values folded at extraction time
dup_docs <- names(which(table(s1$document) > 1))

changed <- 0L
for (i in seq_len(nrow(s1))) {
  doc <- s1$document[i]; doc_name <- tools::file_path_sans_ext(doc); pc <- s1$project_code_hint[i]
  jf_pc <- file.path(raw_dir, paste0("s1_", pc, "_", substr(doc_name, 1, 55), "_results.json"))
  jf <- if (nzchar(pc) && file.exists(jf_pc)) jf_pc else file.path(raw_dir, paste0("s1_", substr(doc_name, 1, 55), "_results.json"))
  if (doc %in% dup_docs && !file.exists(jf_pc)) { cat(sprintf("  %-6s shared document, raw file ambiguous: kept as extracted\n", pc)); next }
  if (!file.exists(jf)) { cat(sprintf("  %-6s no raw results file: %s\n", pc, basename(jf))); next }
  res <- fromJSON(jf, simplifyVector = FALSE)
  rl <- res$results %||% list()
  pdf <- pdf_of[[doc]] %||% ""
  pages <- if (identical(s1$family_module[i], "afdb_pcr")) page_text(pdf) else NULL
  rl <- results_gate(rl, s1$family_module[i], pages)
  failed <- Filter(function(r) identical(r$status, "not achieved"), rl)
  ch <- choose_headline(rl); top <- ch$top
  before <- paste(s1[i, c("result1", "result2", "result3")], collapse = " | ")
  for (k in 1:3) {
    r <- if (length(top) >= k) top[[k]] else NULL
    s1[i, paste0("result", k)] <- if (is.null(r)) "" else as.character(r$value)
    s1[i, paste0("result", k, "_metric_stated")] <- if (is.null(r)) "" else as.character(r$metric_stated %||% "")
    s1[i, paste0("result", k, "_unit_stated")]   <- if (is.null(r)) "" else as.character(r$unit_stated %||% "")
    s1[i, paste0("result", k, "_scope")] <- if (is.null(r)) "" else as.character(r$scope %||% "")
    s1[i, paste0("result", k, "_page")]  <- if (is.null(r)) "" else as.character(r$page %||% "")
  }
  extra <- if (length(ch$rest)) paste0("further results: ", paste(vapply(ch$rest, function(r)
    paste0(r$value, " ", r$metric_stated, " (", r$scope %||% "", ", p", r$page %||% "", ")"), character(1)), collapse = "; ")) else ""
  fails <- if (length(failed)) paste0("NOT achieved: ", paste(vapply(failed, function(r)
    paste0(r$metric_stated, " (", r$value, ", p", r$page %||% "", ")"), character(1)), collapse = "; ")) else ""
  notes <- as.character(res$result_notes %||% "")
  s1$result_notes[i] <- paste(Filter(nzchar, c(notes, fails, extra)), collapse = " | ")
  s1$results_all_n[i] <- as.character(length(rl))
  s1$evidence_depth[i] <- if (length(rl)) "2" else "1"
  after <- paste(s1[i, c("result1", "result2", "result3")], collapse = " | ")
  if (!identical(before, after)) changed <- changed + 1L
  cat(sprintf("  %-6s %s  ->  %s\n", s1$project_code_hint[i], before, after))
}
write.csv(s1, out_f, row.names = FALSE, na = "")
cat(sprintf("\n%d of %d documents changed; written: %s\n", changed, nrow(s1), out_f))
