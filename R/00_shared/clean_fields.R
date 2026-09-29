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
  # "42 270" and "301 183" are thousands separated by a space, the French
  # convention and common in the AfDB and GEF documents. Without this the
  # first group alone became the value, so 42 270 was silently stored as 42.
  low <- gsub("(?<=[0-9]) (?=[0-9]{3}\\b)", "", low, perl = TRUE)
  # a result written as a word ("Three extension agents") still has to reach
  # the sheet as a bare digit
  WORDNUM <- c(one = 1, two = 2, three = 3, four = 4, five = 5, six = 6,
               seven = 7, eight = 8, nine = 9, ten = 10, eleven = 11,
               twelve = 12, fifteen = 15, twenty = 20, thirty = 30,
               forty = 40, fifty = 50, hundred = 100)
  w <- gsub("[^a-z]", "", low)
  if (nzchar(w) && w %in% names(WORDNUM) && !grepl("[0-9]", low)) {
    out$value <- as.character(WORDNUM[[w]])
    out$note  <- paste0("NUMBER WORD IN SOURCE: ", s)
    return(out)
  }
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
  # a nil result may be a genuine failed indicator (which IS a finding) or a
  # placeholder the report never filled in - only a person can tell, so flag it
  # without discarding whatever note is already there
  if (v == 0) out$note <- trimws(paste(out$note,
    paste0("ZERO VALUE - confirm real nil, not placeholder: ", s)))
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
# "beneficiaries", "people", "population", "end-users" are not groups, they
# are counting words. A results-framework line reading "Number of direct
# project beneficiaries - Comoros (target: 10,000)" names nobody, and if it
# is allowed to count as naming people the model has to guess a category.
SPECIFIC_GROUP_RX <- paste0("\\b(farmer|smallholder|small-?holder|producer|",
  "household|communit|women|youth|villager|pastoralist|herder|fisher|",
  "fisherfolk|famil(y|ies)|cooperativ|association member|group member|",
  "vulnerable|children|elderly|migrant|indigenous|men\\b|poor\\b)")

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
  nzchar(s) && !grepl(SPECIFIC_GROUP_RX, s)
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

## A result value that is nothing but a date. Month names in English and
## French, because a good part of the AfDB corpus is French.
DATE_VALUE_RE <- paste0(
  "^\\s*(\\d{1,2}\\s+)?(january|february|march|april|may|june|july|august|",
  "september|october|november|december|janvier|f.vrier|mars|avril|mai|juin|",
  "juillet|ao.t|septembre|octobre|novembre|d.cembre)\\s+(19|20)\\d{2}\\s*$|",
  "^\\s*(19|20)\\d{2}[-/]\\d{1,2}[-/]\\d{1,2}\\s*$|",
  "^\\s*\\d{1,2}[-/]\\d{1,2}[-/](19|20)?\\d{2}\\s*$")

