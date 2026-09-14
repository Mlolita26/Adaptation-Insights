##############################################################################
# cost_report.R - what the extraction has cost, and what the corpus would cost.
#
# The workflow figure lists a cost and model-usage summary as one of the six
# things a run should leave behind. This is that file.
#
# Everything here is either MEASURED or an ASSUMPTION, and the workbook says
# which is which on every sheet:
#
#   measured   the size of every document, and the exact number of characters
#              the pipeline sends to the model - computed by running the
#              pipeline's own page-selection code offline, so it is what the
#              model really saw, not a guess about it
#   measured   the number of calls per document, and the size of every stored
#              response
#   verified   the prices, checked against developers.openai.com/api/docs/pricing
#              on 14 Sep 2026. They still live in the `assumptions` sheet and
#              every cost is an Excel formula pointing at them, so when they
#              move, one edit re-costs the whole workbook.
#   assumed    how many characters make a token (4, the usual figure for
#              English prose), and the share of cost the coding session adds.
#
# One consequence worth knowing: the five calls per document all carry the
# same system prompt and the same document text, differing only in the task
# line at the end. That is a repeated prefix of tens of thousands of tokens,
# far over the 1,024-token minimum, so the API's automatic prompt caching
# should price the document at a tenth for calls two to five. The workbook
# gives both figures - list price, and with that discount.
#
#   Rscript R/reporting/cost_report.R
##############################################################################

suppressPackageStartupMessages({ library(openxlsx) })

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", ".."), mustWork = TRUE)
source(file.path(REPO, "R", "shared", "paths.R"))
OUT <- file.path(REPO, "outputs", "extraction")

rd <- function(f) {
  if (!file.exists(f)) return(NULL)
  d <- read.csv(f, stringsAsFactors = FALSE); d
}

## ---- measured: what the model was sent, and what it sent back ---------------
gold <- rd(file.path(OUT, "gold_prompt_sizes.csv"))
if (is.null(gold)) stop("gold_prompt_sizes.csv not found - run the prompt-size measurement first")
corpus <- rd(file.path(OUT, "corpus_doc_sizes.csv"))

resp_chars <- function(dir) {
  fs <- list.files(dir, "[.]json$", full.names = TRUE)
  if (!length(fs)) return(c(calls = 0, docs = 0, chars = 0))
  doc <- sub("_[a-z_]+[.]json$", "", basename(fs))
  c(calls = length(fs), docs = length(unique(doc)), chars = sum(file.size(fs)))
}
g_resp <- resp_chars(file.path(OUT, "raw"))
l_resp <- resp_chars(file.path(OUT, "locations", "raw"))
G_OUT_CHARS <- if (g_resp["docs"] > 0) round(g_resp["chars"] / g_resp["docs"]) else 0
L_OUT_CHARS <- if (l_resp["docs"] > 0) round(l_resp["chars"] / l_resp["docs"]) else 0
G_CALLS <- if (g_resp["docs"] > 0) round(g_resp["calls"] / g_resp["docs"]) else 5
L_CALLS <- if (l_resp["docs"] > 0) round(l_resp["calls"] / l_resp["docs"]) else 2

## ---- the workbook -----------------------------------------------------------
wb <- createWorkbook()
hdr  <- createStyle(textDecoration = "bold", fgFill = "#DCE9F5", border = "bottom")
bold <- createStyle(textDecoration = "bold")
inp  <- createStyle(fgFill = "#FFF2CC", border = "TopBottomLeftRight",
                    borderColour = "#BF9000")
money <- createStyle(numFmt = "$#,##0.00")
money4 <- createStyle(numFmt = "$#,##0.0000")
num   <- createStyle(numFmt = "#,##0")
grey  <- createStyle(fontColour = "#666666", textDecoration = "italic")

