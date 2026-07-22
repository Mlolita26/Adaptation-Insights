##############################################################################
# zotero_upload.R — Sync the corpus catalogue to the shared Zotero library
#
# One Zotero "report" item per corpus document, organised in collections:
#   {Institution} / included | to screen | screened out
# The source document/project ID goes in the Report Number field.
#
# Idempotent: every item carries a per-source doc tag
# (wbdoc:/gefdoc:/afdbdoc:/gcfdoc:); existing items are read from the
# items listing (NOT the /tags endpoint, whose search index lags behind
# uploads) and are patched into the right collection / report number if
# needed instead of being re-created.
#
# Credentials from ~/.Renviron (never committed):
#   ZOTERO_API_KEY / ZOTERO_LIBRARY_ID / ZOTERO_LIBRARY_TYPE
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

API_KEY      <- Sys.getenv("ZOTERO_API_KEY")
LIBRARY_ID   <- Sys.getenv("ZOTERO_LIBRARY_ID")
LIBRARY_TYPE <- Sys.getenv("ZOTERO_LIBRARY_TYPE", "groups")
stopifnot(nzchar(API_KEY), nzchar(LIBRARY_ID))

ZOTERO_BASE <- glue("https://api.zotero.org/{LIBRARY_TYPE}/{LIBRARY_ID}")
BATCH_SIZE  <- 50

DATA <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature/Data/Project_doc"

SOURCES  <- c("World Bank", "GEF", "GCF", "AfDB")
STATUSES <- c("included", "to screen", "screened out")

zotero_headers <- function() {
  add_headers(
    "Zotero-API-Key"     = API_KEY,
    "Zotero-API-Version" = "3",
    "Content-Type"       = "application/json"
  )
}

# ── Collections: ensure {Institution}/{status} exist, return key map ───────
ensure_collections <- function() {
  cli_h2("Ensuring collection structure")
  cols <- list(); start <- 0
  repeat {
    resp <- GET(glue("{ZOTERO_BASE}/collections?limit=100&start={start}"),
                zotero_headers())
    stop_for_status(resp)
    js <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                   simplifyVector = FALSE)
    if (length(js) == 0) break
    cols <- c(cols, js)
    total <- suppressWarnings(as.numeric(headers(resp)[["total-results"]]))
    start <- start + 100
    if (is.na(total) || start >= total) break
  }
  existing <- bind_rows(lapply(cols, function(cc) {
    tibble(key = cc$key, name = cc$data$name,
           parent = ifelse(isFALSE(cc$data$parentCollection), "",
                           as.character(cc$data$parentCollection)))
  }))
  if (nrow(existing) == 0) existing <- tibble(key = character(),
                                              name = character(),
                                              parent = character())

  create <- function(name, parent = "") {
    payload <- list(list(name = name))
    if (nzchar(parent)) payload[[1]]$parentCollection <- parent
    resp <- POST(glue("{ZOTERO_BASE}/collections"), zotero_headers(),
                 body = toJSON(payload, auto_unbox = TRUE))
    stop_for_status(resp)
    res <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                    simplifyVector = FALSE)
    res$successful[["0"]]$key
  }

  keymap <- list()
  for (src in SOURCES) {
    top <- existing %>% filter(name == src, parent == "")
    top_key <- if (nrow(top) >= 1) top$key[1] else create(src)
    for (st in STATUSES) {
      sub <- existing %>% filter(name == st, parent == top_key)
      sub_key <- if (nrow(sub) >= 1) sub$key[1] else create(st, top_key)
      keymap[[paste(src, st, sep = "|")]] <- sub_key
    }
  }
  keymap
}

# ── Item constructor ────────────────────────────────────────────────────────
mk_item <- function(title, institution, date, url, report_type, report_number,
                    extra, tags, abstract = "", collection = NULL) {
  it <- list(
    itemType     = "report",
    title        = title,
    creators     = list(list(creatorType = "author", name = institution)),
    reportType   = coalesce(report_type, ""),
    reportNumber = coalesce(report_number, ""),
    institution  = institution,
    date         = coalesce(as.character(date), ""),
    url          = coalesce(url, ""),
    abstractNote = coalesce(abstract, ""),
    extra        = extra,
    tags         = lapply(unique(tags[nzchar(tags)]), function(t) list(tag = t))
  )
  if (!is.null(collection)) it$collections <- list(collection)
  it
}

