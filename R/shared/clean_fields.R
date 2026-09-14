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

# A shouted banner is any run of two or more consecutive SHOUTED words, so
# "CULTIVATING RESILIENCE The Journey of..." is de-shouted down to its banner
# while a lone acronym ("Support to NPCA TerrAfrica Secretariat") is left be.
is_shouted_tok <- function(t) {
  lt <- gsub("[^A-Za-z]", "", t)
  nchar(lt) >= 3 && lt == toupper(lt) && !toupper(lt) %in% KNOWN_ACRONYMS
}
deshout_runs <- function(x) {
  toks <- strsplit(x, " ", fixed = TRUE)[[1]]
  if (length(toks) < 2) return(x)
  sh <- vapply(toks, is_shouted_tok, logical(1), USE.NAMES = FALSE)
  r <- rle(sh)
  ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1L
  for (j in which(r$values & r$lengths >= 2L))
    for (i in starts[j]:ends[j])
      toks[i] <- title_case_one(toks[i], i == 1L)
  paste(toks, collapse = " ")
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
  x <- deshout_runs(x)
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

## ---- beneficiaries ----------------------------------------------------------
# A ministry, an agency or a programme team is the CHANNEL, not the group the
# project is ultimately for. Documents usually say who that is - "to improve
# the livelihoods of the rural population", "direct project beneficiaries" -
# so an institution-only answer means the ultimate group was not looked for.
INSTITUTIONAL_RX <- paste0(
  "\\b(ministr|ministry|government|governments|agency|agencies|authority|",
  "secretariat|directorate|department|programme teams?|program teams?|",
  "project teams?|national teams?|country teams?|national stakeholders?|stakeholders?|",
  "member countries|institution|institutions|institutional|council|board|",
  "committee|commission|bureau|unit|staff|officers?|inspectors?|rangers?|",
  "researchers?|scientists?|extension (agents?|officers?|workers?|staff)|",
  "partners?|platform|consultants?|technicians?)\\b")
# Stems are left open on the right: a closing \\b after "communit" or
# "beneficiar" never matches "communities" or "beneficiaries", which is how
# this regex quietly failed to see the very words it was looking for. Only
# the entries that need protection from a longer word keep their boundary
# ("men" must not match "mentioned").
END_GROUP_RX <- paste0("\\b(farmer|smallholder|small-?holder|producer|",
  "household|communit|women|youth|villager|pastoralist|herder|fisher|",
  "fisherfolk|beneficiar|population|people|famil(y|ies)|cooperativ|",
  "association member|group member|vulnerable|children|elderly|migrant|",
  "indigenous|men\\b|poor\\b)")
# TRUE when the stated beneficiary names only intermediaries, with no end group
is_institution_only <- function(stated) {
  s <- tolower(trimws(as.character(stated %||% "")))
  if (!nzchar(s)) return(FALSE)
  grepl(INSTITUTIONAL_RX, s) && !grepl(END_GROUP_RX, s)
}
# Wider net: TRUE when the passage names no group of people at all. A
# document line reading "Beneficiary: 4 LCBC countries: Cameroon, Niger,
# Nigeria and Chad" names a geography, and mapping that to the nearest
# vocabulary option silently invents an answer.
names_no_people <- function(stated) {
  s <- tolower(trimws(as.character(stated %||% "")))
  # a field label is not a group: "7. Beneficiary : 4 LCBC countries" names
  # countries, and the word "Beneficiary" in front of it proves nothing
  s <- sub("^[0-9.() ]*(target |primary |direct |main )*beneficiar(y|ies)[ ]*[:.-][ ]*",
           "", s)
  nzchar(s) && !grepl(END_GROUP_RX, s)
}

# Keyword reading of a passage into the template's beneficiary vocabulary.
# Returns "" when nothing matches or when several groups tie, so a judgement
# call still goes to the model rather than being guessed here.
detect_beneficiary <- function(txt) {
  t <- tolower(paste(as.character(txt), collapse = " "))
  pat <- c(
    "subsistence farmer" = "subsistence farm",
    "smallholder farmer" = "smallholder|small-?scale farm|small-?holder",
    "artisanal fisher" = "artisanal fish|small-?scale fish",
    "pastoralist/herder" = "pastoralist|herder",
    "farmer association" = "farmer associations?\\b",
    "farmer group" = "farmer groups?\\b",
    "producer organization" = "producer organi",
    "cooperative" = "cooperativ",
    "women's group/organization" = "women'?s group|women'?s organi",
    "women (female-headed households)" = "female-?headed",
    "youth" = "\\byouth\\b|young people",
    "household" = "households?\\b",
    "indigenous peoples" = "indigenous",
    "agribusiness" = "agribusiness|agri-?enterprise",
    "farm laborer" = "farm labou?rer",
    "children" = "\\bchildren\\b", "elderly" = "elderly", "migrant" = "migrant",
    "people with disabilities/ disability" = "disabilit",
    "vulnerable population" = "vulnerable",
    "community" = "communit")
  hit <- names(pat)[vapply(pat, function(p) grepl(p, t), logical(1))]
  if (!length(hit)) return("")
  hit[1]   # pat is ordered most specific first
}

## ---- results: coverage is not achievement ------------------------------------
# "20 pilot villages" says WHERE the project worked, not what it changed. A
# place count is a result only when the document reports something achieved at
# those places (adopted, established, trained, restored), not when it merely
# targets, selects or covers them.
PLACE_UNIT_RX <- paste0("\\b(villages?|districts?|countries|country|sites?|",
  "regions?|provinces?|communities|communes?|towns?|cities|city|wards?|",
  "sub-?counties|locations?|areas?|zones?|landscapes?|watersheds?)\\b")
# stems with an open suffix: a trailing \\b would stop "clarifi" matching
# "clarified", which is how these lists quietly fail
ACHIEVED_RX <- paste0("\\b(adopt|establish|form|train|receiv|restor|",
  "rehabilitat|construct|built|build|deliver|implement|achiev|complet|",
  "operational|function|certifi|registr|register|licens|reach|benefit|",
  "produc|increas|reduc|improv|protect|conserv|clarifi|secur|demarcat|",
  "gazett|mapp|sign|launch|install|equipp|suppli|distribut|provid|",
  "carried out|conduct|practis|practic|harvest|plant|irrigat)[a-z]*")
TARGETING_RX <- paste0("\\b(target|select|chosen|choose|identif|plann|",
  "intend|foreseen|propos|cover|worked in|operates? in|present in|",
  "pilot(ed)? in|scope|comprising|consisting)[a-z]*")
is_coverage_not_result <- function(value, unit, stated = "") {
  u <- tolower(paste(unit %||% ""))
  s <- tolower(paste(stated %||% ""))
  if (!nzchar(trimws(paste(u, s)))) return(FALSE)
  if (!grepl(PLACE_UNIT_RX, u)) return(FALSE)      # only place-counted values
  both <- paste(u, s)
  if (grepl(TARGETING_RX, both) && !grepl(ACHIEVED_RX, both)) return(TRUE)
  if (!grepl(ACHIEVED_RX, both)) return(TRUE)       # nothing was achieved there
  # something WAS achieved: the place count is the result only when it is what
  # the sentence counts. "500 barges supplied ... in 77 villages" counts barges,
  # so 77 is coverage; "tenure clarified in 20 villages" counts villages.
  v <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", as.character(value))))
  nums <- suppressWarnings(as.numeric(gsub(",", "",
            regmatches(s, gregexpr("[0-9][0-9,]*(\\.[0-9]+)?", s))[[1]])))
  nums <- nums[!is.na(nums)]
  if (is.na(v) || !length(nums)) return(FALSE)      # cannot tell: keep it
  !identical(nums[1], v)
}

## ---- one gate for "is this actually a result?" -------------------------------
# Returns "" when the value is a real result, otherwise the reason to reject it.
# Used by both pipelines so the two sheets apply the same test.
result_reject_reason <- function(value, unit, stated = "") {
  v <- tolower(trimws(as.character(value %||% "")))
  m <- tolower(paste(unit %||% "", stated %||% ""))
  if (!nzchar(v) && !nzchar(trimws(m))) return("")
  if (grepl(paste0("\\b(rating|ratings|score|scored|scoring|scale of|likert|",
                   "out of (5|4|6|10)|satisfactor|unsatisfactor|",
                   "highly likely|negligible)\\b"), m) ||
      grepl("scale|rating", v))
    return("RATING NOT A RESULT")
  if (grepl(paste0("us\\$|usd|eur|cfaf|mzn|\\bua\\b|disburs|budget|",
                   "grant amount|expenditure|cost of"), m) &&
      !grepl("income|revenue|price|saving|profit", m))
    return("MONEY NOT A RESULT")
  if (grepl("[0-9]\\s*-?\\s*(month|week|year)s?\\b", v) ||
      grepl("duration|extension|closing date", m))
    return("DURATION NOT A RESULT")
  if (grepl("compensat|resettl|expropriat|displaced person", m))
    return("COMPENSATION NOT A RESULT")
  if (grepl(paste0("\\b(reports?|meetings?|missions?|recommendations?|",
                   "audits?|supervision)\\b"), m) &&
      !grepl("beneficiar|farmer|train|hectare|household|workshop", m))
    return("ADMIN COUNT NOT A RESULT")
  # a yes/no milestone indicator ("platform is up: Y") carries no quantity
  if (grepl("^(y|n|yes|no|true|false|achieved|not achieved)$", v) ||
      grepl("yes\\s*/\\s*no|y\\s*/\\s*n\\b|binary indicator", m))
    return("YES/NO INDICATOR NOT A RESULT")
  if (is_coverage_not_result(value, unit, stated))
    return("COVERAGE NOT A RESULT - says where, not what changed")
  ""
}

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
  # a word the PDF broke over a line end ("ag- ricultural"): no space before
  # the hyphen, one after, letters on both sides. A real aside (" - ") has a
  # space on both sides and a real compound ("climate-smart") has none.
  split_word <- grepl("[a-z]- [a-z]", s)
  if (split_word) s <- gsub("([a-z])- ([a-z])", "\\1\\2", s)
  out$value <- s
  notes <- c(if (had) "CHARACTER ARTIFACT REPAIRED - check punctuation",
             if (split_word) "WORD REJOINED ACROSS A LINE BREAK - check spelling")
  if (length(notes)) out$note <- paste(notes, collapse = "; ")
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
# the count and the note must tell one story: a note whose leading number
# disagrees with location_count, without saying why, is flagged for review
check_count_vs_notes <- function(count, notes) {
  cnt <- suppressWarnings(as.integer(gsub("[^0-9]", "", as.character(count %||% ""))))
  n <- as.character(notes %||% "")
  if (is.na(cnt) || !nzchar(n)) return("")
  # page citations are not counts of anything
  n <- gsub("\\[[^]]*\\b(page|pages|p|pp)\\b[^]]*\\]", " ", n, ignore.case = TRUE)
  n <- gsub("\\((?:[^()]*\\b(?:page|pages|p|pp)\\b[^()]*)\\)", " ", n,
            ignore.case = TRUE, perl = TRUE)
  n <- gsub("\\b(page|pages|pp?)\\.?\\s*[0-9]+(\\s*[-]\\s*[0-9]+)?", " ", n,
            ignore.case = TRUE)
  # the count is often written out in the same sentence ("five districts")
  words <- c(one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7,
             eight = 8, nine = 9, ten = 10, eleven = 11, twelve = 12,
             thirteen = 13, fourteen = 14, fifteen = 15, sixteen = 16,
             seventeen = 17, eighteen = 18, nineteen = 19, twenty = 20)
  for (w in names(words))
    n <- gsub(paste0("\\b", w, "\\b"), words[[w]], n, ignore.case = TRUE)
  nums <- suppressWarnings(as.integer(regmatches(n, gregexpr("\\b[0-9]{1,4}\\b", n))[[1]]))
  nums <- nums[!is.na(nums)]
  if (!length(nums) || cnt %in% nums) return("")
  # an explicit reconciliation ("15 of the 26", "of which") is acceptable
  if (grepl("\\bof (the )?[0-9]|of which|out of\\b|\\bpartial\\b|\\bincluding\\b",
            tolower(n))) return("")
  paste0("COUNT AND NOTES DISAGREE: count ", cnt,
         ", notes mention ", paste(unique(nums), collapse = "/"))
}
