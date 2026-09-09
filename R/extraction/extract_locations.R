##############################################################################
# extract_locations.R — SESSION 1 for the LOCATION-SPECIFIC template sheet
# (project_data_location-specific; protocol §5/§7 two-session design).
#
# Extracts, verbatim, one row per location x intervention (x result) from an
# evaluation PDF, plus an enumeration of every named intervention location.
# NO controlled-vocabulary choices here: subsector type, result_level,
# target_beneficiary category, location codes and the project_lead actor code
# are assigned afterwards in R/extraction/harmonize_locations.R.
#
# Carried over from extract_verbatim.R (v1.0 robustness):
#   page-tagged whole document, doc-first prompts (provider caching),
#   section maps for known big-document families, focus injection for
#   multi-project documents, results-framework pages attached as images,
#   mechanical fact-check of values/names against cited pages, junk gates.
#
# Usage:
#   Rscript R/extraction/extract_locations.R manifest.csv   # project_code,pdf,focus
#   Rscript R/extraction/extract_locations.R doc.pdf
#   EXTRACT_MODE=probe    -> locations group only (plumbing test)
#   EXTRACT_MODEL=...     -> model override (default gpt-5-mini)
#   EXTRACT_OUT_DIR=...   -> output folder (default outputs/extraction/locations)
# Requires OPENAI_API_KEY (~/.Renviron).
##############################################################################

suppressPackageStartupMessages({
  library(ellmer); library(pdftools); library(jsonlite); library(readr)
})

MODE  <- Sys.getenv("EXTRACT_MODE", "pilot")
MODEL <- Sys.getenv("EXTRACT_MODEL", "gpt-5-mini")
PROMPT_VERSION <- "loc-v1.1"   # v1.1: Africa-only rows, per-country rows for multi-country programs, focus repeated in rows task
MODEL_TAG <- gsub("[^a-z0-9]+", "-", tolower(MODEL))
# .Renviron lives in the OneDrive-redirected Documents folder; a shell that
# overrides HOME (e.g. Git Bash) makes R miss it — load it explicitly
if (!nzchar(Sys.getenv("OPENAI_API_KEY")))
  for (p in c(file.path(Sys.getenv("OneDrive"), "Documents", ".Renviron"),
              file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron")))
    if (file.exists(p)) { readRenviron(p); break }
stopifnot("OPENAI_API_KEY not set" = nzchar(Sys.getenv("OPENAI_API_KEY")))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 1 && grepl("\\.csv$", args[1])) {
  mf <- read.csv(args[1], stringsAsFactors = FALSE)
  mf[is.na(mf)] <- ""
  PDFS <- mf$pdf; FOCUS <- mf$focus; PCODE <- mf$project_code
} else {
  stopifnot("give a manifest CSV or PDF path(s)" = length(args) > 0)
  PDFS <- args; FOCUS <- rep("", length(PDFS)); PCODE <- rep("", length(PDFS))
}

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", "..")) else getwd()
OUT_DIR <- Sys.getenv("EXTRACT_OUT_DIR", file.path(REPO, "outputs", "extraction", "locations"))
RAW_DIR <- file.path(OUT_DIR, "raw")
dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)

MAX_CHARS <- 600000
digest_path <- function(x) sprintf("%08x", sum(utf8ToInt(x) * seq_along(utf8ToInt(x)) %% 97))

read_doc <- function(path) {
  if (nchar(path) > 250) {   # Windows long-path workaround (OneDrive depth)
    short <- file.path(tempdir(), paste0("x", substr(digest_path(path), 1, 8), ".pdf"))
    ok <- suppressWarnings(file.copy(paste0("\\\\?\\", gsub("/", "\\\\", path)),
                                     short, overwrite = TRUE))
    if (!ok) ok <- file.copy(path, short, overwrite = TRUE)
    stopifnot("could not copy long-path PDF" = ok)
    path <- short
  }
  pages <- pdf_text(path)
  list(pages = pages, n_pages = length(pages), local_path = path)
}

# ---- section maps: same families as extract_verbatim.R, but location and
# component detail lives in the body/annexes, so the wb_icr map additionally
# keeps component-description and annex pages (site lists sit there).
detect_doc_family <- function(pages) {
  head_txt <- tolower(paste(pages[seq_len(min(6, length(pages)))], collapse = " "))
  if (grepl("implementation completion and results report", head_txt)) return("wb_icr")
  if (grepl("independent evaluation office of the gef|evaluation of gef", head_txt)) return("gef_ieo")
  "generic"
}

