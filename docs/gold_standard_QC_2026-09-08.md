# Gold Standard Audit — QC of P001–P010 hand-extracted records

*2026-09-08 · full-document review of all 24 source files against the v02
`project_data_general` rows · shareable version with per-field verdict tables
published as the "Gold Standard Audit" artifact (team link held by Lolita).*

**Scoreboard:** ~240 field checks · ≈77% verified correct with page evidence ·
**20 wrong** · **7 values not present in any source document** · ~30
questionable/imprecise. Every record has at least one wrong or
externally-sourced field. Cleanest: the WB ICRs (P001, P009, P010). Weakest:
the three records drawn from the shared 294-page GEF Food Systems evaluation
(P002–P004) and the ACRE Africa pair (P007–P008).

## Systematic error patterns → pipeline rules

1. **Design year recorded as start year** (P002 2014→2017; P003 2015→2017;
   P004 2010–2014→2017–2025). Rule: approval/effectiveness/launch dates as
   stated in-document; never endorsement/replenishment years.
2. **IDA credits coded as grants** (P009 47% credit; P010 99.3% credit).
   Rule: read the instrument off the title page/financing table; credit=loan;
   record the mix (new `funding_mechanism_portion` field).
3. **Beneficiary category errors** — P004 is a literal row-slip from the
   adjacent RFS table row; P006 "artisanal fisher" traces to "semi-artisanal
   presses"; P003's category appears nowhere; P001 has no fitting option
   (institutional beneficiary). Rule: category must be evidenced by the
   document's own wording; vocab needs an institutional/government option.
4. **Evaluation samples recorded as program results** (P007 result1=FGD
   sample of 33, "57%" unsupported (actual sample 69.7%); P005 62% = survey
   sample share). Rule: methodology numbers are never results.
5. **Values not in the documents**: P005 resource_id 10307 + project_id
   119444 (Oxfam web IDs) + invented Portuguese UCASN name; P006 project_id
   12402 (doc says P-Z1-AA0-006); P007/P008 closure 2022 ("2019 to date").
   Rule: in-document or flagged external — supports the Zotero-code plan.
6. **Mixed denominators in multi-project documents**: P003 pairs
   Liberia-only 2,829 with project-wide 37%; P009's 379,162 is non-unique
   (doc's unique estimate ~137,920); P004 GEF ID 9060 means program in one
   doc, child project in another. Rule: every result carries scope +
   denominator.
7. **Budgets under-captured**: P002 digit misread (894.1M → 904.1M);
   P003 GEF-share-only (44.7M vs ≈308M all-sources); P004 co-financing
   208M omitted; P001/P006 doc-internal contradictions. Rule: data sheet
   wins; consider lead-financing vs co-financing sub-fields.
8. **Headline and negative results missed** in 8/10: 88.4M tCO2e (P002),
   28M ha + 140M tCO2 (P003), 973k ha marine (P004), yields +163–483% and
   incomes tripled (P006), >40k policies (P008), 4th PDO (P009), spillover
   PDO (P010); failed indicators/critical ratings never captured (P001 KP
   not achieved; P006 rated unsatisfactory). Rule: exhaustive extraction,
   PDO-first deterministic ranking, failures are findings.

## Hard errors by record (summary)

- P001: none hard; questionable — location_count (counting rule),
  disbursed (data sheet 3,720,411 vs Annex 2 3,629,277), funder (TLF),
  beneficiary vocab gap, headline-result selection.
- P002: start_year 2014→2017; budget 894.1M→904.1M.
- P003: start_year 2015→2017; beneficiary not-in-docs; result1 is
  Liberia-only; budget GEF-only; implementor "Mano Manufacturing Company"
  is a PPP concessionaire, not implementor (UNDP/WWF-US/IFC/UNEP/CI).
- P004: start 2010→2017; closure 2014→2025; beneficiary row-slip; results
  wrongly empty (973k ha; 119,902 ha; 393 women >200% target; 26 cases).
- P005: rationale projected back from next-phase recommendations; result2
  = survey sample; both IDs external; UCASN Portuguese name invented;
  **no climate content in the document at all** (scope flag).
- P006: beneficiary "artisanal fisher"→subsistence/smallholder farmers;
  document_type ICR→terminal evaluation (OPEV PPER); project_id external.
- P007: result1 = FGD sample; result2 57% unsupported; beneficiary
  "farmer association"→smallholder farmer; closure external; rationale
  quote is verbatim from the P008 document.
- P008: scale sub-national→national ("scope was nationwide"); rationale
  swapped from P007; result_notes mislabels the training topic; missed
  >40,000 policies sold.
- P009: funding_mechanism grant→blended (IDA credits 42.7M + IDA grants
  32.8M + GEF 15.5M); 379,162 needs non-unique caveat.
- P010: funding_mechanism grant→loan (99.3% IDA credit); result3 metric =
  lead-farmer awareness rate, not farmers reached; title typo "Souther";
  **P010_doc2 is a misfiled SWIOFish ISR** (belongs to P009's project).

## Actions

- Fold rules 1–8 into `R/extract_general.R` prompts (Round 1).
- Template questions for the owner: institutional beneficiary option;
  document_type mapping for program evaluations/PPERs; budget vs
  co-financing sub-fields; location_count counting rule; ID fields →
  Zotero document codes.
- Corpus: replace P010_doc2; decide P005 scope status; catalogue the gold
  documents in Zotero.
