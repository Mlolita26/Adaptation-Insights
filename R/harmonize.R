##############################################################################
# harmonize.R — SESSION 2 of the two-session extraction design.
#
# Takes the verbatim output of R/extract_verbatim.R (session1_*.csv) and
# harmonises it to the 27 Aug 2026 template's controlled values:
#   * actor names -> actor CODES from the actor_codes registry (semicolon-
#     joined, per template). Deterministic matching first (name, acronym,
#     substring, fuzzy); leftovers resolved by ONE small batched LLM call
#     against fuzzy candidate shortlists; still-unmatched actors are written
#     to proposed_new_actors.csv for human review — codes are NEVER invented.
#   * coded fields (scale, beneficiary, document type, metrics, units,
#     funding mechanism): deterministic synonym maps first, then ONE batched
#     LLM call per field type, carrying the template readme's definitions.
#     Values are validated in code; anything off-list becomes
#     'CANDIDATE: ...' and is appended to candidate_vocab_log.csv.
#
# The model never sees the documents here — only the short verified extracts.
# A vocabulary change re-runs this script only; no document is re-read.
#
# Usage:
#   Rscript R/harmonize.R                      # latest session1_*.csv
#   Rscript R/harmonize.R data/extraction/session1_20260908_1200.csv
##############################################################################

suppressPackageStartupMessages({
  library(ellmer); library(readxl); library(readr); library(dplyr); library(jsonlite)
})

MODEL <- Sys.getenv("HARMONIZE_MODEL", "gpt-5-mini")
PROMPT_VERSION <- "s2-v0.3"
GL <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature"
TEMPLATE <- file.path(GL, "02_Template",
  "EvidenceSynthesis_GreyLiterature_AfricanAgricultureAdaptation_UpdatedTemplate_27Aug2026.xlsx")

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..")) else getwd()
OUT_DIR <- Sys.getenv("EXTRACT_OUT_DIR", file.path(REPO, "data", "extraction"))

args <- commandArgs(trailingOnly = TRUE)
s1_csv <- if (length(args)) args[1] else {
  f <- list.files(OUT_DIR, pattern = "^session1_.*\\.csv$", full.names = TRUE)
  stopifnot("no session1_*.csv found — run extract_verbatim.R first" = length(f) > 0)
  f[which.max(file.mtime(f))]
}
cat("harmonizing:", s1_csv, "\n")
s1 <- read.csv(s1_csv, check.names = FALSE, stringsAsFactors = FALSE)
s1[is.na(s1)] <- ""

# ------------------------------------------------------- controlled values --
# From the 27 Aug 2026 template readme (regenerate on template release).
OPT <- list(
  scale = c("individual/ household", "community", "sub-national", "national",
            "multinational", "unclear/ unspecified"),
  beneficiary = c("agribusiness", "artisanal fisher", "children", "community",
    "cooperative", "elderly", "farm laborer", "farmer association",
    "farmer group", "household", "indigenous peoples", "low-income households",
    "marginalized group", "migrant", "pastoralist/herder",
    "people with disabilities/ disability", "producer", "producer organization",
    "smallholder farmer", "subsistence farmer", "vulnerable population",
    "women (female-headed households)", "women's group/organization", "youth"),
  doc_type = c("implementation status report", "implementation completion report",
    "impact evaluation report", "case study", "policy brief", "technical note",
    "monitoring & evaluation report", "terminal evaluation", "mid-term evaluation",
    "conference proceeding", "donor report", "resilience assessment",
    "learning brief", "practice note", "multi-country synthesis",
    "regional policy brief", "results framework", "portfolio performance review",
    "thematic adaptation evaluation"),
  metric = c("association members", "biodiversity landscapes conserved",
    "cooperatives reached", "crop producers", "crop yield increase",
    "direct beneficiaries", "extension agents trained", "farmer groups",
    "fishers", "harvest loss reduced", "income increase", "irrigated land",
    "jobs created", "land restored", "land under climate-smart practices",
    "livestock producers", "pest/disease reduction", "processors",
    "producer organizations", "smallholder farmers reached",
    "soil organic matter improved", "terrestrial protected areas",
    "total beneficiaries", "vulnerable households", "wholesalers",
    "women beneficiaries", "youth beneficiaries"),
  unit = c("groups", "hectares", "households", "individuals", "kg",
    "kg/hectare", "liters", "organizations", "percentage", "quantity",
    "tCO2e", "tons"))

