##############################################################################
# screen_corpus.R — corpus label-verification sweep.
#
# The holdout validation found 3 of 10 randomly chosen corpus files
# mislabeled (a WB ISR filed as a GEF MTR; a management response filed as an
# AF MTE; a funding-approval year used as the publication year). This sweep
# checks EVERY in-scope corpus file: the first 3 pages go to a cheap model
# that answers only "what IS this document and from what year"; R then
# compares the answer against the type and year implied by our filename and
# writes a verdict per file. Nothing is renamed or moved — output is a
# review list for the team (the protocol's screening step, operationalised).
#
# Batched BTR-style: 8 documents per call. Near-empty first pages (image
# covers) fall back to a one-page vision call. Model: gpt-5-nano
# (SCREEN_MODEL to override). Cost for 656 files: well under $1.
#
# Usage: Rscript R/screen_corpus.R          (writes data/extraction/corpus_screen.csv)
##############################################################################

suppressPackageStartupMessages({
  library(ellmer); library(pdftools); library(readr); library(dplyr); library(stringr)
})

MODEL <- Sys.getenv("SCREEN_MODEL", "gpt-5-nano")
stopifnot(nzchar(Sys.getenv("OPENAI_API_KEY")))
GL   <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature"
DATA <- file.path(GL, "Data/Project_doc")
full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..")) else getwd()
OUT  <- file.path(REPO, "data", "extraction", "corpus_screen.csv")

CORPUS_DIRS <- c(
  worldbank = "Worldbank/Docs/2015_2026",
  gef       = "gef/Docs/evaluation_docs/2015_2026",
  gcf       = "gcf/Docs/evaluation_docs",
  afdb      = "afdb/Docs/2015_2026",
  af        = "af/Docs/evaluation_docs",
  cif       = "cif/Docs/evaluation_docs")

TYPES <- c("implementation completion report", "terminal evaluation",
  "mid-term evaluation", "impact evaluation report",
  "implementation status / progress report", "management response",
  "funding proposal / project document", "monitoring & evaluation report",
  "portfolio performance review / program evaluation",
  "policy brief / learning brief / factsheet",
  "administrative / meeting document", "other")

# what the FILENAME claims, per source convention
implied_type <- function(f, source) {
  k <- tolower(f)
  if (grepl("implementation_completion|_icr_", k)) return("implementation completion report")
  if (grepl("terminal_evaluation|final_evaluation|final-evaluation", k)) return("terminal evaluation")
  if (grepl("mid-?term", k)) return("mid-term evaluation")
  if (grepl("completion_report|completion_summary|_pcr_", k)) return("implementation completion report")
  if (grepl("evaluation", k)) return("terminal evaluation")   # generic 'evaluation' labels
  ""
}
implied_year <- function(f) {
  y <- str_extract(f, "(19|20)\\d{2}(?=[._])")
  if (is.na(y)) "" else y
}
digest8 <- function(x) sprintf("%08x", sum(utf8ToInt(x) * seq_along(utf8ToInt(x)) %% 97))

# acceptable screened types per implied type (strictness by design)
compatible <- list(
  "implementation completion report" = c("implementation completion report",
      "terminal evaluation", "monitoring & evaluation report"),
  "terminal evaluation" = c("terminal evaluation", "impact evaluation report",
      "implementation completion report", "monitoring & evaluation report",
      "portfolio performance review / program evaluation"),
  "mid-term evaluation" = c("mid-term evaluation"))

# ------------------------------------------------------------- collect docs --
docs <- list()
for (s in names(CORPUS_DIRS)) {
  d <- file.path(DATA, CORPUS_DIRS[s])
  for (f in list.files(d, pattern = "\\.(pdf|PDF)$")) {
    docs[[length(docs) + 1]] <- list(source = s, file = f,
                                     path = file.path(d, f))
  }
}
cat("screening", length(docs), "documents with", MODEL, "\n")

read3 <- function(path) {
  if (nchar(path) > 250) {
    short <- file.path(tempdir(), paste0("s", digest8(path), ".pdf"))
    ok <- suppressWarnings(file.copy(paste0("\\\\?\\", gsub("/", "\\\\", path)),
                                     short, overwrite = TRUE))
    if (!ok) ok <- file.copy(path, short, overwrite = TRUE)
    if (!ok) return(NULL)
    path <- short
  }
  tryCatch({
    n <- pdf_info(path)$pages
    txt <- pdf_text(path)[seq_len(min(3, n))]
    list(text = paste(txt, collapse = "\n"), path = path)
  }, error = function(e) NULL)
}

SYS <- paste(
  "You identify grey-literature documents from their first pages. Answer",
  "only from the text shown; never guess from the numbering asked about.",
  "The publication year is the year THIS DOCUMENT was issued (cover date,",
  "copyright, report date) - not a project approval or funding year.")

spec <- type_object(docs = type_array(items = type_object(
  i = type_integer("Input number."),
  doc_kind_stated = type_string("The document's own designation, verbatim from its pages (e.g. 'Implementation Status & Results Report', 'Rapport d'achevement'). Empty if none visible."),
  doc_type = type_enum(values = TYPES, description = "Best classification of what this document IS."),
  publication_year = type_string("Year this document was issued. Empty if not visible in these pages."),
  project_name = type_string("Project/program name if visible, else empty."),
  language = type_string("Main language: en/fr/pt/other."))))

BATCH <- 8
MAXCH <- 9000   # per-doc excerpt cap
rows <- list()
pending_vision <- list()

