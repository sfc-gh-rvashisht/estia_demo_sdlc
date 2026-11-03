-- Start, run, monitor and stop the DEV and PROD task graphs.
-- Run each statement separately in the Snowflake extension.

-- Start the schedules. Resumes all three tasks in each graph, root last.
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ESTIA_DBT_DEMO_DEV.DBT.DEPLOY_FROM_MAIN');
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN');

-- Run now instead of waiting for the next 5-minute run.
EXECUTE TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY_FROM_MAIN;
EXECUTE TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN;

-- Recent runs of each task, newest first.
SELECT 'DEV' AS environment, name, state, scheduled_time, completed_time, error_message
FROM TABLE(ESTIA_DBT_DEMO_DEV.INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP()),
    SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP()))
WHERE database_name = 'ESTIA_DBT_DEMO_DEV' AND schema_name = 'DBT'
UNION ALL
SELECT 'PROD', name, state, scheduled_time, completed_time, error_message
FROM TABLE(ESTIA_DBT_DEMO_PROD.INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP()),
    SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP()))
WHERE database_name = 'ESTIA_DBT_DEMO_PROD' AND schema_name = 'DBT'
ORDER BY scheduled_time DESC, environment, name;

-- Which commit each project is deployed from (includes engineers' DBT_<NAME> projects).
SHOW DBT PROJECTS IN DATABASE ESTIA_DBT_DEMO_DEV;
SHOW DBT PROJECTS IN DATABASE ESTIA_DBT_DEMO_PROD;

-- Stop the schedules after the demo, so the warehouse isn't woken every 5 minutes.
ALTER TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY_FROM_MAIN SUSPEND;
ALTER TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN SUSPEND;
