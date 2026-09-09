##############################################################################
# harmonize_locations.R — SESSION 2 for the LOCATION-SPECIFIC template sheet
#
# Reads the verbatim rows from extract_locations.R and produces the template's
# project_data_location-specific columns:
#   - location codes matched against the template's location_codes registry
#     (677 entries; codes are reused across projects), unmatched locations
#     become PROPOSALS in 04_Extraction_Results/review/proposed_new_locations.csv
#     with a suggested code {project_code}.{next number} and LLM-estimated
#     coordinates marked for human verification ("pipeline proposes, team
#     decides", protocol §5)
#   - subsector type (7 controlled values), result_level (5), and
#     target_beneficiary (24) — deterministic keyword pass first, then ONE
#     batched LLM call per field for the leftovers (cost priority)
#   - project_title / project_lead / resource_id joined from the latest
#     harmonized GENERAL extraction for the same project codes
#
# Usage:
#   Rscript R/extraction/harmonize_locations.R [s1loc_rows_....csv]
#   (default: the newest s1loc_rows CSV in outputs/extraction/locations)
##############################################################################

suppressPackageStartupMessages({
  library(ellmer); library(jsonlite); library(readr); library(openxlsx)
})

MODEL <- Sys.getenv("EXTRACT_MODEL", "gpt-5-mini")
MODEL_TAG <- gsub("[^a-z0-9]+", "-", tolower(MODEL))
HARM_VERSION <- "loc-s2-v1.0"
if (!nzchar(Sys.getenv("OPENAI_API_KEY")))
  for (p in c(file.path(Sys.getenv("OneDrive"), "Documents", ".Renviron"),
              file.path(Sys.getenv("USERPROFILE"), "Documents", ".Renviron")))
    if (file.exists(p)) { readRenviron(p); break }
stopifnot("OPENAI_API_KEY not set" = nzchar(Sys.getenv("OPENAI_API_KEY")))

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", "..")) else getwd()
source(file.path(REPO, "R", "shared", "paths.R"))
OUT_DIR <- Sys.getenv("EXTRACT_OUT_DIR", file.path(REPO, "outputs", "extraction", "locations"))

args <- commandArgs(trailingOnly = TRUE)
S1_ROWS <- if (length(args)) args[1] else {
  fs <- list.files(OUT_DIR, pattern = "^s1loc_rows_.*\\.csv$", full.names = TRUE)
  stopifnot("no s1loc_rows CSV found — run extract_locations.R first" = length(fs) > 0)
  fs[which.max(file.mtime(fs))]
}
# the location enumeration of the same run (same stamp), else the newest
S1_LOCS <- {
  want <- sub("s1loc_rows_", "s1loc_locations_", S1_ROWS)
  if (file.exists(want)) want else {
    fs <- list.files(OUT_DIR, pattern = "^s1loc_locations_.*\\.csv$", full.names = TRUE)
    if (length(fs)) fs[which.max(file.mtime(fs))] else NA
  }
}
cat("rows:      ", S1_ROWS, "\nlocations: ", S1_LOCS, "\n")
rows <- read.csv(S1_ROWS, stringsAsFactors = FALSE, colClasses = "character")
rows[is.na(rows)] <- ""

# ---- one value per row (v1.2) ------------------------------------------------
# The template wants one row per location x intervention x RESULT. Session 1
# sometimes packs a location's several results into one cell
# ("95;2338654;18208;49"), which makes the value unusable. Split those cells
# into one row each, pairing units positionally when the model supplied them.
split_multivalue <- function(d) {
  if (!nrow(d) || !"result_value" %in% names(d)) return(d)
  out <- vector("list", nrow(d)); n_split <- 0
  for (i in seq_len(nrow(d))) {
    v <- trimws(strsplit(d$result_value[i], "\\s*;\\s*")[[1]])
    v <- v[nzchar(v)]
    if (length(v) <= 1) { out[[i]] <- d[i, , drop = FALSE]; next }
    u <- trimws(strsplit(d$result_unit_stated[i], "\\s*;\\s*")[[1]])
    u <- u[nzchar(u)]
    rep_rows <- d[rep(i, length(v)), , drop = FALSE]
    rep_rows$result_value <- v
    rep_rows$result_unit_stated <- if (length(u) == length(v)) u else d$result_unit_stated[i]
    rep_rows$row_flags <- trimws(paste(rep_rows$row_flags,
      "split from a multi-value cell", sep = "; "))
    rep_rows$row_flags <- sub("^; ", "", rep_rows$row_flags)
    out[[i]] <- rep_rows; n_split <- n_split + 1
  }
  d2 <- do.call(rbind, out)
  if (n_split) cat(sprintf("  multi-value cells split: %d cell(s) -> %d rows (was %d)\n",
                           n_split, nrow(d2), nrow(d)))
  rownames(d2) <- NULL
  d2
}
rows <- split_multivalue(rows)

