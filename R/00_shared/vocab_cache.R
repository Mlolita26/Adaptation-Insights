##############################################################################
# vocab_cache.R - remember how each verbatim extract was mapped to a
# controlled vocabulary value.
#
# Harmonisation asks a model to pick one option from a fixed list. The model
# is not deterministic: harmonising the SAME extraction twice moved the
# beneficiary column by eleven rows in one test. That is not a quality
# difference, it is a coin toss, and it makes a rerun impossible to compare
# against the run before it.
#
# So every decision is written down. On the next run the same extract, judged
# against the same option list, reuses the recorded answer; only genuinely new
# extracts reach the model.
#
# WHAT RETIRES A DECISION (changed 16 Sep 2026). The fingerprint used to mix
# the option list together with a version stamp for the INSTRUCTIONS, so
# rewording the prompt retired every decision for every field and re-opened
# every question. That is how "New knowledge and advocacy products
# disseminated" came to hold two opposite answers:
#
#   27-87336763   10 Sep  ->  "CANDIDATE: knowledge products disseminated"
#   27-668944407  14 Sep  ->  "NOT STATED"        (which blanks the cell)
#
# Same text, same 27 options, opposite answers, because the rules stamp moved
# in between. Now the fingerprint covers the OPTIONS ONLY. A reworded prompt
# keeps the decisions; the rules version is recorded alongside for the audit
# trail, and only a version named in VOCAB_BREAKING_RULES forces a re-decision.
#
# The file is a plain CSV a human can read, correct, or delete:
#   catalogues/vocab_decisions.csv
# Correcting a row there is a durable fix: it is what every later run uses.
##############################################################################

vocab_key <- function(text) {
  k <- tolower(trimws(gsub("[[:space:]]+", " ", as.character(text))))
  substr(k, 1, 300)
}

# Recorded against each decision so it is always clear which instructions it
# was taken under. Changing this no longer retires anything by itself.
VOCAB_RULES_VERSION <- "v3-metric-candidate"

# Rules versions whose decisions genuinely cannot be trusted any more. Add one
# here only when the change alters what a correct answer IS - not when it
# merely rewords the question.
VOCAB_BREAKING_RULES <- character(0)

# a short fingerprint of the OPTION LIST alone
vocab_fingerprint <- function(options) {
  s <- paste(sort(tolower(trimws(as.character(options)))), collapse = "|")
  n <- 0
  for (ch in utf8ToInt(s)) n <- (n * 31 + ch) %% 1000000007
  paste0(length(options), "-", n)
}

vocab_cache_file <- function(repo) file.path(repo, "catalogues", "vocab_decisions.csv")

vocab_cache_load <- function(repo, field, options) {
  f <- vocab_cache_file(repo)
  empty <- setNames(character(0), character(0))
  if (!file.exists(f)) return(empty)
  d <- tryCatch(read.csv(f, stringsAsFactors = FALSE, colClasses = "character"),
                error = function(e) NULL)
  if (is.null(d) || !nrow(d)) return(empty)
  d[is.na(d)] <- ""
  if (!"rules_version" %in% names(d)) d$rules_version <- ""
  # Rows written before 16 Sep 2026 carry a fingerprint that mixed the rules
  # stamp into the hash, so they cannot be recomputed here. They are still
  # good decisions, so accept a legacy row for the same field whose option
  # COUNT matches - field plus count is unambiguous across this catalogue.
  fp     <- vocab_fingerprint(options)
  legacy <- !nzchar(d$rules_version) &
            startsWith(d$options_fingerprint, paste0(length(options), "-"))
  d <- d[d$field == field & (d$options_fingerprint == fp | legacy), ]
  if (nrow(d) && length(VOCAB_BREAKING_RULES))
    d <- d[!d$rules_version %in% VOCAB_BREAKING_RULES, ]
  if (!nrow(d)) return(empty)
  # Two answers for one extract can only come from a past re-decision. Prefer
  # the one that says something: a NOT STATED empties the cell, so it must
  # never quietly win over a real choice recorded for the same text.
  d$informative <- !(toupper(trimws(d$choice)) %in% c("NOT STATED", ""))
  d <- d[order(d$key, d$informative), ]
  d <- d[!duplicated(d$key, fromLast = TRUE), ]   # a later correction wins
  setNames(d$choice, d$key)
}

vocab_cache_save <- function(repo, field, options, texts, choices) {
  keep <- nzchar(texts) & nzchar(choices)
  if (!any(keep)) return(invisible())
  f <- vocab_cache_file(repo)
  new <- data.frame(field = field,
                    options_fingerprint = vocab_fingerprint(options),
                    key = vapply(texts[keep], vocab_key, character(1), USE.NAMES = FALSE),
                    choice = choices[keep],
                    rules_version = VOCAB_RULES_VERSION,
                    first_seen = format(Sys.Date()),
                    stringsAsFactors = FALSE)
  new <- new[!duplicated(new$key), ]
  if (file.exists(f)) {
    old <- tryCatch(read.csv(f, stringsAsFactors = FALSE, colClasses = "character"),
                    error = function(e) NULL)
    if (!is.null(old) && nrow(old)) {
      old[is.na(old)] <- ""
      for (cc in names(new)) if (!cc %in% names(old)) old[[cc]] <- ""
      old <- old[, names(new)]
      seen <- paste(old$field, old$options_fingerprint, old$key)
      new <- new[!paste(new$field, new$options_fingerprint, new$key) %in% seen, ]
      new <- rbind(old, new)
    }
  }
  utils::write.csv(new, f, row.names = FALSE, na = "")
  invisible()
}