DEFS <- list(
  scale = "individual/household: persons or families receiving direct or indirect benefits; community: local residents benefitting collectively; sub-national: interventions benefit regional populations (a landscape, district, or agricultural production zone); national: an entire country's citizens benefit broadly; multinational: involves and benefits multiple nations; unclear/ unspecified: affected beneficiaries remain unidentified.",
  beneficiary = "agribusiness: commercial enterprises in production/processing/distribution of agricultural products; artisanal fisher: small-scale traditional fishers; children: under eighteen; community: a social group sharing space/culture/interests; cooperative: member-owned enterprise; elderly: sixty-five and above; farm laborer: wage farm workers without land; farmer association: organized farmer group for advocacy/markets; farmer group: small collective of farmers collaborating; household: residential unit sharing income and consumption; indigenous peoples: distinct ethnic groups with historical territorial ties; low-income households: earnings below basic-needs threshold; marginalized group: systematically excluded populations; migrant: person moving for opportunity or safety; pastoralist/herder: livelihood from moving livestock; people with disabilities: long-term impairments; producer: cultivates crops or rears animals; producer organization: formal entity representing producers; smallholder farmer: cultivates a small plot with family labor; subsistence farmer: produces mainly to feed own family; vulnerable population: higher risk of poverty/exclusion/harm; women (female-headed households): woman is primary decision-maker/provider; women's group/organization: women's collectives; youth: fifteen to twenty-four.",
  doc_type = "Note: an independent ex-post evaluation that reviews/re-rates a completion report (AfDB PPER, IEG review) = terminal evaluation; an independent evaluation office's multi-program evaluation = portfolio performance review; a completion report written by the financier at project close = implementation completion report.")

# --------------------------------------------------------- LLM batch helper --
llm_map <- function(field, texts, options, definitions = "") {
  idx <- which(nzchar(texts) & !texts %in% options)   # skip already-valid/empty
  if (!length(idx)) return(texts)
  chat <- chat_openai(model = MODEL, system_prompt = paste(
    "You harmonise verbatim extracts from project evaluations into a fixed",
    "controlled vocabulary. You see only the extract, never the document.",
    "Choose the single best option. If no option genuinely fits, answer",
    "'CANDIDATE: ' followed by a 2-6 word free-text label. Never invent",
    "options; never force a bad fit."))
  prompt <- paste0(
    "FIELD: ", field, "\nOPTIONS: ", paste(options, collapse = "; "),
    if (nzchar(definitions)) paste0("\nDEFINITIONS: ", definitions) else "",
    "\n\nINPUT EXTRACTS (numbered):\n",
    paste0(sprintf("%d) %s", seq_along(idx), substr(texts[idx], 1, 400)),
           collapse = "\n"))
  spec <- type_object(mapping = type_array(
    items = type_object(
      i = type_integer("Input number."),
      choice = type_string("One option verbatim, or 'CANDIDATE: ...'."))))
  res <- tryCatch(chat$chat_structured(prompt, type = spec),
                  error = function(e) { warning(field, ": ", conditionMessage(e)); NULL })
  if (is.null(res)) return(texts)
  m <- res$mapping
  if (is.data.frame(m)) m <- lapply(seq_len(nrow(m)), function(i) as.list(m[i, ]))
  out <- texts
  for (mm in m) {
    j <- suppressWarnings(as.integer(mm$i))
    if (is.na(j) || j < 1 || j > length(idx)) next
    ch <- as.character(mm$choice)
    if (!(ch %in% options) && !startsWith(ch, "CANDIDATE:"))
      ch <- paste0("CANDIDATE: ", texts[idx[j]])   # validation: never off-list
    out[idx[j]] <- ch
  }
  out
}

log_candidates <- function(df_doc, field, stated, chosen) {
  k <- which(startsWith(chosen, "CANDIDATE:"))
  if (!length(k)) return(invisible())
  log <- data.frame(date = format(Sys.Date()), document = df_doc[k],
                    field = field, stated = stated[k], chosen = chosen[k],
                    stringsAsFactors = FALSE)
  path <- file.path(OUT_DIR, "candidate_vocab_log.csv")
  write.table(log, path, sep = ",", row.names = FALSE, append = file.exists(path),
              col.names = !file.exists(path))
}

