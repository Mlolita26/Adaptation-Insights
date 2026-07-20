###############################################################################
# World Bank Projects Scraper from worldbank_metadata.csv
#
# Goal:
#   - Read document metadata already downloaded
#   - Extract clean WB project IDs (P######) from `project_id`
#   - Scrape project detail pages only for those IDs
#   - Keep only documents for which project info was successfully retrieved
#
# Output:
#   - worldbank_project_id_map.csv
#   - worldbank_projects_from_docs.csv
#   - worldbank_documents_with_project_info.csv
###############################################################################

library(httr)
library(jsonlite)
library(rvest)
library(dplyr)
library(readr)
library(stringr)
library(tidyr)
library(purrr)
library(processx)

# ═══════════ CONFIG ═══════════

CHROMEDRIVER_PATH <- "C:/Users/mlolita/Downloads/chromedriver-win64/chromedriver-win64/chromedriver.exe"
INPUT_METADATA    <- "C:/Users/mlolita/OneDrive - CGIAR/WP2_Evidence Synthesis/Grey Literature/Data/Project_doc/Worldbank/List/worldbank_metadata.csv"
OUT_ID_MAP        <- "worldbank_project_id_map.csv"
OUT_PROJECTS      <- "worldbank_projects_from_docs.csv"
OUT_DOCS_JOINED   <- "worldbank_documents_with_project_info.csv"

HEADLESS          <- FALSE
WAIT_SECONDS      <- 8
PORT              <- 9517

if (!file.exists(CHROMEDRIVER_PATH)) stop("Chromedriver not found at: ", CHROMEDRIVER_PATH)
if (!file.exists(INPUT_METADATA)) stop("Input file not found: ", INPUT_METADATA)

cat("✓ Chromedriver found\n")
cat("✓ Input metadata found\n\n")

# ═══════════ HELPER FUNCTIONS ═══════════

open_browser <- function(path, port, headless = FALSE) {
  proc <- processx::process$new(path, sprintf("--port=%d", port), stdout="|", stderr="|")
  Sys.sleep(3)
  
  if (!proc$is_alive()) {
    stop("Chromedriver failed: ", proc$read_error())
  }
  
  args <- c(
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-gpu",
    "--window-size=1920,1080",
    "--remote-allow-origins=*"
  )
  if (headless) args <- c("--headless=new", args)
  
  body <- list(
    capabilities = list(
      alwaysMatch = list(
        browserName = "chrome",
        `goog:chromeOptions` = list(args = as.list(args))
      )
    )
  )
  
  resp <- POST(
    sprintf("http://localhost:%d/session", port),
    body = toJSON(body, auto_unbox = TRUE),
    content_type_json(),
    encode = "raw"
  )
  
  sid <- content(resp, "parsed")$value$sessionId
  cat("  Chrome opened on port", port, "\n\n")
  list(base = sprintf("http://localhost:%d", port), sid = sid, proc = proc)
}

go_to <- function(b, url) {
  POST(
    sprintf("%s/session/%s/url", b$base, b$sid),
    body = toJSON(list(url = url), auto_unbox = TRUE),
    content_type_json(),
    encode = "raw"
  )
  invisible()
}

get_url <- function(b) {
  content(GET(sprintf("%s/session/%s/url", b$base, b$sid)), "parsed")$value
}

get_title <- function(b) {
  content(GET(sprintf("%s/session/%s/title", b$base, b$sid)), "parsed")$value
}

get_source <- function(b) {
  content(GET(sprintf("%s/session/%s/source", b$base, b$sid)), "parsed")$value
}

run_js <- function(b, s) {
  r <- POST(
    sprintf("%s/session/%s/execute/sync", b$base, b$sid),
    body = toJSON(list(script = s, args = list()), auto_unbox = TRUE),
    content_type_json(),
    encode = "raw"
  )
  content(r, "parsed")$value
}

close_browser <- function(b) {
  tryCatch(DELETE(sprintf("%s/session/%s", b$base, b$sid)), error = function(e) NULL)
  tryCatch(b$proc$kill(), error = function(e) NULL)
  cat("Browser closed.\n")
}

# ═══════════ ID EXTRACTION / NORMALIZATION ═══════════
# Handles:
#   "ABC -- P123456"
#   "ABC -- 123456"
#   multiple IDs in same cell
# Returns unique clean IDs like P123456

extract_project_ids <- function(x) {
  if (is.na(x) || !nzchar(x)) return(character(0))
  
  txt <- as.character(x)
  
  # First: explicit P + 6 digits
  ids1 <- str_extract_all(txt, "\\bP\\d{6}\\b")[[1]]
  
  # Second: bare 6 digits possibly representing project IDs
  # Only convert to P###### if not already captured
  ids2_raw <- str_extract_all(txt, "(?<!P)\\b\\d{6}\\b")[[1]]
  ids2 <- paste0("P", ids2_raw)
  
  ids <- unique(c(ids1, ids2))
  ids[nzchar(ids)]
}

# Safer single-ID normalization if you ever need it
normalize_project_id <- function(x) {
  ids <- extract_project_ids(x)
  if (length(ids) == 0) return(NA_character_)
  ids[1]
}

