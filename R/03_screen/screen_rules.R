# screen_rules.R - deterministic checks on the screener's judgements.
#
# The 200-document review of 18 Sep 2026 found the model's misses cluster in
# ways code can catch without paying again:
#   1. "in scope" with no climate-risk quote: the intervention criterion was
#      not evidenced (irrigation, value chains or productivity alone were read
#      as adaptation). Verdict becomes "unsure", reason says why.
#   2. "in scope" where the model itself says the project is mitigation or
#      neither: out on intervention.
#   3. "in scope" for a programme evaluation covering several projects:
#      "unsure", it needs a focus project before extraction.
#   4. a reason that is a bare word ("sector"): the verdict is kept but the
#      row is listed for a re-ask, because a reviewer cannot use it.
#   5. documents of one project (same cover identifier in the census) with
#      conflicting verdicts: listed, so the fuller document can decide.
# The original verdict and reason are kept; ruled values sit beside them.
#
#   Rscript R/03_screen/screen_rules.R
#   -> review/scope_screen.csv gains verdict_ruled, rule_applied
#      review/scope_screen_reask.csv   rows to re-judge (bare reasons)
#      review/scope_screen_conflicts.csv projects whose documents disagree

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", ".."), mustWork = TRUE)
source(file.path(REPO, "R", "00_shared", "paths.R"))
source(file.path(REPO, "R", "00_shared", "doc_families.R"))

SCREEN <- file.path(REVIEW_DIR, "scope_screen.csv")
CENSUS <- file.path(REVIEW_DIR, "family_census.csv")
sc <- read.csv(SCREEN, stringsAsFactors = FALSE, colClasses = "character", encoding = "UTF-8")
sc[is.na(sc)] <- ""
n <- nrow(sc)
cat("judgements:", n, "\n")

# The year window is applied here from the model's own verdict when it was
# stored (verdict_model, screener v4 onward), so moving the window is a change
# of two numbers and a rerun of this script: no document is read again. Rows
# from earlier runs keep the verdict the screener wrote.
YEAR_MIN <- 2015; YEAR_MAX <- 2025
verdict <- sc$verdict
if ("verdict_model" %in% names(sc)) {
  has <- nzchar(sc$verdict_model)
  y <- suppressWarnings(as.integer(sc$publication_year))
  base <- ifelse(has, sc$verdict_model, sc$verdict)
  out_year <- has & !is.na(y) & (y < YEAR_MIN | y > YEAR_MAX)
  no_year  <- has & is.na(y) & base == "in scope"
  verdict <- ifelse(out_year, "out of scope", ifelse(no_year, "unsure", base))
}
rule <- rep("", n)
if ("verdict_model" %in% names(sc)) {
  rule[out_year] <- sprintf("timeframe: dated %s, outside %d-%d", sc$publication_year[out_year], YEAR_MIN, YEAR_MAX)
  rule[no_year]  <- "no year stated, so the timeframe cannot be checked"
}
set_rule <- function(i, v, why) { verdict[i] <<- v; rule[i] <<- why }

