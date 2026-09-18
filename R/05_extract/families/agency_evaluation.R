# Family module: evaluator-written terminal evaluations, mid-term reviews,
# final and impact evaluations (UNDP, UNEP, UNIDO, FAO, WFP, consultants for
# national entities). 95 in scope; also used for completion reports without a
# form, AfDB PPERs and IEG ICR reviews. 27 to 209 pages. A loose skeleton by
# evaluation criteria; an identification table at the front holds identity,
# dates and finance; results sit in a matrix in the Effectiveness section or
# an annex, otherwise in prose. Evidence: Document_Families.docx, section 3.3.

MODULE <- list(
  id = "agency_evaluation", label = "Evaluator-written evaluation (terminal, mid-term, final or impact)",
  long_doc_pages = 100,

  # Long reports: the front matter and identification table, the project
  # description, effectiveness and results, finance, conclusions, and every
  # page that looks like a results matrix (three column roles named).
  keep_pages = function(pages, focus) {
    n <- length(pages); low <- tolower(pages); keep <- rep(FALSE, n)
    keep[seq_len(min(15, n))] <- TRUE
    mark <- function(re, span = 0) for (h in grep(re, low)) keep[h:min(n, h + span)] <<- TRUE
    mark("project information table|project identification table|project fact ?sheet|project data|relevant dates|subject of the evaluation", 2)
    mark("project description|description of the project|the project\\b|context and background|problems? (that )?the project", 3)
    mark("effectiveness|progress towards results|achievement of (the )?(project )?(outcomes|objectives|results)|project results|delivery of outputs", 4)
    mark("financ|co-?financ|budget|expenditure|disburs", 1)
    mark("results framework|logical framework|logframe|cadre logique|results matrix|progress towards results matrix", 3)
    mark("conclusions?|lessons|sustainab", 1)
    mark("gender|women|beneficiar", 0)
    roles <- vapply(low, function(t) sum(c(grepl("baseline|r.f.rence", t), grepl("target|cible", t),
      grepl("actual|achiev|level at|midterm level|status|r.alis|atteint", t), grepl("indicator|indicateur", t))), integer(1))
    keep[roles >= 3] <- TRUE
    keep
  },

  rf = list(
    patterns = paste0("progress towards results|results framework|logical framework|logframe|",
                      "cadre logique|results matrix|end.of.project target|midterm target|",
                      "level at (te|mtr|terminal|mid)|achievement of (the )?(project )?(outcomes|objectives|results)|",
                      "status of (outputs|outcomes|indicators)"),
    prefer = "dense",                                # the pages with the most column roles
    annex_start = NULL, extra_pages = NULL,
    anchors = list(
      actual   = "^(level at|midterm level|end.of.project level|achieved|actual|status|cumulative|progress to date|value at|r.alis|atteint)",
      revised  = "^(midterm target|mid.term target|revised)",
      target   = "^(end.of.project|end target|eop target|target|cible|objectif)",
      baseline = "^(baseline|level in 1st|r.f.rence|situation de)"),
    vision = TRUE),

  hierarchy = list(outcome = "objective and outcome indicators", output = "output indicators"),

  notes = list(
    identity = paste(
      "Identity, dates and finance sit in an identification block on the first",
      "pages: UNDP 'Project Information Table' (project title, UNDP PIMS ID, GEF",
      "project ID, country, executing agency or implementing partner, financing",
      "at CEO endorsement and at evaluation, ProDoc signature date, planned and",
      "actual closing), UNEP 'Project Identification Table' (GEF ID, implementing",
      "agency, executing agency, dates, budget), UNIDO 'Project fact sheet', FAO",
      "project identification, WFP 'Subject of the evaluation', consultants'",
      "project description. project_id is the funder's ID as printed: a GEF ID",
      "(four or five digits), an Adaptation Fund project ID (AF00000110 or",
      "062MMAAR style), a GCF FP number; a PIMS or Atlas number is not it.",
      "resource_id is a report number only if one is printed; most have none.",
      "start_year is the ProDoc signature, implementation start or inception",
      "date; closure_year is the actual closing or completion date, not the",
      "planned one. publication_year is the date on the cover, not the year in",
      "the filename. The lead organisation is the implementing agency or",
      "entity (UNDP, UNEP, FAO, UNIDO, WFP, an accredited national entity); the",
      "evaluator or consulting firm on the cover is neither lead nor implementer."),
    geography = paste(
      "Country in the identification block; sites in the project description",
      "and in the results. Sites visited by the evaluators (methods chapter)",
      "are not project sites unless the text says the project worked there."),
    rationale = paste(
      "The problem statement is in the project description ('Problems the",
      "project sought to address', 'Context', 'Development context'); the",
      "objective sentence follows it. The beneficiary group is in the project",
      "description, the results matrix (direct beneficiaries) or the",
      "effectiveness narrative."),
    results = paste(
      "Find the results matrix first: a table whose header has Indicator,",
      "Baseline, a target column ('End-of-project target', 'End target',",
      "'Target') and an actual column ('Level at TE', 'Midterm level',",
      "'Achieved', 'Actual', 'Status'). UNDP mid-term reviews have Project",
      "Strategy / Indicator / Baseline level / Level in 1st PIR / Midterm",
      "target / End-of-project target / Midterm level and assessment /",
      "Achievement rating: the value is the Midterm level. Terminal evaluations",
      "give the level at TE or narrate achievements per outcome with a rating.",
      "If there is no matrix, take achievements stated against targets in the",
      "Effectiveness chapter. Outcome indicators before output indicators.",
      "Ratings (HS, S, MS, MU) are judgements, not results. The executive",
      "summary repeats results already in the matrix: count each once.",
      "Adaptation Fund projects align to the AF Results Framework outcomes and",
      "core indicators; GEF projects to GEF core indicators: keep the wording",
      "the document uses."),
    finance = paste(
      "The identification block gives the grant (GEF, Adaptation Fund or GCF),",
      "the co-financing and the total, planned at approval and sometimes at",
      "evaluation; the 'Finance and co-finance' or 'Financial management'",
      "section gives expenditure and materialised co-financing, often as a",
      "table Source / Type / Planned / Actual. budget_total is the planned",
      "total (grant plus co-financing; for Adaptation Fund projects without",
      "co-financing the grant alone); budget_lead_share is the grant;",
      "disbursed is the actual expenditure. Currency USD unless printed",
      "otherwise. The instrument is a grant. Funder: the GEF (or its trust",
      "fund), the Adaptation Fund or the GCF. Lead: the implementing agency or",
      "entity. Implementer: the executing agency or implementing partner (a",
      "ministry or agency).")),

  traps = paste(
    "Methodology numbers are everywhere near the front (households surveyed,",
    "key informants, focus groups, sites visited) and are never results.",
    "'Joint evaluation: No' is a form field, not a description. Values in a",
    "mid-term review are mid-term values; record them as they are.")
)
