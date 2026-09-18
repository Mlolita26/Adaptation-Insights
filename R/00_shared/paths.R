##############################################################################
# paths.R — single source of truth for the project's folder layout
# (reorganised 2026-09-09; see the root README.md).
#
# New code should source this file instead of hardcoding locations:
#   source(file.path(REPO, "R", "00_shared", "paths.R"))
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
PILOT_DIR     <- file.path(DOCS_ROOT, "pilot")   # gold set, holdout set, candidate pool
GOLD_DOCS_DIR <- file.path(PILOT_DIR, "gold_set_P001-P010")

# in-scope corpus folders per source (relative to DOCS_ROOT)
CORPUS_DIRS <- c(
  worldbank = "Worldbank/Docs/2015_2026",
  gef       = "gef/Docs/evaluation_docs/2015_2026",
  gcf       = "gcf/Docs/evaluation_docs",
  afdb      = "afdb/Docs/2015_2026",
  af        = "af/Docs/evaluation_docs",
  cif       = "cif/Docs/evaluation_docs")

# Every folder a document can sit in, in scope or parked. The census, the
# dedup step and the screener all walk this list, so a file parked for a
# reason is still known to the pipeline and never re-screened blind.
SCAN_DIRS <- list(
  worldbank = c("Worldbank/Docs/2015_2026", "Worldbank/Docs/pre_2015",
                "Worldbank/Docs/to_screen", "Worldbank/Docs/screened_out"),
  gef       = c("gef/Docs/evaluation_docs/2015_2026",
                "gef/Docs/evaluation_docs/pre_2015",
                "gef/Docs/evaluation_docs/undated", "gef/Docs/to_screen"),
  gcf       = c("gcf/Docs/evaluation_docs", "gcf/Docs/to_screen"),
  afdb      = c("afdb/Docs/2015_2026", "afdb/Docs/to_screen", "afdb/Docs/undated"),
  af        = c("af/Docs/evaluation_docs", "af/Docs/progress_reports", "af/Docs/to_screen"),
  cif       = c("cif/Docs/evaluation_docs", "cif/Docs/to_screen"))
