-- ===========================================================================
-- Step 1 of 2: allow Snowflake to read your GitHub repositories (for both DEV
-- and PROD).
-- Run as ACCOUNTADMIN (integrations are account-level objects).
-- Points at github.com/sfc-gh-rvashisht/estia_demo_sdlc-. Change the GitHub
-- user and repository name here if you use a different repository.
-- ===========================================================================

USE ROLE ACCOUNTADMIN;

CREATE API INTEGRATION ESTIA_DEMO_GITHUB
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-rvashisht')
    ENABLED = TRUE
    COMMENT = 'Read access to the dbt demo GitHub repository';

-- Let SYSADMIN use the integration and run tasks. SYSADMIN owns everything else.
GRANT USAGE ON INTEGRATION ESTIA_DEMO_GITHUB TO ROLE SYSADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;

-- ===========================================================================
-- Azure DevOps (Azure Repos) instead of GitHub
--
-- Use this instead of the CREATE API INTEGRATION above when the repository is
-- in Azure Repos. Azure Repos are usually private, so Snowflake reads the
-- repository with a personal access token (PAT) stored as a Snowflake secret.
--
-- In Azure DevOps:
--   1. User settings > Personal access tokens > New token.
--      Scope: Code (Read) only. Set an expiry date. Copy the token.
--      For anything beyond a demo, create the token under a service account,
--      not a named person, and plan for rotating it before it expires.
--   2. Repos > Clone > HTTPS. The URL looks like
--      https://dev.azure.com/<org>/<project>/_git/<repo>
--      Remove any "<org>@" after "https://" if the copied URL includes it.
--   3. If the Azure DevOps organisation restricts access by IP address, add
--      Snowflake's egress IP addresses to its allowlist.
--
-- In Snowflake. The secret is a schema object, so create the DBT schemas first
-- as SYSADMIN, then run the rest as ACCOUNTADMIN. Both the DEV and PROD Git
-- repository objects use the same secret:
--
--   USE ROLE SYSADMIN;
--   CREATE SCHEMA IF NOT EXISTS ESTIA_DBT_DEMO_DEV.DBT;
--   CREATE SCHEMA IF NOT EXISTS ESTIA_DBT_DEMO_PROD.DBT;
--
--   USE ROLE ACCOUNTADMIN;
--
--   CREATE SECRET ESTIA_DBT_DEMO_PROD.DBT.ADO_GIT_PAT
--       TYPE = password
--       USERNAME = '<Azure DevOps user, e.g. name@estia.com.au>'
--       PASSWORD = '<personal access token>';
--
--   CREATE API INTEGRATION ESTIA_DEMO_ADO
--       API_PROVIDER = git_https_api
--       API_ALLOWED_PREFIXES = ('https://dev.azure.com/<org>')
--       ALLOWED_AUTHENTICATION_SECRETS = (ESTIA_DBT_DEMO_PROD.DBT.ADO_GIT_PAT)
--       ENABLED = TRUE
--       COMMENT = 'Read access to the dbt project in Azure Repos';
--
--   GRANT USAGE ON INTEGRATION ESTIA_DEMO_ADO TO ROLE SYSADMIN;
--   GRANT USAGE ON SECRET ESTIA_DBT_DEMO_PROD.DBT.ADO_GIT_PAT TO ROLE SYSADMIN;
--   GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;
--
-- Then use the Azure DevOps version of CREATE GIT REPOSITORY in
-- setup/03_connect_github.sql.
--
-- Alternative: an Azure Pipeline that runs `snow dbt deploy` on merge to main.
-- Snowflake then doesn't read the repository at all: no integration, secret
-- or PAT is needed, and the DEPLOY_FROM_MAIN task is replaced by the pipeline.
-- This is the approach Snowflake recommends for production deployments.
-- ===========================================================================
