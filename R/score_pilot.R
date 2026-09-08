##############################################################################
# score_pilot.R — field-level agreement between the two-session pipeline
# output and the CORRECTED gold standard (metadata/gold_v1_general.csv,
# derived from the 2026-09-08 gold-standard audit).
#
# Gold cells may hold several acceptable alternates separated by ' || '
# (the audit found genuinely defensible variants, e.g. counting rules).
# Verdicts: match | mismatch | candidate (pipeline flagged a vocab gap /
# unregistered actor rather than forcing a value) | both_empty.
# Results are scored as a SET: each filled result slot counts as a hit if
# its value matches any value in the gold results_set.
#
# Usage: Rscript R/score_pilot.R [harmonized_diagnostics_*.csv]
##############################################################################

suppressPackageStartupMessages({ library(readr); library(dplyr) })

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..")) else getwd()
OUT_DIR <- file.path(REPO, "data", "extraction")

args <- commandArgs(trailingOnly = TRUE)
hfile <- if (length(args)) args[1] else {
  f <- list.files(OUT_DIR, pattern = "^harmonized_diagnostics_.*\\.csv$", full.names = TRUE)
  stopifnot("no harmonized_diagnostics_*.csv found" = length(f) > 0)
  f[which.max(file.mtime(f))]
}
cat("scoring:", hfile, "\n")
h <- read.csv(hfile, check.names = FALSE, stringsAsFactors = FALSE); h[is.na(h)] <- ""
g <- read.csv(file.path(REPO, "metadata", "gold_v1_general.csv"),
              check.names = FALSE, stringsAsFactors = FALSE); g[is.na(g)] <- ""

nrm <- function(x) trimws(gsub("\\s+", " ", gsub("[^a-z0-9 .>%/+-]", " ", tolower(x))))
num_one <- function(x) {
  x <- tolower(gsub(",", "", as.character(x)))
  v <- suppressWarnings(as.numeric(x))            # handles 9.1e+07 round-trips
  if (!is.na(v)) return(format(v, scientific = FALSE, trim = TRUE))
  x <- gsub("\\([^)]*\\)", "", x)                 # drop '(111 percent of target)'
  m <- regmatches(x, regexpr("[0-9]+(\\.[0-9]+)?\\s*(billion|million|thousand)?", x))
  if (!length(m) || !nzchar(m)) return("")
  scale <- if (grepl("billion", m)) 1e9 else if (grepl("million", m)) 1e6 else
           if (grepl("thousand", m)) 1e3 else 1
  val <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", m))) * scale
  if (is.na(val)) "" else format(val, scientific = FALSE, trim = TRUE)
}
num <- function(x) vapply(as.character(x), num_one, character(1), USE.NAMES = FALSE)
alts <- function(cell) trimws(strsplit(as.character(cell), "\\|\\|")[[1]])

NUMERIC <- c("publication_year", "start_year", "closure_year", "budget_total",
             "disbursed", "location_count", "evidence_depth")
CONTAINS <- c("project_lead", "funder", "implementor")

match_field <- function(field, gold_cell, extracted) {
  a <- alts(gold_cell); e <- as.character(extracted)
  if (field == "resource_id") e <- sub("^\\s*report\\s+no[.:]?\\s*", "", e, ignore.case = TRUE)
  if (all(!nzchar(a)) && !nzchar(e)) return("both_empty")
  # titles: tolerate appended identifiers/acronyms — containment either way
  if (field == "project_title") {
    for (av in a) if (nchar(nrm(av)) >= 15 && nzchar(e) &&
        (grepl(nrm(av), nrm(e), fixed = TRUE) || grepl(nrm(e), nrm(av), fixed = TRUE)))
      return("match")
  }
  for (av in a) {
    if (!nzchar(av) && !nzchar(e)) return("match")
    if (!nzchar(av)) next
    if (field %in% NUMERIC) {
      if (nzchar(num(av)) && num(av) == num(e)) return("match")
    } else if (field %in% CONTAINS) {
      if (nzchar(e) && (grepl(nrm(av), nrm(e), fixed = TRUE) ||
                        grepl(nrm(e), nrm(av), fixed = TRUE))) return("match")
    } else {
      if (identical(av, "CANDIDATE") && grepl("^candidate", nrm(e))) return("match")
      if (nzchar(e) && nrm(av) == nrm(e)) return("match")
    }
  }
  if (grepl("^(candidate|new)[: ]", nrm(e))) return("candidate")
  "mismatch"
}

FIELDS <- c("project_title", "project_id", "project_lead", "publication_year",
  "start_year", "closure_year", "project_scale", "location_count",
  "target_beneficiary_project", "budget_total", "disbursed", "currency",
  "funding_mechanism", "funder", "implementor", "document_type",
  "resource_id", "evidence_depth")

rows <- list()
for (i in seq_len(nrow(g))) {
  pc <- g$project_code[i]
  hi <- which(h$project_code_hint == pc)
  if (!length(hi)) { cat("no pipeline row for", pc, "\n"); next }
  hr <- h[hi[1], ]
  for (f in FIELDS) {
    ev <- if (f %in% names(hr)) as.character(hr[[f]]) else ""
    rows[[length(rows) + 1]] <- data.frame(project = pc, field = f,
      gold = as.character(g[[f]][i]), extracted = substr(ev, 1, 120),
      verdict = match_field(f, as.character(g[[f]][i]), ev), stringsAsFactors = FALSE)
  }
  # results as a set
  gold_vals <- num(alts(g$results_set[i])); gold_vals <- gold_vals[nzchar(gold_vals)]
  slots <- c(hr$result1, hr$result2, hr$result3)
  slots <- as.character(slots[nzchar(as.character(slots))])
  hits <- sum(vapply(slots, function(s) num(s) %in% gold_vals, logical(1)))
  rows[[length(rows) + 1]] <- data.frame(project = pc, field = "results_set",
    gold = g$results_set[i],
    extracted = paste(slots, collapse = " | "),
    verdict = if (!length(slots)) "mismatch" else
              if (hits == length(slots)) "match" else
              if (hits > 0) "partial" else "mismatch",
    stringsAsFactors = FALSE)
}
sc <- bind_rows(rows)

stamp <- format(Sys.time(), "%Y%m%d_%H%M")
out <- file.path(OUT_DIR, paste0("score_", stamp, ".csv"))
write_csv(sc, out)

cat("\n== per-field agreement ==\n")
per_field <- sc %>% group_by(field) %>%
  summarise(match = sum(verdict %in% c("match", "both_empty")),
            partial = sum(verdict == "partial"),
            candidate = sum(verdict == "candidate"),
            mismatch = sum(verdict == "mismatch"), .groups = "drop") %>%
  arrange(desc(mismatch))
print(as.data.frame(per_field), row.names = FALSE)
tot <- nrow(sc)
cat(sprintf("\nOVERALL: %d checks | %.0f%% match | %d partial | %d candidate-flagged | %d mismatch\n",
  tot, 100 * sum(sc$verdict %in% c("match", "both_empty")) / tot,
  sum(sc$verdict == "partial"), sum(sc$verdict == "candidate"),
  sum(sc$verdict == "mismatch")))
cat("\nmismatches:\n")
mm <- sc[sc$verdict == "mismatch", c("project", "field", "gold", "extracted")]
if (nrow(mm)) print(mm, row.names = FALSE) else cat("none\n")
cat("\nwritten:", out, "\n")
