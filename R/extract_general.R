##############################################################################
# extract_general.R — PILOT: extract project_data_general fields from one or
# more evaluation PDFs, using the method piloted in BTR_Analysis
# (Documents/BTR_Analysis, 0_Processing_updated.Rmd / 3_Urban_tagging.Rmd):
#
#   * ellmer as the LLM interface (BTR: chat_openai + free-text batch prompts)
#   * SEPARATE small prompts per task — experience from BTR: one prompt that
#     asks for everything confuses the model; here each call covers one
#     thematic FIELD GROUP of the template's project_data_general sheet
#   * per-call tryCatch -> NA fields (a failed group never kills the run)
#   * checkpointed outputs (CSV per run + raw JSON per document/group)
#
# Differences from BTR (deliberate):
#   * BTR classified short pre-extracted passages; here the model reads the
#     WHOLE page-tagged document ("[page N]" markers) and must report the
#     pages used (protocol provenance rule).
#   * structured output via chat_structured()/type_object() instead of
#     line-order parsing — schema violations are retried by ellmer, no
#     regex cleanup needed.
#   * the document is placed FIRST in every prompt and the group task after
#     it, so the 6 calls share one prefix and the provider's automatic
#     prompt caching absorbs most of the repeated document cost.
#
# Field definitions/instructions follow the extraction template
# EvidenceSynthesis_GreyLiterature_AfricanAgricultureAdaptation_
# UpdatedTemplate_27Aug2026.xlsx (readme sheet). Actor fields return NAMES —
# actor codes are assigned later against the actor_codes registry (the model
# never invents codes). project_code is assigned by the database, not here.
#
# Usage:
#   Rscript R/extract_general.R                       # pilot: gold-standard P001
#   Rscript R/extract_general.R path\to\document.pdf  # any single document
#   EXTRACT_MODE=probe Rscript R/extract_general.R    # group 1 only (plumbing)
#   EXTRACT_MODEL=gpt-5-nano Rscript R/extract_general.R   # cheaper model
#
# Requires OPENAI_API_KEY in the environment (~/.Renviron).
##############################################################################

suppressPackageStartupMessages({
  library(ellmer); library(pdftools); library(jsonlite); library(readr)
})

MODE  <- Sys.getenv("EXTRACT_MODE", "pilot")     # probe | pilot
MODEL <- Sys.getenv("EXTRACT_MODEL", "gpt-5-mini")
# Prompt version: bump whenever prompt text or schemas change, so every output
# row is traceable to the exact instructions that produced it (QC audit rec.)
PROMPT_VERSION <- "v0.2-qc1"   # v0.2: rules from the 2026-09-08 gold-standard QC audit
stopifnot("OPENAI_API_KEY not set" = nzchar(Sys.getenv("OPENAI_API_KEY")))

GL <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature"
GOLD_P001 <- file.path(GL, "Data/Docs/Selection_mixed stakeholders/P001",
  "P001_World Bank_Implementation Completion and Results Report_2019_worldbank_3A-AFCC2_RI_-Support_to_NPCA_TerrAfrica_Secretariat_--_P149269_Implementation_Completion_and_Results_Report_2019.pdf")

args <- commandArgs(trailingOnly = TRUE)
PDFS <- if (length(args)) args else GOLD_P001

# repo root (same logic as sync_metadata.R)
full  <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO  <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..")) else getwd()
OUT_DIR <- file.path(REPO, "data", "extraction")
RAW_DIR <- file.path(OUT_DIR, "raw")
dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)

MAX_CHARS <- 600000   # ~150k tokens; BTR-style head+tail clip beyond this

digest_path <- function(x) sprintf("%08x", sum(utf8ToInt(x) * seq_along(utf8ToInt(x)) %% 97))

# ---------------------------------------------------------------- document --
read_doc <- function(path) {
  # poppler can't open >260-char Windows paths (deep OneDrive folders):
  # copy to a short temp name first (same workaround as the C:\pdf_in habit)
  if (nchar(path) > 250) {
    short <- file.path(tempdir(), paste0("x", substr(digest_path(path), 1, 8), ".pdf"))
    ok <- suppressWarnings(file.copy(paste0("\\\\?\\", gsub("/", "\\\\", path)),
                                     short, overwrite = TRUE))
    if (!ok) ok <- file.copy(path, short, overwrite = TRUE)
    stopifnot("could not copy long-path PDF" = ok)
    path <- short
  }
  pages <- pdf_text(path)
  txt <- paste0("[page ", seq_along(pages), "]\n", pages, collapse = "\n\n")
  if (nchar(txt) > MAX_CHARS) {   # clip_text pattern from BTR 0_Processing
    txt <- paste0(substr(txt, 1, round(MAX_CHARS * 0.7)), "\n...[clipped]...\n",
                  substr(txt, nchar(txt) - round(MAX_CHARS * 0.3) + 1, nchar(txt)))
  }
  list(text = txt, n_pages = length(pages))
}

