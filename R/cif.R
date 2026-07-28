##############################################################################
# cif.R — Climate Investment Funds (CIF) Evaluation Document Scraper
#
# Targets: EVALUATION documents (independent/program evaluations, learning
#          reviews, completion/performance reports) relevant to African
#          agriculture adaptation, 2015+.
#
# Why cif.org and not Climate Project Explorer: the CIF corpus on CPE is
# effectively empty (verified 2026-07-23 — one Bangladesh proposal), so CIF
# evaluations must come from the fund's own Drupal site.
#
# Retrieval mechanics (verified 2026-07-23):
#   - Enumeration via the sitemap index https://www.cif.org/sitemap.xml
#     (?page=1..N), which lists all node URLs; document pages live under
#     /knowledge-documents/{slug} and /documents/{slug}.
#     (The /knowledge listing page is a static "featured" view — its pager
#     does not advance; sitemap is the only complete enumeration.)
#   - Document detail pages link the file at
#     /sites/cif_enc/files/knowledge-documents/{slug}.pdf (plus variants).
#
# Run modes via env var CIF_MODE: probe | capped | load | full (default)
##############################################################################

# ── Setup ──────────────────────────────────────────────────────────────────
.find_r_dir <- function() {
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

SOURCE_NAME  <- "cif"
DOWNLOAD_DIR <- file.path(PATHS$downloads, SOURCE_NAME)
dir.create(DOWNLOAD_DIR, recursive = TRUE, showWarnings = FALSE)

CIF_BASE <- "https://www.cif.org"
CIF_YEAR_MIN <- 2015L

# slug pre-filter: fetch detail pages only for evaluation-ish documents
CIF_SLUG_RE <- paste(
  "evaluat", "mid-?term", "completion", "performance-review",
  "learning-review", "lessons-learned", "impact-assessment",
  sep = "|")

# governance/admin noise around the E&L Initiative itself — excluded
CIF_EXCLUDE_RE <- paste(
  "annual-report", "work-?plan", "business-?plan", "presentation",
  "concept-note", "policy-and-guidance", "options-paper",
  "terms-of-reference", "\\btor\\b", "workshop", "webinar", "agenda",
  "meeting", "committee", "joint-mission", "session", sep = "|")

# CIF pilot countries outside Africa (public list): a country-specific
# document naming ONLY one of these is out of geographic scope
CIF_NONAF_RE <- paste(
  "mexico", "brazil", "\\blao\\b", "indonesia", "india", "turkey",
  "kazakhstan", "philippines", "viet ?nam", "nepal", "bangladesh",
  "cambodia", "tajikistan", "ukraine", "bolivia", "peru", "chile",
  "colombia", "honduras", "nicaragua", "haiti", "jamaica", "dominica",
  "saint lucia", "grenada", "samoa", "tonga", "vanuatu", "fiji",
  "papua new guinea", "solomon", "kiribati", "yemen", "thailand",
  sep = "|")

# evaluation-type classification from the page title
cif_doc_type <- function(title) {
  t <- tolower(coalesce(title, ""))
  if (grepl("independent evaluation", t))       return("Independent evaluation")
  if (grepl("mid-?term", t))                    return("Mid-term evaluation")
  if (grepl("final evaluation|terminal", t))    return("Final evaluation")
  if (grepl("learning review|lessons", t))      return("Learning review")
  if (grepl("completion", t))                   return("Completion report")
  if (grepl("performance", t))                  return("Performance review")
  if (grepl("impact assessment|impact evaluat", t)) return("Impact evaluation")
  if (grepl("evaluat", t))                      return("Evaluation")
  NA_character_
}

# ── Sitemap enumeration ─────────────────────────────────────────────────────
cif_sitemap_urls <- function() {
  idx <- polite_get(paste0(CIF_BASE, "/sitemap.xml"))
  if (is.null(idx)) return(character(0))
  pages <- unlist(regmatches(httr::content(idx, "text", encoding = "UTF-8"),
                             gregexpr("<loc>[^<]+</loc>",
                                      httr::content(idx, "text", encoding = "UTF-8"))))
  pages <- gsub("</?loc>", "", pages)
  urls <- character(0)
  for (p in pages) {
    r <- polite_get(p)
    if (is.null(r)) next
    txt <- httr::content(r, "text", encoding = "UTF-8")
    ls <- gsub("</?loc>", "", unlist(regmatches(txt, gregexpr("<loc>[^<]+</loc>", txt))))
    urls <- c(urls, ls)
    cli::cli_alert_info("sitemap {basename(p)}: {length(ls)} urls (total {length(urls)})")
  }
  urls
}

# ── Detail page parse ───────────────────────────────────────────────────────
cif_parse_document_page <- function(url) {
  page <- safe_read_html(url)
  if (is.null(page)) return(NULL)
  title <- tryCatch(rvest::html_text2(rvest::html_element(page, "h1")),
                    error = function(e) NA_character_)
  pdfs <- rvest::html_attr(
    rvest::html_elements(page, "a[href*='/sites/'][href$='.pdf'], a[href$='.pdf']"),
    "href")
  pdfs <- pdfs[!is.na(pdfs)]
  pdf <- if (length(pdfs)) {
    h <- pdfs[1]
    if (startsWith(h, "http")) h else paste0(CIF_BASE, h)
  } else NA_character_
  # date: datetime attr or a year in the page header area
  dt <- tryCatch(rvest::html_attr(rvest::html_element(page, "time"), "datetime"),
                 error = function(e) NA_character_)
  yr <- if (!is.na(dt)) substr(dt, 1, 4) else {
    m <- regmatches(title, regexpr("(19|20)\\d{2}", coalesce(title, "")))
    if (length(m) && nchar(m)) m else NA_character_
  }
  # country tags if present
  tags <- tryCatch(rvest::html_text2(
    rvest::html_elements(page, "a[href*='country'], .field--name-field-country a")),
    error = function(e) character(0))
  list(title = title, pdf = pdf, year = yr,
       countries = paste(unique(tags), collapse = ";"))
}

# ── Probe ───────────────────────────────────────────────────────────────────
cif_probe <- function() {
  cli::cli_h2("cif.org probe")
  idx <- polite_get(paste0(CIF_BASE, "/sitemap.xml"))
  ok_sm <- !is.null(idx) && httr::status_code(idx) == 200
  cli::cli_alert_info("sitemap reachable: {ok_sm}")
  d <- cif_parse_document_page(paste0(CIF_BASE, "/knowledge-documents/cif-annual-report-2025"))
  ok_page <- !is.null(d) && !is.na(d$pdf)
  cli::cli_alert_info("detail page parse: {ok_page} (title: {substr(coalesce(d$title,''),1,50)}; pdf: {!is.na(d$pdf)})")
  verdict <- c(sitemap = ok_sm, page = ok_page)
  print(verdict)
  invisible(verdict)
}

# ── Main ────────────────────────────────────────────────────────────────────
run_cif_scraper <- function(max_docs = Inf) {
  cli::cli_h1("CIF Evaluation Document Scraper")
  urls <- cif_sitemap_urls()
  doc_urls <- urls[grepl("/(knowledge-documents|documents)/", urls)]
  cli::cli_alert_info("document pages in sitemap: {length(doc_urls)}")

  cand <- doc_urls[grepl(CIF_SLUG_RE, doc_urls, ignore.case = TRUE) &
                   !grepl(CIF_EXCLUDE_RE, doc_urls, ignore.case = TRUE)]
  cli::cli_alert_info("evaluation-ish slugs after admin-noise exclusion: {length(cand)}")
  if (length(cand) > max_docs) cand <- cand[seq_len(max_docs)]

  rows <- list()
  for (i in seq_along(cand)) {
    u <- cand[i]
    d <- cif_parse_document_page(u)
    if (is.null(d)) next
    dtype <- cif_doc_type(coalesce(d$title, basename(u)))
    if (!is.na(dtype) && grepl(CIF_EXCLUDE_RE, tolower(coalesce(d$title, "")))) dtype <- NA_character_
    if (is.na(d$year) || !nzchar(coalesce(d$year, ""))) {
      m <- regmatches(coalesce(d$pdf, ""), regexpr("(19|20)\\d{2}", coalesce(d$pdf, "")))
      if (length(m) && nchar(m)) d$year <- m
    }
    # Africa relevance: country tags or country/region names in title/slug
    txt <- tolower(paste(d$title, basename(u), d$countries))
    africa_named <- any(vapply(tolower(AFRICA_COUNTRIES_EN),
                               function(cn) grepl(cn, txt, fixed = TRUE), logical(1)))
    regional <- grepl("africa|sahel", txt)
    nonaf_named <- grepl(CIF_NONAF_RE, txt)
    status <- if (is.na(dtype)) "parked"
              else if (africa_named || regional) "kept"
              else if (nonaf_named) "out_of_scope_geo"  # names a non-African pilot country only
              else "kept_global"   # program/portfolio evaluations cover Africa within global scope
    rows[[length(rows) + 1]] <- tibble(
      id         = basename(u),
      title      = coalesce(d$title, basename(u)),
      pdf_url    = coalesce(d$pdf, ""),
      doc_date   = coalesce(d$year, ""),
      doc_type   = coalesce(dtype, "other"),
      country    = d$countries,
      project_id = "",
      web_url    = u,
      status     = status
    )
    if (i %% 20 == 0) cli::cli_alert_info("pages: {i}/{length(cand)}")
  }
  results <- bind_rows(rows)
  cli::cli_alert_info("catalogued: {nrow(results)}")
  print(table(results$status))

  # year floor (kept docs with a known pre-2015 year are parked)
  results <- results %>%
    mutate(.yr = suppressWarnings(as.integer(doc_date)),
           status = ifelse(status %in% c("kept", "kept_global") &
                             !is.na(.yr) & .yr < CIF_YEAR_MIN,
                           "parked_old", status)) %>%
    select(-.yr)

  meta_path <- file.path(PATHS$data, "cif_metadata.csv")
  readr::write_csv(results, meta_path)
  cli::cli_alert_success("metadata: {meta_path}")

  kept <- results %>% filter(status %in% c("kept", "kept_global"), nzchar(pdf_url))
  cli::cli_h2("Downloading {nrow(kept)} kept documents")
  n_ok <- 0; n_fail <- 0; n_skip <- 0
  for (i in seq_len(nrow(kept))) {
    r <- kept[i, ]
    fname <- paste0(substr(glue("cif_{safe_filename(r$id)}_{coalesce(r$doc_date,'XXXX')}"), 1, 100), ".pdf")
    dest <- file.path(DOWNLOAD_DIR, fname)
    if (file.exists(dest)) {
      log_download(SOURCE_NAME, r$id, r$doc_type, r$title, r$pdf_url, dest,
                   "skipped", "Already exists")
      n_skip <- n_skip + 1; next
    }
    ok <- download_pdf(r$pdf_url, dest)
    if (identical(ok, TRUE)) {
      log_download(SOURCE_NAME, r$id, r$doc_type, r$title, r$pdf_url, dest, "success")
      n_ok <- n_ok + 1
    } else if (identical(ok, "skipped")) { n_skip <- n_skip + 1 }
    else {
      log_download(SOURCE_NAME, r$id, r$doc_type, r$title, r$pdf_url, dest,
                   "failed", "Download or validation failed")
      n_fail <- n_fail + 1
    }
  }
  cli::cli_h3("Summary")
  cli::cli_alert_success("downloaded: {n_ok} | failed: {n_fail} | skipped: {n_skip}")
  print_source_summary(SOURCE_NAME)
  invisible(results)
}

# Run if called directly. CIF_MODE: probe | capped | load | full (default)
if (sys.nframe() == 0 || !interactive()) {
  switch(Sys.getenv("CIF_MODE", "full"),
    probe  = cif_probe(),
    capped = run_cif_scraper(max_docs = 15),
    load   = invisible(NULL),
    run_cif_scraper()
  )
}