idx <- seq_along(docs)
chunks <- split(idx, ceiling(idx / BATCH))
for (ci in seq_along(chunks)) {
  ids <- chunks[[ci]]
  texts <- list(); use <- integer(0)
  for (i in ids) {
    r3 <- read3(docs[[i]]$path)
    if (is.null(r3)) {
      rows[[length(rows) + 1]] <- tibble(source = docs[[i]]$source,
        filename = docs[[i]]$file, doc_kind_stated = "", screened_type = "",
        screened_year = "", project_name = "", language = "",
        verdict = "UNREADABLE", note = "pdf_text failed")
      next
    }
    if (nchar(trimws(r3$text)) < 200) {           # image cover -> vision later
      pending_vision[[length(pending_vision) + 1]] <-
        c(i = i, path = r3$path)
      next
    }
    texts[[length(texts) + 1]] <- substr(r3$text, 1, MAXCH)
    use <- c(use, i)
  }
  if (!length(use)) next
  prompt <- paste0("FIRST PAGES OF ", length(use), " DOCUMENTS:\n\n",
    paste0(sprintf("=== DOCUMENT %d ===\n%s", seq_along(use),
                   unlist(texts)), collapse = "\n\n"))
  res <- tryCatch({
    chat_openai(model = MODEL, system_prompt = SYS)$chat_structured(prompt, type = spec)
  }, error = function(e) { warning("batch ", ci, ": ", conditionMessage(e)); NULL })
  m <- if (is.null(res)) list() else res$docs
  if (is.data.frame(m)) m <- lapply(seq_len(nrow(m)), function(k) as.list(m[k, ]))
  got <- rep(FALSE, length(use))
  for (mm in m) {
    j <- suppressWarnings(as.integer(mm$i))
    if (is.na(j) || j < 1 || j > length(use)) next
    i <- use[j]; got[j] <- TRUE
    rows[[length(rows) + 1]] <- tibble(source = docs[[i]]$source,
      filename = docs[[i]]$file,
      doc_kind_stated = as.character(mm$doc_kind_stated),
      screened_type = as.character(mm$doc_type),
      screened_year = as.character(mm$publication_year),
      project_name = as.character(mm$project_name),
      language = as.character(mm$language), verdict = "", note = "")
  }
  for (j in which(!got)) {
    i <- use[j]
    rows[[length(rows) + 1]] <- tibble(source = docs[[i]]$source,
      filename = docs[[i]]$file, doc_kind_stated = "", screened_type = "",
      screened_year = "", project_name = "", language = "",
      verdict = "NO_ANSWER", note = "")
  }
  cat(sprintf("batch %d/%d done (%d docs)\n", ci, length(chunks), length(use)))
}

# ------------------------------------------------ vision pass (image covers) --
if (length(pending_vision)) {
  cat("vision fallback for", length(pending_vision), "image-cover documents\n")
  for (pv in pending_vision) {
    i <- as.integer(pv["i"])
    png <- file.path(tempdir(), paste0("sc", digest8(pv["path"]), ".png"))
    ok <- tryCatch({ pdf_convert(pv["path"], format = "png", pages = 1,
                     filenames = png, dpi = 130, verbose = FALSE); TRUE },
                   error = function(e) FALSE)
    res <- if (ok) tryCatch({
      chat_openai(model = MODEL, system_prompt = SYS)$chat_structured(
        "Identify this document from its cover image.",
        content_image_file(png, resize = "none"),
        type = type_object(
          doc_kind_stated = type_string("Document's own designation, verbatim."),
          doc_type = type_enum(values = TYPES),
          publication_year = type_string("Year issued, empty if not visible."),
          project_name = type_string("Project name if visible."),
          language = type_string("en/fr/pt/other")))
    }, error = function(e) NULL) else NULL
    rows[[length(rows) + 1]] <- tibble(source = docs[[i]]$source,
      filename = docs[[i]]$file,
      doc_kind_stated = if (is.null(res)) "" else as.character(res$doc_kind_stated),
      screened_type = if (is.null(res)) "" else as.character(res$doc_type),
      screened_year = if (is.null(res)) "" else as.character(res$publication_year),
      project_name = if (is.null(res)) "" else as.character(res$project_name),
      language = if (is.null(res)) "" else as.character(res$language),
      verdict = "", note = "image cover (vision)")
  }
}

# -------------------------------------------------------- verdicts (in code) --
out <- bind_rows(rows)
out$implied_type <- vapply(out$filename, implied_type, character(1), source = "")
out$implied_year <- vapply(out$filename, implied_year, character(1))
mk_verdict <- function(k) {
  r <- out[k, ]
  if (nzchar(r$verdict)) return(r$verdict)         # UNREADABLE / NO_ANSWER
  v <- character(0)
  if (r$screened_type %in% c("management response", "funding proposal / project document",
      "implementation status / progress report", "administrative / meeting document",
      "policy brief / learning brief / factsheet"))
    v <- c(v, "NOT_AN_EVALUATION")
  if (nzchar(r$implied_type) && nzchar(r$screened_type) &&
      !(r$screened_type %in% (compatible[[r$implied_type]] %||% r$implied_type)))
    v <- c(v, "TYPE_MISMATCH")
  iy <- suppressWarnings(as.integer(r$implied_year))
  sy <- suppressWarnings(as.integer(str_extract(r$screened_year, "(19|20)\\d{2}")))
  if (!is.na(iy) && !is.na(sy) && abs(iy - sy) >= 2) v <- c(v, "YEAR_MISMATCH")
  if (!length(v)) "OK" else paste(v, collapse = "+")
}
`%||%` <- function(a, b) if (is.null(a)) b else a
out$verdict <- vapply(seq_len(nrow(out)), mk_verdict, character(1))
write_csv(out, OUT)

cat("\nwritten:", OUT, "\n\nverdicts:\n")
print(table(out$verdict))
cat("\nby source (flagged only):\n")
print(out %>% filter(verdict != "OK") %>% count(source, verdict))
