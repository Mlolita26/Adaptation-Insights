##############################################################################
# build_doc_index.R — one unified index: corpus FILENAME -> catalogue metadata
#
# Walks the in-scope corpus folders and matches every document file to its
# row in the per-source catalogues (catalogues/{source}/...). The index feeds
# deterministic PREFILL in extraction (title, year, project id, report no,
# link come from the catalogue, never from cover images or running headers).
#
# Per-source join keys (filenames were built by our own scrapers):
#   worldbank  P-code (P\d{6}) in the filename; doc id for renamed compact
#              files; disambiguation prefers ICR-type rows, then latest date
#   gef        exact filename in gef_evaluation_dates$file (+ title/url via
#              gef_all_documents on gef_id, preferring matching doc_type)
#   gcf        FP/SAP code = 2nd filename token, vs project_id
#   afdb       slugified catalogue title contained in the filename
#   af         project code = 2nd token vs project_id, then doc-type tokens
#   cif        slug (filename minus 'cif_' prefix) inside id or web_url
#
# Output: catalogues/doc_index.csv with match_method ('unmatched' rows kept so
# coverage is measurable). Run after any corpus or catalogue change:
#   Rscript R/build_doc_index.R
##############################################################################

suppressPackageStartupMessages({ library(readr); library(dplyr); library(stringr) })

GL   <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature"
DATA <- file.path(GL, "03_Documents")
full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..")) else getwd()
META <- file.path(REPO, "catalogues")

CORPUS_DIRS <- c(
  worldbank = "Worldbank/Docs/2015_2026",
  gef       = "gef/Docs/evaluation_docs/2015_2026",
  gcf       = "gcf/Docs/evaluation_docs",
  afdb      = "afdb/Docs/2015_2026",
  af        = "af/Docs/evaluation_docs",
  cif       = "cif/Docs/evaluation_docs")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a
slug <- function(x) {
  x <- suppressWarnings(iconv(x, "", "ASCII//TRANSLIT"))   # fold accents (French titles)
  gsub("^_+|_+$", "", gsub("_+", "_", gsub("[^a-z0-9]+", "_", tolower(x))))
}
yr   <- function(d) substr(as.character(d), 1, 4)
blank <- function(n) rep("", n)

idx_row <- function(file, source, title = "", year = "", project_id = "",
                    report_no = "", url = "", method = "unmatched") {
  tibble(filename = file, source = source, title = title, year = year,
         project_id = project_id, report_no = report_no, url = url,
         match_method = method)
}

rows <- list()
add <- function(r) rows[[length(rows) + 1]] <<- r

# ---------------------------------------------------------------- worldbank --
wb <- read_csv(file.path(META, "worldbank/wb_new_method_catalogue.csv"),
               show_col_types = FALSE)
wb$doc_date <- as.character(wb$doc_date)
files <- list.files(file.path(DATA, CORPUS_DIRS["worldbank"]))
for (f in files) {
  pcode <- str_extract(f, "P\\d{6}")
  docid <- str_extract(f, "(?<=_)\\d{7,9}(?=_)")
  cand <- wb[0, ]
  method <- "unmatched"
  if (!is.na(docid) && "id" %in% names(wb)) {
    cand <- wb[which(as.character(wb$id) == docid), ]
    if (nrow(cand)) method <- "wb:docid"
  }
  if (!nrow(cand) && !is.na(pcode)) {
    # catalogue project_id is verbose ('BJ-Project Name -- P166211'): containment
    cand <- wb[which(grepl(pcode, wb$project_id, fixed = TRUE)), ]
    if (nrow(cand) > 1) {
      icr <- cand[grepl("implementation completion", tolower(cand$doc_type)), ]
      if (nrow(icr)) cand <- icr
      cand <- cand[order(cand$doc_date, decreasing = TRUE), ][1, ]
      method <- "wb:pcode+icr"
    } else if (nrow(cand) == 1) method <- "wb:pcode"
  }
  if (nrow(cand)) {
    c1 <- cand[1, ]
    ttl <- sub("^\\s*Implementation Completion and Results Report( \\(ICR\\))?( Document)?\\s*[-:]\\s*",
               "", as.character(c1$title))
    pid <- str_extract(as.character(c1$project_id), "P\\d{6}") %||% as.character(c1$project_id)
    add(idx_row(f, "worldbank", ttl, yr(c1$doc_date), pid,
                as.character(c1$report_no %||% ""), as.character(c1$web_url %||% ""), method))
  } else add(idx_row(f, "worldbank"))
}

# --------------------------------------------------------------------- gef --
gdates <- read_csv(file.path(META, "gef/gef_evaluation_dates.csv"), show_col_types = FALSE)
gdocs  <- read_csv(file.path(META, "gef/gef_all_documents.csv"), show_col_types = FALSE)
files <- list.files(file.path(DATA, CORPUS_DIRS["gef"]))
for (f in files) {
  drow <- gdates[which(gdates$file == f), ]
  gid <- if (nrow(drow)) as.character(drow$gef_id[1]) else str_extract(f, "(?<=^gef_)\\d+")
  year <- if (nrow(drow)) as.character(drow$final_year[1]) else ""
  dt_file <- tolower(gsub("_", " ", sub("\\.[A-Za-z]+$", "", sub("^gef_\\d+_", "", f))))
  cand <- gdocs[which(as.character(gdocs$gef_id) == gid), ]
  pick <- cand[grepl(substr(dt_file, 1, 8), tolower(cand$doc_type), fixed = TRUE), ]
  if (!nrow(pick)) pick <- cand
  if (nrow(pick)) {
    p1 <- pick[1, ]
    add(idx_row(f, "gef", paste0(p1$project_title %||% "", ""), year, gid,
                "", as.character(p1$doc_url %||% ""),
                if (nrow(drow)) "gef:file+id" else "gef:id"))
  } else add(idx_row(f, "gef", year = year, project_id = gid %||% "",
                     method = if (!is.na(gid)) "gef:id-only" else "unmatched"))
}

