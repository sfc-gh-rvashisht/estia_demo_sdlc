# dbt on Snowflake: a day in the life of the data engineering team

This project shows how an engineering team works day to day with dbt on Snowflake:
changing an existing model, adding a new model, reviewing each change in a pull
request, and letting Snowflake release and build whatever is merged to `main`.

The walkthrough follows two pieces of backlog work:

| Ticket | Type of change | Request |
|---|---|---|
| 1 | Change an existing model | Add a falls count to the monthly incidents report |
| 2 | Add a new model | Report monthly incidents per facility by category |

Each ticket follows the same steps:

```
branch ─► develop and test in DEV ─► pull request ─► merge to main ─► Snowflake task graph
                                                                      deploys main and
                                                                      builds PROD
```

The project uses sample aged care incident data. All facility names, resident IDs
and incidents are sample data.

## Architecture

```
Source systems ──► Azure Data Factory ──► BRONZE ──► SILVER ──► GOLD
                                          raw        cleaned    reporting
                                          │          └─── built by dbt ───┘
                                          └── read by dbt as a source
```

| Layer | Schema | Built by | Object type | Contents |
|---|---|---|---|---|
| Bronze | `BRONZE` | Ingestion pipeline | Tables | Source data as received. All columns are text, plus `_source_file` and `_loaded_at`. |
| Silver | `SILVER` | dbt | Tables | Trimmed, standardised and typed data, checked by tests. |
| Gold | `GOLD` | dbt | Tables | Reporting tables. |

In this project `setup/01_land_bronze.sql` stands in for Data Factory and loads
the bronze tables directly.

### Environments and release

| Environment | Where models are built | Built by | When |
|---|---|---|---|
| Development | `ESTIA_DBT_DEMO_DEV.<PREFIX>_SILVER` and `<PREFIX>_GOLD`, one pair per engineer (for example `RVASHISHT_SILVER`) | dbt Core on the engineer's machine, from VS Code | While working on a feature branch |
| Production | `ESTIA_DBT_DEMO_PROD.SILVER` and `GOLD` | dbt project object `ESTIA_DBT_DEMO_PROD.DBT.ESTIA_MEDALLION`, run by a Snowflake task graph | Automatically, every 5 minutes, from whatever is on `main` |

Each engineer sets `DBT_DEV_PREFIX` once, and every local build goes to their own
schemas. Two engineers can work on the same model at the same time without
affecting each other. All engineers read the same DEV bronze data.

```
GitHub main ──► DEPLOY_FROM_MAIN ──► BUILD_SILVER ──► BUILD_GOLD
                pull latest main     build + test     build + test
                redeploy project     silver models    gold models
```

The task graph is in `orchestration/01_create_task_graph.sql`. If a silver test
fails, `BUILD_GOLD` doesn't run, so PROD reporting keeps its last good results.
Nothing in PROD is run by hand, and engineers can't build PROD from their machines:
the local profile only has a DEV target.

## Key dbt concepts

| Concept | Where to look | What it does |
|---|---|---|
| Model | `models/silver/*.sql`, `models/gold/*.sql` | A SELECT statement. dbt creates it as a table or view. |
| Source | `models/sources.yml` | Declares tables dbt reads but doesn't own (bronze). Used with `{{ source() }}`. |
| `ref()` | `models/gold/*.sql` | References another model. dbt uses these to work out build order and lineage. |
| Test | `models/schema.yml`, `tests/` | A query that returns invalid rows. No rows means the test passes. |
| Target | `profiles.yml`, `dbt_projects_profiles.yml` | Which environment (database) dbt builds into. |
| `dbt build` | Terminal, or `EXECUTE DBT PROJECT` in Snowflake | Builds models and runs their tests, in dependency order. |
| dbt project object | `setup/03_connect_github.sql` | The project stored in Snowflake and run on Snowflake compute. |

## Project structure

