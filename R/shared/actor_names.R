##############################################################################
# actor_names.R - the one way to compare two organisation names.
#
# Three copies of this logic had grown up independently: nrm() and nrm_actor()
# in R/extraction/harmonize.R and fold() in R/reporting/audit_proposed_actors.R,
# which stripped "the/of/for/and" that the other two kept. So the audit that
# checks the matcher's proposals disagreed with the matcher about whether two
# names were the same, and a synonym list keyed on one would have been invisible
# to the other. Everything that compares organisation names now comes here.
#
# It also settles a quieter disagreement: readxl trims cell whitespace and
# openxlsx does not, so the same registry sheet has 247 names with a trailing
# space read one way and 1 read the other. actor_registry() trims explicitly,
# so it no longer matters which reader anyone reaches for.
#
# No library() calls, no side effects: safe to source from anything, including
# the checks, which must run without an API key.
##############################################################################

## ---- normalising a name ----------------------------------------------------

# The plain form. Kept character-for-character as harmonize.R's nrm() was,
# because that function is also used for units and for country prefixes, and a
# drift here would silently change unit mapping.
actor_nrm <- function(x) {
  trimws(gsub("[^a-z0-9 ]", " ", gsub("\\s+", " ", tolower(x))))
}

# The forgiving form, for the differences that are spelling rather than
# identity: a bracketed acronym carried inline, British against American
# spelling, and accents. Each was a real duplicate proposal.
actor_fold <- function(x) {
  s <- tolower(as.character(x))
  s <- iconv(s, "UTF-8", "ASCII//TRANSLIT", sub = " ")   # Investigacao = Investigação
  s[is.na(s)] <- ""
  s <- gsub("[(][^)]*[)]", " ", s)
  s <- gsub("centre", "center", s)
  s <- gsub("organisation", "organization", s)
  s <- gsub("programme", "program", s)
  s <- gsub("labour", "labor", s)
  s <- gsub("&", " and ", s, fixed = TRUE)
  trimws(gsub(" +", " ", gsub("[^a-z0-9 ]", " ", s)))
}

# Spacing-insensitive: "MercyCorps" against "Mercy Corps".
actor_squash <- function(x) gsub(" ", "", x, fixed = TRUE)

# Every form one name should be looked up under. The comma-suffix form is
# deliberately NOT here: "Ministry of Finance, Ghana" reduced to "Ministry of
# Finance" is a name several countries share, so it belongs in the synonym
# list under the uniqueness rule, not in a normaliser that cannot check it.
actor_forms <- function(name) {
  f <- c(actor_nrm(name), actor_fold(name), actor_squash(actor_fold(name)))
  unique(f[nzchar(f)])
}

# Words distinctive enough to compare two names by. Stopwords are stripped
# HERE and never inside actor_fold: folding away "of" would collapse
# "Bank of Africa" and "Africa Bank" into one organisation.
ACTOR_STOPWORDS <- c("the", "of", "for", "and", "in", "de", "la", "national",
                     "institute", "agency", "ministry", "project",
                     "development", "african", "africa")
actor_tokens <- function(x, min_chars = 4L) {
  t <- strsplit(actor_fold(x), " ", fixed = TRUE)[[1]]
  t[nchar(t) >= min_chars & !t %in% ACTOR_STOPWORDS]
}

# Acronyms written inside a name, plus the registry's own acronym column.
actor_acronyms <- function(name, acro = "") {
  a <- unlist(regmatches(name, gregexpr("\\b[A-Z]{3,8}\\b", name)))
  a <- toupper(trimws(c(a, acro)))
  unique(a[nzchar(a)])
}

## ---- the registry ----------------------------------------------------------

# One reader, everything trimmed, rows without a code or a name dropped.
actor_registry <- function(template_xlsx) {
  a <- openxlsx::read.xlsx(template_xlsx, sheet = "actor_codes")
  a[is.na(a)] <- ""
  nm <- tolower(trimws(names(a)))
  pick <- function(pat) { k <- grep(pat, nm)[1]; if (is.na(k)) NULL else a[[k]] }
  reg <- data.frame(
    code = trimws(as.character(pick("code"))),
    name = trimws(as.character(pick("name"))),
    acro = trimws(as.character(pick("acronym|accronym|abbrev") %||% "")),
    web  = trimws(as.character(pick("website|profile") %||% "")),
    stringsAsFactors = FALSE)
  reg <- reg[nzchar(reg$code) & nzchar(reg$name), , drop = FALSE]
  reg$nname <- actor_nrm(reg$name); reg$nacro <- actor_nrm(reg$acro)
  reg$aname <- actor_fold(reg$name); reg$aacro <- actor_fold(reg$acro)
  rownames(reg) <- NULL
  reg
}
`%||%` <- function(a, b) if (is.null(a)) b else a

## ---- the lookup index ------------------------------------------------------

