##############################################################################
# af.R — Adaptation Fund Document Scraper (via Climate Project Explorer /
#         Climate Policy Radar public API)
#
# Targets: EVALUATION documents (final/mid-term/terminal evaluations,
#          performance/completion reports) of Adaptation Fund projects in
#          Africa, 2015+. Proposals/project documents are catalogued but
#          not downloaded (parked rows).
#
# Retrieval channel (verified 2026-07-23): the PUBLIC, unauthenticated CPR
# REST API — the same backend that powers climateprojectexplorer.org, the
# Multilateral Climate Funds' joint platform:
#   GET https://api.climatepolicyradar.org/search/documents?query=...
#       (global index — results are filtered client-side to id prefix "AF.")
#   GET https://api.climatepolicyradar.org/families/{import_id}
#       (family = project; returns ALL its documents with direct PDF URLs:
#        cdn_object on cdn.climatepolicyradar.org + source_url on the fund's
#        own store fifspubprd.azureedge.net)
# Notes: the token-gated POST /api/v1/searches is NOT used (origin-bound JWT);
# no corpus filter exists server-side; document type is carried in the
# document TITLE ("Final evaluation report", "Project document", ...).
#
# The CPR client functions (cpr_*) are shared: gcf gap-fill reuses them with
# prefix "GCF." (see run_mcf_scraper).
#
# Run modes via env var AF_MODE: probe | capped | load | full (default)
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

SOURCE_NAME  <- "af"
DOWNLOAD_DIR <- file.path(PATHS$downloads, SOURCE_NAME)
dir.create(DOWNLOAD_DIR, recursive = TRUE, showWarnings = FALSE)

# ── Configuration ───────────────────────────────────────────────────────────
CPR_API <- "https://api.climatepolicyradar.org"
CPE_WEB <- "https://climateprojectexplorer.org"

# API mechanics (verified 2026-07-23): page_size caps at 100 and there is
# NO pagination beyond the first page — each query returns only its top-100
# by relevance. Enumeration therefore uses COUNTRY-TARGETED query templates
# (a country's fund documents rank at the top of its own query), which also
# surfaces GCF families in the same sweep.
MCF_QUERY_TEMPLATES <- c(
  "{country} final evaluation report",
  "{country} mid-term evaluation",
  "{country} project completion evaluation"
)

MCF_PAGE_SIZE <- 100

AF_YEAR_MIN <- 2015L

# Evaluation-type classification from the document TITLE
MCF_KEEP_RE <- paste(
  "final evaluation", "mid-?term evaluation", "terminal evaluation",
  "performance evaluation", "^evaluation report", "completion report",
  "mid-?term review", sep = "|")
MCF_PARK_RE <- paste(
  "project document", "pre-concept", "concept", "funding proposal",
  "inception report", "gender", "annual performance report", "esmp",
  "environmental and social", sep = "|")

mcf_doc_type <- function(title) {
  t <- tolower(coalesce(title, ""))
  if (grepl("final evaluation", t))                return("Final evaluation")
  if (grepl("mid-?term (evaluation|review)", t))   return("Mid-term evaluation")
  if (grepl("terminal evaluation", t))             return("Terminal evaluation")
  # NOTE: (annual) performance REPORTS are progress documents — out of scope
  # as standalone sources; only performance EVALUATIONS count
  if (grepl("performance evaluation", t))          return("Performance evaluation")
  if (grepl("completion report", t))               return("Completion report")
  if (grepl("^evaluation report$|^evaluation", t)) return("Evaluation report")
  NA_character_
}

# Africa ISO3 (54 AU member states)
AFRICA_ISO3 <- c(
  "DZA","AGO","BEN","BWA","BFA","BDI","CPV","CMR","CAF","TCD","COM","COD",
  "COG","CIV","DJI","EGY","GNQ","ERI","SWZ","ETH","GAB","GMB","GHA","GIN",
  "GNB","KEN","LSO","LBR","LBY","MDG","MWI","MLI","MRT","MUS","MAR","MOZ",
  "NAM","NER","NGA","RWA","STP","SEN","SYC","SLE","SOM","ZAF","SSD","SDN",
  "TZA","TGO","TUN","UGA","ZMB","ZWE"
)

