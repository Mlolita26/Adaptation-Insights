##############################################################################
# afdb.R — African Development Bank (AfDB) Evaluation Document Scraper
#
# Targets: project EVALUATION documents only (scope decision 2026-07-17):
#          PCRs, PCR Evaluation Notes, PPERs, mid-term reviews — 2015–2025.
#          Appraisal reports (PAR), ESIAs and progress reports are excluded.
#
# Strategies (both server-rendered Drupal, parsed with rvest):
#   A. www.afdb.org category listings (?page=N, 0-indexed):
#        /en/documents/project-operations/projectprogramme-completion-reports
#        /en/documents/evaluation-reports/completion-report-reviews/
#        /en/documents/evaluation-reports/project-evaluations/
#                                     projects-performance-evaluation-report
#        /en/documents/evaluation-reports/agriculture-agro-industries/6
#   B. idev.afdb.org faceted evaluation search (?field_*_target_id=&page=N),
#      taxonomy IDs discovered at runtime from the search form and cached
#      to data/idev_taxonomy.csv.
#
# Technical notes:
#   - A WAF rejects non-browser clients with 403 (even robots.txt). All
#     requests ride per-host session handles (cookie jars) warmed on the
#     homepages, with full browser headers. Accept-Encoding excludes
#     Brotli ('br') — libcurl on Windows cannot decode it.
#   - Run modes via env var AFDB_MODE: "probe" (access check only),
#     "capped" (2 pages per listing), "full" (default).
#   - If httr access fails, the fetch backend can fall back to headless
#     Chrome via the {chromote} package (AFDB_FETCH_BACKEND <- "chromote");
#     the probe switches automatically when possible. Last resort: place
#     browser-exported rows in data/afdb_manual_listing.csv.
#   - PDF filenames embed the AfDB project code (P-XX-YYY-NNN); the third
#     segment's first letter "A" = agriculture sector — used as a
#     relevance signal alongside keyword matching.
##############################################################################

