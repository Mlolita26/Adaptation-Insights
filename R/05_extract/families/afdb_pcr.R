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
      "d'achevement de projet'. project_lead_name is 'African Development",
      "Bank' (the ADF window is still the Bank): it commissions the project and",
      "publishes this report. The executing ministry or agency is an",
      "implementor, not the lead. Dates in",
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
      "plus recente', 'Cible finale'. When an outcome cell is an index or a",
      "percentage ('30.000' against '100%'), the real count is in the",
      "Narrative assessment cell beside it ('409,089 people'): report that",
      "count with its unit. The Beneficiaries table gives the",
      "headcount and the share of women in one place. NUMBERS in these tables",
      "are printed with THREE DECIMALS and a COMMA as thousands separator:",
      "'7,520.000' is 7,520, '1,352.000' is 1,352, '30.000' is 30 and '3.600'",
      "is 3.6 (a yield). Never multiply by a thousand, never read them as",
      "percentages. The code in brackets after an indicator is its UNIT:",
      "(nbr) number, (mtd) metric tons, (mho) metric tons per hectare, (ha)",
      "hectares, (km) kilometres, (%) percent, (tca) tonnes of CO2 equivalent;",
      "mho is not an electrical unit. When an indicator row is a percentage or",
      "an index, the Assessment or Narrative cell often gives the real count",
      "('409,089 people and 1,352,522 livestock with access to water'): report",
      "that count as the result."),
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
    "Table numbers carry three decimals ('7,520.000' = 7,520; '3.600' = 3.6; '30.000' = 30);",
    "unit codes: nbr number, mtd metric tons, mho metric tons per hectare.",
    "'Progress towards target' percentages are not results. A Board cover",
    "memorandum may precede the form. Many AfDB operations are outside the",
    "agriculture sector; that is the screener's call, not this extraction's.")
)