```
├── dbt_project.yml              # Project settings: silver and gold are tables
├── profiles.yml                 # Connection for local development (DEV)
├── dbt_projects_profiles.yml    # Connection used when the project runs inside Snowflake (PROD)
├── env.yml                      # Role and warehouse for runs inside Snowflake
├── requirements.txt             # dbt versions for local development
├── setup/
│   ├── 01_land_bronze.sql       # Creates an environment and loads sample bronze data
│   ├── 02_github_integration.sql  # ACCOUNTADMIN: lets Snowflake read GitHub; grants to SYSADMIN
│   └── 03_connect_github.sql    # SYSADMIN: Git repository and the PROD dbt project
├── orchestration/
│   ├── 01_create_task_graph.sql # Deploy from main, then build silver, then gold
│   ├── 02_operate.sql           # Start, run now, monitor, stop
│   └── 03_bad_record_prod.sql   # Optional: shows the graph stopping on a failed test
├── models/
│   ├── sources.yml              # Bronze tables
│   ├── schema.yml               # Model descriptions and tests
│   ├── silver/                  # Cleaning and typing
│   └── gold/                    # Reporting
├── tests/                       # Custom tests on gold
├── macros/
│   └── generate_schema_name.sql # DEV: <PREFIX>_SILVER/_GOLD per engineer. PROD: SILVER/GOLD
└── walkthrough/
    ├── queries.sql              # Queries to inspect each layer
    ├── ticket-1-falls-count/    # Completed files for ticket 1, and an invalid record
    └── ticket-2-incidents-by-category/   # Completed files for ticket 2
```

Local dbt reads `profiles.yml` and signs in through the browser. Snowflake reads
`dbt_projects_profiles.yml` and runs as the task's owner role, so neither file
contains credentials.

## Prerequisites

- A Snowflake account with dbt Projects on Snowflake available, a warehouse, a role
  that can create databases and tasks, and access to a role that can create an API
  integration (for example ACCOUNTADMIN) for the one-off GitHub connection
