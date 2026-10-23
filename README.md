# Fundraiser Briefing Agent

> An Agentforce agent that prepares a major-gifts officer for a donor meeting in seconds.
> Built for **Lakeside Community Trust**, a fictional Swiss nonprofit. All donors, gifts and notes are synthetic.
> Amounts are in **CHF**.

**Status:** 🚧 Phase 1 (scaffolding). Sections marked _TODO_ are filled in as each phase lands.

---

## 1. The business problem

Major-gifts officers typically spend 20–40 minutes before each donor meeting clicking through
gift history, activity timelines and scattered meeting notes to answer five questions:

1. How has this person given to us, and is it going up or down?
2. When did we last speak, and what did we promise to follow up on?
3. Are we at risk of losing them?
4. What should I ask for?
5. What did they tell us last time that I must not forget?

This project lets the officer type **"Prep me for my meeting with Eleanor Hart"** and get a
short, consistent briefing that answers all five. The numbers are computed in code, not guessed by the LLM.

## 2. What the briefing contains

| Section | Source | Computed by |
| --- | --- | --- |
| Giving history (total, last gift, frequency, trend) | Closed Won Opportunities | Apex `DonorBriefingService` |
| Last engagement & open tasks | Task / Event | Flow action |
| Lapse-risk score + one-line explanation | Gift history (RFM) | Apex `DonorBriefingService` |
| Suggested ask amount + reasoning | Gift history + capacity rating | Apex `DonorBriefingService` |
| Relevant context from notes | `Donor_Note__c` → Data 360 search index | Agentforce retriever |

## 3. Architecture

_TODO (Phase 2+): finalise once components exist._

```mermaid
flowchart LR
    U[Gift officer<br/>Agentforce panel] --> A[Agentforce agent<br/>Topic: Donor Meeting Prep]
    A -->|Apex action| S[DonorBriefingService<br/>@InvocableMethod]
    A -->|Flow action| F[Get Open Engagements<br/>Autolaunched Flow]
    A -->|Retriever| R[Data 360 Retriever]
    S --> O[(Contact / Account<br/>Opportunity)]
    F --> T[(Task / Event)]
    R --> I[Search Index<br/>chunked + vectorised]
    I --> D[(Donor_Note__c<br/>via CRM data stream)]
    G[Python data generator] -. CSV import .-> O
    G -. CSV import .-> D
```

## 4. Data model

_TODO: final field list._ See [Design decisions](#7-design-decisions--trade-offs) for why this model was chosen over Nonprofit Cloud.

## 5. Repository layout

```text
force-app/main/default/
  classes/          Apex: DonorBriefingService, scoring logic, TestDataFactory, tests
  flows/            Autolaunched flow for open tasks / engagements
  objects/          Custom fields + Donor_Note__c
  permissionsets/   Least-privilege access for the gift-officer persona
  genAiPlugins/     Agentforce topic (added in a later phase)
  genAiFunctions/   Agent action definitions (added in a later phase)
data-generator/     Python script that produces fake CSVs for import
docs/               Data 360 retriever setup, screenshots, ADRs
config/             Scratch-org definition
scripts/apex/       Anonymous Apex helpers (e.g. demo data seeding)
```

## 6. Setup

_TODO: verified, copy-pasteable steps._

Prerequisites: Salesforce CLI (`sf`) v2, a Developer Edition org with Agentforce and Data 360
enabled, and Python 3.10 or later.

1. Clone the repo and authenticate: `sf org login web -a lakeside-dev`
   - In Setup → Company Information, set **Currency Locale** to a Swiss locale (CHF).
     The org is single-currency, so `Opportunity.Amount` is stored in CHF.
2. Deploy metadata: `sf project deploy start -o lakeside-dev`
3. Assign permission set: _TODO_
4. Generate and import data: _TODO_
5. Configure the Data 360 retriever: see `docs/data-360-retriever-setup.md` (_TODO_)
6. Activate the agent and try: _"Prep me for my meeting with …"_

## 7. Design decisions & trade-offs

_TODO: expand each into a short ADR-style entry._

- **Standard objects over Nonprofit Cloud:** chosen because the target org has neither NPC nor Person Accounts.
- **Single currency (CHF):** no multi-currency. Apex labels amounts with the org currency rather than hard-coding a symbol.
- **Deterministic scoring in Apex, narrative in the LLM:** numbers must be auditable and testable.
- **Compute on read vs stored roll-ups:** _TODO_
- **Custom `Donor_Note__c` vs ContentNote for unstructured text:** _TODO_
- **Rule-based RFM lapse risk vs ML model:** _TODO_

## 8. Testing

_TODO: coverage report, test strategy (TestDataFactory, boundary cases for scoring)._

## 9. Limitations & next steps

_TODO_

## Licence

MIT. All data is synthetic, and any resemblance to real people or organisations is coincidental.
