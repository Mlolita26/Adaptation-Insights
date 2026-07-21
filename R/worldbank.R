##############################################################################
# worldbank.R — World Bank Documents & Reports API Scraper
#
# Targets: EVALUATION documents only (scope decision 2026-07-17):
#          Implementation Completion and Results Reports (ICRs) and
#          Project Performance Assessment Reviews (PPARs),
#          2015+, Africa agriculture/adaptation.
#
# API docs: https://documents.worldbank.org/en/publication/documents-reports/api
# Base URL: https://search.worldbank.org/api/v3/wds
#
# Server-side filters (verified live 2026-07-21):
#   docty_exact    — evaluation document types only
#   count_exact    — each African country
#   teratopic_exact— WB's own topic classification ("Agriculture") — catches
#                    agriculture projects regardless of title wording
#   strdate        — document date floor 2015-01-01
#
# Strategy:
#   1. Query docty × African country × Agriculture topic, date >= 2015
#   2. Keyword queries (date-filtered) as a recall net for adaptation docs
#      not topic-tagged Agriculture
#   3. Deduplicate by document ID; relevance screen; drop budget-support
#      instruments (DPO/DPF/PRSC — policy lending, nothing implemented)
#   4. Download PDFs from documents1.worldbank.org with a browser UA
#      (documents.worldbank.org returns 403 to non-browser clients)
#
# Run modes via env var WB_MODE: probe | capped | load | full (default)
##############################################################################

