# Family module: World Bank Implementation Completion and Results Report.
# 295 in scope (276 in the World Bank folder, 19 in the GEF folder). One fixed
# template in two generations: the 2018 template (most of the corpus) keeps
# the results in Annex 1 "Results Framework and Key Outputs"; the 2015-2017
# template keeps them in the Data Sheet, section F "Results Framework
# Analysis", and its Annex 2 is "Outputs by Component".
# Evidence: 01_Protocol/Document_Families.docx, section 3.1.

MODULE <- list(
  id = "wb_icr", label = "World Bank Implementation Completion and Results Report (ICR)",
  long_doc_pages = 100,

  # Long ICRs: keep the Data Sheet, context and objectives, outcome, the
  # results annex, project cost, and the co-financier comments. Both template
  # generations are covered.
  keep_pages = function(pages, focus) {
    n <- length(pages); low <- tolower(pages); keep <- rep(FALSE, n)
    mark <- function(re, span = 0) for (h in grep(re, low)) keep[h:min(n, h + span)] <<- TRUE
    mark("data sheet", 3)
    mark("context and development objectives|project context|context at appraisal", 8)
    mark("\\boutcome\\b", 2)
    mark("results framework and key outputs|results framework analysis", 28)
    mark("key outputs by component|outputs by component", 4)
    mark("project cost by component|project costs and financing", 2)
    mark("recipient, co-financier|borrower, co-financier|co-financier", 4)
    keep
  },

  rf = list(
    patterns = "results framework|key outputs|results framework analysis",
    prefer = "last",
    annex_start = "annex\\s*[0-9ivx]*[.:]?\\s*(results framework|logical framework)",
    # the same achievements are stated a second time, in words, at the end of
    # the annex; take those pages too
    extra_pages = "key outputs by component|outputs by component",
    anchors = list(
      actual   = "^(actual|achiev|completion)",
      revised  = "^(revis|formally)",
      target   = "^(target|original)",
      baseline = "^(baseline|base)"),
    vision = TRUE),

  hierarchy = list(outcome = "PDO indicators (A.1)", output = "Intermediate Results Indicators (A.2)"),

  notes = list(
    identity = paste(
      "The project title is on the cover after 'FOR' and again in the Data Sheet",
      "'Project Name' row, followed by the P-number in brackets; copy it from the",
      "Data Sheet. project_id is the P-number (P followed by six digits); when",
      "additional financing adds a second P-number, take the one in the title.",
      "resource_id is the cover's 'Report No: ICR' followed by digits.",
      "document_type_stated is 'Implementation Completion and Results Report'",
      "(older reports: 'Implementation Completion Report'). The lead",
      "organisation and publisher is the World Bank. Dates are in the Data Sheet",
      "'Key Dates' block: start_year is the Effectiveness date, not Approval;",
      "closure_year is the Actual Closing date, not the Original Closing."),
    geography = paste(
      "The country is on the cover ('TO THE REPUBLIC OF ...') and in the Data",
      "Sheet 'Country' row. Sites are named in section I 'Components', in the",
      "results annex indicator names, and on the map annex."),
    rationale = paste(
      "The problem statement is in section I 'Context at Appraisal' (older",
      "template: section 1 'Project Context'); the objective is the PDO",
      "sentence 'The Project Development Objective is to ...'. The beneficiary",
      "group is usually named as an indicator 'Direct project beneficiaries'",
      "with 'Female beneficiaries (percentage)' beneath it, or in the PDO."),
    results = paste(
      "2018 template: Annex 1 'Results Framework and Key Outputs', part A.1 PDO",
      "Indicators then A.2 Intermediate Results Indicators. Columns: Indicator",
      "Name / Unit of Measure / Baseline / Original Target / Formally Revised",
      "Target / Actual Achieved at Completion. The value is 'Actual Achieved at",
      "Completion'; 'Formally Revised Target' replaces 'Original Target' when",
      "filled. A row of dates printed under the values is when each value was",
      "measured, never a result. Part B 'Key Outputs by Component' repeats each",
      "achievement in a sentence: use it to confirm the table. 2015-2017",
      "template: Data Sheet section F 'Results Framework Analysis' with 'Actual",
      "Value Achieved at Completion or Target Years'. Yes/No indicators are not",
      "numeric results. Take PDO indicators before intermediate ones."),
    finance = paste(
      "Data Sheet financing table: one row per source (IDA, IBRD, named trust",
      "funds, co-financiers, Borrower) with columns Original Amount (US$) /",
      "Revised Amount (US$) / Actual Disbursed (US$), and a 'Total Project Cost'",
      "row: budget_total is the Total Project Cost original amount,",
      "budget_lead_share is the World Bank row (IDA, IBRD or the trust fund),",
      "disbursed is the total Actual Disbursed. Currency USD; IDA credits are",
      "also stated in SDR on the cover, use the US dollar figures. The",
      "instrument is the cover wording 'ON A CREDIT IN THE AMOUNT OF',",
      "'ON A GRANT', 'ON A SMALL GRANT'. Funders are the World Bank (IDA or",
      "IBRD) and any named trust fund or co-financier; a GEF or LDCF trust fund",
      "line makes the GEF a funder. The implementer is the 'Implementing",
      "Agency' in the Data Sheet 'Organizations' block; the Borrower is the",
      "country. Annex 3 (older: Annex 1) gives cost by component, appraisal",
      "against actual.")),

  traps = paste(
    "The acronym list defines 'ICRR' (the IEG review); that word does not",
    "describe this document. Dates under indicator values are measurement",
    "dates. Amounts are in US dollars.")
)
