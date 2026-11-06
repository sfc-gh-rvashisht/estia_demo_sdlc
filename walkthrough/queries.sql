-- Queries used during the walkthrough. Run each one separately.

-- 0. Set the name dbt-ci builds your branch into (from feature/<name>/..., in
--    capitals, e.g. JSMITH), then run these SET statements once per session.
SET dev_prefix = '<DEV_NAME>';
SET dev_silver_facilities = 'ESTIA_DBT_DEMO_DEV.' || $dev_prefix || '_SILVER.SILVER_FACILITIES';
SET dev_silver_incidents  = 'ESTIA_DBT_DEMO_DEV.' || $dev_prefix || '_SILVER.SILVER_INCIDENTS';
SET dev_gold_monthly      = 'ESTIA_DBT_DEMO_DEV.' || $dev_prefix || '_GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS';
SET dev_gold_by_category  = 'ESTIA_DBT_DEMO_DEV.' || $dev_prefix || '_GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS_BY_CATEGORY';

-- 1. Check the current session.
SELECT CURRENT_ACCOUNT_NAME(), CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE();

-- 2. Bronze facilities as landed: extra spaces, lowercase states, all text.
SELECT * FROM ESTIA_DBT_DEMO_DEV.BRONZE.FACILITIES;

-- 3. Silver facilities after dbt has cleaned them, in shared DEV (built from main).
SELECT * FROM ESTIA_DBT_DEMO_DEV.SILVER.SILVER_FACILITIES;

-- 4. Gold monthly incidents: your branch, shared DEV and PROD.
SELECT * FROM IDENTIFIER($dev_gold_monthly)
ORDER BY incident_month, facility_id;

SELECT * FROM ESTIA_DBT_DEMO_DEV.GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS
ORDER BY incident_month, facility_id;

SELECT * FROM ESTIA_DBT_DEMO_PROD.GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS
ORDER BY incident_month, facility_id;

-- 5. Where the bad record I031 exists, by layer and environment.
SELECT 'DEV bronze' AS location, COUNT(*) AS rows_found
FROM ESTIA_DBT_DEMO_DEV.BRONZE.INCIDENTS WHERE incident_id = 'I031'
UNION ALL
SELECT 'DEV silver (your branch)', COUNT(*)
FROM IDENTIFIER($dev_silver_incidents) WHERE incident_id = 'I031'
UNION ALL
SELECT 'PROD bronze', COUNT(*)
FROM ESTIA_DBT_DEMO_PROD.BRONZE.INCIDENTS WHERE incident_id = 'I031';

-- 6. Total incidents and falls in each environment. Run after the change is
--    merged and released: until then, shared DEV and PROD have no fall_count.
SELECT 'DEV (your branch)' AS environment, SUM(incident_count) AS incidents, SUM(fall_count) AS falls
FROM IDENTIFIER($dev_gold_monthly)
UNION ALL
SELECT 'DEV (main)', SUM(incident_count), SUM(fall_count)
FROM ESTIA_DBT_DEMO_DEV.GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS
UNION ALL
SELECT 'PROD', SUM(incident_count), SUM(fall_count)
FROM ESTIA_DBT_DEMO_PROD.GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS;

-- 7. Incidents by category: your branch, then PROD after release.
SELECT * FROM IDENTIFIER($dev_gold_by_category)
ORDER BY incident_month, facility_id, incident_type;

SELECT incident_type, SUM(incident_count) AS incidents
FROM ESTIA_DBT_DEMO_PROD.GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS_BY_CATEGORY
GROUP BY incident_type
ORDER BY incidents DESC;