split_countries <- function(x) trimws(strsplit(coalesce(x, ""), "[;,]")[[1]])

# Builders return a tibble: doctag, source, status, report_number + item payload
# in a list-column.

# ── World Bank ──────────────────────────────────────────────────────────────
build_worldbank <- function() {
  meta <- read_csv(file.path(DATA, "Worldbank/List/worldbank_metadata.csv"),
                   show_col_types = FALSE, col_types = cols(.default = "c"))
  cat_df <- read_csv(file.path(DATA, "Worldbank/List/wb_new_method_catalogue.csv"),
                     show_col_types = FALSE, col_types = cols(.default = "c")) %>%
    left_join(meta %>% select(id, abstract), by = "id")

  rows <- bind_rows(
    cat_df %>% filter(screen_status == "in_scope") %>% mutate(.status = "included"),
    cat_df %>% filter(screen_status == "to_screen", already_have == "TRUE") %>%
      mutate(.status = "to screen")
  )

  wb_one <- function(r, status) {
    pcodes <- paste(unlist(str_extract_all(coalesce(r$project_id, ""), "P\\d{6}")),
                    collapse = "; ")
    list(
      doctag = paste0("wbdoc:", r$id), source = "World Bank", status = status,
      item = mk_item(
        title = str_squish(r$title), institution = "World Bank",
        date = substr(coalesce(r$doc_date, ""), 1, 10), url = r$web_url,
        report_type = r$doc_type, report_number = r$id,
        extra = glue("Project(s): {pcodes} | Topics: {coalesce(r$topics,'')} | PDF: {coalesce(r$pdf_url,'')}"),
        abstract = ifelse(coalesce(r$abstract, "NA") == "NA", "",
                          str_squish(coalesce(r$abstract, ""))),
        tags = c("worldbank", split_countries(r$country), paste0("wbdoc:", r$id))
      )
    )
  }
  out <- lapply(seq_len(nrow(rows)), function(i) wb_one(rows[i, ], rows$.status[i]))

  # screened_out folder: match files back to the old metadata by P-codes+year
  so_dir <- file.path(DATA, "Worldbank/Docs/screened_out")
  so_files <- basename(list.files(so_dir))
  meta_ix <- meta %>%
    mutate(pkey = vapply(project_id, function(p)
             paste(sort(unlist(str_extract_all(coalesce(p, ""), "P\\d{6}"))),
                   collapse = "+"), character(1)),
           yr = substr(doc_date, 1, 4))
  for (f in so_files) {
    pcodes <- sort(unlist(str_extract_all(f, "P\\d{6}")))
    yr <- str_match(f, "_(\\d{4})\\.pdf$")[, 2]
    m <- meta_ix %>% filter(pkey == paste(pcodes, collapse = "+"), yr == !!yr)
    if (nrow(m) >= 1) {
      r <- m[1, ]
      out[[length(out) + 1]] <- wb_one(r, "screened out")
    } else {
      out[[length(out) + 1]] <- list(
        doctag = paste0("wbdoc:file:", f), source = "World Bank",
        status = "screened out",
        item = mk_item(
          title = str_squish(str_replace_all(tools::file_path_sans_ext(f), "_", " ")),
          institution = "World Bank", date = yr, url = "",
          report_type = "Implementation Completion and Results Report",
          report_number = "",
          extra = glue("file: {f}"),
          tags = c("worldbank", paste0("wbdoc:file:", f))
        )
      )
    }
  }
  out
}