# ═══════════ JS EXTRACTION ═══════════

JS_EXTRACT_V2 <- "
  var result = {};

  var items = document.querySelectorAll('.main-detail li');
  items.forEach(function(li) {
    var label = li.querySelector('label');
    var values = li.querySelectorAll('p.document-info');
    if (label && values.length > 0) {
      var lbl = label.innerText.replace(/[0-9\\s]*$/,'').trim();
      var vals = [];
      values.forEach(function(p) {
        var t = p.innerText.trim();
        if (t && t !== 'N/A' && t !== '(as of board presentation)') vals.push(t);
      });
      if (lbl && vals.length > 0) {
        result[lbl] = vals.join(' | ');
      }
    }
  });

  var abstractEl = document.querySelector('#abstract .intro_paragraph .more');
  if (abstractEl) {
    result['Abstract'] = abstractEl.innerText.replace(/Show More.*$/,'').trim().substring(0, 2000);
  }

  var devObj = document.querySelector('#development-objective .intro_paragraph .more');
  if (devObj) {
    result['Development Objective'] = devObj.innerText.trim().substring(0, 2000);
  }

  var sectorCard = document.querySelector('sector-section .card-main-section');
  if (sectorCard) {
    var sectorText = sectorCard.innerText.trim();
    if (sectorText && sectorText !== 'No data available.') {
      result['Sectors'] = sectorText;
    }
  }

  var themeCard = document.querySelector('theme-section .card-main-section');
  if (themeCard) {
    var themeText = themeCard.innerText.trim();
    if (themeText && themeText !== 'No data available.') {
      result['Themes'] = themeText;
    }
  }

  var finTables = document.querySelectorAll('.Financing_section table');
  finTables.forEach(function(table) {
    var rows = table.querySelectorAll('tr');
    rows.forEach(function(row) {
      var cells = row.querySelectorAll('td');
      if (cells.length >= 2) {
        var key = cells[0].innerText.trim();
        var val = cells[1].innerText.trim();
        if (key && val && !result['Finance: ' + key]) {
          result['Finance: ' + key] = val;
        }
      }
    });
  });

  var h1 = document.querySelector('h1');
  if (h1) result['Project Title'] = h1.innerText.trim();

  return JSON.stringify(result);
"

# ═══════════ READ AND EXPAND DOCUMENT->PROJECT LINKS ═══════════

cat("=== Reading metadata ===\n")
docs <- read_csv(INPUT_METADATA, show_col_types = FALSE)

if (!"project_id" %in% names(docs)) {
  stop("Expected column `project_id` not found in metadata file.")
}

cat("  Documents in metadata:", nrow(docs), "\n")

doc_project_map <- docs %>%
  mutate(doc_row_id = row_number()) %>%
  mutate(extracted_ids = map(project_id, extract_project_ids)) %>%
  unnest_longer(extracted_ids, values_to = "clean_project_id", keep_empty = TRUE) %>%
  mutate(clean_project_id = ifelse(clean_project_id == "", NA, clean_project_id))

cat("  Documents with at least one extractable project ID:",
    sum(!is.na(doc_project_map$clean_project_id) %>% as.integer() > 0), "\n")

doc_project_map<-doc_project_map%>%filter(clean_project_id!="P")

unique_project_ids <- doc_project_map %>%
  filter(!is.na(clean_project_id)) %>%
  distinct(clean_project_id) %>%
  arrange(clean_project_id) %>%
  pull(clean_project_id)

cat("  Unique project IDs extracted:", length(unique_project_ids), "\n\n")



write_csv(doc_project_map, OUT_ID_MAP)
cat("  ✓ Saved ID map to", OUT_ID_MAP, "\n\n")

# ═══════════ OPEN BROWSER ═══════════

cat("=== Opening browser ===\n")
browser <- open_browser(CHROMEDRIVER_PATH, PORT, HEADLESS)
go_to(browser, "https://www.google.com")
Sys.sleep(2)
cat("  Test:", get_title(browser), "\n\n")

# ═══════════ SCRAPE PROJECT PAGES ═══════════

cat("=== Scraping project pages ===\n\n")
all_results <- vector("list", length(unique_project_ids))