# -------------------------------------------------------- actor registry -----
actors <- suppressMessages(read_excel(TEMPLATE, sheet = "actor_codes"))
names(actors) <- tolower(trimws(names(actors)))
codecol <- grep("code", names(actors), value = TRUE)[1]
namecol <- grep("name", names(actors), value = TRUE)[1]
acrocol <- grep("acronym|accronym|abbrev", names(actors), value = TRUE)[1]  # sheet spells it 'actor_accronym'
areg <- data.frame(
  code = trimws(as.character(actors[[codecol]])),
  name = trimws(as.character(actors[[namecol]])),
  acro = if (!is.na(acrocol)) trimws(as.character(actors[[acrocol]])) else "",
  stringsAsFactors = FALSE)
areg <- areg[nzchar(areg$code) & nzchar(areg$name), ]
nrm <- function(x) trimws(gsub("[^a-z0-9 ]", " ", gsub("\\s+", " ", tolower(x))))
areg$nname <- nrm(areg$name); areg$nacro <- nrm(areg$acro)

match_actor_det <- function(name) {
  n <- nrm(name)
  if (!nzchar(n)) return(NA_character_)
  hit <- which(areg$nname == n | (nzchar(areg$nacro) & areg$nacro == n))
  if (length(hit) == 1) return(areg$code[hit[1]])
  # substring containment only for long-enough names: a short acronym like
  # 'TAF' sits inside unrelated words ('Taflalet') and must go to the LLM
  # shortlist instead of matching deterministically (Round-4 bug)
  if (nchar(n) >= 8) {
    hit <- which(vapply(areg$nname, function(x) nzchar(x) &&
      (grepl(x, n, fixed = TRUE) || grepl(n, x, fixed = TRUE)), logical(1)))
    if (length(hit) == 1) return(areg$code[hit[1]])
  }
  NA_character_
}
fuzzy_candidates <- function(name, k = 6) {
  n <- nrm(name)
  words <- strsplit(n, " ")[[1]]; words <- words[nchar(words) > 3]
  hits <- unique(c(
    which(vapply(areg$nname, function(x) nzchar(x) &&
      (grepl(x, n, fixed = TRUE) || grepl(n, x, fixed = TRUE)), logical(1))),
    # acronyms catch renames (e.g. 'NEPAD Agency' -> AUDA-NEPAD registry row)
    which(vapply(areg$nacro, function(x) nzchar(x) &&
      (grepl(x, n, fixed = TRUE) || grepl(n, x, fixed = TRUE) ||
       any(vapply(words, function(w) grepl(w, x, fixed = TRUE), logical(1)))),
      logical(1))),
    agrep(n, areg$nname, max.distance = 0.25)))
  head(hits, k)
}