# --------------------------------------------------------------------- gcf --
gcf <- read_csv(file.path(META, "gcf/gcf_cpe_metadata.csv"), show_col_types = FALSE)
files <- list.files(file.path(DATA, CORPUS_DIRS["gcf"]))
for (f in files) {
  code <- str_extract(f, "(?<=^gcf_)(FP|SAP)\\d+")
  cand <- if (!is.na(code)) gcf[which(grepl(code, gcf$project_id, fixed = TRUE)), ] else gcf[0, ]
  if (nrow(cand)) {
    c1 <- cand[order(nchar(cand$title))[1], ]   # shortest title = project name heuristic
    # family_year is the APPROVAL year, not publication - never prefill from it
    add(idx_row(f, "gcf", c1$title, yr(c1$doc_date %||% ""),
                code, "", as.character(c1$web_url %||% ""), "gcf:fpcode"))
  } else add(idx_row(f, "gcf", project_id = code %||% "",
                     method = if (!is.na(code)) "gcf:code-only" else "unmatched"))
}

# -------------------------------------------------------------------- afdb --
adb <- read_csv(file.path(META, "afdb/afdb_metadata.csv"), show_col_types = FALSE)
adb$tslug <- substr(slug(adb$title), 1, 45)
files <- list.files(file.path(DATA, CORPUS_DIRS["afdb"]))
for (f in files) {
  fslug <- slug(sub("\\.[A-Za-z]+$", "", f))
  hits <- which(nchar(adb$tslug) > 12 & vapply(adb$tslug, function(s)
    grepl(s, fslug, fixed = TRUE), logical(1)))
  if (length(hits) >= 1) {
    c1 <- adb[hits[1], ]
    add(idx_row(f, "afdb", c1$title,
                yr(c1$doc_date %||% c1$year %||% str_extract(f, "(?<=_)(19|20)\\d{2}(?=\\.)")),
                as.character(c1$project_id %||% ""), "",
                as.character(c1$web_url %||% ""),
                if (length(hits) == 1) "afdb:titleslug" else "afdb:titleslug-first"))
  } else add(idx_row(f, "afdb", year = str_extract(f, "(?<=_)(19|20)\\d{2}(?=\\.)") %||% ""))
}

# ---------------------------------------------------------------------- af --
af <- read_csv(file.path(META, "af/af_metadata.csv"), show_col_types = FALSE)
files <- list.files(file.path(DATA, CORPUS_DIRS["af"]))
for (f in files) {
  parts <- strsplit(sub("\\.[A-Za-z]+$", "", f), "_")[[1]]
  code <- if (length(parts) >= 2) parts[2] else ""
  fyear <- str_extract(f, "(19|20)\\d{2}")
  cand <- af[which(af$project_id == code), ]
  if (nrow(cand) > 1) {
    dt <- tolower(paste(parts[-c(1, 2)], collapse = " "))
    better <- cand[vapply(tolower(cand$doc_type), function(x)
      nzchar(x) && grepl(substr(x, 1, 6), dt, fixed = TRUE), logical(1)), ]
    if (nrow(better)) cand <- better
  }
  if (nrow(cand)) {
    c1 <- cand[1, ]
    add(idx_row(f, "af", c1$title, yr(c1$doc_date %||% c1$family_year %||% fyear),
                code, "", as.character(c1$web_url %||% ""), "af:code+type"))
  } else add(idx_row(f, "af", project_id = code, year = fyear %||% ""))
}

# --------------------------------------------------------------------- cif --
cif <- read_csv(file.path(META, "cif/cif_metadata.csv"), show_col_types = FALSE)
files <- list.files(file.path(DATA, CORPUS_DIRS["cif"]))
for (f in files) {
  s <- gsub("_+$", "", sub("^cif_", "", sub("\\.[A-Za-z]+$", "", f)))
  hits <- which(grepl(s, paste(cif$id, cif$web_url), fixed = TRUE))
  if (!length(hits)) {   # filenames may append _{year} after the slug
    s2 <- sub("_(19|20)\\d{2}$", "", s)
    if (s2 != s) hits <- which(grepl(s2, paste(cif$id, cif$web_url), fixed = TRUE))
  }
  if (length(hits) >= 1) {
    c1 <- cif[hits[1], ]
    add(idx_row(f, "cif", c1$title, yr(c1$doc_date %||% ""),
                as.character(c1$project_id %||% ""), "",
                as.character(c1$web_url %||% ""),
                if (length(hits) == 1) "cif:slug" else "cif:slug-first"))
  } else add(idx_row(f, "cif"))
}

# ------------------------------------------------------------------ output --
idx <- bind_rows(rows)
idx[is.na(idx)] <- ""
dupes <- idx$filename[duplicated(idx$filename)]
out <- file.path(META, "doc_index.csv")
write_csv(idx, out)
cat("doc_index:", nrow(idx), "files ->", out, "\n")
cat("duplicate filenames:", length(dupes), "\n")
cat("\ncoverage by source:\n")
print(idx %>% group_by(source) %>%
  summarise(files = n(),
            matched = sum(match_method != "unmatched"),
            with_title = sum(nzchar(title)),
            with_year = sum(nzchar(year) & year != "NA"),
            with_projid = sum(nzchar(project_id)), .groups = "drop"))
cat("\nmatch methods:\n"); print(table(idx$match_method))
