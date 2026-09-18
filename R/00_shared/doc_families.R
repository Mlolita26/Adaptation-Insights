# doc_families.R - which template is this document written in?
#
# A source is not a family. The GEF folder holds World Bank ICRs, AfDB PCRs,
# GEF Portal forms, UNDP evaluations and World Bank progress reports side by
# side, and the same is true in smaller measure elsewhere. Deduplication,
# screening and extraction all need one answer to "what kind of document is
# this", so the definitions live here once and every step sources this file.
#
# The forms (ICR, PCR, Portal form, completion summary...) announce
# themselves on the cover with fixed wording, which a rule catches for free
# and consistently. The screener, which reads the whole document anyway, is
# then asked to confirm or correct the guess from this same closed list, and
# a disagreement is flagged rather than silently resolved.
#
# Each family carries:
#   id        short key used in CSVs and for routing
#   label     what a person calls it
#   module    which extraction prompt handles it ("none" = not extracted:
#             progress documents and worksheets fail the source-type rule)
#   owner     the source whose own portal publishes this form (the copy to
#             keep when the same document turns up in two folders), or NA
#   progress  TRUE for supervision / progress documents, not evaluations
#   multi     TRUE when the document covers several projects by design
#   where     where the template fields sit in this form - for the prompt
#             module and for people reading the queue
#   detect    regex on the first pages, lowercased and whitespace-collapsed
# Order matters: the first match wins, so forms come before catch-alls.

