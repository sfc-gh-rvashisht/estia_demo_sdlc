-- ===========================================================================
-- Roles and service users for the Azure Pipelines.
--
-- Run once, after setup/01_land_bronze.sql has created both databases, with
-- Execute All in the Snowflake extension. Each part switches to the role it
-- needs (USERADMIN, SYSADMIN, SECURITYADMIN).
--
-- Two service users, one per service connection in Azure DevOps:
--
--   SVC_ADO_DBT_DEV   service connection snowflake-dev    role ESTIA_DBT_DEV_DEPLOY
--                     dbt-ci (every branch and pull request), and the DEV
--                     stages of dbt-release and dbt-refresh.
--   SVC_ADO_DBT_PROD  service connection snowflake-prod   role ESTIA_DBT_PROD_DEPLOY
--                     PROD stages of dbt-release and dbt-refresh only.
--
-- dbt-ci runs code that hasn't been reviewed yet, so its user can't reach
-- PROD at all. A role set on the connection wouldn't be enough: a session can
-- switch to any role granted to its user.
--
-- ESTIA_DBT_ENGINEER is for people: it reads DEV and PROD, and changes nothing
-- except the walkthrough's sample bronze record in DEV.
--
-- Before running, replace:
--   <WAREHOUSE>        warehouse for dbt runs, e.g. TRANSFORM_WH
--   <DEV_ISSUER>, <DEV_SUBJECT>    from the snowflake-dev service connection
--   <PROD_ISSUER>, <PROD_SUBJECT>  from the snowflake-prod service connection
-- Copy the issuer and subject exactly as Azure DevOps shows them (service
-- connection > Edit). Don't build them by hand.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Roles
-- ---------------------------------------------------------------------------
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS ESTIA_DBT_DEV_DEPLOY
    COMMENT = 'Deploys and builds dbt projects in ESTIA_DBT_DEMO_DEV';
CREATE ROLE IF NOT EXISTS ESTIA_DBT_PROD_DEPLOY
    COMMENT = 'Deploys and builds the dbt project in ESTIA_DBT_DEMO_PROD';
CREATE ROLE IF NOT EXISTS ESTIA_DBT_ENGINEER
    COMMENT = 'Reads DEV and PROD dbt output';

-- Keep the roles under SYSADMIN so administrators can manage what they create.
GRANT ROLE ESTIA_DBT_DEV_DEPLOY TO ROLE SYSADMIN;
GRANT ROLE ESTIA_DBT_PROD_DEPLOY TO ROLE SYSADMIN;
GRANT ROLE ESTIA_DBT_ENGINEER TO ROLE SYSADMIN;

-- ---------------------------------------------------------------------------
-- 2. Where the dbt project objects live, and what the deploy roles can use
-- ---------------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE SCHEMA IF NOT EXISTS ESTIA_DBT_DEMO_DEV.DBT
    COMMENT = 'dbt project objects: shared DEV and one per engineer or pull request';
CREATE SCHEMA IF NOT EXISTS ESTIA_DBT_DEMO_PROD.DBT
    COMMENT = 'dbt project object for PROD';

GRANT USAGE ON WAREHOUSE <WAREHOUSE> TO ROLE ESTIA_DBT_DEV_DEPLOY;
GRANT USAGE ON WAREHOUSE <WAREHOUSE> TO ROLE ESTIA_DBT_PROD_DEPLOY;
GRANT USAGE ON WAREHOUSE <WAREHOUSE> TO ROLE ESTIA_DBT_ENGINEER;

-- DEV: read bronze, create dbt projects, create SILVER/GOLD and per-engineer schemas.
GRANT USAGE ON DATABASE ESTIA_DBT_DEMO_DEV TO ROLE ESTIA_DBT_DEV_DEPLOY;
GRANT CREATE SCHEMA ON DATABASE ESTIA_DBT_DEMO_DEV TO ROLE ESTIA_DBT_DEV_DEPLOY;
GRANT USAGE ON SCHEMA ESTIA_DBT_DEMO_DEV.BRONZE TO ROLE ESTIA_DBT_DEV_DEPLOY;
GRANT SELECT ON ALL TABLES IN SCHEMA ESTIA_DBT_DEMO_DEV.BRONZE TO ROLE ESTIA_DBT_DEV_DEPLOY;
GRANT USAGE, CREATE DBT PROJECT, CREATE STAGE ON SCHEMA ESTIA_DBT_DEMO_DEV.DBT
    TO ROLE ESTIA_DBT_DEV_DEPLOY;

-- PROD: the same, in PROD only.
GRANT USAGE ON DATABASE ESTIA_DBT_DEMO_PROD TO ROLE ESTIA_DBT_PROD_DEPLOY;
GRANT CREATE SCHEMA ON DATABASE ESTIA_DBT_DEMO_PROD TO ROLE ESTIA_DBT_PROD_DEPLOY;
GRANT USAGE ON SCHEMA ESTIA_DBT_DEMO_PROD.BRONZE TO ROLE ESTIA_DBT_PROD_DEPLOY;
GRANT SELECT ON ALL TABLES IN SCHEMA ESTIA_DBT_DEMO_PROD.BRONZE TO ROLE ESTIA_DBT_PROD_DEPLOY;
GRANT USAGE, CREATE DBT PROJECT, CREATE STAGE ON SCHEMA ESTIA_DBT_DEMO_PROD.DBT
    TO ROLE ESTIA_DBT_PROD_DEPLOY;

