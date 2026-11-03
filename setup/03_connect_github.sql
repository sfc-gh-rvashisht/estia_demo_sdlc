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
-- And in ESTIA_DBT_DEMO_DEV only:
--   4. Procedure DBT.DEPLOY_BRANCH, which engineers call to deploy their
--      feature branch and build it into their own schemas.
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

-- 4. Deploy an engineer's branch and build it into their own schemas.
--    Usage: CALL ESTIA_DBT_DEMO_DEV.DBT.DEPLOY_BRANCH('JSMITH', 'feature-x');
--    Creates or updates the engineer's dbt project ESTIA_DBT_DEMO_DEV.DBT.DBT_<NAME>
--    from the branch, then runs `dbt build --target personal`, which writes to
--    ESTIA_DBT_DEMO_DEV.<NAME>_SILVER and <NAME>_GOLD.
--    Optional third argument: extra dbt arguments, e.g. '--select gold_facility_monthly_incidents+'.
CREATE OR REPLACE PROCEDURE ESTIA_DBT_DEMO_DEV.DBT.DEPLOY_BRANCH(
    DEV_NAME VARCHAR, BRANCH VARCHAR, DBT_ARGS VARCHAR DEFAULT '')
RETURNS TABLE()
LANGUAGE SQL
COMMENT = 'Deploy a feature branch and build it into the engineer''s own DEV schemas'
EXECUTE AS CALLER
AS
$$
DECLARE
    bad_input EXCEPTION (-20001, 'DEV_NAME must be letters, digits or underscores; BRANCH must be letters, digits, dots, dashes or underscores (no slashes); DBT_ARGS must not contain quotes or semicolons.');
    name VARCHAR DEFAULT UPPER(TRIM(:DEV_NAME));
    project VARCHAR;
    source VARCHAR;
    res RESULTSET;
BEGIN
    IF (NOT REGEXP_LIKE(:name, '^[A-Z][A-Z0-9_]{0,30}$')
        OR NOT REGEXP_LIKE(:BRANCH, '^[A-Za-z0-9._-]{1,100}$')
        OR REGEXP_LIKE(:DBT_ARGS, '.*[\'";].*')) THEN
        RAISE bad_input;
    END IF;

    project := 'ESTIA_DBT_DEMO_DEV.DBT.DBT_' || :name;
    source := '@ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO/branches/' || :BRANCH;

    ALTER GIT REPOSITORY ESTIA_DBT_DEMO_DEV.DBT.ESTIA_REPO FETCH;

    -- DEFAULT_TARGET is dev because Snowflake compiles the project when it is
    -- created or redeployed, before a developer name is passed in. The build
    -- below always uses --target personal with the name.
    EXECUTE IMMEDIATE 'CREATE DBT PROJECT IF NOT EXISTS ' || :project ||
        ' FROM ''' || :source || ''' DEFAULT_TARGET = ''dev'' DBT_VERSION = ''1.11.11''' ||
        ' COMMENT = ''Feature branch deployments for ' || :name || '''';
    EXECUTE IMMEDIATE 'ALTER DBT PROJECT ' || :project || ' DEPLOY FROM ''' || :source || '''';

    res := (EXECUTE IMMEDIATE 'EXECUTE DBT PROJECT ' || :project ||
        ' ARGS = ''build --target personal ' || :DBT_ARGS || '''' ||
        ' ENV_VARS = (''DBT_DEV_PREFIX'' = ''' || :name || ''')');
    RETURN TABLE(res);
END;
$$;

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
-- Everything else (FETCH, LIST, CREATE DBT PROJECT, DEPLOY_BRANCH) and the
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
