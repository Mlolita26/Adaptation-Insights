##############################################################################
# score_locations.R — QC the location-specific extraction against Lucy's
# manual gold rows (catalogues/gold_v1_locations.csv, from working DB v02).
#
# Rows have no natural key, so scoring is two-level:
#   1. SET-BASED per project: row counts, location coverage (names, via the
#      registry), result-value coverage.
#   2. ALIGNMENT: each gold row is matched to its best pipeline row (value +
#      location + text overlap), then fields are compared on the aligned
#      pairs. An alignment CSV is written for human review.
#
# Usage:
#   Rscript R/extraction/score_locations.R [harmonized.csv] [gold.csv]
##############################################################################

suppressPackageStartupMessages({ library(openxlsx) })

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- if (length(full)) normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", "..")) else getwd()
source(file.path(REPO, "R", "shared", "paths.R"))
OUT_DIR <- Sys.getenv("EXTRACT_OUT_DIR", file.path(REPO, "outputs", "extraction", "locations"))

args <- commandArgs(trailingOnly = TRUE)
HFILE <- if (length(args) >= 1) args[1] else {
  fs <- list.files(OUT_DIR, pattern = "^locations_harmonized_.*\\.csv$", full.names = TRUE)
  stopifnot("no harmonized locations CSV found" = length(fs) > 0)
  fs[which.max(file.mtime(fs))]
}
GFILE <- if (length(args) >= 2) args[2] else file.path(REPO, "catalogues", "gold_v1_locations.csv")
cat("pipeline:", HFILE, "\ngold:    ", GFILE, "\n\n")

h <- read.csv(HFILE, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE)
g <- read.csv(GFILE, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE)
h[is.na(h)] <- ""; g[is.na(g)] <- ""

## code -> name/country via the template registry + this run's proposals
REG <- read.xlsx(TEMPLATE_XLSX, sheet = "location_codes")
REG[is.na(REG)] <- ""
prop_csv <- file.path(REVIEW_DIR, "proposed_new_locations.csv")
if (file.exists(prop_csv)) {
  pr <- read.csv(prop_csv, stringsAsFactors = FALSE, colClasses = "character")
  pr[is.na(pr)] <- ""
  REG <- rbind(REG[, c("location_name", "location_id", "location_country")],
               pr[, c("location_name", "location_id", "location_country")])
} else REG <- REG[, c("location_name", "location_id", "location_country")]
code2name <- setNames(REG$location_name, REG$location_id)

norm_loc <- function(x) {
  x <- tolower(iconv(x, "UTF-8", "ASCII//TRANSLIT"))
  x <- gsub("\\b(district|region|province|commune|county|sub-?county|village|town|city|watershed|department|the|of)\\b", " ", x)
  x <- gsub("[^a-z0-9]+", " ", x)
  trimws(gsub("\\s+", " ", x))
}
codes_to_names <- function(codes) {
  cds <- trimws(strsplit(codes, ";")[[1]])
  vapply(cds, function(cd) if (cd %in% names(code2name)) code2name[[cd]] else cd,
         character(1), USE.NAMES = FALSE)
}
norm_num <- function(x) {
  x <- gsub("[^0-9.]", "", x)
  v <- suppressWarnings(as.numeric(x))
  # per element: vectorized format() pads a whole vector to common decimals
  vapply(v, function(z) if (is.na(z)) "" else
    format(z, scientific = FALSE, trim = TRUE, digits = 15), character(1))
}
toks <- function(x) {
  t <- strsplit(norm_loc(x), " ")[[1]]
  unique(t[nchar(t) > 3])
}
jac <- function(a, b) {
  if (!length(a) || !length(b)) return(0)
  length(intersect(a, b)) / length(union(a, b))
}

## gold location names come pre-translated in location_names
g$loc_names <- lapply(ifelse(nzchar(g$location_names), g$location_names, g$location),
                      function(x) norm_loc(trimws(strsplit(x, ";")[[1]])))
h$loc_names <- lapply(h$location, function(x) norm_loc(codes_to_names(x)))

