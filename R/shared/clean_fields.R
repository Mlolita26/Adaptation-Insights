##############################################################################
# clean_fields.R — deterministic field hygiene shared by both extraction
# pipelines. Team rules agreed 9 September 2026:
#
#   project_title   never ALL CAPS, never carries a project or document code;
#                   abbreviations are fine
#   location_count  a bare number, nothing else
#   location_notes  always carries a verbatim statement from the document
#                   about the location(s)
#   GESI_project    when the document says nothing about gender, say so
#   result values   whole digits (no separators, no "4.7 million", no "over")
#   percentages     shown with %
#
# These run in code, after the model, so they hold regardless of the prompt.
##############################################################################

## ---- titles ----------------------------------------------------------------
# identifiers that must not appear in a title. Abbreviations (APPSA, AFCC2/RI)
# are deliberately NOT matched here.
TITLE_CODE_RX <- paste0(
  "\\(?\\b(GEF\\s*ID|Project\\s*ID|Report\\s*No\\.?)\\s*:?\\s*[A-Z0-9./-]+\\)?|",
  "\\(?\\bP\\d{5,7}\\b\\)?|",            # P149269
  "\\(?\\bTF\\d?[A-Z0-9]{4,}\\b\\)?|",   # TF0A3918
  "\\(?\\bICR\\d{4,}\\b\\)?|",           # ICR00004643
  "\\(?\\bIDA[- ]?\\d{4,}\\b\\)?")

SMALL_WORDS <- c("a", "an", "and", "as", "at", "by", "for", "from", "in", "of",
                 "on", "or", "the", "to", "with", "et", "de", "du", "la", "le",
                 "des", "sur", "pour", "dans")
KNOWN_ACRONYMS <- c("APPSA", "RFS", "GGP", "CFI", "GEF", "IAP", "NPCA", "SLWM",
                    "IPM", "SWIO", "AFCC2", "RI", "PPCR", "FIP", "SREP", "NFLSP",
                    "CSIF", "ROAM", "AFR", "SADC", "IFAD", "UNDP", "UNEP", "FAO",
                    "WB", "AfDB", "GCF", "AF", "CIF", "NGO", "PPP", "MSME", "SME",
                    "ICT", "M&E", "MCA", "EEZ", "VSL", "PCR", "CCP", "BMU", "VFC")

cap_parts <- function(w) {   # capitalise after / and - too: Research/Development
  parts <- strsplit(w, "(?<=[/-])", perl = TRUE)[[1]]
  paste(vapply(parts, function(p) sub("([a-z])", "\\U\\1", p, perl = TRUE),
               character(1)), collapse = "")
}
title_case_one <- function(w, first = FALSE) {
  bare <- gsub("[^A-Za-z0-9&/]", "", w)
  if (nzchar(bare) && toupper(bare) %in% KNOWN_ACRONYMS) return(toupper(w))
  # no vowel and at least two letters -> almost certainly an acronym (NPCA)
  if (nchar(bare) >= 2 && nchar(bare) <= 6 && !grepl("[AEIOUYaeiouy]", bare))
    return(toupper(w))
  lw <- tolower(w)
  if (!first && gsub("[^a-z]", "", lw) %in% SMALL_WORDS) return(lw)
  cap_parts(lw)
}
# "shouty" = at least three SHOUTED words, so a mixed title like
# "EMPOWERING RWANDAN FARMERS Financial Education as a Catalyst" is caught
# while "Resilient Food Systems (RFS)" is left alone
n_shouted <- function(x) {
  toks <- strsplit(x, "[^A-Za-z0-9&/'-]+")[[1]]
  toks <- toks[nchar(gsub("[^A-Za-z]", "", toks)) >= 3]
  sum(vapply(toks, function(t) {
    lt <- gsub("[^A-Za-z]", "", t)
    nzchar(lt) && lt == toupper(lt) && !toupper(lt) %in% KNOWN_ACRONYMS
  }, logical(1)))
}

clean_title <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[1])) return("")
  x <- trimws(gsub("\\s+", " ", as.character(x[1])))
  if (!nzchar(x)) return("")
  x <- gsub(TITLE_CODE_RX, " ", x, perl = TRUE)   # drop identifiers
  x <- gsub("\\s*--+\\s*", " ", x)                 # the WB "-- Pxxxxx" separator
  x <- gsub("\\(\\s*\\)", " ", x)                  # brackets left empty
  x <- trimws(gsub("\\s+", " ", x))
  x <- gsub("[ ,;:_-]+$", "", x)
  if (n_shouted(x) >= 3) {
    parts <- strsplit(x, " ")[[1]]
    x <- paste(vapply(seq_along(parts), function(i) title_case_one(parts[i], i == 1L),
                      character(1)), collapse = " ")
  }
  trimws(x)
}

## ---- counts ----------------------------------------------------------------
# "20 pilot villages" -> "20"; "~4" -> "4"; "N/A" -> ""
clean_count <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[1])) return("")
  v <- gsub("[^0-9]", "", as.character(x[1]))
  if (!nzchar(v)) return("")
  as.character(as.integer(v))
}