# ── CPR API client (shared by AF and the GCF gap-fill) ─────────────────────
cpr_get_json <- function(url) {
  Sys.sleep(runif(1, HTTP_CONFIG$delay_min, HTTP_CONFIG$delay_max))
  safe_get_json(url)
}

#' Search /search/documents (top-100 by relevance; no deeper pagination)
cpr_search_top <- function(query) {
  url <- paste0(CPR_API, "/search/documents?query=",
                utils::URLencode(query, reserved = TRUE),
                "&page_size=", MCF_PAGE_SIZE)
  js <- cpr_get_json(url)
  if (is.null(js)) return(NULL)
  js$results
}

#' Sweep country-targeted queries; collect family import_ids per prefix
#' (e.g. c("AF.", "GCF.")). Results cached to data/mcf_family_ids.csv so
#' the GCF gap-fill reuses the same sweep.
cpr_collect_family_ids <- function(prefixes = c("AF.", "GCF."),
                                   countries = AFRICA_COUNTRIES_EN,
                                   use_cache = TRUE) {
  cache <- file.path(PATHS$data, "mcf_family_ids.csv")
  if (use_cache && file.exists(cache)) {
    df <- readr::read_csv(cache, show_col_types = FALSE)
    cli::cli_alert_info("family ids loaded from cache: {nrow(df)}")
    return(df)
  }
  fam <- list()
  n_q <- 0
  for (co in countries) {
    for (tpl in MCF_QUERY_TEMPLATES) {
      n_q <- n_q + 1
      res <- cpr_search_top(sub("\\{country\\}", co, tpl))
      if (is.null(res)) next
      for (r in res) {
        id <- r$id
        for (pref in prefixes) {
          if (startsWith(id, pref)) {
            # authoritative family id from the member_of relation
            # (r$documents is sometimes a single relation object, sometimes
            # an array of them); fall back to deriving from the document id
            fid <- NULL
            rels <- r$documents
            if (!is.null(rels)) {
              if (!is.null(rels$type)) rels <- list(rels)
              for (rel in rels) {
                if (identical(rel$type, "member_of") && !is.null(rel$value$id)) {
                  fid <- rel$value$id; break
                }
              }
            }
            if (is.null(fid)) {
              code <- sub("^[A-Z]+\\.document\\.([A-Za-z0-9_]+)\\..*$", "\\1", id)
              if (!identical(code, id)) {
                fid <- paste0(sub("\\.$", "", pref), ".family.", code, ".0")
              }
            }
            if (!is.null(fid)) fam[[fid]] <- pref
          }
        }
      }
    }
    if (n_q %% 30 == 0) cli::cli_alert_info("queries: {n_q} | families: {length(fam)}")
  }
  df <- tibble(family_id = names(fam), prefix = unlist(fam))
  if (use_cache) {  # only persist full sweeps (partial runs must not poison the cache)
    readr::write_csv(df, cache)
    cli::cli_alert_success("family sweep done: {nrow(df)} families ({n_q} queries); cached")
  } else {
    cli::cli_alert_success("family sweep done: {nrow(df)} families ({n_q} queries); not cached (partial)")
  }
  df
}

#' Fetch one family; returns NULL or a list(family, docs tibble)
cpr_get_family <- function(fid) {
  js <- cpr_get_json(paste0(CPR_API, "/families/", fid))
  if (is.null(js) || is.null(js$data)) return(NULL)
  d <- js$data
  docs <- purrr::map(d$documents, function(doc) {
    tibble(
      id           = coalesce(doc$import_id, ""),
      doc_title    = coalesce(doc$title, ""),
      cdn_url      = coalesce(doc$cdn_object, ""),
      source_url   = coalesce(doc$source_url, ""),
      content_type = coalesce(doc$content_type, ""),
      md5          = coalesce(doc$md5_sum, ""),
      doc_slug     = coalesce(doc$slug, "")
    )
  }) %>% bind_rows()
  list(
    import_id   = d$import_id,
    title       = coalesce(d$title, ""),
    slug        = coalesce(d$slug, ""),
    geographies = unlist(d$geographies),
    published   = coalesce(d$published_date, ""),
    corpus_id   = coalesce(d$corpus_id, ""),
    docs        = docs
  )
}

