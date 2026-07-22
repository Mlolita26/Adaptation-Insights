##############################################################################
# zotero_upload.R — Sync the corpus catalogue to the shared Zotero library
#
# Pushes one Zotero "report" item per in-scope corpus document, for all
# pilot sources (World Bank, GEF, GCF, AfDB), reading the CURRENT canonical
# catalogues. Idempotent: every item carries a per-source id tag
# (wbdoc:/gefdoc:/afdbdoc:/gcfdoc:) and existing tags are checked first —
# re-running uploads only what is new.
#
# Credentials come from ~/.Renviron (never committed):
#   ZOTERO_API_KEY=...          # zotero.org/settings/keys (write access)
#   ZOTERO_LIBRARY_ID=...       # number in the group's URL
#   ZOTERO_LIBRARY_TYPE=groups  # or "users" for a personal library
#
# Usage: Rscript R/zotero_upload.R
##############################################################################

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(cli)
  library(glue)
  library(readr)
  library(stringr)
})

# ── Configuration ───────────────────────────────────────────────────────────
API_KEY      <- Sys.getenv("ZOTERO_API_KEY")
LIBRARY_ID   <- Sys.getenv("ZOTERO_LIBRARY_ID")
LIBRARY_TYPE <- Sys.getenv("ZOTERO_LIBRARY_TYPE", "groups")
stopifnot(nzchar(API_KEY), nzchar(LIBRARY_ID))

ZOTERO_BASE <- glue("https://api.zotero.org/{LIBRARY_TYPE}/{LIBRARY_ID}")
BATCH_SIZE  <- 50

DATA <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature/Data/Project_doc"

zotero_headers <- function() {
  add_headers(
    "Zotero-API-Key"     = API_KEY,
    "Zotero-API-Version" = "3",
    "Content-Type"       = "application/json"
  )
}

mk_item <- function(title, institution, date, url, report_type, extra, tags,
                    abstract = "") {
  list(
    itemType     = "report",
    title        = title,
    creators     = list(list(creatorType = "author", name = institution)),
    reportType   = coalesce(report_type, ""),
    institution  = institution,
    date         = coalesce(as.character(date), ""),
    url          = coalesce(url, ""),
    abstractNote = coalesce(abstract, ""),
    extra        = extra,
    tags         = lapply(unique(tags[nzchar(tags)]), function(t) list(tag = t))
  )
}

split_countries <- function(x) {
  trimws(strsplit(coalesce(x, ""), "[;,]")[[1]])
}

# ── Item builders (one per source, each returns list(items, id_tags)) ─────

build_worldbank <- function() {
  cat_path <- file.path(DATA, "Worldbank/List/wb_new_method_catalogue.csv")
  meta     <- read_csv(file.path(DATA, "Worldbank/List/worldbank_metadata.csv"),
                       show_col_types = FALSE, col_types = cols(.default = "c"))
  cat_df <- read_csv(cat_path, show_col_types = FALSE,
                     col_types = cols(.default = "c")) %>%
    filter(screen_status == "in_scope") %>%
    left_join(meta %>% select(id, abstract), by = "id")

  items <- lapply(seq_len(nrow(cat_df)), function(i) {
    r <- cat_df[i, ]
    pcodes <- paste(unlist(str_extract_all(coalesce(r$project_id, ""), "P\\d{6}")),
                    collapse = "; ")
    mk_item(
      title       = str_squish(r$title),
      institution = "World Bank",
      date        = substr(coalesce(r$doc_date, ""), 1, 10),
      url         = r$web_url,
      report_type = r$doc_type,
      extra       = glue("WB doc id: {r$id} | Project(s): {pcodes} | Topics: {coalesce(r$topics,'')} | PDF: {coalesce(r$pdf_url,'')}"),
      abstract    = ifelse(coalesce(r$abstract, "NA") == "NA", "", str_squish(coalesce(r$abstract, ""))),
      tags        = c("worldbank", split_countries(r$country), paste0("wbdoc:", r$id))
    )
  })
  list(items = items, tags = paste0("wbdoc:", cat_df$id))
}

build_gef <- function() {
  docs_dir <- file.path(DATA, "gef/Docs/evaluation_docs/2015_2026")
  files <- basename(list.files(docs_dir))
  dates <- read_csv(file.path(DATA, "gef/List/gef_evaluation_dates.csv"),
                    show_col_types = FALSE, col_types = cols(.default = "c")) %>%
    filter(file %in% files)
  meta <- read_csv(file.path(DATA, "gef/List/gef_all_documents.csv"),
                   show_col_types = FALSE, col_types = cols(.default = "c"))
  proj <- meta %>% group_by(gef_id) %>% slice(1) %>% ungroup()

  items <- lapply(seq_len(nrow(dates)), function(i) {
    r <- dates[i, ]
    p <- proj %>% filter(gef_id == r$gef_id)
    dtype <- str_replace_all(str_remove(r$doc_type, "_\\d+$"), "_", " ")
    title <- if (nrow(p) == 1) paste0(str_squish(p$project_title), " — ", dtype)
             else paste0("GEF ", r$gef_id, " — ", dtype)
    drow <- meta %>% filter(gef_id == r$gef_id, doc_type == dtype) %>% slice(1)
    mk_item(
      title       = title,
      institution = "Global Environment Facility",
      date        = r$final_year,
      url         = if (nrow(p) == 1) p$project_url else "",
      report_type = dtype,
      extra       = glue("GEF ID: {r$gef_id} | year from: {r$method} | PDF: {if (nrow(drow) == 1) coalesce(drow$doc_url, '') else ''}"),
      tags        = c("gef", if (nrow(p) == 1) split_countries(p$country),
                      paste0("gefdoc:", r$file))
    )
  })
  list(items = items, tags = paste0("gefdoc:", dates$file))
}