FAMILIES <- list(
  list(id = "wb_icrr", label = "World Bank IEG ICR Review", module = "agency_evaluation",
       owner = "worldbank", progress = FALSE, multi = FALSE,
       where = paste("IEG's 10 to 20 page validation of an ICR: project data (P-number, dates,",
                     "financing), objectives, outcome ratings by objective with the evidence IEG",
                     "accepted, lessons. Results are summarised, not tabulated; the ICR itself",
                     "is the fuller source and usually sits in the same folder."),
       # ICRs define 'ICRR' in their acronym list, so the bare abbreviation
       # is not evidence; the review's own title or report number is
       detect = paste0("implementation completion (and results )?report (\\(icr\\) )?review|",
                       "report number ?:? ?icrr[0-9]+|^.{0,400}independent evaluation group")),

  list(id = "wb_icr", label = "World Bank ICR", module = "wb_icr", owner = "worldbank",
       progress = FALSE, multi = FALSE,
       where = paste("Data Sheet on p1-3: project name and P-number, financing table,",
                     "Key Dates (Approval, Effectiveness, Original and Actual Closing), ratings.",
                     "PDO and outcome in sections I-II. Annex 1 'Results Framework and Key Outputs':",
                     "indicator tables (Baseline / Original Target / Formally Revised Target /",
                     "Actual Achieved at Completion) then 'Key Outputs by Component'.",
                     "Annex 2 'Project Cost by Component' for disbursed."),
       # the title words, or an ICR report number on the cover when the title
       # page is an image or oddly ordered
       detect = "implementation completion (and results )?report|report no\\.?:? ?icr[0-9]{4,}"),

  list(id = "wb_isr", label = "World Bank ISR (progress)", module = "none", owner = "worldbank",
       progress = TRUE, multi = FALSE,
       where = "Implementation Status and Results Report: a supervision snapshot, not an evaluation.",
       detect = "implementation status (&|and) results report"),

  list(id = "gef_pir", label = "GEF Project Implementation Report (progress)", module = "none",
       owner = "gef", progress = TRUE, multi = FALSE,
       where = "Annual implementation report filed by the agency; not an evaluation.",
       detect = "^.{0,300}project implementation report|gef - project implementation report"),

  list(id = "gef_portal_form", label = "GEF Portal TE / MTR form", module = "gef_portal_form",
       owner = "gef", progress = FALSE, multi = FALSE,
       where = paste("System-generated PDF ('d/m/yyyy Page 1 of N'). I Overview: A Description,",
                     "B Key Dates (CEO endorsement, agency approval, implementation start, first",
                     "disbursement, expected/actual MTR, expected/actual completion, actual TE),",
                     "C Disbursements. II Progress status and issues (findings, stakeholders,",
                     "gender, knowledge). III Core Indicators 1-11 with target at PIF, at CEO",
                     "endorsement, achieved at MTR / at TE. IV Co-financing by source and type.",
                     "V Safeguards. Implementing agency, executing entity, trust fund named in I.B."),
       # pdftools may put the running header ('3/14/2025 Page 1 of 10') after
       # the body, so the form is also recognised by its own first field row
       detect = paste0("^.{0,60}[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} page 1 of [0-9]+|",
                       "^.{0,200}(terminal evaluation|mid-?term review|mid-?term evaluation|\\bmtr\\b|\\bte\\b)",
                       " ?project id: ?[0-9]{3,5} project")),

  list(id = "unep_completion_form", label = "UNEP operational completion form",
       module = "gef_portal_form", owner = "gef", progress = FALSE, multi = FALSE,
       where = paste("3 to 8 page form: 1 Project identification (GEF ID, title, agency, dates,",
                     "budget), then delivery of outputs and outcomes by component, ratings,",
                     "co-financing. Sparse; results are short statements against planned outputs."),
       detect = "simplified operational completion report|project operational completion report|operational completion report \\(ocr\\)"),

  list(id = "gef_indicator_sheet", label = "GEF-7 core indicator worksheet", module = "none",
       owner = "gef", progress = FALSE, multi = FALSE,
       where = paste("Standalone annex listing GEF core indicators with targets and achievements;",
                     "belongs to a project's evaluation rather than standing alone."),
       detect = "gef ?7 core indicators|core indicator worksheet"),

  list(id = "gcf_completion_summary", label = "GCF project completion summary",
       module = "gcf_completion", owner = "gcf", progress = FALSE, multi = FALSE,
       where = paste("4 pages. Project/Programme Data block (title, accredited entity, executing",
                     "entities, countries, FP number, dates, financing). Key information and",
                     "lessons. 'Project/Programme Performance: ex-ante vs ex-post results':",
                     "GCF core indicators with baseline, ex-ante target vs actual, reason for",
                     "variance, achievement rating."),
       detect = "gcf project completion summary|project completion summary \\[fp[0-9]{3}\\]"),

  list(id = "gcf_pcr", label = "GCF project completion report", module = "gcf_completion",
       owner = "gcf", progress = FALSE, multi = FALSE,
       where = paste("GCF PCR template (2021): Data Profile (accredited entity, executing entity,",
                     "FP number, board approval, theme). Sections 1-7 narrative by component and",
                     "against the six GCF investment criteria. Annex 1 'Report on Logical",
                     "Framework' is the results table; Annex 2 financial performance by category."),
       detect = "project/programme completion report"),

  list(id = "afdb_pcr", label = "AfDB project completion report form", module = "afdb_pcr",
       owner = "afdb", progress = FALSE, multi = FALSE,
       where = paste("1 Basic Data: A Report data (title, project code P-XX-XXX-XXX, country,",
                     "sector, report and mission dates), B Bank staff, C Project data (financing",
                     "plan by source in UA or EUR, loan number, approval / signature / entry into",
                     "force / first and last disbursement dates, amounts approved, cancelled,",
                     "disbursed), D Management review. 2 Performance assessment: A Relevance,",
                     "B Effectiveness with 'Report on Outcomes' and 'Output reporting' tables",
                     "(Baseline value / Most recent value (A) / End target (B) / Progress towards",
                     "target (A/B) / Narrative assessment), C Efficiency, D Sustainability.",
                     "3 Stakeholder performance. 4 Lessons. 5 Overall PCR rating. Amounts in UA."),
       detect = paste0("(project completion report|rapport d.ach[eè]vement|\\(pcr\\))",
                       ".{0,4000}?(basic data|donn[ée]es de base|p-[a-z]{2}-[a-z0-9]{3}-[0-9]{3}|",
                       "african development (bank|fund)|banque africaine|fonds africain|adb/bd/|adf/bd/)")),

  list(id = "afdb_pper", label = "AfDB project performance evaluation report",
       module = "agency_evaluation", owner = "afdb", progress = FALSE, multi = FALSE,
       where = paste("OPEV/IDEV evaluator-written report on one operation: basic project data,",
                     "then relevance, effectiveness (outcomes against appraisal targets),",
                     "efficiency, sustainability, ratings, lessons."),
       detect = "project performance evaluation report|\\(pper\\)"),

  list(id = "cif_country_me", label = "CIF country M&E report (PPCR / FIP / SREP)",
       module = "cif_country_me", owner = "cif", progress = FALSE, multi = TRUE,
       where = paste("Cover table: investment plan, endorsement date, lead and other MDBs,",
                     "projects with approval dates. Core indicator tables per project with",
                     "Baseline / Target at MDB approval / Report Year columns / Total actual to",
                     "date. Rows are per project; do not sum across the investment plan."),
       detect = paste0("(monitoring and evaluation report|monitoring and reporting report|m&r report)",
                       ".{0,3000}?(investment plan|ppcr|pilot program for climate resilience|",
                       "forest investment program|srep|scaling.up renewable)")),

  list(id = "af_ppr", label = "Adaptation Fund project performance report (progress)",
       module = "none", owner = "af", progress = TRUE, multi = FALSE,
       where = "Annual PPR filed by the implementing entity; not an evaluation.",
       # only when the document calls ITSELF a PPR up front; an evaluation
       # that cites the PPRs it drew on is not one
       detect = "^.{0,400}project performance report"),

  list(id = "programme_evaluation", label = "Programme / portfolio / thematic evaluation",
       module = "programme_evaluation", owner = NA_character_, progress = FALSE, multi = TRUE,
       where = paste("Covers several projects by design (GEF IEO, IDEV corporate or cluster,",
                     "CIF programme reviews, joint evaluations). Project-level facts, if any, sit",
                     "in per-project tables or annexes; read only the focus project's row."),
       # named institutional formats only; a single-project evaluation that
       # happens to say 'programme' is left to agency_evaluation, and the
       # screener's covers_several_projects flag catches the rest
       detect = paste0("independent evaluation office of the gef|evaluation of gef|\\bidev\\b|",
                       "independent development evaluation|corporate evaluation|cluster evaluation|",
                       "thematic evaluation|joint evaluation(?!:? ?no\\b)|portfolio (evaluation|review)|",
                       "(evaluation|review|assessment) of the (ppcr|fip|ctf|srep|climate investment funds|",
                       "forest investment program|pilot program for climate resilience|",
                       "clean technology fund|scaling.up renewable energy program)")),

  list(id = "agency_evaluation", label = "Evaluator-written TE / MTR / final evaluation",
       module = "agency_evaluation", owner = NA_character_, progress = FALSE, multi = FALSE,
       where = paste("UNDP / UNEP / UNIDO / FAO / WFP / consultant template: executive summary",
                     "with ratings, methods (sample sizes are NOT results), project description",
                     "(IDs, agencies, budget, dates), findings by Relevance / Effectiveness /",
                     "Efficiency / Sustainability, conclusions, annexes. Results in a 'progress",
                     "towards results' matrix (indicator, baseline, midterm and end targets, level",
                     "at MTR/TE, rating) in the Effectiveness chapter or an annex; otherwise in",
                     "narrative. Objective / outcome / output wording, no PDO. AF documents align",
                     "to the AF Results Framework; GEF ones to GEF core indicators."),
       detect = paste0("terminal evaluation|final evaluation|mid-?term (review|evaluation|assessment)|",
                       "\\bmidterm\\b|end.of.project evaluation|terminal review|evaluation report|",
                       "impact evaluation|impact assessment|examen [àa] mi-parcours|",
                       "office of evaluation|evaluation office|independent evaluation unit|",
                       "[ée]valuation (finale|terminale|[àa] mi-parcours)|revue [àa] mi-parcours")),

  list(id = "completion_report", label = "Completion / terminal / final report (non-form)",
       module = "agency_evaluation", owner = NA_character_, progress = FALSE, multi = FALSE,
       where = paste("Government or agency narrative at closure without a fixed template:",
                     "project data sheet, progress against planned milestones, budget",
                     "execution, lessons. Results mostly in narrative or a milestones table."),
       detect = "completion report|terminal report|self-evaluation|rapport (final|d.ach[eè]vement)|final report"),

  list(id = "generic", label = "Unrecognised", module = "generic", owner = NA_character_,
       progress = FALSE, multi = FALSE,
       where = "No family matched; the whole document is read with the generic prompt.",
       detect = NA_character_)
)