summary_rows <- list(); align_rows <- list()
for (pc in sort(unique(g$project_code))) {
  gp <- g[g$project_code == pc, ]; hp <- h[h$project_code == pc, ]
  g_locs <- unique(unlist(gp$loc_names)); g_locs <- g_locs[nzchar(g_locs) & g_locs != "unspecified"]
  h_locs <- unique(unlist(hp$loc_names)); h_locs <- h_locs[nzchar(h_locs) & h_locs != "unspecified"]
  # a gold location counts as covered on exact match OR word-level containment
  # ("tanzania" is covered by "mainland tanzania bagamoyo"), both directions
  covers <- function(g) any(vapply(h_locs, function(h)
    g == h || grepl(paste0("\\b", g, "\\b"), h) || grepl(paste0("\\b", h, "\\b"), g),
    logical(1)))
  loc_hit <- sum(vapply(g_locs, covers, logical(1)))
  g_vals <- unique(norm_num(gp$result_value)); g_vals <- g_vals[nzchar(g_vals)]
  h_vals <- unique(norm_num(hp$result_value)); h_vals <- h_vals[nzchar(h_vals)]
  val_hit <- sum(g_vals %in% h_vals)

  # align each gold row to its best pipeline row
  lvl_ok <- sub_ok <- ben_ok <- n_aligned <- 0
  for (i in seq_len(nrow(gp))) {
    if (!nrow(hp)) break
    sc <- vapply(seq_len(nrow(hp)), function(j) {
      s <- 0
      gv <- norm_num(gp$result_value[i])
      if (nzchar(gv) && gv == norm_num(hp$result_value[j])) s <- s + 3
      s <- s + 2 * jac(gp$loc_names[[i]], hp$loc_names[[j]])
      s <- s + jac(toks(gp$result_stated[i]), toks(hp$result_stated[j]))
      s <- s + jac(toks(gp$intervention_stated[i]), toks(hp$intervention_stated[j]))
      s
    }, numeric(1))
    j <- which.max(sc)
    matched <- sc[j] >= 0.8
    if (matched) {
      n_aligned <- n_aligned + 1
      if (tolower(gp$result_level[i]) == tolower(hp$result_level[j]) &&
          nzchar(gp$result_level[i])) lvl_ok <- lvl_ok + 1
      if (tolower(gp$subsector_type[i]) == tolower(hp$`subsector type`[j]) &&
          nzchar(gp$subsector_type[i])) sub_ok <- sub_ok + 1
      if (tolower(gp$target_beneficiary[i]) == tolower(hp$target_beneficiary[j]) &&
          nzchar(gp$target_beneficiary[i])) ben_ok <- ben_ok + 1
    }
    align_rows[[length(align_rows) + 1]] <- data.frame(
      project = pc, gold_row = gp$row_id[i], matched = matched,
      score = round(sc[j], 2),
      gold_loc = substr(gp$location_names[i], 1, 40),
      pipe_loc = substr(paste(codes_to_names(hp$location[j]), collapse = "; "), 1, 40),
      gold_value = gp$result_value[i], pipe_value = hp$result_value[j],
      gold_level = gp$result_level[i], pipe_level = hp$result_level[j],
      gold_subsector = gp$subsector_type[i], pipe_subsector = hp$`subsector type`[j],
      gold_beneficiary = gp$target_beneficiary[i], pipe_beneficiary = hp$target_beneficiary[j],
      gold_result = substr(gp$result_stated[i], 1, 70),
      pipe_result = substr(hp$result_stated[j], 1, 70),
      stringsAsFactors = FALSE)
  }
  summary_rows[[pc]] <- data.frame(
    project = pc, rows_gold = nrow(gp), rows_pipe = nrow(hp),
    gold_locs = length(g_locs), locs_covered = loc_hit,
    extra_pipe_locs = length(setdiff(h_locs, g_locs)),
    gold_values = length(g_vals), values_covered = val_hit,
    rows_aligned = n_aligned,
    level_agree = lvl_ok, subsector_agree = sub_ok, beneficiary_agree = ben_ok,
    stringsAsFactors = FALSE)
}
S <- do.call(rbind, summary_rows)
A <- do.call(rbind, align_rows)

tag <- paste0(sub("^locations_harmonized_", "", sub("\\.csv$", "", basename(HFILE))),
              "_vs_", sub("^(gold_v1_|claude_)", "", sub("\\.csv$", "", basename(GFILE))))
dir.create(SCORES_DIR, recursive = TRUE, showWarnings = FALSE)
sf <- file.path(SCORES_DIR, paste0("score_locations_", tag, ".csv"))
af <- file.path(SCORES_DIR, paste0("align_locations_", tag, ".csv"))
write.csv(S, sf, row.names = FALSE); write.csv(A, af, row.names = FALSE)

print(S, row.names = FALSE)
cat(sprintf(paste0(
  "\nTOTALS: gold rows %d | pipeline rows %d | gold locations covered %d/%d",
  " (%.0f%%)\n        gold result values found %d/%d (%.0f%%) | gold rows",
  " aligned %d/%d\n        on aligned rows - level %d, subsector %d,",
  " beneficiary %d agree\n"),
  sum(S$rows_gold), sum(S$rows_pipe), sum(S$locs_covered), sum(S$gold_locs),
  100 * sum(S$locs_covered) / max(1, sum(S$gold_locs)),
  sum(S$values_covered), sum(S$gold_values),
  100 * sum(S$values_covered) / max(1, sum(S$gold_values)),
  sum(S$rows_aligned), sum(S$rows_gold),
  sum(S$level_agree), sum(S$subsector_agree), sum(S$beneficiary_agree)))
cat("\nwritten:", sf, "\n         ", af, "\n")
