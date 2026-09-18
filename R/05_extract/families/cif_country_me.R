# Family module: CIF country monitoring and evaluation report (PPCR, FIP,
# SREP investment plans). The annual results report a pilot country files on
# its investment plan and the projects under it; rows are per project.
# Evidence: Document_Families.docx, section 3.8.

MODULE <- list(
  id = "cif_country_me", label = "CIF country monitoring and evaluation report",
  long_doc_pages = 100, keep_pages = NULL,

  rf = list(
    patterns = "total actual to date|report year|target indicated at the time",
    prefer = "dense",
    annex_start = NULL, extra_pages = NULL,
    anchors = list(
      actual   = "^(total actual|actual)",
      revised  = "^(revised)",
      target   = "^(target)",
      baseline = "^(baseline|baseli)"),
    vision = TRUE),

  hierarchy = list(outcome = "programme core indicators", output = "project-level indicators"),

  notes = list(
    identity = paste(
      "The cover table gives the programme (PPCR, FIP or SREP), the country,",
      "the Investment Plan endorsement date, the Lead MDB and other MDBs, the",
      "reporting date, and a table of projects with their implementing MDB and",
      "funding approval dates. The project at hand is one row of that table:",
      "its title is the project name in that row; project_id is empty unless a",
      "code is printed; the lead organisation is the MDB implementing that",
      "project; the publisher is the country's programme unit. start_year is",
      "the MDB funding approval date of that project; closure_year is usually",
      "not stated in a progress report. resource_id stays empty."),
    geography = "Regions and districts appear late, in the project descriptions on the last pages.",
    rationale = paste(
      "There is no objective statement; the programme's purpose is on the",
      "cover. Beneficiaries appear in the core indicator tables."),
    results = paste(
      "Core indicator tables per project or theme with columns Baseline /",
      "Target indicated at the time of MDB approval / Report Year (one column",
      "per year) / Total Actual to date. The result is 'Total Actual to date';",
      "the Report Year columns are annual increments and must not be added to",
      "it. Read only the row of the project at hand; never sum across the",
      "investment plan."),
    finance = paste(
      "The cover table gives the CIF funding approved per project (the",
      "budget_lead_share, currency USD); co-financing by the MDB or others is",
      "stated per project when at all. Instrument: grant or concessional loan",
      "as the table says. Funder: the Climate Investment Funds (the named",
      "programme). Lead: the implementing MDB. Implementer: the country agency",
      "named for the project.")),

  traps = "Never aggregate across projects; each row is a different project."
)
