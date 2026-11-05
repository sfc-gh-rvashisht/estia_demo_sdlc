-- Start, run, monitor and stop the DEV and PROD task graphs.
-- Run each statement separately in the Snowflake extension.

-- Start the schedules. Resumes all three tasks in each graph, root last.
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ESTIA_DBT_DEMO_DEV.DBT.DEPLOY');
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN');

-- Run now instead of waiting for the next 5-minute run. Both build main.
-- DEV runs can overlap (so branch runs are never skipped), but two runs of
-- main at once redeploy the same project and one can fail with "Live version
-- is not found". Only run DEV for main when the history query below shows no
-- DEV main run in progress.
EXECUTE TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY;
EXECUTE TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN;

-- Build your branch into your own DEV schemas (<dev_name>_SILVER and _GOLD).
-- Push the branch first. Branch names can't contain "/".
EXECUTE TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY
    USING CONFIG = $${"branch": "feature-falls-and-categories", "dev_name": "RVASHISHT"}$$;

-- Recent runs of each task, newest first. DEV runs show which branch and
-- engineer they were for in the config column.
SELECT 'DEV' AS environment, name, state, scheduled_time, completed_time,
       PARSE_JSON(config):dev_name::VARCHAR AS dev_name,
       PARSE_JSON(config):branch::VARCHAR AS branch, error_message
FROM TABLE(ESTIA_DBT_DEMO_DEV.INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP()),
    SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP(),
    RESULT_LIMIT => 10000))
WHERE database_name = 'ESTIA_DBT_DEMO_DEV' AND schema_name = 'DBT'
UNION ALL
SELECT 'PROD', name, state, scheduled_time, completed_time, NULL, 'main', error_message
FROM TABLE(ESTIA_DBT_DEMO_PROD.INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP()),
    SCHEDULED_TIME_RANGE_END => CURRENT_TIMESTAMP(),
    RESULT_LIMIT => 10000))
WHERE database_name = 'ESTIA_DBT_DEMO_PROD' AND schema_name = 'DBT'
ORDER BY scheduled_time DESC, environment, name;

-- Which commit each project is deployed from (includes engineers' DBT_<NAME> projects).
SHOW DBT PROJECTS IN DATABASE ESTIA_DBT_DEMO_DEV;
SHOW DBT PROJECTS IN DATABASE ESTIA_DBT_DEMO_PROD;

-- Stop the schedules after the demo, so the warehouse isn't woken every 5 minutes.
ALTER TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY SUSPEND;
ALTER TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN SUSPEND;