# ---- team field rules: whole-digit values, % for percentages -----------------
source(file.path(REPO, "R", "shared", "clean_fields.R"))
if (nrow(rows)) {
  n_fix <- 0
  for (i in seq_len(nrow(rows))) {
    if (!nzchar(rows$result_value[i])) next
    cn <- clean_number(rows$result_value[i])
    u  <- clean_unit(rows$result_unit_stated[i], rows$result_value[i])
    if (!identical(cn$value, rows$result_value[i]) ||
        !identical(u, rows$result_unit_stated[i])) n_fix <- n_fix + 1
    rows$result_value[i] <- cn$value
    rows$result_unit_stated[i] <- u
    if (nzchar(cn$note))
      rows$row_flags[i] <- trimws(paste(rows$row_flags[i], cn$note, sep = "; "))
  }
  rows$row_flags <- sub("^; ", "", rows$row_flags)
  cat(sprintf("  %-18s %d value/unit cells normalised (whole digits, %%)\n",
              "field rules", n_fix))
}
locs <- if (!is.na(S1_LOCS)) {
  l <- read.csv(S1_LOCS, stringsAsFactors = FALSE, colClasses = "character")
  l[is.na(l)] <- ""; l
} else NULL

## ── registry + helpers ──────────────────────────────────────────────────────
REG <- read.xlsx(TEMPLATE_XLSX, sheet = "location_codes")
REG[is.na(REG)] <- ""
norm_loc <- function(x) {
  x <- iconv(x, "UTF-8", "ASCII//TRANSLIT", sub = " ")
  x <- tolower(x)
  x <- gsub("\\s*\\([^)]*\\)", " ", x)          # strip parentheticals (v1.2)
  # plurals too: "Western Provinces" must reduce to the same key as the alias
  # "Western Province", or it is proposed as a new location
  x <- gsub("\\b(districts?|regions?|provinces?|communes?|count(y|ies)|sub-?count(y|ies)|villages?|towns?|cities|city|watersheds?|departments?|islands?|the|of)\\b", " ", x)
  x <- gsub("[^a-z0-9]+", " ", x)
  trimws(gsub("\\s+", " ", x))
}
REG$norm <- norm_loc(REG$location_name)
REG$norm_country <- tolower(trimws(REG$location_country))

# ---- location aliases (v1.2) -------------------------------------------------
# Registries and documents name the same place in different languages. Rows are
# name|alias (both directions are tried). Team-editable; missing file is fine.
ALIAS <- local({
  p <- file.path(REVIEW_DIR, "location_aliases.csv")
  if (!file.exists(p)) return(NULL)
  a <- read.csv(p, stringsAsFactors = FALSE, colClasses = "character")
  a[is.na(a)] <- ""
  a[nzchar(a$name) & nzchar(a$alias), , drop = FALSE]
})
alias_forms <- function(nm) {
  out <- nm
  if (!is.null(ALIAS)) {
    n <- norm_loc(nm)
    out <- c(out, ALIAS$alias[norm_loc(ALIAS$name) == n], ALIAS$name[norm_loc(ALIAS$alias) == n])
  }
  unique(out[nzchar(out)])
}
# one spelling per country in the proposals file, or the review list splits
# ("United Republic of Tanzania" 25 + "Tanzania" 3 for the same country)
canon_country <- function(x) {
  if (!nzchar(x) || is.null(ALIAS)) return(x)
  n <- norm_loc(x)
  hit <- ALIAS$name[norm_loc(ALIAS$alias) == n]
  if (length(hit)) return(hit[1])
  strip <- function(s) trimws(gsub("\\s+", " ",
    gsub("\\b(republic|united|union|democratic|the|of)\\b", " ", tolower(s))))
  m <- REG$location_country[strip(REG$location_country) == strip(x) & nzchar(REG$location_country)]
  if (length(m)) m[1] else x
}

