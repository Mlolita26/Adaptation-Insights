##############################################################################
# harvest_actor_websites.R - ask each organisation in the registry what it
# calls itself, by reading the one website the registry already records.
#
# This is the evidence behind the synonym list. A registry row says "African
# Union Development Agency"; a document says "NEPAD Agency"; the organisation's
# own homepage is the thing that can settle whether those are the same body.
# Nothing here decides anything - it collects, and a person reads the result.
#
# What is kept, and why:
#
#   final_url     a redirect IS a rename. nepad.org landing on auda-nepad.org
#                 is the organisation telling us both of its names.
#   title         usually the name it prefers
#   site_name     the short form it uses for itself (og:site_name)
#   heading       the first h1, often the full legal name
#   formerly      any sentence saying "formerly / previously known as /
#                 renamed / rebranded" - the single most valuable line
#   lang          whether a local-language form is to be expected
#   status        so a failure is a recorded fact rather than a gap
#
# One page per site. Nothing is crawled. Fetching reuses polite_get() and
# safe_read_html() from R/shared/01_utils.R, which already carry the project's
# user agent, a 1 to 2.5 second delay, a 60 second timeout, three retries with
# backoff and 429 handling.
#
# Resumable: a site already in the harvest is skipped, and the file is written
# after every batch, so stopping it costs nothing.
#
#   Rscript R/reporting/harvest_actor_websites.R --limit=50
#   Rscript R/reporting/harvest_actor_websites.R            # the rest
#   Rscript R/reporting/harvest_actor_websites.R --dry
##############################################################################

suppressPackageStartupMessages({
  library(openxlsx); library(httr); library(xml2); library(cli)
})

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", ".."), mustWork = TRUE)
source(file.path(REPO, "R", "shared", "paths.R"))
source(file.path(REPO, "R", "shared", "actor_names.R"))
source(file.path(REPO, "R", "shared", "00_config.R"))
source(file.path(REPO, "R", "shared", "01_utils.R"))

args  <- commandArgs(trailingOnly = TRUE)
opt   <- function(n, d = "") { h <- grep(paste0("^--", n, "="), args, value = TRUE)
                               if (length(h)) sub(paste0("^--", n, "="), "", h[1]) else d }
LIMIT <- suppressWarnings(as.integer(opt("limit", "0")))
DRY   <- any(args == "--dry")
BATCH <- 25

OUT <- file.path(REPO, "catalogues", "actor_website_harvest.csv")
COLS <- c("actor_code", "actor_name", "url", "final_url", "status",
          "title", "site_name", "heading", "formerly", "lang", "fetched_at")

## ---- which sites are worth asking -------------------------------------------
# "not found", "na", a Facebook page or an aggregator profile are not the
# organisation speaking for itself.
JUNK <- "^(not found|na|n/a|none|-|unknown)$"
AGGREGATOR <- "facebook|linkedin|twitter|x\\.com|developmentaid|wikipedia|youtube"

reg <- actor_registry(TEMPLATE_XLSX)
u <- trimws(reg$web)
u[grepl(JUNK, tolower(u))] <- ""
u[grepl(AGGREGATOR, tolower(u))] <- ""
u[nzchar(u) & !grepl("^https?://", u)] <- paste0("https://", u[nzchar(u) & !grepl("^https?://", u)])
todo <- data.frame(actor_code = reg$code, actor_name = reg$name, url = u,
                   stringsAsFactors = FALSE)
todo <- todo[nzchar(todo$url), , drop = FALSE]
cat("registry", nrow(reg), "actors |", nrow(todo), "with a site worth asking\n")

done <- if (file.exists(OUT)) {
  read_csv_utf8(OUT)
} else NULL
if (!is.null(done)) {
  todo <- todo[!todo$actor_code %in% done$actor_code, , drop = FALSE]
  cat("already harvested:", nrow(done), "| remaining:", nrow(todo), "\n")
}
if (LIMIT > 0 && nrow(todo) > LIMIT) todo <- todo[seq_len(LIMIT), , drop = FALSE]
cat("this run:", nrow(todo), "sites in", ceiling(nrow(todo) / BATCH),
    sprintf("batches | no API cost | ~%d min at 1-2.5s politeness plus response\n",
            ceiling(nrow(todo) * 4 / 60)))