for (i in seq_along(unique_project_ids)) {
  pid <- unique_project_ids[i]
  page_url <- paste0("https://projects.worldbank.org/en/projects-operations/project-detail/", pid)
  
  cat(sprintf("[%d/%d] %s\n", i, length(unique_project_ids), pid))
  go_to(browser, page_url)
  Sys.sleep(WAIT_SECONDS)
  
  current_url <- tryCatch(get_url(browser), error = function(e) NA_character_)
  html <- tryCatch(get_source(browser), error = function(e) "")
  cat("  URL:", current_url, "\n")
  cat("  HTML:", nchar(html), "chars\n")
  
  js_raw <- tryCatch(run_js(browser, JS_EXTRACT_V2), error = function(e) NULL)
  kv <- if (!is.null(js_raw) && is.character(js_raw) && nchar(js_raw) > 2) {
    tryCatch(fromJSON(js_raw), error = function(e) list())
  } else {
    list()
  }
  
  cat("  Fields:", length(kv), "\n")
  
  get_field <- function(exact_name) {
    idx <- which(tolower(names(kv)) == tolower(exact_name))
    if (length(idx) > 0) return(as.character(kv[[idx[1]]]))
    NA_character_
  }
  
  # Mark whether scrape looks successful
  scrape_ok <- length(kv) > 0 && !is.na(get_field("Project Title")) && nzchar(get_field("Project Title"))
  
  row <- data.frame(
    clean_project_id    = pid,
    scrape_ok           = scrape_ok,
    project_name        = get_field("Project Title"),
    status              = get_field("Status"),
    country             = get_field("Country"),
    region              = get_field("Region"),
    approval_date       = get_field("Approval Date"),
    closing_date        = get_field("Closing Date"),
    disclosure_date     = get_field("Disclosure Date"),
    effective_date      = get_field("Effective Date"),
    total_project_cost  = get_field("Total Project Cost"),
    commitment_amount   = get_field("Commitment Amount"),
    team_leader         = get_field("Team Leader"),
    borrower            = get_field("Borrower"),
    implementing_agency = get_field("Implementing Agency"),
    env_category        = get_field("Environmental Category"),
    env_social_risk     = get_field("Environmental and Social Risk"),
    fiscal_year         = get_field("Fiscal Year"),
    last_stage          = get_field("Last Stage Reached"),
    consultant_required = get_field("Consultant Services required"),
    sectors             = get_field("Sectors"),
    themes              = get_field("Themes"),
    dev_objective       = get_field("Development Objective"),
    abstract_project    = get_field("Abstract"),
    url                 = page_url,
    all_raw_data        = paste(paste0(names(kv), ": ", kv), collapse = " | "),
    stringsAsFactors    = FALSE
  )
  
  all_results[[i]] <- row
  if (scrape_ok) {
    cat("  ✓ Success\n\n")
  } else {
    cat("  ✗ No usable project data found\n\n")
  }
  
  if (i < length(unique_project_ids)) Sys.sleep(2)
}

projects <- bind_rows(all_results)

# ═══════════ SAVE PROJECT TABLE ═══════════

cat("=== Saving project table ===\n")
write_csv(projects, OUT_PROJECTS)
cat("  ✓", nrow(projects), "rows ->", OUT_PROJECTS, "\n\n")

# ═══════════ KEEP ONLY DOCUMENTS WITH SUCCESSFUL PROJECT INFO ═══════════

cat("=== Joining documents to project info ===\n")

valid_projects <- projects %>%
  filter(scrape_ok) %>%
  distinct(clean_project_id)

docs_joined <- doc_project_map %>%
  filter(!is.na(clean_project_id)) %>%
  inner_join(valid_projects, by = "clean_project_id") %>%
  left_join(projects, by = "clean_project_id")

# Optional:
# if a document links to multiple project IDs, it will appear multiple times.
# That is usually desirable. If you want one row per original document only,
# you can collapse later.

write_csv(docs_joined, OUT_DOCS_JOINED)

cat("  ✓ Joined rows:", nrow(docs_joined), "->", OUT_DOCS_JOINED, "\n\n")

# ═══════════ SUMMARY ═══════════

cat("=== Summary ===\n")
cat("  Input documents:", nrow(docs), "\n")
cat("  Unique extracted project IDs:", length(unique_project_ids), "\n")
cat("  Successfully scraped projects:", sum(projects$scrape_ok, na.rm = TRUE), "\n")
cat("  Documents linked to successfully scraped projects:",
    n_distinct(docs_joined$doc_row_id), "\n\n")

# ═══════════ COMPLETENESS ═══════════

cat("=== Project Data Completeness ===\n")
check_cols <- c(
  "project_name","status","country","region","approval_date",
  "closing_date","total_project_cost","commitment_amount",
  "team_leader","borrower","implementing_agency",
  "sectors","themes","dev_objective","abstract_project"
)

proj_ok <- projects %>% filter(scrape_ok)

if (nrow(proj_ok) > 0) {
  for (col in check_cols) {
    filled <- sum(!is.na(proj_ok[[col]]) & proj_ok[[col]] != "")
    pct <- round(100 * filled / nrow(proj_ok))
    bar <- strrep("█", floor(pct / 5))
    cat(sprintf("  %-22s %3d/%d (%3d%%) %s\n", col, filled, nrow(proj_ok), pct, bar))
  }
} else {
  cat("  No successfully scraped projects.\n")
}

# ═══════════ PREVIEW ═══════════

cat("\n=== Project Preview ===\n")
print(
  projects %>%
    select(clean_project_id, scrape_ok, project_name, status, country, approval_date, total_project_cost) %>%
    head(10)
)

cat("\n=== Document + Project Preview ===\n")
print(
  docs_joined %>%
    select(id, title, clean_project_id, project_name, country.y, status, approval_date) %>%
    head(10)
)

# ═══════════ CLOSE ═══════════

close_browser(browser)
cat("\n✓ All done.\n")