##############################################################################
# gef_doc_dates.R — Recover document dates for GEF evaluation documents
#
# The GEF website does not expose per-document dates, and
# gef_all_documents.csv has no date column. This script recovers a year for
# each file in Data/Project_doc/gef/Docs/evaluation_docs from, in order of
# trust:
#   1. year_text     — month+year dates on the first pages (PDF) or in the
#                      body text (docx); evaluation covers carry the report
#                      date; the latest such year is taken
#   2. year_filename — a 4-digit year embedded in the filename (PIRs etc.)
#   3. year_meta     — embedded creation metadata. Trusted for docx/xlsx
#                      (authoring date in docProps/core.xml). NOT used for
#                      PDFs: the GEF CDN regenerated files, so PDF creation
#                      dates cluster falsely on 2025.
#
# PDFs whose first pages yield almost no text are flagged scanned = TRUE
# (image-only, would need OCR). Legacy .doc/.xls and archives get no year
# here — handled separately.
#
# Output: Data/Project_doc/gef/List/gef_evaluation_dates.csv
# Usage:  "C:\Program Files\R\R-4.4.2\bin\Rscript.exe" R/gef_doc_dates.R
##############################################################################

suppressPackageStartupMessages(library(pdftools))

BASE <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature"
DOCS <- file.path(BASE, "Data/Project_doc/gef/Docs/evaluation_docs")
OUT  <- file.path(BASE, "Data/Project_doc/gef/List/gef_evaluation_dates.csv")

N_PAGES   <- 8     # pages of PDF text to scan for dates
MIN_CHARS <- 400   # less text than this over N_PAGES => treat as scanned

MONTHS_EN <- paste(month.name, collapse = "|")
MONTHS_FR <- "janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|octobre|novembre|décembre|decembre"
MONTHS_PT <- "janeiro|fevereiro|março|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro"
MONTHS_ES <- "enero|febrero|marzo|mayo|junio|julio|septiembre|octubre|noviembre|diciembre"
MONTHS <- paste(MONTHS_EN, MONTHS_FR, MONTHS_PT, MONTHS_ES, sep = "|")
# Month-name formats only. Numeric formats (06/2026, 2026-06-30) are
# deliberately excluded: evaluation fact-sheet tables list PLANNED closing
# dates in numeric form, which would win under the latest-year rule.
DATE_RE <- sprintf(paste0(
  "((\\d{1,2}\\s+)?\\b(%s)\\b\\.?,?\\s+(19|20)\\d{2})",   # [23 ]June 2019 / juin 2019
  "|(\\b(%s)\\b\\s+\\d{1,2},?\\s+(19|20)\\d{2})"          # June 23, 2019
), MONTHS, MONTHS)

year_from_text <- function(txt) {
  hits <- regmatches(txt, gregexpr(DATE_RE, txt, ignore.case = TRUE))[[1]]
  yrs <- as.integer(regmatches(hits, regexpr("(19|20)\\d{2}", hits)))
  yrs <- yrs[yrs >= 1991 & yrs <= 2026]
  if (length(yrs) == 0) NA_integer_ else max(yrs)
}

year_from_filename <- function(name) {
  yrs <- as.integer(regmatches(name, gregexpr("(19|20)\\d{2}", name))[[1]])
  yrs <- yrs[yrs >= 1991 & yrs <= 2026]
  if (length(yrs) == 0) NA_integer_ else max(yrs)
}

read_zip_entry <- function(path, entry) {
  # readLines(unz()) truncates; extract to a temp dir and read whole file
  tmp <- tempfile("zx")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  ok <- tryCatch({
    utils::unzip(path, files = entry, exdir = tmp, junkpaths = TRUE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok) return(NA_character_)
  f <- file.path(tmp, basename(entry))
  if (!file.exists(f)) return(NA_character_)
  readChar(f, file.size(f), useBytes = TRUE)
}

year_from_ooxml_meta <- function(path) {
  xml <- read_zip_entry(path, "docProps/core.xml")
  if (is.na(xml)) return(NA_integer_)
  m <- regmatches(xml, regexpr("<dcterms:created[^>]*>\\s*(\\d{4})", xml))
  if (length(m) == 0) return(NA_integer_)
  as.integer(sub(".*?(\\d{4})$", "\\1", m))
}

docx_body_text <- function(path, max_chars = 20000) {
  xml <- read_zip_entry(path, "word/document.xml")
  if (is.na(xml)) return("")
  txt <- gsub("<[^>]+>", " ", substr(xml, 1, max_chars * 5))
  substr(txt, 1, max_chars)
}

files <- list.files(DOCS, full.names = TRUE)
files <- files[!dir.exists(files)]
res <- vector("list", length(files))

for (i in seq_along(files)) {
  f    <- files[i]
  name <- basename(f)
  ext  <- tolower(tools::file_ext(f))
  gef_id   <- sub("^gef_(\\d+)_.*$", "\\1", name)
  doc_type <- sub("^gef_\\d+_(.*)\\.[^.]+$", "\\1", name)

  y_text <- NA_integer_; y_meta <- NA_integer_; scanned <- FALSE; deep <- FALSE
  if (ext == "pdf") {
    txt <- tryCatch({
      n <- pdf_info(f)$pages
      paste(suppressMessages(pdf_text(f))[seq_len(min(N_PAGES, n))],
            collapse = "\n")
    }, error = function(e) "")
    scanned <- nchar(gsub("\\s", "", txt)) < MIN_CHARS
    y_text  <- year_from_text(txt)
    if (is.na(y_text)) {
      # fallback: scan the whole document (dates often only in annexes)
      txt_all <- tryCatch(paste(suppressMessages(pdf_text(f)), collapse = "\n"),
                          error = function(e) "")
      y_text <- year_from_text(txt_all)
      if (!is.na(y_text)) deep <- TRUE
    }
  } else if (ext == "docx") {
    y_text <- year_from_text(docx_body_text(f))
    y_meta <- year_from_ooxml_meta(f)
  } else if (ext == "xlsx") {
    y_meta <- year_from_ooxml_meta(f)
  }
  y_file <- year_from_filename(sub("^gef_\\d+_", "", name))

  final <- NA_integer_; method <- "none"
  if (!is.na(y_text))       { final <- y_text; method <- if (deep) "text_deep" else "text" }
  else if (!is.na(y_file))  { final <- y_file; method <- "filename" }
  else if (!is.na(y_meta) && ext %in% c("docx", "xlsx") && y_meta > 1991) {
    final <- y_meta; method <- "ooxml_created"
  }

  res[[i]] <- data.frame(file = name, gef_id = gef_id, doc_type = doc_type,
                         ext = ext, scanned = scanned,
                         year_text = y_text, year_filename = y_file,
                         year_meta = y_meta, final_year = final,
                         method = method, stringsAsFactors = FALSE)
  if (i %% 25 == 0) cat(sprintf("  %d/%d\n", i, length(files)))
}

out <- do.call(rbind, res)
write.csv(out, OUT, row.names = FALSE)
cat(sprintf("Wrote %d rows to %s\n", nrow(out), OUT))
cat("\nMethod counts:\n"); print(table(out$method))
cat("\nScanned PDFs (need OCR):", sum(out$scanned), "\n")
cat("\nFinal year distribution:\n"); print(table(out$final_year, useNA = "ifany"))
cat("\nUndated by extension:\n")
print(table(out$ext[is.na(out$final_year)]))
