-- ===========================================================================
-- Step 2 of 2: connect the GitHub repository and create the PROD dbt project
-- from the main branch. Run as SYSADMIN, after setup/02_github_integration.sql.
-- Points at github.com/sfc-gh-rvashisht/estia_demo_sdlc-. Change the GitHub
-- user and repository name here if you use a different repository.
-- ===========================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE SCHEMA ESTIA_DBT_DEMO_PROD.DBT
    COMMENT = 'dbt project, Git repository and orchestration tasks';

-- A Snowflake copy of the repository. FETCH pulls the latest commits.
CREATE GIT REPOSITORY ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO
    API_INTEGRATION = ESTIA_DEMO_GITHUB
    ORIGIN = 'https://github.com/sfc-gh-rvashisht/estia_demo_sdlc-.git';

-- Azure DevOps (Azure Repos) version. Use instead of the statement above, after
-- the Azure DevOps steps in setup/02_github_integration.sql. The DBT schema
-- already exists from that step, so skip the CREATE SCHEMA above.
--
--   CREATE GIT REPOSITORY ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO
--       API_INTEGRATION = ESTIA_DEMO_ADO
--       GIT_CREDENTIALS = ESTIA_DBT_DEMO_PROD.DBT.ADO_GIT_PAT
--       ORIGIN = 'https://dev.azure.com/<org>/<project>/_git/<repo>';
--
-- Everything below (FETCH, LIST, CREATE DBT PROJECT) and the task graph in
-- orchestration/ stay the same. A merge to main in Azure Repos is picked up
-- by the DEPLOY_FROM_MAIN task in the same way as a merge in GitHub.
-- If FETCH fails with an authentication error, check the PAT has Code (Read)
-- scope, hasn't expired, and that USERNAME in the secret is your Azure DevOps
-- user.

ALTER GIT REPOSITORY ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO FETCH;

-- Check Snowflake can see the files on main.
LIST @ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO/branches/main;

-- Create the dbt project object from main.
CREATE DBT PROJECT ESTIA_DBT_DEMO_PROD.DBT.ESTIA_MEDALLION
    FROM '@ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO/branches/main'
    DEFAULT_TARGET = 'prod'
    DBT_VERSION = '1.11.11'
    COMMENT = 'Silver and gold incident reporting, deployed from main';

SHOW DBT PROJECTS IN SCHEMA ESTIA_DBT_DEMO_PROD.DBT;
