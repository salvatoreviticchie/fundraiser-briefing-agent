"""
Generate fake donor data for Lakeside Community Trust as CSV files.

Everything here is synthetic: names are random combinations, emails use the
reserved example.com domain, and no real person or organisation is involved.

Output (one CSV per Salesforce object, in import order):
    households.csv  -> Account
    donors.csv      -> Contact
    gifts.csv       -> Opportunity  (Closed Won = received gift)
    notes.csv       -> Donor_Note__c
    tasks.csv       -> Task

Import them with scripts/import-demo-data.sh (see the README).

Run it:
    python3 data-generator/generate_data.py                  # 30 donors, as of today
    python3 data-generator/generate_data.py --donors 10 --seed 7 --as-of 2026-06-30

Python notes for Apex developers are marked "PY:".
"""

# PY: imports are like Apex's built-in namespaces, but explicit. These are all
# part of Python's standard library, so there is nothing to pip install.
import argparse
import calendar
import csv
import random
import unicodedata
from datetime import date, timedelta
from pathlib import Path

# ---------------------------------------------------------------------------
# Reference data
# ---------------------------------------------------------------------------
# PY: a list literal, like List<String>{...} in Apex. Swiss-style mix of
# German, French and Italian names, combined at random so nobody real is described.
FIRST_NAMES = [
    "Anna", "Lukas", "Sophie", "Matteo", "Léa", "Jonas", "Chiara", "Nicolas",
    "Laura", "David", "Elena", "Simon", "Camille", "Reto", "Giulia", "Thomas",
    "Nina", "Fabio", "Claire", "Martin", "Sara", "Luca", "Mia", "Andreas",
]
LAST_NAMES = [
    "Keller", "Meier", "Rossi", "Dubois", "Brunner", "Favre", "Steiner", "Bianchi",
    "Fischer", "Rochat", "Huber", "Moretti", "Gerber", "Perrin", "Baumann", "Galli",
    "Schmid", "Girard", "Frei", "Lombardi", "Weber", "Bonvin", "Zimmermann", "Conti",
]
CITIES = ["Lucerne", "Zug", "Lausanne", "Lugano", "Neuchâtel", "Thun", "Biel", "Locarno"]

# Lakeside Community Trust's (fictional) programmes. Notes mention these so the
# Data 360 retriever has something meaningful to find.
PROGRAMMES = [
    "youth literacy programme",
    "lake shore clean-up",
    "community food bank",
    "music school scholarships",
    "elder companionship visits",
    "refugee language cafés",
    "community garden",
]

# Donor archetypes drive the shape of each gift history, so the data exercises
# every branch of the Apex scoring logic (low, medium and high risk, new, prospect).
# PY: a dict maps keys to values, like Map<String, Integer> in Apex.
# Weights are relative: "loyal_monthly" appears about 3x as often as "lapsed".
ARCHETYPE_WEIGHTS = {
    "loyal_monthly": 3,
    "lapsing_monthly": 2,
    "growing_annual": 4,
    "steady_annual": 5,
    "declining": 3,
    "lapsed": 2,
    "new": 3,
    "prospect": 3,
    "major_grant": 2,
}

# Which capacity bands (Contact.Capacity_Rating__c) make sense for each archetype.
CAPACITY_BY_ARCHETYPE = {
    "loyal_monthly": ["C", "D"],
    "lapsing_monthly": ["C", "D"],
    "growing_annual": ["A", "B", "C"],
    "steady_annual": ["B", "C"],
    "declining": ["B", "C"],
    "lapsed": ["A", "B", "C"],
    "new": ["B", "C", "D"],
    "prospect": ["A", "B", "C"],
    "major_grant": ["A"],
}

# Salesforce counts most records as 2 KB of data storage; Developer Edition orgs have 5 MB.
STORAGE_KB_PER_RECORD = 2

