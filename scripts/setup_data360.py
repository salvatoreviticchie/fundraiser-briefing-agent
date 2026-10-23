"""
Create the Data 360 plumbing for donor notes through the Data 360 (Data Cloud) Connect API:

    1. data stream     Donor_Note__c (CRM)  ->  data lake object  Donor_Note_c_Home__dll
    2. data model obj  Donor_Note__dlm (custom, category Other)
    3. field mapping   DLO -> DMO, one-to-one
    4. first refresh   (CRM streams then refresh on their own schedule)

Safe to re-run: each step checks whether its object already exists.

The search index and retriever are still created in Setup (see
docs/data-360-retriever-setup.md): at the time of writing, POST /ssot/search-index
accepted our request shape but failed server-side with UNKNOWN_EXCEPTION.

Usage:
    python3 scripts/setup_data360.py [target-org-alias]

It calls `sf api request rest`, so the org must already be authenticated with the sf CLI.
No credentials are read or stored by this script.
"""

import json
import subprocess
import sys
import tempfile

API = "/services/data/v65.0/ssot"
STREAM = "Donor_Note_c_Home"          # data stream name; its DLO is STREAM + "__dll"
DLO = STREAM + "__dll"
DMO = "Donor_Note__dlm"

# (DMO field API name, label, data type, is primary key). CRM field "Body__c" lands in the
# data lake as "Body_c", and both data lake and data model fields get a "__c" suffix.
FIELDS = [
    ("Id__c", "Record ID", "Text", True),
    ("Name__c", "Subject", "Text", False),
    ("Contact_c__c", "Donor", "Text", False),
    ("Note_Type_c__c", "Note Type", "Text", False),
    ("Note_Date_c__c", "Note Date", "Date", False),
    ("Body_c__c", "Body", "Text", False),
    ("Lakeside_Id_c__c", "Lakeside ID", "Text", False),
    ("LastModifiedDate__c", "Last Modified Date", "DateTime", False),
]


def api(org: str, method: str, path: str, body: dict | None = None):
    """Call the org's REST API through the sf CLI and return the parsed JSON response."""
    command = ["sf", "api", "request", "rest", API + path, "--method", method, "-o", org]
    if body is not None:
        # PY: NamedTemporaryFile gives us a real file to pass with --body @file;
        # delete=False so the sf process can still open it after we close it.
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(body, handle)
        command += ["--body", "@" + handle.name]
    output = subprocess.run(command, capture_output=True, text=True).stdout
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        sys.exit(f"Unexpected response from {method} {path}:\n{output[:500]}")


def is_error(response) -> bool:
    """The Connect API returns errors as a list of {errorCode, message} objects."""
    return isinstance(response, list) and bool(response) and "errorCode" in response[0]


def ensure_stream(org: str) -> None:
    if not is_error(api(org, "GET", f"/data-streams/{STREAM}")):
        print(f"1. Data stream {STREAM} already exists")
        return
    # PY: a list comprehension turns FIELDS into the data lake field definitions.
    # The data lake names drop the trailing "__c" that the data model adds.
    lake_fields = [
        {"name": name[:-3], "label": label, "dataType": dtype, "isPrimaryKey": pk}
        for name, label, dtype, pk in FIELDS
    ]
    body = {
        "name": STREAM,
        "label": "Donor Note Home",
        "connectorInfo": {
            "connectorType": "SalesforceDotCom",
            "connectorDetails": {"name": "SalesforceDotCom_Home", "sourceObject": "Donor_Note__c"},
        },
        "dataLakeObjectInfo": {
            "name": STREAM,
            "label": "Donor Note Home",
            "category": "Other",           # Engagement would demand an event date-time field
            "dataspaceInfo": [{"name": "default"}],
            "fields": lake_fields,
        },
    }
    response = api(org, "POST", "/data-streams", body)
    if is_error(response):
        sys.exit(f"Could not create data stream: {response}")
    print(f"1. Created data stream {STREAM} -> {DLO}")


def ensure_dmo(org: str) -> None:
    if not is_error(api(org, "GET", f"/data-model-objects/{DMO}")):
        print(f"2. Data model object {DMO} already exists")
        return
    body = {
        "name": DMO.removesuffix("__dlm"),   # PY: str.removesuffix (Python 3.9+)
        "label": "Donor Note",
        "category": "OTHER",
        "dataSpaceName": "default",
        "fields": [
            {"name": name, "label": label, "dataType": dtype, "isPrimaryKey": pk}
            for name, label, dtype, pk in FIELDS
        ],
    }
    response = api(org, "POST", "/data-model-objects", body)
    if is_error(response):
        sys.exit(f"Could not create data model object: {response}")
    print(f"2. Created data model object {DMO}")


def ensure_mapping(org: str) -> None:
    existing = api(org, "GET", f"/data-model-object-mappings?dataspace=default&dmoDeveloperName={DMO}")
    if not is_error(existing) and existing.get("objectSourceTargetMaps"):
        print(f"3. Mapping {DLO} -> {DMO} already exists")
        return
    body = {
        "sourceEntityDeveloperName": DLO,
        "targetEntityDeveloperName": DMO,
        "fieldMapping": [
            {"sourceFieldDeveloperName": name, "targetFieldDeveloperName": name} for name, *_ in FIELDS
        ],
    }
    response = api(org, "POST", "/data-model-object-mappings?dataspace=default", body)
    if is_error(response):
        sys.exit(f"Could not create mapping: {response}")
    print(f"3. Mapped {DLO} -> {DMO} ({len(FIELDS)} fields)")


def refresh_and_count(org: str) -> None:
    api(org, "POST", f"/data-streams/{STREAM}/actions/run", {})
    result = api(org, "POST", "/query", {"sql": f"SELECT COUNT(*) AS n FROM {DMO}"})
    count = result["data"][0]["n"] if isinstance(result, dict) and result.get("data") else "unknown"
    print(f"4. Refresh requested. Rows in {DMO} right now: {count} "
          "(the first ingestion can take up to an hour)")


def main() -> None:
    org = sys.argv[1] if len(sys.argv) > 1 else "agentforce-dev"
    ensure_stream(org)
    ensure_dmo(org)
    ensure_mapping(org)
    refresh_and_count(org)
    print("Next: create the search index and retriever in Setup (docs/data-360-retriever-setup.md, steps 3-5).")


if __name__ == "__main__":
    main()