## ---- one gate for "is this actually a result?" -------------------------------
# Returns "" when the value is a real result, otherwise the reason to reject it.
# Used by both pipelines so the two sheets apply the same test.
result_reject_reason <- function(value, unit, stated = "", metric = "") {
  v <- tolower(trimws(as.character(value %||% "")))
  # the harmonised metric is evidence too: "project duration" and
  # "time to reach beneficiaries" announce themselves there, not in the
  # verbatim wording the gate used to see on its own
  m <- tolower(paste(unit %||% "", stated %||% "", metric %||% ""))
  if (!nzchar(v) && !nzchar(trimws(m))) return("")
  if (grepl(paste0("\\b(rating|ratings|score|scored|scoring|scale of|likert|",
                   "out of (5|4|6|10)|satisfactor(y|ily)?|unsatisfactor(y|ily)?|rated|",
                   "highly likely|negligible)\\b"), m) ||
      grepl("scale|rating", v))
    return("RATING NOT A RESULT")
  if (grepl(paste0("us ?\\$|\\$ ?[0-9]|dollars?|usd|eur|cfaf|mzn|\\bua\\b|disburs|budget|",
                   "grant amount|expenditure|cost of|contribution of|fund contribution"), m) &&
      !grepl("income|revenue|price|saving|profit", m))
    return("MONEY NOT A RESULT")
  # A bare "extension" also names extension agents, extension workers and
  # extension services, which ARE results ("extension agents trained" is one
  # of the template's own metrics), so only time-extension wording counts.
  # A value that is only a date is rejected too: a closing date is not an
  # achievement.
  if (grepl("[0-9]\\s*-?\\s*(month|week|year)s?\\b", v) ||
      grepl(DATE_VALUE_RE, v) ||
      grepl(paste0("duration|closing date|completion date|elapsed|",
                   "\\btime to (reach|complete|deliver|first)|",
                   "(no[- ]cost|time|period|deadline|month)\\s*extension|",
                   "extension (of|to) the (closing|completion|project)"), m))
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

## ---- funding mechanism portion ----------------------------------------------
# The template allows only five instrument types, and its own example shows how
# an unlisted one is written: "grant (40%) + loan (40%) + other-in-kind
# contribution (20%)". So anything outside the five keeps its wording behind the
# "other-" prefix rather than being invented as a new category. Entries are NOT
# merged: two grants from different funders stay listed separately, which is
# what the sheet is for.
FUNDING_OPTIONS <- c("blended", "grant", "investment", "loan", "other")
map_portion_label <- function(lbl) {
  l <- tolower(trimws(lbl))
  if (!nzchar(l)) return("")
  if (grepl("blend", l)) return("blended")
  if (grepl("\\bloans?\\b|\\bcredits?\\b|cr.dit|pr.t|borrow|concessional lend", l)) return("loan")
  if (grepl("\\bgrants?\\b|subvention|\\bdons?\\b|non-repayable", l)) return("grant")
  if (grepl("investment|equity|\\bbonds?\\b|capital injection", l)) return("investment")
  paste0("other-", sub("^other[- ]+", "", l))
}
clean_funding_portion <- function(x) {
  out <- list(value = "", note = "")
  s <- trimws(as.character(x %||% ""))
  if (!nzchar(s)) return(out)
  parts <- trimws(strsplit(s, "+", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(out)
  changed <- character(0)
  new <- vapply(parts, function(pt) {
    pct <- regmatches(pt, regexpr("\\([^)]*\\)$", pt))
    lbl <- trimws(sub("\\([^)]*\\)$", "", pt))
    mapped <- map_portion_label(lbl)
    if (!nzchar(mapped)) return("")
    if (tolower(lbl) != mapped) changed <<- c(changed, paste0(lbl, " -> ", mapped))
    trimws(paste0(mapped, if (length(pct)) paste0(" ", pct) else ""))
  }, character(1), USE.NAMES = FALSE)
  new <- new[nzchar(new)]
  out$value <- paste(new, collapse = " + ")
  if (length(changed))
    out$note <- paste0("funding_mechanism_portion recoded: ",
                       paste(changed, collapse = "; "))
  out
}


## ---- a result must say what it counts -------------------------------------
# A unit on its own is not information: "100 / percentage" tells a reader
# nothing. Session 1 sometimes puts a unit word where the metric belongs
# (P005 answered "Percent"), and Session 2 sometimes answers NOT STATED for a
# metric the extract does state but the 27-option list has no home for. Either
# way the cell arrives empty, so the floor below guarantees that a value always
# carries a label a person can read - as a CANDIDATE, which is what the review
# queue is for, never as an invented controlled value.
UNIT_WORDS <- paste0("^(percent|percentage|%|number|numbers|count|counts|",
                     "quantity|total|totals|value|values|unit|units|no[.]?|",
                     "nb|ratio|rate|index|score|amount)$")
is_unit_word <- function(x) grepl(UNIT_WORDS, tolower(trimws(as.character(x))))

metric_floor <- function(metric, metric_stated, scope = "") {
  m <- trimws(as.character(metric %||% ""))
  if (nzchar(m)) return(m)
  lab <- trimws(as.character(metric_stated %||% ""))
  if (!nzchar(lab) || is_unit_word(lab)) lab <- trimws(as.character(scope %||% ""))
  if (!nzchar(lab)) return("CANDIDATE: unlabelled result")
  w <- strsplit(trimws(gsub("[^A-Za-z0-9 %/-]", " ", lab)), " +")[[1]]
  w <- w[nzchar(w)]
  if (!length(w)) return("CANDIDATE: unlabelled result")
  paste0("CANDIDATE: ", paste(utils::head(w, 6), collapse = " "))
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

## ---- money ------------------------------------------------------------------
# Money is plain digits everywhere in the pipeline: 33000000, never 3.3e+07.
# R writes a numeric 33000000 as "3.3e+07" the moment as.character() touches
# it, which once leaked into budget_total and budget_notes (Charity pilot,
# 28 Sep 2026). Parse with money_num(), write with format_money(). Cases in
# R/08_quality/test_regressions.R.
money_num <- function(x) {
  if (is.numeric(x)) return(x)
  x <- tolower(trimws(as.character(x)))
  sci <- grepl("^[0-9.]+e[+-]?[0-9]+$", x)
  out <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", x)))
  out[sci] <- suppressWarnings(as.numeric(x[sci]))
  out
}
format_money <- function(n) {
  n <- money_num(n)
  whole <- !is.na(n) & abs(n - round(n)) < 1e-9
  out <- rep("", length(n))
  out[whole] <- formatC(n[whole], format = "f", digits = 0)
  out[!is.na(n) & !whole] <- formatC(n[!is.na(n) & !whole], format = "f", digits = 2)
  trimws(out)
}
# "lead N; cofinancing N" (QC question 7, 28 Sep 2026): empty when the document
# gives no lead share or the share is not below the total
budget_notes_for <- function(total, lead) {
  bt <- money_num(total); bl <- money_num(lead)
  ok <- !is.na(bl) & bl > 0 & (is.na(bt) | bl < bt)
  out <- rep("", length(bl))
  both <- ok & !is.na(bt)
  out[both] <- paste0("lead ", format_money(bl[both]), "; cofinancing ", format_money(bt[both] - bl[both]))
  out[ok & is.na(bt)] <- paste0("lead ", format_money(bl[ok & is.na(bt)]))
  out
}

## ---- beneficiary metrics by rule --------------------------------------------
# The references word people counts the same way every time: "direct" makes
# direct beneficiaries; "reached", "total" or a count of men and women together
# makes total beneficiaries; women or female makes women beneficiaries; youth
# makes youth beneficiaries; households makes vulnerable households; farmers
# who benefited or adopted makes smallholder farmers reached. The model used to
# answer total or direct at random for the same wording (Charity pilot re-run,
# 28 Sep 2026). Returns "" when the rule does not apply.
map_people_metric_det <- function(x) {
  x <- tolower(paste(x, collapse = " "))
  if (!nzchar(trimws(x))) return("")
  if (grepl("of which|dont ", x)) return("")
  people <- grepl("beneficiar|benefit(t)?(ing|ed)|people|persons|individuals|reached|served|registered", x)
  both <- grepl("males? and females?|females? and males?|men and women|women and men|hommes et femmes|by gender|by sex", x)
  if (grepl("women|female|femmes|girls", x) && !both && people) return("women beneficiaries")
  if (grepl("youth|young people|jeunes|young men|young women", x) && !both && people) return("youth beneficiaries")
  if (grepl("household|menage|ménage", x) && grepl("beneficiar|benefit|reached|supported|served|assisted|targeted|considered", x)) return("vulnerable households")
  if (grepl("direct", x) && grepl("beneficiar|benefit", x)) return("direct beneficiaries")
  if (both && grepl("beneficiar|benefit", x)) return("total beneficiaries")
  if (grepl("beneficiar|benefit(t)?(ing|ed)", x) && grepl("reached|total|cumulative|indirect", x)) return("total beneficiaries")
  if (grepl("beneficiar|people with access|people (reached|served|supported)|registered beneficiar|people &|people and livestock", x)) return("direct beneficiaries")
  if (grepl("farmers?|farm managers?|smallholders?|producers?|agriculteurs?|producteurs?", x) && grepl("benefit|reached|adopt|supported|assisted|bénéfici", x) && !grepl("group|organi|cooperativ|association", x)) return("smallholder farmers reached")
  ""
}

## ---- template-exact strings ---------------------------------------------------
# The template writes two document types with a non-breaking hyphen (U+2011) and
# the emissions unit with a subscript two (U+2082). The pipeline uses plain
# ASCII inside; the export writes the template's own characters so that filters
# and pivots in the template line up. (Vocabulary review, 28 Sep 2026)
TEMPLATE_EXACT <- c("mid-term evaluation" = "mid\u2011term evaluation",
                    "multi-country synthesis" = "multi\u2011country synthesis",
                    "tCO2e" = "tCO\u2082e")
template_exact <- function(x) {
  x <- as.character(x); k <- x %in% names(TEMPLATE_EXACT)
  x[k] <- unname(TEMPLATE_EXACT[x[k]]); x
}
template_ascii <- function(x) {
  x <- as.character(x); k <- x %in% TEMPLATE_EXACT
  x[k] <- names(TEMPLATE_EXACT)[match(x[k], TEMPLATE_EXACT)]; x
}

## ---- units: a count noun is a quantity ------------------------------------------
# "policies", "villages", "weather stations", "training days" are counts; the
# template's unit for a count is quantity. Only measure words keep a candidate
# unit (kilometres, tons per hectare) for the team to decide on.
UNIT_MEASURE_RE <- "percent|%|\\bha\\b|hectare|\\bkg|\\bton|litre|liter|\\bm3\\b|cubic|\\bkm|kilomet|metre|meter|/|\\bper\\b|score|scale|ratio|\\brate|index|\\byes\\b|\\bno\\b|tco|co2|month|year|usd|eur|\\bua\\b|\\$|\\bmho\\b|\\bmtd\\b"
unit_count_fallback <- function(stated, mapped) {
  st <- tolower(trimws(as.character(stated %||% ""))); mp <- as.character(mapped %||% "")
  open <- startsWith(mp, "CANDIDATE:") || !nzchar(mp) || toupper(mp) == "NOT STATED"
  if (!open || !nzchar(st)) return(mp)
  if (grepl(UNIT_MEASURE_RE, st)) return(mp)
  "quantity"
}

## ---- candidate labels ----------------------------------------------------------
# A candidate label names what was counted: no digits, no percent signs, no
# qualifiers copied from the sentence ("as low as 39% for Maize"). A label that
# is only a unit word (percentage, number) says nothing and is dropped.
clean_candidate_label <- function(x) {
  x <- as.character(x); k <- startsWith(x, "CANDIDATE:")
  if (!any(k)) return(x)
  lab <- trimws(sub("^CANDIDATE:\\s*", "", x[k]))
  lab <- gsub("[0-9][0-9.,]*\\s*%?", "", lab)
  lab <- sub("^(as (low|high) as|over|more than|nearly|approximately|about|almost|around|up to|at least|for|of|the)\\s+", "", lab, ignore.case = TRUE)
  lab <- sub("^(as (low|high) as|over|more than|nearly|approximately|about|almost|around|up to|at least|for|of|the)\\s+", "", lab, ignore.case = TRUE)
  lab <- trimws(gsub("\\s+", " ", lab))
  unit_words <- c("percent", "percentage", "number", "quantity", "count", "total", "nbr", "%", "value")
  x[k] <- ifelse(nzchar(lab) & !tolower(lab) %in% unit_words, paste0("CANDIDATE: ", lab), "")
  x
}

## ---- a people metric never carries a measure unit ---------------------------------
# "vulnerable households [hectares]" and "direct beneficiaries [percentage]" are
# contradictions: the unit says land or an index, the metric says people. The
# metric goes back to a candidate built from the stated wording. (28 Sep 2026)
MEASURE_UNITS <- c("hectares", "tons", "kg", "kg/hectare", "liters", "tCO2e", "percentage")
PEOPLE_METRIC_OPTIONS <- c("direct beneficiaries", "total beneficiaries", "women beneficiaries",
  "youth beneficiaries", "smallholder farmers reached", "vulnerable households", "crop producers",
  "livestock producers", "fishers", "processors", "wholesalers", "association members", "extension agents trained")
stated_is_measure <- function(stated_unit) {
  u <- tolower(trimws(as.character(stated_unit %||% "")))
  grepl(UNIT_MEASURE_RE, u) & !grepl("^%|percent|pour ?cent", u)   # a percentage share of people is still about people
}
squish <- function(x) trimws(gsub("\\s+", " ", as.character(x %||% "")))
# A candidate carries the document's exact wording (Lolita, 29 Sep 2026): the
# team decides later whether it becomes an option, and a made-up label would
# hide what the document said.
candidate_verbatim <- function(mapped, stated) {
  mapped <- as.character(mapped); stated <- squish(stated)
  k <- (startsWith(mapped, "CANDIDATE:") | !nzchar(mapped)) & nzchar(stated)
  mapped[k] <- paste0("CANDIDATE: ", substr(stated[k], 1, 160))
  mapped
}
metric_unit_consistent <- function(metric, unit, stated_metric) {
  metric <- as.character(metric); unit <- as.character(unit)
  clash <- metric %in% PEOPLE_METRIC_OPTIONS & (unit %in% MEASURE_UNITS | startsWith(unit, "CANDIDATE:")) &
           !(metric %in% c("women beneficiaries", "youth beneficiaries") & unit == "percentage")
  if (!any(clash)) return(metric)
  metric[clash] <- candidate_verbatim("", stated_metric[clash])
  metric
}

## ---- result metrics by rule -----------------------------------------------------
# When the document's wording says which template option it is, the option is
# chosen here and the model is not asked. Area units select among the land
# options; rate units select the yield option; head nouns select the people,
# organisation and effect options. Returns "" when no rule applies, and never
# an option that is not in the template. (29 Sep 2026)
METRIC_AREA_UNIT_RE <- "\\bha\\b|hectare|superficie|\\bhas\\b|acres?\\b"
metric_head <- function(m) {
  m <- tolower(squish(m))
  m <- sub("^\\s*((indicator|output|outcome|result|pdo|io)\\s*)?[a-z]?[0-9]+(\\.[0-9]+)*[.:)]?\\s*", "", m)
  m <- sub("^(number|nombre|no\\.?|total( number)?|cumulative( number)?|share|percentage|proportion|area|volume|quantity|increase|decrease|change)\\s*(of|de|in|d')?\\s*", "", m)
  m
}
map_metric_det <- function(stated_metric, stated_unit = "") {
  m <- tolower(squish(stated_metric)); u <- tolower(squish(stated_unit)); mu <- paste(m, u)
  if (!nzchar(m)) return("")
  head <- metric_head(m)
  area <- grepl(METRIC_AREA_UNIT_RE, u) || (grepl(METRIC_AREA_UNIT_RE, m) && !grepl("per hectare|/ha|kg/|t/", mu))
  rate <- grepl("kg/ha|t/ha|kg per ha|tons? per ha|per hectare|q/ha|quintal|\\bmho\\b", mu) || grepl("^%|percent", u)
  # land options, decided by the unit
  if (area) {
    if (grepl("landscapes? under improved (practices|management)", m)) return("biodiversity landscapes conserved")
    if (grepl("protected area", m) && !grepl("excluding protected", m)) return("terrestrial protected areas")
    if (grepl("restor|rehabilitat|reforest|afforest|regenerat|reclaim|degraded|dunes? fixed|fixed dunes|stabili[sz]ed", m)) return("land restored")
    if (grepl("irrigat|drainage", m)) return("irrigated land")
    if (grepl("climate.?smart|climate.?resilient|resilient (crops?|practices|agricultur|technolog)|sustainable land|sustainable landscape|land and water management|\\bslw?m\\b|improved (land|agricultural|farming|soil) (management|practices|technolog)|agroforestry|soil and water conservation|conservation agriculture|under (new|improved) technolog|improved technolog|adaptation practices|csa\\b", m)) return("land under climate-smart practices")
    if (grepl("biodivers|conserv|ecosystem|habitat|mangrove|wetland|forest|rangeland|pasture|watershed|catchment", m) ||
        (grepl("marine|coastal|landscape", m) && grepl("conserv|manag|protect|restor", m))) return("biodiversity landscapes conserved")
    return("")
  }
  if (grepl("^(jobs?|employment|emplois|green jobs)", head) || grepl("jobs? created|employment created|emplois cr", m) || grepl("^jobs?$", u)) return("jobs created")
  # a people unit is a people count whatever else the sentence mentions
  people_unit <- nzchar(u) && grepl("farmer|farm manager|producer|household|beneficiar|people|persons|individuals|women|men\\b|youth|members|participants|trainees|pastoralist|fisher|agripreneur|jobs|students|staff", u)
  if (people_unit) {
    if (grepl("^(farm managers?|farmers?|smallholders?|producers?|agricult|producteurs?)", head) || grepl("farm managers|farmers|producers", u)) return("smallholder farmers reached")
    return("")
  }
  # effects
  yield_head <- grepl("^((average|mean|crop|increased?|increase in|improved|higher) )*(yields?|rendements?|productivity)\\b", head)
  if (yield_head || (rate && grepl("yield|rendement", m)) || grepl("\\bmho\\b|kg/ha|t/ha", mu)) return("crop yield increase")
  if (grepl("\\bincome|revenue|revenu|earnings", m) && !grepl("share of|spen[dt]|expenditure|of (their|the|household) income|cost", m)) return("income increase")
  if (grepl("post.?harvest loss|harvest loss|storage loss|losses? reduc|reduc.* loss", m)) return("harvest loss reduced")
  if (grepl("\\bpest|disease (incidence|prevalence|reduc|control)|armyworm|locust|infestation", m) && !grepl("human|hiv|malaria", m)) return("pest/disease reduction")
  if (grepl("soil organic|organic matter|soil carbon|soil fertility|soil health", m)) return("soil organic matter improved")
  # people and organisation counts, by head noun
  if (grepl("^(jobs?|employment|emplois|green jobs)", head) || grepl("jobs? created|employment created|emplois cr", m)) return("jobs created")
  if (grepl("extension (agents?|workers?|officers?|staff)|advisory agents?|agents de vulgarisation|conseillers agricoles", m)) return("extension agents trained")
  if (grepl("^(members of|association members|membres)|members of (the )?(associations?|cooperatives?|groups?)", head)) return("association members")
  if (grepl("^cooperatives?\\b", head) && !grepl("members", head)) return("cooperatives reached")
  if (grepl("^(farmer|farmers'?|producer|women'?s?|youth|common interest|self.?help|savings|water users?'?) (groups?|associations?)|^groupements?|^\\bwuas?\\b|^\\bcigs?\\b|^vslas?\\b|^clubs?\\b", head)) return("farmer groups")
  if (grepl("^(producer|farmer|farmers'?|fisher|fishers'?) organi|^organi[sz]ations? (of|de) (producers|farmers)|^associations?\\b|^unions?\\b|^federations?\\b|^cooperatives? and associations", head)) return("producer organizations")
  if (grepl("^(crop|maize|rice|cassava|sorghum|millet|wheat|vegetable|horticultur|cereal|coffee|cocoa|cashew|potato|bean) (farmers|producers|growers)", head)) return("crop producers")
  if (grepl("^(livestock|pastoral|herders?|dairy|cattle|poultry|small ruminant|animal) (farmers|producers|keepers|owners|herders)|^pastoralists?", head)) return("livestock producers")
  if (grepl("^(fishers?|fishermen|fisherfolk|fishing (communit|households)|artisanal fishers?|p\u00eacheurs)", head)) return("fishers")
  if (grepl("^(processors?|transformateurs|agro.?processors?)", head)) return("processors")
  if (grepl("^(wholesalers?|traders|grossistes|commer\u00e7ants)", head)) return("wholesalers")
  ""
}

## ---- an option must fit the thing counted --------------------------------------
# The model sometimes picks an option for a count of something else: 17,980 land
# titles issued to associations became "producer organizations". The head noun
# of the stated metric must be compatible with the kind of option.
METRIC_KIND <- c(
  "direct beneficiaries" = "people", "total beneficiaries" = "people", "women beneficiaries" = "people",
  "youth beneficiaries" = "people", "smallholder farmers reached" = "people", "vulnerable households" = "people",
  "crop producers" = "people", "livestock producers" = "people", "fishers" = "people", "processors" = "people",
  "wholesalers" = "people", "association members" = "people", "extension agents trained" = "people",
  "cooperatives reached" = "org", "farmer groups" = "org", "producer organizations" = "org",
  "biodiversity landscapes conserved" = "land", "irrigated land" = "land", "land restored" = "land",
  "land under climate-smart practices" = "land", "terrestrial protected areas" = "land",
  "crop yield increase" = "rate", "income increase" = "rate", "harvest loss reduced" = "rate",
  "pest/disease reduction" = "rate", "soil organic matter improved" = "rate", "jobs created" = "jobs")
NOT_PEOPLE_OR_ORG_RE <- paste0(
  "^([a-z'-]+ ){0,4}(titles?|certificates?|deeds?)\\b|^(polic|plans?|strateg|laws?|decrees?|agreements?|technolog|products?|",
  "reports?|events?|stations?|wells?|boreholes?|dams?|schemes?|structures?|markets?|centres?|centers?|",
  "seeds?|inputs?|kits?|fertili|animals?|cattle|livestock|goats|sheep|poultry|trees?|seedlings?|plots?|",
  "hectares?|\\bha\\b|km\\b|kilomet|tons?|tonnes|kg\\b|litres?|liters?|cubic|m3|villages?|districts?|countries|communes?|sites?)")
metric_option_conflict <- function(option, stated_metric, unit = "") {
  option <- as.character(option); kind <- unname(METRIC_KIND[option]); kind[is.na(kind)] <- ""
  head <- vapply(stated_metric, metric_head, character(1), USE.NAMES = FALSE)
  unit <- as.character(unit)
  bad <- (kind %in% c("people", "org") & grepl(NOT_PEOPLE_OR_ORG_RE, head)) |
         (kind == "land" & nzchar(unit) & !unit %in% c("hectares", "") & !startsWith(unit, "CANDIDATE:") & !grepl(METRIC_AREA_UNIT_RE, tolower(stated_metric))) |
         (kind == "org" & grepl("^(members|membres)", head))
  bad[is.na(bad)] <- FALSE
  bad
}

## ---- units by rule (moved from harmonize.R, 29 Sep 2026) ----------------------
# AfDB result tables abbreviate units: mho is metric tons per hectare (not
# siemens), mtd metric tons, nbr number (Charity pilot, 28 Sep 2026)
unit_syn <- c("mho" = "CANDIDATE: mho", "mtd" = "tons", "nbr" = "quantity",
  "mt" = "tons", "metric tons" = "tons", "metric tonnes" = "tons", "metric ton" = "tons",
  "t co2e" = "tCO2e", "tco2" = "tCO2e", "tonnes of co2" = "tCO2e", "tonnes co2e" = "tCO2e",
  "women" = "individuals", "men" = "individuals", "youth" = "individuals", "participants" = "individuals",
  "trainees" = "individuals", "members" = "individuals", "producers" = "individuals", "pastoralists" = "individuals",
  "fishers" = "individuals", "students" = "individuals", "staff" = "individuals", "agripreneurs" = "individuals",
  "jobs" = "individuals", "males and females" = "individuals", "registered beneficiaries" = "individuals",
  "associations" = "organizations", "cooperatives" = "organizations", "organisations" = "organizations",
  "committees" = "groups", "cbos" = "groups", "wuas" = "groups", "farmer groups" = "groups",
              "ha" = "hectares", "hectare" = "hectares", "hectares" = "hectares",
  "%" = "percentage", "percent" = "percentage", "percentage" = "percentage",
  "percentage points" = "percentage", "people" = "individuals",
  "persons" = "individuals", "individuals" = "individuals",
  "farmers" = "individuals", "beneficiaries" = "individuals",
  "households" = "households", "hh" = "households", "groups" = "groups",
  "organizations" = "organizations", "organisations" = "organizations",
  "kg" = "kg", "kilograms" = "kg", "kg/ha" = "kg/hectare",
  "kg/hectare" = "kg/hectare", "liters" = "liters", "litres" = "liters",
  "tco2e" = "tCO2e", "mtco2" = "tCO2e", "mtco2e" = "tCO2e", "tons" = "tons",
  "tonnes" = "tons", "t" = "tons", "number" = "quantity", "count" = "quantity",
  "quantity" = "quantity", "countries" = "quantity", "yes/no" = "quantity")
# the general normaliser drops "%" and "/" entirely, which silently wiped
# every percentage unit and every "kg/ha", so units get their own one
unrm <- function(x) trimws(gsub("\\s+", " ", tolower(gsub("[.]+$", "", x))))
map_unit_det <- function(u) {
  k <- unrm(u)
  if (k %in% names(unit_syn)) return(unname(unit_syn[k]))
  k2 <- actor_nrm(u)
  if (!nzchar(k2)) return(if (nzchar(k)) u else "")
  if (k2 %in% names(unit_syn)) unname(unit_syn[k2]) else u
}