## ---- numbers ---------------------------------------------------------------
# "4.7 million" -> 4700000 | "10,496" -> 10496 | "15.00" -> 15
# "over 20,001" -> 20001 | "47 percent" -> 47 | "11-20%" -> 11 (range flagged)
MAGNITUDE <- c(thousand = 1e3, k = 1e3, million = 1e6, m = 1e6, mn = 1e6,
               billion = 1e9, bn = 1e9)
clean_number <- function(x) {
  out <- list(value = "", note = "")
  if (is.null(x) || !length(x) || is.na(x[1])) return(out)
  s <- trimws(as.character(x[1]))
  if (!nzchar(s)) return(out)
  if (toupper(s) %in% c("N", "Y", "NO", "YES")) { out$value <- toupper(s); return(out) }
  low <- tolower(s)
  # a whole sentence is not a value
  if (lengths(gregexpr("\\S+", low)) > 12) { out$note <- "VALUE WAS A SENTENCE"; return(out) }
  nums <- regmatches(low, gregexpr("[0-9]+(?:[.,][0-9]+)*", low))[[1]]
  if (!length(nums)) { out$note <- "NO NUMBER IN VALUE"; return(out) }
  is_range <- length(nums) >= 2 &&
              grepl("[0-9]\\s*(-|to|and|a)\\s*[0-9]|between", low)
  norm1 <- function(n) {
    n <- gsub(",(?=[0-9]{3}\\b)", "", n, perl = TRUE)   # thousands separators
    n <- gsub(",", ".", n, fixed = TRUE)                # decimal comma
    suppressWarnings(as.numeric(n))
  }
  v <- norm1(nums[1])
  if (is.na(v)) { out$note <- "NO NUMBER IN VALUE"; return(out) }
  mag <- names(MAGNITUDE)[vapply(names(MAGNITUDE),
           function(k) grepl(paste0("\\b", k, "\\b"), low), logical(1))]
  if (length(mag)) v <- round(v * MAGNITUDE[[mag[1]]])
  # "whole digits" means no separators and no "4.7 million", NOT the loss of a
  # real decimal: a 2.8 t/ha yield or an 85.7% rate keeps its decimal
  out$value <- if (v == round(v))
    format(round(v), scientific = FALSE, trim = TRUE, big.mark = "")
  else sub("0+$", "", format(v, scientific = FALSE, trim = TRUE, big.mark = "",
                             nsmall = 0, digits = 15))
  out$value <- sub("\\.$", "", out$value)
  if (is_range) out$note <- paste0("RANGE IN SOURCE: ", s)
  else if (grepl("\\b(over|more than|fewer than|less than|about|approx|around|up to|at least|nearly|almost)\\b", low))
    out$note <- paste0("QUALIFIER IN SOURCE: ", s)
  out
}

## ---- percentages -----------------------------------------------------------
is_percent <- function(value, unit) {
  txt <- tolower(paste(value, unit))
  grepl("%|\\bper ?cent(age)?\\b", txt)
}
# free-text unit fields show the symbol; the general sheet's controlled list
# still uses the word "percentage", which harmonize maps to
clean_unit <- function(unit, value = "") {
  u <- trimws(as.character(unit %||% ""))
  if (is_percent(value, u)) return("%")
  u
}
`%||%` <- function(a, b) if (is.null(a) || !length(a) || is.na(a[1])) b else a

## ---- text fields -----------------------------------------------------------
# Control characters occasionally arrive in prose fields where a dash was in
# the PDF ("natural resource base <TAB>6 particularly soil"). Repair the dash
# case, strip the rest, and flag it so a human can look rather than have a
# stray digit read as data.
clean_text <- function(x) {
  out <- list(value = "", note = "")
  if (is.null(x) || !length(x) || is.na(x[1])) return(out)
  s <- as.character(x[1])
  had <- grepl("[--\t]", s)
  s <- gsub("[\t]\\s*[0-9]{1,4}(?=\\s)", " -", s, perl = TRUE)
  s <- gsub("[--\t]", " ", s)
  s <- trimws(gsub("\\s+", " ", s))
  out$value <- s
  if (had) out$note <- "CHARACTER ARTIFACT REPAIRED - check punctuation"
  out
}
GESI_NONE <- "The document does not address gender equality or social inclusion."
clean_gesi <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[1]) || !nzchar(trimws(as.character(x[1]))))
    return(GESI_NONE)
  trimws(as.character(x[1]))
}
# location_notes must always carry something verbatim about the locations;
# the geographic scope quote is the fallback when the model leaves it empty
clean_location_notes <- function(notes, scope_stated = "") {
  n <- trimws(as.character(notes %||% ""))
  if (nzchar(n)) return(n)
  s <- trimws(as.character(scope_stated %||% ""))
  if (nzchar(s)) return(s)
  ""
}
