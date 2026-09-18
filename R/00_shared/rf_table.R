##############################################################################
# rf_table.R — read a results-framework table AS A TABLE.
#
# The problem this solves: a results table says
#
#   Indicator | Unit | Baseline | Original Target | Revised Target | Actual
#   Farmers reached | Number | 0.00 | 2,070,000.00 |               | 2,601,000.00
#
# but the PDF text layer flattens it to "0.00 2,070,000.00 2,601,000.00" with
# no labels, and the count of printed figures changes from row to row because a
# revised target may or may not exist. Asked to pick "the result" out of that,
# the model took the first figure — the BASELINE — and recorded 0 for a project
# that reached 2.6 million farmers (holdout H001, all three slots 0.00).
#
# The fix is comprehension, not a heuristic: work out what each column MEANS,
# then read the value under the one that means "actual achieved".
#
# How, and why this way:
#   * The FIGURES say where the columns are. They align on a few x positions,
#     page after page. Header words cannot be grouped by the space between them
#     - in a World Bank ICR "Measure" ends 7 points before "Baseline" starts,
#     while "Actual" and "Achieved", one label, sit 31 apart.
#   * The HEADER says what each column is called. Each role is looked up by its
#     own wording and matched to the nearest figure column, and only when it is
#     genuinely close. That matters: on a page where no indicator was revised
#     there IS no revised column, and a looser rule would let the words
#     "Formally Revised Target" drift onto the original-target figures.
#   * Anything left of the first figure column is the indicator, gathered
#     across the lines it wraps over.
#
# Geometry locates, wording decides. A new publisher or language needs its
# header wording added to RF_ANCHORS, never new coordinates.
#
# Why not a value rule: "reject a 0" was considered and rejected. A 0 under
# "actual" is a real finding - H001 has an indicator that ran 15 -> 6 -> 0 -
# and the protocol counts a failed indicator as a finding. Only the column can
# tell a starting point from a total failure.
#
#   rows <- rf_tables(local_pdf_path, pages)   # character vector, prompt-ready
##############################################################################

# One role, one set of header words. Checked in this order, so the wording that
# would also satisfy a looser role is claimed by the specific one first.
RF_ANCHORS <- list(
  actual   = "^(actual|achiev|completion|r.alis|atteint|obtenu)",
  revised  = "^(revis|formally|r.vis)",
  target   = "^(target|original|cible|objectif|pr.vu|attendu)",
  baseline = "^(baseline|r.f.rence|base|d.part)")

RF_BAND    <- 22   # a header label may wrap over this many points of lines
RF_XTOL    <- 8    # two figures start in the same column within this many
RF_NEAR    <- 34   # a header word names a column only this close to it
RF_MINROWS <- 1    # a single-row table is still a table

# Ask the figures where the columns are. Only figures to the right of the
# leftmost header role word count: a year or a footnote marker inside the
# indicator text is not a column, and letting one in would shift every cell.
rf_num_starts <- function(body, x_min = -Inf) {
  num <- body[grepl("^[0-9]", body$text) & body$x >= x_min, , drop = FALSE]
  if (nrow(num) < RF_MINROWS) return(numeric(0))
  xs  <- sort(num$x)
  grp <- cumsum(c(1, diff(xs) > RF_XTOL))
  keep <- vapply(split(xs, grp), function(v)
    if (length(v) >= RF_MINROWS) min(v) else NA_real_, numeric(1))
  sort(unname(keep[!is.na(keep)]))
}

# Ask the header what each column is called.
rf_assign_roles <- function(hw, starts) {
  roles <- rep("", length(starts))
  if (!length(starts)) return(roles)
  for (nm in names(RF_ANCHORS)) {
    cand <- hw[grepl(RF_ANCHORS[[nm]], tolower(hw$text)), , drop = FALSE]
    if (!nrow(cand)) next
    best <- NA_integer_; bestd <- Inf
    for (k in seq_len(nrow(cand))) {
      d <- abs(starts - cand$x[k])
      if (!length(d)) next
      i <- which.min(d)
      if (length(i) && d[i] <= RF_NEAR && d[i] < bestd && !nzchar(roles[i])) {
        best <- i; bestd <- d[i]
      }
    }
    if (!is.na(best)) roles[best] <- nm
  }
  roles
}

