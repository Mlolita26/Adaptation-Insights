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
PROMPT_VERSION <- "s1-v1.2"   # v1.2 (16 Sep 2026), from adjudicating the gold
# disagreements against the documents: title copied character for character;
# start year accepts "since 2018" prose; location_count never counts the
# evaluation's own focus groups or interviews; a publisher that delivers the
# work is also an implementor and partners named in running text count;
# financing read from the focus programme's row in a multi-programme table.
# v1.1: team field rules - no shouty titles, no codes in titles, numeric-only
# location_count, location_notes always filled, GESI stated when absent,
# whole-digit results, % for percentages
MODEL_TAG <- gsub("[^a-z0-9]+", "-", tolower(MODEL))   # for output file names
# .Renviron lives in the OneDrive-redirected Documents folder; a shell that
# overrides HOME (e.g. Git Bash) makes R miss it, so load it explicitly
if (!nzchar(Sys.getenv("OPENAI_API_KEY")))
  for (p in c(file.path(Sys.getenv("OneDrive"), "Documents", ".Renviron"),
              file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron")))
    if (file.exists(p)) { readRenviron(p); break }
stopifnot("OPENAI_API_KEY not set" = nzchar(Sys.getenv("OPENAI_API_KEY")))

GL <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature"
GOLD_P001 <- file.path(GL, "03_Documents/pilot/gold_set_P001-P010/P001",
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
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", "..")) else getwd()
OUT_DIR <- Sys.getenv("EXTRACT_OUT_DIR", file.path(REPO, "outputs", "extraction"))
source(file.path(REPO, "R", "00_shared", "clean_fields.R"))
source(file.path(REPO, "R", "00_shared", "rf_table.R"))
source(file.path(REPO, "R", "00_shared", "doc_families.R"))
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

# -------------------------------------------- catalogue prefill (tier 1) ----
# catalogues/doc_index.csv maps every corpus FILENAME to its catalogue row
# (built by R/build_doc_index.R; 100% coverage over the 656 in-scope files).
# Precedence: catalogue > cover-vision > text extraction. Displaced extracted
# values are kept in *_extracted columns for QC.
DOC_INDEX <- local({
  p <- file.path(REPO, "catalogues", "doc_index.csv")
  if (file.exists(p)) {
    di <- read.csv(p, stringsAsFactors = FALSE, colClasses = "character")
    di[is.na(di)] <- ""
    di
  } else NULL
})

# ------------------------------------------------- section maps (big docs) --
# For known document families the template fields live in fixed sections, so
# long documents are cut to those pages BEFORE prompting — this replaces the
# blind head+tail clip that lost mid-document facts (e.g. program start years
# on p.191 of the 294-page GEF IEO evaluation). Selected pages keep their
# ORIGINAL [page N] numbers, so citations and the fact-check stay valid.
# Unknown families and documents under 100 pages keep every page.
detect_doc_family <- function(pages) {
  # the shared detector (00_shared/doc_families.R) is the one place a family
  # is defined; this maps its answer onto the section maps this script has
  fam <- detect_family(pages)$family
  if (fam == "wb_icr") return("wb_icr")
  head_txt <- tolower(paste(pages[seq_len(min(6, length(pages)))], collapse = " "))
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

# ------------------------------------------ results-framework vision (tier 5) --
# Results frameworks are TABLES, and pdftools scrambles table layouts - a
# holdout failure mode (values found on 'other pages', NOT FOUND in tables).
# When a results-framework/logframe section is detected, its pages are also
# attached AS IMAGES to the results call so actual values are read from the
# rendered table. Capped to RF_MAX_IMG pages; ~a cent per document.
RF_MAX_IMG <- 10
rf_pages <- function(pages) {
  low <- tolower(pages)
  hits <- grep(paste0("results framework|key outputs|logical framework|",
                      "logframe|cadre logique|matrice de r|cadre de r"), low)
  if (!length(hits)) return(integer(0))
  # the annex itself sits at the END; earlier hits are the TOC and body
  # references — prefer an explicit annex-start hit, else the last mention
  ann <- grep("annex\\s*[0-9ivx]*[.:]?\\s*(results framework|logical framework)", low)
  start <- if (length(ann)) ann[length(ann)] else hits[length(hits)]
  # A World Bank ICR states its achievements twice: once in the indicator
  # tables and again, unambiguously, in the "Key Outputs by Component"
  # narrative at the END of the same annex. In H001 that narrative sits on
  # p56-58 while the annex starts at p37, so a flat 10-page window never
  # reached it; P009 is the same. Take the window AND those pages.
  win <- seq(start, min(length(pages), start + RF_MAX_IMG - 1))
  keyout <- grep("key outputs by component", low)
  keyout <- keyout[keyout >= start]
  sort(unique(c(win, head(keyout, 3))))
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
    project_title  = type_string("The PROJECT's name, word by word as stated - from the cover ('...Project (P123456)'), the data sheet's 'Project Name' row, or the 'evaluation of the project X' phrasing (extract X). Never the REPORT's own name (e.g. 'PPCR Evaluation Report' is a report title, not a project title). WRITE IT IN NORMAL SENTENCE CASE even when the cover shouts it in capitals. Keep abbreviations as they are (APPSA, RFS, AFCC2/RI) but NEVER include a project or document code: no 'P149269', no '(GEF ID 9072)', no 'ICR00004643', no trailing '-- Pxxxxxx'. Copy the remaining words CHARACTER FOR CHARACTER from the data sheet, including spacing around hyphens and slashes: if it reads 'AFCC2/RI -Support', do not tidy it to 'AFCC2/RI - Support'."),
    project_id     = type_string("The publisher's project identifier exactly as printed IN THIS DOCUMENT, e.g. 'P149269'. Empty if none printed."),
    project_lead_name = type_string("NAME of the ORGANISATION leading the project, as the document names it (often the implementing agency or publisher, e.g. 'World Bank'). Never an internal department, global practice, division or regional unit of an organisation — name the organisation itself. An organisation that both commissions and delivers the work is the lead AND an implementor: record it in both places."),
    publication_year = type_string("Year the source document was published (front page)."),
    start_year     = type_string("Year the project ACTUALLY started per the document. Look in the Key Dates / basic-data table: 'Approval', 'Effectiveness', 'entry into force', 'signature', 'officially launched', French 'mise en vigueur'. Never design/concept/endorsement years, and NEVER an extension approval or revised-closing decision date. If no formal date is stated but the document gives an explicit implementation period ('implemented between 2017 and 2022'), use its first year. A prose statement of when work began also counts: 'under implementation since 2018', 'running since 2018', 'operational since 2018'. Empty only if none of these is stated."),
    start_year_evidence = type_string("Short exact quote stating the start (e.g. 'Approval 29-Apr-2014', 'implemented between 2017 and 2022'), with its wording unchanged."),
    closure_year   = type_string("Year the project ACTUALLY closed ('actual closing', 'completed in'; the last year of an explicit implementation period counts if the project is described as finished). Empty if still running ('to date') or not stated."),
    closure_year_evidence = type_string("Short exact quote stating the closing."),
    implementation_period = type_string("The implementation period exactly as the document states it, e.g. '2017-2022' or 'implemented between 2017 and 2022', if any such statement exists. Empty otherwise."),
    document_type_stated = type_string("The document's OWN designation of itself, verbatim (e.g. 'Implementation Completion and Results Report', 'Project Performance Evaluation Report', 'Mid-term evaluation of the project ...')."),
    resource_id    = type_string("The DOCUMENT's own report/document number as printed, e.g. 'ICR00004643', 'GEF/E/C.70/02'. NEVER a grant, loan or trust-fund account number (TF-..., IDA-..., 2100155...), never internal department/routing codes (RDGW/AHAI), never bare date codes. Empty if none."),
    source_pages   = pg())),

geography = list(
  task = paste(
    "Extract the geographic scope verbatim. Review the whole document and",
    "aggregate location lists that appear in different sections."),
  type = type_object(
    scope_stated   = type_string("Exact quote of the document's own statement of geographic scope/coverage (e.g. 'The study's geographical scope was nationwide' or the countries list)."),
    location_count = type_string("A BARE NUMBER and nothing else - digits only, no words, no '~', no 'N/A', no unit. It is the count of DISTINCT African locations named anywhere as receiving interventions, at the MOST PRECISE level the document supports: if specific villages, sites or districts are enumerated, count those (20 pilot villages beats 4 countries); fall back to counting countries only when nothing finer is enumerated. Aggregate across the whole document; count each location once. NEVER count the evaluation's own fieldwork: focus groups, interviews, survey rounds, sampling units and respondent groups are not places. If a sentence says four focus groups were held with farmers from two districts, the count is two. Leave empty only when the document truly never says."),
    location_count_basis = type_string("One sentence saying exactly what was counted, at which level (villages/districts/countries) and where the lists are (pages), so the count can be checked."),
    location_notes = type_string(paste(
      "ALWAYS fill this, and it MUST account for the number in location_count.",
      "Give a VERBATIM sentence, phrase or list from the document naming where",
      "the project worked - quote it exactly, do not paraphrase.",
      "The two fields must tell one story. If the passage you quote covers only",
      "PART of what you counted, say so first and then quote, for example:",
      "'26 countries are named as receiving support; 15 of them received CSIF",
      "support: \"Uganda, Madagascar, Ghana...\"'. Never leave a number here",
      "that contradicts location_count without explaining the difference.",
      "If the project also worked outside Africa, add",
      "'total of X international locations, of which Y African' after the quote.")),
    source_pages   = pg())),

rationale = list(
  task = "Extract why the project was implemented and who it targets, verbatim.",
  type = type_object(
    rationale_project = type_string(paste(
      "WHY the project was needed, IN THE DOCUMENT'S OWN WORDS.",
      "Copy the sentence or sentences that state the problem, EXACTLY as",
      "printed, word for word. Do NOT rewrite, summarise, translate, tidy or",
      "recombine them into a sentence of your own, and do not add words to",
      "make them fit this field. This text is machine-checked against the page.",
      "Choose the passage that gives the context-specific hazards, stressors",
      "and pain points, and the perceived benefits, up to 100 words.",
      "If two separate passages are needed to cover the climatic and the",
      "non-climatic drivers, quote both and join them with ' ... ', each part",
      "still word for word.",
      "If a passage is longer than 100 words, quote its most relevant part",
      "exactly and mark the cut with '...'.",
      "CLIMATIC drivers to look for: drought, rainfall variability, flooding,",
      "temperature, cyclones, sea-level rise, climate-linked pests and disease.",
      "NON-CLIMATIC: land degradation, soil fertility loss, overexploitation,",
      "food and nutrition insecurity, poverty, weak market access, insecure",
      "tenure, weak institutions or extension, gender gaps.",
      "NEVER put here: the project's objectives or components, the activities",
      "it carried out, who funded or implemented it, or its results. A",
      "sentence starting 'To improve...' or 'The project supported...' is the",
      "wrong content unless the document itself uses those words to describe",
      "the problem.")),
    rationale_project_page = type_integer("Page number where the quoted rationale passage appears."),
    target_beneficiary_stated = type_string(paste(
      "EXACT quote (verbatim, machine-checkable) of the passage naming who the",
      "project ULTIMATELY benefits. Ministries, agencies, programme teams,",
      "staff and researchers are the channel, not the beneficiary: when the",
      "project works through institutions, quote the passage that says who",
      "that is for - the objective or goal statement ('to improve the",
      "livelihoods of the rural population of SSA'), the direct-beneficiary",
      "indicator, or the stated target group. Quote the institution instead",
      "only when the document never names an end group.",
      "EVIDENCE, NOT INFERENCE: the passage must SHOW this group benefiting -",
      "reached, trained, supported, served, targeted, received, or counted as",
      "beneficiaries. A group merely mentioned in the document is not enough.",
      "Documents usually say this outright, so look for it: a 'direct project",
      "beneficiaries' indicator in the results framework, a beneficiary table",
      "or count (often disaggregated by sex or youth), a 'the project",
      "targets/serves/reaches X' sentence, or the target group named in the",
      "objectives. Quote the clearest of those.",
      "If no passage shows who benefited, leave this EMPTY rather than assume.")),
    target_beneficiary_page = type_integer("Page of that quote."),
    GESI_project = type_string("Summary of gender-equality and social-inclusion content as presented (management, design, results, disaggregation, indigenous communities, local knowledge). If the document says nothing about gender or social inclusion, write exactly: The document does not address gender equality or social inclusion. Never leave this empty."),
    source_pages = pg())),

results = list(
  task = paste(
    "Extract ALL quantitative project-level ACTUAL results, exhaustively.",
    "Check the results framework / indicator annex first.",
    "SHORTFALLS AND NON-DELIVERY COUNT AS RESULTS AND ARE OFTEN MISSED.",
    "Include every indicator that fell short, delivered nothing, or was",
    "dropped, with its actual figure - including zero. An output reported as",
    "'0 of 2 collection centres built', '10 of 17 warehouses (59%)' or",
    "'0.00' against a target is a FINDING, not an empty cell: give the actual",
    "(0, 10) and set status 'not achieved' or 'partially achieved'. Read the",
    "effectiveness/achievement narrative as well as the annex - completion",
    "rates per output are usually stated there and not in the table.",
    "Report metric and unit AS THE DOCUMENT WORDS THEM — do",
    "not translate into any external category.",
    "A RESULT IS A QUANTITY OF SOMETHING THE PROJECT CHANGED OR DELIVERED:",
    "people (beneficiaries reached, farmers/women/youth trained, households",
    "served, jobs created), land and water (hectares restored, irrigated,",
    "under improved management), production and yields (tons, kg/ha, crop",
    "yield increase, income increase), infrastructure and assets (km of",
    "roads, wells, markets, storage built), animals, organizations/groups",
    "formed or strengthened, emissions avoided (tCO2e), policies or plans",
    "adopted, and adoption/achievement percentages OF SUCH QUANTITIES.",
    "NOT results, never extract as results: durations and time periods",
    "(months, years of implementation, extensions), calendar dates,",
    "counts of reports/meetings/missions/recommendations/contracts,",
    "staffing or administrative numbers, disbursement rates or amounts,",
    "targets without actuals, the evaluation's own methodology numbers,",
    "survey-questionnaire rows, PREDECESSOR/historical program figures,",
    "or other projects' results.",
    "NOT A RESULT EITHER: an evaluation RATING or score ('4 out of 5',",
    "'moderately satisfactory') is a judgement about the project, not",
    "something it delivered. And a COUNT OF PLACES that only says where",
    "the project worked - '20 pilot villages', '3 countries covered',",
    "'sites targeted' - is coverage, not a result: a result is what the",
    "implementation PRODUCED. A place count counts only when the document",
    "reports something achieved there (villages where tenure was",
    "clarified, communities that adopted a practice)."),
  type = type_object(
    results = type_array(description = "One entry per distinct quantitative actual result.",
      items = type_object(
        value  = type_string("The NUMBER in WHOLE DIGITS, nothing else: 14325, not '14,325'; 4700000, not '4.7 million'; 47, not '47 percent'; 15, not '15.00'. No qualifiers ('over', 'approximately'), no units, no ranges, no sentences - put those in metric_stated or scope. 'N' or 'Y' for a yes/no indicator."),
        metric_stated = type_string("What is counted, in the document's own words (the indicator name or phrase, verbatim) — e.g. wording like 'direct project beneficiaries', 'land area under sustainable management', 'women trained'."),
        unit_stated   = type_string("Counting unit in the document's own words (e.g. 'farmers', 'ha', 'households'). For a percentage write the symbol %, not the word. Empty if none stated."),
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
    "the financing/data-sheet table first.",
    "A document covering SEVERAL programmes usually has no data sheet. Its",
    "financing sits in a comparison table with one row per programme, with",
    "columns such as 'Total GEF financing' and 'Total cofinancing'. Read ONLY",
    "the focus programme's row, and the total budget is that row's own",
    "financing PLUS its cofinancing."),
  type = type_object(
    budget_total = type_string("Total PLANNED budget: the financing-plan / data-sheet TOTAL across ALL sources (lead fund grant/credit + co-financing + government counterpart + beneficiary in-kind). Typical table rows: 'GEF grant', 'IDA credit', 'Government', 'Co-financing', 'TOTAL'. NEVER the amount spent/executed - that is disbursed, a different field. Digits only, EXPANDED to full units: 'UA 1.71 million' -> 1710000."),
    budget_lead_share = type_string("The lead funder's / main envelope alone (e.g. the GEF, GCF, AF or IDA amount), digits only, expanded to full units. Empty if same as budget_total."),
    disbursed    = type_string("Total actually SPENT/disbursed: look for 'actual disbursed', 'actual at closing', 'total spent', 'expenditure', execution tables, French 'decaisse'. Sum ALL sources actually spent when several are stated. Not commitments, not the plan. Data sheet wins on contradictions (flag them in finance_notes). Digits only, expanded to full units (1.39 million -> 1390000)."),
    currency     = type_string("ISO currency code, e.g. 'USD', 'EUR', 'UA'."),
    instrument_stated = type_string("EXACT wording of the financing instrument(s) from the title page or financing table, verbatim (e.g. 'ON A CREDIT ... AND A GRANT', 'SMALL GRANT', 'GEF Trust Fund grants')."),
    funding_mechanism_portion = type_string("INSTRUMENT-TYPE mix (grant/loan/investment/other — never fund or account names) WITH PERCENTAGES in parentheses joined by ' + ', per the template format: 'grant (40%) + loan (40%) + other-in-kind contribution (20%)'. Compute percentages from stated amounts when the document gives amounts but no percentages. Empty if the split cannot be established."),
    funder_names      = type_array(items = type_string(), description = "NAMES of all funding ORGANISATIONS incl. named trust funds and co-financiers, as the document names them. Never account/grant numbers like 'TF-17015' or 'IDA-52030', and never financing-table row labels or generic categories in any language ('Borrower/Recipient', 'Local Beneficiaries', 'Bilateral Agencies', 'GOUVERNEMENT/BENEFICIAIRE', 'CONTREPARTIE') - only actual named organisations (a named government like 'Government of Benin' counts)."),
    implementor_names = type_array(items = type_string(), description = "NAMES of the implementing agencies: those designated by the data sheet PLUS any co-implementing national agencies named in the document body (multi-country projects often have one agency per country while the data sheet names only one). Not private partners, borrowers or buyers. Include delivery partners named only in running text, not just those in a table: 'their partner, UCASN, delivered' names an implementor. When the publisher delivers the work itself, name the publisher here too."),
    finance_notes = type_string("Contradictions between financing tables, counterpart funding that never materialized, or similar. Empty if none."),
    source_pages = pg()))
)

# ---------------------------------------------------- result ranking (code) --
# A headcount tells you how big a project was; an outcome tells you whether it
# worked. The synthesis exists to answer the second, so reach must not outrank
# the project's own objective indicator. The old +10 for "beneficiar" did
# exactly that: on holdout H002 it recorded 313,981 beneficiaries and dropped
# the project's two PDO indicators, coffee productivity (1.20) and quality
# share (65.93%), which are what the project was for.
is_reach <- function(r) grepl(
  paste0("beneficiar|people reached|persons reached|farmers reached|",
         "households reached|reached with|participants"),
  tolower(paste(r$metric_stated, r$unit_stated)))

# Two slots must not describe one indicator. H009 spent all three on 438,291
# total / 214,763 male / 223,528 female; P010 on the programme total plus
# Malawi's share of it. That is one result with a breakdown, not three results.
metric_key <- function(r) {
  k <- tolower(paste(r$metric_stated, collapse = " "))
  k <- gsub("[(][^)]*[)]", " ", k)
  k <- gsub(paste0("- *(of which|male|female|men|women|total|regional|national|",
                   "overall|cumulative|disaggregated).*$"), " ", k)
  k <- gsub("[^a-z ]", " ", k)
  k <- trimws(gsub(" +", " ", k))
  substr(k, 1, 42)
}

rank_results <- function(rl) {
  if (!length(rl)) return(rl)
  score <- vapply(rl, function(r) {
    s <- 0
    if (identical(r$indicator_level, "PDO/outcome")) s <- s + 100
    if (identical(r$indicator_level, "intermediate")) s <- s + 50
    if (is_reach(r)) s <- s - 5
    s
  }, numeric(1))
  rl[order(-score, seq_along(rl))]
}

# Fill the three slots: best first, never the same indicator twice, and at
# least one outcome that is not a headcount whenever the document offers one.
choose_three <- function(top) {
  pick <- list(); seen <- character(0); spare <- list()
  for (r in top) {
    k <- metric_key(r)
    if (nzchar(k) && k %in% seen) { spare[[length(spare) + 1L]] <- r; next }
    pick[[length(pick) + 1L]] <- r; seen <- c(seen, k)
    if (length(pick) == 3L) break
  }
  if (length(pick) && all(vapply(pick, is_reach, logical(1)))) {
    alt <- Filter(function(r) !is_reach(r), c(top, spare))
    if (length(alt)) pick[[length(pick)]] <- alt[[1]]
  }
  while (length(pick) < 3L && length(spare)) {
    pick[[length(pick) + 1L]] <- spare[[1]]; spare <- spare[-1]
  }
  pick
}

fold_results <- function(res, row) {
  rl <- res$results
  if (is.null(rl)) rl <- list()
  if (is.data.frame(rl)) rl <- lapply(seq_len(nrow(rl)), function(i) as.list(rl[i, ]))
  is_money <- vapply(rl, function(r) grepl(
    "US\\$|USD|EUR|CFAF|\\bUA\\b|disburs|financ|budget|grant amount",
    paste(r$unit_stated, r$metric_stated), ignore.case = TRUE), logical(1))
  rl <- rl[!is_money]
  # sanity gates (holdout findings): durations, dates, admin counts and
  # no-data placeholder zeros must never occupy a headline slot
  is_junk <- vapply(rl, function(r) {
    v <- tolower(as.character(r$value)); m <- tolower(as.character(r$metric_stated))
    no_digit  <- !grepl("[0-9]", v) && !v %in% c("n", "y", "no", "yes")
    duration  <- grepl("[0-9]\\s*-?\\s*(month|week|year)s?\\b", v) ||
                 grepl("duration|extension|time ?frame|closing date|implementation period", m)
    datelike  <- grepl("^\\s*[0-9]{1,2} (january|february|march|april|may|june|july|august|september|october|november|december)|(19|20)[0-9]{2}\\s*$", v) &&
                 grepl("date|closing|launch|approval", m)
    admin     <- grepl("reports?|meetings?|missions?|recommendations?|contracts?|audits?|supervision", m) &&
                 !grepl("beneficiar|farmer|train|hectare|household", m)
    longtext  <- nchar(v) > 40
    zero_nodata <- grepl("^\\s*0(\\.0+)?\\s*$", v) && !identical(r$status, "not achieved")
    # shared gate: ratings, and place counts that say where the project worked
    # rather than what changed there ("20 pilot villages")
    shared <- nzchar(result_reject_reason(as.character(r$value),
                                          as.character(r$unit_stated),
                                          as.character(r$metric_stated)))
    no_digit || duration || datelike || admin || longtext || zero_nodata || shared
  }, logical(1))
  rl <- rl[!is_junk]
  achieved <- Filter(function(r) !identical(r$status, "not achieved"), rl)
  failed   <- Filter(function(r) identical(r$status, "not achieved"), rl)
  ranked <- rank_results(achieved)
  top    <- choose_three(ranked)
  for (i in 1:3) {
    r <- if (length(top) >= i) top[[i]] else NULL
    row[[paste0("result", i)]] <- if (is.null(r)) "" else as.character(r$value)
    row[[paste0("result", i, "_metric_stated")]] <- if (is.null(r)) "" else as.character(r$metric_stated)
    row[[paste0("result", i, "_unit_stated")]]   <- if (is.null(r)) "" else as.character(r$unit_stated)
    row[[paste0("result", i, "_scope")]] <- if (is.null(r)) "" else as.character(r$scope)
    row[[paste0("result", i, "_page")]]  <- if (is.null(r)) "" else as.character(r$page)
  }
  # everything the three slots could not hold - including an indicator dropped
  # because another slot already describes it - still belongs in the notes
  rest <- Filter(function(r) !any(vapply(top, identical, logical(1), r)), ranked)
  extra <- if (length(rest))
    paste0("further results: ", paste(vapply(rest, function(r)
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
  if (is.null(quote) || !length(quote) || is.na(quote[1])) return("skipped")
  q <- norm_txt(quote[1])
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
  if (is.null(value) || !length(value) || is.na(value[1])) return("skipped")
  v <- norm_num(value[1])
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
  if (is.null(name) || !length(name) || is.na(name[1])) return("skipped")
  name <- name[1]
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
  # the rationale must be the document's own words, so it is checked like any
  # other quote; each ' ... '-joined part is checked separately
  rp <- as_pages(raw$rationale$rationale_project_page)
  if (!length(rp)) rp <- as_pages(raw$rationale$source_pages)
  rq <- as.character(raw$rationale$rationale_project %||% "")
  if (nzchar(rq)) {
    parts <- trimws(strsplit(rq, "\\s*\\.{3}\\s*")[[1]])
    parts <- parts[nchar(parts) >= 12]
    if (!length(parts)) parts <- rq
    st <- vapply(parts, check_quote, character(1), rp, pages_txt, USE.NAMES = FALSE)
    add("rationale_project",
        if (all(st %in% c("verified", "verified_tokens (table)"))) "verified"
        else if (any(st == "NOT FOUND")) "NOT FOUND"
        else st[1])
  }
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
      imgs <- list()
      if (gname == "results") {
        rfp <- rf_pages(doc$pages)
        # Read the indicator tables AS TABLES first and hand the model rows
        # whose columns are already named. This is what stops it taking the
        # baseline for the achievement: in the flattened text a row is a bare
        # run of figures, and the count of figures changes from row to row.
        tbl <- tryCatch(rf_tables(doc$local_path, rfp), error = function(e) character(0))
        if (length(tbl)) {
          cat("  rf-table   ", length(tbl), "indicator row(s) with named columns\n")
          prompt <- paste0(prompt,
            "\n\nINDICATOR TABLE, COLUMNS ALREADY RESOLVED (authoritative for these ",
            "rows - the page text flattens these tables and loses which figure is ",
            "which):\n", paste(tbl, collapse = "\n"),
            "\n\nUse the value marked ACTUAL ACHIEVED as the result. Never use a ",
            "baseline or a target as a result. An ACTUAL ACHIEVED of 0 IS a result ",
            "- report it with status 'not achieved'.")
        }
        for (p in rfp) {
          png <- file.path(tempdir(), paste0("rf_", substr(digest_path(pdf_path), 1, 8),
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
            "the actual values from the images wherever the text is unclear.")
        }
      }
      if (length(imgs)) do.call(chat$chat_structured,
                                c(list(prompt), imgs, list(type = g$type)))
      else chat$chat_structured(prompt, type = g$type)
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

  # ------ tier 2: image-cover fallback (glossy reports whose cover is an
  # image: the text layer sees only running headers - detect via a near-empty
  # first page, read the cover with ONE small vision call)
  if (nchar(trimws(doc$pages[1])) < 150) {
    png <- file.path(tempdir(), paste0("cover_", substr(digest_path(pdf_path), 1, 8), ".png"))
    okc <- tryCatch({ pdftools::pdf_convert(doc$local_path, format = "png", pages = 1,
                      filenames = png, dpi = 150, verbose = FALSE); TRUE },
                    error = function(e) FALSE)
    if (okc) {
      cov <- tryCatch({
        ch <- chat_openai(model = MODEL, system_prompt = SYSTEM)
        ch$chat_structured(
          paste("This image is the COVER PAGE of a project evaluation document",
                "whose text layer is empty. Read from the image:"),
          content_image_file(png, resize = "none"),
          type = type_object(
            cover_title = type_string("The report/project title as printed on the cover, verbatim."),
            cover_year  = type_string("Publication year printed on the cover (copyright line, date). Empty if none visible."),
            cover_publisher = type_string("Publisher/lead organisation shown on the cover. Empty if none.")))
      }, error = function(e) { warning("cover vision failed: ", conditionMessage(e)); NULL })
      if (!is.null(cov)) {
        if (nzchar(gv(cov$cover_title))) {
          row$project_title_extracted <- gv(row$project_title)
          row$project_title <- trimws(gsub("\\s+", " ", gv(cov$cover_title)))
          row$title_source <- "cover_vision"
        }
        cyr <- regmatches(gv(cov$cover_year), regexpr("(19|20)[0-9]{2}", gv(cov$cover_year)))
        if (!nzchar(gv(row$publication_year)) && length(cyr))
          row$publication_year <- cyr
        if (!nzchar(gv(row$project_lead_name)) && nzchar(gv(cov$cover_publisher)))
          row$project_lead_name <- gv(cov$cover_publisher)
        cat("  cover      read by vision fallback\n")
      }
    }
  }

  # ------ tier 1: catalogue prefill (corpus documents) - catalogue wins
  if (!is.null(DOC_INDEX)) {
    ixr <- DOC_INDEX[DOC_INDEX$filename == basename(pdf_path), ]
    if (nrow(ixr) == 1 && ixr$match_method != "unmatched") {
      stash <- function(field, val) {
        if (nzchar(val)) {
          row[[paste0(field, "_extracted")]] <<- gv(row[[field]])
          row[[field]] <<- val
        }
      }
      stash("project_title", ixr$title)
      stash("project_id", ixr$project_id)
      stash("resource_id", ixr$report_no)
      if (!nzchar(gv(row$publication_year)) && nzchar(ixr$year) && ixr$year != "NA")
        row$publication_year <- ixr$year
      row$reference_link_1 <- ixr$url
      row$prefill <- ixr$match_method
      cat("  prefill    from catalogue (", ixr$match_method, ")\n")
    }
  }

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
  # ---- team field rules (9 Sep 2026), applied in code AFTER the catalogue
  # prefill, because catalogue titles are often shouty and carry the P-code
  row$project_title_raw <- gv(row$project_title)
  row$project_title <- clean_title(row$project_title)
  if (!identical(row$project_title, row$project_title_raw) &&
      nzchar(row$project_title_raw)) row$title_cleaned <- "yes"
  lc_raw <- gv(row$location_count)
  row$location_count <- clean_count(lc_raw)
  if (nzchar(lc_raw) && !identical(lc_raw, row$location_count))
    row$location_count_raw <- lc_raw
  row$location_notes <- clean_location_notes(gv(row$location_notes), gv(row$scope_stated))
  cflag <- check_count_vs_notes(row$location_count, row$location_notes)
  if (nzchar(cflag)) row$location_count_flag <- cflag
  row$GESI_project <- clean_gesi(gv(row$GESI_project))
  for (tf in c("rationale_project", "GESI_project", "location_notes",
               "target_beneficiary_stated", "scope_stated", "result_notes",
               "finance_notes", "project_title")) {
    if (!is.null(row[[tf]])) {
      ct <- clean_text(gv(row[[tf]]))
      row[[tf]] <- ct$value
      if (nzchar(ct$note)) row$text_artifact_flag <- ct$note
    }
  }
  for (i in 1:3) {
    vf <- paste0("result", i); uf <- paste0(vf, "_unit_stated")
    cn <- clean_number(gv(row[[vf]]))
    if (nzchar(gv(row[[vf]]))) {
      row[[vf]] <- cn$value
      row[[uf]] <- clean_unit(gv(row[[uf]]), gv(row[[vf]]))
      if (nzchar(cn$note))
        row$result_notes <- trimws(paste(gv(row$result_notes),
                                         paste0(vf, ": ", cn$note), sep = " | "))
    }
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