# ---------------------------------------------------------------------------
# Hand-written "hero" donors for the demo script. The rest are generated.
# ---------------------------------------------------------------------------
HERO_DONORS = [
    {
        "first": "Eleanor", "last": "Hart", "preferred": "Dr Hart", "city": "Lucerne",
        "archetype": "growing_annual", "capacity": "B",
        "notes": [
            ("Meeting", 70, "Lunch at the boathouse: literacy programme",
             "Eleanor was very moved by the reading-buddies story from the spring report. "
             "She asked whether a gift could fund a second after-school site in Kriens. "
             "She mentioned her late husband taught primary school for 30 years and she would "
             "like any named fund to honour him. Prefers meetings before noon; no phone calls."),
            ("Call", 200, "Thank-you call after annual gift",
             "Thanked her for this year's gift. She said she is reviewing her estate plans with her "
             "lawyer this autumn and is open to discussing a legacy gift next year. Keep it low-key."),
            ("Grant Report", 400, "Literacy programme impact report shared",
             "Sent the 12-month literacy report: 140 children, average reading age up 9 months. "
             "Eleanor replied asking for more detail on volunteer training costs."),
        ],
    },
    {
        "first": "Marco", "last": "Bernasconi", "preferred": "Marco", "city": "Lugano",
        "archetype": "lapsing_monthly", "capacity": "C",
        "notes": [
            ("Event", 300, "Lake clean-up volunteer day",
             "Marco brought his two teenagers to the lake shore clean-up and stayed for the barbecue. "
             "Talked about moving his monthly gift to the clean-up fund specifically."),
            ("Call", 160, "Card payment failed",
             "Monthly card payment bounced; Marco said his bank card was replaced after a fraud alert "
             "and he would update the details. No update received since."),
        ],
    },
    {
        "first": "Claire", "last": "Rochat", "preferred": "Claire", "city": "Lausanne",
        "archetype": "lapsed", "capacity": "A",
        "notes": [
            ("Meeting", 900, "Coffee: food bank expansion",
             "Claire gave the lead gift for the food bank cold-store. She was frustrated the opening "
             "was delayed by six months and felt she had not been kept informed. "
             "Any re-engagement should start with an honest update on the project, not an ask."),
        ],
    },
]


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
def add_months(d: date, months: int) -> date:
    """Shift a date by whole months, clamping the day (31 Jan + 1 month = 28/29 Feb).

    PY: Python's date has no addMonths() like Apex, so we write our own.
    The ": date" and "-> date" parts are type hints: documentation only, not enforced.
    """
    month_index = d.month - 1 + months
    year = d.year + month_index // 12      # PY: // is integer division
    month = month_index % 12 + 1           # PY: % is modulo, like Math.mod()
    last_day = calendar.monthrange(year, month)[1]
    return date(year, month, min(d.day, last_day))


def to_ascii(text: str) -> str:
    """Strip accents: "Léa" -> "Lea". Salesforce rejects non-ASCII characters in Email fields.

    PY: NFKD splits "é" into "e" plus a combining accent; encoding to ASCII with
    "ignore" then drops the accent and keeps the letter.
    """
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")


def round_to(amount: float, step: int) -> int:
    """Round to a believable gift amount, e.g. 487 -> 500 with step 50."""
    return max(step, int(round(amount / step)) * step)


# ---------------------------------------------------------------------------
# Gift histories, one function per archetype
# ---------------------------------------------------------------------------
# Each returns a list of (gift_date, amount, gift_type) tuples.
# PY: a tuple is an immutable, fixed-size group of values, e.g. (date, 100, "One_off").

def monthly_series(as_of: date, months: int, last_gift_months_ago: int, amount: int):
    """`months` consecutive monthly gifts, the newest `last_gift_months_ago` months ago."""
    start = add_months(as_of, -last_gift_months_ago)
    # PY: a "list comprehension" builds a list in one line, like a for-loop that .add()s.
    return [(add_months(start, -i), amount, "Recurring") for i in range(months)]


