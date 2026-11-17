# LENS H: THE COST (Economic & Resource Analysis)

Question: What does this seam cost to build, run, and maintain?

## H.1 Total Cost of Ownership

* BUILD COST: Engineering effort, testing infra, docs.
* RUN COST: Infra, egress data transfer, API fees, log/metric storage.
* MAINTAIN COST: Schema evolution, incident response MTTR x frequency, tech debt.
* OPPORTUNITY COST: Features blocked by fragile seams.

Flag seams where annual maintenance cost > original build cost.
