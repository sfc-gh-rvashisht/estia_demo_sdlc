-- Start, run, monitor and stop the PROD task graph.
-- Run each statement separately in the Snowflake extension.

-- Start the schedule. Resumes all three tasks, root last.
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN');

-- Run now instead of waiting for the next 5-minute run.
EXECUTE TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN;

-- Recent runs of each task, newest first.
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(ESTIA_DBT_DEMO_PROD.INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP()),
    SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP()))
WHERE schema_name = 'DBT'
ORDER BY scheduled_time DESC, name;

-- Which commit is deployed.
SHOW DBT PROJECTS IN SCHEMA ESTIA_DBT_DEMO_PROD.DBT;

-- Stop the schedule after the demo, so the warehouse isn't woken every 5 minutes.
ALTER TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN SUSPEND;
