-- DEV only. Simulates the ingestion pipeline landing a record with an invalid
-- incident category. Run each step separately in the Snowflake extension.

-- Step 1: land the bad record in DEV bronze.
INSERT INTO ESTIA_DBT_DEMO_DEV.BRONZE.INCIDENTS
    (incident_id, resident_id, incident_date, incident_type, _source_file, _loaded_at)
VALUES
    ('I031', 'R001', '2026-03-31', 'FALLL',
     'incident_system/incidents_20260402.csv', '2026-04-02 02:05:00');

-- Step 2: confirm what landed.
SELECT * FROM ESTIA_DBT_DEMO_DEV.BRONZE.INCIDENTS WHERE incident_id = 'I031';

-- Step 3: push a commit to your branch, or in Azure DevOps run dbt-ci for
-- your branch (Run pipeline). The accepted_values test on silver_incidents
-- fails, the run fails, and the gold models are skipped.

-- Step 4: remove the record. In practice the source team corrects it and the
-- pipeline reloads the file. Then run dbt-ci again: all tests pass.
DELETE FROM ESTIA_DBT_DEMO_DEV.BRONZE.INCIDENTS WHERE incident_id = 'I031';
