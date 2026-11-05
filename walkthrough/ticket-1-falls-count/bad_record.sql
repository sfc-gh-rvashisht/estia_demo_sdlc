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

-- Step 3: build your branch again. Replace the branch and name with yours.
EXECUTE TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY
    USING CONFIG = $${"branch": "feature-falls-and-categories", "dev_name": "RVASHISHT"}$$;

-- Step 4: after about a minute, check the run. BUILD_SILVER shows FAILED (the
-- accepted_values test on silver_incidents) and BUILD_GOLD doesn't run.
SELECT name, state, scheduled_time, error_message
FROM TABLE(ESTIA_DBT_DEMO_DEV.INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('minute', -10, CURRENT_TIMESTAMP()),
    SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP(),
    RESULT_LIMIT => 10000))
WHERE database_name = 'ESTIA_DBT_DEMO_DEV' AND schema_name = 'DBT'
ORDER BY scheduled_time DESC, name;

-- Step 5: remove the record. In practice the source team corrects it and the
-- pipeline reloads the file. Then run step 3 again: all tasks succeed.
DELETE FROM ESTIA_DBT_DEMO_DEV.BRONZE.INCIDENTS WHERE incident_id = 'I031';