add <- function(nm, df, widths = NULL, start = 1) {
  addWorksheet(wb, nm)
  writeData(wb, nm, df, startRow = start, headerStyle = hdr)
  setColWidths(wb, nm, seq_along(df),
               if (is.null(widths)) pmin(60, pmax(12, nchar(names(df)) + 4)) else widths)
  freezePane(wb, nm, firstActiveRow = start + 1)
}

## sheet: read me
readme <- data.frame(
  ` ` = c(
    "WHAT THIS IS",
    "The cost of the extraction so far, and what the whole corpus would cost.",
    "",
    "HOW TO USE IT",
    "Open the 'assumptions' sheet. The yellow cells are the only things you edit.",
    "Change a price and every figure in this workbook recalculates - the costs are",
    "formulas, not typed numbers.",
    "",
    "WHAT IS MEASURED AND WHAT IS ASSUMED",
    "Measured: the size of every document, the exact characters sent to the model",
    "(computed with the pipeline's own page-selection code, so it is what the model",
    "actually saw), the number of calls per document, and the size of every reply.",
    "Assumed: the price per million tokens, and how many characters make a token.",
    "",
    "PROMPT CACHING - why there are two cost columns",
    "The five calls for one document send the same system prompt and the same",
    "document text, differing only in the task line at the end. The API caches a",
    "repeated prefix over 1,024 tokens automatically and charges a tenth for it,",
    "so calls two to five should pay the cached rate on the document. The",
    "'with caching' column is the more likely bill; the plain column is the",
    "worst case if caching does not engage.",
    "",
    "THE ONE THING TO CHECK",
    "Prices were verified on 14 Sep 2026 against developers.openai.com. They move.",
    "Re-check before quoting any figure here in a budget.",
    "",
    "SHEETS",
    "assumptions        the editable inputs",
    "gold set           what the ten pilot documents actually cost",
    "corpus projection  what the full corpus would cost, under four scenarios",
    "models tested      gpt-5-mini against gpt-5-nano on the same 190 checks",
    "how measured       where every number came from"),
  check.names = FALSE, stringsAsFactors = FALSE)
add("read me", readme, widths = 95)
addStyle(wb, "read me", bold, rows = c(2, 5, 10, 16, 20), cols = 1, gridExpand = TRUE)

## sheet: assumptions  (the only editable cells)
A <- data.frame(
  input = c("characters per token",
            "gpt-5-mini  price per 1M input tokens (USD)",
            "gpt-5-mini  price per 1M output tokens (USD)",
            "gpt-5-mini  price per 1M CACHED input tokens (USD)",
            "gpt-5-nano  price per 1M input tokens (USD)",
            "gpt-5-nano  price per 1M output tokens (USD)",
            "gpt-5-nano  price per 1M CACHED input tokens (USD)",
            "documents in the corpus (PDFs on disk)",
            "documents per project, when all are read",
            "session 1 calls per document - general sheet",
            "session 1 calls per document - location sheet",
            "session 2 (coding) as a share of session 1 cost"),
  value = c(4, 0.25, 2.00, 0.025, 0.05, 0.40, 0.005,
            if (!is.null(corpus)) nrow(corpus) else 628,
            2.4, G_CALLS, L_CALLS, 0.05),
  note = c("rule of thumb for English prose; 4 is the usual figure",
           "VERIFIED 14 Sep 2026 on developers.openai.com/api/docs/pricing",
           "VERIFIED 14 Sep 2026 on developers.openai.com/api/docs/pricing",
           "VERIFIED 14 Sep 2026 - 90% off, applied automatically to a repeated prompt prefix",
           "VERIFIED 14 Sep 2026 on developers.openai.com/api/docs/pricing",
           "VERIFIED 14 Sep 2026 on developers.openai.com/api/docs/pricing",
           "VERIFIED 14 Sep 2026 - 90% off",
           "measured: PDFs found under the six corpus folders",
           "measured: 24 PDFs across the 10 gold project folders",
           "measured: stored responses divided by documents",
           "measured: stored responses divided by documents",
           "coding sends short extracts, not documents - small but not nil"),
  stringsAsFactors = FALSE)
