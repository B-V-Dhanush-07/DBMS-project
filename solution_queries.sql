-- =====================================================================================
-- THE QUIET LEDGER : 7-QUERY REFERENCE SOLUTION (PostgreSQL)
-- =====================================================================================
-- Run setup.sql first (it is the only setup script needed), then run the seven statements below
-- in the SAME PostgreSQL session.
--
-- The solution deliberately avoids hard-coding the discovered incident ID,
-- destination room, first-tier people, second-tier person, or final numeric answer.
-- Each query creates a temporary view used by the following query.
--
-- Final result for the supplied database:
--     S = 361 seconds
--     R = 4 people
--     W = 587
--     answer = 361 * 4 + 587 = 2031
--
-- -------------------------------------------------------------------------------------
-- Query 1 : FIND THE INCIDENT
-- -------------------------------------------------------------------------------------
-- The incident must satisfy every clause in question.md:
--   1. final recorded move of its exhibit
--   2. exhibit is sealed and Missing; transfer is sealed
--   3. Theft case already Closed before the day of the move
--   4. transfer leaves the case's origin room
--   5. at least two earlier transfers of the same exhibit
--   6. registered current room differs from transfer destination
--
-- ROW_NUMBER() gives a deterministic ordering even when two transfers share a timestamp.
-- prior_moves is derived from that same ordering rather than relying only on timestamps.
-- =====================================================================================

CREATE OR REPLACE TEMP VIEW incident AS
WITH chain AS (
    SELECT
        t.*,
        ROW_NUMBER() OVER (
            PARTITION BY t.evidence_id
            ORDER BY t.transfer_time DESC, t.transfer_id DESC
        ) AS rn_from_end,
        ROW_NUMBER() OVER (
            PARTITION BY t.evidence_id
            ORDER BY t.transfer_time, t.transfer_id
        ) - 1 AS prior_moves
    FROM evidence_transfers t
)
SELECT
    ch.transfer_id,
    ch.evidence_id,
    ch.transfer_time AS t_stamp,
    ch.transfer_time - INTERVAL '3 hours' AS win_start,
    ch.to_location_id,
    e.weight_grams
FROM chain ch
JOIN evidence e
    ON e.evidence_id = ch.evidence_id
JOIN cases c
    ON c.case_id = e.case_id
WHERE ch.rn_from_end = 1
  AND e.status = 'Missing'
  AND e.sealed
  AND ch.seal_state = 'sealed'
  AND c.case_type = 'Theft'
  AND c.status = 'Closed'
  AND c.closed_on < DATE(ch.transfer_time)
  AND ch.from_location_id = c.origin_location_id
  AND ch.prior_moves >= 2
  AND e.current_location_id <> ch.to_location_id;

-- =====================================================================================
-- Query 2 : FIND THE SHADOW ROOMS
-- =====================================================================================
-- Shadow rooms are ALL restricted rooms in the same building as the incident's
-- destination room. This derives the building from the incident itself.
-- =====================================================================================

CREATE OR REPLACE TEMP VIEW shadow AS
SELECT
    l.location_id,
    l.badge_level_required
FROM locations l
JOIN locations dest
    ON dest.building = l.building
CROSS JOIN incident i
WHERE dest.location_id = i.to_location_id
  AND l.restricted;

-- =====================================================================================
-- Query 3 : FIND THE FIRST-TIER PEOPLE
-- =====================================================================================
-- First-tier requires BOTH conditions:
--   A. More than half of the person's granted, unescorted shadow-room entries
--      in the incident window are suspect entries.
--   B. Their latest qualifying sighting at or before the incident is in a
--      shadow room.
--
-- A suspect entry is:
--   - ENTRY
--   - GRANTED
--   - unescorted
--   - anomaly_flag = 'Y'
--   - person's clearance is below the room's required badge level
-- =====================================================================================

CREATE OR REPLACE TEMP VIEW tier1 AS
WITH wing_entries AS (
    SELECT
        a.person_id,
        a.access_time,
        a.anomaly_flag,
        (p.clearance_level < s.badge_level_required) AS under_cleared
    FROM access_logs a
    JOIN shadow s
        ON s.location_id = a.location_id
    JOIN people p
        ON p.person_id = a.person_id
    CROSS JOIN incident i
    WHERE a.action = 'ENTRY'
      AND a.result = 'GRANTED'
      AND a.escort_id IS NULL
      AND a.access_time BETWEEN i.win_start AND i.t_stamp
),
tier1_candidates AS (
    SELECT person_id
    FROM wing_entries
    GROUP BY person_id
    HAVING
        SUM(
            CASE
                WHEN anomaly_flag = 'Y' AND under_cleared
                THEN 1
                ELSE 0
            END
        ) * 2 > COUNT(*)
),
last_seen AS (
    SELECT
        x.person_id,
        x.location_id
    FROM (
        SELECT
            pl.person_id,
            pl.location_id,
            ROW_NUMBER() OVER (
                PARTITION BY pl.person_id
                ORDER BY pl.observed_at DESC, pl.event_id DESC
            ) AS rn
        FROM person_location pl
        CROSS JOIN incident i
        WHERE pl.observed_at <= i.t_stamp
          AND pl.confidence >= 0.70
    ) x
    WHERE x.rn = 1
)
SELECT tc.person_id
FROM tier1_candidates tc
JOIN last_seen ls
    ON ls.person_id = tc.person_id