-- Engineers: see the databases and bronze. The walkthrough lands and removes
-- one sample record in DEV bronze; remove that grant for real source data.
GRANT USAGE ON DATABASE ESTIA_DBT_DEMO_DEV TO ROLE ESTIA_DBT_ENGINEER;
GRANT USAGE ON DATABASE ESTIA_DBT_DEMO_PROD TO ROLE ESTIA_DBT_ENGINEER;
GRANT USAGE ON SCHEMA ESTIA_DBT_DEMO_DEV.BRONZE TO ROLE ESTIA_DBT_ENGINEER;
GRANT USAGE ON SCHEMA ESTIA_DBT_DEMO_PROD.BRONZE TO ROLE ESTIA_DBT_ENGINEER;
GRANT SELECT ON ALL TABLES IN SCHEMA ESTIA_DBT_DEMO_DEV.BRONZE TO ROLE ESTIA_DBT_ENGINEER;
GRANT SELECT ON ALL TABLES IN SCHEMA ESTIA_DBT_DEMO_PROD.BRONZE TO ROLE ESTIA_DBT_ENGINEER;
GRANT INSERT, DELETE ON TABLE ESTIA_DBT_DEMO_DEV.BRONZE.INCIDENTS TO ROLE ESTIA_DBT_ENGINEER;

-- ---------------------------------------------------------------------------
-- 3. Future grants: tables in bronze, and the schemas and tables dbt creates
--    (SILVER, GOLD, <NAME>_SILVER, CI_PR_<id>_GOLD, ...), readable by engineers.
-- ---------------------------------------------------------------------------
USE ROLE SECURITYADMIN;

GRANT SELECT ON FUTURE TABLES IN SCHEMA ESTIA_DBT_DEMO_DEV.BRONZE TO ROLE ESTIA_DBT_DEV_DEPLOY;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ESTIA_DBT_DEMO_PROD.BRONZE TO ROLE ESTIA_DBT_PROD_DEPLOY;
-- Schema-level future grants take precedence over database-level ones, so
-- engineers need their own on bronze too.
GRANT SELECT ON FUTURE TABLES IN SCHEMA ESTIA_DBT_DEMO_DEV.BRONZE TO ROLE ESTIA_DBT_ENGINEER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ESTIA_DBT_DEMO_PROD.BRONZE TO ROLE ESTIA_DBT_ENGINEER;

GRANT USAGE ON FUTURE SCHEMAS IN DATABASE ESTIA_DBT_DEMO_DEV TO ROLE ESTIA_DBT_ENGINEER;
GRANT SELECT ON FUTURE TABLES IN DATABASE ESTIA_DBT_DEMO_DEV TO ROLE ESTIA_DBT_ENGINEER;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE ESTIA_DBT_DEMO_PROD TO ROLE ESTIA_DBT_ENGINEER;
GRANT SELECT ON FUTURE TABLES IN DATABASE ESTIA_DBT_DEMO_PROD TO ROLE ESTIA_DBT_ENGINEER;

-- dbt projects: engineers can see them and their runs in Snowsight.
GRANT USAGE ON SCHEMA ESTIA_DBT_DEMO_DEV.DBT TO ROLE ESTIA_DBT_ENGINEER;
GRANT USAGE ON SCHEMA ESTIA_DBT_DEMO_PROD.DBT TO ROLE ESTIA_DBT_ENGINEER;
GRANT MONITOR ON FUTURE DBT PROJECTS IN SCHEMA ESTIA_DBT_DEMO_DEV.DBT TO ROLE ESTIA_DBT_ENGINEER;
GRANT MONITOR ON FUTURE DBT PROJECTS IN SCHEMA ESTIA_DBT_DEMO_PROD.DBT TO ROLE ESTIA_DBT_ENGINEER;

-- ---------------------------------------------------------------------------
-- 4. Service users. No passwords: each trusts one Azure DevOps service
--    connection through workload identity federation.
-- ---------------------------------------------------------------------------
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS SVC_ADO_DBT_DEV
    TYPE = SERVICE
    DEFAULT_ROLE = ESTIA_DBT_DEV_DEPLOY
    DEFAULT_WAREHOUSE = <WAREHOUSE>
    DEFAULT_SECONDARY_ROLES = ()
    COMMENT = 'Azure Pipelines, service connection snowflake-dev'
    WORKLOAD_IDENTITY = (
        TYPE = OIDC
        ISSUER = '<DEV_ISSUER>'
        SUBJECT = '<DEV_SUBJECT>'
        OIDC_AUDIENCE_LIST = ('api://AzureADTokenExchange')
    );

CREATE USER IF NOT EXISTS SVC_ADO_DBT_PROD
    TYPE = SERVICE
    DEFAULT_ROLE = ESTIA_DBT_PROD_DEPLOY
    DEFAULT_WAREHOUSE = <WAREHOUSE>
    DEFAULT_SECONDARY_ROLES = ()
    COMMENT = 'Azure Pipelines, service connection snowflake-prod'
    WORKLOAD_IDENTITY = (
        TYPE = OIDC
        ISSUER = '<PROD_ISSUER>'
        SUBJECT = '<PROD_SUBJECT>'
        OIDC_AUDIENCE_LIST = ('api://AzureADTokenExchange')
    );

USE ROLE SECURITYADMIN;
GRANT ROLE ESTIA_DBT_DEV_DEPLOY TO USER SVC_ADO_DBT_DEV;
GRANT ROLE ESTIA_DBT_PROD_DEPLOY TO USER SVC_ADO_DBT_PROD;

-- Engineers: repeat for each person.
-- GRANT ROLE ESTIA_DBT_ENGINEER TO USER <USER_NAME>;

-- If the account has a network policy: Microsoft-hosted agents have no fixed
-- IP addresses. Use self-hosted agents with known addresses and allow those
-- for the two service users.