LOCATION_TYPES <- c("city", "country", "district", "farm", "region",
                    "sub-county", "town", "village", "watershed")
map_loc_type <- function(level_stated) {
  l <- tolower(level_stated)
  hit <- LOCATION_TYPES[vapply(LOCATION_TYPES, function(t) grepl(t, l, fixed = TRUE), logical(1))]
  if (length(hit)) return(hit[1])
  if (grepl("commune|municipal", l)) return("town")
  if (grepl("province|state|governorate|zone", l)) return("region")
  if (grepl("county|prefecture|department", l)) return("district")
  if (grepl("site|community|locality|oasis", l)) return("village")
  ""   # unknown -> LLM batch decides later
}

# country lookup per (document, location name) from the enumeration output
loc_country <- function(doc, name) {
  if (is.null(locs)) return("")
  m <- locs[locs$document == doc & norm_loc(locs$location_name) == norm_loc(name), ]
  if (nrow(m)) m$country[1] else ""
}
loc_level <- function(doc, name) {
  if (is.null(locs)) return("")
  m <- locs[locs$document == doc & norm_loc(locs$location_name) == norm_loc(name), ]
  if (nrow(m)) m$level_stated[1] else ""
}

## ── location-code matcher (deterministic tiers + proposal intake) ──────────
proposals <- list()
next_no <- local({
  counters <- new.env()
  # codes already handed out in earlier runs must be counted too, or every run
  # restarts at registry-max + 1 and re-issues the same codes to other places
  prev_ids <- local({
    p <- file.path(REVIEW_DIR, "proposed_new_locations.csv")
    if (!file.exists(p)) return(character(0))
    x <- read.csv(p, stringsAsFactors = FALSE, colClasses = "character")
    x$location_id[!is.na(x$location_id)]
  })
  function(pcode) {
    key <- pcode
    if (is.null(counters[[key]])) {
      ex <- c(REG$location_id[startsWith(REG$location_id, paste0(pcode, "."))],
              prev_ids[startsWith(prev_ids, paste0(pcode, "."))])
      ns <- suppressWarnings(as.integer(sub("^.*\\.", "", ex)))
      counters[[key]] <- if (length(ns) && any(!is.na(ns))) max(ns, na.rm = TRUE) else 0
    }
    counters[[key]] <- counters[[key]] + 1
    counters[[key]]
  }
})

match_one_loc <- function(name, pcode, doc) {
  if (tolower(trimws(name)) %in% c("unspecified", "n/a", "")) {
    un <- REG[REG$location_name == "Unspecified" &
              startsWith(REG$location_id, paste0(pcode, ".")), ]
    if (nrow(un)) return(list(code = un$location_id[1], how = "registry-unspecified"))
    key <- paste0(pcode, "|Unspecified")
    if (is.null(proposals[[key]]))
      proposals[[key]] <<- data.frame(
        location_name = "Unspecified", location_id = paste0(pcode, ".0"),
        location_type = "N/A", coordinate_latitude = "N/A",
        coordinate_longitude = "N/A", coordinate_type = "N/A",
        location_country = "N/A", first_seen_project = pcode,
        source_document = doc, note = "", stringsAsFactors = FALSE)
    return(list(code = paste0(pcode, ".0"), how = "proposed-unspecified"))
  }
  ctry <- tolower(trimws(loc_country(doc, name)))
  # each tier is tried for the name and for any registered alias of it (v1.2)
  forms <- unique(norm_loc(alias_forms(name)))
  forms <- forms[nzchar(forms)]
  if (!length(forms)) forms <- norm_loc(name)
  # tier 1: exact normalized name (or alias) + country
  m <- REG[REG$norm %in% forms & nzchar(ctry) & REG$norm_country == ctry, ]
  if (nrow(m) >= 1) return(list(code = m$location_id[1], how = "name+country"))
  # tier 2: exact normalized name (or alias), unique across the registry
  m <- REG[REG$norm %in% forms & nzchar(REG$norm), ]
  if (nrow(m) == 1) return(list(code = m$location_id[1], how = "name-unique"))
  if (nrow(m) > 1) {
    # prefer an entry whose country matches this project's other locations
    return(list(code = m$location_id[1], how = "ambiguous"))
  }
  # tier 3: new location -> proposal (dedup within this run)
  key <- paste0(tolower(name), "|", ctry)
  if (!is.null(proposals[[key]])) return(list(code = proposals[[key]]$location_id, how = "proposed"))
  code <- paste0(pcode, ".", next_no(pcode))
  proposals[[key]] <<- data.frame(
    location_name = trimws(name), location_id = code,
    location_type = map_loc_type(loc_level(doc, name)),
    coordinate_latitude = "", coordinate_longitude = "",
    coordinate_type = "estimated",
    location_country = canon_country(trimws(loc_country(doc, name))),
    first_seen_project = pcode, source_document = doc,
    note = "", stringsAsFactors = FALSE)
  list(code = code, how = "proposed")
}