resolve_actors <- function(all_names) {
  uniq <- unique(trimws(unlist(strsplit(all_names[nzchar(all_names)], ";\\s*"))))
  uniq <- uniq[nzchar(uniq)]
  map <- setNames(vapply(uniq, match_actor_det, character(1)), uniq)
  pending <- names(map)[is.na(map)]
  if (length(pending)) {                     # one batched LLM disambiguation
    cand_codes <- lapply(pending, function(p) areg$code[fuzzy_candidates(p)])
    lines <- vapply(seq_along(pending), function(i) {
      cand <- fuzzy_candidates(pending[i])
      paste0(i, ") '", pending[i], "' -> candidates: ",
             if (length(cand)) paste0(areg$code[cand], "=", areg$name[cand],
                                      ifelse(nzchar(areg$acro[cand]),
                                             paste0(" [", areg$acro[cand], "]"), ""),
                                      collapse = "; ") else "(none)")
    }, character(1))
    chat <- chat_openai(model = MODEL, system_prompt = paste(
      "You match organisation names from evaluation documents to a registry.",
      "Pick the candidate code ONLY if it is CLEARLY the same organisation",
      "(renames/acronyms count, e.g. a former name of the same body).",
      "An acronym matches only the candidate's actual acronym or name",
      "initials — letters merely CONTAINED in a candidate's name (e.g. 'TAF'",
      "inside 'Taflalet') are NOT a match. A department, global practice,",
      "division or regional unit is not an organisation — answer 'NEW' for",
      "those. When in ANY doubt, answer 'NEW' and describe the organisation",
      "so a registry entry can be prepared. Never guess codes."))
    spec <- type_object(mapping = type_array(items = type_object(
      i = type_integer(), code = type_string("Registry code or 'NEW'."),
      scale = type_enum(values = c("global", "continental", "national", "unknown"),
        description = "For NEW actors: the organisation's scale per the registry convention (global; continental = Africa-wide; national)."),
      country = type_string("For NEW national actors: the country, e.g. 'Rwanda'. Empty otherwise."),
      acronym = type_string("The organisation's acronym if commonly used, else empty."),
      actor_type = type_string("For NEW actors, one of: academic institution; advocacy organization/group; banks and microfinance institutions; bilateral development agency; civil society organization; development organization; farmer/pastoralist organization/cooperative; foundation/ philanthropic organization; government agency; intergovernmental organization; international finance institution; media; non-governmental organization; other; private company; producer/farmer group; project/programme; research institution; think tank; trade organization; training/capacity building centre."))))
    res <- tryCatch(chat$chat_structured(
      paste0("ORGANISATIONS AND CANDIDATES:\n", paste(lines, collapse = "\n")),
      type = spec), error = function(e) NULL)
    newinfo <- list()
    if (!is.null(res)) {
      m <- res$mapping
      if (is.data.frame(m)) m <- lapply(seq_len(nrow(m)), function(i) as.list(m[i, ]))
      for (mm in m) {
        j <- suppressWarnings(as.integer(mm$i))
        if (is.na(j) || j < 1 || j > length(pending)) next
        cd <- as.character(mm$code)
        # accept ONLY a code from this item's own candidate shortlist — a
        # valid-but-unshown registry code would be an unverifiable guess
        if (cd %in% cand_codes[[j]]) map[pending[j]] <- cd
        else newinfo[[pending[j]]] <- mm     # NEW: keep scale/acronym/type
      }
    }
  } else newinfo <- list()
  new <- names(map)[is.na(map)]
  if (length(new)) {
    # Intake form for the team: suggested code = registry-convention prefix
    # (GLO / CON / country prefix) + next free number in that section.
    # These are PROPOSALS — the code becomes real only once a human adds the
    # row to the actor_codes sheet; the next harmonize run then matches it
    # automatically (no re-extraction needed).
    prefix_of <- function(code) gsub("[0-9]+$", "", code)
    next_code <- local({
      taken <- table(prefix_of(areg$code))
      maxn  <- vapply(names(taken), function(p) {
        suppressWarnings(max(as.integer(gsub("^[A-Za-z]+", "",
          areg$code[prefix_of(areg$code) == p])), na.rm = TRUE))
      }, numeric(1))
      counter <- as.list(maxn)
      function(prefix) {
        n <- if (!is.null(counter[[prefix]])) counter[[prefix]] + 1 else 1
        counter[[prefix]] <<- n
        paste0(prefix, n)
      }
    })
    country_prefix <- function(country) {
      # reuse whatever prefix the registry already uses for that country if
      # any national actor exists; else first 3 letters uppercased
      k <- nrm(country)
      if (!nzchar(k)) return("")
      toupper(substr(gsub(" ", "", k), 1, 3))
    }
    rows <- lapply(new, function(nm) {
      inf <- newinfo[[nm]]
      scale <- if (!is.null(inf)) as.character(inf$scale) else "unknown"
      pre <- switch(scale, global = "GLO", continental = "CON",
                    national = country_prefix(as.character(inf$country)), "")
      data.frame(date = format(Sys.Date()), actor_name = nm,
        actor_accronym = if (!is.null(inf)) as.character(inf$acronym) else "",
        suggested_scale = scale,
        suggested_country = if (!is.null(inf)) as.character(inf$country) else "",
        suggested_code = if (nzchar(pre)) next_code(pre) else "",
        suggested_actor_type = if (!is.null(inf)) as.character(inf$actor_type) else "",
        status = "REVIEW: confirm/edit, add row to actor_codes, then re-run harmonize",
        stringsAsFactors = FALSE)
    })
    nn <- do.call(rbind, rows)
    path <- file.path(OUT_DIR, "proposed_new_actors.csv")
    if (file.exists(path)) {                       # don't re-propose known names
      seen <- tryCatch(read.csv(path, stringsAsFactors = FALSE)$actor_name,
                       error = function(e) character(0))
      nn <- nn[!nn$actor_name %in% seen, , drop = FALSE]
    }
    if (nrow(nn))
      write.table(nn, path, sep = ",", row.names = FALSE,
                  append = file.exists(path), col.names = !file.exists(path))
  }
  map[is.na(map)] <- paste0("NEW: ", names(map)[is.na(map)])
  map
}
codes_for <- function(x, map) {
  if (!nzchar(x)) return("")
  parts <- trimws(unlist(strsplit(x, ";\\s*")))
  paste(unique(map[parts]), collapse = "; ")
}

