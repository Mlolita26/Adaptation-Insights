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
  "carries [page N] markers: always report the page numbers you used.")

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
    project_id       = type_string("The publisher's own project identifier, e.g. 'P149269' (scan title page or 'project no'). Empty string if none."),
    project_lead_name = type_string("NAME of the organisation leading the project (often the publisher). Name only, no code."),
    publication_year = type_string("Year the source document was published (usually front page). Not necessarily the project completion year."),
    start_year       = type_string("Year the project officially started (can be approval of concept note). Actual, not planned."),
    closure_year     = type_string("Year the project officially closed. Actual, not planned."),
    document_type    = type_enum(values = c("implementation status report",
      "implementation completion report", "impact evaluation report",
      "case study", "policy brief", "technical note",
      "monitoring & evaluation report", "terminal evaluation",
      "mid-term evaluation", "conference proceeding", "donor report",
      "resilience assessment", "learning brief", "practice note",
      "multi-country synthesis", "regional policy brief", "results framework",
      "portfolio performance review", "thematic adaptation evaluation"),
      description = "Type of the source document, from title/description/metadata."),
    resource_id      = type_string("The DOCUMENT's own number per the publisher's archive system, e.g. 'ICR00004643' (title page, 'report no'). Empty string if none."),
    source_pages     = pg())),

geography = list(
  task = paste(
    "Extract the geographic scope of the project. Review the whole document",
    "('country', 'region', 'target areas')."),
  type = type_object(
    project_scale  = type_enum(values = c("individual/ household", "community",
      "sub-national", "national", "multinational", "unclear/ unspecified"),
      description = "Geographic level of the project. individual/household = persons/families benefit; community = local residents collectively; sub-national = regional populations (landscape, district, production zone); national = whole country; multinational = multiple nations; unclear/ unspecified."),
    location_count = type_string("Number of different AFRICAN locations where interventions were carried out. Prefix ~ for estimates; 'N/A' if unspecified."),
    location_notes = type_string("Geographic scope beyond Africa, as 'total of X international locations, of which Y African'. Empty string if the project is Africa-only and location_count covers it."),
    source_pages   = pg())),

rationale = list(
  task = paste(
    "Extract why the project was implemented and who it targets."),
  type = type_object(
    rationale_project = type_string("Context-specific rationale: the climatic and non-climatic hazards, stressors, pain points and perceived benefits that justified the project, quoted or summarised from the document in ONE sentence of up to 100 words. Capture ALL targeted climatic and non-climatic drivers and their interactions."),
    target_beneficiary_project = type_enum(values = c("agribusiness",
      "artisanal fisher", "children", "community", "cooperative", "elderly",
      "farm laborer", "farmer association", "farmer group", "household",
      "indigenous peoples", "low-income households", "marginalized group",
      "migrant", "pastoralist/herder", "people with disabilities/ disability",
      "producer", "producer organization", "smallholder farmer",
      "subsistence farmer", "vulnerable population",
      "women (female-headed households)", "women's group/organization", "youth"),
      description = "General beneficiary group targeted by the project. If several apply, choose the larger/overarching one (e.g. 'community')."),
    GESI_project = type_string("Consideration of gender equality and social inclusion in the project (management, intervention design, results: data disaggregation, women empowerment, youth access to resources, indigenous communities, local knowledge). Summarise what the document presents; empty string if nothing."),
    source_pages = pg())),

results = list(
  task = paste(
    "Extract up to three HEADLINE quantitative project-level results (e.g.",
    "total beneficiaries reached, hectares of land restored). Choose the most",
    "prominent, project-wide, ACTUAL (achieved) results — not targets. If the",
    "document states fewer than three, leave the rest empty."),
  type = type_object(
    result1        = type_string("Numeric value of result 1, as stated (e.g. '14325', '>1,000'). Empty if none."),
    result1_metric = type_string("Metric of result 1 as stated, preferring one of: association members, biodiversity landscapes conserved, cooperatives reached, crop producers, crop yield increase, direct beneficiaries, extension agents trained, farmer groups, fishers, harvest loss reduced, income increase, irrigated land, jobs created, land restored, land under climate-smart practices, livestock producers, pest/disease reduction, processors, producer organizations, smallholder farmers reached, soil organic matter improved, terrestrial protected areas, total beneficiaries, vulnerable households, wholesalers, women beneficiaries, youth beneficiaries. If none fits, give a short free-text metric prefixed 'CANDIDATE: '."),
    result1_unit   = type_string("Counting unit of result 1, preferring one of: groups, hectares, households, individuals, kg, kg/hectare, liters, organizations, percentage, quantity, tCO2e, tons. If none fits, prefix 'CANDIDATE: '."),
    result2        = type_string("Numeric value of result 2. Empty if none."),
    result2_metric = type_string("Metric of result 2 (same options/rules as result1_metric)."),
    result2_unit   = type_string("Unit of result 2 (same options/rules as result1_unit)."),
    result3        = type_string("Numeric value of result 3. Empty if none."),
    result3_metric = type_string("Metric of result 3 (same options/rules as result1_metric)."),
    result3_unit   = type_string("Unit of result 3 (same options/rules as result1_unit)."),
    result_notes   = type_string("Any additional project results information worth keeping (other results, caveats). Empty string if none."),
    source_pages   = pg())),

finance = list(
  task = paste(
    "Extract the project financing ('credit', 'loan', 'grant', 'amount',",
    "'actual disbursed', 'total project cost', 'actual at closing')."),
  type = type_object(
    budget_total = type_string("Total project budget as stated: sum of all financing sources INCLUDING in-kind contributions. Digits only, no separators (e.g. '40000000')."),
    disbursed    = type_string("Total actually disbursed for implementation ('actual disbursed'/'actual at closing'). Digits only."),
    currency     = type_string("ISO currency code of the budget, e.g. 'USD', 'EUR', 'GHS'."),
    funding_mechanism = type_string("Type of funding: blended (concessional/public + private capital), grant (non-repayable), investment (expects financial return), loan (repayable), other (carbon credits, in-kind, insurance, domestic budget). Mixes allowed, e.g. 'grant+loan'. Use 'other' if unclassifiable."),
    funding_mechanism_portion = type_string("Distribution of funding instruments with percentages, e.g. 'grant (40%) + loan (40%) + other-in-kind contribution (20%)'. Empty string if the split is not stated."),
    funder_names      = type_array(items = type_string(), description = "NAMES of all organisations funding the project. Names only, no codes."),
    implementor_names = type_array(items = type_string(), description = "NAMES of all organisations implementing interventions. Names only, no codes."),
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

# -------------------------------------------------------------- extraction --
extract_doc <- function(pdf_path, groups = GROUPS) {
  doc_name <- tools::file_path_sans_ext(basename(pdf_path))
  cat("\n==", doc_name, "==\n")
  doc <- read_doc(pdf_path)
  cat("  pages:", doc$n_pages, "| chars:", nchar(doc$text), "\n")

  row <- list(document = basename(pdf_path), model = MODEL,
              run_date = format(Sys.Date()))
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