- A GitHub account, with Git on your machine signed in to it (able to `git push`)
- VS Code with the [Snowflake extension](https://docs.snowflake.com/en/user-guide/vscode-ext)
- Python 3.10 or later

The Snowflake extension and dbt connect separately. Run dbt models from the
terminal, not with the extension's Execute button: model files contain `ref()`
and `source()`, which only dbt can resolve.

---

## Part 1: One-off setup

### 1.1 Install dbt

Open this folder in VS Code, then in the terminal:

```bash
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Set the connection details for local dbt:

```bash
export SNOWFLAKE_ACCOUNT='<org>-<account>'
export SNOWFLAKE_USER='<user>'
export SNOWFLAKE_ROLE='<role>'
export SNOWFLAKE_WAREHOUSE='<warehouse>'
export DBT_DEV_PREFIX='<your name>'      # for example RVASHISHT
```

On Windows PowerShell use `$env:SNOWFLAKE_ACCOUNT = '<org>-<account>'`, and so on.

### 1.2 Load bronze data

In the Snowflake extension, run query 1 in `walkthrough/queries.sql` to confirm
the account, role and warehouse. Then open `setup/01_land_bronze.sql`:

1. Leave `SET demo_db = 'ESTIA_DBT_DEMO_DEV';` and run **Execute All**.
2. Change the value to `'ESTIA_DBT_DEMO_PROD'` and run **Execute All** again.
3. Change it back to `'ESTIA_DBT_DEMO_DEV'`.

Each environment now has three bronze tables: 3 facilities, 12 residents and
30 incidents from January to March 2026.

### 1.3 Build DEV locally

```bash
dbt debug --profiles-dir . --target dev
dbt build --profiles-dir . --target dev
```

DEV now has your own schemas, for example `ESTIA_DBT_DEMO_DEV.RVASHISHT_SILVER`
(three tables) and `RVASHISHT_GOLD` (one table with 9 rows and 30 incidents). dbt
creates these schemas on the first build.

In `walkthrough/queries.sql`, set `dev_prefix` in statement 0 to the same value as
`DBT_DEV_PREFIX`, and run the SET statements once per session.

### 1.4 Put the project on GitHub

On GitHub, create a new **public**, empty repository (for example `estia-dbt-demo`)
(no README, licence or .gitignore). Then:

```bash
git init -b main
git add .
git status --short
git commit -m "Add silver and gold incident reporting"
git remote add origin https://github.com/<github-user>/<repository>.git
git push -u origin main
```

Check `git status --short` before committing: `.venv`, `target` and `logs` are
excluded by `.gitignore`.

### 1.5 Connect Snowflake to GitHub and create the PROD project

In both scripts, set the GitHub user and repository name to your repository.

1. Run `setup/02_github_integration.sql` as **ACCOUNTADMIN**. It creates the API
   integration that lets Snowflake read your GitHub repositories, and grants
   SYSADMIN permission to use it and to run tasks.
2. Run `setup/03_connect_github.sql` as **SYSADMIN**. It creates the
   `ESTIA_DBT_DEMO_PROD.DBT` schema, the Git repository object
   `ESTIA_DBT_DEMO_PROD.DBT.ESTIA_REPO`, and the dbt project object
   `ESTIA_DBT_DEMO_PROD.DBT.ESTIA_MEDALLION` from `main`.

SYSADMIN owns the schema, repository, project and tasks, so the tasks can update
the repository and redeploy the project.

### 1.6 Create and start the task graph

Run `orchestration/01_create_task_graph.sql` as SYSADMIN. The tasks run on
`COMPUTE_WH`. Then in `orchestration/02_operate.sql` run:

1. `SYSTEM$TASK_DEPENDENTS_ENABLE(...)` to start the schedule.
2. `EXECUTE TASK ...` to run it now.
3. The `TASK_HISTORY` query. After a minute or two, all three tasks show `SUCCEEDED`.

Run query 4 in `walkthrough/queries.sql` to see the same 9 rows in your DEV schemas
and in PROD.

In Snowsight:

- **Transformation » dbt Projects** lists `ESTIA_MEDALLION` and each run.
- Open the task `DEPLOY_FROM_MAIN` (in the database explorer under
  `ESTIA_DBT_DEMO_PROD` › `DBT` › Tasks). The **Graph** tab shows the three tasks;
  **Run History** shows each run.

---

## Part 2: Explore the project

Run queries 2 and 3 in `walkthrough/queries.sql` to compare bronze and silver
facilities. Bronze has extra spaces in the names and lowercase state codes;
silver has neither.

Open the silver models:

- `silver_facilities.sql` trims names and uppercases state codes.
- `silver_incidents.sql` converts the incident date from text to `DATE`.

Open `models/gold/gold_facility_monthly_incidents.sql`. It joins the three silver
models with `ref()` and counts incidents per facility per month. Only months with
at least one incident appear.

Open `models/schema.yml` to see the descriptions and tests for each model.

---

## Part 3: Ticket 1, change an existing model

> **Request:** Add a falls count to the monthly incidents report.

### 3.1 Create a branch

```bash
git switch main
git pull
git switch -c feature/monthly-falls
```

### 3.2 Change the model

In `models/gold/gold_facility_monthly_incidents.sql`, add a comma after
`count(*) as incident_count`, then add:

```sql
sum(case when incidents.incident_type = 'Fall' then 1 else 0 end) as fall_count
```

In `models/schema.yml`, add this under the gold model's `columns`:

```yaml
      - name: fall_count
        description: Incidents with the category Fall. Zero when a month has no falls.
        data_tests: [not_null]
```

Add two tests:

```bash
cp walkthrough/ticket-1-falls-count/assert_expected_monthly_falls.sql.example tests/assert_expected_monthly_falls.sql
cp walkthrough/ticket-1-falls-count/assert_fall_count_bounds.sql.example tests/assert_fall_count_bounds.sql
```

- `assert_expected_monthly_falls.sql` checks the fall counts against the expected values.
- `assert_fall_count_bounds.sql` checks falls are never more than total incidents.

The completed model is in `walkthrough/ticket-1-falls-count/gold_facility_monthly_incidents.sql.example`.

### 3.3 Build and test in DEV

```bash
dbt build --profiles-dir . --target dev --select gold_facility_monthly_incidents+
```

`--select gold_facility_monthly_incidents+` builds the changed model and anything
downstream of it, and runs their tests, in your own schemas. Your DEV gold table
now has a `fall_count` column. PROD is unchanged.

### 3.4 Catch an invalid record

This simulates the ingestion pipeline landing an incident with a mistyped category
(`FALLL`) in DEV bronze. DEV bronze is shared, so every engineer's next DEV build
would see the same record.

1. In the Snowflake extension, run steps 1 and 2 in
   `walkthrough/ticket-1-falls-count/bad_record.sql`.
2. Build DEV:

   ```bash
   dbt build --profiles-dir . --target dev
   ```

   The test `accepted_values_silver_incidents_incident_type` fails. dbt skips the
   gold model because a test on the silver model it depends on failed.

3. Run query 5 in `walkthrough/queries.sql`. The record is in DEV bronze and in
   your DEV silver, because dbt builds each model before testing it. Your DEV gold
   still holds its previous results. PROD does not have the record.

4. Fix the data, not the test. In practice the source team corrects the record and
   the pipeline reloads the file. To simulate this, run step 3 in `bad_record.sql`.

5. Build DEV again. All tests pass.

### 3.5 Open a pull request

```bash
git status --short
git add models/gold/gold_facility_monthly_incidents.sql models/schema.yml \
        tests/assert_expected_monthly_falls.sql tests/assert_fall_count_bounds.sql
git commit -m "Add monthly falls per facility"
git push -u origin feature/monthly-falls
```

On GitHub, open a pull request from `feature/monthly-falls` into `main`. The
**Files changed** tab shows the model change, the YAML and the two new tests.
A reviewer approves it and merges it. That is the last manual step: from here
Snowflake releases the change to PROD on its own.

### 3.6 Snowflake releases it

Within 5 minutes the task graph pulls `main`, redeploys the dbt project and builds
PROD. Nothing needs to be run. (When recording, you can trigger the same graph
straight away with `EXECUTE TASK` in `orchestration/02_operate.sql` instead of
waiting.)

Check the result:

- The `TASK_HISTORY` query in `orchestration/02_operate.sql` shows the three tasks succeeded.
- Query 6 in `walkthrough/queries.sql` shows 30 incidents and 10 falls in your DEV schemas and in PROD.
- In Snowsight, the task's **Run History** and **Transformation » dbt Projects** show the new run.

Bring your local `main` up to date:

```bash
git switch main
git pull
```

---

## Part 4: Ticket 2, add a new model

> **Request:** Report monthly incidents per facility by category.

### 4.1 Create a branch

```bash
git switch -c feature/incidents-by-category
```

### 4.2 Add the model and its documentation

A new model is a new SQL file. Its tests and descriptions go in a YAML file
alongside it:

```bash
cp walkthrough/ticket-2-incidents-by-category/gold_facility_monthly_incidents_by_category.sql.example \
   models/gold/gold_facility_monthly_incidents_by_category.sql
cp walkthrough/ticket-2-incidents-by-category/gold_facility_monthly_incidents_by_category.yml.example \
   models/gold/gold_facility_monthly_incidents_by_category.yml
```

The SQL uses the same `ref()` joins as the monthly model and adds `incident_type`
to the grouping. Because it sits in `models/gold/`, it is created as a table in your
`<PREFIX>_GOLD` schema in DEV and in `GOLD` in PROD. The task graph's `BUILD_GOLD`
step picks it up without any change to the orchestration.

Add two tests:

```bash
cp walkthrough/ticket-2-incidents-by-category/assert_one_row_per_facility_month_category.sql.example \
   tests/assert_one_row_per_facility_month_category.sql
cp walkthrough/ticket-2-incidents-by-category/assert_category_totals_match_monthly.sql.example \
   tests/assert_category_totals_match_monthly.sql
```

- `assert_one_row_per_facility_month_category.sql` checks each facility, month and category appears once.
- `assert_category_totals_match_monthly.sql` checks the category counts add up to the totals in the existing monthly model.

### 4.3 Build and test in DEV

```bash
dbt build --profiles-dir . --target dev --select gold_facility_monthly_incidents_by_category+
```

Run the first query under 7 in `walkthrough/queries.sql`. The new table has 27 rows.

### 4.4 Check the lineage

```bash
dbt docs generate --profiles-dir . --target dev
dbt docs serve --port 8080
```

The lineage graph shows the new model alongside the existing one, both built from
the silver tables. Press Ctrl+C to stop the server.

### 4.5 Open a pull request

```bash
git add models/gold/gold_facility_monthly_incidents_by_category.sql \
        models/gold/gold_facility_monthly_incidents_by_category.yml \
        tests/assert_one_row_per_facility_month_category.sql \
        tests/assert_category_totals_match_monthly.sql
git commit -m "Add monthly incidents by category"
git push -u origin feature/incidents-by-category
```

Open the pull request on GitHub, review and merge.

### 4.6 Snowflake releases it

The task graph releases it within 5 minutes (or trigger it with `EXECUTE TASK`).
When the three tasks have succeeded, run the second query under 7 in
`walkthrough/queries.sql`. Then:

```bash
git switch main
git pull
```

---

## Part 5 (optional): A failed test stops the release

`orchestration/03_bad_record_prod.sql` lands the same invalid record in PROD
bronze and runs the task graph. `BUILD_SILVER` fails on the accepted-values test
and `BUILD_GOLD` doesn't run, so PROD gold keeps its last good results. The task
graph shows the failure in Snowsight. Step 4 removes the record and runs the graph
again.

## After the demo

Stop the schedule so the warehouse isn't woken every 5 minutes:

```sql
ALTER TASK ESTIA_DBT_DEMO_PROD.DBT.DEPLOY_FROM_MAIN SUSPEND;
```

---

## Expected results

### Monthly incidents (after ticket 1)

| Month | Facility | Incidents | Falls |
|---|---|---:|---:|
| 2026-01-01 | F001 | 4 | 2 |
| 2026-01-01 | F002 | 3 | 1 |
| 2026-01-01 | F003 | 3 | 0 |
| 2026-02-01 | F001 | 3 | 1 |
| 2026-02-01 | F002 | 4 | 2 |
| 2026-02-01 | F003 | 3 | 1 |
| 2026-03-01 | F001 | 3 | 0 |
| 2026-03-01 | F002 | 3 | 1 |
| 2026-03-01 | F003 | 4 | 2 |

### Incidents by category (after ticket 2)

27 rows. Totals across all facilities and months:

| Category | Incidents |
|---|---:|
| Fall | 10 |
| Other | 8 |
| Wound | 7 |
| Medication Error | 5 |

The expected-value tests in `tests/` are written for this sample data and need
updating if the data changes.

## Tests included

| Test | Checks |
|---|---|
| `unique`, `not_null` | Facility, resident and incident IDs are present and unique |
| `accepted_values` | State codes and incident categories are valid |
| `relationships` | Every resident belongs to a known facility; every incident to a known resident |
| `assert_one_row_per_facility_month` | Monthly gold has one row per facility per month |
| `assert_gold_reconciles_to_silver` | Monthly gold counts every silver incident exactly once |
| `assert_expected_monthly_counts` | Monthly gold matches the expected counts for the sample data |
| `assert_expected_monthly_falls` | Fall counts match the expected values (ticket 1) |
| `assert_fall_count_bounds` | Falls are between zero and total incidents (ticket 1) |
| `assert_one_row_per_facility_month_category` | Category gold has one row per facility, month and category (ticket 2) |
| `assert_category_totals_match_monthly` | Category counts add up to the monthly totals (ticket 2) |

## Going further

In this walkthrough the engineer builds and tests in their own DEV schemas before
opening the pull request, and the task graph releases whatever is merged to
`main`. A production setup would typically add an Azure DevOps (or GitHub Actions)
pipeline around the same steps:

| Addition | What it gives you |
|---|---|
| A pipeline on each pull request that runs `dbt build` into a CI schema in DEV | Tests must pass before a pull request can be merged |
| A shared DEV or TEST environment built by the pipeline from `main` or a release branch | Changes from several engineers tested together before PROD |
| Branch protection on `main` | Merges only through reviewed pull requests |
| A release pipeline that runs `snow dbt deploy` on merge, instead of the task pulling from Git | Deployment controlled and logged by the pipeline, with an approval gate |
| A service user with key-pair or workload identity authentication for pipelines | No personal credentials in automation |
| A task schedule matched to data arrival (for example after the nightly Data Factory load) | PROD builds once per load instead of every 5 minutes |

## Resetting

To run the walkthrough again:

1. Check that I031 is not in DEV or PROD bronze.
2. On GitHub, open each merged pull request and use **Revert** to create a revert
   pull request, then merge it. The task graph redeploys the starting code.
3. Locally: `git switch main`, `git pull`, delete the feature branches, then
   `dbt build --profiles-dir . --target dev`.
4. Drop the new table from your DEV schema and from PROD. dbt doesn't remove tables
   for models that no longer exist:

   ```sql
   DROP TABLE ESTIA_DBT_DEMO_DEV.RVASHISHT_GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS_BY_CATEGORY;
   DROP TABLE ESTIA_DBT_DEMO_PROD.GOLD.GOLD_FACILITY_MONTHLY_INCIDENTS_BY_CATEGORY;
   ```

## References

- [dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake)
- [Deploy dbt project objects](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake-deploy)
- [Setting up Snowflake to use Git](https://docs.snowflake.com/en/developer-guide/git/git-setting-up)
- [Introduction to tasks](https://docs.snowflake.com/en/user-guide/tasks-intro)
- [Snowflake extension for VS Code](https://docs.snowflake.com/en/user-guide/vscode-ext)
- [dbt data tests](https://docs.getdbt.com/docs/build/data-tests)