select_pages <- function(pages, family, focus = "") {
  n <- length(pages)
  if (family == "generic" || n <= 100) return(rep(TRUE, n))
  low <- tolower(pages)
  keep <- rep(FALSE, n)
  keep[seq_len(min(12, n))] <- TRUE
  mark <- function(re, span = 0) {
    for (h in grep(re, low)) keep[h:min(n, h + span)] <<- TRUE
  }
  if (family == "wb_icr") {
    mark("data sheet")
    mark("context and development objectives|project context", 8)
    mark("\\boutcome\\b", 2)
    mark("results framework and key outputs", 28)
    mark("components?[:]|description of components|annex", 6)
  } else if (family == "gef_ieo") {
    keep[seq_len(min(30, n))] <- TRUE
    mark("annex 15|global environmental benefits", 8)
    if (nzchar(focus)) {
      acro <- regmatches(focus, regexpr("\\(([A-Z]{2,6})\\)", focus))
      acro <- tolower(gsub("[()]", "", acro))
      gid  <- regmatches(focus, regexpr("[0-9]{4}", focus))
      phrase <- tolower(trimws(sub("^the\\s+", "",
                sub("[(,].*$", "", tolower(focus)))))
      pats <- Filter(nzchar, c(
        if (length(acro)) paste0("\\b", acro, "\\b"),
        if (length(gid)) gid,
        if (nchar(phrase) > 8) phrase))
      if (length(pats)) {
        hit <- Reduce(`|`, lapply(pats, function(p) grepl(p, low)))
        keep[hit] <- TRUE
      }
    }
  }
  keep
}

RF_MAX_IMG <- 10
rf_pages <- function(pages) {
  low <- tolower(pages)
  hits <- grep(paste0("results framework|key outputs|logical framework|",
                      "logframe|cadre logique|matrice de r|cadre de r"), low)
  if (!length(hits)) return(integer(0))
  ann <- grep("annex\\s*[0-9ivx]*[.:]?\\s*(results framework|logical framework)", low)
  start <- if (length(ann)) ann[length(ann)] else hits[length(hits)]
  seq(start, min(length(pages), start + RF_MAX_IMG - 1))
}

build_doc_text <- function(pages, sel) {
  txt <- paste0("[page ", which(sel), "]\n", pages[sel], collapse = "\n\n")
  if (nchar(txt) > MAX_CHARS) {
    txt <- paste0(substr(txt, 1, round(MAX_CHARS * 0.7)), "\n...[clipped]...\n",
                  substr(txt, nchar(txt) - round(MAX_CHARS * 0.3) + 1, nchar(txt)))
  }
  txt
}

SYSTEM <- paste(
  "You are a meticulous VERBATIM data-extraction assistant for grey-literature",
  "project evaluation documents (African agriculture climate adaptation).",
  "Your subject is WHERE the project worked: the specific places where",
  "adaptation interventions were implemented, and what happened in each place.",
  "You extract passages and literal facts EXACTLY as the document states them.",
  "You never classify into external categories — that happens later, elsewhere.",
  "When a value or passage is not in the document, return an empty string.",
  "Report actual values, not planned/target ones. The text carries [page N]",
  "markers: always report the page number for everything you extract.",
  "HARD RULES: (1) Numbers describing the evaluation's own methodology",
  "(sample sizes, respondents, focus groups) are never project results —",
  "though the methodology itself belongs in evidence_methodology fields.",
  "(2) In documents covering several projects, read only this project's",
  "content. (3) Places named only as travel logistics, control/comparison",
  "sites, ministry office addresses or geographic context are NOT",
  "intervention locations.")

pg <- function() type_array(items = type_integer(),
  description = "Page numbers ([page N]) where this information was found.")