SYSTEM <- paste(
  "You are a meticulous data-extraction assistant for grey-literature project",
  "evaluation documents (African agriculture climate adaptation).",
  "Extract ONLY what the document states — never guess, never fill from prior",
  "knowledge. When a value is not stated in the document, return an empty",
  "string. Report actual values, not planned/target ones. The document text",
  "carries [page N] markers: always report the page numbers you used.",
  # rules from the 2026-09-08 gold-standard QC audit (docs/gold_standard_QC):
  "HARD RULES: (1) Numbers describing the evaluation's own methodology",
  "(sample sizes, people interviewed, focus-group participants, share of",
  "women IN THE SAMPLE) are NEVER project results. (2) In tables covering",
  "several projects or programs, read only the row for THIS project.",
  "(3) Every value must be verifiable on a page of this document; if you",
  "cannot point to it, return an empty string instead. (4) When two tables",
  "in the document contradict each other, use the data sheet / basic-data",
  "table and mention the contradiction in the nearest notes field.")

# ------------------------------------------------------- field group schemas --
# Descriptions condensed from the 27 Aug 2026 template readme instructions.

pg <- function() type_array(items = type_integer(),
  description = "Page numbers ([page N] markers) where this information was found.")

GROUPS <- list(

identity = list(
  task = paste(
    "Extract the project identity and timeline. The document evaluates one",
    "main project. Years must be ACTUAL years stated in the document, never",
    "planned ones; empty string if not stated."),
  type = type_object(
    project_title    = type_string("Title of the adaptation project, word by word as stated (title page or 'project title'/'project name' fields)."),
    project_id       = type_string("The publisher's own project identifier, e.g. 'P149269', exactly as printed IN THIS DOCUMENT (title page, 'project no', basic data table). Empty string if the document prints none — never supply one from elsewhere."),
    project_lead_name = type_string("NAME of the organisation leading the project (often the publisher). Name only, no code."),
    publication_year = type_string("Year the source document was published (usually front page). Not necessarily the project completion year."),
    start_year       = type_string("Year the project ACTUALLY started: approval, effectiveness, signature or official launch as stated in the document. NEVER use design, concept, CEO-endorsement or funding-cycle years (a program 'endorsed 2015, implemented 2017-2022' starts in 2017). Empty string if not stated."),
    closure_year     = type_string("Year the project ACTUALLY closed ('actual closing', 'completed in'). Not the planned/original closing date. If the document says the project is still running ('to date', 'under implementation'), return empty string — do not infer an end year."),
    document_type    = type_enum(values = c("implementation status report",
      "implementation completion report", "impact evaluation report",
      "case study", "policy brief", "technical note",
      "monitoring & evaluation report", "terminal evaluation",
      "mid-term evaluation", "conference proceeding", "donor report",
      "resilience assessment", "learning brief", "practice note",
      "multi-country synthesis", "regional policy brief", "results framework",
      "portfolio performance review", "thematic adaptation evaluation"),
      description = "Type of the source document. Check WHO wrote it and WHETHER IT REVIEWS ANOTHER REPORT: an independent ex-post evaluation that re-rates a completion report (e.g. AfDB PPER, IEG review) is a 'terminal evaluation', NOT an 'implementation completion report'; a multi-program evaluation by an independent evaluation office is a 'portfolio performance review'."),
    resource_id      = type_string("The DOCUMENT's own number per the publisher's archive system, e.g. 'ICR00004643' or 'GEF/E/C.70/02' (title page, 'report no'). Only what is printed in the document; empty string if none."),
    source_pages     = pg())),

geography = list(
  task = paste(
    "Extract the geographic scope of the project. Review the whole document",
    "('country', 'region', 'target areas') and aggregate lists that appear in",
    "different sections."),
  type = type_object(
    project_scale  = type_enum(values = c("individual/ household", "community",
      "sub-national", "national", "multinational", "unclear/ unspecified"),
      description = "Geographic level of the project. Use the document's own scope statement (a 'nationwide' program is national even if analysed by province). individual/household = persons/families benefit; community = local residents collectively; sub-national = regional populations (landscape, district, production zone); national = whole country; multinational = multiple nations; unclear/ unspecified."),
    location_count = type_string("Number of DISTINCT African locations (countries for multi-country projects, districts/sites for single-country ones) named ANYWHERE in the document as receiving project interventions — aggregate all lists across the whole document, count each location once. Prefix ~ for estimates; 'N/A' if unspecified."),
    location_count_basis = type_string("One short sentence saying what was counted (e.g. 'union of the 15 CSIF countries plus 7 mission-only countries named on pages 29-34'). This makes the count checkable."),
    location_notes = type_string("Geographic scope beyond Africa, as 'total of X international locations, of which Y African'. Empty string if the project is Africa-only and location_count covers it."),
    source_pages   = pg())),

rationale = list(
  task = paste(
    "Extract why the project was implemented and who it targets."),
  type = type_object(
    rationale_project = type_string("Context-specific rationale: the climatic and non-climatic hazards, stressors, pain points and perceived benefits that justified the project, quoted or summarised from the document in ONE sentence of up to 100 words. Capture ALL targeted climatic and non-climatic drivers and their interactions."),
    target_beneficiary_project = type_string(paste(
      "General beneficiary group targeted by the project, using one of:",
      "agribusiness, artisanal fisher, children, community, cooperative,",
      "elderly, farm laborer, farmer association, farmer group, household,",
      "indigenous peoples, low-income households, marginalized group,",
      "migrant, pastoralist/herder, people with disabilities/ disability,",
      "producer, producer organization, smallholder farmer, subsistence",
      "farmer, vulnerable population, women (female-headed households),",
      "women's group/organization, youth.",
      "The category MUST be supported by the document's own wording about who",
      "the project targets — do not infer it from stray phrases. If several",
      "apply, choose the larger/overarching one. If the real beneficiary is",
      "an institution, government agency or country (capacity-building",
      "projects), no option fits: return 'CANDIDATE: ' plus a short",
      "free-text description instead of forcing a wrong option.")),
    target_beneficiary_evidence = type_string("Short verbatim quote from the document naming the beneficiaries (with page), justifying the category above."),
    GESI_project = type_string("Consideration of gender equality and social inclusion in the project (management, intervention design, results: data disaggregation, women empowerment, youth access to resources, indigenous communities, local knowledge). Summarise what the document presents; empty string if nothing."),
    source_pages = pg())),

results = list(
  task = paste(
    "Extract ALL quantitative project-level ACTUAL results (achieved values,",
    "not targets) — exhaustively, not a selection. Check the results",
    "framework / indicator annex first: headline achievements often sit in",
    "annex tables, not the summary text. Include results whose target was",
    "NOT achieved (a failure is a finding), and failed yes/no indicators.",
    "Do NOT include: targets without actuals, numbers about the evaluation's",
    "own methodology (samples, respondents), results of OTHER projects",
    "sharing this document, or FINANCING figures (budgets, disbursements,",
    "grant amounts are inputs, not results — they belong to the finance",
    "fields)."),
  type = type_object(
    results = type_array(description = "One entry per distinct quantitative actual result found anywhere in the document.",
      items = type_object(
        value  = type_string("The actual value as stated, e.g. '14325', '>1,000', '47'."),
        metric = type_string("What is being counted, as stated, preferring one of: association members, biodiversity landscapes conserved, cooperatives reached, crop producers, crop yield increase, direct beneficiaries, extension agents trained, farmer groups, fishers, harvest loss reduced, income increase, irrigated land, jobs created, land restored, land under climate-smart practices, livestock producers, pest/disease reduction, processors, producer organizations, smallholder farmers reached, soil organic matter improved, terrestrial protected areas, total beneficiaries, vulnerable households, wholesalers, women beneficiaries, youth beneficiaries. If none fits, give a short free-text metric prefixed 'CANDIDATE: '."),
        unit   = type_string("Counting unit, preferring one of: groups, hectares, households, individuals, kg, kg/hectare, liters, organizations, percentage, quantity, tCO2e, tons. If none fits, prefix 'CANDIDATE: '."),
        indicator_level = type_enum(values = c("PDO/outcome", "intermediate", "narrative"),
          description = "PDO/outcome = a development-objective or outcome indicator; intermediate = component/output indicator; narrative = a figure stated in running text only."),
        status = type_enum(values = c("achieved", "partially achieved", "not achieved", "no target stated"),
          description = "Achievement against the indicator's target, as the document rates it."),
        scope  = type_string("Denominator and coverage: which project/component, which geography, whole program or one country, unique persons or aggregated counts. One short phrase, e.g. 'whole program, incl. indirect beneficiaries' or 'Liberia only'."),
        page   = type_integer("Page ([page N]) where this actual value is stated.")
      )),
    result_notes = type_string("Caveats that change how the numbers should be read (double-counting warnings, data-quality statements, internal contradictions between tables) plus any notable failed indicators, briefly. Empty string if none."),
    source_pages = pg())),

finance = list(
  task = paste(
    "Extract the project financing. Read the TITLE PAGE wording and the",
    "financing/data-sheet table first ('credit', 'loan', 'grant', 'amount',",
    "'actual disbursed', 'total project cost', 'actual at closing',",
    "'co-financing', 'counterpart')."),
  type = type_object(
    budget_total = type_string("Total project budget: sum of ALL financing sources — lead funder + co-financing + counterpart + in-kind. Not just the lead funder's or one fund's share. Digits only, no separators (e.g. '40000000')."),
    budget_lead_share = type_string("The lead funder's / main financing envelope alone (e.g. the GEF grant or IDA amount), digits only — so the co-financing share stays visible. Empty if same as budget_total."),
    disbursed    = type_string("Total actually disbursed for implementation ('actual disbursed'/'actual at closing'). If tables contradict, use the data sheet and flag it in finance_notes. Digits only."),
    currency     = type_string("ISO currency code of the budget, e.g. 'USD', 'EUR', 'UA'."),
    funding_mechanism = type_string("Type of funding by INSTRUMENT as printed on the title page / financing table: a World Bank or AfDB 'credit' is a LOAN (repayable), not a grant. Options: blended (mix of instruments), grant (non-repayable), investment (expects financial return), loan (repayable), other. Mixes allowed, e.g. 'loan+grant'."),
    funding_mechanism_portion = type_string("Distribution of funding instruments with amounts or percentages, e.g. 'IDA credits USD 42.7M (47%) + IDA grants USD 32.8M + GEF grants USD 15.5M'. Empty string if the split is not stated."),
    funder_names      = type_array(items = type_string(), description = "NAMES of all organisations funding the project, including trust funds and co-financiers. Names only, no codes."),
    implementor_names = type_array(items = type_string(), description = "NAMES of the implementing agencies as the data sheet/document designates them (not private partners, borrowers or buyers). Names only, no codes."),
    finance_notes = type_string("Contradictions between the document's own financing tables, counterpart funding that never materialized, or anything else that changes how the figures should be read. Empty string if none."),
    source_pages = pg())),

evidence = list(
  task = paste(
    "Judge the depth of evidence this document provides."),
  type = type_object(
    evidence_depth = type_enum(values = c("0", "1", "2"),
      description = "0 = only general project information; 1 = also concrete information on the adaptation actions implemented; 2 = also evidence on the RESULTS of those actions."),
    evidence_depth_reason = type_string("One sentence justifying the score, citing what the document does/does not provide."),
    source_pages = pg()))
)

