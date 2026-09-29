# Compare the three headline results of two Session 1 runs, document by
# document, against a reference results file (one row per reference result
# with project_code, value, metric, unit as the scorer reads it).
#
#   Rscript R/08_quality/compare_results_slots.R --old=<session1.csv> --new=<session1.csv> \
#           --reference=<gold_v1_results.csv> [--out=<csv>]
#
# Prints, per document, the old and new slots with a mark when a slot value is
# one of the reference values, and a summary: how many of the three slots hit
# the reference in each run, and how many documents have a people count first.
# Written for the headline results rule of 28 Sep 2026 (results_rank.R).

args <- commandArgs(trailingOnly = TRUE)
opt <- function(k, default = "") { v <- sub(paste0("^--", k, "="), "", grep(paste0("^--", k, "="), args, value = TRUE)); if (length(v)) v[1] else default }
old_f <- opt("old"); new_f <- opt("new"); ref_f <- opt("reference"); out_f <- opt("out")
stopifnot(nzchar(old_f), nzchar(new_f), nzchar(ref_f))
rd <- function(f) { d <- read.csv(f, stringsAsFactors = FALSE, check.names = FALSE, colClasses = "character", encoding = "UTF-8"); d[is.na(d)] <- ""; d }
old <- rd(old_f); new <- rd(new_f); ref <- rd(ref_f)
code_col <- function(d) if ("project_code" %in% names(d)) "project_code" else "project_code_hint"
num <- function(x) { x <- gsub("[^0-9.]", "", x); suppressWarnings(as.numeric(x)) }
ref_vals <- split(num(ref$value), ref$project_code)
val_col <- function(d) if ("value" %in% names(d)) "value" else names(d)[grepl("^result$|^value$", names(d))][1]
if (!"value" %in% names(ref)) stop("reference file needs a 'value' column")
hit <- function(v, pc) {
  rv <- ref_vals[[pc]]; rv <- rv[!is.na(rv)]
  if (is.na(v) || !length(rv)) return(FALSE)
  isTRUE(any(abs(rv - v) < 1e-6 | (rv > 0 & abs(rv - v) / rv < 0.005)))
}
people_re <- "beneficiar|household|farmer|people|persons|individuals|women|youth|jobs|trainee|participants|members|residents|families|producers|users"
rows <- list(); cat(sprintf("%-6s %-4s %-3s %-48s %s\n", "doc", "run", "hit", "slot value and metric", ""))
summ <- list(old = c(hits = 0, slots = 0, people_first = 0), new = c(hits = 0, slots = 0, people_first = 0))
codes <- union(old[[code_col(old)]], new[[code_col(new)]])
for (pc in codes) {
  for (run in c("old", "new")) {
    d <- if (run == "old") old else new; cc <- code_col(d); r <- d[d[[cc]] == pc, , drop = FALSE]
    if (!nrow(r)) next
    for (i in 1:3) {
      v <- r[[paste0("result", i)]][1]; m <- r[[paste0("result", i, "_metric_stated")]][1]; u <- r[[paste0("result", i, "_unit_stated")]][1]
      if (!nzchar(v)) next
      h <- hit(num(v), pc)
      summ[[run]]["slots"] <- summ[[run]]["slots"] + 1; summ[[run]]["hits"] <- summ[[run]]["hits"] + h
      if (i == 1 && grepl(people_re, tolower(paste(m, u)))) summ[[run]]["people_first"] <- summ[[run]]["people_first"] + 1
      cat(sprintf("%-6s %-4s %-3s %s %s (%s)\n", pc, run, if (h) "yes" else ".", v, substr(m, 1, 60), u))
      rows[[length(rows) + 1]] <- data.frame(project_code = pc, run = run, slot = i, value = v, metric = m, unit = u, hits_reference = h, stringsAsFactors = FALSE)
    }
  }
  cat("\n")
}
cat(sprintf("\nOLD run: %d of %d slots are reference values; people count first in %d documents\n", summ$old["hits"], summ$old["slots"], summ$old["people_first"]))
cat(sprintf("NEW run: %d of %d slots are reference values; people count first in %d documents\n", summ$new["hits"], summ$new["slots"], summ$new["people_first"]))
if (nzchar(out_f) && length(rows)) { write.csv(do.call(rbind, rows), out_f, row.names = FALSE); cat("written:", out_f, "\n") }