GROUPS <- list(

locations = list(
  task = paste(
    "Enumerate EVERY distinct named location in Africa where this project",
    "actually implemented adaptation interventions or reached beneficiaries.",
    "Sweep the WHOLE document: component descriptions, results sections,",
    "annex site lists, maps' captions, tables. Count each place once, at",
    "every level the document names it (a named village AND its district",
    "are two entries — each level gets its own entry). Include countries",
    "when the document works at country level. Exclude places that are",
    "only: evaluation travel stops, control/comparison sites, capital",
    "cities mentioned as ministry seats, other projects' sites, or",
    "geographic context (rivers, borders, climate zones)."),
  type = type_object(
    locations = type_array(description = "One entry per distinct named intervention location.",
      items = type_object(
        name = type_string("The location's name exactly as printed, without the administrative word — 'Kiboga', not 'Kiboga district'. For a country entry, the country name."),
        level_stated = type_string("The administrative level in the document's own words: village, town, city, commune, district, province, region, county, sub-county, watershed, country... Empty if the document never says."),
        country = type_string("Country this location is in."),
        page = type_integer("Page where this location is (first) named as an intervention site."))),
    enumeration_notes = type_string("One sentence: what kinds of lists were found where (e.g. '14 pilot villages listed in Annex 3 p.61; 4 districts named in component descriptions'). Empty if trivial."),
    source_pages = pg())),

location_rows = list(
  task = paste(
    "Extract the location-specific interventions and their results, as ROWS.",
    "One row = one intervention at one location (or one group of locations",
    "treated jointly). Work location by location through the document.",
    "RULES FOR ROWS:",
    "(a) If the document breaks an intervention's results down by location,",
    "make one row per location. If several locations are only ever treated",
    "jointly, make ONE row naming all of them.",
    "(b) A row does not need a result: an intervention described for a",
    "location with no reported outcome is still a row (leave result fields",
    "empty). But prefer rows WITH results where the document reports them.",
    "(c) COUNTRIES ARE LOCATIONS TOO: in a multi-country project or program,",
    "make one row PER COUNTRY whenever the document describes that country's",
    "activities or results — check per-country sections, annex tables listing",
    "countries, and country case studies. Do this for EVERY participating",
    "country the document covers, even briefly; finer site-level rows come",
    "in addition where the document gives them.",
    "(d) Never invent location-specificity: a project-wide total that the",
    "document does not tie to any named country or place is NOT a location",
    "row — skip it (it belongs to the project-level extraction, not here).",
    "(e) ONLY LOCATIONS IN AFRICA: rows for sites or countries outside",
    "Africa are never extracted, even when the program also works there.",
    "(f) All *_stated fields quote or closely paraphrase the document in",
    "max 50 words, in the document's language.",
    "RESULTS: a result is a quantity the project changed or delivered at",
    "that location — people reached/trained, hectares restored/irrigated,",
    "tons produced, km built, animals, groups formed, tCO2e avoided,",
    "adoption percentages. NEVER results: durations, calendar dates,",
    "counts of reports/meetings/missions, staffing or administrative",
    "numbers, disbursements or budget amounts, targets without actuals,",
    "the evaluation's own sample sizes, predecessor-program figures."),
  type = type_object(
    rows = type_array(description = "One entry per location x intervention (x result).",
      items = type_object(
        locations = type_string("Location NAME(S) this row applies to, exactly as the document names them, several joined by '; '. Use the finest level the row's evidence supports."),
        subsector_stated = type_string("The agricultural domain this intervention targets, quoted or closely paraphrased from the document, max 50 words (e.g. crop production, livestock, fisheries, land management, food distribution)."),
        intervention_stated = type_string("WHAT was implemented at this location, quoted or closely paraphrased, max 50 words (e.g. training, irrigation works, seed distribution, agroforestry, insurance product)."),
        rationale_stated = type_string("The stressor or perceived benefit this intervention responds to AT THIS LOCATION (drought, flooding, food insecurity, market access...), quoted or closely paraphrased, max 50 words. Empty if the document states none for this location."),
        target_beneficiary_stated = type_string("WHO this intervention targets at this location, in the document's own words (e.g. 'smallholder farmers', '200 women's groups'). Empty if unstated."),
        result_stated = type_string("The concrete result reported for this location, quoted or closely paraphrased, max 50 words. Empty if no result is reported."),
        result_value = type_string("The result's NUMBER only, as stated: '2829', '43', '>1,000'. Digits, no thousands separators where possible. Empty if the result is qualitative or there is none."),
        result_unit_stated = type_string("Counting unit/what-is-counted for that value, in the document's words: 'farmers trained', 'hectares', 'percent of groups'. Empty if no value."),
        evidence_methodology_stated = type_string("HOW the result was assessed, per the document: survey, interviews, monitoring data, field visits..., quoted or closely paraphrased, max 50 words. Empty if unstated."),
        evidence_source_stated = type_string("The evidence SOURCE named for the result: progress reports, M&E system, workshop reports, use metrics... Empty if unstated."),
        page = type_integer("Page where this row's core statement is."))),
    row_notes = type_string("Caveats affecting the rows (double counting across locations, contradictory site lists, data-quality warnings), briefly. Empty if none."),
    source_pages = pg()))
)

