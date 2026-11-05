-- ===========================================================================
-- Orchestration: one task graph in each database.
--
--   DEPLOY  ──►  BUILD_SILVER  ──►  BUILD_GOLD
--
-- 1. The first task pulls the latest commits from GitHub and redeploys a dbt
--    project.
-- 2. BUILD_SILVER builds and tests the silver models. Tests that also read
--    gold run in the next step, after gold is rebuilt.
-- 3. BUILD_GOLD builds and tests the gold models. It only runs if silver
--    succeeded, so a failed silver test stops gold being refreshed.
--
-- DEV (root task ESTIA_DBT_DEMO_DEV.DBT.DEPLOY) takes two settings:
--   - Every 5 minutes it runs with its defaults, {"branch": "main", "dev_name": ""},
--     and builds main into the shared SILVER and GOLD schemas.
--   - An engineer runs it with their own settings to build their branch into
--     <DEV_NAME>_SILVER and <DEV_NAME>_GOLD:
--       EXECUTE TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY
--           USING CONFIG = $${"branch": "feature-x", "dev_name": "JSMITH"}$$;
--     The branch is deployed as that engineer's own dbt project, DBT_<DEV_NAME>.
--
-- PROD (root task ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN) only builds main.
--
-- Run as SYSADMIN. COMPUTE_WH runs the tasks. SYSADMIN needs
-- EXECUTE TASK on the account (granted in setup/02_github_integration.sql).
-- Tasks are created suspended. Start them with orchestration/02_operate.sql.
--
-- Run this file from Snowsight or the VS Code Snowflake extension. The
-- Snowflake CLI splits the BEGIN ... END task bodies at each semicolon.
-- ===========================================================================

USE ROLE SYSADMIN;

-- ---------------------------------------------------------------------------
-- DEV: shared SILVER and GOLD from main, or an engineer's branch
-- ---------------------------------------------------------------------------

CREATE TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '5 MINUTE'
    CONFIG = $${"branch": "main", "dev_name": ""}$$
    COMMENT = 'Deploy main to shared DEV, or a branch to an engineer''s own dbt project'
AS
DECLARE
    bad_input EXCEPTION (-20001, 'dev_name must be letters, digits or underscores; branch must be letters, digits, dots, dashes or underscores (no slashes); without a dev_name, branch must be main.');
