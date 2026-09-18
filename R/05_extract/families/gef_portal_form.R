# Family module: GEF Portal terminal evaluation and mid-term review form (also
# used for the UNEP operational completion form). 25 portal forms and 8 UNEP
# forms in scope. The portal form is a system-generated PDF of 5 to 19 pages
# with the same sections every time; it summarises a fuller report that the
# 'Annex' section links to. Evidence: Document_Families.docx, sections 3.4-3.5.

MODULE <- list(
  id = "gef_portal_form", label = "GEF Portal TE/MTR form (or UNEP operational completion form)",
  long_doc_pages = 100, keep_pages = NULL,          # always short: whole document

  rf = list(
    patterns = "core indicators|extracted indicators|delivery of outputs|results achieved",
    prefer = "first",
    annex_start = NULL, extra_pages = NULL,
    # GEF-7 forms: Target at PIF / At CEO Endorsement / Achieved at MTR / Achieved at TE
    anchors = list(
      actual   = "^(achieved|actual|materialized)",
      revised  = "^(at ceo|ceo)",
      target   = "^(target|at pif|pif|expected)",
      baseline = "^(baseline)"),
    vision = TRUE),

  hierarchy = list(outcome = "core indicators", output = "output-level achievements in the findings narrative"),

  notes = list(
    identity = paste(
      "Section I.A 'Description' has rows Project name, Country, GEF ID,",
      "Implementing Agency, Executing Entity, Trust Fund, Project Type,",
      "Objective: copy the title from 'Project name'; project_id is the GEF ID;",
      "resource_id stays empty (the form has no report number). The cover word",
      "'TERMINAL EVALUATION' or 'MID-TERM REVIEW' is document_type_stated and",
      "the header date ('3/14/2025 Page 1 of 10') or the 'TE Submission' row is",
      "the publication date. The lead organisation and publisher is the",
      "Implementing Agency (UNDP, UNEP, FAO, UNIDO ...). Section I.B 'Key",
      "Dates': start_year is 'Implementation Start' (not CEO Endorsement or",
      "Agency Approval); closure_year is 'Actual Completion' (not Expected).",
      "UNEP operational completion form: block 1 'Project Identification' gives",
      "GEF ID, title, executing agency, start date and actual completion date."),
    geography = "Countries are on the cover and in I.A; sites, if any, are in the findings narrative.",
    rationale = paste(
      "The 'Objective' row in I.A or the opening of II.A 'Main findings' states",
      "the objective; the problem it answers is in the same narrative.",
      "Beneficiaries are a core indicator ('Total number of direct",
      "beneficiaries') and II.C 'Gender Equality' gives the gender content."),
    results = paste(
      "Section III 'Core Indicators' is the results table. Older forms list",
      "'EXTRACTED INDICATORS' as label and value rows (Total number of direct",
      "beneficiaries; Ha of land better managed to withstand the effects of",
      "climate change; No. of people trained; No. of institutions with",
      "strengthened capacities; No. of policies, plans and processes ...): each",
      "value is an achieved value. GEF-7 forms list Core Indicators 1 to 11 with",
      "columns Target at PIF / At CEO Endorsement / Achieved at MTR / Achieved",
      "at TE: the result is the 'Achieved' column matching this form (TE or",
      "MTR); PIF and CEO Endorsement figures are targets. II.A 'Main findings'",
      "states output-level achievements against targets ('exceeded four of the",
      "seven output level targets'): use it for an outcome-level result when",
      "the indicator set only gives reach. UNEP form: 'Delivery of outputs' and",
      "'Project outcome' are short statements, no targets."),
    finance = paste(
      "I.A or I.C 'Disbursements' gives the GEF grant amount and the cumulative",
      "disbursement; section IV 'Co-financing' lists Sources of Co-financing /",
      "Name of Co-financier / Type / Investment Mobilized / Anticipated at",
      "CEO($) / Materialized at MTR($) / Materialized at TE($). budget_total is",
      "the GEF grant plus the materialised co-financing at TE (anticipated at",
      "CEO when the TE column is empty); budget_lead_share is the GEF grant;",
      "disbursed is the cumulative disbursement. Currency USD. Instrument:",
      "grant. Funder: the Global Environment Facility through the named trust",
      "fund (GEF Trust Fund, LDCF, SCCF) plus each named co-financier. Lead:",
      "the Implementing Agency. Implementer: the Executing Entity.")),

  traps = paste(
    "This form is a summary: expect no components, no sites and no methods.",
    "'Expected MTR' and 'Expected Completion' are plans; only 'Actual' rows are",
    "events. The 'Annex' section holds a link to the full report, nothing more.")
)
