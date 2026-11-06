-- Optional, PROD. Shows a failed test stopping bad data reaching PROD gold.
-- Run each step separately in the Snowflake extension, with a role that can
-- write to PROD bronze (the walkthrough roles can't; ask an administrator).

-- Step 1: land an incident with an invalid category in PROD bronze.
INSERT INTO ESTIA_DBT_DEMO_PROD.BRONZE.INCIDENTS
    (incident_id, resident_id, incident_date, incident_type, _source_file, _loaded_at)
VALUES
    ('I031', 'R001', '2026-03-31', 'FALLL',
     'incident_system/incidents_20260402.csv', '2026-04-02 02:05:00');

-- Step 2: in Azure DevOps, run the dbt-refresh pipeline (Run pipeline).
--         Its PROD stage fails on accepted_values_silver_incidents_incident_type
--         and the gold models are skipped, so PROD gold keeps its last good
--         results.

-- Step 3: confirm gold doesn't include the record.
SELECT SUM(incident_count) AS incidents
FROM ESTIA_DBT_DEMO_PROD.GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS;

-- Step 4: remove the record (the source team's correction), then run
--         dbt-refresh again. Both stages succeed.
DELETE FROM ESTIA_DBT_DEMO_PROD.BRONZE.INCIDENTS WHERE incident_id = 'I031';