# ── Setup ──────────────────────────────────────────────────────────────────
# Find and source config + utils. Works with Rscript, source(), and interactive R.
.find_r_dir <- function() {
  # returns the directory containing this script (the R/ folder)
  tryCatch({
    d <- dirname(sys.frame(2)$ofile)
    if (!is.null(d) && nzchar(d)) return(normalizePath(d, mustWork = FALSE))
  }, error = function(e) NULL)
  # Try commandArgs (works with Rscript)
  tryCatch({
    args <- commandArgs(trailingOnly = FALSE)
    fa <- grep("^--file=", args, value = TRUE)
    if (length(fa)) return(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
  }, error = function(e) NULL)
  # Fall back to working directory
  wd <- getwd()
  if (file.exists(file.path(wd, "R", "00_config.R"))) return(file.path(wd, "R"))
  if (file.exists(file.path(wd, "00_config.R"))) return(wd)
  return(wd)
}
if (!exists("PATHS")) {
  .r_dir <- .find_r_dir()
  source(file.path(.r_dir, "00_config.R"))
  source(file.path(.r_dir, "01_utils.R"))
}

DOWNLOAD_DIR <- file.path(PATHS$downloads, "worldbank")
dir.create(DOWNLOAD_DIR, recursive = TRUE, showWarnings = FALSE)

SOURCE_NAME <- "worldbank"

# ── World Bank API Configuration ───────────────────────────────────────────
WB_API_BASE <- "https://search.worldbank.org/api/v3/wds"

# Document types to search (exact match values for docty_exact)
WB_DOC_TYPES <- c(

  "Implementation Completion and Results Report",
  "Implementation Completion Report",
  "Project Performance Assessment Review"
)

# Fields to return in API response (teratopic = WB's own topic
# classification, used as keep/drop evidence in filter_relevant)
WB_FIELDS <- paste(
  "id", "display_title", "pdfurl", "docdt", "docty", "count",
  "repnme", "projn", "abstracts", "lang_exact", "url", "teratopic",
  sep = ","
)

# Keyword search queries (used for broader matching)
WB_KEYWORD_QUERIES <- c(
  "agriculture adaptation climate Africa",
  "climate resilience agriculture Africa",
  "climate smart agriculture Africa",
  "food security climate change Africa",
  "irrigation climate adaptation Africa",
  "livestock resilience Africa drought",
  "agricultural development climate Africa"
)

# ── Scope filters (team decision 2026-07-17) ───────────────────────────────
# Document date floor — applied CLIENT-SIDE on docdt. The API's strdate
# param is unreliable in combination with teratopic_exact/count_exact
# (verified 2026-07-21: Kenya+topic+strdate returns 0 despite matching
# docs existing). No ceiling: evaluations of 2015-2025 activity keep
# being published.
WB_MIN_YEAR <- 2015L

# WB topic classification used as KEEP EVIDENCE (not as a query filter:
# topic coverage is incomplete on recent documents — using it server-side
# verifiably loses in-scope projects, e.g. Uganda ACDP 2024, TerrAfrica).
# A document is kept if its topics include this OR its title matches
# agriculture/adaptation keywords.
WB_TOPICS <- c("Agriculture")

# Regional/global 'count' values: multi-country projects are NOT filed
# under their member countries (verified 2026-07-21: Regional Pastoral
# Livelihoods = 'Africa'; some docs even carry count='World', e.g. DRC
# Agriculture Rehabilitation). Swept in addition to the 54 countries.
WB_REGIONAL_COUNTS <- c(
  "Africa", "Eastern Africa", "Western Africa", "Southern Africa",
  "Central Africa", "Western and Central Africa",
  "Eastern and Southern Africa", "World"
)

# Budget-support / policy-lending instruments: excluded — nothing is
# implemented on the ground, so there are no adaptation actions to extract.
WB_EXCLUDE_TITLE_RE <- paste(
  "Development Policy", "Poverty Reduction Support", "Budget Support",
  "Policy Financing", "\\bDPO\\b", "\\bDPF\\b", "\\bDPL\\b", "\\bPRSC\\b",
  sep = "|"
)

# ── Helper: Build WB API URL ──────────────────────────────────────────────
build_wb_url <- function(qterm = NULL, docty = NULL, country = NULL,
                         topic = NULL, strdate = NULL,
                         rows = 50, offset = 0) {
  params <- list(
    format = "json",
    fl     = WB_FIELDS,
    rows   = rows,
    os     = offset
  )
  if (!is.null(qterm))   params$qterm          <- qterm
  if (!is.null(docty))   params$docty_exact    <- docty
  if (!is.null(country)) params$count_exact    <- country
  if (!is.null(topic))   params$teratopic_exact <- topic
  if (!is.null(strdate)) params$strdate        <- strdate

  url <- paste0(WB_API_BASE, "?", paste(
    mapply(function(k, v) paste0(k, "=", utils::URLencode(as.character(v), reserved = TRUE)),
           names(params), params),
    collapse = "&"
  ))
  url
}

# ── Helper: Parse WB API response ─────────────────────────────────────────
parse_wb_response <- function(json_data) {
  if (is.null(json_data)) return(tibble())

  # The API returns documents in a named list under "documents"
  docs <- json_data$documents
  if (is.null(docs) || length(docs) == 0) return(tibble())

  # Remove the "facets" entry if present
  docs[["facets"]] <- NULL

  records <- purrr::compact(purrr::map(docs, function(doc) {
    tryCatch({
      # Helper: safely flatten any field to a single character string
      flatten_field <- function(x) {
        if (is.null(x)) return(NA_character_)
        if (is.list(x)) return(paste(unlist(x), collapse = "; "))
        as.character(x)
      }
      
      tibble(
        id            = flatten_field(doc$id),
        title         = flatten_field(doc$display_title),
        pdf_url       = flatten_field(doc$pdfurl),
        doc_date      = flatten_field(doc$docdt),
        doc_type      = flatten_field(doc$docty),
        country       = flatten_field(doc$count),
        report_name   = flatten_field(doc$repnme),
        project_id    = flatten_field(doc$projn),
        abstract      = flatten_field(doc$abstracts),
        language      = flatten_field(doc$lang_exact),
        web_url       = flatten_field(doc$url),
        topics        = flatten_field(doc$teratopic)
      )
    }, error = function(e) NULL)
  }))
  
  if (length(records) == 0) return(tibble())
  bind_rows(records)
}

# ── Strategy 1: doc type × African country (recall-first, no topic) ───────
#' Fetches ALL evaluation docs per country; scope precision is applied in
#' filter_relevant() using the returned teratopic field + title keywords.
search_by_doctype_country <- function(countries = c(unname(WB_AFRICA_NAMES),
                                                    WB_REGIONAL_COUNTS)) {
  cli::cli_h2("Strategy 1: doc type × African country (recall-first)")

  all_results <- tibble()

  total_combos <- length(WB_DOC_TYPES) * length(countries)
  combo_count <- 0

  for (docty in WB_DOC_TYPES) {
    for (country in countries) {
      combo_count <- combo_count + 1

      if (combo_count %% 20 == 0) {
        cli::cli_alert_info("Progress: {combo_count}/{total_combos} combinations...")
      }

      offset <- 0
      page_size <- 50

      repeat {
        url <- build_wb_url(docty = docty, country = country,
                            rows = page_size, offset = offset)
        json <- safe_get_json(url)

        if (is.null(json)) break

        total <- as.numeric(json$total %||% 0)
        if (total == 0) break

        records <- parse_wb_response(json)
        if (nrow(records) == 0) break

        all_results <- bind_rows(all_results, records)
        offset <- offset + page_size

        if (offset >= total) break
      }
    }
  }

  cli::cli_alert_success("Strategy 1 found {nrow(all_results)} raw results")
  all_results
}

# ── Strategy 2: Keyword searches (recall net) ─────────────────────────────
#' Catches agriculture/adaptation evaluation docs the WB did not topic-tag
#' "Agriculture". Restricted to the evaluation doc types and the date floor.
search_by_keywords <- function(max_queries = length(WB_KEYWORD_QUERIES)) {
  cli::cli_h2("Strategy 2: Keyword-based searches (evaluation doc types)")

  all_results <- tibble()

  for (query in head(WB_KEYWORD_QUERIES, max_queries)) {
    cli::cli_alert_info("Searching: {query}")

    for (docty in WB_DOC_TYPES) {
      offset <- 0
      page_size <- 50
      max_results <- 500  # cap per query

      repeat {
        url <- build_wb_url(qterm = query, docty = docty,
                            rows = page_size, offset = offset)
        json <- safe_get_json(url)

        if (is.null(json)) break

        total <- as.numeric(json$total %||% 0)
        if (total == 0) break

        records <- parse_wb_response(json)
        if (nrow(records) == 0) break

        all_results <- bind_rows(all_results, records)
        offset <- offset + page_size

        if (offset >= total || offset >= max_results) break
      }
    }
  }

  cli::cli_alert_success("Strategy 2 found {nrow(all_results)} raw results")
  all_results
}

# ── Relevance filtering ───────────────────────────────────────────────────
filter_relevant <- function(results) {
  cli::cli_h2("Filtering for relevance")

  if (nrow(results) == 0) return(results)

  # Deduplicate by document ID
  results <- results %>% distinct(id, .keep_all = TRUE)
  cli::cli_alert_info("After dedup: {nrow(results)} documents")

  # Date floor (client-side; the API strdate param is unreliable)
  n_before <- nrow(results)
  results <- results %>%
    mutate(.yr = suppressWarnings(as.integer(substr(doc_date, 1, 4)))) %>%
    filter(is.na(.yr) | .yr >= WB_MIN_YEAR) %>%
    select(-.yr)
  cli::cli_alert_info("Date floor >= {WB_MIN_YEAR}: dropped {n_before - nrow(results)}")

  # Africa check on the COUNTRY FIELD (abstract mentions of "Africa"
  # previously admitted Yemen/Lebanon documents). Docs filed under
  # count='World' pass if the TITLE names an African country.
  africa_re <- paste(c("africa", tolower(AFRICA_COUNTRIES_EN)), collapse = "|")
  n_before <- nrow(results)
  results <- results %>%
    filter(
      grepl(africa_re, tolower(coalesce(country, ""))) |
      (grepl("world", tolower(coalesce(country, ""))) &
         grepl(africa_re, tolower(coalesce(title, ""))))
    )
  cli::cli_alert_info("Non-African country dropped: {n_before - nrow(results)}")

  # Three-way scope rule using the WB topic classification as evidence
  # (topic coverage is incomplete, especially on recent documents):
  #   in_scope : Agriculture among the WB topics, OR agriculture/adaptation
  #              keywords in the title/report name
  #   to_screen: neither of the above, but agriculture/adaptation keywords
  #              appear in the ABSTRACT — weak evidence, kept for screening
  #   (dropped): no positive signal in topics, title, or abstract
  results <- results %>%
    rowwise() %>%
    mutate(
      .ag_topic   = grepl("Agriculture", coalesce(topics, ""), fixed = TRUE),
      .kw = passes_relevance_fast(
        paste(coalesce(title, ""), coalesce(report_name, ""),
              coalesce(project_id, ""), sep = " "),
        require_africa = FALSE,
        require_sector = TRUE
      ),
      .kw_abstract = passes_relevance_fast(
        coalesce(abstract, ""),
        require_africa = FALSE,
        require_sector = TRUE
      ),
      screen_status = dplyr::case_when(
        .ag_topic | .kw ~ "in_scope",
        .kw_abstract    ~ "to_screen",
        TRUE            ~ "drop"
      )
    ) %>%
    ungroup()

  n_drop <- sum(results$screen_status == "drop")
  results <- results %>%
    filter(screen_status != "drop") %>%
    select(-.ag_topic, -.kw, -.kw_abstract)

  cli::cli_alert_success(paste0(
    "Scope rule: {sum(results$screen_status == 'in_scope')} in scope, ",
    "{sum(results$screen_status == 'to_screen')} to screen (abstract evidence only), ",
    "{n_drop} dropped (no positive signal)"))

  # Drop budget-support / policy-lending instruments (nothing implemented)
  n_before <- nrow(results)
  results <- results %>%
    filter(!grepl(WB_EXCLUDE_TITLE_RE,
                  paste(coalesce(title, ""), coalesce(report_name, "")),
                  ignore.case = FALSE))
  cli::cli_alert_info("Budget-support instruments dropped: {n_before - nrow(results)}")

  results
}

# ── Download one PDF (documents1 host + browser UA) ───────────────────────
#' documents.worldbank.org returns 403 Forbidden to non-browser clients.
#' Fetch from the documents1 CDN host with a browser User-Agent instead;
#' fall back to the original URL via the shared util. Validation mirrors
#' download_pdf() (min size + %PDF- magic, delete on fail).
WB_BROWSER_UA <- paste0(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ",
  "AppleWebKit/537.36 (KHTML, like Gecko) ",
  "Chrome/126.0.0.0 Safari/537.36"
)

wb_download_pdf <- function(url, dest) {
  if (file.exists(dest)) return("skipped")
  url1 <- sub("^https?://documents\\.worldbank\\.org",
              "https://documents1.worldbank.org", url)
  Sys.sleep(runif(1, HTTP_CONFIG$delay_min, HTTP_CONFIG$delay_max))
  resp <- tryCatch(
    httr::GET(url1, httr::user_agent(WB_BROWSER_UA),
              httr::timeout(HTTP_CONFIG$timeout_sec)),
    error = function(e) NULL
  )
  if (is.null(resp) || httr::status_code(resp) != 200) {
    # fall back to the original host (https), still with the browser UA —
    # some documents only resolve there; remaining failures are dead links
    resp <- tryCatch(
      httr::GET(sub("^http:", "https:", url), httr::user_agent(WB_BROWSER_UA),
                httr::timeout(HTTP_CONFIG$timeout_sec)),
      error = function(e) NULL
    )
    if (is.null(resp) || httr::status_code(resp) != 200) return(FALSE)
  }
  ok <- tryCatch({
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    writeBin(httr::content(resp, as = "raw"), dest)
    fsize <- file.info(dest)$size
    valid <- FALSE
    if (!is.na(fsize) && fsize >= HTTP_CONFIG$min_pdf_bytes) {
      con   <- file(dest, "rb")
      magic <- rawToChar(readBin(con, "raw", n = 5))
      close(con)
      valid <- identical(magic, "%PDF-")
    }
    if (!valid && file.exists(dest)) file.remove(dest)
    valid
  }, error = function(e) {
    if (file.exists(dest)) file.remove(dest)
    FALSE
  })
  ok
}

# ── Download PDFs ─────────────────────────────────────────────────────────
download_results <- function(results) {
  cli::cli_h2("Downloading PDFs")

  if (nrow(results) == 0) {
    cli::cli_alert_warning("No documents to download.")
    return(invisible(NULL))
  }

  # Filter to those with PDF URLs
  with_pdf <- results %>% filter(!is.na(pdf_url) & nchar(pdf_url) > 0)
  cli::cli_alert_info("{nrow(with_pdf)} documents have PDF URLs")

  success <- 0
  failed <- 0
  skipped <- 0

  for (i in seq_len(nrow(with_pdf))) {
    row <- with_pdf[i, ]

    # Build filename
    year <- tryCatch(
      format(as.Date(row$doc_date), "%Y"),
      error = function(e) "XXXX"
    )
    proj <- safe_filename(coalesce(row$project_id, "noproj"))
    dtype <- safe_filename(coalesce(row$doc_type, "doc"))
    fname <- glue("{SOURCE_NAME}_{proj}_{dtype}_{year}.pdf")
    dest <- file.path(DOWNLOAD_DIR, fname)

    # Check if already exists
    if (file.exists(dest)) {
      log_download(SOURCE_NAME, row$project_id, row$doc_type,
                   row$title, row$pdf_url, dest, "skipped",
                   "File already exists")
      skipped <- skipped + 1
      next
    }

    # Download
    result <- wb_download_pdf(row$pdf_url, dest)

    if (identical(result, TRUE)) {
      log_download(SOURCE_NAME, row$project_id, row$doc_type,
                   row$title, row$pdf_url, dest, "success")
      success <- success + 1
    } else if (identical(result, "skipped")) {
      log_download(SOURCE_NAME, row$project_id, row$doc_type,
                   row$title, row$pdf_url, dest, "skipped")
      skipped <- skipped + 1
    } else {
      log_download(SOURCE_NAME, row$project_id, row$doc_type,
                   row$title, row$pdf_url, dest, "failed",
                   "Download or validation failed")
      failed <- failed + 1
    }

    # Progress
    if (i %% 10 == 0) {
      cli::cli_alert_info("Progress: {i}/{nrow(with_pdf)} " %>%
        paste0("(OK: {success}, fail: {failed}, skip: {skipped})"))
    }
  }

  cli::cli_h3("Download Summary")
  cli::cli_alert_success("Success: {success}")
  cli::cli_alert_danger("Failed: {failed}")
  cli::cli_alert_info("Skipped: {skipped}")
  cli::cli_alert_info("No PDF URL: {nrow(results) - nrow(with_pdf)}")
}

# ── Save metadata ─────────────────────────────────────────────────────────
save_metadata <- function(results) {
  meta_path <- file.path(PATHS$data, "worldbank_metadata.csv")
  readr::write_csv(results, meta_path)
  cli::cli_alert_success("Metadata saved to: {meta_path}")
}

# ── Access/filter probe ────────────────────────────────────────────────────
#' One cheap query verifying the server-side filters work: Kenya ICRs with
#' the Agriculture topic and 2015+ date floor.
wb_probe <- function() {
  cli::cli_h2("World Bank API filter probe (Kenya ICRs)")
  base_url  <- build_wb_url(docty = WB_DOC_TYPES[1], country = "Kenya", rows = 0)
  topic_url <- build_wb_url(docty = WB_DOC_TYPES[1], country = "Kenya",
                            topic = WB_TOPICS[1], rows = 50)
  n_base <- as.numeric(safe_get_json(base_url)$total %||% -1)
  topic_json <- safe_get_json(topic_url)
  n_topic <- as.numeric(topic_json$total %||% -1)
  recs <- parse_wb_response(topic_json)
  n_2015 <- sum(suppressWarnings(as.integer(substr(recs$doc_date, 1, 4))) >= WB_MIN_YEAR,
                na.rm = TRUE)
  cli::cli_alert_info("Kenya ICRs, no filters:              {n_base}")
  cli::cli_alert_info("Kenya ICRs, Agriculture topic:       {n_topic}")
  cli::cli_alert_info("  of which >= {WB_MIN_YEAR} (client-side):   {n_2015}")
  ok <- n_base > 0 && n_topic > 0 && n_topic < n_base && n_2015 > 0
  if (ok) cli::cli_alert_success("Topic filter + client-side date floor working")
  else    cli::cli_alert_danger("Unexpected counts — check API params")
  invisible(c(base = n_base, topic = n_topic, in_scope = n_2015))
}

# ── Main execution ────────────────────────────────────────────────────────
run_worldbank_scraper <- function(countries = unname(WB_AFRICA_NAMES),
                                  max_keyword_queries = length(WB_KEYWORD_QUERIES)) {
  cli::cli_h1("World Bank Grey Literature Scraper")
  cli::cli_alert_info("Download directory: {DOWNLOAD_DIR}")
  cli::cli_alert_info("Scope: {paste(WB_DOC_TYPES, collapse=' | ')}; topic {paste(WB_TOPICS, collapse='/')}; date >= {WB_MIN_YEAR}")

  # Collect results from both strategies
  results1 <- search_by_doctype_country(countries)
  results2 <- search_by_keywords(max_keyword_queries)

  # Combine and deduplicate
  all_results <- bind_rows(results1, results2)
  cli::cli_alert_info("Total raw results: {nrow(all_results)}")

  # Filter for relevance
  relevant <- filter_relevant(all_results)

  # Save metadata before downloading
  save_metadata(relevant)

  # Download PDFs
  download_results(relevant)

  # Print summary
  print_source_summary(SOURCE_NAME)

  cli::cli_h2("Done!")
  invisible(relevant)
}

# Run if called directly. WB_MODE: probe | capped | load | full (default)
if (sys.nframe() == 0 || !interactive()) {
  switch(Sys.getenv("WB_MODE", "full"),
    probe  = wb_probe(),
    capped = run_worldbank_scraper(countries = c("Kenya", "Mozambique"),
                                   max_keyword_queries = 1),
    load   = invisible(NULL),   # source functions only, no run
    run_worldbank_scraper()
  )
}
