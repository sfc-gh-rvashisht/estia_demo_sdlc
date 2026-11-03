-- ===========================================================================
-- Orchestration: shared DEV and PROD are both rebuilt from main.
-- Each database has the same task graph:
--
--   DEPLOY_FROM_MAIN  ──►  BUILD_SILVER  ──►  BUILD_GOLD
--   (every 5 minutes)
--
-- 1. DEPLOY_FROM_MAIN pulls the latest commits from GitHub and redeploys the
--    dbt project from main.
-- 2. BUILD_SILVER builds and tests the silver models. Tests that also read
--    gold run in the next step, after gold is rebuilt.
-- 3. BUILD_GOLD builds and tests the gold models. It only runs if silver
--    succeeded, so a failed silver test stops gold being refreshed.
--
-- Engineers' feature branches are not built here; they use
-- ESTIA_DBT_DEMO_DEV.DBT.DEPLOY_BRANCH (setup/03_connect_github.sql).
--
-- Run as SYSADMIN. COMPUTE_WH runs the tasks. SYSADMIN needs
-- EXECUTE TASK on the account (granted in setup/02_github_integration.sql).
-- Tasks are created suspended. Start them with orchestration/02_operate.sql.
-- ===========================================================================

USE ROLE SYSADMIN;

-- ---------------------------------------------------------------------------
-- DEV: shared SILVER and GOLD in ESTIA_DBT_DEMO_DEV
-- ---------------------------------------------------------------------------

CREATE TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY_FROM_MAIN
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '5 MINUTE'
    COMMENT = 'Pull main from GitHub and redeploy the shared DEV dbt project'
AS
BEGIN
    ALTER GIT REPOSITORY ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO FETCH;
    ALTER DBT PROJECT ESTIA_DBT_DEMO_DEV.DBT.ESTIA_MEDALLION
        DEPLOY FROM '@ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO/branches/main';
END;

CREATE TASK ESTIA_DBT_DEMO_DEV.DBT.BUILD_SILVER
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Build and test silver models in shared DEV'
    AFTER ESTIA_DBT_DEMO_DEV.DBT.DEPLOY_FROM_MAIN
AS
    EXECUTE DBT PROJECT ESTIA_DBT_DEMO_DEV.DBT.ESTIA_MEDALLION
        ARGS = 'build --target dev --select models/silver --indirect-selection cautious';

CREATE TASK ESTIA_DBT_DEMO_DEV.DBT.BUILD_GOLD
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Build and test gold models in shared DEV'
    AFTER ESTIA_DBT_DEMO_DEV.DBT.BUILD_SILVER
AS
    EXECUTE DBT PROJECT ESTIA_DBT_DEMO_DEV.DBT.ESTIA_MEDALLION
        ARGS = 'build --target dev --select models/gold';

-- ---------------------------------------------------------------------------
-- PROD: SILVER and GOLD in ESTIA_DBT_DEMO_PROD
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