def gifts_for(archetype: str, as_of: date, rng: random.Random):
    """Build a gift history that matches the archetype's behaviour."""
    if archetype == "loyal_monthly":
        return monthly_series(as_of, rng.randint(12, 24), 0, rng.choice([20, 30, 50, 100]))

    if archetype == "lapsing_monthly":
        # Gave monthly, then stopped 4-8 months ago.
        return monthly_series(as_of, rng.randint(12, 20), rng.randint(4, 8), rng.choice([25, 50, 75]))

    if archetype == "growing_annual":
        amount = rng.randint(1500, 12000)
        last = as_of - timedelta(days=rng.randint(30, 100))
        gifts = []
        for years_ago in range(rng.randint(3, 5)):
            gifts.append((add_months(last, -12 * years_ago), round_to(amount, 250), "One_off"))
            amount /= rng.uniform(1.1, 1.3)   # older gifts were smaller
        return gifts

    if archetype == "steady_annual":
        amount = rng.randint(500, 8000)
        last = as_of - timedelta(days=rng.randint(30, 300))
        return [
            (add_months(last, -12 * y), round_to(amount * rng.uniform(0.95, 1.05), 50), "One_off")
            for y in range(rng.randint(3, 6))
        ]

    if archetype == "declining":
        amount = rng.randint(2000, 10000)
        last = as_of - timedelta(days=rng.randint(60, 200))
        # This year's gift is 40-70% smaller than last year's.
        return [
            (last, round_to(amount * rng.uniform(0.3, 0.6), 250), "One_off"),
            (add_months(last, -12), round_to(amount, 250), "One_off"),
            (add_months(last, -24), round_to(amount, 250), "One_off"),
        ]

    if archetype == "lapsed":
        amount = rng.randint(1000, 20000)
        last = add_months(as_of, -rng.randint(26, 40))
        return [(add_months(last, -12 * y), round_to(amount, 500), "One_off") for y in range(rng.randint(2, 4))]

    if archetype == "new":
        first = as_of - timedelta(days=rng.randint(20, 150))
        gifts = [(first, rng.choice([100, 250, 500, 1000]), "One_off")]
        if rng.random() < 0.5:   # PY: random() returns a float in [0, 1)
            gifts.append((first + timedelta(days=rng.randint(10, 15)), rng.choice([100, 250]), "One_off"))
        return gifts

    if archetype == "major_grant":
        amount = rng.randint(25000, 90000)
        last = as_of - timedelta(days=rng.randint(30, 200))
        return [(add_months(last, -12 * y), round_to(amount, 5000), "Grant") for y in range(rng.randint(2, 4))]

    return []   # "prospect": no gifts yet


# ---------------------------------------------------------------------------
# Notes and tasks
# ---------------------------------------------------------------------------
NOTE_TEMPLATES = [
    ("Meeting", "Coffee: {programme}",
     "{first} asked for an update on the {programme} and wanted to know how many volunteers are involved. "
     "Mentioned {detail}."),
    ("Call", "Check-in call",
     "Short call with {first}. Interested in the {programme}; prefers updates by email. Mentioned {detail}."),
    ("Event", "Supporters' evening",
     "{first} attended the supporters' evening and spoke with the {programme} coordinator. Mentioned {detail}."),
    ("Grant Report", "Impact report: {programme}",
     "Shared the annual impact report for the {programme}. {first} replied that the outcomes were clear "
     "and asked about plans for next year."),
]
PERSONAL_DETAILS = [
    "a grandchild starting school in the autumn",
    "plans to retire next spring",
    "volunteering at a local choir",
    "a preference for anonymous giving",
    "interest in a matched-giving campaign",
    "a recent house move to the lakeside",
    "that their employer offers gift matching",
]