FAMILY_IDS <- vapply(FAMILIES, `[[`, character(1), "id")
names(FAMILIES) <- FAMILY_IDS

# A form's moment in the project cycle is fixed by what the form is: an ICR
# is a completion document even though it discusses the mid-term review and
# cites the ISRs. Only evaluator-written reports need their title read.
FAMILY_KIND <- c(wb_icrr = "completion", wb_icr = "completion", wb_isr = "progress",
                 gef_pir = "progress", unep_completion_form = "completion",
                 gef_indicator_sheet = "other", gcf_completion_summary = "completion",
                 gcf_pcr = "completion", afdb_pcr = "completion", afdb_pper = "terminal",
                 cif_country_me = "progress", af_ppr = "progress",
                 completion_report = "completion")

family_info <- function(id) FAMILIES[[if (id %in% FAMILY_IDS) id else "generic"]]

# the text a detector looks at: the first pages, lowercased, one space between words
family_head <- function(pages, n = 3) {
  h <- paste(pages[seq_len(min(n, length(pages)))], collapse = " ")
  h <- tolower(gsub("\\s+", " ", h))
  trimws(h)
}

# Terminal, midterm, completion, progress or other: the document's moment in
# the project cycle. Two documents about the same project with the same kind
# are the same document; with different kinds they are a project cluster.
doc_kind <- function(head) {
  one <- function(h) {
    if (grepl("mid-?term|\\bmidterm\\b|mi-parcours|\\bmtr\\b", h)) return("midterm")
    if (grepl("terminal|final evaluation|[ée]valuation finale|terminale|end.of.project|\\bte\\b report", h)) return("terminal")
    if (grepl("impact (evaluation|assessment)", h)) return("impact")
    if (grepl("completion|ach[eè]vement|terminal report|final report", h)) return("completion")
    if (grepl("implementation status (&|and) results|project implementation report|project performance report", h)) return("progress")
    "other"
  }
  # the title zone first; the whole head only if the title says nothing
  k <- one(substr(head, 1, 600))
  if (k == "other") k <- one(head)
  k
}

