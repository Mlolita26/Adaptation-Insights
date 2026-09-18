# Family module: programme, portfolio and thematic evaluations that cover
# several projects by design (GEF Independent Evaluation Office, IDEV
# corporate and cluster evaluations, CIF programme evaluations). Extracted
# only with a focus project named in the manifest; the focus line is injected
# into every prompt by extract_verbatim.R. Evidence: Document_Families.docx, 3.9.

MODULE <- list(
  id = "programme_evaluation", label = "Programme, portfolio or thematic evaluation covering several projects",
  long_doc_pages = 100,

  # Long reports: the executive summary and programme tables at the front,
  # the annex with per-programme benefits, and every page naming the focus
  # project (its acronym, its ID or its name).
  keep_pages = function(pages, focus) {
    n <- length(pages); low <- tolower(pages); keep <- rep(FALSE, n)
    keep[seq_len(min(30, n))] <- TRUE
    mark <- function(re, span = 0) for (h in grep(re, low)) keep[h:min(n, h + span)] <<- TRUE
    mark("annex 15|global environmental benefits|portfolio overview|case stud", 8)
    if (nzchar(focus)) {
      acro <- regmatches(focus, regexpr("\\(([A-Z]{2,6})\\)", focus))
      acro <- tolower(gsub("[()]", "", acro))
      gid  <- regmatches(focus, regexpr("[0-9]{4}", focus))
      phrase <- tolower(trimws(sub("^the\\s+", "", sub("[(,].*$", "", tolower(focus)))))
      pats <- Filter(nzchar, c(if (length(acro)) paste0("\\b", acro, "\\b"),
                               if (length(gid)) gid, if (nchar(phrase) > 8) phrase))
      if (length(pats)) keep[Reduce(`|`, lapply(pats, function(p) grepl(p, low)))] <- TRUE
    }
    keep
  },

  rf = list(
    patterns = paste0("results framework|logical framework|logframe|core indicator|",
                      "global environmental benefits|portfolio"),
    prefer = "last",
    annex_start = "annex\\s*[0-9ivx]*[.:]?\\s*(results framework|logical framework|global environmental)",
    extra_pages = NULL,
    anchors = RF_ANCHORS, vision = TRUE),

  hierarchy = list(outcome = "programme or project outcome indicators", output = "output indicators"),

  notes = list(
    identity = paste(
      "This document covers several projects. The project at hand is the one",
      "named in the focus line: take its title, ID, agency and dates from the",
      "portfolio table, the programme comparison table or its case study,",
      "never from the document's own title. document_type_stated is the",
      "evaluation's own name. The publisher is the evaluation office (GEF IEO,",
      "IDEV, the CIF); the lead organisation is the agency implementing the",
      "focus project."),
    geography = "Countries of the focus project only, from its row or case study.",
    rationale = "The focus project's rationale from its case study or programme description; never the evaluation's own purpose.",
    results = paste(
      "Results exist only where the document has a per-project or",
      "per-programme table (for instance the GEF annex on global environmental",
      "benefits with one row per programme, or a case-study results box). Read",
      "only the focus project's row. Portfolio totals are never the project's",
      "results. Empty results fields are the honest outcome for most of these."),
    finance = paste(
      "There is usually no data sheet. Financing sits in a comparison table",
      "with one row per programme and columns such as 'Total GEF financing' and",
      "'Total cofinancing': read only the focus programme's row; budget_total",
      "is that row's own financing plus its cofinancing, budget_lead_share is",
      "its own financing. Currency USD unless stated.")),

  traps = paste(
    "Never aggregate across projects or programmes; a figure for the whole",
    "portfolio is not a result of the focus project.")
)