rows$location <- ""; rows$loc_match <- ""
for (i in seq_len(nrow(rows))) {
  nms <- strsplit(rows$locations_stated[i], ";\\s*")[[1]]
  res <- lapply(nms, match_one_loc, pcode = rows$project_code_hint[i],
                doc = rows$document[i])
  codes <- vapply(res, `[[`, character(1), "code")
  hows  <- vapply(res, `[[`, character(1), "how")
  keep  <- nzchar(codes)
  rows$location[i]  <- paste(codes[keep], collapse = "; ")
  rows$loc_match[i] <- paste(unique(hows), collapse = ",")
}

## ── controlled vocabularies: deterministic pass then ONE batched LLM call ──
SUBSECTORS <- c("agri-food", "farming system-crop", "farming system-livestock",
                "farming system-mixed", "farming system-fish", "land use",
                "cross cutting")
SUB_DEFS <- paste(
  "1) agri-food: food production and distribution systems (processing,",
  "value chains, markets, food security programming);",
  "2) farming system-crop: plant cultivation and harvest activities;",
  "3) farming system-livestock: animal raising and breeding operations;",
  "4) farming system-mixed: combined crops and livestock farming, as well as fisheries;",
  "5) farming system-fish: aquatic harvesting and fish farming;",
  "6) land use: territorial management and spatial planning (land, soil,",
  "watershed, forest management and restoration);",
  "7) cross cutting: spans several domains or targets none in particular",
  "(finance, insurance, policy, capacity building across sectors).")

det_subsector <- function(txt) {
  t <- tolower(txt)
  fish <- grepl("fish|aquacult|coastal|marine", t)
  live <- grepl("livestock|pastoral|herd|cattle|goat|sheep|poultry|dairy|fodder", t)
  crop <- grepl("crop|maize|rice|seed|cocoa|coffee|cassava|wheat|sorghum|horticult|vegetable|cereal|yield|palm oil|soy", t)
  land <- grepl("land management|land use|land degradation|watershed|forest|restoration|reforestation|slwm|soil conservation|erosion|deforestation", t)
  food <- grepl("value chain|processing|post-?harvest|storage|market access|food distribution|food system", t)
  hits <- c(fish = fish, live = live, crop = crop, land = land, food = food)
  if (sum(hits) != 1) return("")
  c(fish = "farming system-fish", live = "farming system-livestock",
    crop = "farming system-crop", land = "land use",
    food = "agri-food")[names(hits)[hits]]
}

TARGETS <- c("agribusiness", "artisanal fisher", "children", "community",
  "cooperative", "elderly", "farm laborer", "farmer association",
  "farmer group", "household", "indigenous peoples", "low-income households",
  "marginalized group", "migrant", "pastoralist/herder", "people with disabilities/ disability",
  "producer", "producer organization", "smallholder farmer", "subsistence farmer",
  "vulnerable population", "women (female-headed households)",
  "women's group/organization", "youth")