build_afdb <- function() {
  meta <- read_csv(file.path(DATA, "afdb/List/afdb_metadata.csv"),
                   show_col_types = FALSE, col_types = cols(.default = "c")) %>%
    filter(!is.na(doc_type), doc_type != "",
           suppressWarnings(as.integer(year)) >= 2015,
           suppressWarnings(as.integer(year)) <= 2025)

  items <- lapply(seq_len(nrow(meta)), function(i) {
    r <- meta[i, ]
    mk_item(
      title       = str_squish(r$title),
      institution = "African Development Bank",
      date        = if (grepl("^\\d{4}-", coalesce(r$doc_date, ""))) substr(r$doc_date, 1, 10) else r$year,
      url         = r$web_url,
      report_type = r$doc_type,
      extra       = glue("Project code: {coalesce(r$project_id,'')} | Listing: {coalesce(r$listing,'')} | PDF: {coalesce(r$pdf_url,'')}"),
      tags        = c("afdb", split_countries(r$country), paste0("afdbdoc:", r$id))
    )
  })
  list(items = items, tags = paste0("afdbdoc:", meta$id))
}

build_gcf <- function() {
  docs_dir <- file.path(DATA, "gcf/Docs/evaluation_docs")
  files <- basename(list.files(docs_dir))
  items <- lapply(files, function(f) {
    base <- tools::file_path_sans_ext(f)
    code <- str_match(base, "^gcf_([A-Z0-9]+)_")[, 2]
    dtype <- str_replace_all(str_remove(sub("^gcf_[A-Z0-9]+_", "", base), "_\\d+$"), "_", " ")
    mk_item(
      title       = glue("GCF {code} — {dtype}"),
      institution = "Green Climate Fund",
      date        = "",
      url         = glue("https://www.greenclimate.fund/project/{tolower(code)}"),
      report_type = dtype,
      extra       = glue("GCF project: {code} | file: {f}"),
      tags        = c("gcf", paste0("gcfdoc:", f))
    )
  })
  list(items = items, tags = paste0("gcfdoc:", files))
}

# ── Existing-tag fetch (idempotency) ───────────────────────────────────────
#' Reads the doc-id tags from the ITEMS themselves, not the /tags endpoint:
#' Zotero's tag search index lags behind uploads (verified 2026-07-22 —
#' relying on /tags right after an upload caused mass duplicates), while the
#' items listing is immediately consistent.
fetch_existing_tags <- function() {
  cli_h2("Checking library for already-uploaded documents")
  existing <- character(0)
  start <- 0
  repeat {
    resp <- GET(glue("{ZOTERO_BASE}/items?limit=100&start={start}&itemType=report"),
                zotero_headers())
    stop_for_status(resp)
    items <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                      simplifyVector = FALSE)
    if (length(items) == 0) break
    for (it in items) {
      tags <- vapply(it$data$tags, function(t) t$tag, character(1))
      existing <- c(existing, tags[grepl("^(wbdoc|gefdoc|afdbdoc|gcfdoc):", tags)])
    }
    total <- suppressWarnings(as.numeric(headers(resp)[["total-results"]]))
    start <- start + 100
    if (is.na(total) || start >= total) break
  }
  unique(existing)
}

# ── Upload ──────────────────────────────────────────────────────────────────
upload_items <- function(items, label) {
  if (length(items) == 0) {
    cli_alert_info("{label}: nothing new to upload")
    return(invisible(c(ok = 0, fail = 0)))
  }
  n_ok <- 0; n_fail <- 0
  batches <- split(items, ceiling(seq_along(items) / BATCH_SIZE))
  for (b in seq_along(batches)) {
    resp <- POST(glue("{ZOTERO_BASE}/items"), zotero_headers(),
                 body = toJSON(unname(batches[[b]]), auto_unbox = TRUE))
    if (status_code(resp) == 429) {
      wait <- suppressWarnings(as.numeric(headers(resp)[["retry-after"]]))
      Sys.sleep(ifelse(is.na(wait), 30, wait))
      resp <- POST(glue("{ZOTERO_BASE}/items"), zotero_headers(),
                   body = toJSON(unname(batches[[b]]), auto_unbox = TRUE))
    }
    stop_for_status(resp)
    res <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                    simplifyVector = FALSE)
    n_ok   <- n_ok + length(res$successful)
    n_fail <- n_fail + length(res$failed)
    if (length(res$failed) > 0) {
      for (f in res$failed) cli_alert_danger("  failed: {f$message}")
    }
    cli_alert_info("{label}: batch {b}/{length(batches)} done")
    Sys.sleep(1)
  }
  cli_alert_success("{label}: uploaded {n_ok} ({n_fail} failed)")
  invisible(c(ok = n_ok, fail = n_fail))
}

# ── Main ────────────────────────────────────────────────────────────────────
main <- function() {
  cli_h1("Zotero catalogue sync — {LIBRARY_TYPE}/{LIBRARY_ID}")
  done <- fetch_existing_tags()
  cli_alert_info("{length(done)} documents already in the library")

  sources <- list(
    `World Bank` = build_worldbank(),
    GEF          = build_gef(),
    AfDB         = build_afdb(),
    GCF          = build_gcf()
  )

  for (label in names(sources)) {
    s <- sources[[label]]
    new_ix <- which(!(s$tags %in% done))
    cli_h2("{label}: {length(s$items)} catalogued, {length(new_ix)} new")
    upload_items(s$items[new_ix], label)
  }
  cli_h2("Done")
}

main()