# ── Setup ──────────────────────────────────────────────────────────────────
.find_r_dir <- function() {
  # returns the directory containing this script (the R/ folder)
  tryCatch({
    d <- dirname(sys.frame(2)$ofile)
    if (!is.null(d) && nzchar(d)) return(normalizePath(d, mustWork = FALSE))
  }, error = function(e) NULL)
  tryCatch({
    args <- commandArgs(trailingOnly = FALSE)
    fa <- grep("^--file=", args, value = TRUE)
    if (length(fa)) return(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
  }, error = function(e) NULL)
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

DOWNLOAD_DIR <- file.path(PATHS$downloads, "afdb")
dir.create(DOWNLOAD_DIR, recursive = TRUE, showWarnings = FALSE)

SOURCE_NAME <- "afdb"

# ── AfDB Configuration ─────────────────────────────────────────────────────
AFDB_BASE <- "https://www.afdb.org"
IDEV_BASE <- "https://idev.afdb.org"

IDEV_SEARCH_URL <- paste0(IDEV_BASE, "/en/page/evaluations/search")

# Strategy A: targeted category listings (?page=N, 0-indexed)
# implied type is applied only when `confirm` matches the title — the
# category listings mix in other doc types (IPRs, feasibility studies, ...)
AFDB_CATEGORY_LISTINGS <- list(
  pcr = list(
    path    = "/en/documents/project-operations/projectprogramme-completion-reports",
    label   = "Project Completion Reports",
    implied = "PCR",
    confirm = "completion report|[- ]pcr\\b|rapport d.ach.vement"
  ),
  pcr_review = list(
    path    = "/en/documents/evaluation-reports/completion-report-reviews/",
    label   = "Completion Report Reviews",
    implied = "PCREN",
    confirm = "review|validation|evaluation note|completion"
  ),
  pper = list(
    path    = "/en/documents/evaluation-reports/project-evaluations/projects-performance-evaluation-report",
    label   = "Project Performance Evaluation Reports",
    implied = "PPER",
    confirm = "performance evaluation|pper|evaluation"
  ),
  agri_eval = list(
    path    = "/en/documents/evaluation-reports/agriculture-agro-industries/6",
    label   = "Agriculture Evaluation Reports",
    implied = "EVAL",
    confirm = "evaluation|\\bevaluat|réexamen"
  )
)

# Strategy B: IDEV document-category facets to sweep, matched against the
# taxonomy labels discovered at runtime from field_category_doc_target_id
# (observed ids: 74 Project performance evaluation, 75 Project cluster
#  evaluation, 80 Impact evaluation, 185 Evaluation report,
#  186 PCR and XSR Validation synthesis)
IDEV_DOCTYPE_LABEL_PATTERNS <- c(
  "^Project performance evaluation$",
  "^Project cluster evaluation$",
  "^Impact evaluation$",
  "^Evaluation report$",
  "Completion Report .* Validation"
)

# Evaluation-type priority (lower = preferred for one-per-project selection)
AFDB_DOC_TYPE_PRIORITY <- c(
  PPER  = 1L,  # independent post-completion evaluation (IDEV)
  EER   = 1L,  # extended/external evaluation report
  EVAL  = 2L,  # other evaluation report (category-implied)
  PCREN = 2L,  # PCR evaluation note (IDEV validation of a PCR)
  PCR   = 3L,  # project completion report (self-assessment)
  MTR   = 4L,  # mid-term review
  MTEV  = 4L   # mid-term evaluation (alternate abbreviation)
)

# Recognized but out of scope (proposals / safeguard / progress docs)
AFDB_EXCLUDED_TYPES <- c("PAR", "ESIA", "IPR", "ISR")

AFDB_YEAR_MIN <- 2015L
AFDB_YEAR_MAX <- 2025L

AFDB_ONE_PER_PROJECT <- TRUE   # keep only the best evaluation doc per project

AFDB_MAX_PAGES      <- 60      # safety cap per category listing
AFDB_IDEV_MAX_PAGES <- 100     # IDEV search observed up to ~page 90

# Browser User-Agent (required: generic UAs are blocked)
AFDB_BROWSER_UA <- paste0(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ",
  "AppleWebKit/537.36 (KHTML, like Gecko) ",
  "Chrome/120.0.0.0 Safari/537.36"
)

# AfDB is Africa-focused by mandate; require sector keywords only
AFDB_REQUIRE_AFRICA <- FALSE
AFDB_REQUIRE_SECTOR <- TRUE

# Known Google-indexed PDF used by the access probe
AFDB_PROBE_PDF_URL <- paste0(
  AFDB_BASE, "/sites/default/files/documents/projects-and-operations/",
  "mozambique-_drought_recovery_and_agriculture_resilience_project-",
  "_p-mz-aa0-033-pcr-juin-2025.pdf"
)

# Fetch backend: "httr" (default) or "chromote" (headless Chrome fallback)
AFDB_FETCH_BACKEND <- "httr"

# ── Per-host session handles (persistent cookies) ──────────────────────────
# The WAF requires a session cookie set by the homepage before serving
# listing pages. Cookie jars are per-host, so www and idev get separate
# handles, each warmed on its own homepage.
AFDB_HANDLE <- NULL
IDEV_HANDLE <- NULL

afdb_init_session <- function(base_url = AFDB_BASE) {
  cli::cli_alert_info("Initialising session for {base_url} ...")
  h <- httr::handle(base_url)
  resp <- tryCatch(
    httr::GET(
      base_url,
      handle = h,
      httr::user_agent(AFDB_BROWSER_UA),
      httr::timeout(HTTP_CONFIG$timeout_sec),
      httr::add_headers(
        Accept            = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        `Accept-Language` = "en-US,en;q=0.9",
        `Accept-Encoding` = "gzip, deflate",
        `Upgrade-Insecure-Requests` = "1",
        `Sec-Fetch-Dest`  = "document",
        `Sec-Fetch-Mode`  = "navigate",
        `Sec-Fetch-Site`  = "none",
        `Sec-Fetch-User`  = "?1"
      )
    ),
    error = function(e) NULL
  )
  status <- if (is.null(resp)) NA_integer_ else httr::status_code(resp)
  if (!is.na(status) && status == 200) {
    cli::cli_alert_success("Session OK (homepage 200)")
    Sys.sleep(runif(1, 1.5, 3.0))
  } else {
    status_str <- if (is.na(status)) "no response (network error)" else status
    cli::cli_alert_warning("Homepage returned {status_str} — cookies may be missing")
  }
  h
}

afdb_warm_sessions <- function() {
  if (is.null(AFDB_HANDLE)) AFDB_HANDLE <<- afdb_init_session(AFDB_BASE)
  if (is.null(IDEV_HANDLE)) IDEV_HANDLE <<- afdb_init_session(IDEV_BASE)
  invisible(NULL)
}

.afdb_pick_handle <- function(url) {
  if (grepl("^https?://idev\\.", url)) IDEV_HANDLE else AFDB_HANDLE
}

.afdb_default_referer <- function(url) {
  if (grepl("^https?://idev\\.", url)) paste0(IDEV_BASE, "/en/page/evaluations")
  else paste0(AFDB_BASE, "/en/documents")
}

# ── Helper: AfDB-specific polite GET ──────────────────────────────────────
#' Uses the per-host cookie handle + browser UA + gzip-only encoding.
afdb_get <- function(url, referer = NULL, handle = NULL) {
  if (is.null(referer)) referer <- .afdb_default_referer(url)
  if (is.null(handle))  handle  <- .afdb_pick_handle(url)
  Sys.sleep(runif(1, HTTP_CONFIG$delay_min, HTTP_CONFIG$delay_max))

  for (attempt in seq_len(HTTP_CONFIG$max_retries)) {
    resp <- tryCatch({
      args <- list(
        url,
        httr::user_agent(AFDB_BROWSER_UA),
        httr::timeout(HTTP_CONFIG$timeout_sec),
        httr::add_headers(
          Accept            = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          `Accept-Language` = "en-US,en;q=0.9",
          `Accept-Encoding` = "gzip, deflate",
          Referer           = referer,
          `Upgrade-Insecure-Requests` = "1",
          `Sec-Fetch-Dest`  = "document",
          `Sec-Fetch-Mode`  = "navigate",
          `Sec-Fetch-Site`  = "same-origin",
          `Sec-Fetch-User`  = "?1",
          `Cache-Control`   = "max-age=0"
        )
      )
      if (!is.null(handle)) args <- c(args, list(handle = handle))
      do.call(httr::GET, args)
    },
    error = function(e) {
      cli::cli_alert_warning("AfDB GET error (attempt {attempt}): {e$message}")
      NULL
    })

    if (is.null(resp)) { Sys.sleep(2^attempt); next }
    status <- httr::status_code(resp)
    if (status == 200) return(resp)
    if (status == 429) { Sys.sleep(30); next }
    if (status >= 500) { Sys.sleep(2^attempt); next }
    cli::cli_alert_warning("HTTP {status} for: {url}")
    return(resp)
  }
  NULL
}

# ── Helper: Read HTML via httr ─────────────────────────────────────────────
afdb_read_html <- function(url, referer = NULL) {
  resp <- afdb_get(url, referer = referer)
  if (is.null(resp) || httr::status_code(resp) != 200) return(NULL)
  tryCatch({
    txt <- httr::content(resp, as = "text", encoding = "UTF-8")
    if (nchar(txt) < 200) return(NULL)
    xml2::read_html(txt)
  }, error = function(e) {
    cli::cli_alert_warning("HTML parse error: {e$message}")
    NULL
  })
}

# ── Chromote fallback backend (headless Chrome) ────────────────────────────
.afdb_env <- new.env(parent = emptyenv())

afdb_chromote_html <- function(url, wait_sec = 6) {
  if (!requireNamespace("chromote", quietly = TRUE)) {
    cli::cli_alert_warning("{.pkg chromote} not installed — cannot use browser backend")
    return(NULL)
  }
  tryCatch({
    if (is.null(.afdb_env$chromote)) {
      .afdb_env$chromote <- chromote::ChromoteSession$new()
    }
    b <- .afdb_env$chromote
    b$Page$navigate(url)
    Sys.sleep(wait_sec)
    html <- b$Runtime$evaluate("document.documentElement.outerHTML")$result$value
    if (is.null(html) || nchar(html) < 200) return(NULL)
    xml2::read_html(html)
  }, error = function(e) {
    cli::cli_alert_warning("chromote error: {e$message}")
    NULL
  })
}

# ── Fetch seam: all parsing goes through this ──────────────────────────────
afdb_fetch_html <- function(url, referer = NULL) {
  switch(AFDB_FETCH_BACKEND,
    chromote = afdb_chromote_html(url),
    afdb_read_html(url, referer = referer)
  )
}

# ── Phase 0: access probe (decision gate) ──────────────────────────────────
#' Cheaply answers "can we fetch anything at all?" before a full run.
#' Returns c(www =, idev =, pdf =) logicals. If httr fails on the HTML
#' probes but chromote works, switches AFDB_FETCH_BACKEND automatically.
afdb_probe_access <- function() {
  cli::cli_h2("AfDB access probe")
  afdb_warm_sessions()

  p1_url <- paste0(AFDB_BASE, AFDB_CATEGORY_LISTINGS$pcr$path, "?page=0")
  p2_url <- IDEV_SEARCH_URL

  probe_listing <- function(url, selector) {
    page <- afdb_fetch_html(url)
    if (is.null(page)) return(FALSE)
    length(rvest::html_elements(page, selector)) > 0
  }

  www_ok <- probe_listing(p1_url,
    ".views-row, .views-field-title, .view-content, div.col-xs-12")
  cli::cli_alert_info("P1 www listing:   {if (www_ok) 'OK' else 'FAILED'}")

  idev_ok <- probe_listing(p2_url,
    "select[name*='field_document_type'], select[name*='field_sector'], .views-row")
  cli::cli_alert_info("P2 IDEV search:   {if (idev_ok) 'OK' else 'FAILED'}")

  pdf_ok <- tryCatch({
    resp <- afdb_get(AFDB_PROBE_PDF_URL)
    if (!is.null(resp) && httr::status_code(resp) == 200) {
      raw5 <- httr::content(resp, as = "raw")[1:5]
      rawToChar(raw5) == "%PDF-"
    } else FALSE
  }, error = function(e) FALSE)
  cli::cli_alert_info("P3 direct PDF:    {if (pdf_ok) 'OK' else 'FAILED'}")

  # Escalate to chromote if HTML probes failed under httr
  if (!www_ok && !idev_ok && AFDB_FETCH_BACKEND == "httr" &&
      requireNamespace("chromote", quietly = TRUE)) {
    cli::cli_alert_info("httr blocked — trying headless Chrome backend ...")
    AFDB_FETCH_BACKEND <<- "chromote"
    www_ok  <- probe_listing(p1_url, ".views-row, .views-field-title, div.col-xs-12")
    idev_ok <- probe_listing(p2_url, "select[name*='field_document_type'], .views-row")
    if (!www_ok && !idev_ok) {
      AFDB_FETCH_BACKEND <<- "httr"
      cli::cli_alert_danger("Chrome backend also blocked")
    } else {
      cli::cli_alert_success("Chrome backend works — using AFDB_FETCH_BACKEND='chromote'")
    }
  }

  verdict <- c(www = www_ok, idev = idev_ok, pdf = pdf_ok)
  cli::cli_h3("Probe verdict")
  cli::cli_alert_info("www={www_ok} idev={idev_ok} pdf={pdf_ok} backend={AFDB_FETCH_BACKEND}")
  verdict
}

# ── Helper: Parse document type from title suffix ─────────────────────────
#' AfDB titles embed doc type as " - PCR October 2025" or " - IPR novembre 2024"
parse_doc_type_from_title <- function(title) {
  if (is.na(title) || nchar(title) == 0) return(NA_character_)
  pattern <- "\\b(PPER|EER|PCREN|PCR|MTEv|MTEV|MTR|IPR|ISR|PAR|ESIA)\\b"
  m <- regmatches(title, regexpr(pattern, title, ignore.case = TRUE))
  if (length(m) == 0 || nchar(m) == 0) return(NA_character_)
  toupper(m)
}

# ── Helper: normalize a doc-type label/abbr to a canonical abbreviation ────
normalize_doc_type <- function(x) {
  if (is.na(x) || nchar(x) == 0) return(NA_character_)
  u <- toupper(x)
  if (u %in% c(names(AFDB_DOC_TYPE_PRIORITY), AFDB_EXCLUDED_TYPES)) return(u)
  if (grepl("PERFORMANCE EVALUATION|PPER", u)) return("PPER")
  if (grepl("EVALUATION NOTE|PCR EVALUATION|COMPLETION REPORT REVIEW|VALIDATION", u)) return("PCREN")
  if (grepl("COMPLETION", u)) return("PCR")
  if (grepl("MID[- ]?TERM", u)) return("MTR")
  if (grepl("APPRAISAL", u)) return("PAR")
  if (grepl("EVALUATION", u)) return("EVAL")
  NA_character_
}

# ── Helper: Strip doc type suffix to get project name ────────────────────
extract_project_name <- function(title) {
  if (is.na(title) || nchar(title) == 0) return(NA_character_)
  pattern <- "\\s*-\\s*(PPER|EER|PCREN|PCR|MTEv|MTEV|MTR|IPR|ISR|PAR|ESIA)(\\s.*)?$"
  trimws(sub(pattern, "", title, ignore.case = TRUE))
}

# ── Helper: extract AfDB project code (P-XX-YYY-NNN) ───────────────────────
#' Codes appear in PDF filenames/titles, sometimes lowercase.
#' Third segment's first letter is the sector ("A" = agriculture).
afdb_parse_project_code <- function(...) {
  txt <- paste(c(...), collapse = " ")
  m <- regmatches(txt, regexpr("P-[A-Za-z0-9]{2}-[A-Za-z0-9]{3}-\\d{3}", txt))
  if (length(m) == 0) return(NA_character_)
  toupper(m)
}

# ── Helper: best-effort document year ──────────────────────────────────────
afdb_extract_year <- function(doc_date = NA, pdf_url = NA, title = NA) {
  pick <- function(x) {
    y <- suppressWarnings(as.integer(x))
    if (!is.na(y) && y >= 1990 && y <= 2026) y else NA_integer_
  }
  # 1. ISO listing date
  if (!is.na(doc_date) && grepl("^\\d{4}-", doc_date))
    return(pick(substr(doc_date, 1, 4)))
  # 2. year in the PDF filename
  if (!is.na(pdf_url)) {
    m <- regmatches(pdf_url, gregexpr("(19|20)\\d{2}", basename(pdf_url)))[[1]]
    if (length(m)) return(pick(m[length(m)]))
    # 3. IDEV dated folder /Evaluations/YYYY-MM/
    m2 <- regmatches(pdf_url, regexpr("/Evaluations/(19|20)\\d{2}-\\d{2}/", pdf_url))
    if (length(m2) && nchar(m2)) return(pick(substr(gsub("[^0-9]", "", m2), 1, 4)))
  }
  # 4. year in the title
  if (!is.na(title)) {
    m3 <- regmatches(title, gregexpr("(19|20)\\d{2}", title))[[1]]
    if (length(m3)) return(pick(m3[length(m3)]))
  }
  NA_integer_
}

# ── Helper: Parse a www.afdb.org document listing page ─────────────────────
#' Listing markup (confirmed live 2026-07): each document is a Bootstrap
#' grid cell <div class="col-xs-12 col-sm-6 col-md-4"> containing
#' .views-field-title (a -> /en/documents/{slug}) and
#' .views-field-field-publication-date ("10-Jul-2026").
#' Rows are located as the PARENTS of .views-field-title — robust to grid
#' class changes.
parse_afdb_listing <- function(page_html, category_label,
                               implied_type = NA_character_,
                               confirm_pattern = NULL) {
  if (is.null(page_html)) return(tibble())

  title_els <- tryCatch(
    rvest::html_elements(page_html, ".views-field-title"),
    error = function(e) list()
  )
  if (length(title_els) == 0) return(tibble())

  records <- purrr::map(title_els, function(t_el) {
    tryCatch({
      entry <- xml2::xml_parent(t_el)

      title_a <- rvest::html_element(t_el, "a")
      if (is.na(title_a)) return(NULL)
      title <- trimws(rvest::html_text2(title_a))
      href  <- rvest::html_attr(title_a, "href")
      if (is.na(title) || nchar(title) < 5) return(NULL)

      web_url <- if (!is.na(href)) {
        if (startsWith(href, "http")) href else paste0(AFDB_BASE, href)
      } else NA_character_

      date_el  <- rvest::html_element(entry,
        ".views-field-field-publication-date, span.date-display-single, time, .views-field-created")
      doc_date <- if (!is.na(date_el)) trimws(rvest::html_text2(date_el)) else NA_character_

      # Locale-safe ISO conversion (AfDB uses "10-Jul-2026")
      parsed <- suppressWarnings(lubridate::dmy(doc_date, quiet = TRUE))
      doc_date_iso <- if (!is.na(parsed)) format(parsed, "%Y-%m-%d") else doc_date

      pdf_el  <- rvest::html_element(entry, "a[href$='.pdf'], a[href$='.PDF']")
      pdf_url <- if (!is.na(pdf_el)) {
        h <- rvest::html_attr(pdf_el, "href")
        if (!is.na(h)) { if (startsWith(h, "http")) h else paste0(AFDB_BASE, h) }
      } else NA_character_

      title_lower <- tolower(title)
      country <- NA_character_
      for (cn in AFRICA_COUNTRIES_EN) {
        if (grepl(tolower(cn), title_lower, fixed = TRUE)) { country <- cn; break }
      }

      dtype <- parse_doc_type_from_title(title)
      if (is.na(dtype) && !is.null(confirm_pattern) &&
          grepl(confirm_pattern, title_lower)) {
        dtype <- implied_type
      }

      tibble(
        id         = safe_filename(title),
        title      = title,
        pdf_url    = pdf_url,
        doc_date   = doc_date_iso,
        doc_type   = dtype,
        country    = country,
        project_id = afdb_parse_project_code(title, pdf_url, href),
        web_url    = web_url,
        listing    = category_label
      )
    }, error = function(e) NULL)
  })

  purrr::compact(records) %>%
    bind_rows() %>%
    distinct(web_url, .keep_all = TRUE)
}

# ── Strategy A: www.afdb.org category listings ─────────────────────────────
scrape_afdb_categories <- function(max_pages = AFDB_MAX_PAGES) {
  cli::cli_h2("Strategy A: www.afdb.org category listings")
  all_results <- tibble()

  for (cat_name in names(AFDB_CATEGORY_LISTINGS)) {
    cat <- AFDB_CATEGORY_LISTINGS[[cat_name]]
    cli::cli_alert_info("Listing: {cat$label}")

    for (page_num in 0:max_pages) {
      url <- paste0(AFDB_BASE, cat$path,
                    if (grepl("\\?", cat$path)) "&" else "?", "page=", page_num)
      page_html <- afdb_fetch_html(url)

      if (is.null(page_html)) {
        cli::cli_alert_warning("  Could not fetch page {page_num} — stopping listing.")
        break
      }
      records <- parse_afdb_listing(page_html, cat$label, cat$implied, cat$confirm)
      if (nrow(records) == 0) {
        cli::cli_alert_info("  Page {page_num}: empty — end of listing.")
        break
      }
      all_results <- bind_rows(all_results, records)
      cli::cli_alert_success("  Page {page_num}: {nrow(records)} entries (total: {nrow(all_results)})")

      next_link <- rvest::html_element(page_html,
        "a[rel='next'], .pager__item--next a, li.pager-next a, li.next a")
      if (is.na(next_link)) {
        cli::cli_alert_info("  No next-page link — end of listing.")
        break
      }
    }
  }
  cli::cli_alert_success("Strategy A total: {nrow(all_results)} documents")
  all_results
}

# ── Strategy B: IDEV taxonomy discovery + faceted search ───────────────────
idev_discover_taxonomy <- function(refresh = FALSE) {
  cache <- file.path(PATHS$data, "idev_taxonomy.csv")
  if (!refresh && file.exists(cache)) {
    tax <- readr::read_csv(cache, show_col_types = FALSE)
    cli::cli_alert_info("IDEV taxonomy loaded from cache ({nrow(tax)} options)")
    return(tax)
  }
  cli::cli_alert_info("Discovering IDEV facet taxonomy from search form ...")
  page <- afdb_fetch_html(IDEV_SEARCH_URL)
  if (is.null(page)) {
    cli::cli_alert_danger("Could not fetch IDEV search form")
    return(tibble(facet = character(), id = character(), label = character()))
  }
  selects <- rvest::html_elements(page, "select[name^='field_']")
  tax <- purrr::map(selects, function(sel) {
    facet <- rvest::html_attr(sel, "name")
    opts  <- rvest::html_elements(sel, "option")
    tibble(
      facet = facet,
      id    = rvest::html_attr(opts, "value"),
      label = trimws(rvest::html_text2(opts))
    )
  }) %>% bind_rows() %>% filter(!is.na(id), id != "", label != "")
  if (nrow(tax) > 0) {
    readr::write_csv(tax, cache)
    cli::cli_alert_success("IDEV taxonomy: {nrow(tax)} options cached to {cache}")
  }
  tax
}

idev_facet_ids <- function(tax, facet_pattern, label_patterns) {
  hits <- tax %>%
    filter(grepl(facet_pattern, facet)) %>%
    filter(Reduce(`|`, lapply(label_patterns, function(p)
      grepl(p, label, ignore.case = TRUE))))
  hits
}

parse_idev_listing <- function(page_html, doctype_label) {
  if (is.null(page_html)) return(tibble())

  rows <- rvest::html_elements(page_html, ".views-row")
  make_record <- function(title, href, doc_date) {
    if (is.na(title) || nchar(title) < 5 || is.na(href)) return(NULL)
    web_url <- if (startsWith(href, "http")) href else paste0(IDEV_BASE, href)
    parsed  <- suppressWarnings(lubridate::dmy(doc_date, quiet = TRUE))
    if (is.na(parsed)) parsed <- suppressWarnings(lubridate::mdy(doc_date, quiet = TRUE))
    doc_date_iso <- if (!is.na(parsed)) format(parsed, "%Y-%m-%d") else doc_date
    title_lower <- tolower(title)
    country <- NA_character_
    for (cn in AFRICA_COUNTRIES_EN) {
      if (grepl(tolower(cn), title_lower, fixed = TRUE)) { country <- cn; break }
    }
    tibble(
      id         = safe_filename(title),
      title      = title,
      pdf_url    = NA_character_,
      doc_date   = doc_date_iso,
      doc_type   = doctype_label,
      country    = country,
      project_id = afdb_parse_project_code(title, href),
      web_url    = web_url,
      listing    = paste0("IDEV: ", doctype_label)
    )
  }

  records <- if (length(rows) > 0) {
    purrr::map(rows, function(row) {
      tryCatch({
        a <- rvest::html_element(row, "a[href*='/en/document/'], .views-field-title a, h3 a, h2 a")
        if (is.na(a)) return(NULL)
        date_el <- rvest::html_element(row,
          "time, span.date-display-single, .views-field-created, .date")
        make_record(
          trimws(rvest::html_text2(a)),
          rvest::html_attr(a, "href"),
          if (!is.na(date_el)) trimws(rvest::html_text2(date_el)) else NA_character_
        )
      }, error = function(e) NULL)
    })
  } else {
    # fallback: bare anchor harvest
    anchors <- rvest::html_elements(page_html, "a[href*='/en/document/']")
    purrr::map(anchors, function(a) {
      tryCatch(
        make_record(trimws(rvest::html_text2(a)), rvest::html_attr(a, "href"), NA_character_),
        error = function(e) NULL)
    })
  }

  purrr::compact(records) %>% bind_rows() %>% distinct(web_url, .keep_all = TRUE)
}

scrape_idev_evaluations <- function(max_pages = AFDB_IDEV_MAX_PAGES) {
  cli::cli_h2("Strategy B: IDEV faceted evaluation search")
  tax <- idev_discover_taxonomy()
  if (nrow(tax) == 0) {
    cli::cli_alert_warning("No IDEV taxonomy — skipping IDEV strategy")
    return(tibble())
  }

  doctypes <- idev_facet_ids(tax, "category_doc", IDEV_DOCTYPE_LABEL_PATTERNS)
  if (nrow(doctypes) == 0) {
    cli::cli_alert_warning("No matching IDEV document-category facets found; available:")
    print(tax %>% filter(grepl("category_doc", facet)) %>% head(30))
    return(tibble())
  }
  cli::cli_alert_info("Sweeping {nrow(doctypes)} document-type facet(s): {paste(doctypes$label, collapse=', ')}")

  all_results <- tibble()
  for (i in seq_len(nrow(doctypes))) {
    dt <- doctypes[i, ]
    cli::cli_alert_info("IDEV doc type: {dt$label} (id={dt$id})")
    for (page_num in 0:max_pages) {
      url <- paste0(
        IDEV_SEARCH_URL,
        "?field_category_doc_target_id=", dt$id,
        "&field_region_target_id=All",
        "&field_topic_target_id=All",
        "&field_sector_target_id=All",
        "&title=&page=", page_num
      )
      page_html <- afdb_fetch_html(url)
      if (is.null(page_html)) {
        cli::cli_alert_warning("  Could not fetch page {page_num} — stopping.")
        break
      }
      records <- parse_idev_listing(page_html, dt$label)
      if (nrow(records) == 0) {
        cli::cli_alert_info("  Page {page_num}: empty — end of facet.")
        break
      }
      all_results <- bind_rows(all_results, records)
      cli::cli_alert_success("  Page {page_num}: {nrow(records)} entries (total: {nrow(all_results)})")
    }
  }
  cli::cli_alert_success("Strategy B total: {nrow(all_results)} documents")
  all_results
}

# ── Manual-assisted last resort ─────────────────────────────────────────────
afdb_load_manual_listing <- function() {
  path <- file.path(PATHS$data, "afdb_manual_listing.csv")
  if (!file.exists(path)) return(tibble())
  rows <- readr::read_csv(path, show_col_types = FALSE)
  cli::cli_alert_info("Loaded {nrow(rows)} rows from manual listing {path}")
  rows
}

# ── Helper: Visit a document page to resolve its PDF URL ─────────────────
resolve_pdf_url <- function(web_url) {
  if (is.na(web_url) || nchar(web_url) == 0) return(NA_character_)
  base <- if (grepl("^https?://idev\\.", web_url)) IDEV_BASE else AFDB_BASE
  page <- afdb_fetch_html(web_url)
  if (is.null(page)) return(NA_character_)
  pdf_links <- rvest::html_elements(page,
    "a[href$='.pdf'], a[href$='.PDF'], a[href*='fileadmin'], a[href*='/sites/default/files/']")
  if (length(pdf_links) == 0) return(NA_character_)
  # prefer links that end in .pdf
  hrefs <- rvest::html_attr(pdf_links, "href")
  hrefs <- hrefs[!is.na(hrefs)]
  if (length(hrefs) == 0) return(NA_character_)
  pdfs <- hrefs[grepl("\\.pdf$", hrefs, ignore.case = TRUE)]
  href <- if (length(pdfs)) pdfs[1] else hrefs[1]
  if (startsWith(href, "http")) href else paste0(base, href)
}

# ── Cross-host dedupe ───────────────────────────────────────────────────────
dedupe_documents <- function(results) {
  if (nrow(results) == 0) return(results)
  n0 <- nrow(results)
  norm_title <- tolower(gsub("[^a-z0-9]+", " ", tolower(results$title)))
  results <- results %>%
    mutate(.norm_title = norm_title,
           .pdf_base = ifelse(is.na(pdf_url), NA_character_,
                              tolower(basename(pdf_url)))) %>%
    arrange(is.na(pdf_url)) %>%              # keep rows that already have a PDF
    distinct(.pdf_base, .norm_title, .keep_all = TRUE) %>%
    distinct(web_url, .keep_all = TRUE) %>%
    select(-.norm_title, -.pdf_base)
  cli::cli_alert_info("Dedupe: {n0} -> {nrow(results)} documents")
  results
}

# ── Scope filter: evaluation types only, 2015–2025 ─────────────────────────
filter_scope <- function(results) {
  if (nrow(results) == 0) return(results)
  cli::cli_h2("Scope filter (evaluation types, {AFDB_YEAR_MIN}-{AFDB_YEAR_MAX})")

  results <- results %>%
    mutate(doc_type = sapply(doc_type, normalize_doc_type)) %>%
    filter(!doc_type %in% AFDB_EXCLUDED_TYPES)
  cli::cli_alert_info("After type filter: {nrow(results)}")

  results <- results %>%
    rowwise() %>%
    mutate(year = afdb_extract_year(doc_date, pdf_url, title)) %>%
    ungroup()

  n_na <- sum(is.na(results$year))
  results <- results %>%
    filter(is.na(year) | (year >= AFDB_YEAR_MIN & year <= AFDB_YEAR_MAX))
  cli::cli_alert_info("After year filter: {nrow(results)} (kept {n_na} with unknown year)")
  results
}

# ── Relevance filtering ────────────────────────────────────────────────────
filter_relevant <- function(results) {
  cli::cli_h2("Filtering for relevance (agriculture/adaptation)")
  if (nrow(results) == 0) return(results)

  results %>%
    rowwise() %>%
    mutate(
      .kw = passes_relevance_fast(
        paste(coalesce(title, ""), coalesce(listing, ""), sep = " "),
        require_africa = AFDB_REQUIRE_AFRICA,
        require_sector = AFDB_REQUIRE_SECTOR
      ),
      .agri_code = !is.na(project_id) && grepl("^P-[A-Z0-9]{2}-A", project_id),
      relevant = .kw || .agri_code
    ) %>%
    ungroup() %>%
    filter(relevant) %>%
    select(-relevant, -.kw, -.agri_code)
}

# ── One document per project: select highest-priority type ────────────────
select_best_document <- function(results) {
  if (nrow(results) == 0 || !AFDB_ONE_PER_PROJECT) return(results)
  cli::cli_h2("Selecting one document per project (priority ranking)")

  results <- results %>%
    mutate(
      project_name = sapply(title, extract_project_name),
      .group_key = ifelse(!is.na(project_id), project_id,
                          tolower(gsub("[^a-z0-9]+", " ", tolower(project_name)))),
      .priority = {
        p <- AFDB_DOC_TYPE_PRIORITY[doc_type]
        ifelse(is.na(p), 99L, as.integer(p))
      }
    )

  cli::cli_alert_info("Before: {nrow(results)} docs, {dplyr::n_distinct(results$.group_key)} projects")
  type_dist <- results %>% count(doc_type, sort = TRUE)
  for (i in seq_len(nrow(type_dist))) {
    cli::cli_text("  {coalesce(type_dist$doc_type[i], '(unknown)')}: {type_dist$n[i]}")
  }

  best <- results %>%
    group_by(.group_key) %>%
    arrange(.priority, desc(doc_date)) %>%
    slice(1) %>%
    ungroup() %>%
    select(-.priority, -.group_key)

  cli::cli_alert_success("After selection: {nrow(best)} documents (one per project)")
  best
}

# ── Resolve missing PDF URLs ───────────────────────────────────────────────
enrich_pdf_urls <- function(results) {
  cli::cli_h2("Resolving PDF URLs (visiting document pages)")
  needs_pdf <- results %>% filter(is.na(pdf_url) & !is.na(web_url))
  has_pdf   <- results %>% filter(!is.na(pdf_url) | is.na(web_url))
  cli::cli_alert_info("{nrow(needs_pdf)} documents need PDF URL resolution")
  if (nrow(needs_pdf) == 0) return(results)

  resolved <- needs_pdf %>%
    rowwise() %>%
    mutate(pdf_url = {
      cli::cli_alert_info("  {substr(title, 1, 65)}")
      resolve_pdf_url(web_url)
    }) %>%
    ungroup()

  bind_rows(has_pdf, resolved)
}

# ── Download one PDF via the session handle ────────────────────────────────
#' Mirrors download_pdf()'s validation (min size + %PDF- magic, delete on
#' fail), but rides afdb_get() — the shared util's plain polite_get() is
#' blocked by the WAF.
afdb_download_pdf <- function(url, dest) {
  if (file.exists(dest)) return("skipped")
  resp <- afdb_get(url)
  if (is.null(resp) || httr::status_code(resp) != 200) return(FALSE)
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
  with_pdf <- results %>% filter(!is.na(pdf_url) & nchar(pdf_url) > 0)
  cli::cli_alert_info("{nrow(with_pdf)} documents have PDF URLs")

  success <- 0L; failed <- 0L; skipped <- 0L

  for (i in seq_len(nrow(with_pdf))) {
    row <- with_pdf[i, ]
    year_str <- if (!is.na(row$year)) row$year else "XXXX"
    proj_str <- if (!is.na(row$project_id)) row$project_id
                else safe_filename(substr(coalesce(row$project_name, row$title, "notitle"), 1, 60))
    fname <- paste0(substr(
      glue("{SOURCE_NAME}_{coalesce(row$doc_type, 'DOC')}_{proj_str}_{year_str}"),
      1, 100), ".pdf")
    dest <- file.path(DOWNLOAD_DIR, fname)

    status <- afdb_download_pdf(row$pdf_url, dest)

    if (identical(status, "skipped")) {
      log_download(SOURCE_NAME, row$project_id, row$doc_type,
                   row$title, row$pdf_url, dest, "skipped", "Already exists")
      skipped <- skipped + 1L
    } else if (isTRUE(status)) {
      log_download(SOURCE_NAME, row$project_id, row$doc_type,
                   row$title, row$pdf_url, dest, "success")
      success <- success + 1L
    } else {
      log_download(SOURCE_NAME, row$project_id, row$doc_type,
                   row$title, row$pdf_url, dest, "failed",
                   "Download or PDF validation failed")
      failed <- failed + 1L
    }

    if (i %% 10 == 0)
      cli::cli_alert_info("Progress: {i}/{nrow(with_pdf)} (OK:{success} fail:{failed} skip:{skipped})")
  }

  cli::cli_h3("Download Summary")
  cli::cli_alert_success("Success: {success}")
  cli::cli_alert_danger("Failed:  {failed}")
  cli::cli_alert_info("Skipped: {skipped}")
  cli::cli_alert_info("No PDF:  {nrow(results) - nrow(with_pdf)}")
}

# ── Save metadata ─────────────────────────────────────────────────────────
save_metadata <- function(results) {
  meta_path <- file.path(PATHS$data, "afdb_metadata.csv")
  readr::write_csv(results, meta_path)
  cli::cli_alert_success("Metadata saved ({nrow(results)} rows): {meta_path}")
}

# ── Main execution ────────────────────────────────────────────────────────
run_afdb_scraper <- function(max_pages = AFDB_MAX_PAGES,
                             idev_max_pages = AFDB_IDEV_MAX_PAGES) {
  cli::cli_h1("AfDB Evaluation Document Scraper")
  cli::cli_alert_info("Download dir: {DOWNLOAD_DIR}")

  # Step 0: sessions + access probe (abort loudly if fully blocked)
  probe <- afdb_probe_access()
  if (!probe["www"] && !probe["idev"]) {
    manual <- afdb_load_manual_listing()
    if (nrow(manual) == 0) {
      cli::cli_alert_danger(paste0(
        "AfDB is blocking all listing access (WAF). Options: install {.pkg chromote} ",
        "for the browser backend, or export listing rows from a real browser to ",
        "data/afdb_manual_listing.csv"))
      log_download(SOURCE_NAME, NA, NA, "AfDB access probe", AFDB_BASE,
                   NA, "blocked", "WAF blocked www + IDEV listing probes")
      return(invisible(NULL))
    }
    all_docs <- manual
  } else {
    # Step 1: both strategies
    docs_a <- if (probe["www"]) {
      tryCatch(scrape_afdb_categories(max_pages), error = function(e) {
        cli::cli_alert_danger("Strategy A failed: {e$message}"); tibble()
      })
    } else tibble()
    docs_b <- if (probe["idev"]) {
      tryCatch(scrape_idev_evaluations(idev_max_pages), error = function(e) {
        cli::cli_alert_danger("Strategy B failed: {e$message}"); tibble()
      })
    } else tibble()
    all_docs <- bind_rows(docs_a, docs_b)
  }

  if (nrow(all_docs) == 0) {
    cli::cli_alert_danger("No documents found. Check network and URL structure.")
    return(invisible(NULL))
  }

  # Step 2: dedupe -> scope -> relevance
  all_docs <- dedupe_documents(all_docs)
  in_scope <- filter_scope(all_docs)
  relevant <- filter_relevant(in_scope)
  cli::cli_alert_info("After relevance filter: {nrow(relevant)} documents")

  if (nrow(relevant) == 0) {
    cli::cli_alert_warning("No documents passed the filters.")
    save_metadata(relevant)
    return(invisible(NULL))
  }

  # Step 3: one document per project (gated by AFDB_ONE_PER_PROJECT)
  best <- select_best_document(relevant)
  if (!"project_name" %in% names(best)) {
    best <- best %>% mutate(project_name = sapply(title, extract_project_name))
  }

  # Step 4: resolve PDF URLs, save metadata, download
  best <- enrich_pdf_urls(best)
  # year may only be recoverable from the resolved PDF URL (IDEV dated paths)
  best <- best %>%
    rowwise() %>%
    mutate(year = if (is.na(year)) afdb_extract_year(doc_date, pdf_url, title) else year) %>%
    ungroup() %>%
    filter(is.na(year) | (year >= AFDB_YEAR_MIN & year <= AFDB_YEAR_MAX))
  save_metadata(best)
  download_results(best)

  # Step 5: summary
  print_source_summary(SOURCE_NAME)
  cli::cli_h2("Done!")
  invisible(best)
}

# Run if called directly. AFDB_MODE: probe | capped | load | full (default)
if (sys.nframe() == 0 || !interactive()) {
  switch(Sys.getenv("AFDB_MODE", "full"),
    probe  = afdb_probe_access(),
    capped = run_afdb_scraper(max_pages = 2, idev_max_pages = 2),
    load   = invisible(NULL),   # source functions only, no run
    run_afdb_scraper()
  )
}