# Returns list(family, rule, kind). `rule` is the regex that fired, or
# "fallback" when nothing matched, so a wrong call can be traced to its cause.
detect_family <- function(pages, n = 3) {
  head <- family_head(pages, n)
  kind_of <- function(id) if (id %in% names(FAMILY_KIND)) unname(FAMILY_KIND[id]) else doc_kind(head)
  for (f in FAMILIES) {
    if (is.na(f$detect)) next
    if (grepl(f$detect, head, perl = TRUE)) {
      return(list(family = f$id, rule = f$detect, kind = kind_of(f$id)))
    }
  }
  list(family = "generic", rule = "fallback", kind = doc_kind(head))
}

# The closed list as the screener prompt states it: id, label, one line each.
family_choices_text <- function() {
  paste(vapply(FAMILIES, function(f) {
    flag <- if (isTRUE(f$progress)) " [progress document, not an evaluation]"
            else if (isTRUE(f$multi)) " [covers several projects]" else ""
    sprintf("- %s: %s%s", f$id, f$label, flag)
  }, character(1)), collapse = "\n")
}

# Project and report identifiers a cover may carry, by funder convention.
# Used by the dedup step to say "same document" across folders.
extract_ids <- function(head) {
  up <- toupper(head)
  pick <- function(re) { m <- regmatches(up, gregexpr(re, up, perl = TRUE))[[1]]; unique(m) }
  list(
    wb_project  = pick("\\bP[0-9]{6}\\b"),
    wb_report   = pick("\\bICR[0-9]{3,8}\\b"),
    afdb_code   = pick("\\bP-[A-Z]{2}-[A-Z0-9]{3}-[0-9]{3}\\b"),
    gef_id      = { g <- regmatches(up, gregexpr("GEF (PROJECT )?ID[^0-9]{0,12}([0-9]{4,5})", up, perl = TRUE))[[1]]
                    unique(sub(".*?([0-9]{4,5})$", "\\1", g)) },
    gcf_fp      = pick("\\b[FS]P[0-9]{3}\\b"),
    af_id       = unique(c(pick("\\bAF[0-9]{8}\\b"), pick("\\bAFRDG[0-9]{5}\\b"),
                           pick("\\b[0-9]{3}[A-Z]{2,3}[A-Z]{2,4}R\\b")))
  )
}