# ── GEF ─────────────────────────────────────────────────────────────────────
build_gef <- function() {
  dates <- read_csv(file.path(DATA, "gef/List/gef_evaluation_dates.csv"),
                    show_col_types = FALSE, col_types = cols(.default = "c"))
  meta <- read_csv(file.path(DATA, "gef/List/gef_all_documents.csv"),
                   show_col_types = FALSE, col_types = cols(.default = "c"))
  proj <- meta %>% group_by(gef_id) %>% slice(1) %>% ungroup()

  folders <- list(
    `included`  = basename(list.files(file.path(DATA, "gef/Docs/evaluation_docs/2015_2026"))),
    `to screen` = basename(list.files(file.path(DATA, "gef/Docs/evaluation_docs/undated")))
  )

  out <- list()
  for (status in names(folders)) {
    rows <- dates %>% filter(file %in% folders[[status]])
    for (i in seq_len(nrow(rows))) {
      r <- rows[i, ]
      p <- proj %>% filter(gef_id == r$gef_id)
      dtype <- str_replace_all(str_remove(r$doc_type, "_\\d+$"), "_", " ")
      title <- if (nrow(p) == 1) paste0(str_squish(p$project_title), " — ", dtype)
               else paste0("GEF ", r$gef_id, " — ", dtype)
      drow <- meta %>% filter(gef_id == r$gef_id, doc_type == dtype) %>% slice(1)
      out[[length(out) + 1]] <- list(
        doctag = paste0("gefdoc:", r$file), source = "GEF", status = status,
        item = mk_item(
          title = title, institution = "Global Environment Facility",
          date = coalesce(r$final_year, ""),
          url = if (nrow(p) == 1) p$project_url else "",
          report_type = dtype, report_number = r$gef_id,
          extra = glue("GEF ID: {r$gef_id} | year from: {r$method} | PDF: {if (nrow(drow) == 1) coalesce(drow$doc_url, '') else ''}"),
          tags = c("gef", if (nrow(p) == 1) split_countries(p$country),
                   paste0("gefdoc:", r$file))
        )
      )
    }
  }
  out
}

# ── AfDB ────────────────────────────────────────────────────────────────────
build_afdb <- function() {
  meta <- read_csv(file.path(DATA, "afdb/List/afdb_metadata.csv"),
                   show_col_types = FALSE, col_types = cols(.default = "c")) %>%
    mutate(.yr = suppressWarnings(as.integer(year)),
           .status = case_when(
             is.na(doc_type) | doc_type == "" ~ "to screen",
             is.na(.yr)                        ~ "to screen",
             .yr >= 2015 & .yr <= 2025         ~ "included",
             TRUE                              ~ "screened out"
           ))

  lapply(seq_len(nrow(meta)), function(i) {
    r <- meta[i, ]
    list(
      doctag = paste0("afdbdoc:", r$id), source = "AfDB", status = r$.status,
      item = mk_item(
        title = str_squish(r$title), institution = "African Development Bank",
        date = if (grepl("^\\d{4}-", coalesce(r$doc_date, ""))) substr(r$doc_date, 1, 10)
               else coalesce(r$year, ""),
        url = r$web_url, report_type = r$doc_type,
        report_number = coalesce(r$project_id, ""),
        extra = glue("Listing: {coalesce(r$listing,'')} | PDF: {coalesce(r$pdf_url,'')}"),
        tags = c("afdb", split_countries(r$country), paste0("afdbdoc:", r$id))
      )
    )
  })
}

# ── GCF ─────────────────────────────────────────────────────────────────────
build_gcf <- function() {
  folders <- list(
    `included`     = basename(list.files(file.path(DATA, "gcf/Docs/evaluation_docs"))),
    `screened out` = basename(list.files(file.path(DATA, "gcf/Docs/proposal_stage")))
  )
  out <- list()
  for (status in names(folders)) {
    for (f in folders[[status]]) {
      base <- tools::file_path_sans_ext(f)
      code <- str_match(base, "^gcf_([A-Z0-9]+)_")[, 2]
      dtype <- str_replace_all(str_remove(sub("^gcf_[A-Z0-9]+_", "", base), "_\\d+$"), "_", " ")
      out[[length(out) + 1]] <- list(
        doctag = paste0("gcfdoc:", f), source = "GCF", status = status,
        item = mk_item(
          title = glue("GCF {code} — {dtype}"), institution = "Green Climate Fund",
          date = "", url = glue("https://www.greenclimate.fund/project/{tolower(code)}"),
          report_type = dtype, report_number = code,
          extra = glue("GCF project: {code} | file: {f}"),
          tags = c("gcf", paste0("gcfdoc:", f))
        )
      )
    }
  }
  out
}