for (i in seq_len(n)) {
  if (verdict[i] != "in scope") next
  fam <- if (nzchar(sc$family[i])) sc$family[i] else "generic"
  info <- family_info(fam)
  if (sc$adaptation_or_mitigation[i] %in% c("mitigation", "neither")) {
    set_rule(i, "out of scope", "model says the project is not adaptation (adaptation_or_mitigation); out on intervention")
  } else if (nchar(trimws(sc$climate_risk_quote[i])) < 12) {
    set_rule(i, "unsure", "no climate risk quoted, so the intervention criterion is not evidenced")
  } else if (sc$covers_several_projects[i] == "yes" && (isTRUE(info$multi) || fam == "programme_evaluation")) {
    set_rule(i, "unsure", "covers several projects: needs a focus project before extraction")
  }
}
# 6. a person's decision wins over everything above. review/scope_screen_overrides.csv
#    holds one row per decided document: source, filename, verdict (in scope /
#    out of scope / unsure), note, by. This is the accepted / rejected loop
#    in the workflow diagram.
OVR <- file.path(REVIEW_DIR, "scope_screen_overrides.csv")
if (file.exists(OVR)) {
  ov <- read.csv(OVR, stringsAsFactors = FALSE, colClasses = "character", encoding = "UTF-8")
  ov <- ov[ov$verdict %in% c("in scope", "out of scope", "unsure"), ]
  key <- paste(sc$source, sc$filename)
  hit <- match(paste(ov$source, ov$filename), key)
  for (j in which(!is.na(hit))) {
    i <- hit[j]
    verdict[i] <- ov$verdict[j]
    rule[i] <- paste0("human (", ov$by[j], "): ", ov$note[j])
  }
  cat("overrides applied:", sum(!is.na(hit)), "of", nrow(ov), "
")
}
bare <- nchar(trimws(sc$reason)) < 25
sc$verdict_ruled <- verdict
sc$rule_applied  <- ifelse(bare & !nzchar(rule), "reason is a bare word: re-ask", ifelse(bare, paste(rule, "| reason is a bare word: re-ask"), rule))

## ---- 5. conflicting verdicts inside one project ------------------------------
conf <- data.frame()
if (file.exists(CENSUS)) {
  cen <- read.csv(CENSUS, stringsAsFactors = FALSE, colClasses = "character", encoding = "UTF-8")
  cen[is.na(cen)] <- ""
  key <- setNames(paste(cen$source, cen$filename), paste(cen$source, cen$filename))
  ids <- lapply(seq_len(nrow(cen)), function(i) {
    v <- unlist(lapply(c("wb_project", "afdb_code", "gef_id", "gcf_fp", "af_id"), function(cn) {
      x <- cen[[cn]][i]; if (nzchar(x)) paste0(cn, ":", strsplit(x, ";")[[1]]) else character(0)
    }))
    v
  })
  idmap <- split(rep(paste(cen$source, cen$filename), lengths(ids)), unlist(ids))
  vmap <- setNames(sc$verdict_ruled, paste(sc$source, sc$filename))
  rows <- list()
  for (k in names(idmap)) {
    docs <- unique(idmap[[k]]); docs <- docs[docs %in% names(vmap)]
    if (length(docs) < 2) next
    vs <- vmap[docs]
    if (length(unique(vs)) < 2) next
    rows[[length(rows) + 1]] <- data.frame(project_id = k, n_docs = length(docs),
      verdicts = paste(sprintf("%s [%s]", sub("^[a-z]+ ", "", docs), vs), collapse = " | "),
      stringsAsFactors = FALSE)
  }
  if (length(rows)) conf <- do.call(rbind, rows)
}

## ---- write ---------------------------------------------------------------------
write.csv(sc, SCREEN, row.names = FALSE, na = "", fileEncoding = "UTF-8")
reask <- sc[bare, c("source", "folder", "filename", "verdict", "reason", "family")]
write.csv(reask, file.path(REVIEW_DIR, "scope_screen_reask.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(conf, file.path(REVIEW_DIR, "scope_screen_conflicts.csv"), row.names = FALSE, fileEncoding = "UTF-8")
# the human queue: every unsure document with the model's reason and the rule
# that made it unsure, so a person can decide without opening the CSV
unsure <- sc[sc$verdict_ruled == "unsure", c("source", "folder", "filename", "family", "reason", "rule_applied", "doc_type", "publication_year")]
write.csv(unsure, file.path(REVIEW_DIR, "scope_screen_unsure.csv"), row.names = FALSE, fileEncoding = "UTF-8")
cat("unsure queue for a person:", nrow(unsure), "\n")

cat("\nverdicts before and after the rules:\n")
print(addmargins(table(before = sc$verdict, after = sc$verdict_ruled)))
cat("\nrules applied:\n"); print(table(sub(" \\|.*$", "", sc$rule_applied[nzchar(sc$rule_applied)])))
cat("\nrows to re-ask (bare reason):", nrow(reask), "\n")
cat("projects whose documents disagree:", nrow(conf), "\n")
if (nrow(conf)) print(head(conf, 12))
cat("\nwritten:", SCREEN, "(+ verdict_ruled, rule_applied)\n        scope_screen_reask.csv, scope_screen_conflicts.csv\n")
