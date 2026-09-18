# Family module: AfDB Project Completion Report form.
# 113 in scope (109 in the AfDB folder, 4 in the GEF folder). A filled form
# with fixed numbered blocks, 11 to 39 pages, English or French. The results
# are two tables inside the Effectiveness block at about a quarter of the
# document, not in an annex. Amounts are in Units of Account (UA), sometimes
# EUR or USD. Evidence: 01_Protocol/Document_Families.docx, section 3.2.

MODULE <- list(
  id = "afdb_pcr", label = "AfDB Project Completion Report (PCR) form",
  long_doc_pages = 100, keep_pages = NULL,          # short: whole document

  rf = list(
    patterns = paste0("outcome reporting|output reporting|report on outcomes|",
                      "rapport sur les effets|rapport sur les produits|",
                      "outcome indicators|output indicators|indicateurs d.effet|indicateurs de produit"),
    prefer = "first",                                # the tables sit in the body, once
    annex_start = NULL, extra_pages = NULL,
    anchors = list(
      actual   = "^(most|actual|valeur la plus|r.alis|atteint)",   # "Most recent value (A)"
      revised  = "^(revis|r.vis)",
      target   = "^(end|target|cible|expected)",                    # "End target (B)"
      baseline = "^(baseline|valeur de r|r.f.rence|situation de)"),
    vision = TRUE),

  hierarchy = list(outcome = "Outcome indicators (as per RLF)", output = "Output indicators"),

  notes = list(
    identity = paste(
      "Block 1 'Basic Data', C 'Project data' holds 'Project title' and 'Project",
      "code' (P-XX-XXX-XXX; regional operations PZ1-...): copy the title from",
      "there and use the code as project_id. A 'Report data' row gives 'Date of",
      "report' (publication_year). resource_id: leave empty unless a report",
      "number is printed; the loan or grant number ('2100150033443') is not one.",
      "document_type_stated is 'Project Completion Report' or 'Rapport",
      "d'achevement de projet'. The lead organisation and publisher is the",
      "African Development Bank (the ADF window is still the Bank). Dates in",
      "'Project data', 'Processing milestones' and 'Disbursement and closing",
      "dates': start_year is the entry into force or the first disbursement,",
      "not approval or signature; closure_year is the closing date or the last",
      "disbursement, actual not planned. A Board version carries a memorandum",
      "before the form: the form starts a few pages in."),
    geography = paste(
      "'Country' in Project data. Regions and districts are named in the",
      "Effectiveness narrative and in the output table rows."),
    rationale = paste(
      "Block 2 A 'Relevance of project development objective' quotes the",
      "objective and states the problem; the climate risk sits there and in",
      "'Progress towards the project's development objective' comments. The",
      "beneficiary group is in the Beneficiaries table (item 5 under",
      "Effectiveness): Actual (A) / Planned (B) / percent of women / Category."),
    results = paste(
      "Block 2 B 'Effectiveness': table 2 'Outcome reporting' then table 3",
      "'Output reporting'. Columns: Outcome (or Output) indicators (as per RLF)",
      "/ Baseline value / Most recent value (A) / End target (B) / Progress",
      "towards target (A/B) / Narrative assessment / Core Sector Indicator. The",
      "result is 'Most recent value (A)'; 'End target (B)' is the target;",
      "'Progress towards target' is a percentage of the target and is never a",
      "result. Outcome indicators before output indicators. The Narrative",
      "assessment cell explains target revisions. French: 'Rapport sur les",
      "effets', 'Rapport sur les produits', 'Valeur de reference', 'Valeur la",
      "plus recente', 'Cible finale'. The Beneficiaries table gives the",
      "headcount and the share of women in one place."),
    finance = paste(
      "Block 1 C 'Project data': the 'Financing source / instrument' table",
      "(Foreign currency / Local currency / Total) gives the plan by source,",
      "and the 'Financing amount' table gives approved, signed, cancelled, net",
      "and disbursed amounts with the disbursement rate. budget_total is the",
      "financing plan total across all sources; budget_lead_share is the ADB or",
      "ADF loan or grant; disbursed is the disbursed amount. Currency is UA",
      "(Units of Account) in most forms, EUR in the newest, USD in some: record",
      "the code exactly. The instrument is the 'Financing instrument' row (ADF",
      "loan, ADF grant, ADB loan, trust fund grant) with its number. Funders:",
      "the African Development Bank or Fund plus the 'Co-financiers and other",
      "external partners' row. Implementer: the 'Executing agency' row, or the",
      "ministry named as executing the project.")),

  traps = paste(
    "Amounts are in Units of Account unless the form says EUR or USD.",
    "'Progress towards target' percentages are not results. A Board cover",
    "memorandum may precede the form. Many AfDB operations are outside the",
    "agriculture sector; that is the screener's call, not this extraction's.")
)