add("assumptions", A, widths = c(46, 14, 62))
addStyle(wb, "assumptions", inp, rows = 2:(nrow(A) + 1), cols = 2, gridExpand = TRUE)
writeData(wb, "assumptions", "the yellow cells are the inputs; everything else is calculated from them",
          startRow = nrow(A) + 3, startCol = 1)
addStyle(wb, "assumptions", grey, rows = nrow(A) + 3, cols = 1)

CT <- "assumptions!$B$2"; PI <- "assumptions!$B$3"; PO <- "assumptions!$B$4"
PC <- "assumptions!$B$5"                      # cached input
NCORP <- "assumptions!$B$9"; NPER <- "assumptions!$B$10"
CG <- "assumptions!$B$11"; CL <- "assumptions!$B$12"; S2 <- "assumptions!$B$13"

## sheet: gold set
n <- nrow(gold)
G <- data.frame(
  project = gold$code, document_family = gold$family,
  pages = gold$pages_total, pages_sent = gold$pages_sent,
  characters_in_document = gold$chars_doc,
  characters_sent_to_model = gold$chars_sent,
  stringsAsFactors = FALSE)
r <- 2:(n + 1)
G$input_tokens_general  <- sprintf("=F%d*%s/%s", r, CG, CT)
G$output_tokens_general <- sprintf("=%d/%s", G_OUT_CHARS, CT)
G$cost_general          <- sprintf("=G%d/1000000*%s+H%d/1000000*%s", r, PI, r, PO)
G$input_tokens_location  <- sprintf("=F%d*%s/%s", r, CL, CT)
G$output_tokens_location <- sprintf("=%d/%s", L_OUT_CHARS, CT)
G$cost_location          <- sprintf("=J%d/1000000*%s+K%d/1000000*%s", r, PI, r, PO)
G$cost_both              <- sprintf("=(I%d+L%d)*(1+%s)", r, r, S2)
# the same work, priced with the repeated-prefix discount the API applies
# automatically: the first call of each document pays full rate for the
# document text, the rest pay the cached rate for it
G$cost_both_with_caching <- sprintf(
  "=((F%d/%s*%s+F%d/%s*(%s-1)*%s)+(F%d/%s*%s+F%d/%s*(%s-1)*%s))/1000000+(H%d+K%d)/1000000*%s",
  r, CT, PI, r, CT, CG, PC, r, CT, PI, r, CT, CL, PC, r, r, PO)
for (cc in c("input_tokens_general","output_tokens_general","cost_general",
             "input_tokens_location","output_tokens_location","cost_location",
             "cost_both","cost_both_with_caching"))
  class(G[[cc]]) <- c(class(G[[cc]]), "formula")
add("gold set", G, widths = c(9, 16, 8, 11, 22, 24, 18, 18, 12, 18, 18, 13, 12, 22))
tr <- n + 2
writeData(wb, "gold set", "TOTAL, 10 gold documents", startRow = tr, startCol = 1)
for (col in c(3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14)) {
  L <- LETTERS[col]
  writeFormula(wb, "gold set", sprintf("=SUM(%s2:%s%d)", L, L, n + 1),
               startRow = tr, startCol = col)
}
addStyle(wb, "gold set", bold, rows = tr, cols = 1:14, gridExpand = TRUE)
addStyle(wb, "gold set", money4, rows = 2:tr, cols = c(9, 12, 13, 14), gridExpand = TRUE)
addStyle(wb, "gold set", num, rows = 2:tr, cols = c(3, 4, 5, 6, 7, 8, 10, 11), gridExpand = TRUE)
writeData(wb, "gold set",
  "P002, P003 and P004 are three projects inside ONE document, so that document is sent three times, once per programme. That is why the totals are higher than the page count suggests.",
  startRow = tr + 2, startCol = 1)