det_target <- function(txt) {
  t <- tolower(txt)
  pat <- c("smallholder farmer" = "smallholder", "subsistence farmer" = "subsistence farmer",
    "artisanal fisher" = "artisanal fish|small-scale fish", "pastoralist/herder" = "pastoralist|herder",
    "farmer association" = "farmer associations?\\b", "farmer group" = "farmer groups?\\b",
    "producer organization" = "producer organi", "cooperative" = "cooperativ",
    "women's group/organization" = "women'?s group|women'?s organi",
    "women (female-headed households)" = "female-?headed|\\bwomen\\b",
    "youth" = "\\byouth\\b|young people", "household" = "households?\\b",
    "community" = "communit", "indigenous peoples" = "indigenous",
    "agribusiness" = "agribusiness|agri-?enterprise", "farm laborer" = "farm labou?rer",
    "children" = "\\bchildren\\b", "elderly" = "elderly", "migrant" = "migrant",
    "people with disabilities/ disability" = "disabilit",
    "vulnerable population" = "vulnerable")
  hit <- names(pat)[vapply(pat, function(p) grepl(p, t), logical(1))]
  if (length(hit) == 1) hit else ""   # several hits -> LLM picks overarching
}

RESULT_LEVELS <- c("input", "process", "output", "outcome", "impact")
LEVEL_DEFS <- paste(
  "1) input: resources, means and investments mobilized to conduct",
  "interventions; 2) process: activities or tasks carried out by the project",
  "team (trainings held, workshops conducted, systems set up); 3) output:",
  "short-term direct results of activities (people trained, hectares treated,",
  "infrastructure delivered, groups formed); 4) outcome: medium-term effects",
  "on beneficiaries (adoption of practices, productivity or income increases,",
  "improved food security); 5) impact: long-term systemic results.")

# one batched structured call: items {idx, choice}
llm_choose <- function(items, vocab, defs, what) {
  if (!nrow(items)) return(character(0))
  chat <- chat_openai(model = MODEL, system_prompt = paste(
    "You classify grey-literature extraction snippets into a fixed vocabulary.",
    "Choose EXACTLY one vocabulary value per item, from the list given.",
    "If no value fits at all, answer 'CANDIDATE: <your suggested new term>'."))
  prompt <- paste0(
    "VOCABULARY for ", what, ":\n", paste("-", vocab, collapse = "\n"),
    "\n\nDEFINITIONS:\n", defs, "\n\nITEMS:\n",
    paste0("[", items$idx, "] ", items$text, collapse = "\n"),
    "\n\nReturn one choice per item id.")
  res <- tryCatch(chat$chat_structured(prompt, type = type_array(
    items = type_object(
      idx = type_integer("The item id in brackets."),
      choice = type_string("One vocabulary value verbatim, or 'CANDIDATE: ...'.")))),
    error = function(e) { warning(what, " LLM batch failed: ", conditionMessage(e)); NULL })
  out <- setNames(rep("", nrow(items)), items$idx)
  if (is.null(res)) return(out)
  if (is.data.frame(res)) res <- lapply(seq_len(nrow(res)), function(i) as.list(res[i, ]))
  for (r in res) {
    k <- as.character(r$idx)
    if (k %in% names(out)) out[k] <- as.character(r$choice)
  }
  out
}

CAND_LOG <- file.path(REVIEW_DIR, "candidate_vocab_log.csv")
log_candidate <- function(field, value, context) {
  row <- data.frame(date = format(Sys.Date()), field = field, candidate = value,
                    context = substr(context, 1, 160), stringsAsFactors = FALSE)
  if (file.exists(CAND_LOG)) {
    old <- read.csv(CAND_LOG, stringsAsFactors = FALSE, colClasses = "character")
    old[is.na(old)] <- ""
    if ("field" %in% names(old) && "candidate" %in% names(old) &&
        any(old$field == field & old$candidate == value)) return(invisible())
    # the general harmonizer writes this file with its own columns — align
    for (cn in setdiff(names(old), names(row))) row[[cn]] <- ""
    for (cn in setdiff(names(row), names(old))) old[[cn]] <- ""
    row <- rbind(old, row[names(old)])
  }
  write.csv(row, CAND_LOG, row.names = FALSE)
}

