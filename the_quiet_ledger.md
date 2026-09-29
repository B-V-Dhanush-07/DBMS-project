# The Quiet Ledger

*(Background and brief in one file. Load `setup.sql` into PostgreSQL; it is the only script you need.)*

---

## Part One: Background

### I. The Bureau and Its Ostensibly Impregnable Ledger

The Metropolitan Records Bureau prides itself on a custody apparatus of almost liturgical exactitude. Every sealed exhibit that crosses its threshold is entered into a ledger, and every subsequent displacement of that exhibit is supposed to leave an indelible, timestamped trace. Doors are bound to badges, badges to persons, handsets to registered proprietors, and a lattice of sensors and cameras purports to know, at any given minute, who is standing where. In the Bureau's own idiom, nothing is ever lost; it is merely mislaid until the paperwork catches up.

### II. The Lacuna

Sometime within the past twelve months, a sealed exhibit vanished from that ledger without so much as a murmur. No alarm sounded, no custodian raised an objection, and no reconciliation flagged the discrepancy. The exhibit did not evaporate, of course. The audit board can offer only this: *"it was moved by hand, at night, from the room where its case began, into a storage room that the register never learned about."* It furnishes no date, no chamber, no exhibit and no culprit, and it will not be drawn into conjecture.

### III. The Suspicion

Internal Affairs harbours a grim hypothesis: that this was no opportunistic pilfering but a coordinated, clandestine enterprise, an inside job orchestrated by a cabal of insiders who shielded one another and exploited the trust vested in their positions. Some of them, it is believed, crossed thresholds they had no entitlement to cross. Others never set foot near the scene at all, and served instead as intermediaries, relaying assurances and warnings across the darkness by telephone.

### IV. The Treacherous Nature of the Evidence

Do not mistake abundance for reliability. The archive is replete with entries that are plausible yet spurious, corroborating yet coincidental, and in places flatly self-contradictory. Several exhibits have gone astray; several cases have been laid to rest; several transfers bear an identical clock stamp; and a number of employees possess badge swipes, calls and sightings that appear damning on their face and evaporate under scrutiny. The individual named as the actor on a transfer is a matter of record, not a presumption of guilt.

You are therefore not a mere reader of the archive but its adjudicator. Corroborate every claim against a second and third table. Only what survives triangulation may be admitted as fact.

---

## Part Two: The Brief

The database has ten tables: `people`, `locations`, `devices`, `cases`, `case_people`, `evidence`, `evidence_transfers`, `access_logs`, `calls`, `person_location`. No date, room, exhibit or name is stated anywhere in this document; all of them must come from the records.

**Governing text.** The audit board's sentence in Part One is atmosphere, not a rule. Only the numbered clauses below decide anything. The clauses are listed in an order that is *not* the order in which they depend on one another; some refer forward to terms defined further down. Every term, once defined, keeps that meaning throughout.

**The number sought** is a single integer, assembled in clause 10 from three quantities (S, R, W) that are themselves defined only in clauses 9, 8 and 1 respectively.

### Clauses

**1. The Occurrence.** Among all rows of `evidence_transfers` there is exactly one row about which none of the following six statements is false. That row is the Occurrence. Write **τ** for its `transfer_time`, **δ** for its `to_location_id`, and **X** for its exhibit.

1. No other transfer row of X is later than it. Lateness is decided by `transfer_time`, and where two rows have equal times, the one with the larger `transfer_id` is the later.
2. X has `sealed` true and `status` equal to `'Missing'`, and the row's own `seal_state` is `'sealed'`.
3. The case of X has `case_type` equal to `'Theft'` and `status` equal to `'Closed'`, and its `closed_on` calendar date lies strictly before the calendar date of τ.
4. The row's `from_location_id` equals that case's `origin_location_id`.
5. At least two *other* transfer rows of X are earlier than it (same lateness rule as in 1.). A row counts here even if its `from_location_id` and `to_location_id` are identical.
6. The `current_location_id` of X is not δ.

**2. The Vigil.** The closed time interval from τ minus 180 minutes up to τ, with both end instants included.

**3. The Shadow.** The set of all locations for which `restricted` is true and whose `building` text equals the `building` of δ. Room δ itself belongs to the Shadow if it is restricted; no room is left out merely because of what happened in it.

**4. Plain entries and suspect entries.**
A *plain entry* is an `access_logs` row that has `action` `'ENTRY'`, `result` `'GRANTED'`, `escort_id` null, a location in the Shadow, and an `access_time` inside the Vigil.
A *suspect entry* is a plain entry that additionally has `anomaly_flag` `'Y'` **and** whose person's `clearance_level` is strictly less than the `badge_level_required` of the entered room.

**5. Firstlings.** A person is a Firstling when both of the following hold, and not otherwise.

- (a) The person has at least one plain entry, and the number of their suspect entries is strictly greater than the number of their plain entries that are *not* suspect. (Equal numbers do not suffice.)
- (b) Consider only `person_location` rows of that person with `observed_at` not after τ and `confidence` at least 0.70. Among those, take the row with the latest `observed_at` (equal times: larger `event_id`). Its location lies in the Shadow. A person with no such row fails (b).

**6. Valid calls.** A `calls` row is valid when all of the following are true.

- `call_type` is `'voice'` and `answered` is true.
- `duration_sec` is at least 30 (exactly 30 passes).
- `call_time` lies inside the Vigil.
- The device named by the row's `device_id` has `owner_id` equal to the row's `caller_id`, has `issued_on` on or before the calendar date of `call_time`, and has `retired_on` either null or strictly after the calendar date of `call_time`.

**7. Secondlings.** A person who is *not* a Firstling and who, taking valid calls in which they appear as either caller or receiver, has stood opposite at least three *distinct* Firstlings. Each such Firstling counts once however many calls they shared. Opposite parties who are not Firstlings do not count.

**8. The Ring.** Firstlings and Secondlings taken together, each person once. **R** is the number of people in the Ring.

**9. Coordination calls.** A valid call is a coordination call when its caller and its receiver are both in the Ring, and its caller was *present* during the 60 minutes up to the call. The caller was present if at least one of these exists:

- an `access_logs` row of the caller with `action` `'ENTRY'` and `result` `'GRANTED'`, in a Shadow location (escort and anomaly flag are irrelevant here), or
- a `person_location` row of the caller in a Shadow location with `confidence` at least 0.70,

whose timestamp `t` satisfies `call_time − 60 minutes < t ≤ call_time` (the earlier end excluded, the later end included). A call is counted once even if both kinds of evidence exist. **S** is the sum of `duration_sec` over all coordination calls.

**10. The number.** Let **W** be the `weight_grams` of X multiplied by 10 and rounded to the nearest whole number.

> **answer = S × R + W**

### What to submit

One integer, derived only from the records. Do not assume that a badge entry, a call, a sighting or a custody transfer is meaningful without cross-checking it against the other tables, and watch the ordering of events, the exact edges of intervals, device validity, clearance levels, and how many transfers share the same stamp.
