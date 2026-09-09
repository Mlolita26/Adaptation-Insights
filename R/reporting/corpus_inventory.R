##############################################################################
# corpus_inventory.R — census of the document corpus (03_Documents)
#
# Writes 03_Documents/Corpus_Inventory.xlsx with three sheets:
#   overview — one row per source: how many docs, in scope vs parked,
#              how many are attached in the Zotero group library, totals
#   folders  — one row per subfolder: status, file count, size, Zotero count
#   files    — every file: status, size, in Zotero, in doc_index,
#              corpus-screen verdict
#
# No LLM calls. Zotero is read via the web API (read-only); if the API is
# unreachable the in_zotero columns are left blank and the overview says so.
# Rerun any time:  Rscript R/reporting/corpus_inventory.R
##############################################################################

suppressPackageStartupMessages({
  library(httr); library(jsonlite); library(openxlsx)
})

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", ".."),
                      mustWork = TRUE)
source(file.path(REPO, "R", "shared", "paths.R"))

OUT_XLSX <- file.path(DOCS_ROOT, "Corpus_Inventory.xlsx")

## ── 1. walk 03_Documents ───────────────────────────────────────────────────
all_files <- list.files(DOCS_ROOT, recursive = TRUE, full.names = FALSE)
all_files <- all_files[!grepl("^~\\$", basename(all_files))]          # Office locks
all_files <- all_files[basename(all_files) != "Corpus_Inventory.xlsx"]
all_files <- all_files[basename(all_files) != "README.md"]

top <- sub("/.*$", "", all_files)
src_map <- c(Worldbank = "worldbank", gef = "gef", gcf = "gcf",
             afdb = "afdb", af = "af", cif = "cif", pilot_gold = "pilot_gold")
source_of <- unname(src_map[top]); source_of[is.na(source_of)] <- top[is.na(source_of)]

rel_dir <- dirname(all_files); rel_dir[rel_dir == "."] <- ""
fname   <- basename(all_files)
ext     <- tolower(tools::file_ext(fname))
size_mb <- round(file.info(file.path(DOCS_ROOT, all_files))$size / 1e6, 2)

status_of <- function(src, dir_rel) {
  if (src == "pilot_gold")                 return("pilot gold set")
  scope <- CORPUS_DIRS[src]
  if (!is.na(scope) && startsWith(paste0(dir_rel, "/"), paste0(scope, "/")))
                                           return("in scope (evaluation corpus)")
  if (grepl("(^|/)List(/|$)", dir_rel))    return("metadata (List)")
  return("parked")
}
status <- mapply(status_of, source_of, rel_dir, USE.NAMES = FALSE)
# the parked reason is the first folder below Docs/ (e.g. funding_proposals)
parked_reason <- ifelse(status == "parked",
                        sub("^.*?Docs/?", "", rel_dir), "")

files <- data.frame(source = source_of, folder = rel_dir, filename = fname,
                    ext = ext, size_mb = size_mb, status = status,
                    parked_reason = parked_reason, stringsAsFactors = FALSE)
cat("files found under 03_Documents:", nrow(files), "\n")

## ── 2. Zotero attachments (read-only) ──────────────────────────────────────
zotero_files <- NULL; zotero_note <- ""
zkey <- Sys.getenv("ZOTERO_API_KEY"); zlib <- Sys.getenv("ZOTERO_LIBRARY_ID")
if (nzchar(zkey) && nzchar(zlib)) {
  zotero_files <- tryCatch({
    fn <- character(0); start <- 0
    repeat {
      r <- GET(sprintf("https://api.zotero.org/groups/%s/items", zlib),
               query = list(itemType = "attachment", format = "json",
                            limit = 100, start = start),
               add_headers(`Zotero-API-Key` = zkey, `Zotero-API-Version` = "3"),
               timeout(60))
      stop_for_status(r)
      js <- fromJSON(content(r, "text", encoding = "UTF-8"), simplifyVector = FALSE)
      fn <- c(fn, vapply(js, function(it) {
        f <- it$data$filename; if (is.null(f)) "" else f
      }, character(1)))
      total <- as.integer(headers(r)[["total-results"]])
      start <- start + 100
      if (start >= total || length(js) == 0) break
    }
    unique(tolower(fn[nzchar(fn)]))
  }, error = function(e) { zotero_note <<- conditionMessage(e); NULL })
}
if (is.null(zotero_files)) {
  cat("Zotero API not available (", zotero_note, ") — in_zotero left blank\n")
  files$in_zotero <- NA
} else {
  cat("Zotero attachments in the group library:", length(zotero_files), "\n")
  files$in_zotero <- tolower(files$filename) %in% zotero_files
  # only document files are expected in Zotero; blank out the metadata rows
  files$in_zotero[files$status == "metadata (List)"] <- NA
}

