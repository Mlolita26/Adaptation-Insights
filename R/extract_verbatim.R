##############################################################################
# extract_verbatim.R — SESSION 1 of the two-session extraction design
# (protocol §5/§7: Session 1 = verbatim extraction, Session 2 = coding).
#
# This script extracts ONLY verbatim passages and literal facts from one or
# more evaluation PDFs — no controlled-vocabulary choices are made here.
# Controlled-value harmonisation happens afterwards in R/harmonize.R, which
# sees only the short verified extracts, never the documents.
#
# Why: (a) verbatim outputs can be FACT-CHECKED mechanically — this script
# string-matches every quote and literal value against the cited page and
# writes a verification report; (b) one job per prompt (BTR lesson);
# (c) vocabulary changes re-run only Session 2, no document is re-read.
#
# Method carried over from extract_general.R (BTR_Analysis lineage):
# separate prompt per field group, whole page-tagged document doc-first
# (provider prompt caching), structured output, per-group tryCatch,
# JSON audit per group, timestamped CSV per run, prompt_version stamping.
#
# evidence_depth is NOT asked of the model: it is derived in code from what
# Session 1 found (results present -> 2, else 1), deterministically.
#
# Usage:
#   Rscript R/extract_verbatim.R                    # gold-standard P001
#   Rscript R/extract_verbatim.R doc1.pdf doc2.pdf  # any documents
#   EXTRACT_MODE=probe  -> identity group only (plumbing test)
#   EXTRACT_MODEL=gpt-5-nano -> cheaper model
# Requires OPENAI_API_KEY (~/.Renviron).
##############################################################################

suppressPackageStartupMessages({
  library(ellmer); library(pdftools); library(jsonlite); library(readr)
})

MODE  <- Sys.getenv("EXTRACT_MODE", "pilot")
MODEL <- Sys.getenv("EXTRACT_MODEL", "gpt-5-mini")
PROMPT_VERSION <- "s1-v0.7"   # v0.7: implementation_period field + R-derived years, body co-implementors, no predecessor figures, no account numbers as IDs
MODEL_TAG <- gsub("[^a-z0-9]+", "-", tolower(MODEL))   # for output file names
stopifnot("OPENAI_API_KEY not set" = nzchar(Sys.getenv("OPENAI_API_KEY")))

GL <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature"
GOLD_P001 <- file.path(GL, "Data/Docs/Selection_mixed stakeholders/P001",
  "P001_World Bank_Implementation Completion and Results Report_2019_worldbank_3A-AFCC2_RI_-Support_to_NPCA_TerrAfrica_Secretariat_--_P149269_Implementation_Completion_and_Results_Report_2019.pdf")

# Input: PDF path(s), or a MANIFEST csv (columns: project_code, pdf, focus).
# `focus` handles multi-project documents: it is injected into every prompt
# so the model extracts only for the named program (e.g. the shared GEF
# Food Systems evaluation covering RFS + GGP + CFI).
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 1 && grepl("\\.csv$", args[1])) {
  mf <- read.csv(args[1], stringsAsFactors = FALSE)
  mf[is.na(mf)] <- ""
  PDFS <- mf$pdf; FOCUS <- mf$focus; PCODE <- mf$project_code
} else {
  PDFS <- if (length(args)) args else GOLD_P001
  FOCUS <- rep("", length(PDFS)); PCODE <- rep("", length(PDFS))
}

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..")) else getwd()
OUT_DIR <- file.path(REPO, "data", "extraction")
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
  list(pages = pages, n_pages = length(pages))
}

