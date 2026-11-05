-- ===========================================================================
-- Step 2 of 2: connect the Git repository and create the dbt projects.
-- Run as SYSADMIN, after setup/02_github_integration.sql.
-- Points at github.com/sfc-gh-rvashisht/estia_demo_sdlc-. Change the GitHub
-- user and repository name here if you use a different repository.
--
-- Creates, in each of ESTIA_DBT_DEMO_DEV and ESTIA_DBT_DEMO_PROD:
--   1. Schema DBT, which holds the objects below and the orchestration tasks.
--   2. Git repository object DBT.ESTIA_REPO.
--   3. dbt project object DBT.ESTIA_MEDALLION, deployed from main.
-- Engineers build their branches with the DEV task graph
-- (orchestration/01_create_task_graph.sql), which deploys each branch as the
-- engineer's own dbt project.
-- ===========================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;

-- ---------------------------------------------------------------------------
-- DEV
-- ---------------------------------------------------------------------------

-- 1. Schema for the dbt projects, Git repository and tasks.
CREATE SCHEMA ESTIA_DBT_DEMO_DEV.DBT
    COMMENT = 'dbt projects, Git repository and orchestration tasks';

-- 2. A Snowflake copy of the repository. FETCH pulls the latest commits.
CREATE GIT REPOSITORY ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO
    API_INTEGRATION = ESTIA_DEMO_GITHUB
    ORIGIN = 'https://github.com/sfc-gh-rvashisht/estia_demo_sdlc-.git';

ALTER GIT REPOSITORY ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO FETCH;
LIST @ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO/branches/main;

-- 3. Shared DEV project, built from main by the DEV task graph.
CREATE DBT PROJECT ESTIA_DBT_DEMO_DEV.DBT.ESTIA_MEDALLION
    FROM '@ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO/branches/main'
    DEFAULT_TARGET = 'dev'
    DBT_VERSION = '1.11.11'
    COMMENT = 'Shared DEV, deployed from main';

-- ---------------------------------------------------------------------------
-- PROD
-- ---------------------------------------------------------------------------

-- 1. Schema for the dbt project, Git repository and tasks.
CREATE SCHEMA ESTIA_DBT_DEMO_PROD.DBT
    COMMENT = 'dbt project, Git repository and orchestration tasks';

-- 2. A Snowflake copy of the repository. FETCH pulls the latest commits.
CREATE GIT REPOSITORY ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO
    API_INTEGRATION = ESTIA_DEMO_GITHUB
    ORIGIN = 'https://github.com/sfc-gh-rvashisht/estia_demo_sdlc-.git';

-- Azure DevOps (Azure Repos) version. Use instead of both CREATE GIT REPOSITORY
-- statements, after the Azure DevOps steps in setup/02_github_integration.sql.
-- Those steps create the DBT schemas, so skip the CREATE SCHEMA statements.
--
--   CREATE GIT REPOSITORY ESTIA_DBT_DEMO_<DEV|PROD>.DBT.ESTIA_REPO
--       API_INTEGRATION = ESTIA_DEMO_ADO
--       GIT_CREDENTIALS = ESTIA_DBT_DEMO_PROD.DBT.ADO_GIT_PAT
--       ORIGIN = 'https://dev.azure.com/<org>/<project>/_git/<repo>';
--
-- Everything else (FETCH, LIST, CREATE DBT PROJECT) and the
-- task graphs in orchestration/ stay the same. If FETCH fails with an
-- authentication error, check the PAT has Code (Read) scope, hasn't expired,
-- and that USERNAME in the secret is your Azure DevOps user.

ALTER GIT REPOSITORY ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO FETCH;
LIST @ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO/branches/main;

-- 3. PROD project, built from main by the PROD task graph.
CREATE DBT PROJECT ESTIA_DBT_DEMO_PROD.DBT.ESTIA_MEDALLION
    FROM '@ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO/branches/main'
    DEFAULT_TARGET = 'prod'
    DBT_VERSION = '1.11.11'
    COMMENT = 'PROD, deployed from main';

SHOW DBT PROJECTS IN DATABASE ESTIA_DBT_DEMO_DEV;
SHOW DBT PROJECTS IN DATABASE ESTIA_DBT_DEMO_PROD;