# ── Probe ───────────────────────────────────────────────────────────────────
af_probe <- function() {
  cli::cli_h2("CPR API probe")
  p0 <- cpr_search_top("Senegal final evaluation report")
  ok_search <- !is.null(p0) && length(p0) > 0
  n_af <- if (ok_search) sum(vapply(p0, function(r) startsWith(r$id, "AF."), logical(1))) else 0
  cli::cli_alert_info("country query: {if (ok_search) length(p0) else 'FAIL'} results, {n_af} AF hits")

  fam <- cpr_get_family("AF.family.007NSNCR.0")
  ok_family <- !is.null(fam) && nrow(fam$docs) > 0
  cli::cli_alert_info("family fetch (Senegal 007NSNCR): {if (ok_family) paste(nrow(fam$docs), 'documents') else 'FAIL'}")

  ok_pdf <- FALSE
  if (ok_family) {
    u <- fam$docs$cdn_url[nzchar(fam$docs$cdn_url)][1]
    resp <- tryCatch(httr::GET(u, httr::user_agent(HTTP_CONFIG$user_agent),
                               httr::timeout(HTTP_CONFIG$timeout_sec)),
                     error = function(e) NULL)
    if (!is.null(resp) && httr::status_code(resp) == 200) {
      raw5 <- httr::content(resp, as = "raw")[1:5]
      ok_pdf <- identical(rawToChar(raw5), "%PDF-")
    }
    cli::cli_alert_info("CDN PDF valid: {ok_pdf}")
  }
  verdict <- c(search = ok_search, family = ok_family, pdf = ok_pdf)
  print(verdict)
  invisible(verdict)
}