## ── 3. doc_index membership + corpus-screen verdicts ───────────────────────
idx_path <- file.path(REPO, "catalogues", "doc_index.csv")
idx_names <- if (file.exists(idx_path)) {
  idx <- read.csv(idx_path, stringsAsFactors = FALSE)
  tolower(basename(idx$filename))
} else character(0)
files$in_doc_index <- tolower(files$filename) %in% idx_names
files$in_doc_index[!files$status %in% "in scope (evaluation corpus)"] <- NA

scr_path <- file.path(REVIEW_DIR, "corpus_screen.csv")
files$screen_verdict <- ""; files$screen_note <- ""
if (file.exists(scr_path)) {
  scr <- read.csv(scr_path, stringsAsFactors = FALSE)
  m <- match(tolower(files$filename), tolower(scr$filename))
  files$screen_verdict <- ifelse(is.na(m), "", scr$verdict[m])
  files$screen_note    <- ifelse(is.na(m), "", scr$note[m])
}

## ── 4. build the three sheets ──────────────────────────────────────────────
n_or_blank <- function(x) if (all(is.na(x))) "" else sum(x, na.rm = TRUE)

per_source <- lapply(split(files, files$source), function(g) {
  ins <- g[g$status == "in scope (evaluation corpus)", ]
  data.frame(
    source            = g$source[1],
    total_files       = nrow(g),
    total_size_mb     = round(sum(g$size_mb, na.rm = TRUE), 1),
    in_scope_docs     = nrow(ins),
    in_zotero         = if (is.null(zotero_files)) "" else
                          sum(ins$in_zotero, na.rm = TRUE),
    missing_in_zotero = if (is.null(zotero_files)) "" else
                          sum(!ins$in_zotero, na.rm = TRUE),
    parked_files      = sum(g$status == "parked"),
    gold_set_files    = sum(g$status == "pilot gold set"),
    metadata_files    = sum(g$status == "metadata (List)"),
    screen_flagged    = sum(ins$screen_verdict != "" &
                            toupper(ins$screen_verdict) != "OK", na.rm = TRUE),
    stringsAsFactors  = FALSE)
})
overview <- do.call(rbind, per_source)
num_cols <- vapply(overview, is.numeric, logical(1))
tot <- overview[1, ]; tot$source <- "TOTAL"
for (cn in names(overview)[num_cols]) tot[[cn]] <- sum(overview[[cn]])
for (cn in c("in_zotero", "missing_in_zotero"))
  tot[[cn]] <- if (any(overview[[cn]] == "")) "" else
                 sum(as.integer(overview[[cn]]))
overview <- rbind(overview, tot)

folders <- do.call(rbind, lapply(split(files, paste(files$source, files$folder)),
  function(g) data.frame(
    source = g$source[1], folder = g$folder[1], status = g$status[1],
    n_files = nrow(g), n_pdf = sum(g$ext == "pdf"),
    size_mb = round(sum(g$size_mb, na.rm = TRUE), 1),
    n_in_zotero = n_or_blank(g$in_zotero), stringsAsFactors = FALSE)))
folders <- folders[order(folders$source, folders$folder), ]

files_out <- files[order(files$source, files$folder, files$filename),
                   c("source", "status", "folder", "filename", "ext", "size_mb",
                     "in_zotero", "in_doc_index", "screen_verdict",
                     "screen_note", "parked_reason")]

## ── 5. write the workbook ──────────────────────────────────────────────────
wb <- createWorkbook()
hdr <- createStyle(textDecoration = "bold", border = "bottom")
add <- function(name, df, widths) {
  addWorksheet(wb, name)
  writeData(wb, name, df, headerStyle = hdr, withFilter = TRUE)
  freezePane(wb, name, firstRow = TRUE)
  setColWidths(wb, name, cols = seq_along(df), widths = widths)
}
add("overview", overview, c(12, rep(14, ncol(overview) - 1)))
add("folders",  folders,  c(12, 45, 28, 9, 9, 9, 12))
add("files",    files_out, c(12, 26, 40, 60, 6, 9, 10, 12, 24, 40, 24))
info <- data.frame(what = c("generated", "generated by", "zotero library",
                            "zotero status", "note"),
  value = c(format(Sys.time(), "%Y-%m-%d %H:%M"),
            "05_Pipeline/R/reporting/corpus_inventory.R (rerun any time)",
            zlib,
            if (is.null(zotero_files)) paste("unavailable:", zotero_note)
            else sprintf("%d attachments read", length(zotero_files)),
            "in_zotero matches on exact filename; a doc renamed in Zotero shows as missing"))
add("about", info, c(16, 90))
saveWorkbook(wb, OUT_XLSX, overwrite = TRUE)
cat("written:", OUT_XLSX, "\n")
print(overview, row.names = FALSE)
