"""
Swap external IDs for Salesforce IDs in a CSV column, the classic "VLOOKUP" step
of a Data Loader migration.

Why it's needed: the Bulk API can link records by external ID only through a named
relationship (e.g. Account.Lakeside_Id__c). Opportunity.ContactId and Task.WhoId
have no usable relationship name, so we look the IDs up ourselves after the
Contacts are loaded.

Usage:
    python3 resolve_ids.py <input.csv> <id_map.csv> <old_column> <new_column> <output.csv>

    id_map.csv is the output of:
        sf data query -q "SELECT Id, Lakeside_Id__c FROM Contact WHERE Lakeside_Id__c != null" -r csv

Example:
    python3 resolve_ids.py gifts.csv contact_ids.csv Contact.Lakeside_Id__c ContactId gifts_resolved.csv
"""

import csv
import sys


def load_id_map(path: str) -> dict:
    """Read the query export into {"DN-00001": "003...", ...}."""
    with open(path, newline="", encoding="utf-8") as handle:
        # PY: a dict comprehension, like building a Map<String, Id> in a for-loop.
        return {row["Lakeside_Id__c"]: row["Id"] for row in csv.DictReader(handle)}


def resolve(input_path: str, id_map: dict, old_column: str, new_column: str, output_path: str) -> int:
    """Copy input to output, replacing old_column's values with mapped IDs. Returns rows written."""
    with open(input_path, newline="", encoding="utf-8") as source:
        reader = csv.DictReader(source)
        # PY: rename the header in place, keeping column order.
        fieldnames = [new_column if name == old_column else name for name in reader.fieldnames]
        rows = []
        for row in reader:
            external_id = row.pop(old_column)    # PY: pop() removes the key and returns its value
            if external_id not in id_map:
                # Fail loudly: silently dropping the link would create orphaned gifts.
                sys.exit(f"No Salesforce ID found for {external_id}; was it imported?")
            row[new_column] = id_map[external_id]
            rows.append(row)

    with open(output_path, "w", newline="", encoding="utf-8") as target:
        writer = csv.DictWriter(target, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return len(rows)


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    # PY: sys.argv[0] is the script name; unpacking assigns the five arguments at once.
    in_csv, map_csv, old_col, new_col, out_csv = sys.argv[1:]
    count = resolve(in_csv, load_id_map(map_csv), old_col, new_col, out_csv)
    print(f"Resolved {count} rows: {old_col} -> {new_col} in {out_csv}")