# One page -> labelled rows. character(0) when the page holds no table this
# function can vouch for; the caller then falls back to the flattened text and
# the vision pass exactly as before, which is the honest outcome.
rf_page_rows <- function(w, page) {
  if (is.null(w) || !nrow(w)) return(character(0))
  w$text <- trimws(as.character(w$text))
  w <- w[nzchar(w$text), , drop = FALSE]
  if (!nrow(w)) return(character(0))

  anchor <- which(grepl("^baseline|^r.f.rence|^ligne de base", tolower(w$text)))
  if (!length(anchor)) return(character(0))
  hy   <- w$y[anchor[1]]
  hw   <- w[abs(w$y - hy) <= RF_BAND, , drop = FALSE]
  body <- w[w$y > max(hw$y) + 2, , drop = FALSE]
  if (!nrow(body)) return(character(0))

  anchor_x <- hw$x[grepl(paste(unlist(RF_ANCHORS), collapse = "|"), tolower(hw$text))]
  starts <- rf_num_starts(body, if (length(anchor_x)) min(anchor_x) - 40 else -Inf)
  if (length(starts) < 2) return(character(0))
  roles <- rf_assign_roles(hw, starts)
  if (!("actual" %in% roles)) return(character(0))
  i_act <- which(roles == "actual")[1]

  left  <- min(starts) - 6           # everything left of the figures is the indicator
  bounds <- c(starts - 6, Inf)
  out <- character(0); carry <- character(0)

  for (yy in sort(unique(body$y))) {
    ln <- body[body$y == yy, , drop = FALSE]
    ln <- ln[order(ln$x), ]
    ind <- paste(ln$text[ln$x < left], collapse = " ")
    cell <- rep("", length(starts))
    fig <- ln[ln$x >= left, , drop = FALSE]
    for (k in seq_len(nrow(fig))) {
      j <- min(max(which(bounds <= fig$x[k])), length(starts))
      cell[j] <- trimws(paste(cell[j], fig$text[k]))
    }
    act <- cell[i_act]
    if (!grepl("^[0-9][0-9,. ]*$", act)) {        # not a data row: hold the text
      if (nzchar(ind) && !grepl("^comments", tolower(ind))) carry <- c(carry, ind)
      if (length(carry) > 4) carry <- tail(carry, 4)
      next
    }
    name <- trimws(paste(paste(carry, collapse = " "), ind))
    carry <- character(0)
    if (!nzchar(name)) next
    parts <- character(0)
    for (i in seq_along(starts)) {
      if (!nzchar(cell[i])) next
      lab <- switch(roles[i], actual = "ACTUAL ACHIEVED", baseline = "baseline",
                    target = "target", revised = "revised target",
                    paste0("col", i))
      parts <- c(parts, paste0(lab, ": ", cell[i]))
    }
    out <- c(out, sprintf("[table p%d] %s | %s", page, name,
                          paste(parts, collapse = " | ")))
  }
  out
}

# pages: the RF/annex window to try. A scanned table yields no words, and the
# vision pass remains the answer for those.
rf_tables <- function(pdf_path, pages, max_rows = 120) {
  if (!length(pages)) return(character(0))
  dat <- tryCatch(pdftools::pdf_data(pdf_path), error = function(e) NULL)
  if (is.null(dat)) return(character(0))
  pages <- pages[pages >= 1 & pages <= length(dat)]
  out <- character(0)
  for (p in pages) {
    out <- c(out, tryCatch(rf_page_rows(dat[[p]], p),
                           error = function(e) character(0)))
    if (length(out) >= max_rows) break
  }
  head(out, max_rows)
}
