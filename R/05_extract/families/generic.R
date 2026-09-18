# Family module: generic. Used when no family matched, and as the fallback
# when a module is missing. Nothing about the layout is assumed.
#
# Every module defines MODULE with the same fields (see wb_icr.R for the
# fully annotated version):
#   id, label            module name and what to call it in the prompt
#   long_doc_pages       documents longer than this get keep_pages applied
#   keep_pages(pages, focus) -> logical, or NULL to read the whole document
#   rf$patterns          regex locating the results-table pages
#   rf$prefer            "first" | "last" | "dense": which hit is the table
#   rf$annex_start       regex for the annex heading (used with "last")
#   rf$extra_pages       regex for pages to add after the table ("last")
#   rf$anchors           header words per column role for rf_table.R, or NULL
#   rf$vision            attach the table pages as images
#   hierarchy            what this family calls its outcome and output levels
#   notes                one text per field group, appended to the task
#   traps                family rules appended to the system prompt

MODULE <- list(
  id = "generic", label = "Unrecognised document, generic reading",
  long_doc_pages = 100, keep_pages = NULL,
  rf = list(
    patterns = paste0("results framework|key outputs|logical framework|logframe|",
                      "cadre logique|matrice de r|cadre de r|progress towards results|",
                      "achievement of (the )?(outcomes|objectives|results)"),
    prefer = "last",
    annex_start = "annex\\s*[0-9ivx]*[.:]?\\s*(results framework|logical framework|logframe)",
    extra_pages = NULL,
    anchors = RF_ANCHORS, vision = TRUE),
  hierarchy = list(outcome = "objective or outcome indicators", output = "output indicators"),
  notes = list(
    identity = paste("No family template is known for this document. Take the identity",
                     "fields from the cover and the first pages, and the dates from any",
                     "dates block or from the text."),
    geography = "",
    rationale = "",
    results = paste("Look for any table with baseline, target and actual columns;",
                    "otherwise take achievements stated against their targets in the text."),
    finance = "Take the financing from any financing table or budget section; record the currency as printed."),
  traps = "Read the whole document; nothing about its layout is assumed."
)