# ------------------------------------------------- deterministic first maps --
unit_syn <- c("ha" = "hectares", "hectare" = "hectares", "hectares" = "hectares",
  "%" = "percentage", "percent" = "percentage", "percentage" = "percentage",
  "percentage points" = "percentage", "people" = "individuals",
  "persons" = "individuals", "individuals" = "individuals",
  "farmers" = "individuals", "beneficiaries" = "individuals",
  "households" = "households", "hh" = "households", "groups" = "groups",
  "organizations" = "organizations", "organisations" = "organizations",
  "kg" = "kg", "kilograms" = "kg", "kg/ha" = "kg/hectare",
  "kg/hectare" = "kg/hectare", "liters" = "liters", "litres" = "liters",
  "tco2e" = "tCO2e", "mtco2" = "tCO2e", "mtco2e" = "tCO2e", "tons" = "tons",
  "tonnes" = "tons", "t" = "tons", "number" = "quantity", "count" = "quantity",
  "quantity" = "quantity", "countries" = "quantity", "yes/no" = "quantity")
map_unit_det <- function(u) {
  k <- nrm(u)
  if (!nzchar(k)) return("")
  if (k %in% names(unit_syn)) unname(unit_syn[k]) else u
}
map_doctype_det <- function(d) {
  k <- tolower(d)
  if (grepl("implementation completion", k)) return("implementation completion report")
  if (grepl("performance evaluation report|icr review", k)) return("terminal evaluation")
  if (grepl("terminal evaluation|final evaluation|final report", k)) return("terminal evaluation")
  if (grepl("mid.?term", k)) return("mid-term evaluation")
  if (grepl("implementation status", k)) return("implementation status report")
  if (grepl("impact (assessment|evaluation)", k)) return("impact evaluation report")
  # independent multi-program / fund-level evaluations
  if (grepl("independent evaluation office|evaluation of .*programs|independent evaluation of the|evaluation of the pilot program", k))
    return("portfolio performance review")
  if (grepl("^\\s*evaluation of ", k)) return("terminal evaluation")
  d
}
map_funding_det <- function(instr) {
  k <- tolower(instr)
  # known funds whose instrument is always a grant, even when the wording is
  # only 'funded by ...' (GEF Trust Fund, Adaptation Fund, LDCF/SCCF windows)
  if (grepl("gef trust fund|\\bget\\b|adaptation fund|ldcf|sccf|green climate fund|\\bgcf\\b|gafsp", k) &&
      !grepl("credit|loan", k)) return("grant")
  k <- gsub("investment project financing", "", k)   # WB modality label, not an instrument
  has <- c(loan = grepl("credit|loan", k), grant = grepl("grant", k),
           investment = grepl("equity|bond|investment", k))
  found <- names(has)[has]
  if (!length(found)) return("")
  paste(found, collapse = "+")
}

# ------------------------------------------------------------ harmonise -----
h <- s1
gc_chr <- function(col) if (col %in% names(h)) as.character(h[[col]]) else rep("", nrow(h))

# actors -> codes
amap <- resolve_actors(c(gc_chr("project_lead_name"), gc_chr("funder_names"),
                         gc_chr("implementor_names")))
h$project_lead <- vapply(gc_chr("project_lead_name"), codes_for, character(1), map = amap)
h$funder       <- vapply(gc_chr("funder_names"), codes_for, character(1), map = amap)
h$implementor  <- vapply(gc_chr("implementor_names"), codes_for, character(1), map = amap)

# scale + beneficiary + document type (deterministic, then batched LLM)
h$project_scale <- llm_map("project_scale (geographic level of the project)",
  paste0("scope: ", gc_chr("scope_stated"), " | locations: ",
         gc_chr("location_count"), " ", gc_chr("location_notes")),
  OPT$scale, DEFS$scale)
h$target_beneficiary_project <- llm_map(
  "target_beneficiary_project (who the project targets)",
  gc_chr("target_beneficiary_stated"), OPT$beneficiary, DEFS$beneficiary)
dt <- vapply(gc_chr("document_type_stated"), map_doctype_det, character(1))
h$document_type <- llm_map("document_type", dt, OPT$doc_type, DEFS$doc_type)

