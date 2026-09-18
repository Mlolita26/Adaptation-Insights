# Family module: GCF Project Completion Summary (4 pages) and Project or
# Programme Completion Report (the 2021 template, about 70 pages). Three
# documents for two projects today. Evidence: Document_Families.docx, 3.7.

MODULE <- list(
  id = "gcf_completion", label = "GCF project completion summary or completion report",
  long_doc_pages = 100, keep_pages = NULL,

  rf = list(
    patterns = paste0("report on logical framework|fund-level impact|ex-ante vs|",
                      "performance: ex-ante|annex 1|core indicator"),
    prefer = "last",                                 # the annex holds the full table
    annex_start = "annex 1[.:]? ?report on logical framework",
    extra_pages = "ex-ante vs|performance: ex-ante",
    anchors = list(
      actual   = "^(actual)",
      revised  = "^(revised)",
      target   = "^(planned|ex-ante|target)",
      baseline = "^(baseline)"),
    vision = TRUE),

  hierarchy = list(outcome = "Fund-level impact and outcome indicators (Annex 1.1, 1.2)", output = "output indicators (Annex 1.2)"),

  notes = list(
    identity = paste(
      "The 'Project/Programme Data' block (summary, page 1) or the",
      "'Project/Programme Data Profile' numbered fields 1 to 17 (completion",
      "report, pages 2 and 3) give the title, the Funding Proposal number",
      "(FP followed by three digits, the project_id), the Accredited Entity,",
      "the Executing Entities, the countries, the Board approval date, the FAA",
      "signature and effectiveness dates and the completion date. The lead",
      "organisation is the Accredited Entity; the publisher of the summary is",
      "the GCF Secretariat, of the completion report the Accredited Entity.",
      "start_year is the FAA effectiveness date (not Board approval);",
      "closure_year is the completion date. resource_id stays empty."),
    geography = "Countries and region in the data block; sites in section 1 of the completion report.",
    rationale = paste(
      "The completion report's section 1 'Background and contextual analysis'",
      "states the climate problem and the objective; the summary's 'Key project",
      "information' paragraph does the same in brief. Beneficiaries are",
      "Adaptation Core Indicator 1 (total direct beneficiaries, with the share",
      "of women) and Core Indicator 2 (indirect beneficiaries)."),
    results = paste(
      "Completion report: Annex 1 'Report on Logical Framework', part 1.1",
      "Fund-level impact indicators then 1.2 project outcome and output",
      "indicators, columns Baseline / Planned Target / Actual Result / Data",
      "Sources / Reason for the variance / Achievement assessment rating: the",
      "value is 'Actual Result', which often carries its unit and the share of",
      "women in brackets. Summary: page 4 'Project/Programme Performance:",
      "ex-ante vs. ex-post results' with Indicators / Baseline / Ex-ante target",
      "vs. Actual result / Reason for the variance and an achievement rating;",
      "its percentages of target are printed as bars and land at the end of the",
      "page text, so read that page from the image. Take an outcome or",
      "result-area indicator before the beneficiary headcount."),
    finance = paste(
      "The data block gives total project cost including co-financing",
      "(budget_total), GCF financing or 'GCF Proceeds approved'",
      "(budget_lead_share) and 'GCF Proceeds disbursed to the Accredited",
      "Entity' (disbursed); Annex 2 gives financial performance by category.",
      "Currency USD. Instrument: the GCF financing row says 'Grant'. Funder:",
      "the Green Climate Fund plus named co-financiers. Lead: the Accredited",
      "Entity. Implementer: the Executing Entities.")),

  traps = paste(
    "The GCF calls every funded activity a 'project/programme'; this is one",
    "project. Achievement ratings (Achieved, Partially achieved) are not results.")
)
