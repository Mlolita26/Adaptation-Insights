##############################################################################
# prompt_history.R - how the extraction prompts got to where they are.
#
# Two sheets, nothing else: a read me, and one row per prompt version saying
# what was going wrong, what changed, whether the fix went in the prompt or in
# code, and what it did to the score.
#
# The history is curated, not computed: it comes from the commit log and the
# score files, written down here so it survives. Add a row whenever a version
# number changes.
#
#   Rscript R/reporting/prompt_history.R
##############################################################################

suppressPackageStartupMessages({ library(openxlsx) })

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", ".."), mustWork = TRUE)
source(file.path(REPO, "R", "shared", "paths.R"))

H <- function(...) data.frame(..., stringsAsFactors = FALSE)

hist <- rbind(
H(version = "v0.2-qc1", script = "extract_general.R", date = "2026-09-08",
  sheet = "general",
  problem = "First extraction read against the gold standard by hand. The mistakes were systematic, not random: wrong years, report title used as project title, amounts in millions rather than full digits.",
  change  = "Rules written straight from the audit findings, one per observed mistake.",
  fixed_in = "prompt",
  effect  = "first measurable baseline"),

H(version = "s1-v0.5", script = "extract_verbatim.R", date = "2026-09-08",
  sheet = "general",
  problem = "Long documents were cut at a character limit, so facts in the middle were never seen. A project start year sat on page 191 of a 294 page evaluation. Short acronyms also matched the wrong organisation.",
  change  = "Section maps for World Bank ICRs and GEF evaluations: the document is cut to the sections that hold template fields, keeping the original page numbers so citations stay checkable. Survey annexes excluded. Name the organisation, never its department.",
  fixed_in = "prompt and code",
  effect  = "mid document facts recoverable"),

H(version = "s1-v0.6", script = "extract_verbatim.R", date = "2026-09-08",
  sheet = "general",
  problem = "Years came from approval or extension dates. Amounts were written as 1.71 million. Financing table row labels such as Borrower or Local Beneficiaries were being read as funders.",
  change  = "Take years from the stated implementation period. Amounts in full digits. Row labels are not organisations.",
  fixed_in = "prompt",
  effect  = "round 2: 78% field agreement"),

H(version = "s1-v0.7", script = "extract_verbatim.R", date = "2026-09-09",
  sheet = "general",
  problem = "Years still wrong on some projects. Co-implementing agencies named in the body were missed because the data sheet names only one. Figures from the predecessor programme were being pulled in. Account numbers such as TF-17015 were used as the report id.",
  change  = "An explicit implementation_period field with the years derived in R rather than asked of the model. Body co-implementors. Predecessor figures excluded. An account number is never an id.",
  fixed_in = "prompt and code",
  effect  = "round 5: 88% on the corrected gold"),

H(version = "s1-v0.8", script = "extract_verbatim.R", date = "2026-09-09",
  sheet = "general",
  problem = "Things that are not results were filling the three result slots: project durations, dates, numbers of meetings and reports, disbursement rates.",
  change  = "A results typology with worked examples of what counts, plus an explicit list of what never counts. Gates in code so a rejected value can never reach a headline slot.",
  fixed_in = "prompt and code",
  effect  = "result slots stop filling with admin counts"),

H(version = "s1-v0.9", script = "extract_verbatim.R", date = "2026-09-09",
  sheet = "general",
  problem = "Budget and disbursed were being confused, and French documents were read badly on finance. The report's own title was still sometimes taken as the project title.",
  change  = "Finance typology: financing plan rows, planned against spent, and the French terms for disbursement. Anti examples for identity fields.",
  fixed_in = "prompt",
  effect  = "finance fields stabilise"),

H(version = "s1-v1.0", script = "extract_verbatim.R", date = "2026-09-09",
  sheet = "general",
  problem = "Indicator tables scramble when a PDF is turned into text, so results framework annexes were unreadable exactly where the numbers live.",
  change  = "Those pages are attached to the results call as images as well as text, capped at ten pages.",
  fixed_in = "prompt and code",
  effect  = "results framework values become readable"),

H(version = "s1-v1.1", script = "extract_verbatim.R", date = "2026-09-09",
  sheet = "general",
  problem = "Team review of the output: titles in capitals, document codes inside titles, location count written as a phrase, gender field left empty rather than saying nothing was found, results with decimals, the word percentage instead of a sign.",
  change  = "Field rules written once in shared code and applied twice, at extraction and again at coding, so re-running an old extraction picks up rules written since.",
  fixed_in = "code",
  effect  = "title mismatches 4 to 1"),

H(version = "loc-v1.0", script = "extract_locations.R", date = "2026-09-09",
  sheet = "location",
  problem = "First location specific extraction. One row per location, intervention and result.",
  change  = "New script, same two session design.",
  fixed_in = "prompt",
  effect  = "44% of the gold locations, 27 of 60 rows"),

H(version = "loc-v1.1", script = "extract_locations.R", date = "2026-09-09",
  sheet = "location",
  problem = "The enumeration step found 228 locations but the row step kept only 74. Most of what was found was being thrown away.",
  change  = "The list of locations found is fed into the row prompt. Scorer given containment matching so a place named two ways is not counted as a miss.",
  fixed_in = "prompt and code",
  effect  = "the single biggest gain in coverage"),

H(version = "loc-v1.2", script = "extract_locations.R", date = "2026-09-09",
  sheet = "location",
  problem = "A verified list of errors from reading the ten documents three ways: our own read, the gold, and the pipeline.",
  change  = "Each error on the list addressed individually.",
  fixed_in = "prompt and code",
  effect  = "errors closed one by one"),

H(version = "loc-v1.3", script = "extract_locations.R", date = "2026-09-09",
  sheet = "location",
  problem = "We had banned workshop and training counts as results, which contradicted the template's own example unit, training workshops held. Real results were being discarded.",
  change  = "Activity deliverables are location level results. Rule corrected and the wrongly removed reference values restored.",
  fixed_in = "prompt and code",
  effect  = "82% of gold locations, 47 of 60 rows"),

H(version = "loc-v1.4", script = "extract_locations.R", date = "2026-09-09",
  sheet = "location",
  problem = "Beneficiary was often the ministry that delivered the work rather than the people who benefited. Rationale was reworded to fit the column instead of quoted. Coverage counts such as 20 pilot villages targeted, and rating scales, were being recorded as results.",
  change  = "Beneficiary must be the ultimate group and must be evidenced, with the document's own statement captured. Rationale must be the document's own words and is fact checked. One shared gate rejects coverage counts and ratings.",
  fixed_in = "prompt and code",
  effect  = "84% of gold locations, 50 of 60 rows"),

H(version = "s2-v0.3", script = "harmonize.R", date = "2026-09-08",
  sheet = "coding",
  problem = "The coding step could return a value that is not on the template's list.",
  change  = "Every value validated in code. Anything off the list becomes a candidate and goes to a review log instead of into the data.",
  fixed_in = "code",
  effect  = "no off list value can reach the sheet"),

H(version = "s2-v0.3 (rules v2)", script = "harmonize.R", date = "2026-09-14",
  sheet = "coding",
  problem = "The model had to choose an option even when the extract stated nothing. A results framework line naming nobody became a beneficiary.",
  change  = "The coding step may answer NOT STATED and leave the cell empty. The answer is recorded so a re-run does not pay to ask again.",
  fixed_in = "prompt and code",
  effect  = "32 cells correctly left empty on the gold set"),

H(version = "loc-s2-v1.0", script = "harmonize_locations.R", date = "2026-09-09",
  sheet = "coding",
  problem = "Location codes, subsector, beneficiary and result level all needed assigning from verbatim text.",
  change  = "Deterministic keyword pass first, then one batched call per field for what is left. Unmatched places become proposals with a suggested code.",
  fixed_in = "code",
  effect  = "codes never invented by the model")
)