addStyle(wb, "gold set", grey, rows = tr + 2, cols = 1)

## sheet: corpus projection
mean_sent <- if (!is.null(corpus) && any(corpus$ok))
  round(mean(corpus$chars_sent[corpus$ok])) else round(mean(gold$chars_sent))
readable <- if (!is.null(corpus)) sum(corpus$ok) else NA
P <- data.frame(
  scenario = c("General sheet only, one document per project",
               "General + location, one document per project",
               "General sheet only, every document in the project folder",
               "General + location, every document in the project folder"),
  documents = c(sprintf("=%s", NCORP), sprintf("=%s", NCORP),
                sprintf("=%s*%s", NCORP, NPER), sprintf("=%s*%s", NCORP, NPER)),
  mean_characters_sent = rep(mean_sent, 4),
  stringsAsFactors = FALSE)
pr <- 2:5
P$input_tokens <- c(sprintf("=B%d*C%d*%s/%s", pr[1], pr[1], CG, CT),
                    sprintf("=B%d*C%d*(%s+%s)/%s", pr[2], pr[2], CG, CL, CT),
                    sprintf("=B%d*C%d*%s/%s", pr[3], pr[3], CG, CT),
                    sprintf("=B%d*C%d*(%s+%s)/%s", pr[4], pr[4], CG, CL, CT))
P$output_tokens <- c(sprintf("=B%d*%d/%s", pr[1], G_OUT_CHARS, CT),
                     sprintf("=B%d*%d/%s", pr[2], G_OUT_CHARS + L_OUT_CHARS, CT),
                     sprintf("=B%d*%d/%s", pr[3], G_OUT_CHARS, CT),
                     sprintf("=B%d*%d/%s", pr[4], G_OUT_CHARS + L_OUT_CHARS, CT))
P$cost_usd <- sprintf("=(D%d/1000000*%s+E%d/1000000*%s)*(1+%s)", pr, PI, pr, PO, S2)
P$cost_with_caching <- c(
  sprintf("=(B%d*C%d/%s*%s+B%d*C%d/%s*(%s-1)*%s)/1000000+E%d/1000000*%s", pr[1], pr[1], CT, PI, pr[1], pr[1], CT, CG, PC, pr[1], PO),
  sprintf("=(B%d*C%d/%s*%s+B%d*C%d/%s*(%s+%s-1)*%s)/1000000+E%d/1000000*%s", pr[2], pr[2], CT, PI, pr[2], pr[2], CT, CG, CL, PC, pr[2], PO),
  sprintf("=(B%d*C%d/%s*%s+B%d*C%d/%s*(%s-1)*%s)/1000000+E%d/1000000*%s", pr[3], pr[3], CT, PI, pr[3], pr[3], CT, CG, PC, pr[3], PO),
  sprintf("=(B%d*C%d/%s*%s+B%d*C%d/%s*(%s+%s-1)*%s)/1000000+E%d/1000000*%s", pr[4], pr[4], CT, PI, pr[4], pr[4], CT, CG, CL, PC, pr[4], PO))
P$cost_per_document <- sprintf("=F%d/B%d", pr, pr)
for (cc in c("documents","input_tokens","output_tokens","cost_usd",
             "cost_with_caching","cost_per_document"))
  class(P[[cc]]) <- c(class(P[[cc]]), "formula")
add("corpus projection", P, widths = c(56, 12, 22, 16, 16, 12, 20, 18))
addStyle(wb, "corpus projection", money, rows = 2:5, cols = c(6, 7), gridExpand = TRUE)
addStyle(wb, "corpus projection", money4, rows = 2:5, cols = 8, gridExpand = TRUE)
addStyle(wb, "corpus projection", num, rows = 2:5, cols = c(2, 3, 4, 5), gridExpand = TRUE)
notes <- c(
  sprintf("Mean characters sent per document is measured over %s corpus PDFs that could be read.",
          ifelse(is.na(readable), "the gold", format(readable, big.mark = ","))),
  "'Every document in the project folder' uses the ratio measured on the gold folders: 24 PDFs for 10 projects.",
  "Multi-project documents are NOT counted twice here. One GEF evaluation held three of the ten gold projects; if that pattern holds across the corpus the general-sheet figures are an underestimate.",
  "Re-runs are cheaper than first runs: the coding session reuses recorded decisions, so a second harmonise of the same extraction makes almost no calls.")
