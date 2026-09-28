# reference_comparison.R - one workbook that puts a reference extraction, the
# pipeline's extraction and the scorer's verdicts side by side.
#
# score_pilot.R writes a CSV of verdicts (project, field, gold, extracted,
# verdict, why). This turns that CSV, the reference it was scored against and
# the harmonised pipeline output into a workbook a person can read:
#   summary      overall agreement and one row per field
#   comparison   one row per check: reference, pipeline, verdict, why
#   reference    the reference extraction as written
#   pipeline     the pipeline's rows in template column order
#   about        which files, when
#
#   Rscript R/08_quality/reference_comparison.R --score=<score.csv> \
#       --reference=<reference.csv> --pipeline=<harmonized.csv> \
#       --out=<workbook.xlsx> [--title="Charity pilot"]

suppressPackageStartupMessages(library(openxlsx))
args <- commandArgs(trailingOnly = TRUE)
opt <- function(name, default = "") { v <- sub(paste0("^--", name, "="), "", grep(paste0("^--", name, "="), args, value = TRUE)); if (length(v)) v[1] else default }
SCORE <- opt("score"); REF <- opt("reference"); PIPE <- opt("pipeline"); OUT <- opt("out"); TITLE <- opt("title", "Reference comparison")
stopifnot(nzchar(SCORE), nzchar(REF), nzchar(PIPE), nzchar(OUT))
rd <- function(p) { d <- read.csv(p, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE, encoding = "UTF-8"); d[is.na(d)] <- ""; d }
sc <- rd(SCORE); ref <- rd(REF); pipe <- rd(PIPE)

ok <- sc$verdict %in% c("match", "both_empty")
overall <- data.frame(measure = c("checks", "agree (match or both empty)", "partial", "mismatch", "candidate", "agreement"),
  value = c(nrow(sc), sum(ok), sum(sc$verdict == "partial"), sum(sc$verdict == "mismatch"), sum(sc$verdict == "candidate"),
            sprintf("%.1f percent", 100 * sum(ok) / nrow(sc))), stringsAsFactors = FALSE)
per_field <- do.call(rbind, lapply(split(sc, sc$field), function(g) data.frame(field = g$field[1], checks = nrow(g),
  agree = sum(g$verdict %in% c("match", "both_empty")), partial = sum(g$verdict == "partial"), mismatch = sum(g$verdict == "mismatch"),
  agreement = sprintf("%.0f percent", 100 * mean(g$verdict %in% c("match", "both_empty"))), stringsAsFactors = FALSE)))
per_field <- per_field[order(per_field$agree / per_field$checks, per_field$field), ]
per_doc <- do.call(rbind, lapply(split(sc, sc$project), function(g) data.frame(document = g$project[1], checks = nrow(g),
  agree = sum(g$verdict %in% c("match", "both_empty")), mismatch = sum(g$verdict == "mismatch"),
  agreement = sprintf("%.0f percent", 100 * mean(g$verdict %in% c("match", "both_empty"))), stringsAsFactors = FALSE)))

cmp <- sc[, intersect(c("project", "field", "gold", "extracted", "verdict", "why"), names(sc))]
names(cmp)[names(cmp) == "gold"] <- "reference"; names(cmp)[names(cmp) == "extracted"] <- "pipeline"
cmp <- cmp[order(cmp$verdict != "mismatch", cmp$verdict != "partial", cmp$project, cmp$field), ]

key <- if ("project_code_hint" %in% names(pipe)) "project_code_hint" else "project_code"
tmpl <- c("project_code", "project_title", "project_id", "project_lead", "publication_year", "start_year", "closure_year", "project_scale",
  "location_count", "location_notes", "rationale_project", "target_beneficiary_project", "GESI_project", "result1", "result1_metric",
  "result1_unit", "result2", "result2_metric", "result2_unit", "result3", "result3_metric", "result3_unit", "result_notes", "budget_total",
  "disbursed", "currency", "funding_mechanism", "funding_mechanism_portion", "budget_notes", "funder", "implementors", "document_type",
  "resource_id", "evidence_depth", "reference_link_1", "reference_link_2", "reference_link_3")
pipe_out <- pipe[, c(key, intersect(tmpl, setdiff(names(pipe), key))), drop = FALSE]
names(pipe_out)[1] <- "project_code"

wb <- createWorkbook()
hdr <- createStyle(textDecoration = "bold", border = "bottom", fgFill = "#E8EEE8"); ttl <- createStyle(textDecoration = "bold", fontSize = 12)
put <- function(sheet, df, row, title = NULL, widths = NULL, filter = FALSE) {
  if (!is.null(title)) { writeData(wb, sheet, title, startRow = row); addStyle(wb, sheet, ttl, rows = row, cols = 1); row <- row + 1 }
  writeData(wb, sheet, df, startRow = row, headerStyle = hdr, withFilter = filter)
  if (!is.null(widths)) setColWidths(wb, sheet, cols = seq_along(widths), widths = widths)
  invisible(row + nrow(df) + 2)
}
addWorksheet(wb, "summary"); r <- put("summary", overall, 1, TITLE, c(30, 12, 10, 10, 12, 14))
r <- put("summary", per_field, r, "By field (weakest first)"); put("summary", per_doc, r, "By document")
addWorksheet(wb, "comparison"); put("comparison", cmp, 1, NULL, c(9, 26, 50, 50, 12, 70), filter = TRUE); freezePane(wb, "comparison", firstRow = TRUE)
mis <- cmp$verdict == "mismatch"; if (any(mis)) addStyle(wb, "comparison", createStyle(fgFill = "#F6E3E3"), rows = which(mis) + 1, cols = 1:ncol(cmp), gridExpand = TRUE)
addWorksheet(wb, "reference"); put("reference", ref, 1, NULL, pmin(50, pmax(10, nchar(names(ref)) + 4)), filter = TRUE); freezePane(wb, "reference", firstRow = TRUE)
addWorksheet(wb, "pipeline"); put("pipeline", pipe_out, 1, NULL, pmin(50, pmax(10, nchar(names(pipe_out)) + 4)), filter = TRUE); freezePane(wb, "pipeline", firstRow = TRUE)
addWorksheet(wb, "about")
put("about", data.frame(what = c("score", "reference", "pipeline", "generated", "how"),
  value = c(SCORE, REF, PIPE, format(Sys.time(), "%Y-%m-%d %H:%M"),
            "Rscript R/08_quality/reference_comparison.R --score= --reference= --pipeline= --out= [--title=]"), stringsAsFactors = FALSE), 1, NULL, c(12, 120))
saveWorkbook(wb, OUT, overwrite = TRUE)
cat("written:", OUT, "\n"); print(overall, row.names = FALSE); cat("\n"); print(per_field, row.names = FALSE)