apply_vocab <- function(rows, field_out, text_fun, det_fun, vocab, defs, what,
                        only = rep(TRUE, nrow(rows))) {
  rows[[field_out]] <- ""
  txts <- text_fun(rows)
  for (i in seq_len(nrow(rows))) if (only[i] && nzchar(trimws(txts[i])))
    rows[[field_out]][i] <- det_fun(txts[i])
  todo <- which(only & nzchar(trimws(txts)) & !nzchar(rows[[field_out]]))
  cat(sprintf("  %-18s det: %d | LLM: %d | skipped: %d\n", what,
      sum(nzchar(rows[[field_out]])), length(todo),
      sum(!only | !nzchar(trimws(txts)))))
  if (length(todo)) {
    items <- data.frame(idx = todo, text = substr(txts[todo], 1, 300))
    ch <- llm_choose(items, vocab, defs, what)
    for (k in names(ch)) {
      i <- as.integer(k); v <- ch[k]
      if (v %in% vocab) rows[[field_out]][i] <- v
      else if (startsWith(v, "CANDIDATE")) {
        log_candidate(what, sub("^CANDIDATE:\\s*", "", v), txts[i])
        rows$notes_extra[i] <- paste0(rows$notes_extra[i], "; vocab candidate (",
                                      what, "): ", sub("^CANDIDATE:\\s*", "", v))
      } else if (nzchar(v)) {
        # tolerate case/spacing mismatches from the model
        hit <- vocab[tolower(gsub("[^a-z]", "", vocab)) == tolower(gsub("[^a-zA-Z]", "", v))]
        if (length(hit) == 1) rows[[field_out]][i] <- hit
      }
    }
  }
  rows
}

rows$notes_extra <- ""
cat("controlled-vocabulary mapping:\n")
rows <- apply_vocab(rows, "subsector_type",
  function(r) paste(r$subsector_stated, "|", r$intervention_stated),
  det_subsector, SUBSECTORS, SUB_DEFS, "subsector type")
rows <- apply_vocab(rows, "target_beneficiary",
  function(r) r$target_beneficiary_stated,
  det_target, TARGETS, paste("Pick the LARGER/overarching group when several",
  "apply (e.g. 'community'). Vocabulary as defined in the template readme."),
  "target_beneficiary")
# A7: a row with a result must name who benefited. Where the location passage
# is silent, inherit the project's own beneficiary (the most frequent value
# among that project's other rows), and say so in the notes.
{
  need <- (nzchar(rows$result_stated) | nzchar(rows$result_value)) &
          !nzchar(rows$target_beneficiary)
  n_inherit <- 0
  for (pc in unique(rows$project_code_hint[need])) {
    have <- rows$target_beneficiary[rows$project_code_hint == pc & nzchar(rows$target_beneficiary)]
    if (!length(have)) next
    fallback <- names(sort(table(have), decreasing = TRUE))[1]
    idx <- which(need & rows$project_code_hint == pc)
    rows$target_beneficiary[idx] <- fallback
    rows$notes_extra[idx] <- paste0(rows$notes_extra[idx],
      "; beneficiary inherited from project (", fallback, ")")
    n_inherit <- n_inherit + length(idx)
  }
  cat(sprintf("  %-18s inherited for %d result rows with no stated group\n",
              "beneficiary", n_inherit))
}
has_result <- nzchar(rows$result_stated) | nzchar(rows$result_value)
rows <- apply_vocab(rows, "result_level",
  function(r) paste(r$result_stated, "|", r$result_value, r$result_unit_stated),
  function(txt) "", RESULT_LEVELS, LEVEL_DEFS, "result_level", only = has_result)