# ── Core: build catalogue + download for one fund prefix ───────────────────
run_mcf_scraper <- function(prefix = "AF.", source_name = "af",
                            countries = AFRICA_COUNTRIES_EN,
                            year_min = AF_YEAR_MIN) {
  cli::cli_h1("MCF scraper via CPR API — prefix {prefix}")
  dl_dir <- file.path(PATHS$downloads, source_name)
  dir.create(dl_dir, recursive = TRUE, showWarnings = FALSE)

  # only trust/write the sweep cache on a full-country sweep
  fam_df <- cpr_collect_family_ids(prefixes = c("AF.", "GCF."),
                                   countries = countries,
                                   use_cache = length(countries) >= 50)
  fam_ids <- fam_df$family_id[fam_df$prefix == prefix]
  cli::cli_alert_success("{length(fam_ids)} candidate families for {prefix}")

  rows <- list()
  n_f <- 0; n_guidance <- 0
  project_corpus <- paste0("MCF.corpus.", sub("\\.$", "", prefix), ".n0000")
  for (fid in fam_ids) {
    n_f <- n_f + 1
    fam <- cpr_get_family(fid)
    if (is.null(fam)) next
    if (!identical(fam$corpus_id, project_corpus)) { n_guidance <- n_guidance + 1; next }
    in_africa <- length(intersect(fam$geographies, AFRICA_ISO3)) > 0
    fam_year <- suppressWarnings(as.integer(substr(fam$published, 1, 4)))
    proj_code <- sub("^[A-Z]+\\.family\\.([A-Za-z0-9]+)\\..*$", "\\1", fam$import_id)

    for (i in seq_len(nrow(fam$docs))) {
      doc <- fam$docs[i, ]
      dtype <- mcf_doc_type(doc$doc_title)
      status <- if (!in_africa) "out_of_scope_geo"
                else if (!is.na(dtype)) "kept"
                else "parked"
      rows[[length(rows) + 1]] <- tibble(
        id          = doc$id,
        title       = paste0(fam$title, " — ", doc$doc_title),
        pdf_url     = ifelse(nzchar(doc$cdn_url), doc$cdn_url, doc$source_url),
        doc_date    = fam$published,
        doc_type    = coalesce(dtype, doc$doc_title),
        country     = paste(fam$geographies, collapse = ";"),
        project_id  = proj_code,
        web_url     = paste0(CPE_WEB, "/document/", fam$slug),
        source_url  = doc$source_url,
        content_type = doc$content_type,
        md5         = doc$md5,
        family_id   = fam$import_id,
        family_year = fam_year,
        status      = status
      )
    }
    if (n_f %% 20 == 0) cli::cli_alert_info("families processed: {n_f}/{length(fam_ids)}")
  }
  results <- bind_rows(rows)
  cli::cli_alert_info("guidance/non-project families skipped: {n_guidance}")
  cli::cli_alert_info("documents catalogued: {nrow(results)}")
  cli::cli_alert_info("status: {paste(capture.output(print(table(results$status))), collapse=' / ')}")

  # date floor on kept docs (family year is approval-era; evaluations come
  # later, so a family year >= year_min - 10 with unknown doc year is kept
  # flagged; strict floor only when family clearly predates scope era)
  results <- results %>%
    mutate(status = ifelse(
      status == "kept" & !is.na(family_year) & family_year < (year_min - 10),
      "parked_old", status))

  meta_path <- file.path(PATHS$data, paste0(source_name, "_metadata.csv"))
  readr::write_csv(results, meta_path)
  cli::cli_alert_success("metadata: {meta_path}")

  # downloads
  kept <- results %>% filter(status == "kept", nzchar(pdf_url))
  cli::cli_h2("Downloading {nrow(kept)} kept documents")
  n_ok <- 0; n_fail <- 0; n_skip <- 0
  for (i in seq_len(nrow(kept))) {
    r <- kept[i, ]
    ext <- tolower(tools::file_ext(sub("\\?.*$", "", r$pdf_url)))
    if (!nzchar(ext) || nchar(ext) > 4) ext <- "pdf"
    ftype <- safe_filename(r$doc_type)
    fname <- glue("{source_name}_{r$project_id}_{ftype}_{coalesce(as.character(r$family_year),'XXXX')}.{ext}")
    dest <- file.path(dl_dir, fname)
    if (file.exists(dest)) {
      log_download(source_name, r$project_id, r$doc_type, r$title, r$pdf_url,
                   dest, "skipped", "Already exists")
      n_skip <- n_skip + 1; next
    }
    ok <- download_pdf(r$pdf_url, dest)
    if (identical(ok, FALSE) && nzchar(r$source_url) && r$source_url != r$pdf_url) {
      ok <- download_pdf(r$source_url, dest)
    }
    # non-PDF types (docx evals): download_pdf rejects them — fetch raw
    if (identical(ok, FALSE) && ext != "pdf") {
      resp <- tryCatch(httr::GET(r$pdf_url, httr::user_agent(HTTP_CONFIG$user_agent),
                                 httr::timeout(HTTP_CONFIG$timeout_sec)),
                       error = function(e) NULL)
      if (!is.null(resp) && httr::status_code(resp) == 200) {
        writeBin(httr::content(resp, as = "raw"), dest)
        ok <- file.size(dest) > 10240
      }
    }
    if (identical(ok, TRUE)) {
      log_download(source_name, r$project_id, r$doc_type, r$title, r$pdf_url,
                   dest, "success")
      n_ok <- n_ok + 1
    } else if (identical(ok, "skipped")) {
      n_skip <- n_skip + 1
    } else {
      log_download(source_name, r$project_id, r$doc_type, r$title, r$pdf_url,
                   dest, "failed", "Download or validation failed")
      n_fail <- n_fail + 1
    }
    if (i %% 10 == 0) cli::cli_alert_info("downloads: {i}/{nrow(kept)} (ok {n_ok}, fail {n_fail}, skip {n_skip})")
  }
  cli::cli_h3("Summary")
  cli::cli_alert_success("downloaded: {n_ok} | failed: {n_fail} | skipped: {n_skip}")
  print_source_summary(source_name)
  invisible(results)
}

run_af_scraper <- function(countries = AFRICA_COUNTRIES_EN) {
  run_mcf_scraper(prefix = "AF.", source_name = "af", countries = countries)
}

# Run if called directly. AF_MODE: probe | capped | load | full (default)
if (sys.nframe() == 0 || !interactive()) {
  switch(Sys.getenv("AF_MODE", "full"),
    probe  = af_probe(),
    capped = run_af_scraper(countries = c("Senegal", "Kenya", "Madagascar")),
    load   = invisible(NULL),
    run_af_scraper()
  )
}