# ------------------------------------------------------- junk gates (code) --
word_count <- function(x) lengths(gregexpr("\\S+", x)) * nzchar(trimws(x))

fold_rows <- function(res, meta) {
  rl <- res$rows
  if (is.null(rl)) rl <- list()
  if (is.data.frame(rl)) rl <- lapply(seq_len(nrow(rl)), function(i) as.list(rl[i, ]))
  g <- function(r, f) { v <- r[[f]]; if (is.null(v) || !length(v) || is.na(v[1])) "" else as.character(v[1]) }
  keep <- vapply(rl, function(r) {
    loc <- g(r, "locations"); iv <- g(r, "intervention_stated")
    v <- tolower(g(r, "result_value")); m <- tolower(paste(g(r, "result_unit_stated"), g(r, "result_stated")))
    if (!nzchar(loc) || !nzchar(iv)) return(FALSE)                 # no anchor
    money    <- grepl("us\\$|usd|eur|cfaf|\\bua\\b|disburs|budget|grant amount", m)
    duration <- grepl("[0-9]\\s*-?\\s*(month|week|year)s?\\b", v) ||
                grepl("duration|extension|closing date", m)
    admin    <- grepl("reports?|meetings?|missions?|recommendations?|audits?|supervision", m) &&
                !grepl("beneficiar|farmer|train|hectare|household|workshop", m)
    !(money || duration || admin)
  }, logical(1))
  rl <- rl[keep]
  if (!length(rl)) return(NULL)
  df <- do.call(rbind, lapply(rl, function(r) {
    rs <- g(r, "result_stated"); rv <- g(r, "result_value")
    flags <- c(
      if (any(word_count(c(g(r, "subsector_stated"), g(r, "intervention_stated"),
                           g(r, "rationale_stated"), rs)) > 60)) "OVER 50 WORDS",
      if (nzchar(rv) && !grepl("[0-9]", rv)) "VALUE NOT NUMERIC")
    data.frame(
      locations_stated  = g(r, "locations"),
      subsector_stated  = g(r, "subsector_stated"),
      intervention_stated = g(r, "intervention_stated"),
      rationale_stated  = g(r, "rationale_stated"),
      target_beneficiary_stated = g(r, "target_beneficiary_stated"),
      result_stated     = rs,
      result_value      = rv,
      result_unit_stated = g(r, "result_unit_stated"),
      evidence_methodology_stated = g(r, "evidence_methodology_stated"),
      evidence_source_stated = g(r, "evidence_source_stated"),
      page = g(r, "page"),
      evidence_depth = if (nzchar(rs) || nzchar(rv)) "2" else "1",
      row_flags = paste(flags, collapse = "; "),
      stringsAsFactors = FALSE)
  }))
  for (m in names(meta)) df[[m]] <- meta[[m]]
  df$row_notes <- if (is.null(res$row_notes)) "" else as.character(res$row_notes)
  df
}

fold_locations <- function(res, meta) {
  ll <- res$locations
  if (is.null(ll)) ll <- list()
  if (is.data.frame(ll)) ll <- lapply(seq_len(nrow(ll)), function(i) as.list(ll[i, ]))
  if (!length(ll)) return(NULL)
  g <- function(r, f) { v <- r[[f]]; if (is.null(v) || !length(v) || is.na(v[1])) "" else as.character(v[1]) }
  df <- do.call(rbind, lapply(ll, function(r) data.frame(
    location_name = g(r, "name"), level_stated = g(r, "level_stated"),
    country = g(r, "country"), page = g(r, "page"), stringsAsFactors = FALSE)))
  df <- df[nzchar(df$location_name), , drop = FALSE]
  df <- df[!duplicated(tolower(paste(df$location_name, df$country))), , drop = FALSE]
  for (m in names(meta)) df[[m]] <- meta[[m]]
  df$enumeration_notes <- if (is.null(res$enumeration_notes)) "" else as.character(res$enumeration_notes)
  df
}

# ------------------------------------------------ verbatim fact-check (code) --
norm_txt <- function(x) {
  x <- tolower(x)
  x <- gsub("[‘’“”]", "'", x)
  x <- gsub("[–—]", "-", x)
  x <- gsub("[^a-z0-9]+", " ", x)
  trimws(x)
}
norm_num <- function(x) gsub("[^0-9]", "", x)