def notes_for(donor: dict, as_of: date, rng: random.Random, next_id):
    """Two or three templated notes per donor (hero donors use their hand-written notes)."""
    if donor.get("notes"):
        templates = list(donor["notes"])
    else:
        templates = []
        programme = rng.choice(PROGRAMMES)
        for kind, subject, body in rng.sample(NOTE_TEMPLATES, k=rng.randint(2, 3)):
            text = body.format(first=donor["first"], programme=programme, detail=rng.choice(PERSONAL_DETAILS))
            templates.append((kind, rng.randint(15, 600), subject.format(programme=programme), text))

    return [
        {
            "Lakeside_Id__c": next_id("NT"),
            "Name": subject[:80],                      # Name field max length is 80
            "Contact__r.Lakeside_Id__c": donor["id"],  # link to parent via its external ID
            "Note_Type__c": kind.replace(" ", "_"),    # picklist API names: "Grant Report" -> "Grant_Report"
            "Note_Date__c": (as_of - timedelta(days=days_ago)).isoformat(),
            "Body__c": body,
        }
        for kind, days_ago, subject, body in templates
    ]


def tasks_for(donor: dict, as_of: date, rng: random.Random, next_id):
    """One completed touchpoint (last engagement) and sometimes an open follow-up."""
    tasks = [{
        "Lakeside_Id__c": next_id("TK"),
        "Subject": rng.choice(["Thank-you call", "Stewardship visit", "Sent impact report"]),
        "Who.Lakeside_Id__c": donor["id"],   # swapped for WhoId by resolve_ids.py
        "Status": "Completed",
        "Priority": "Normal",
        "ActivityDate": (as_of - timedelta(days=rng.randint(10, 250))).isoformat(),
        "Description": "Logged by demo data generator.",
    }]
    if donor["archetype"] != "lapsed" and rng.random() < 0.7:
        tasks.append({
            "Lakeside_Id__c": next_id("TK"),
            "Subject": rng.choice([
                "Send programme update before meeting",
                "Confirm interest in site visit",
                "Follow up on matched-giving form",
                "Invite to spring supporters' evening",
            ]),
            "Who.Lakeside_Id__c": donor["id"],   # swapped for WhoId by resolve_ids.py
            "Status": "Not Started",
            "Priority": rng.choice(["High", "Normal"]),
            # Some open tasks are overdue (negative offset), which the agent should flag.
            "ActivityDate": (as_of + timedelta(days=rng.randint(-20, 30))).isoformat(),
            "Description": "Logged by demo data generator.",
        })
    return tasks


