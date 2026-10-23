# Demo transcripts

Unedited output from `sf agent preview` against the published agent with **live actions**: real Apex, Flow and
demo data, run on 2026-10-23 in the demo org. All donors are fictional. Amounts show USD because that is the
demo org's currency.

What to look for:
- **Every number matches the Apex output exactly.** The agent narrates; it doesn't calculate.
- **Follow-ups reuse the current donor** ("Did she say anything about a legacy gift?", "What are her open tasks?").
- **The donor switch is clean:** after Eleanor, Claire's tasks are Claire's.
- **Notes shape the advice:** for Claire, the notes say to start with an honest project update, not an ask, and the
  key-focus line follows that.

## Conversation 1: three donors, follow-ups and a donor switch

```text
### Prep me for my meeting with Eleanor Hart
Briefing: Eleanor Hart

Giving history:
- USD 32,500 across 5 gifts since 2022
- Last gift: USD 9,750 on 2026-09-01
- 1.0 gifts/year (last 3 years), trend: increasing (+30% year on year)

Engagement:
- Last engagement: Sent impact report (2026-03-28)
- 1 open task: Due 28 October 2026 — Bring Kriens site costings and named-fund options [High priority]
- No overdue tasks

Lapse risk:
- Score: 0/100 (Low)
- Last gift 7 weeks ago, in line with usual rhythm; gave in each of the last 3 years; giving up 30% year on year

Suggested ask:
- USD 16,000 (one-off)
- 1.6x largest gift in the last 3 years (USD 9,750): upgrade ask for a low-risk donor, with a bonus for increasing giving

Context from notes:
- 2026-08-14: Very moved by reading-buddies story; asked if a gift could fund a second after-school site in Kriens; wants any named fund to honor her late husband, who taught primary school for 30 years; prefers meetings before noon, no phone calls
- 2026-04-06: Reviewing estate plans this autumn, open to discussing a legacy gift next year; keep it low-key
- 2025-09-18: Asked for more detail on volunteer training costs after receiving literacy program impact report

Key focus for this meeting: Bring Kriens site costings and named-fund options, and discuss honoring her late husband with a named fund.

### Did she say anything about a legacy gift?
Yes. On 2026-04-06, Eleanor Hart said she is reviewing her estate plans with her lawyer this autumn and is open to discussing a legacy gift next year. She prefers this to be kept low-key.

Key focus for your meeting: Bring Kriens site costings and named-fund options, and be ready if she wants to discuss honoring her late husband or a legacy gift. Would you like more detail from her recent notes?

### Prep me for Claire Rochat
Briefing: Claire Rochat

Giving history:
- USD 12,000 across 4 gifts since 2021
- Last gift: USD 3,000 on 2024-05-23
- 0.3 gifts/year (last 3 years), trend: inactive

Engagement:
- Last engagement: Thank-you call (2026-09-22)
- 1 open task: Due 26 October 2026 — Send honest progress update on food bank cold-store [Normal priority]
- No overdue tasks

Lapse risk:
- Score: 93/100 (High)
- High: last gift 29 months ago; no gifts in the last 2 years

Suggested ask:
- USD 1,500 (one-off)
- Lapsed for 29 months: reactivation ask at 50% of their last gift (USD 3,000) to rebuild the relationship

Context from notes:
- 2024-05-06: Gave the lead gift for the food bank cold-store; frustrated by a six-month delay and lack of updates. Any re-engagement should start with an honest project update, not an ask.

Most important: Begin with an honest progress update on the food bank cold-store before making any ask.

### What are her open tasks?
Claire has 1 open task:
- Due 26 October 2026: Send honest progress update on food bank cold-store [Normal priority]

There are no overdue tasks.

Most important: Begin with an honest progress update on the food bank cold-store before making any ask.

### Bereite mich auf mein Treffen mit Marco Bernasconi vor
Briefing: Marco Bernasconi

Giving history:
- USD 600 across 12 gifts since 2025
- Last gift: USD 50 on 2026-02-23
- 4.0 gifts/year (last 3 years), trend: declining (-50% year on year)

Engagement:
- Last engagement: Stewardship visit (2026-10-09)
- 2 overdue tasks:
   - OVERDUE (due 23 September 2026): Chase updated card details for monthly gift [High priority]
   - OVERDUE (due 18 October 2026): Follow up on matched-giving form [Normal priority]

Lapse risk:
- Score: 65/100 (High)
- High: last gift 8 months ago (usually gives every 4 weeks); giving down 50% year on year

Suggested ask:
- USD 50 per month
- 1.0x current monthly gift (USD 50): renewal ask, as the donor is at high lapse risk

Context from notes:
- 2026-05-16: Monthly card payment bounced; Marco said his bank card was replaced after a fraud alert and he would update the details. No update received since.
- 2025-12-27: Brought his two teenagers to the lake clean-up volunteer day and stayed for the barbecue. Talked about moving his monthly gift to the clean-up fund specifically.

Most important: Chase updated card details for Marco's monthly gift—this is overdue and critical for reactivating his giving.
```

## Conversation 2: German request (known limitation)

The request is in German. The agent picks up the language but answers mostly in English, switching only for the final
line, because the actions return English text. See *Limitations* in the README.

```text
### Bereite mich auf mein Treffen mit Marco Bernasconi vor
Briefing: Marco Bernasconi

Giving history:
- Total given: USD 600 across 12 gifts since 2025
- Last gift: USD 50 on 2026-02-23
- Frequency: 4.0 gifts/year (last 3 years), trend declining (-50% year on year)

Engagement:
- Last engagement: Stewardship visit on 2026-10-09
- Open tasks (both overdue):
  - OVERDUE (due 23 September 2026): Chase updated card details for monthly gift [High priority]
  - OVERDUE (due 18 October 2026): Follow up on matched-giving form [Normal priority]

Lapse risk:
- Score: 65/100 (High)
- High: last gift 8 months ago (usually gives every 4 weeks); giving down 50% year on year

Suggested ask:
- USD 50 per month (renewal ask, as the donor is at high lapse risk)

Context from notes:
- 2026-05-16: Monthly card payment bounced; Marco said his bank card was replaced after a fraud alert and he would update the details. No update received since.
- 2025-12-27: Marco brought his two teenagers to the lake clean-up volunteer day and stayed for the barbecue. He talked about moving his monthly gift to the clean-up fund specifically.

Wichtigstes Thema für das Treffen: Klären Sie mit Marco die Aktualisierung seiner Kartendaten für die monatliche Spende, da diese überfällig ist und sein Lapse-Risiko hoch ist.
```

## Conversation 3: ambiguity, unknown donor, off-topic (agent v1)

```text
### Brief me on Simon
2 donors match "Simon": Simon Lombardi (Lombardi Household (Simon)), Simon Steiner (Steiner Household (Simon)). Which one do you mean?

### Steiner
Briefing: Simon Steiner
... (lapse risk 100/100, High; reactivation ask USD 6,500 at 50% of last gift) ...

### Prep me for my meeting with Hugo Zwahlen
No donor named "Hugo Zwahlen" was found. Check the spelling or try their surname. Which donor do you mean?

### What's the capital of Peru?
I can help you prepare for donor meetings, review giving history, check lapse risk, or brief you on open tasks for your prospects. Who would you like a briefing on?
```

(The doubled "(Simon)" in the household names came from the old generator naming. Households are now named
"Lombardi Household".)