# ------------------------------------------------- section maps (big docs) --
# For known document families the template fields live in fixed sections, so
# long documents are cut to those pages BEFORE prompting — this replaces the
# blind head+tail clip that lost mid-document facts (e.g. program start years
# on p.191 of the 294-page GEF IEO evaluation). Selected pages keep their
# ORIGINAL [page N] numbers, so citations and the fact-check stay valid.
# Unknown families and documents under 100 pages keep every page.
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
  keep[seq_len(min(12, n))] <- TRUE            # cover, data sheet, TOC
  mark <- function(re, span = 0) {
    for (h in grep(re, low)) keep[h:min(n, h + span)] <<- TRUE
  }
  if (family == "wb_icr") {
    mark("data sheet")
    mark("context and development objectives|project context", 8)
    mark("\\boutcome\\b", 2)
    mark("results framework and key outputs", 28)
    mark("project cost by component", 2)
    mark("recipient, co-financier", 4)
  } else if (family == "gef_ieo") {
    keep[seq_len(min(30, n))] <- TRUE          # exec summary + program tables
    mark("annex 15|global environmental benefits", 8)
    if (nzchar(focus)) {                       # the focus program's own pages
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

build_doc_text <- function(pages, sel) {
  txt <- paste0("[page ", which(sel), "]\n", pages[sel], collapse = "\n\n")
  if (nchar(txt) > MAX_CHARS) {                # backstop clip, BTR-style
    txt <- paste0(substr(txt, 1, round(MAX_CHARS * 0.7)), "\n...[clipped]...\n",
                  substr(txt, nchar(txt) - round(MAX_CHARS * 0.3) + 1, nchar(txt)))
  }
  txt
}

SYSTEM <- paste(
  "You are a meticulous VERBATIM data-extraction assistant for grey-literature",
  "project evaluation documents (African agriculture climate adaptation).",
  "You extract passages and literal facts EXACTLY as the document states them.",
  "You never classify into external categories — that happens later, elsewhere.",
  "When a value or passage is not in the document, return an empty string.",
  "Report actual values, not planned/target ones. The text carries [page N]",
  "markers: always report the page number for everything you extract, and",
  "make quotes exact so they can be verified against the page by machine.",
  "HARD RULES: (1) Numbers describing the evaluation's own methodology",
  "(sample sizes, respondents, focus-group participants) are never project",
  "results. (2) In tables covering several projects, read only this",
  "project's row. (3) If two tables contradict each other, use the data",
  "sheet / basic-data table and mention the contradiction in the nearest",
  "notes field.")

pg <- function() type_array(items = type_integer(),
  description = "Page numbers ([page N]) where this information was found.")

GROUPS <- list(

identity = list(
  task = "Extract the project identity and timeline, verbatim from the document.",
  type = type_object(
    project_title  = type_string("Title of the adaptation project, word by word as stated (title page, 'project title'/'project name')."),
    project_id     = type_string("The publisher's project identifier exactly as printed IN THIS DOCUMENT, e.g. 'P149269'. Empty if none printed."),
    project_lead_name = type_string("NAME of the ORGANISATION leading the project, as the document names it (often the implementing agency or publisher, e.g. 'World Bank'). Never an internal department, global practice, division or regional unit of an organisation — name the organisation itself."),
    publication_year = type_string("Year the source document was published (front page)."),
    start_year     = type_string("Year the project ACTUALLY started per the document (approval, signature, effectiveness or official launch). Never design/concept/endorsement years. If no formal date is stated but the document gives an explicit implementation period ('implemented between 2017 and 2022', 'implementation phase 2004-2007'), use its first year. Empty only if neither is stated."),
    start_year_evidence = type_string("Short exact quote stating the start (e.g. 'Approval 29-Apr-2014', 'implemented between 2017 and 2022'), with its wording unchanged."),
    closure_year   = type_string("Year the project ACTUALLY closed ('actual closing', 'completed in'; the last year of an explicit implementation period counts if the project is described as finished). Empty if still running ('to date') or not stated."),
    closure_year_evidence = type_string("Short exact quote stating the closing."),
    implementation_period = type_string("The implementation period exactly as the document states it, e.g. '2017-2022' or 'implemented between 2017 and 2022', if any such statement exists. Empty otherwise."),
    document_type_stated = type_string("The document's OWN designation of itself, verbatim (e.g. 'Implementation Completion and Results Report', 'Project Performance Evaluation Report', 'Mid-term evaluation of the project ...')."),
    resource_id    = type_string("The DOCUMENT's own report/document number as printed, e.g. 'ICR00004643', 'GEF/E/C.70/02'. NEVER a grant, loan or trust-fund account number (TF-..., IDA-..., 2100155...). Empty if none."),
    source_pages   = pg())),

geography = list(
  task = paste(
    "Extract the geographic scope verbatim. Review the whole document and",
    "aggregate location lists that appear in different sections."),
  type = type_object(
    scope_stated   = type_string("Exact quote of the document's own statement of geographic scope/coverage (e.g. 'The study's geographical scope was nationwide' or the countries list)."),
    location_count = type_string("Number of DISTINCT African locations named anywhere as receiving interventions, counted at the MOST PRECISE level the document supports: if specific villages, sites or districts are enumerated, count those (e.g. '20 pilot villages' beats '4 countries'); fall back to counting countries only when nothing finer is enumerated. Aggregate across the whole document; count each location once. Prefix ~ for estimates; 'N/A' if unspecified."),
    location_count_basis = type_string("One sentence saying exactly what was counted, at which level (villages/districts/countries) and where the lists are (pages), so the count can be checked."),
    location_notes = type_string("Scope beyond Africa as 'total of X international locations, of which Y African'. Empty if Africa-only."),
    source_pages   = pg())),

rationale = list(
  task = "Extract why the project was implemented and who it targets, verbatim.",
  type = type_object(
    rationale_project = type_string("The context-specific rationale: climatic and non-climatic hazards, stressors, pain points and perceived benefits that justified the project — quoting or closely summarising the document, ONE sentence up to 100 words, capturing ALL stated drivers and their interactions."),
    target_beneficiary_stated = type_string("EXACT quote (verbatim, machine-checkable) of the passage naming who the project targets/benefits."),
    target_beneficiary_page = type_integer("Page of that quote."),
    GESI_project = type_string("Summary of gender-equality and social-inclusion content as presented (management, design, results, disaggregation, indigenous communities, local knowledge). Empty string if none."),
    source_pages = pg())),

results = list(
  task = paste(
    "Extract ALL quantitative project-level ACTUAL results, exhaustively.",
    "Check the results framework / indicator annex first. Include results",
    "whose target was NOT achieved and failed yes/no indicators (a failure",
    "is a finding). Report metric and unit AS THE DOCUMENT WORDS THEM — do",
    "not translate into any external category. Do NOT include: targets",
    "without actuals, the evaluation's own methodology numbers, rows from",
    "survey questionnaires, interview forms or annexed data-collection",
    "instruments (questions, rating scales, respondent tallies),",
    "PREDECESSOR or historical program figures (results of earlier phases",
    "or prior initiatives are background, not this project's results), other",
    "projects' results, or FINANCING figures (budgets/disbursements are",
    "inputs, not results)."),
  type = type_object(
    results = type_array(description = "One entry per distinct quantitative actual result.",
      items = type_object(
        value  = type_string("Actual value as stated, e.g. '14325', '>1,000', 'N'."),
        metric_stated = type_string("What is counted, in the document's own words (the indicator name or phrase, verbatim)."),
        unit_stated   = type_string("Counting unit in the document's own words (e.g. 'farmers', 'ha', 'percent'). Empty if none stated."),
        indicator_level = type_enum(values = c("PDO/outcome", "intermediate", "narrative"),
          description = "PDO/outcome = development-objective or outcome indicator; intermediate = component/output indicator; narrative = figure in running text only."),
        status = type_enum(values = c("achieved", "partially achieved", "not achieved", "no target stated"),
          description = "Achievement vs target, as the document rates it."),
        scope  = type_string("Denominator/coverage: which component, geography, whole program or one country, unique or aggregated counts. One short phrase."),
        page   = type_integer("Page where the actual value is stated.")
      )),
    result_notes = type_string("Caveats changing how the numbers read (double counting, data quality, contradictions) plus notable failed indicators, briefly. Empty if none."),
    source_pages = pg())),

finance = list(
  task = paste(
    "Extract the project financing verbatim. Read the TITLE PAGE wording and",
    "the financing/data-sheet table first."),
  type = type_object(
    budget_total = type_string("Total budget: sum of ALL financing sources (lead funder + co-financing + counterpart + in-kind). Digits only, EXPANDED to full units: 'UA 1.71 million' -> 1710000, 'USD 3.75 million' -> 3750000."),
    budget_lead_share = type_string("The lead funder's / main envelope alone (e.g. the GEF or IDA amount), digits only, expanded to full units. Empty if same as budget_total."),
    disbursed    = type_string("Total actually disbursed ('actual disbursed'/'actual at closing'). Data sheet wins on contradictions (flag them in finance_notes). Digits only, expanded to full units (1.39 million -> 1390000)."),
    currency     = type_string("ISO currency code, e.g. 'USD', 'EUR', 'UA'."),
    instrument_stated = type_string("EXACT wording of the financing instrument(s) from the title page or financing table, verbatim (e.g. 'ON A CREDIT ... AND A GRANT', 'SMALL GRANT', 'GEF Trust Fund grants')."),
    funding_mechanism_portion = type_string("INSTRUMENT-TYPE mix (grant/loan/investment/other — never fund or account names) WITH PERCENTAGES in parentheses joined by ' + ', per the template format: 'grant (40%) + loan (40%) + other-in-kind contribution (20%)'. Compute percentages from stated amounts when the document gives amounts but no percentages. Empty if the split cannot be established."),
    funder_names      = type_array(items = type_string(), description = "NAMES of all funding ORGANISATIONS incl. named trust funds and co-financiers, as the document names them. Never account/grant numbers like 'TF-17015' or 'IDA-52030', and never financing-table row labels or generic categories ('Borrower/Recipient', 'Local Beneficiaries', 'Bilateral Agencies') - only actual named organisations."),
    implementor_names = type_array(items = type_string(), description = "NAMES of the implementing agencies: those designated by the data sheet PLUS any co-implementing national agencies named in the document body (multi-country projects often have one agency per country while the data sheet names only one). Not private partners, borrowers or buyers."),
    finance_notes = type_string("Contradictions between financing tables, counterpart funding that never materialized, or similar. Empty if none."),
    source_pages = pg()))
)

# ---------------------------------------------------- result ranking (code) --
rank_results <- function(rl) {
  if (!length(rl)) return(rl)
  score <- vapply(rl, function(r) {
    s <- 0
    if (identical(r$indicator_level, "PDO/outcome")) s <- s + 100
    if (identical(r$indicator_level, "intermediate")) s <- s + 50
    if (grepl("beneficiar", tolower(paste(r$metric_stated, r$unit_stated)))) s <- s + 10
    s
  }, numeric(1))
  rl[order(-score, seq_along(rl))]
}

fold_results <- function(res, row) {
  rl <- res$results
  if (is.null(rl)) rl <- list()
  if (is.data.frame(rl)) rl <- lapply(seq_len(nrow(rl)), function(i) as.list(rl[i, ]))
  is_money <- vapply(rl, function(r) grepl(
    "US\\$|USD|EUR|CFAF|\\bUA\\b|disburs|financ|budget|grant amount",
    paste(r$unit_stated, r$metric_stated), ignore.case = TRUE), logical(1))
  rl <- rl[!is_money]
  achieved <- Filter(function(r) !identical(r$status, "not achieved"), rl)
  failed   <- Filter(function(r) identical(r$status, "not achieved"), rl)
  top <- rank_results(achieved)
  for (i in 1:3) {
    r <- if (length(top) >= i) top[[i]] else NULL
    row[[paste0("result", i)]] <- if (is.null(r)) "" else as.character(r$value)
    row[[paste0("result", i, "_metric_stated")]] <- if (is.null(r)) "" else as.character(r$metric_stated)
    row[[paste0("result", i, "_unit_stated")]]   <- if (is.null(r)) "" else as.character(r$unit_stated)
    row[[paste0("result", i, "_scope")]] <- if (is.null(r)) "" else as.character(r$scope)
    row[[paste0("result", i, "_page")]]  <- if (is.null(r)) "" else as.character(r$page)
  }
  extra <- if (length(top) > 3)
    paste0("further results: ", paste(vapply(top[4:length(top)], function(r)
      paste0(r$value, " ", r$metric_stated, " (", r$scope, ", p", r$page, ")"),
      character(1)), collapse = "; ")) else ""
  fails <- if (length(failed))
    paste0("NOT achieved: ", paste(vapply(failed, function(r)
      paste0(r$metric_stated, " (", r$value, ", p", r$page, ")"), character(1)),
      collapse = "; ")) else ""
  notes <- if (is.null(res$result_notes)) "" else as.character(res$result_notes)
  row$result_notes <- paste(Filter(nzchar, c(notes, fails, extra)), collapse = " | ")
  row$results_all_n <- as.character(length(rl))
  # evidence_depth derived deterministically (protocol: 2 = results evidence)
  row$evidence_depth <- if (length(rl)) "2" else "1"
  row
}

# ------------------------------------------------ verbatim fact-check (code) --
norm_txt <- function(x) {
  x <- tolower(x)
  x <- gsub("[\u2018\u2019\u201c\u201d]", "'", x)
  x <- gsub("[\u2013\u2014]", "-", x)
  x <- gsub("[^a-z0-9]+", " ", x)
  trimws(x)
}
norm_num <- function(x) gsub("[^0-9]", "", x)

check_quote <- function(quote, pages_cited, pages_txt) {
  q <- norm_txt(quote)
  if (!nzchar(q) || nchar(q) < 8) return("skipped")
  cited <- unique(unlist(lapply(pages_cited, function(p)
    max(1, p - 1):min(length(pages_txt), p + 1))))
  cited <- cited[cited >= 1 & cited <= length(pages_txt)]
  hay_cited <- norm_txt(paste(pages_txt[cited], collapse = " "))
  if (grepl(q, hay_cited, fixed = TRUE)) return("verified")
  if (grepl(q, norm_txt(paste(pages_txt, collapse = " ")), fixed = TRUE))
    return("found_other_page")
  # table cells are not contiguous in extracted text: if ~all tokens of the
  # quote sit on the cited page(s), it is a table reconstruction, not invented
  tok <- strsplit(q, " ")[[1]]; tok <- tok[nchar(tok) > 2]
  if (length(tok) >= 2 &&
      mean(vapply(tok, function(t) grepl(t, hay_cited, fixed = TRUE), logical(1))) >= 0.9)
    return("verified_tokens (table)")
  "NOT FOUND"
}
check_value <- function(value, pages_cited, pages_txt) {
  v <- norm_num(value)
  if (!nzchar(v) || nchar(v) < 2) return("skipped")
  cited <- unique(unlist(lapply(pages_cited, function(p)
    max(1, p - 1):min(length(pages_txt), p + 1))))
  hay <- norm_num(paste(pages_txt[cited], collapse = " "))
  if (grepl(v, hay, fixed = TRUE)) return("verified")
  if (grepl(v, norm_num(paste(pages_txt, collapse = " ")), fixed = TRUE))
    return("found_other_page")
  "NOT FOUND"
}

check_name <- function(name, pages_txt) {   # actor names: anywhere in the doc
  n <- norm_txt(name)
  if (!nzchar(n) || nchar(n) < 3) return("skipped")
  hay <- norm_txt(paste(pages_txt, collapse = " "))
  if (grepl(n, hay, fixed = TRUE)) return("verified")
  acr <- regmatches(name, regexpr("\\(([^)]+)\\)", name))   # '(TLF)' style
  if (length(acr) && grepl(norm_txt(gsub("[()]", "", acr)), hay, fixed = TRUE))
    return("verified")
  "NOT FOUND"
}

verify_doc <- function(row, raw, pages_txt, doc) {
  as_pages <- function(x) { p <- suppressWarnings(as.integer(unlist(x))); p[!is.na(p)] }
  v <- list()
  add <- function(item, status) v[[length(v) + 1]] <<- data.frame(
    document = doc, item = item, status = status, stringsAsFactors = FALSE)
  add("project_lead_name", check_name(raw$identity$project_lead_name, pages_txt))
  for (nm in unlist(raw$finance$funder_names))
    add(paste0("funder: ", substr(nm, 1, 40)), check_name(nm, pages_txt))
  for (nm in unlist(raw$finance$implementor_names))
    add(paste0("implementor: ", substr(nm, 1, 40)), check_name(nm, pages_txt))
  idp <- as_pages(raw$identity$source_pages)
  add("project_id",  check_value(raw$identity$project_id, idp, pages_txt))
  add("resource_id", check_quote(raw$identity$resource_id, idp, pages_txt))
  add("start_year_evidence",   check_quote(raw$identity$start_year_evidence, idp, pages_txt))
  add("closure_year_evidence", check_quote(raw$identity$closure_year_evidence, idp, pages_txt))
  add("document_type_stated",  check_quote(raw$identity$document_type_stated, idp, pages_txt))
  add("scope_stated", check_quote(raw$geography$scope_stated,
      as_pages(raw$geography$source_pages), pages_txt))
  tbp <- as_pages(raw$rationale$target_beneficiary_page)
  if (!length(tbp)) tbp <- as_pages(raw$rationale$source_pages)
  add("target_beneficiary_stated",
      check_quote(raw$rationale$target_beneficiary_stated, tbp, pages_txt))
  fnp <- as_pages(raw$finance$source_pages)
  add("budget_total", check_value(raw$finance$budget_total, fnp, pages_txt))
  add("disbursed",    check_value(raw$finance$disbursed, fnp, pages_txt))
  rl <- raw$results$results
  if (is.data.frame(rl)) rl <- lapply(seq_len(nrow(rl)), function(i) as.list(rl[i, ]))
  for (i in seq_along(rl)) {
    r <- rl[[i]]
    add(paste0("result_", i, ": ", substr(r$metric_stated, 1, 40)),
        check_value(r$value, as_pages(r$page), pages_txt))
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

  row <- list(project_code_hint = pcode, document = basename(pdf_path),
              model = MODEL, prompt_version = PROMPT_VERSION,
              run_date = format(Sys.Date()))
  focus_line <- if (nzchar(focus)) paste0(
    "IMPORTANT — this document covers SEVERAL programs/projects. Extract ",
    "ONLY for ", focus, ". Ignore every other program's rows, results and ",
    "financing. ") else ""
  raw <- list()
  for (gname in names(groups)) {
    g <- groups[[gname]]
    prompt <- paste0("DOCUMENT (page-tagged):\n\n", doc$text,
                     "\n\n---\nTASK: ", focus_line, g$task)
    t0 <- Sys.time()
    res <- tryCatch({
      chat <- chat_openai(model = MODEL, system_prompt = SYSTEM)
      chat$chat_structured(prompt, type = g$type)
    }, error = function(e) e)
    secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
    if (inherits(res, "error")) {
      warning(gname, " failed: ", conditionMessage(res))
      cat(sprintf("  %-10s FAILED (%ss): %s\n", gname, secs,
                  substr(conditionMessage(res), 1, 80)))
      next
    }
    cat(sprintf("  %-10s ok (%ss)\n", gname, secs))
    raw[[gname]] <- res
    write_json(res, file.path(RAW_DIR, paste0("s1_", substr(doc_name, 1, 55),
               "_", gname, ".json")), auto_unbox = TRUE, pretty = TRUE)
    if (gname == "results") { row <- fold_results(res, row); next }
    for (f in names(res)) {
      vv <- res[[f]]
      row[[if (f == "source_pages") paste0(gname, "_pages") else f]] <-
        if (length(vv) > 1) paste(unlist(vv), collapse = "; ") else
        if (length(vv) == 0) "" else as.character(vv)
    }
  }
  # derive missing years from an explicit implementation period, IN CODE —
  # deterministic, immune to the model's (correct) caution about whether a
  # period statement "counts" as an official start (v0.7, QC pattern fix)
  gv <- function(x) if (is.null(x) || !length(x) || is.na(x)) "" else as.character(x)
  per <- gv(row$implementation_period)
  if (nzchar(per)) {
    yrs <- as.integer(unlist(regmatches(per, gregexpr("(19|20)[0-9]{2}", per))))
    yrs <- yrs[!is.na(yrs) & yrs >= 1990 & yrs <= 2035]
    if (length(yrs)) {
      if (!nzchar(gv(row$start_year))) {
        row$start_year <- as.character(min(yrs))
        row$start_year_evidence <- paste0("derived from implementation period: ", per)
      }
      if (length(yrs) >= 2 && !nzchar(gv(row$closure_year))) {
        row$closure_year <- as.character(max(yrs))
        row$closure_year_evidence <- paste0("derived from implementation period: ", per)
      }
    }
  }
  # year sanity check (template: only 2000-2025 accepted)
  for (yf in c("publication_year", "start_year", "closure_year")) {
    y <- suppressWarnings(as.integer(row[[yf]]))
    if (!is.na(y) && (y < 2000 || y > 2025))
      row[[paste0(yf, "_flag")]] <- "OUT OF 2000-2025 RANGE"
  }
  ver <- tryCatch(verify_doc(row, raw, doc$pages, basename(pdf_path)),
                  error = function(e) { warning("verify failed: ", conditionMessage(e)); NULL })
  list(row = as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE),
       verify = ver)
}

if (MODE == "probe") GROUPS <- GROUPS["identity"]

out <- Map(extract_doc, PDFS, FOCUS, PCODE)
rows <- dplyr::bind_rows(lapply(out, `[[`, "row"))
vers <- do.call(rbind, Filter(Negate(is.null), lapply(out, `[[`, "verify")))

stamp <- paste0(MODEL_TAG, "_", format(Sys.time(), "%Y%m%d_%H%M"))
row_csv <- file.path(OUT_DIR, paste0("session1_", stamp, ".csv"))
write_csv(rows, row_csv)
cat("\nwritten:", row_csv, "\n")
if (!is.null(vers)) {
  ver_csv <- file.path(OUT_DIR, paste0("verify_", stamp, ".csv"))
  write_csv(vers, ver_csv)
  cat("verification report:", ver_csv, "\n")
  cat("verification summary:\n"); print(table(vers$status))
}
