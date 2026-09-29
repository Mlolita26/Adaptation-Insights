# location_comparison.R - one workbook putting a reading reference of the
# LOCATION sheet, the pipeline's own sheet and the score side by side.
#
# score_locations.R writes two CSVs: a per-project summary and an alignment of
# every reference row to the pipeline row it was matched to. This turns those,
# plus the two sheets themselves, into a workbook a person can read:
#   summary      one row per document: rows, sites, values, what agreed
#   sites        one row per reference SITE: did it reach the sheet, was it
#                named at all, what each side holds for it
#   rows         one row per reference ROW beside its matched pipeline row,
#                with each field marked agree / differ / only one side
#   values       every reference value: kept, read but not kept, or never read
#   reference    the reference as written
#   pipeline     the pipeline's location sheet
#   about        which files, when
#
#   Rscript R/08_quality/location_comparison.R --score=<score_locations.csv> \
#       --align=<align_locations.csv> --reference=<reference.csv> \
#       --pipeline=<locations_harmonized.csv> --out=<workbook.xlsx> \
#       [--session1=<s1loc_rows.csv>] [--title="Charity pilot"]

suppressPackageStartupMessages(library(openxlsx))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default = "") {
  v <- sub(paste0("^--", name, "="), "", grep(paste0("^--", name, "="), args, value = TRUE))
  if (length(v)) v[1] else default
}
SCORE <- opt("score"); ALIGN <- opt("align"); REF <- opt("reference")
PIPE <- opt("pipeline"); OUT <- opt("out"); S1 <- opt("session1")
TITLE <- opt("title", "Location reference comparison")
stopifnot(nzchar(SCORE), nzchar(ALIGN), nzchar(REF), nzchar(PIPE), nzchar(OUT))

rd <- function(p) {
  d <- read.csv(p, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE)
  d[is.na(d)] <- ""; d
}
sc <- rd(SCORE); al <- rd(ALIGN); ref <- rd(REF); pipe <- rd(PIPE)
s1 <- if (nzchar(S1) && file.exists(S1)) rd(S1) else NULL

num <- function(x) suppressWarnings(as.numeric(gsub("[^0-9.]", "", x)))
pct <- function(a, b) if (is.na(b) || b == 0) "" else sprintf("%.0f percent", 100 * a / b)

## ---- summary ---------------------------------------------------------------
for (cl in c("rows_gold", "rows_pipe", "gold_locs", "locs_covered", "locs_named",
             "gold_values", "values_covered", "values_read", "rows_aligned",
             "level_agree", "subsector_agree", "beneficiary_agree", "extra_pipe_locs"))
  if (cl %in% names(sc)) sc[[cl]] <- num(sc[[cl]])

summ <- data.frame(
  document = sc$project,
  reference_rows = sc$rows_gold, pipeline_rows = sc$rows_pipe,
  reference_sites = sc$gold_locs,
  sites_in_the_sheet = sc$locs_covered,
  sites_named_anywhere = if ("locs_named" %in% names(sc)) sc$locs_named else NA,
  sites_only_the_pipeline_has = sc$extra_pipe_locs,
  reference_values = sc$gold_values,
  values_kept = sc$values_covered,
  values_read = if ("values_read" %in% names(sc)) sc$values_read else NA,
  rows_matched = sc$rows_aligned,
  level_agrees = sc$level_agree, subsector_agrees = sc$subsector_agree,
  beneficiary_agrees = sc$beneficiary_agree,
  stringsAsFactors = FALSE)
tot <- data.frame(document = "ALL", t(colSums(summ[, -1], na.rm = TRUE)), stringsAsFactors = FALSE)
names(tot) <- names(summ)
summ <- rbind(summ, tot)

overall <- data.frame(
  measure = c("reference rows", "pipeline rows", "reference sites",
              "sites that reached the sheet", "sites named anywhere by the model",
              "reference values", "values kept as a main result",
              "values present in Session 1", "reference rows matched",
              "of those, result level agrees", "of those, subsector agrees",
              "of those, target beneficiary agrees"),
  count = c(tot$reference_rows, tot$pipeline_rows, tot$reference_sites,
            tot$sites_in_the_sheet, tot$sites_named_anywhere, tot$reference_values,
            tot$values_kept, tot$values_read, tot$rows_matched,
            tot$level_agrees, tot$subsector_agrees, tot$beneficiary_agrees),
  share = c("", "", "",
            pct(tot$sites_in_the_sheet, tot$reference_sites),
            pct(tot$sites_named_anywhere, tot$reference_sites), "",
            pct(tot$values_kept, tot$reference_values),
            pct(tot$values_read, tot$reference_values),
            pct(tot$rows_matched, tot$reference_rows),
            pct(tot$level_agrees, tot$rows_matched),
            pct(tot$subsector_agrees, tot$rows_matched),
            pct(tot$beneficiary_agrees, tot$rows_matched)),
  stringsAsFactors = FALSE)

## ---- rows: the alignment, with each field marked ---------------------------
mark <- function(a, b) {
  a <- trimws(tolower(a)); b <- trimws(tolower(b))
  ifelse(!nzchar(a) & !nzchar(b), "both empty",
  ifelse(a == b, "agree",
  ifelse(!nzchar(b), "pipeline empty",
  ifelse(!nzchar(a), "reference empty", "differ"))))
}
rows <- al
rows$matched <- ifelse(toupper(rows$matched) == "TRUE", "matched", "no match")
rows$level <- mark(rows$gold_level, rows$pipe_level)
rows$subsector <- mark(rows$gold_subsector, rows$pipe_subsector)
rows$beneficiary <- mark(rows$gold_beneficiary, rows$pipe_beneficiary)
rows$value <- mark(rows$gold_value, rows$pipe_value)
rows <- rows[, c("project", "gold_row", "matched", "score", "gold_loc", "pipe_loc",
                 "gold_value", "pipe_value", "value", "gold_level", "pipe_level", "level",
                 "gold_subsector", "pipe_subsector", "subsector",
                 "gold_beneficiary", "pipe_beneficiary", "beneficiary",
                 "gold_result", "pipe_result")]