if (DRY || !nrow(todo)) {
  cat(if (DRY) "dry run - stopping.\n" else "nothing to do.\n"); quit(save = "no")
}

## ---- reading one page --------------------------------------------------------
first_text <- function(doc, css) {
  n <- xml2::xml_find_first(doc, css)
  if (inherits(n, "xml_missing")) "" else trimws(gsub("\\s+", " ", xml2::xml_text(n)))
}
meta_content <- function(doc, prop) {
  n <- xml2::xml_find_first(doc, sprintf("//meta[@property='%s' or @name='%s']", prop, prop))
  if (inherits(n, "xml_missing")) "" else trimws(xml2::xml_attr(n, "content"))
}
FORMERLY_RX <- paste0("[^.]*\\b(formerly|previously known as|previously called|",
                      "renamed|rebranded|was established as|now known as)\\b[^.]*[.]")

harvest_one <- function(code, name, url) {
  row <- setNames(as.list(rep("", length(COLS))), COLS)
  row$actor_code <- code; row$actor_name <- name; row$url <- url
  row$fetched_at <- format(Sys.time(), "%Y-%m-%d %H:%M")
  resp <- tryCatch(polite_get(url), error = function(e) NULL)
  if (is.null(resp)) { row$status <- "no response"; return(as.data.frame(row, stringsAsFactors = FALSE)) }
  row$status    <- as.character(httr::status_code(resp))
  row$final_url <- resp$url
  txt <- tryCatch(httr::content(resp, as = "text", encoding = "UTF-8"),
                  error = function(e) "")
  if (!nzchar(txt) || !grepl("<body", txt, ignore.case = TRUE)) {
    row$status <- paste0(row$status, " no readable page")
    return(as.data.frame(row, stringsAsFactors = FALSE))
  }
  doc <- tryCatch(xml2::read_html(txt), error = function(e) NULL)
  if (is.null(doc)) { row$status <- paste0(row$status, " unparseable")
                      return(as.data.frame(row, stringsAsFactors = FALSE)) }
  row$title     <- substr(first_text(doc, "//title"), 1, 200)
  row$site_name <- substr(meta_content(doc, "og:site_name"), 1, 120)
  row$heading   <- substr(first_text(doc, "//h1"), 1, 200)
  row$lang      <- substr(xml2::xml_attr(xml2::xml_find_first(doc, "//html"), "lang"), 1, 12)
  body <- trimws(gsub("\\s+", " ", xml2::xml_text(doc)))
  hit  <- regmatches(body, regexpr(FORMERLY_RX, body, ignore.case = TRUE))
  row$formerly  <- if (length(hit)) substr(trimws(hit[1]), 1, 300) else ""
  row[is.na(row)] <- ""
  as.data.frame(row, stringsAsFactors = FALSE)
}

## ---- run, writing after every batch ------------------------------------------
chunks <- split(seq_len(nrow(todo)), ceiling(seq_len(nrow(todo)) / BATCH))
for (ci in seq_along(chunks)) {
  k <- chunks[[ci]]
  got <- do.call(rbind, lapply(k, function(i)
    harvest_one(todo$actor_code[i], todo$actor_name[i], todo$url[i])))
  done <- if (is.null(done)) got else rbind(done[, COLS], got[, COLS])
  write_csv_utf8(done, OUT)
  ok <- sum(grepl("^200", got$status) & nzchar(got$title))
  cat(sprintf("batch %d/%d: %d of %d pages read (%d%% cumulative)\n",
              ci, length(chunks), ok, nrow(got),
              round(100 * mean(grepl("^200", done$status) & nzchar(done$title)))))
}

cat("\nwritten:", OUT, "(", nrow(done), "rows )\n")
readable <- grepl("^200", done$status) & nzchar(done$title)
cat("readable pages:", sum(readable), "of", nrow(done),
    sprintf("(%d%%)\n", round(100 * mean(readable))))
cat("said 'formerly ...':", sum(nzchar(done$formerly)), "\n")
cat("redirected elsewhere:",
    sum(nzchar(done$final_url) & done$final_url != done$url), "\n")