JOIN shadow s
    ON s.location_id = ls.location_id;

-- =====================================================================================
-- Query 4 : FIND VALID CALLS
-- =====================================================================================
-- A valid call must be:
--   - voice
--   - answered
--   - at least 30 seconds
--   - inside the 3-hour incident window
--   - placed from the caller's own handset
--   - handset issued on or before the call date
--   - handset never retired, or retired only AFTER the call date
-- =====================================================================================

CREATE OR REPLACE TEMP VIEW valid_calls AS
SELECT
    c.call_id,
    c.caller_id,
    c.receiver_id,
    c.call_time,
    c.duration_sec
FROM calls c
JOIN devices d
    ON d.device_id = c.device_id
CROSS JOIN incident i
WHERE c.call_type = 'voice'
  AND c.answered
  AND c.duration_sec >= 30
  AND d.owner_id = c.caller_id
  AND d.issued_on <= DATE(c.call_time)
  AND (
        d.retired_on IS NULL
        OR d.retired_on > DATE(c.call_time)
      )
  AND c.call_time BETWEEN i.win_start AND i.t_stamp;

-- =====================================================================================
-- Query 5 : BUILD THE RING
-- =====================================================================================
-- A second-tier person is NOT already first tier and has valid calls with at least
-- three DISTINCT first-tier people. Calls count in either direction.
--
-- The ring is first tier UNION second tier.
-- =====================================================================================

CREATE OR REPLACE TEMP VIEW ring AS
WITH contacts AS (
    SELECT
        caller_id AS person_id,
        receiver_id AS other_id
    FROM valid_calls

    UNION ALL

    SELECT
        receiver_id AS person_id,
        caller_id AS other_id
    FROM valid_calls
),
tier2 AS (
    SELECT person_id
    FROM contacts
    WHERE other_id IN (SELECT person_id FROM tier1)
      AND person_id NOT IN (SELECT person_id FROM tier1)
    GROUP BY person_id
    HAVING COUNT(DISTINCT other_id) >= 3
)
SELECT person_id
FROM tier1

UNION

SELECT person_id
FROM tier2;

-- =====================================================================================
-- Query 6 : FIND COORDINATION CALLS
-- =====================================================================================
-- A coordination call must:
--   1. be a valid call
--   2. have BOTH caller and receiver in the ring
--   3. have the caller physically inside a shadow room during
--      (call_time - 60 minutes, call_time]
--
-- Physical presence can come from either:
--   - a granted ENTRY into a shadow room, or
--   - a sighting with confidence >= 0.70 in a shadow room.
--
-- The interval is open on the left and closed on the right exactly as defined
-- in question.md.
-- =====================================================================================

CREATE OR REPLACE TEMP VIEW coordination AS
SELECT
    vc.call_id,
    vc.duration_sec
FROM valid_calls vc
WHERE vc.caller_id IN (SELECT person_id FROM ring)
  AND vc.receiver_id IN (SELECT person_id FROM ring)
  AND (
        EXISTS (
            SELECT 1
            FROM access_logs a
            JOIN shadow s
                ON s.location_id = a.location_id
            WHERE a.person_id = vc.caller_id
              AND a.action = 'ENTRY'
              AND a.result = 'GRANTED'
              AND a.access_time > vc.call_time - INTERVAL '60 minutes'
              AND a.access_time <= vc.call_time
        )
        OR EXISTS (
            SELECT 1
            FROM person_location pl
            JOIN shadow s
                ON s.location_id = pl.location_id
            WHERE pl.person_id = vc.caller_id
              AND pl.confidence >= 0.70
              AND pl.observed_at > vc.call_time - INTERVAL '60 minutes'
              AND pl.observed_at <= vc.call_time
        )
      );

-- =====================================================================================
-- Query 7 : COMPUTE THE FINAL ANSWER
-- =====================================================================================
-- S = total duration of all coordination calls
-- R = number of people in the ring
-- W = weight_grams * 10, rounded to the nearest whole number
--
-- COALESCE makes S = 0 if there are no coordination calls, rather than returning NULL.
-- The final expression is cast to bigint so the output is explicitly an integer.
-- =====================================================================================

SELECT
    (
        COALESCE((SELECT SUM(duration_sec) FROM coordination), 0)
        * (SELECT COUNT(*) FROM ring)
        + ROUND((SELECT weight_grams * 10 FROM incident))
    )::BIGINT AS answer;

-- Expected result for the supplied database:
--
--   answer
--   ------
--   2031
--
-- Breakdown:
--   S = 361
--   R = 4
--   W = 587
--   361 * 4 + 587 = 2031