# ---------------------------------------------------- result ranking (code) --
# The model extracts ALL results; headline selection happens HERE,
# deterministically, so it never varies between runs (QC pattern 8):
# PDO/outcome indicators first, beneficiary metrics preferred within a tier,
# then document order. "Not achieved" results go to result_notes, not the
# headline slots — but they are kept, because a failure is a finding.
rank_results <- function(rl) {
  if (!length(rl)) return(rl)
  score <- vapply(rl, function(r) {
    s <- 0
    if (identical(r$indicator_level, "PDO/outcome")) s <- s + 100
    if (identical(r$indicator_level, "intermediate")) s <- s + 50
    if (grepl("beneficiar", tolower(paste(r$metric, r$unit)))) s <- s + 10
    s
  }, numeric(1))
  rl[order(-score, seq_along(rl))]
}

fold_results <- function(res, row) {
  rl <- res$results
  if (is.null(rl)) rl <- list()
  if (is.data.frame(rl)) rl <- lapply(seq_len(nrow(rl)), function(i) as.list(rl[i, ]))
  # belt-and-braces: financing figures are never headline results, even if
  # the model returns them (currency units / disbursement wording)
  is_money <- vapply(rl, function(r) grepl(
    "US\\$|USD|EUR|CFAF|\\bUA\\b|disburs|financ|budget|grant amount",
    paste(r$unit, r$metric), ignore.case = TRUE), logical(1))
  money <- rl[is_money]; rl <- rl[!is_money]
  achieved <- Filter(function(r) !identical(r$status, "not achieved"), rl)
  failed   <- Filter(function(r) identical(r$status, "not achieved"), rl)
  top <- rank_results(achieved)
  for (i in 1:3) {
    r <- if (length(top) >= i) top[[i]] else NULL
    row[[paste0("result", i)]]           <- if (is.null(r)) "" else as.character(r$value)
    row[[paste0("result", i, "_metric")]] <- if (is.null(r)) "" else as.character(r$metric)
    row[[paste0("result", i, "_unit")]]   <- if (is.null(r)) "" else as.character(r$unit)
    row[[paste0("result", i, "_scope")]]  <- if (is.null(r)) "" else as.character(r$scope)
  }
  extra <- if (length(top) > 3)
    paste0("further results: ", paste(vapply(top[4:length(top)], function(r)
      paste0(r$value, " ", r$metric, " (", r$scope, ", p", r$page, ")"),
      character(1)), collapse = "; ")) else ""
  fails <- if (length(failed))
    paste0("NOT achieved: ", paste(vapply(failed, function(r)
      paste0(r$metric, " (", r$value, ", p", r$page, ")"), character(1)),
      collapse = "; ")) else ""
  row$result_notes <- paste(Filter(nzchar, c(
    coalesce_chr(res$result_notes), fails, extra)), collapse = " | ")
  row$results_all_n <- as.character(length(rl))
  row
}
coalesce_chr <- function(x) if (is.null(x) || !length(x)) "" else as.character(x)

