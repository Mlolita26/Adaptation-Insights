##############################################################################
# audit_proposed_actors.R - check every proposed new actor before a human
# spends time on it, the way audit_proposed_locations.R does for places.
#
# The pipeline proposes an actor whenever the matcher cannot place a name in
# the registry. Three kinds of proposal are not worth a new code, and the
# team should not have to spot them by eye:
#
#   NEAR-DUPLICATE  the registry already holds it under a slightly different
#                   name ("Centre"/"Center", an inline acronym, a missing
#                   space). The matcher folds these now, so a survivor here
#                   is a spelling the folding does not cover yet.
#   NOT AN ORGANISATION  a project coordination unit, task force or steering
#                   committee is part of a project, not a body that outlives
#                   it. The registry is a list of organisations.
#   FINANCING ARM   IDA is the World Bank's concessional window, ADF is the
#                   African Development Fund. Whether those get their own
#                   code or fold into the parent is the team's call, but it
#                   is a different question from "is this a new organisation".
#
#   Rscript R/reporting/audit_proposed_actors.R
##############################################################################

suppressPackageStartupMessages({ library(openxlsx) })

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", ".."), mustWork = TRUE)
source(file.path(REPO, "R", "shared", "paths.R"))

rd <- function(f) {
  d <- read.csv(f, stringsAsFactors = FALSE, colClasses = "character")
  d[is.na(d)] <- ""; d
}

# the harmoniser writes its proposals beside the run; the team's copy lives
# in review/. Audit whichever is newer, so this works either way round.
cands <- c(file.path(REVIEW_DIR, "proposed_new_actors.csv"),
           file.path(REPO, "outputs", "extraction", "proposed_new_actors.csv"))
cands <- cands[file.exists(cands)]
if (!length(cands)) { cat("no proposed_new_actors.csv - nothing to audit\n"); quit(save = "no") }
PROP <- cands[which.max(file.mtime(cands))]
cat("auditing:", PROP, "\n")
p <- rd(PROP)
if (!nrow(p)) { cat("proposal file is empty\n"); quit(save = "no") }

A <- read.xlsx(TEMPLATE_XLSX, sheet = "actor_codes"); A[is.na(A)] <- ""
names(A)[1:4] <- c("name", "acro", "code", "type")
A <- A[nzchar(A$code), ]

fold <- function(x) {
  s <- tolower(as.character(x))
  s <- gsub("[(][^)]*[)]", " ", s)
  s <- gsub("centre", "center", s); s <- gsub("organisation", "organization", s)
  s <- gsub("programme", "program", s); s <- gsub("labour", "labor", s)
  s <- gsub("\\b(the|of|for|and)\\b", " ", s)
  trimws(gsub(" +", " ", gsub("[^a-z0-9 ]", " ", s)))
}
A$f <- fold(A$name); A$fa <- fold(A$acro)

UNIT_RX <- paste0("\\b(project|programme|program) (coordination|implementation|",
  "management) unit\\b|\\b(pcu|piu|pmu)\\b|\\btask ?force\\b|",
  "\\bsteering committee\\b|\\bworking group\\b|\\bfocal points?\\b")
ARM_RX <- paste0("\\b(fund|facility|window|association|trust)\\b")

verdict <- character(nrow(p)); note <- character(nrow(p))
for (i in seq_len(nrow(p))) {
  nm <- p$actor_name[i]; f <- fold(nm)
  low <- tolower(nm)
  if (!nzchar(f)) { verdict[i] <- "EMPTY - drop"; next }

  hit <- which(A$f == f | (nzchar(A$fa) & A$fa == f) |
               gsub(" ", "", A$f, fixed = TRUE) == gsub(" ", "", f, fixed = TRUE))
  if (!length(hit)) {
    d <- adist(f, A$f, ignore.case = TRUE)[1, ]
    k <- which.min(d)
    if (1 - d[k] / max(nchar(f), nchar(A$f[k])) >= 0.90) hit <- k
  }
  if (length(hit)) {
    verdict[i] <- "NEAR-DUPLICATE - use the existing code"
    note[i] <- paste0(A$code[hit[1]], " = ", A$name[hit[1]])
    next
  }
  if (grepl(UNIT_RX, low)) { verdict[i] <- "NOT AN ORGANISATION - part of a project"; next }
  if (grepl(ARM_RX, low)) {
    d <- adist(f, A$f, ignore.case = TRUE)[1, ]
    k <- which.min(d)
    sim <- 1 - d[k] / max(nchar(f), nchar(A$f[k]))
    verdict[i] <- "FINANCING ARM - own code, or fold into the parent?"
    if (sim >= 0.70) note[i] <- paste0("closest parent: ", A$code[k], " = ", A$name[k])
    next
  }
  verdict[i] <- "NEW - needs a code"
}

out <- cbind(p, audit_verdict = verdict, audit_note = note)
out <- out[order(out$audit_verdict == "NEW - needs a code", out$actor_name), ]
cat("verdicts over", nrow(p), "proposals:\n")
print(table(verdict))

f_out <- file.path(REVIEW_DIR, "proposed_new_actors_AUDIT.xlsx")
wb <- createWorkbook(); addWorksheet(wb, "proposed_actors")
writeData(wb, "proposed_actors", out, withFilter = TRUE,
          headerStyle = createStyle(textDecoration = "bold", fgFill = "#EEEEEE"))
freezePane(wb, "proposed_actors", firstRow = TRUE)
setColWidths(wb, "proposed_actors", cols = seq_along(out),
             widths = pmin(52, pmax(12, nchar(names(out)) + 4)))
saveWorkbook(wb, f_out, overwrite = TRUE)
cat("\nwritten:", f_out, "\n")
