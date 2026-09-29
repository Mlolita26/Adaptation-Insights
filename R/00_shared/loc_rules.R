##############################################################################
# loc_rules.R - deterministic rules of the location sheet (harmonize_locations.R)
#
# Moved out of the harmoniser on 29 Sep 2026 so that test_regressions.R can
# exercise them. The model decides only where these rules are silent.
##############################################################################

# ---- subsector type ----------------------------------------------------------
det_subsector <- function(txt) {
  t <- tolower(txt)
  # water supply for people and animals is infrastructure across domains, not a
  # farming system: a water pan serves drinking, livestock and gardens at once
  # (KACCAL Kenya, DRSLP Ethiopia) - 29 Sep 2026. Irrigation stays with crops.
  if (grepl("water pan|water point|borehole|water scheme|water suppl|water harvest|dam\\b|reservoir|water kiosk|hand ?pump|piped water|water network|water availability", t) &&
      !grepl("irrigat", t)) return("cross cutting")
  fish <- grepl("fish|aquacult", t)   # "coastal" risk management is not fisheries (CP07)
  live <- grepl("livestock|pastoral|herd|cattle|goat|sheep|poultry|dairy|fodder", t)
  crop <- grepl("crop|maize|rice|seed|cocoa|coffee|cassava|wheat|sorghum|horticult|vegetable|cereal|yield|palm oil|soy", t)
  land <- grepl("land management|land use|land degradation|watershed|forest|restoration|reforestation|afforestation|slwm|soil conservation|erosion|deforestation|dune|rangeland|pastoral reserve|gully|tree planting|revegetat", t)
  food <- grepl("value chain|processing|post-?harvest|storage|market access|food distribution|food system", t)
  hits <- c(fish = fish, live = live, crop = crop, land = land, food = food)
  if (sum(hits) != 1) return("")
  c(fish = "farming system-fish", live = "farming system-livestock",
    crop = "farming system-crop", land = "land use",
    food = "agri-food")[names(hits)[hits]]
}

# ---- target beneficiary ------------------------------------------------------
det_target <- function(txt) {
  t <- tolower(txt)
  pat <- c("smallholder farmer" = "smallholder", "subsistence farmer" = "subsistence farmer",
    "artisanal fisher" = "artisanal fish|small-scale fish", "pastoralist/herder" = "pastoralist|herder",
    "farmer association" = "farmer associations?\\b", "farmer group" = "farmer groups?\\b",
    "producer organization" = "producer organi", "cooperative" = "cooperativ",
    "women's group/organization" = "women'?s group|women'?s organi",
    "women (female-headed households)" = "female-?headed|\\bwomen\\b",
    "youth" = "\\byouth\\b|young people", "household" = "households?\\b",
    "community" = "communit", "indigenous peoples" = "indigenous",
    "agribusiness" = "agribusiness|agri-?enterprise", "farm laborer" = "farm labou?rer",
    "children" = "\\bchildren\\b", "elderly" = "elderly", "migrant" = "migrant",
    "people with disabilities/ disability" = "disabilit",
    "vulnerable population" = "vulnerable",
    "producer" = "\\bproducers?\\b",
    # the template's overarching group: a count of people at large, with no
    # narrower group named, is the community served (29 Sep 2026)
    "community" = "communit|direct beneficiar|\\bbeneficiaries\\b|\\bpeople\\b|\\bpersons\\b|residents|\\bpopulation\\b|inhabitants|villagers")
  # plain "farmers" is the smallholder in this corpus; "a group of 200 farmers"
  # is a farmer group (29 Sep 2026)
  pat["smallholder farmer"] <- "smallholder|small-?scale farmers?|\\bfarmers?\\b"
  pat["farmer group"] <- "farmer groups?\\b|groups? of [0-9,]* ?farmers"
  hit <- names(pat)[vapply(pat, function(p) grepl(p, t), logical(1))]
  # a female or youth SHARE named beside the whole group is not the group:
  # "200 farmers comprising 100 women and 50 youths", "202,658 farmers of
  # which 113,660 female" -> the farmers (29 Sep 2026)
  share <- grepl("of which|of whom|including|includ|compris|\\bwomen and\\b|\\band women\\b|% ?(women|female)|(women|female)[^.]{0,25}(youth|young)|[0-9][0-9,.]* ?(women|female|youth)", t)
  sub_groups <- c("women (female-headed households)", "youth", "children", "elderly")
  if (share && any(hit %in% sub_groups) && any(!hit %in% sub_groups)) hit <- hit[!hit %in% sub_groups]
  if ("farmer group" %in% hit && "smallholder farmer" %in% hit) hit <- setdiff(hit, "smallholder farmer")
  if ("household" %in% hit && "smallholder farmer" %in% hit && grepl("farm(ing)? households?|households? of farmers", t)) hit <- setdiff(hit, "smallholder farmer")
  if (length(hit) == 1) hit else ""   # several hits -> LLM picks overarching
}

