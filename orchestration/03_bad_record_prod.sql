-- Optional, PROD. Shows the task graph stopping when silver tests fail.
-- Run each step separately in the Snowflake extension.

-- Step 1: land an incident with an invalid category in PROD bronze.
INSERT INTO ESTIA_DBT_DEMO_PROD.BRONZE.INCIDENTS
    (incident_id, resident_id, incident_date, incident_type, _source_file, _loaded_at)
VALUES
    ('I031', 'R001', '2026-03-31', 'FALLL',
     'incident_system/incidents_20260402.csv', '2026-04-02 02:05:00');

-- Step 2: run the task graph now (or wait for the next scheduled run).
EXECUTE TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN;

-- Step 3: after about a minute, check the runs. BUILD_SILVER shows FAILED and
-- BUILD_GOLD does not run, so PROD gold keeps its last good results.
SELECT name, state, scheduled_time, error_message
FROM TABLE(ESTIA_DBT_DEMO_PROD.INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('minute', -15, CURRENT_TIMESTAMP()),
    SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP()))
WHERE schema_name = 'DBT'
ORDER BY scheduled_time DESC, name;

-- Step 4: remove the record (the source team's correction) and run again.
DELETE FROM ESTIA_DBT_DEMO_PROD.BRONZE.INCIDENTS WHERE incident_id = 'I031';
EXECUTE TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN;