# -------------------------------------------------------------- extraction --
extract_doc <- function(pdf_path, groups = GROUPS) {
  doc_name <- tools::file_path_sans_ext(basename(pdf_path))
  cat("\n==", doc_name, "==\n")
  doc <- read_doc(pdf_path)
  cat("  pages:", doc$n_pages, "| chars:", nchar(doc$text), "\n")

  row <- list(document = basename(pdf_path), model = MODEL,
              prompt_version = PROMPT_VERSION, run_date = format(Sys.Date()))
  for (gname in names(groups)) {
    g <- groups[[gname]]
    prompt <- paste0("DOCUMENT (page-tagged):\n\n", doc$text,
                     "\n\n---\nTASK: ", g$task)
    t0 <- Sys.time()
    res <- tryCatch({
      chat <- chat_openai(model = MODEL, system_prompt = SYSTEM)
      chat$chat_structured(prompt, type = g$type)
    }, error = function(e) e)
    secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)

    if (inherits(res, "error")) {                       # BTR pattern: NA, go on
      warning(gname, " failed: ", conditionMessage(res))
      cat(sprintf("  %-10s FAILED (%ss): %s\n", gname, secs,
                  substr(conditionMessage(res), 1, 80)))
      next
    }
    cat(sprintf("  %-10s ok (%ss)\n", gname, secs))
    write_json(res, file.path(RAW_DIR, paste0(substr(doc_name, 1, 60), "_",
               gname, ".json")), auto_unbox = TRUE, pretty = TRUE)
    if (gname == "results") {                 # ranked in code, not by the model
      row <- fold_results(res, row)
      row$results_pages <- paste(unlist(res$source_pages), collapse = "; ")
      next
    }
    for (f in names(res)) {
      v <- res[[f]]
      row[[if (f == "source_pages") paste0(gname, "_pages") else f]] <-
        if (length(v) > 1) paste(unlist(v), collapse = "; ") else
        if (length(v) == 0) "" else as.character(v)
    }
  }
  as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE)
}

if (MODE == "probe") GROUPS <- GROUPS["identity"]

rows <- lapply(PDFS, extract_doc)
out <- dplyr::bind_rows(rows)
out_csv <- file.path(OUT_DIR, paste0("pilot_general_info_",
                     format(Sys.time(), "%Y%m%d_%H%M"), ".csv"))
write_csv(out, out_csv)
cat("\nwritten:", out_csv, "\n")