names(hist) <- c("Version", "Script", "Date", "Sheet",
                 "What was going wrong", "What changed",
                 "Fixed in", "Measured effect")

readme <- data.frame(
  ` ` = c(
  "WHAT THIS IS",
  "How the extraction prompts got to where they are, one row per version.",
  "",
  "HOW TO READ IT",
  "Each row starts with something that was actually wrong in the output, usually",
  "found by comparing a run against the gold standard. The next columns say what",
  "we changed and whether the fix belonged in the prompt or in the code.",
  "",
  "WHY 'FIXED IN' MATTERS",
  "A fix in code is deterministic and free, and it applies to old runs when they",
  "are re-processed. A fix in the prompt costs a re-run of the documents. We move",
  "a rule into code whenever the answer is mechanical.",
  "",
  "THE THIRD KIND OF FIX",
  "Some disagreements could not be fixed either way, because the template itself",
  "does not say what the right answer is. Those became questions for the template",
  "owner rather than prompt changes. They are tracked in QC_Common_Mistakes.docx,",
  "not here.",
  "",
  "KEEPING IT CURRENT",
  "Add a row whenever a version number changes in one of the extraction scripts.",
  "Current versions: s1-v1.1 (general), loc-v1.4 (location), s2-v0.3 and",
  "loc-s2-v1.0 (coding).",
  "",
  "Rebuilt with: Rscript 05_Pipeline/R/reporting/prompt_history.R"),
  check.names = FALSE, stringsAsFactors = FALSE)

wb <- createWorkbook()
hdr <- createStyle(textDecoration = "bold", fgFill = "#DCE9F5", border = "bottom",
                   valign = "top")
wrap <- createStyle(wrapText = TRUE, valign = "top")
boldc <- createStyle(textDecoration = "bold", valign = "top")

addWorksheet(wb, "read me")
writeData(wb, "read me", readme)
setColWidths(wb, "read me", 1, 92)
addStyle(wb, "read me", boldc, rows = c(2, 5, 10, 15, 21), cols = 1, gridExpand = TRUE)

addWorksheet(wb, "prompt history")
writeData(wb, "prompt history", hist, headerStyle = hdr, withFilter = TRUE)
setColWidths(wb, "prompt history", 1:8, c(18, 22, 12, 10, 62, 62, 16, 30))
addStyle(wb, "prompt history", wrap, rows = 2:(nrow(hist) + 1), cols = 1:8,
         gridExpand = TRUE)
addStyle(wb, "prompt history", boldc, rows = 2:(nrow(hist) + 1), cols = 1,
         gridExpand = TRUE)
freezePane(wb, "prompt history", firstActiveRow = 2, firstActiveCol = 2)
for (r in 2:(nrow(hist) + 1)) setRowHeights(wb, "prompt history", r, 62)

f <- file.path(RESULTS_DIR, "prompt_history.xlsx")
writable <- function(p) {
  if (!file.exists(p)) return(TRUE)
  con <- suppressWarnings(try(file(p, "ab"), silent = TRUE))
  if (inherits(con, "try-error")) return(FALSE)
  close(con); TRUE
}
if (!writable(f)) f <- sub("[.]xlsx$", format(Sys.time(), "_%Y%m%d_%H%M.xlsx"), f)
saveWorkbook(wb, f, overwrite = TRUE)
cat("written:", f, "\n")
cat("  versions recorded:", nrow(hist), "\n")
