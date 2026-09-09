##############################################################################
# paths.R — single source of truth for the project's folder layout
# (reorganised 2026-09-09; see the root README.md).
#
# New code should source this file instead of hardcoding locations:
#   source(file.path(REPO, "R", "paths.R"))
# Existing scripts still carry inline constants pointing at the same places;
# they are kept in sync with this file.
##############################################################################

GL_ROOT    <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature"

PROTOCOL_DIR <- file.path(GL_ROOT, "01_Protocol")     # protocol + QC docx
TEMPLATE_DIR <- file.path(GL_ROOT, "02_Template")     # Lucy's template + working DBs
DOCS_ROOT    <- file.path(GL_ROOT, "03_Documents")    # the corpus (per source)
RESULTS_DIR  <- file.path(GL_ROOT, "04_Extraction_Results")  # team-facing outputs
REVIEW_DIR   <- file.path(RESULTS_DIR, "review")      # human to-do lists
SCORES_DIR   <- file.path(RESULTS_DIR, "scores")
ARCHIVE_DIR  <- file.path(GL_ROOT, "99_Archive")

TEMPLATE_XLSX <- file.path(TEMPLATE_DIR,
  "EvidenceSynthesis_GreyLiterature_AfricanAgricultureAdaptation_UpdatedTemplate_27Aug2026.xlsx")
GOLD_DOCS_DIR <- file.path(DOCS_ROOT, "pilot_gold/Selection_mixed stakeholders")

# in-scope corpus folders per source (relative to DOCS_ROOT)
CORPUS_DIRS <- c(
  worldbank = "Worldbank/Docs/2015_2026",
  gef       = "gef/Docs/evaluation_docs/2015_2026",
  gcf       = "gcf/Docs/evaluation_docs",
  afdb      = "afdb/Docs/2015_2026",
  af        = "af/Docs/evaluation_docs",
  cif       = "cif/Docs/evaluation_docs")