# Every form that may be looked up, and the code it points at. `kind` says
# where the form came from so a match can always be explained.
#
# A synonym table is optional; without one the index is exactly the registry
# and matching behaves as it always has.
actor_index <- function(reg, synonyms = NULL) {
  keys <- rbind(
    data.frame(form = reg$nname, code = reg$code, tier = "registry",
               kind = "name", via = "", stringsAsFactors = FALSE),
    data.frame(form = reg$nacro, code = reg$code, tier = "registry",
               kind = "acronym", via = "", stringsAsFactors = FALSE),
    data.frame(form = reg$aname, code = reg$code, tier = "registry",
               kind = "name-folded", via = "", stringsAsFactors = FALSE),
    data.frame(form = reg$aacro, code = reg$code, tier = "registry",
               kind = "acronym-folded", via = "", stringsAsFactors = FALSE))
  keys <- keys[nzchar(keys$form), , drop = FALSE]
  # A one or two letter acronym is not an identifier. 25 registry rows carry
  # one, and "AA" was enough to match Access Agriculture deterministically,
  # which is how a document mentioning anything abbreviated AA would have been
  # filed under a Belgian NGO. Short acronyms still reach the shortlist, where
  # the confirmation step can weigh them against the document's wording.
  short <- grepl("acronym", keys$kind) & nchar(keys$form) < 3
  keys <- keys[!short, , drop = FALSE]

  if (!is.null(synonyms) && nrow(synonyms)) {
    s <- synonyms[synonyms$status == "active" & nzchar(synonyms$synonym) &
                  synonyms$actor_code %in% reg$code, , drop = FALSE]
    if (nrow(s)) {
      syn <- do.call(rbind, lapply(seq_len(nrow(s)), function(i) {
        f <- actor_forms(s$synonym[i])
        data.frame(form = f, code = s$actor_code[i], tier = s$tier[i],
                   kind = paste0("synonym:", s$source[i]),
                   via = s$synonym[i], stringsAsFactors = FALSE)
      }))
      keys <- rbind(keys, syn[nzchar(syn$form), , drop = FALSE])
    }
  }
  list(reg = reg, keys = keys, synonyms = synonyms)
}

## ---- matching --------------------------------------------------------------

# Returns the code, how it was reached, and (for a synonym) which synonym did
# it. Every tier demands a unique CODE, not a unique row: a registry that
# lists one organisation twice under the same code is not an ambiguity.
# Anything ambiguous falls through to the caller's confirmation step rather
# than being guessed.
match_actor_det <- function(name, IDX) {
  none <- list(code = NA_character_, how = "", via = "")
  n <- actor_nrm(name)
  if (!nzchar(n)) return(none)
  reg <- IDX$reg; keys <- IDX$keys

  hit_codes <- function(k) unique(k$code[nzchar(k$code)])
  one <- function(k, how) {
    cd <- hit_codes(k)
    if (length(cd) == 1) list(code = cd, how = how,
                              via = if (nzchar(k$via[1])) k$via[1] else "") else NULL
  }

  # 1. the name or acronym exactly as the registry writes it
  r <- one(keys[keys$tier == "registry" & keys$kind %in% c("name", "acronym") &
                keys$form == n, , drop = FALSE], "name")
  if (!is.null(r)) return(r)

  # 2. a trusted synonym
  fs <- actor_forms(name)
  r <- one(keys[keys$tier == "trusted" & keys$form %in% fs, , drop = FALSE], "synonym")
  if (!is.null(r)) return(r)

  # 3. the forgiving form, long enough that a short word cannot collide
  a <- actor_fold(name)
  if (nchar(a) >= 6) {
    r <- one(keys[keys$tier == "registry" & keys$form == a, , drop = FALSE], "folded")
    if (!is.null(r)) return(r)
    sq <- actor_squash(a)
    r <- one(keys[keys$tier == "registry" &
                  actor_squash(keys$form) == sq, , drop = FALSE], "squashed")
    if (!is.null(r)) return(r)
  }

  # 4. containment, for long names only. A short acronym sits inside unrelated
  # words ('TAF' inside 'Taflalet'), which is why this tier has a length guard
  # and why synonyms are never allowed into it.
  if (nchar(n) >= 8) {
    k <- which(nzchar(reg$nname) &
               vapply(reg$nname, function(x)
                 grepl(x, n, fixed = TRUE) || grepl(n, x, fixed = TRUE), logical(1)))
    cd <- unique(reg$code[k])
    if (length(cd) == 1) return(list(code = cd, how = "contained", via = ""))
  }
  none
}

# Rows worth showing the confirmation step. Synonym hits go FIRST: the list is
# truncated to k, and a code that is not on the shortlist can never be chosen,
# so appending synonyms at the end would push working candidates off and lose
# matches rather than gain them.
actor_candidates <- function(name, IDX, k = 8L) {
  reg <- IDX$reg; keys <- IDX$keys
  n <- actor_nrm(name); fs <- actor_forms(name)
  words <- strsplit(n, " ", fixed = TRUE)[[1]]; words <- words[nchar(words) > 3]

  syn <- keys[keys$tier %in% c("trusted", "candidate") & keys$form %in% fs, , drop = FALSE]
  rows <- match(syn$code, reg$code); via <- syn$via
  rows <- rows[!is.na(rows)]; via <- via[seq_along(rows)]

  more <- unique(c(
    which(vapply(reg$nname, function(x) nzchar(x) &&
      (grepl(x, n, fixed = TRUE) || grepl(n, x, fixed = TRUE)), logical(1))),
    which(vapply(reg$nacro, function(x) nzchar(x) &&
      (grepl(x, n, fixed = TRUE) || grepl(n, x, fixed = TRUE) ||
       any(vapply(words, function(w) grepl(w, x, fixed = TRUE), logical(1)))),
      logical(1))),
    agrep(n, reg$nname, max.distance = 0.25)))
  more <- more[!more %in% rows]

  idx <- c(rows, more)
  v <- c(via, rep("", length(more)))
  keep <- seq_len(min(k, length(idx)))
  list(rows = idx[keep], via = v[keep])
}