names(rows) <- c("document", "reference_row", "matched", "match_score",
                 "reference_site", "pipeline_site", "reference_value", "pipeline_value",
                 "value", "reference_level", "pipeline_level", "level",
                 "reference_subsector", "pipeline_subsector", "subsector",
                 "reference_beneficiary", "pipeline_beneficiary", "beneficiary",
                 "reference_result", "pipeline_result")
rows <- rows[order(rows$matched == "matched", rows$document, rows$reference_row), ]

## ---- sites -----------------------------------------------------------------
site_col <- if ("location_names" %in% names(ref)) "location_names" else "location"
sites <- do.call(rbind, lapply(split(ref, paste(ref$project_code, ref[[site_col]])), function(g) {
  data.frame(document = g$project_code[1], site = g[[site_col]][1],
             level = if ("location_level" %in% names(g)) g$location_level[1] else "",
             reference_rows = nrow(g),
             reference_values = sum(nzchar(g$result_value)),
             reference_depth = paste(sort(unique(g$evidence_depth)), collapse = "/"),
             pages = paste(unique(g$page[nzchar(g$page)]), collapse = "; "),
             stringsAsFactors = FALSE)
}))
alm <- al[toupper(al$matched) == "TRUE", ]
key <- paste(alm$project, alm$gold_loc)
sites$reached_the_sheet <- ifelse(paste(sites$document, substr(sites$site, 1, 40)) %in% key, "yes", "no")
sites <- sites[order(sites$reached_the_sheet, sites$document, sites$site), ]

## ---- values ----------------------------------------------------------------
vals <- ref[nzchar(ref$result_value), c("project_code", site_col, "result_value",
                                        "result_metric", "result_unit", "page")]
names(vals) <- c("document", "site", "reference_value", "metric", "unit", "page")
nv <- function(x) unique(na.omit(num(unlist(strsplit(x, "\\|\\|")))))
pipe_vals <- split(num(pipe$result_value), pipe$project_code)
s1_vals <- if (!is.null(s1)) split(num(s1$result_value), s1$project_code_hint) else NULL
vals$state <- vapply(seq_len(nrow(vals)), function(i) {
  d <- vals$document[i]; want <- nv(vals$reference_value[i])
  if (length(want) && any(want %in% (pipe_vals[[d]] %||% numeric(0)))) return("kept as a main result")
  if (!is.null(s1_vals) && length(want) && any(want %in% (s1_vals[[d]] %||% numeric(0))))
    return("read, not kept among the main results")
  "not read"
}, character(1))
vals <- vals[order(vals$state, vals$document), ]

## ---- write -----------------------------------------------------------------
wb <- createWorkbook()
hdr <- createStyle(textDecoration = "bold", fgFill = "#EEEEEE", border = "bottom")
warn <- createStyle(fgFill = "#FCE4E4"); okc <- createStyle(fgFill = "#E8F5E9")
put <- function(name, d, freeze = 1) {
  addWorksheet(wb, name); writeData(wb, name, d, headerStyle = hdr)
  freezePane(wb, name, firstActiveRow = freeze + 1)
  setColWidths(wb, name, seq_along(d), widths = "auto")
}
put("summary", overall); put("per document", summ); put("sites", sites)
put("rows", rows); put("values", vals)
put("reference", ref); put("pipeline", pipe)
for (cl in c("value", "level", "subsector", "beneficiary")) {
  j <- which(names(rows) == cl)
  bad <- which(rows[[cl]] %in% c("differ", "pipeline empty", "reference empty")) + 1
  good <- which(rows[[cl]] %in% c("agree", "both empty")) + 1
  if (length(bad))  addStyle(wb, "rows", warn, rows = bad,  cols = j, gridExpand = TRUE, stack = TRUE)
  if (length(good)) addStyle(wb, "rows", okc,  rows = good, cols = j, gridExpand = TRUE, stack = TRUE)
}
j <- which(names(sites) == "reached_the_sheet")
bad <- which(sites$reached_the_sheet == "no") + 1
if (length(bad)) addStyle(wb, "sites", warn, rows = bad, cols = j, gridExpand = TRUE, stack = TRUE)
j <- which(names(vals) == "state")
bad <- which(vals$state == "not read") + 1
if (length(bad)) addStyle(wb, "values", warn, rows = bad, cols = j, gridExpand = TRUE, stack = TRUE)

addWorksheet(wb, "about")
writeData(wb, "about", data.frame(item = c("title", "written", "score", "alignment",
  "reference", "pipeline", "session 1 rows"),
  value = c(TITLE, format(Sys.time(), "%Y-%m-%d %H:%M"), SCORE, ALIGN, REF, PIPE,
            if (nzchar(S1)) S1 else "not given"), stringsAsFactors = FALSE),
  headerStyle = hdr)
setColWidths(wb, "about", 1:2, widths = "auto")
saveWorkbook(wb, OUT, overwrite = TRUE)
cat("written:", OUT, "\n")
cat(sprintf("  %d reference rows, %d pipeline rows, %d sites, %d values\n",
            nrow(ref), nrow(pipe), nrow(sites), nrow(vals)))