# result metrics + units
for (i in 1:3) {
  ms <- gc_chr(paste0("result", i, "_metric_stated"))
  us <- vapply(gc_chr(paste0("result", i, "_unit_stated")), map_unit_det, character(1))
  h[[paste0("result", i, "_metric")]] <- llm_map(
    paste0("result_metric (what a project result counts)"), ms, OPT$metric)
  h[[paste0("result", i, "_unit")]] <- llm_map("result_unit", us, OPT$unit)
}

# funding mechanism: deterministic from instrument wording first ('funded
# by <known grant fund>' rules included); anything a keyword can't settle
# goes to the LLM with the template definitions instead of defaulting to
# 'other' blindly
fm <- vapply(gc_chr("instrument_stated"), map_funding_det, character(1))
# no instrument wording, but the funder itself settles it (grant-only funds)
grantfunder <- grepl("gef|global environment facility|trust fund|adaptation fund",
                     tolower(gc_chr("funder_names")))
fm[!nzchar(fm) & grantfunder] <- "grant"
pendfm <- !nzchar(fm) & nzchar(gc_chr("instrument_stated"))
if (any(pendfm)) {
  fm2 <- llm_map("funding_mechanism (financing instrument type)",
    ifelse(pendfm, paste0("instrument wording: ", gc_chr("instrument_stated"),
                          " | portion: ", gc_chr("funding_mechanism_portion")), ""),
    c("grant", "loan", "investment", "blended", "other", "loan+grant"),
    "blended: intentional mix of concessional/public and private capital; grant: non-repayable funds; investment: capital expecting financial return; loan: borrowed money requiring repayment; other: alternative mechanisms (carbon credits, in-kind, insurance, domestic budget); loan+grant: mixed credits and grants. If genuinely unclassifiable, choose other.")
  fm[pendfm] <- fm2[pendfm]
}
fm[startsWith(fm, "CANDIDATE:")] <- "other"   # readme: unclassifiable -> other
h$funding_mechanism <- fm

# candidate logging
log_candidates(h$document, "target_beneficiary_project",
               gc_chr("target_beneficiary_stated"), h$target_beneficiary_project)
for (i in 1:3) {
  log_candidates(h$document, paste0("result", i, "_metric"),
                 gc_chr(paste0("result", i, "_metric_stated")),
                 h[[paste0("result", i, "_metric")]])
  log_candidates(h$document, paste0("result", i, "_unit"),
                 gc_chr(paste0("result", i, "_unit_stated")),
                 h[[paste0("result", i, "_unit")]])
}

# ------------------------------------------------ template-shaped output ----
TEMPLATE_COLS <- c("project_code", "project_title", "project_id", "project_lead",
  "publication_year", "start_year", "closure_year", "project_scale",
  "location_count", "location_notes", "rationale_project",
  "target_beneficiary_project", "GESI_project",
  "result1", "result1_metric", "result1_unit",
  "result2", "result2_metric", "result2_unit",
  "result3", "result3_metric", "result3_unit", "result_notes",
  "budget_total", "disbursed", "currency", "funding_mechanism",
  "funding_mechanism_portion", "funder", "implementor", "document_type",
  "resource_id", "evidence_depth",
  "reference_link_1", "reference_link_2", "reference_link_3")
for (cc in TEMPLATE_COLS) if (!cc %in% names(h)) h[[cc]] <- ""
tmpl <- h[, TEMPLATE_COLS]

s1_model <- if ("model" %in% names(s1) && nzchar(s1$model[1]))
  gsub("[^a-z0-9]+", "-", tolower(s1$model[1])) else "unknown"
stamp <- paste0(s1_model, "_", format(Sys.time(), "%Y%m%d_%H%M"))
out1 <- file.path(OUT_DIR, paste0("harmonized_", stamp, ".csv"))
out2 <- file.path(OUT_DIR, paste0("harmonized_diagnostics_", stamp, ".csv"))
write_csv(tmpl, out1)
h$harmonize_version <- PROMPT_VERSION; h$session1_file <- basename(s1_csv)
write_csv(h, out2)
cat("template-shaped:", out1, "\ndiagnostics:    ", out2, "\n")
cat("actors: ", sum(!startsWith(unlist(amap), "NEW:")), "matched,",
    sum(startsWith(unlist(amap), "NEW:")), "proposed new\n")