check_value <- function(value, page_cited, pages_txt) {
  v <- norm_num(value)
  if (!nzchar(v) || nchar(v) < 2) return("skipped")
  p <- suppressWarnings(as.integer(page_cited))
  cited <- if (!is.na(p)) max(1, p - 1):min(length(pages_txt), p + 1) else integer(0)
  hay <- norm_num(paste(pages_txt[cited], collapse = " "))
  if (nzchar(hay) && grepl(v, hay, fixed = TRUE)) return("verified")
  if (grepl(v, norm_num(paste(pages_txt, collapse = " ")), fixed = TRUE))
    return("found_other_page")
  "NOT FOUND"
}
check_name <- function(name, pages_txt) {
  n <- norm_txt(name)
  if (!nzchar(n) || nchar(n) < 3) return("skipped")
  if (grepl(n, norm_txt(paste(pages_txt, collapse = " ")), fixed = TRUE)) "verified"
  else "NOT FOUND"
}
# *_stated fields are quote-or-paraphrase: check token coverage on cited page
check_paraphrase <- function(txt, page_cited, pages_txt) {
  q <- norm_txt(txt)
  if (!nzchar(q) || nchar(q) < 12) return("skipped")
  p <- suppressWarnings(as.integer(page_cited))
  cited <- if (!is.na(p)) max(1, p - 1):min(length(pages_txt), p + 1) else integer(0)
  hay <- norm_txt(paste(pages_txt[cited], collapse = " "))
  tok <- strsplit(q, " ")[[1]]; tok <- tok[nchar(tok) > 3]
  if (length(tok) < 3) return("skipped")
  cov <- mean(vapply(tok, function(t) grepl(t, hay, fixed = TRUE), logical(1)))
  if (cov >= 0.85) "verified"
  else {
    hay_all <- norm_txt(paste(pages_txt, collapse = " "))
    cov_all <- mean(vapply(tok, function(t) grepl(t, hay_all, fixed = TRUE), logical(1)))
    if (cov_all >= 0.85) "found_other_page"
    else if (cov_all >= 0.55) "paraphrase (partial tokens)"
    else "NOT FOUND"
  }
}

verify_doc <- function(rows_df, locs_df, pages_txt, doc) {
  v <- list()
  add <- function(item, status) v[[length(v) + 1]] <<- data.frame(
    document = doc, item = item, status = status, stringsAsFactors = FALSE)
  if (!is.null(locs_df)) for (i in seq_len(nrow(locs_df)))
    add(paste0("location: ", substr(locs_df$location_name[i], 1, 40)),
        check_name(locs_df$location_name[i], pages_txt))
  if (!is.null(rows_df)) for (i in seq_len(nrow(rows_df))) {
    for (nm in strsplit(rows_df$locations_stated[i], ";\\s*")[[1]])
      if (tolower(nm) != "unspecified")
        add(paste0("row_", i, " loc: ", substr(nm, 1, 30)), check_name(nm, pages_txt))
    if (nzchar(rows_df$result_value[i]))
      add(paste0("row_", i, " value: ", rows_df$result_value[i]),
          check_value(rows_df$result_value[i], rows_df$page[i], pages_txt))
    add(paste0("row_", i, " intervention"),
        check_paraphrase(rows_df$intervention_stated[i], rows_df$page[i], pages_txt))
  }
  do.call(rbind, v)
}

