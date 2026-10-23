#!/usr/bin/env bash
# Load the generated CSVs into an org with Bulk API 2.0 upserts.
#
# Upserting on Lakeside_Id__c (an external ID) means:
#   - re-running is safe: existing rows are updated, not duplicated
#   - children reference parents by external ID where Salesforce allows it
#     (Account.Lakeside_Id__c, Contact__r.Lakeside_Id__c)
#   - Opportunity.ContactId and Task.WhoId have no relationship name, so their
#     Contact IDs are resolved after Contacts load (data-generator/resolve_ids.py)
#
# Usage: scripts/import-demo-data.sh [target-org-alias]
# Prerequisite: the running user has the Lakeside_Data_Admin permission set.
set -euo pipefail

ORG="${1:-agentforce-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/data-generator/output"

if [[ ! -f "$DIR/donors.csv" ]]; then
  echo "No CSVs found in $DIR. Run: python3 data-generator/generate_data.py" >&2
  exit 1
fi

upsert() {
  echo "==> $1  <-  $(basename "$2")"
  sf data upsert bulk -o "$ORG" -s "$1" -f "$2" -i Lakeside_Id__c --line-ending LF -w 10
}

# 1. Parents.
upsert Account "$DIR/households.csv"
upsert Contact "$DIR/donors.csv"

# 2. Look up the new Contact IDs and swap them into the gift and task files.
echo "==> Resolving Contact IDs"
sf data query -o "$ORG" -r csv \
  -q "SELECT Id, Lakeside_Id__c FROM Contact WHERE Lakeside_Id__c != null" > "$DIR/contact_ids.csv"
python3 "$ROOT/data-generator/resolve_ids.py" "$DIR/gifts.csv" "$DIR/contact_ids.csv" \
  Contact.Lakeside_Id__c ContactId "$DIR/gifts_resolved.csv"
python3 "$ROOT/data-generator/resolve_ids.py" "$DIR/tasks.csv" "$DIR/contact_ids.csv" \
  Who.Lakeside_Id__c WhoId "$DIR/tasks_resolved.csv"

# 3. Children.
upsert Opportunity "$DIR/gifts_resolved.csv"
upsert Donor_Note__c "$DIR/notes.csv"
upsert Task "$DIR/tasks_resolved.csv"

echo "Done. Remove the demo data later with: sf apex run -o $ORG -f scripts/apex/delete-demo-data.apex"