# ---------------------------------------------------------------------------
# Main build
# ---------------------------------------------------------------------------
def build(donor_count: int, as_of: date, seed: int) -> dict:
    """Return {file name: list of row dicts}. All randomness comes from one seeded generator,
    so the same seed and as-of date always produce identical files."""
    rng = random.Random(seed)

    # PY: a closure: next_id "remembers" the counters dict between calls,
    # a bit like a static Map in an Apex class.
    counters = {}

    def next_id(prefix: str) -> str:
        counters[prefix] = counters.get(prefix, 0) + 1
        return f"{prefix}-{counters[prefix]:05d}"   # PY: f-string, e.g. "GF-00042"

    # Start with the hero donors, then fill up with generated ones.
    donors = [dict(hero) for hero in HERO_DONORS][:donor_count]
    used_names = {(d["first"], d["last"]) for d in donors}   # PY: a set, like Set<...>
    archetypes = list(ARCHETYPE_WEIGHTS)
    weights = list(ARCHETYPE_WEIGHTS.values())

    while len(donors) < donor_count:
        first, last = rng.choice(FIRST_NAMES), rng.choice(LAST_NAMES)
        if (first, last) in used_names:
            continue
        used_names.add((first, last))
        archetype = rng.choices(archetypes, weights=weights)[0]
        donors.append({
            "first": first, "last": last, "preferred": "", "city": rng.choice(CITIES),
            "archetype": archetype, "capacity": rng.choice(CAPACITY_BY_ARCHETYPE[archetype]),
        })

    files = {"households.csv": [], "donors.csv": [], "gifts.csv": [], "notes.csv": [], "tasks.csv": []}

    for donor in donors:
        household_id = next_id("HH")
        donor["id"] = next_id("DN")

        files["households.csv"].append({
            "Lakeside_Id__c": household_id,
            "Name": f"{donor['last']} Household ({donor['first']})",
            "BillingCity": donor["city"],
            "BillingCountry": "Switzerland",
        })
        files["donors.csv"].append({
            "Lakeside_Id__c": donor["id"],
            "Account.Lakeside_Id__c": household_id,
            "FirstName": donor["first"],
            "LastName": donor["last"],
            "Preferred_Name__c": donor["preferred"],
            "Email": to_ascii(f"{donor['first']}.{donor['last']}@example.com").lower(),
            "MailingCity": donor["city"],
            "MailingCountry": "Switzerland",
            "Capacity_Rating__c": donor["capacity"],
            # Kept in the description so the archetype is visible in the org when demoing.
            "Description": f"Demo archetype: {donor['archetype']}",
        })

        # PY: sorted(..., reverse=True) returns a new list, newest gift first.
        for gift_date, amount, gift_type in sorted(gifts_for(donor["archetype"], as_of, rng), reverse=True):
            files["gifts.csv"].append({
                "Lakeside_Id__c": next_id("GF"),
                "Name": f"{donor['last']} {gift_type.replace('_', '-')} gift {gift_date.isoformat()}",
                "Account.Lakeside_Id__c": household_id,
                "Contact.Lakeside_Id__c": donor["id"],   # swapped for ContactId by resolve_ids.py
                "Amount": amount,
                "CloseDate": gift_date.isoformat(),
                "StageName": "Closed Won",
                "Gift_Type__c": gift_type,
            })

        # Major-gift prospects get an open (not yet won) solicitation, which must NOT count as giving.
        if donor["archetype"] in ("prospect", "growing_annual") and rng.random() < 0.4:
            files["gifts.csv"].append({
                "Lakeside_Id__c": next_id("GF"),
                "Name": f"{donor['last']} major gift proposal",
                "Account.Lakeside_Id__c": household_id,
                "Contact.Lakeside_Id__c": donor["id"],
                "Amount": rng.choice([10000, 25000, 50000]),
                "CloseDate": (as_of + timedelta(days=90)).isoformat(),
                "StageName": "Proposal/Price Quote",
                "Gift_Type__c": "One_off",
            })

        files["notes.csv"].extend(notes_for(donor, as_of, rng, next_id))
        files["tasks.csv"].extend(tasks_for(donor, as_of, rng, next_id))

    return files


def write_csvs(files: dict, out_dir: Path) -> None:
    """Write each list of dicts to a CSV whose header is the dict keys."""
    out_dir.mkdir(parents=True, exist_ok=True)
    # PY: .items() yields (key, value) pairs, like iterating a Map's entrySet.
    for name, rows in files.items():
        if not rows:
            continue
        # PY: "with" closes the file automatically, like a try/finally.
        # newline="" stops Python adding blank lines; LF endings are what `sf data upsert bulk` expects.
        with open(out_dir / name, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()), lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate fake Lakeside Community Trust donor data.")
    parser.add_argument("--donors", type=int, default=30, help="number of donors (default 30)")
    parser.add_argument("--seed", type=int, default=42, help="random seed for reproducible output")
    parser.add_argument("--as-of", type=date.fromisoformat, default=date.today(),
                        help="reference date, YYYY-MM-DD (default: today)")
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "output",
                        help="output folder (default: data-generator/output)")
    args = parser.parse_args()
    if not 1 <= args.donors <= 300:
        parser.error("--donors must be between 1 and 300 (Developer Edition storage is small)")

    files = build(args.donors, args.as_of, args.seed)
    write_csvs(files, args.out)

    total = sum(len(rows) for rows in files.values())
    print(f"Wrote {total} records to {args.out} (as of {args.as_of}, seed {args.seed}):")
    for name, rows in files.items():
        print(f"  {name:<15} {len(rows):>4} rows")
    print(f"Estimated data storage: ~{total * STORAGE_KB_PER_RECORD / 1024:.1f} MB "
          f"(Developer Edition orgs have 5 MB in total)")


# PY: this block only runs when the file is executed directly, not when imported.
if __name__ == "__main__":
    main()