# -------------------------------------------------------------- extraction --
extract_doc <- function(pdf_path, focus = "", pcode = "", groups = GROUPS) {
  doc_name <- tools::file_path_sans_ext(basename(pdf_path))
  cat("\n==", if (nzchar(pcode)) paste0(pcode, " · "), doc_name, "==\n")
  doc <- read_doc(pdf_path)
  fam <- detect_doc_family(doc$pages)
  sel <- select_pages(doc$pages, fam, focus)
  doc$text <- build_doc_text(doc$pages, sel)
  cat("  pages:", doc$n_pages, "| family:", fam, "| pages used:", sum(sel),
      "| chars:", nchar(doc$text),
      if (nzchar(focus)) paste0("| focus: ", focus), "\n")

  meta <- list(project_code_hint = pcode, document = basename(pdf_path),
               model = MODEL, prompt_version = PROMPT_VERSION,
               run_date = format(Sys.Date()))
  focus_line <- if (nzchar(focus)) paste0(
    "IMPORTANT — this document covers SEVERAL programs/projects. Extract ",
    "ONLY for ", focus, ". Ignore every other program's sites, rows and ",
    "results, and double-check each row: a location that belongs to another ",
    "program in this document must not appear. ") else ""
  raw <- list()
  for (gname in names(groups)) {
    g <- groups[[gname]]
    prompt <- paste0("DOCUMENT (page-tagged):\n\n", doc$text,
                     "\n\n---\nTASK: ", focus_line, g$task)
    t0 <- Sys.time()
    res <- tryCatch({
      chat <- chat_openai(model = MODEL, system_prompt = SYSTEM)
      imgs <- list()
      if (gname == "location_rows") {
        rfp <- rf_pages(doc$pages)
        for (p in rfp) {
          png <- file.path(tempdir(), paste0("rfl_", substr(digest_path(pdf_path), 1, 8),
                                             "_", p, ".png"))
          okp <- tryCatch({ pdftools::pdf_convert(doc$local_path, format = "png",
                            pages = p, filenames = png, dpi = 110, verbose = FALSE); TRUE },
                          error = function(e) FALSE)
          if (okp) imgs[[length(imgs) + 1]] <- content_image_file(png, resize = "none")
        }
        if (length(imgs)) {
          cat("  rf-vision  ", length(imgs), "table page(s) attached [page",
              rfp[1], "onward]\n")
          prompt <- paste0(prompt,
            "\n\nATTACHED IMAGES: the results-framework/table pages [page ",
            paste(rfp[seq_along(imgs)], collapse = ", "), "] rendered as ",
            "images, because table layouts scramble in the text layer. Read ",
            "location-disaggregated values from the images wherever the text ",
            "is unclear.")
        }
      }
      if (length(imgs)) do.call(chat$chat_structured,
                                c(list(prompt), imgs, list(type = g$type)))
      else chat$chat_structured(prompt, type = g$type)
    }, error = function(e) e)
    secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
    if (inherits(res, "error")) {
      warning(gname, " failed: ", conditionMessage(res))
      cat(sprintf("  %-14s FAILED (%ss): %s\n", gname, secs,
                  substr(conditionMessage(res), 1, 80)))
      next
    }
    cat(sprintf("  %-14s ok (%ss)\n", gname, secs))
    raw[[gname]] <- res
    write_json(res, file.path(RAW_DIR, paste0("s1loc_", substr(doc_name, 1, 55),
               "_", gname, ".json")), auto_unbox = TRUE, pretty = TRUE)
  }
  rows_df <- if (!is.null(raw$location_rows)) fold_rows(raw$location_rows, meta) else NULL
  locs_df <- if (!is.null(raw$locations)) fold_locations(raw$locations, meta) else NULL
  cat("  rows:", if (is.null(rows_df)) 0 else nrow(rows_df),
      "| locations enumerated:", if (is.null(locs_df)) 0 else nrow(locs_df), "\n")
  ver <- tryCatch(verify_doc(rows_df, locs_df, doc$pages, basename(pdf_path)),
                  error = function(e) { warning("verify failed: ", conditionMessage(e)); NULL })
  list(rows = rows_df, locations = locs_df, verify = ver)
}

if (MODE == "probe") GROUPS <- GROUPS["locations"]

out  <- Map(extract_doc, PDFS, FOCUS, PCODE)
rows <- dplyr::bind_rows(Filter(Negate(is.null), lapply(out, `[[`, "rows")))
locs <- dplyr::bind_rows(Filter(Negate(is.null), lapply(out, `[[`, "locations")))
vers <- do.call(rbind, Filter(Negate(is.null), lapply(out, `[[`, "verify")))

stamp <- paste0(MODEL_TAG, "_", format(Sys.time(), "%Y%m%d_%H%M"))
if (nrow(rows)) {
  f <- file.path(OUT_DIR, paste0("s1loc_rows_", stamp, ".csv"))
  write_csv(rows, f); cat("\nwritten:", f, "(", nrow(rows), "rows )\n")
}
if (nrow(locs)) {
  f <- file.path(OUT_DIR, paste0("s1loc_locations_", stamp, ".csv"))
  write_csv(locs, f); cat("written:", f, "(", nrow(locs), "locations )\n")
}
if (!is.null(vers)) {
  f <- file.path(OUT_DIR, paste0("verify_loc_", stamp, ".csv"))
  write_csv(vers, f)
  cat("verification report:", f, "\nverification summary:\n")
  print(table(vers$status))
}
