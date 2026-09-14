##############################################################################
# figure_workflow.R - the one-page picture of the pipeline for the protocol.
#
# Draws docs/workflow.png: where documents come from, what runs, the accuracy
# gate that decides whether we tune again or go to the full corpus, and every
# file the run leaves behind. Base graphics only, so it regenerates anywhere
# R runs and needs no diagram tool.
#
# Keep it in step with Section 7 of the protocol. If a step or an output
# changes, change it here and re-run - the figure is generated, not drawn by
# hand, so it cannot quietly fall out of date.
#
#   Rscript R/reporting/figure_workflow.R
##############################################################################

full <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
REPO <- normalizePath(file.path(dirname(sub("^--file=", "", full[1])), "..", ".."), mustWork = TRUE)
OUT  <- file.path(REPO, "docs", "workflow.png")

BLUE <- "#1B75BC"; BLUE_D <- "#125A91"; GREY <- "#6B6B6B"; INK <- "#222222"

png(OUT, width = 1700, height = 1150, res = 150)
op <- par(mar = c(0, 0, 0, 0), xaxs = "i", yaxs = "i")
plot(NA, xlim = c(0, 100), ylim = c(0, 100), axes = FALSE, xlab = "", ylab = "")

# rounded rectangle
rbox <- function(x, y, w, h, r = 1.2, fill = BLUE, border = NA) {
  a <- seq(0, pi / 2, length.out = 12)
  xs <- c(x - w/2 + r - r*cos(a), x + w/2 - r + r*sin(a),
          x + w/2 - r + r*cos(a), x - w/2 + r - r*sin(a))
  ys <- c(y + h/2 - r + r*sin(a), y + h/2 - r + r*cos(a),
          y - h/2 + r - r*sin(a), y - h/2 + r - r*cos(a))
  polygon(xs, ys, col = fill, border = border)
}
label <- function(x, y, lines, cex = 0.72, col = "white", font = 1) {
  n <- length(lines); step <- 2.1 * cex
  for (i in seq_len(n))
    text(x, y + (n - 1) / 2 * step - (i - 1) * step, lines[i],
         col = col, cex = cex, font = font)
}
node <- function(x, y, w, h, lines, fill = BLUE, cex = 0.72, font = 1) {
  rbox(x, y, w, h, fill = fill); label(x, y, lines, cex = cex, font = font)
}
# decision
diamond <- function(x, y, w, h, lines, cex = 0.7) {
  polygon(c(x, x + w/2, x, x - w/2), c(y + h/2, y, y - h/2, y),
          col = BLUE_D, border = NA)
  label(x, y, lines, cex = cex)
}
# stacked-document shape for the files a run leaves behind
docs <- function(x, y, w, h, lines, cex = 0.64) {
  for (k in 2:1) rbox(x + k * 0.7, y + k * 0.7, w, h, fill = "#7FB5DF")
  rbox(x, y, w, h, fill = BLUE); label(x, y, lines, cex = cex)
}
arrow <- function(x0, y0, x1, y1) arrows(x0, y0, x1, y1, length = 0.09,
                                         col = GREY, lwd = 1.6, xpd = NA)
elbow <- function(pts) {                       # right-angled connector
  for (i in seq_len(nrow(pts) - 2))
    segments(pts[i, 1], pts[i, 2], pts[i + 1, 1], pts[i + 1, 2], col = GREY, lwd = 1.6)
  n <- nrow(pts); arrow(pts[n - 1, 1], pts[n - 1, 2], pts[n, 1], pts[n, 2])
}

text(3, 95, "EXTRACTION WORKFLOW", adj = 0, cex = 1.5, font = 2, col = INK)
text(3, 91.2, "what runs, what it is checked against, and what it leaves behind",
     adj = 0, cex = 0.75, col = GREY)

SP <- 38                                        # the spine
node(SP, 84, 30, 8, c("Documents", "03_Documents\\{source}\\  -  in-scope only"))
arrow(SP, 80, SP, 76.5)
node(SP, 72, 30, 8, c("Session 1  -  verbatim extraction",
                      "every quote checked against its page"))
arrow(SP, 68, SP, 64.5)
node(SP, 60, 30, 8, c("Session 2  -  coding",
                      "verbatim extract into controlled vocabularies"))
arrow(SP, 56, SP, 51)

diamond(SP, 44, 26, 13, c("Accuracy against the", "gold standard", "above threshold?"))
text(SP - 14.5, 50.5, "on a subset:", adj = 1, cex = 0.63, col = GREY)
text(SP - 14.5, 48.2, "10 gold documents", adj = 1, cex = 0.63, col = GREY)

# NO - tune and come back
text(SP + 14.8, 46.2, "NO", adj = 0, cex = 0.66, col = INK)
node(80, 44, 30, 13, c("Improve the prompts", "sharpen the field definitions",
                       "add the actors and locations", "the documents actually name"),
     fill = BLUE_D, cex = 0.66)
arrow(SP + 13, 44, 65, 44)
elbow(rbind(c(80, 50.5), c(80, 72), c(55.5, 72)))
text(82, 62, "run it again", adj = 0, cex = 0.62, col = GREY)

# YES - go to the whole corpus
text(SP + 1.2, 35.5, "YES", adj = 0, cex = 0.66, col = INK)
arrow(SP, 37.5, SP, 33.5)
node(SP, 29, 30, 8, c("Run on the full corpus", "656 in-scope documents"))

# the outputs - one row, six files, nothing clipped or overlapping
text(SP, 22.6, "what a run leaves behind", cex = 0.78, font = 2, col = INK)
segments(SP, 25.0, SP, 24.0, col = GREY, lwd = 1.6)
segments(SP, 21.0, SP, 19.6, col = GREY, lwd = 1.6)
xs <- c(8.5, 24.8, 41.1, 57.4, 73.7, 90)
segments(min(xs), 19.6, max(xs), 19.6, col = GREY, lwd = 1.6)
for (x in xs) arrow(x, 19.6, x, 16.4)

docs(xs[1], 11.5, 14, 9, c("EXTRACTED DATA", "project sheet", "+ location sheet"))
docs(xs[2], 11.5, 14, 9, c("Proposed", "new actors", "to review"))
docs(xs[3], 11.5, 14, 9, c("Proposed", "new locations", "to review"))
docs(xs[4], 11.5, 14, 9, c("Fields flagged", "for manual", "review"))
docs(xs[5], 11.5, 14, 9, c("Questions for the", "template owner"))
docs(xs[6], 11.5, 14, 9, c("Cost and", "model use", "(not yet written)"))

text(SP, 3.4, "the first is the result; the other five are what needs a person",
     cex = 0.68, col = GREY)

par(op); invisible(dev.off())
cat("written:", OUT, "\n")