# ── Existing items (key, version, doctag) — items listing, not /tags ───────
fetch_existing_items <- function() {
  cli_h2("Reading library items")
  rows <- list(); start <- 0
  repeat {
    resp <- GET(glue("{ZOTERO_BASE}/items?limit=100&start={start}&itemType=report"),
                zotero_headers())
    stop_for_status(resp)
    items <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                      simplifyVector = FALSE)
    if (length(items) == 0) break
    for (it in items) {
      tags <- vapply(it$data$tags, function(t) t$tag, character(1))
      doc <- tags[grepl("^(wbdoc|gefdoc|afdbdoc|gcfdoc):", tags)]
      colls <- unlist(it$data$collections)
      rows[[length(rows) + 1]] <- tibble(
        key = it$key, version = it$version,
        doctag = if (length(doc)) doc[1] else NA_character_,
        report_number = coalesce(it$data$reportNumber, ""),
        collections = paste(colls, collapse = ",")
      )
    }
    total <- suppressWarnings(as.numeric(headers(resp)[["total-results"]]))
    start <- start + 100
    if (is.na(total) || start >= total) break
  }
  if (length(rows) == 0) return(tibble(key = character(), version = integer(),
                                       doctag = character(),
                                       report_number = character(),
                                       collections = character()))
  bind_rows(rows)
}

# ── POST helper with 429 handling ───────────────────────────────────────────
post_batch <- function(payload) {
  resp <- POST(glue("{ZOTERO_BASE}/items"), zotero_headers(),
               body = toJSON(payload, auto_unbox = TRUE))
  if (status_code(resp) == 429) {
    wait <- suppressWarnings(as.numeric(headers(resp)[["retry-after"]]))
    Sys.sleep(ifelse(is.na(wait), 30, wait))
    resp <- POST(glue("{ZOTERO_BASE}/items"), zotero_headers(),
                 body = toJSON(payload, auto_unbox = TRUE))
  }
  stop_for_status(resp)
  fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
}

# ── Main ────────────────────────────────────────────────────────────────────
main <- function() {
  cli_h1("Zotero catalogue sync — {LIBRARY_TYPE}/{LIBRARY_ID}")

  keymap <- ensure_collections()
  existing <- fetch_existing_items()
  cli_alert_info("{nrow(existing)} items in the library")

  catalogue <- c(build_worldbank(), build_gef(), build_afdb(), build_gcf())
  cli_alert_info("{length(catalogue)} documents in the catalogue")

  # 1. create new items (with collection + report number)
  new_entries <- Filter(function(x) !(x$doctag %in% existing$doctag), catalogue)
  cli_h2("Creating {length(new_entries)} new items")
  if (length(new_entries) > 0) {
    items <- lapply(new_entries, function(x) {
      it <- x$item
      it$collections <- list(keymap[[paste(x$source, x$status, sep = "|")]])
      it
    })
    n_ok <- 0
    for (b in split(items, ceiling(seq_along(items) / BATCH_SIZE))) {
      res <- post_batch(unname(b))
      n_ok <- n_ok + length(res$successful)
      if (length(res$failed) > 0)
        for (f in res$failed) cli_alert_danger("  failed: {f$message}")
      Sys.sleep(1)
    }
    cli_alert_success("created {n_ok}")
  }

  # 2. patch existing items whose collection / report number is missing
  cat_ix <- setNames(catalogue, vapply(catalogue, function(x) x$doctag, character(1)))
  patches <- list()
  for (i in seq_len(nrow(existing))) {
    e <- existing[i, ]
    if (is.na(e$doctag) || is.null(cat_ix[[e$doctag]])) next
    x <- cat_ix[[e$doctag]]
    want_col <- keymap[[paste(x$source, x$status, sep = "|")]]
    want_rn  <- coalesce(x$item$reportNumber, "")
    need_col <- !grepl(want_col, e$collections, fixed = TRUE)
    need_rn  <- !identical(e$report_number, want_rn) && nzchar(want_rn)
    if (need_col || need_rn) {
      patches[[length(patches) + 1]] <- list(
        key = e$key, version = e$version,
        collections = list(want_col),
        reportNumber = want_rn
      )
    }
  }
  cli_h2("Patching {length(patches)} existing items (collection / report number)")
  if (length(patches) > 0) {
    n_ok <- 0
    for (b in split(patches, ceiling(seq_along(patches) / BATCH_SIZE))) {
      res <- post_batch(unname(b))
      n_ok <- n_ok + length(res$successful)
      if (length(res$failed) > 0)
        for (f in res$failed) cli_alert_danger("  failed: {f$message}")
      Sys.sleep(1)
    }
    cli_alert_success("patched {n_ok}")
  }

  cli_h2("Done")
}

main()
