##############################################################################
# zotero_upload.R — Push scraped document metadata to a Zotero library
#
# Uploads catalogue entries (one Zotero "report" item per document) from a
# scraper metadata CSV to a Zotero user or group library via the Web API.
# Items are tagged `wbdoc:{id}` and existing tags are checked first, so the
# script is idempotent — re-running skips everything already uploaded.
#
# ── One-time setup ──────────────────────────────────────────────────────────
# 1. Create a (group) library: https://www.zotero.org/groups → New Group.
#    The number in the group URL is the library ID.
#    (For a personal library: https://www.zotero.org/settings/keys shows
#    your userID; set LIBRARY_TYPE to "users".)
# 2. Create an API key with write access to that library:
#    https://www.zotero.org/settings/keys/new
# 3. Set the key as an environment variable so it is never committed:
#    Sys.setenv(ZOTERO_API_KEY = "...")   # or put it in .Renviron
#
# Usage: Rscript R/zotero_upload.R
##############################################################################

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(cli)
  library(glue)
})

# ── Configuration ───────────────────────────────────────────────────────────
LIBRARY_TYPE <- "groups"                       # "groups" or "users"
LIBRARY_ID   <- Sys.getenv("ZOTERO_LIBRARY_ID")  # e.g. "5678901"
API_KEY      <- Sys.getenv("ZOTERO_API_KEY")

METADATA_CSV <- file.path(
  "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature",
  "Data/Project_doc/Worldbank/List/worldbank_metadata.csv"
)
MIN_YEAR    <- 2015
SOURCE_TAG  <- "worldbank"
DOCID_PREFIX <- "wbdoc:"   # per-document tag used for duplicate detection

ZOTERO_BASE <- glue("https://api.zotero.org/{LIBRARY_TYPE}/{LIBRARY_ID}")
BATCH_SIZE  <- 50          # Zotero API maximum per write request

stopifnot(nzchar(API_KEY), nzchar(LIBRARY_ID))

zotero_headers <- function() {
  add_headers(
    "Zotero-API-Key"     = API_KEY,
    "Zotero-API-Version" = "3",
    "Content-Type"       = "application/json"
  )
}

# ── Fetch tags already in the library (for idempotent re-runs) ─────────────
fetch_existing_docids <- function() {
  cli_h2("Checking library for already-uploaded documents")
  existing <- character(0)
  start <- 0
  repeat {
    resp <- GET(
      glue("{ZOTERO_BASE}/tags?q={DOCID_PREFIX}&limit=100&start={start}"),
      zotero_headers()
    )
    stop_for_status(resp)
    tags <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                     simplifyDataFrame = TRUE)
    if (length(tags) == 0 || nrow(as.data.frame(tags)) == 0) break
    existing <- c(existing, as.data.frame(tags)$tag)
    n_total <- as.numeric(headers(resp)[["total-results"]])
    start <- start + 100
    if (is.na(n_total) || start >= n_total) break
  }
  existing <- existing[startsWith(existing, DOCID_PREFIX)]
  cli_alert_info("{length(existing)} documents already in library")
  sub(DOCID_PREFIX, "", existing, fixed = TRUE)
}

# ── Build one Zotero 'report' item from a metadata row ─────────────────────
build_item <- function(row) {
  pcodes <- paste(
    unlist(regmatches(row$project_id, gregexpr("P\\d{6}", row$project_id))),
    collapse = "; "
  )
  countries <- trimws(strsplit(coalesce(row$country, ""), "[;,]")[[1]])
  countries <- countries[nzchar(countries)]

  tags <- c(SOURCE_TAG, "ICR", paste0(DOCID_PREFIX, row$id), countries)

  list(
    itemType     = "report",
    title        = trimws(gsub("\\s+", " ", row$title)),
    creators     = list(list(creatorType = "author", name = "World Bank")),
    reportType   = coalesce(row$doc_type, ""),
    institution  = "World Bank",
    date         = substr(coalesce(row$doc_date, ""), 1, 10),
    language     = ifelse(coalesce(row$language, "NA") == "NA", "",
                          row$language),
    url          = coalesce(row$web_url, ""),
    abstractNote = ifelse(coalesce(row$abstract, "NA") == "NA", "",
                          trimws(gsub("\\s+", " ", row$abstract))),
    extra        = glue(
      "WB doc id: {row$id} | Project(s): {pcodes} | PDF: {row$pdf_url}"
    ),
    tags         = lapply(tags, function(t) list(tag = t))
  )
}

# ── Upload in batches ───────────────────────────────────────────────────────
upload_items <- function(items) {
  n_ok <- 0; n_fail <- 0
  batches <- split(items, ceiling(seq_along(items) / BATCH_SIZE))
  for (b in seq_along(batches)) {
    cli_alert_info("Uploading batch {b}/{length(batches)}")
    resp <- POST(
      glue("{ZOTERO_BASE}/items"),
      zotero_headers(),
      body = toJSON(unname(batches[[b]]), auto_unbox = TRUE)
    )
    stop_for_status(resp)
    res <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                    simplifyVector = FALSE)
    n_ok   <- n_ok + length(res$successful)
    n_fail <- n_fail + length(res$failed)
    if (length(res$failed) > 0) {
      for (f in res$failed) cli_alert_danger("Failed: {f$message}")
    }
    Sys.sleep(1)  # be polite to the API
  }
  cli_alert_success("Uploaded {n_ok} items ({n_fail} failed)")
}

# ── Main ────────────────────────────────────────────────────────────────────
main <- function() {
  cli_h1("Zotero upload — {SOURCE_TAG}")

  meta <- readr::read_csv(METADATA_CSV, show_col_types = FALSE) %>%
    mutate(year = suppressWarnings(as.integer(substr(doc_date, 1, 4)))) %>%
    filter(!is.na(year), year >= MIN_YEAR)
  cli_alert_info("{nrow(meta)} in-scope documents in metadata (>= {MIN_YEAR})")

  done <- fetch_existing_docids()
  todo <- meta %>% filter(!as.character(id) %in% done)
  cli_alert_info("{nrow(todo)} new documents to upload")
  if (nrow(todo) == 0) return(invisible())

  items <- lapply(seq_len(nrow(todo)), function(i) build_item(todo[i, ]))
  upload_items(items)
}

main()