# ---- result level ------------------------------------------------------------
# The wording of what was counted usually says whether it is a thing delivered
# (output), a change in beneficiaries (outcome) or an activity (process).
# what a unit counts: things and people delivered or reached are outputs
LOC_OUTPUT_UNIT <- paste0("\\b(ha|hectares?|km|kilomet(re|er)s?|acres?|bags?|tons?|tonnes?|",
  "boreholes?|wells?|water pans?|pans?|canals?|schemes?|dams?|stations?|centres?|centers?|",
  "stoves?|gardens?|plots?|schools?|clinics?|markets?|shops?|stores?|granaries|granary|",
  "nurseries|ponds?|reserves?|structures?|units?|systems?|plans?|policies|policy|",
  "cooperatives?|associations?|organi[sz]ations?|groups?|committees?|schools?|",
  "beneficiaries|households?|farmers?|people|persons?|residents?|individuals?|",
  "members?|participants?|staff|agents?|trainees?|producers?|fishers?|women|men|youths?|",
  "seedlings?|trees?|plants?|animals?|livestock|goats?|cattle|hives?|beehives?|",
  "machines?|pumps?|tractors?|kits?|packs?|buoys?|vehicles?)\\b")
# what a unit measures: a rate or a share is an outcome only when the wording
# names a change in the beneficiaries' situation
LOC_EFFECT_WORD <- paste0("adopt|yield|income|revenue|productiv|access|satisf|reduc|",
  "increas|improv|food secur|resilien|price|distance|time to|mortality|prevalence|",
  "consumption|saving|profit|per (ha|hectare|cow|day|capita)")

det_level <- function(txt) {
  t <- tolower(txt)
  outc <- grepl("adopt|yield|income|revenue|productiv|production increas|access to|reduc|improved (food|nutrition|diet)|food secur|resilien|catch increas|survival|mortality|prevalence|satisf|% of (households|farmers|beneficiaries) (with|using|report)", t)
  outp <- grepl("trained|constructed|built|installed|distributed|established|rehabilitated|restored|planted|delivered|equipped|formed|created|drilled|reached|supported|served|issued|beneficiar", t)
  proc <- grepl("meetings? held|workshops? (held|organi)|missions|consultations|sessions (held|conducted)|studies? (completed|conducted)|plans? (developed|drafted|prepared)|assessments? conducted|inspections? (conducted|carried|undertaken)|audits? (conducted|carried)|samples? (analy|tested)", t)
  inp  <- grepl("budget|disbursed|staff recruited|equipment procured|vehicles|funds mobili", t)
  # a yield, income or adoption figure is an outcome even when the sentence
  # also says what was delivered ("increased yield ... seeds delivered")
  if (outc && outp && grepl("yield|productiv|income|revenue|adopt|food secur|access to", t)) return("outcome")
  hits <- c(outcome = outc, output = outp, process = proc, input = inp)
  if (sum(hits) == 1) return(names(hits)[hits])
  # nothing in the wording decided it: the unit does. A count of things or
  # people delivered or reached is an output; a rate or share is an outcome
  # only where the wording names a change (29 Sep 2026)
  if (grepl("%|percent|\\bper ?cent", t) || grepl("/ha|per hectare|kg/|litres? per|per cow|per day|/cow|/litre|/kg", t))
    return(if (grepl(LOC_EFFECT_WORD, t)) "outcome" else "output")
  if (grepl(LOC_OUTPUT_UNIT, t)) return("output")
  ""
}

# ---- result unit (free text on the location sheet) --------------------------
# AfDB tables give "nbr" and "mtd" as units. A bare count word says nothing, so
# the counted noun is read from the result statement ("Pastoralists and
# agro-pastoralists trained"); metric tons become tons as on the general sheet.
# ---- does this text actually say anything? ---------------------------------
# Session 1 sometimes copies a table cell into the result statement, so the
# statement is a bare number ("1 194", "23%") and carries no evidence of what
# was counted. Such a statement cannot decide a level or a group.
has_words <- function(txt) grepl("[A-Za-z]{3}", as.character(txt %||% ""))

loc_unit_fix <- function(unit, stated = "") {
  u <- tolower(trimws(as.character(unit %||% "")))
  if (grepl("^(mtd|mt|metric tons?|tonnes?|t)$", u)) return("tons")
  if (!grepl("^(nbr|no\\.?|n|nr|num|number|numbers|count|units?|\\(number\\)|nombre)$", u)) return(trimws(as.character(unit %||% "")))
  s <- tolower(as.character(stated %||% ""))
  s <- sub("^.*?(number|nbr|no\\.?|nombre)\\s+(of|de)\\s+", "", s)          # "Number of federal ... staff" -> "federal ... staff"
  s <- sub("[(:;].*$", "", s)                                             # drop parentheses and clauses
  s <- gsub("[0-9][0-9,.]*\\s*%?", " ", s)                                # drop the figures
  s <- gsub("\\b(target|baseline|actual|achieved|cumulative|total|the|a|an)\\b", " ", s)
  s <- trimws(gsub("\\s+", " ", gsub("[^a-z/ -]", " ", s)))
  n <- length(strsplit(s, " ")[[1]])
  if (nzchar(s) && n <= 8) s else "number"
}