## ── coordinates for proposed locations (one batched call, estimated) ───────
prop <- if (length(proposals)) do.call(rbind, unname(proposals)) else NULL
if (!is.null(prop)) {
  need <- which(prop$location_name != "Unspecified")
  if (length(need)) {
    chat <- chat_openai(model = MODEL, system_prompt = paste(
      "You provide approximate WGS84 coordinates for named places, for later",
      "human verification. If you do not recognize a place, say so."))
    res <- tryCatch(chat$chat_structured(paste0(
      "Approximate coordinates for these places (decimal degrees, 4 decimals):\n",
      paste0("[", need, "] ", prop$location_name[need], ", ",
             prop$location_country[need], collapse = "\n")),
      type = type_array(items = type_object(
        idx = type_integer("Item id in brackets."),
        latitude = type_string("Decimal latitude, e.g. '12.3456'. Empty if unknown."),
        longitude = type_string("Decimal longitude. Empty if unknown."),
        known = type_boolean("FALSE if you do not actually recognize this place.")))),
      error = function(e) { warning("coords batch failed: ", conditionMessage(e)); NULL })
    if (!is.null(res)) {
      if (is.data.frame(res)) res <- lapply(seq_len(nrow(res)), function(i) as.list(res[i, ]))
      for (r in res) {
        i <- as.integer(r$idx)
        if (!is.na(i) && i %in% need && isTRUE(r$known)) {
          prop$coordinate_latitude[i]  <- as.character(r$latitude)
          prop$coordinate_longitude[i] <- as.character(r$longitude)
        }
      }
    }
    prop$note[need] <- trimws(paste(prop$note[need],
      "coordinates LLM-estimated - verify before use"))
  }
  # append to the shared review file, dedup by name+country+project
  PROP_CSV <- file.path(REVIEW_DIR, "proposed_new_locations.csv")
  if (file.exists(PROP_CSV)) {
    old <- read.csv(PROP_CSV, stringsAsFactors = FALSE, colClasses = "character")
    key <- function(d) tolower(paste(d$location_name, d$location_country, d$first_seen_project))
    prop <- rbind(old, prop[!key(prop) %in% key(old), , drop = FALSE])
  }
  write.csv(prop, PROP_CSV, row.names = FALSE)
  cat("proposed new locations:", sum(prop$location_name != "Unspecified"),
      "->", PROP_CSV, "\n")
}

## ── project-level fields from the latest harmonized general run ────────────
gen <- local({
  fs <- list.files(file.path(REPO, "outputs", "extraction"),
                   pattern = "^harmonized_.*\\.csv$", full.names = TRUE)
  if (!length(fs)) return(NULL)
  g <- read.csv(fs[which.max(file.mtime(fs))], stringsAsFactors = FALSE,
                colClasses = "character")
  g[is.na(g)] <- ""; g
})
pick <- function(g, want) if (!is.null(g) && want %in% names(g)) g[[want]] else ""
join_gen <- function(pcode, field) {
  if (is.null(gen) || !"project_code" %in% names(gen)) return("")
  m <- gen[gen$project_code == pcode, ]
  if (nrow(m) && field %in% names(m)) m[[field]][1] else ""
}

## ── assemble the template sheet ────────────────────────────────────────────
out <- data.frame(
  row_id = seq_len(nrow(rows)),
  project_code  = rows$project_code_hint,
  project_title = vapply(rows$project_code_hint, join_gen, character(1), "project_title"),
  project_lead  = vapply(rows$project_code_hint, join_gen, character(1), "project_lead"),
  location = rows$location,
  subsector_stated = rows$subsector_stated,
  `subsector type` = rows$subsector_type,
  intervention_stated = rows$intervention_stated,
  rationale_stated = rows$rationale_stated,
  target_beneficiary = rows$target_beneficiary,
  result_stated = rows$result_stated,
  result_value = rows$result_value,
  result_unit = rows$result_unit_stated,
  result_level = rows$result_level,
  evidence_methodology = rows$evidence_methodology_stated,
  evidence_source = rows$evidence_source_stated,
  resource_id = vapply(rows$project_code_hint, join_gen, character(1), "resource_id"),
  evidence_depth = rows$evidence_depth,
  resource_link = vapply(rows$project_code_hint, join_gen, character(1), "reference_link_1"),
  notes = trimws(sub("^; ", "", paste0(
    ifelse(nzchar(rows$row_flags), paste0(rows$row_flags, "; "), ""),
    ifelse(nzchar(rows$loc_match) & grepl("proposed|ambiguous", rows$loc_match),
           paste0("location ", rows$loc_match, "; "), ""),
    sub("^; ", "", rows$notes_extra)))),
  check.names = FALSE, stringsAsFactors = FALSE)

stamp <- paste0(MODEL_TAG, "_", format(Sys.time(), "%Y%m%d_%H%M"))
f <- file.path(OUT_DIR, paste0("locations_harmonized_", stamp, ".csv"))
write_csv(out, f)
cat("\nwritten:", f, "(", nrow(out), "rows )\n")
cat("rows per project:\n"); print(table(out$project_code))
cat("location match methods:\n"); print(table(rows$loc_match))