BEGIN
    LET branch VARCHAR := COALESCE(SYSTEM$GET_TASK_GRAPH_CONFIG('branch')::VARCHAR, 'main');
    LET name VARCHAR := UPPER(TRIM(COALESCE(SYSTEM$GET_TASK_GRAPH_CONFIG('dev_name')::VARCHAR, '')));
    IF (NOT REGEXP_LIKE(:branch, '^[A-Za-z0-9._-]{1,100}$')
        OR NOT REGEXP_LIKE(:name, '^([A-Z][A-Z0-9_]{0,30})?$')
        OR (:name = '' AND :branch <> 'main')) THEN
        RAISE bad_input;
    END IF;

    ALTER GIT REPOSITORY ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO FETCH;

    IF (:name = '') THEN
        ALTER DBT PROJECT ESTIA_DBT_DEMO_DEV.DBT.ESTIA_MEDALLION
            DEPLOY FROM '@ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO/branches/main';
    ELSE
        -- The engineer's own project. DEFAULT_TARGET is dev because Snowflake
        -- compiles the project when it is deployed, before dev_name is passed in.
        LET project VARCHAR := 'ESTIA_DBT_DEMO_DEV.DBT.DBT_' || :name;
        LET source VARCHAR := '@ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO/branches/' || :branch;
        EXECUTE IMMEDIATE 'CREATE DBT PROJECT IF NOT EXISTS ' || :project ||
            ' FROM ''' || :source || ''' DEFAULT_TARGET = ''dev'' DBT_VERSION = ''1.11.11''' ||
            ' COMMENT = ''Feature branch deployments for ' || :name || '''';
        EXECUTE IMMEDIATE 'ALTER DBT PROJECT ' || :project || ' DEPLOY FROM ''' || :source || '''';
    END IF;
END;

-- Without this, EXECUTE TASK is skipped when a scheduled run is about to start
-- ("has a scheduled run that will start soon; skipping"). Branch runs and main
-- runs build different projects into different schemas, so they can overlap.
ALTER TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY SET OVERLAP_POLICY = ALLOW_ALL_OVERLAP;

CREATE TASK ESTIA_DBT_DEMO_DEV.DBT.BUILD_SILVER
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Build and test silver models in shared DEV or an engineer''s schemas'
    AFTER ESTIA_DBT_DEMO_DEV.DBT.DEPLOY
AS
BEGIN
    LET name VARCHAR := UPPER(TRIM(COALESCE(SYSTEM$GET_TASK_GRAPH_CONFIG('dev_name')::VARCHAR, '')));
    IF (:name = '') THEN
        EXECUTE DBT PROJECT ESTIA_DBT_DEMO_DEV.DBT.ESTIA_MEDALLION
            ARGS = 'build --target dev --select models/silver --indirect-selection cautious';
    ELSEIF (REGEXP_LIKE(:name, '^[A-Z][A-Z0-9_]{0,30}$')) THEN
        EXECUTE IMMEDIATE 'EXECUTE DBT PROJECT ESTIA_DBT_DEMO_DEV.DBT.DBT_' || :name ||
            ' ARGS = ''build --target personal --select models/silver --indirect-selection cautious''' ||
            ' ENV_VARS = (''DBT_DEV_PREFIX'' = ''' || :name || ''')';
    END IF;
END;

CREATE TASK ESTIA_DBT_DEMO_DEV.DBT.BUILD_GOLD
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Build and test gold models in shared DEV or an engineer''s schemas'
    AFTER ESTIA_DBT_DEMO_DEV.DBT.BUILD_SILVER
AS
BEGIN
    LET name VARCHAR := UPPER(TRIM(COALESCE(SYSTEM$GET_TASK_GRAPH_CONFIG('dev_name')::VARCHAR, '')));
    IF (:name = '') THEN
        EXECUTE DBT PROJECT ESTIA_DBT_DEMO_DEV.DBT.ESTIA_MEDALLION
            ARGS = 'build --target dev --select models/gold';
    ELSEIF (REGEXP_LIKE(:name, '^[A-Z][A-Z0-9_]{0,30}$')) THEN
        EXECUTE IMMEDIATE 'EXECUTE DBT PROJECT ESTIA_DBT_DEMO_DEV.DBT.DBT_' || :name ||
            ' ARGS = ''build --target personal --select models/gold''' ||
            ' ENV_VARS = (''DBT_DEV_PREFIX'' = ''' || :name || ''')';
    END IF;
END;

-- ---------------------------------------------------------------------------
-- PROD: SILVER and GOLD in ESTIA_DBT_DEMO_PROD, from main only
-- ---------------------------------------------------------------------------

CREATE TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '5 MINUTE'
    COMMENT = 'Pull main from GitHub and redeploy the PROD dbt project'
AS
BEGIN
    ALTER GIT REPOSITORY ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO FETCH;
    ALTER DBT PROJECT ESTIA_DBT_DEMO_PROD.DBT.ESTIA_MEDALLION
        DEPLOY FROM '@ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO/branches/main';
END;

CREATE TASK ESTIA_DBT_DEMO_PROD.DBT.BUILD_SILVER
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Build and test silver models in PROD'
    AFTER ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN
AS
    EXECUTE DBT PROJECT ESTIA_DBT_DEMO_PROD.DBT.ESTIA_MEDALLION
        ARGS = 'build --target prod --select models/silver --indirect-selection cautious';

CREATE TASK ESTIA_DBT_DEMO_PROD.DBT.BUILD_GOLD
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Build and test gold models in PROD'
    AFTER ESTIA_DBT_DEMO_PROD.DBT.BUILD_SILVER
AS
    EXECUTE DBT PROJECT ESTIA_DBT_DEMO_PROD.DBT.ESTIA_MEDALLION
        ARGS = 'build --target prod --select models/gold';

SHOW TASKS IN SCHEMA ESTIA_DBT_DEMO_DEV.DBT;
SHOW TASKS IN SCHEMA ESTIA_DBT_DEMO_PROD.DBT;
