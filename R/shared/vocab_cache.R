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
# extracts reach the model. That makes reruns reproducible and progressively
# cheaper. Changing the option list changes the fingerprint, so old decisions
# for that field stop being reused rather than silently locking in an answer
# that predates the vocabulary.
#
# The file is a plain CSV a human can read, correct, or delete:
#   catalogues/vocab_decisions.csv
# Correcting a row there is a durable fix: it is what every later run uses.
##############################################################################

vocab_key <- function(text) {
  k <- tolower(trimws(gsub("\\s+", " ", as.character(text))))
  substr(k, 1, 300)
}

# a short fingerprint of the option list, so a changed vocabulary retires the
# decisions taken under the old one
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
  d <- d[d$field == field & d$options_fingerprint == vocab_fingerprint(options), ]
  if (!nrow(d)) return(empty)
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