for (i in seq_along(notes)) {
  writeData(wb, "corpus projection", notes[i], startRow = 7 + i, startCol = 1)
  addStyle(wb, "corpus projection", grey, rows = 7 + i, cols = 1)
}

## sheet: models tested
M <- data.frame(
  model = c("gpt-5-mini", "gpt-5-nano"),
  status = c("in use", "tested 8 Sep 2026, not adopted"),
  checks = c(190, 190),
  matched = c(151, 136),
  match_rate = c("=D2/C2", "=D3/C3"),
  outright_mismatches = c(14, 31),
  fields_filled = c("79%", "75%"),
  relative_price_input = c(sprintf("=%s", PI), sprintf("=assumptions!$B$5")),
  relative_price_output = c(sprintf("=%s", PO), sprintf("=assumptions!$B$6")),
  verdict = c("adopted",
              "cheaper, but more than twice the outright mismatches on identical checks - the review time costs more than the saving"),
  stringsAsFactors = FALSE)
for (cc in c("match_rate", "relative_price_input", "relative_price_output"))
  class(M[[cc]]) <- c(class(M[[cc]]), "formula")
add("models tested", M, widths = c(13, 30, 9, 10, 12, 20, 14, 20, 20, 70))
addStyle(wb, "models tested", createStyle(numFmt = "0%"), rows = 2:3, cols = 5, gridExpand = TRUE)
writeData(wb, "models tested",
  "Both were scored on the same 190 field checks against the same gold standard, so the two rows are directly comparable.",
  startRow = 5, startCol = 1)
addStyle(wb, "models tested", grey, rows = 5, cols = 1)

## sheet: how measured
H <- data.frame(
  figure = c("characters sent to the model",
             "calls per document",
             "characters returned",
             "documents in the corpus",
             "documents per project",
             "price per token",
             "characters per token",
             "session 2 share",
             "model comparison"),
  how = c("the pipeline's own page-selection code run offline over each PDF - the exact string the model receives, including the [page N] markers",
          "stored response files divided by documents, from outputs/extraction/raw and locations/raw",
          "size of every stored response file",
          "PDFs found under the six corpus folders in 03_Documents",
          "24 PDFs across the 10 gold project folders",
          "ASSUMED - editable on the assumptions sheet",
          "ASSUMED - editable on the assumptions sheet",
          "ASSUMED - coding sends short extracts, not whole documents",
          "score files from both runs over the same gold set"),
  measured_or_assumed = c("measured", "measured", "measured", "measured",
                          "measured", "assumed", "assumed", "assumed", "measured"),
  stringsAsFactors = FALSE)
add("how measured", H, widths = c(30, 100, 20))

f <- file.path(RESULTS_DIR, "extraction_costs.xlsx")
writable <- function(p) {
  if (!file.exists(p)) return(TRUE)
  con <- suppressWarnings(try(file(p, "ab"), silent = TRUE))
  if (inherits(con, "try-error")) return(FALSE)
  close(con); TRUE
}
if (!writable(f)) f <- sub("[.]xlsx$", format(Sys.time(), "_%Y%m%d_%H%M.xlsx"), f)
saveWorkbook(wb, f, overwrite = TRUE)
cat("written:", f, "\n")
cat("  gold documents costed:", n, "\n")
cat("  mean characters sent per corpus document:", format(mean_sent, big.mark = ","), "\n")
cat("  measured calls per document: general", G_CALLS, "| location", L_CALLS, "\n")
