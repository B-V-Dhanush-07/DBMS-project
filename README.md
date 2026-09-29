# The Quiet Ledger

![The Quiet Ledger](thumbnail.jpeg)

A **PostgreSQL detective puzzle** built for a Database Management Systems (DBMS) project.

A sealed exhibit has vanished from the Metropolitan Records Bureau's custody ledger. No alarm sounded, and no date, room, exhibit or culprit is named anywhere in the brief. Using ten related tables full of plausible, misleading and contradictory records, you must find the incident, identify the insiders involved, and work out a single integer answer.

The puzzle tests investigative thinking as much as SQL syntax: every claim has to be checked against a second and third table before it counts.

---

## Quick start

**Requirements:** PostgreSQL 13 or newer (tested on PostgreSQL 16).

```bash
# 1. Create a database
createdb quiet_ledger

# 2. Load the data (this is the only script you need)
psql -d quiet_ledger -f setup.sql

# 3. Read the brief, then start querying
psql -d quiet_ledger
```

`setup.sql` drops and recreates all tables, so it is safe to run again to reset the database. It is about 3.8 MB because every person has a small JPEG photo stored inline as `bytea`.

---

## The task

Read [`the_quiet_ledger.md`](the_quiet_ledger.md). It contains the background story and ten numbered clauses that define every term. Only those clauses decide what counts as evidence.

You submit **one integer**, derived only from the records. Things to watch for:

- the exact edges of time intervals (open vs closed ends)
- how many transfers share the same timestamp
- device validity (owner, issue date, retirement date)
- clearance levels against the level a room requires
- records that look damning but fall apart when cross-checked

---

## Database schema

Ten tables, 250 rows each.

| Table | What it holds |
|---|---|
| `people` | Bureau staff: role, division, clearance level, badge, photo |
| `locations` | Rooms and zones: building, floor, restricted flag, required badge level |
| `devices` | Registered handsets: owner, issue and retirement dates |
| `cases` | Investigations: type, status, closing date, origin room |
| `case_people` | Who worked on which case and in what capacity |
| `evidence` | Exhibits: seal status, weight, current registered room |
| `evidence_transfers` | The custody ledger: every recorded move of an exhibit |
| `access_logs` | Badge swipes: person, room, time, result, escort, anomaly flag |
| `calls` | Phone records: caller, receiver, device, time, duration |
| `person_location` | Sensor and camera sightings with a confidence score |

### Relationships

```
people ──< devices ──< calls >── people
   │
   ├──< access_logs >── locations
   ├──< person_location >── locations
   ├──< case_people >── cases >── locations (origin)
   │
cases ──< evidence ──< evidence_transfers >── locations (from / to)
```

---

## Skills practised

- Multi-table joins and correlated subqueries (`EXISTS`)
- Window functions (`ROW_NUMBER() OVER (PARTITION BY ...)`) for "latest" and "earlier than" logic with tie-breaking
- Temporary views to build a solution step by step
- Precise timestamp and interval handling (`BETWEEN`, open/closed ranges, `INTERVAL`)
- `GROUP BY` / `HAVING` for counting and threshold rules
- Data validation and cross-checking against contradictory records

---

## Repository contents

| File | Purpose |
|---|---|
| `setup.sql` | Creates and fills all 10 tables |
| `the_quiet_ledger.md` | Background story and the puzzle brief |
| `The_Quiet_Ledger_Report.docx` | Full project report: design, decoys, verification |
| `solution_queries.sql` | Reference solution in 7 queries (**spoilers**) |
| `answer.txt` | Expected answer (**spoiler**) |
| `thumbnail.jpeg` | Cover image |

> Want to solve it yourself? Don't open `solution_queries.sql`, `answer.txt` or the report until you have an answer.

---

## Verification

The reference solution was run on a fresh PostgreSQL 16 database. Exactly one record satisfies the incident definition, and the seven queries in `solution_queries.sql` produce the value stored in `answer.txt`.

---

## License

Released under the [MIT License](LICENSE).
