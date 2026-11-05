# dbt on Snowflake: developing, testing and releasing data models

This project walks through the day-to-day workflow for a data engineering team
using dbt on Snowflake:

1. An engineer changes an existing model and adds a new one on a Git branch.
2. They push the branch, and Snowflake builds and tests it in their own
   development schemas.
3. Bad source data arrives, and a dbt test stops it reaching the reports.
4. The change is reviewed and merged through a pull request.
5. Snowflake deploys the merged code and builds shared development and
   production automatically.

It uses a medallion architecture (bronze, silver, gold) and sample aged care
incident data. All facility names, resident IDs and incidents are sample data.

---

## How it works

### Architecture

```
Source systems ──► Azure Data Factory ──► BRONZE ──► SILVER ──► GOLD
                                          raw        cleaned    reporting
                                          │          └─── built by dbt ───┘
                                          └── read by dbt as a source
```

| Layer | Built by | Object type | Contents |
|---|---|---|---|
| Bronze | Ingestion pipeline (Azure Data Factory) | Tables | Source data as received. All columns are text, plus `_source_file` and `_loaded_at`. |
| Silver | dbt | Tables | Trimmed, standardised and typed data, checked by tests. |
| Gold | dbt | Tables | Reporting tables. |

dbt reads bronze but never writes to it.

### Environments

All dbt runs happen inside Snowflake, from code in Git. Nobody builds from
their own machine.

| Environment | Where models are built | Built from | When |
|---|---|---|---|
| Your branch | `ESTIA_DBT_DEMO_DEV.<DEV_NAME>_SILVER` and `<DEV_NAME>_GOLD` | Your feature branch | When you run the DEV task graph with your branch and name |
| Shared DEV | `ESTIA_DBT_DEMO_DEV.SILVER` and `GOLD` | `main` | Every 5 minutes, by a task graph |
| Production | `ESTIA_DBT_DEMO_PROD.SILVER` and `GOLD` | `main` | Every 5 minutes, by a task graph |

Each engineer builds into their own schemas, so several people can work on the
same model at once without affecting each other. Shared DEV always shows what
is on `main` against development data.

### How a change reaches production

```
feature branch ─► git push ─► EXECUTE TASK DEV DEPLOY ─► your DEV schemas ─► pull request ─► merge to main
                              (your branch and name)                                              │
          ┌───────────────────────────────────────────────────────────────────────────────────────┤
          ▼                                                                                       ▼
ESTIA_DBT_DEMO_DEV.DBT  (every 5 minutes, main)                 ESTIA_DBT_DEMO_PROD.DBT  (every 5 minutes, main)
DEPLOY ──► BUILD_SILVER ──► BUILD_GOLD                          DEPLOY_FROM_MAIN ──► BUILD_SILVER ──► BUILD_GOLD
```

The merge is the last manual step. In each environment, if a silver test fails,
`BUILD_GOLD` doesn't run, so reports keep their last good results.

### One DEV task graph for main and for your branch

The DEV task graph takes two settings, `branch` and `dev_name`. On its 5-minute
schedule it uses its defaults (`main`, no name) and builds shared DEV. To build
your branch, run the same graph with your own settings:

```sql
EXECUTE TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY
    USING CONFIG = $${"branch": "<branch>", "dev_name": "<DEV_NAME>"}$$;
```

1. `DEPLOY` fetches the latest commits and deploys your branch as your own dbt
   project object, `ESTIA_DBT_DEMO_DEV.DBT.DBT_<DEV_NAME>`.
2. `BUILD_SILVER` and `BUILD_GOLD` run `dbt build --target personal` with your
   name, so the `generate_schema_name` macro writes to `<DEV_NAME>_SILVER` and
   `<DEV_NAME>_GOLD`. As in every environment, gold isn't built if a silver test
   fails.

The run appears in the task's **Run History** in Snowsight and in the
`TASK_HISTORY` query in `orchestration/02_operate.sql`, which shows the branch
and name each run was for.

Branch names must not contain `/`. Use names like `feature-falls-and-categories`.

### Key dbt concepts

| Concept | Where to look | What it does |
|---|---|---|
| Model | `models/silver/*.sql`, `models/gold/*.sql` | A SELECT statement. dbt creates it as a table or view. |
| Source | `models/sources.yml` | Declares tables dbt reads but doesn't own (bronze). Used with `{{ source() }}`. |
| `ref()` | `models/gold/*.sql` | References another model. dbt uses these to work out build order and lineage. |
| Test | `models/schema.yml`, `tests/` | A query that returns invalid rows. No rows means the test passes. |
| `dbt build` | `EXECUTE DBT PROJECT` in Snowflake | Builds models and runs their tests, in dependency order. |
| dbt project object | Snowsight, Transformation » dbt Projects | A version of the project stored in Snowflake and run on Snowflake compute. |
| Target | `dbt_projects_profiles.yml` | Where a run writes: `personal` (your schemas), `dev` (shared DEV) or `prod`. |

### Project structure

```
├── dbt_project.yml              # Project settings: silver and gold are tables
├── dbt_projects_profiles.yml    # Targets used in Snowflake: personal, dev, prod
├── env.yml                      # Role, warehouse and developer name for runs in Snowflake
├── profiles.yml                 # Optional: running dbt on your own machine
├── requirements.txt             # Optional: dbt versions for running locally
├── models/
│   ├── sources.yml              # Bronze tables
│   ├── schema.yml               # Model descriptions and tests
│   ├── silver/                  # Cleaning and typing
│   └── gold/                    # Reporting
├── tests/                       # Custom tests on gold
├── macros/
│   └── generate_schema_name.sql # personal: <DEV_NAME>_SILVER/_GOLD. dev and prod: SILVER/GOLD
├── walkthrough/
│   ├── queries.sql              # Queries to inspect each layer
│   ├── ticket-1-falls-count/    # Files for the model change, and an invalid record
│   └── ticket-2-incidents-by-category/   # Files for the new model
├── orchestration/               # The DEV and PROD task graphs and how to operate them
└── setup/                       # One-off environment setup (see the end of this guide)
```

---

## Before you start

You need:

- VS Code with the [Snowflake extension](https://docs.snowflake.com/en/user-guide/vscode-ext)
- Git, and permission to push branches to the repository
- Access to a Snowflake account where the environment has been set up (see
  [Setting up your own environment](#setting-up-your-own-environment)), with a
  role and warehouse you can use

You don't need dbt installed: it runs inside Snowflake.

1. Clone the project and open it in VS Code:

   ```bash
   git clone <repository URL>
   cd <repository folder>
   ```

2. In the Snowflake extension, sign in to the account.
3. Open `walkthrough/queries.sql`, set `dev_prefix` under statement 0 to your
   name or initials (for example `JSMITH`), and run the SET statements. Run them
   again in each new session. Use the same name as `dev_name` whenever you run
   the DEV task graph for your branch.

Model files contain `ref()` and `source()`, which only dbt can resolve, so don't
run them with the extension's Execute button.

---

## Walkthrough

### Step 1: Explore the layers

1. Run query 2 to see bronze facilities as they arrive: extra spaces in the names,
   lowercase state codes, everything stored as text.
2. Run query 3 to see the same facilities in shared DEV silver, cleaned.
3. Open the models:
   - `models/sources.yml` declares the bronze tables.
   - `models/silver/silver_facilities.sql` trims names and uppercases state codes.
   - `models/silver/silver_incidents.sql` converts the incident date from text to `DATE`.
   - `models/gold/gold_facility_monthly_incidents.sql` joins the three silver models
     with `ref()` and counts incidents per facility per month. Only months with at
     least one incident appear.
   - `models/schema.yml` holds the descriptions and tests for each model.
4. In Snowsight, open **Transformation » dbt Projects** to see the shared DEV and
   production projects, both named `ESTIA_MEDALLION`, and their runs. Open the task
   `DEPLOY` (`ESTIA_DBT_DEMO_DEV` › `DBT` › Tasks) and select **Graph** to see the
   three DEV tasks. Production has the same graph, starting at `DEPLOY_FROM_MAIN`.

### Step 2: Create a branch

Two requests have come in:

| Request | Type of change |
|---|---|
| Add a falls count to the monthly incidents report | Change an existing model |
| Report monthly incidents per facility by category | Add a new model |

```bash
git switch main
git pull
git switch -c feature-falls-and-categories
```

### Step 3: Change an existing model

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

The completed model is in
`walkthrough/ticket-1-falls-count/gold_facility_monthly_incidents.sql.example`.

### Step 4: Add a new model

A new model is a new SQL file, with its descriptions and tests in a YAML file
alongside it:

```bash
cp walkthrough/ticket-2-incidents-by-category/gold_facility_monthly_incidents_by_category.sql.example \
   models/gold/gold_facility_monthly_incidents_by_category.sql
cp walkthrough/ticket-2-incidents-by-category/gold_facility_monthly_incidents_by_category.yml.example \
   models/gold/gold_facility_monthly_incidents_by_category.yml
```

It uses the same `ref()` joins as the monthly model and adds `incident_type` to the
grouping. Because it sits in `models/gold/`, it becomes a table in each
environment's gold schema. The task graphs pick it up with no change to the
orchestration.

### Step 5: Add tests

```bash
cp walkthrough/ticket-1-falls-count/assert_expected_monthly_falls.sql.example tests/assert_expected_monthly_falls.sql
cp walkthrough/ticket-1-falls-count/assert_fall_count_bounds.sql.example tests/assert_fall_count_bounds.sql
cp walkthrough/ticket-2-incidents-by-category/assert_one_row_per_facility_month_category.sql.example tests/assert_one_row_per_facility_month_category.sql
cp walkthrough/ticket-2-incidents-by-category/assert_category_totals_match_monthly.sql.example tests/assert_category_totals_match_monthly.sql
```

| Test | Checks |
|---|---|
| `assert_expected_monthly_falls` | Fall counts match the expected values |
| `assert_fall_count_bounds` | Falls are never more than total incidents |
| `assert_one_row_per_facility_month_category` | Each facility, month and category appears once |
| `assert_category_totals_match_monthly` | Category counts add up to the totals in the existing monthly model |

### Step 6: Push the branch and build it in your schemas

```bash
git add models/gold/ models/schema.yml tests/
git status --short
git commit -m "Add monthly falls and incidents by category"
git push -u origin feature-falls-and-categories
```

Then, in the Snowflake extension, run the DEV task graph with your branch and
name (also in `orchestration/02_operate.sql`):

```sql
EXECUTE TASK ESTIA_DBT_DEMO_DEV.DBT.DEPLOY
    USING CONFIG = $${"branch": "feature-falls-and-categories", "dev_name": "<DEV_NAME>"}$$;
```

The statement returns straight away; the run takes a minute or two. Follow it in
the task's **Run History** or **Graph** tab in Snowsight, or with the
`TASK_HISTORY` query in `orchestration/02_operate.sql`. Snowflake deploys your
branch as `ESTIA_DBT_DEMO_DEV.DBT.DBT_<DEV_NAME>` and builds it into your own
schemas. Its dbt runs are listed under **Transformation » dbt Projects** ›
`DBT_<DEV_NAME>`.

When all three tasks show `SUCCEEDED`:

- Query 4, first statement: your table now has `fall_count`. Shared DEV and
  production don't yet.
- Query 7, first statement: the new table has 27 rows.

To change something, edit, commit, push and run the task graph again.

### Step 7: Bad data arrives

The ingestion pipeline lands an incident with a mistyped category (`FALLL`) in
development bronze.

1. Run steps 1 and 2 in `walkthrough/ticket-1-falls-count/bad_record.sql`.
2. Run step 3, which builds your branch again, and after a minute step 4.
   `BUILD_SILVER` shows `FAILED` on the test
   `accepted_values_silver_incidents_incident_type`, and `BUILD_GOLD` doesn't
   run. The **Graph** tab in Snowsight shows where it stopped.
3. Run query 5. The record is in development bronze and in your silver schema,
   because dbt builds each model before testing it. Your gold tables still hold
   their previous results, so reporting isn't affected. Production doesn't have
   the record.
4. Fix the data, not the test. Normally the source team corrects the record and
   the pipeline reloads the file. Step 5 of `bad_record.sql` simulates this. Run
   step 3 again: all three tasks succeed.

dbt doesn't roll back models that were already built when a test fails. It skips
the models that depend on them.

Development bronze is shared. Until the record is fixed, it also fails the
shared DEV build from `main` and every other engineer's branch build.

### Step 8: Open a pull request

Open a pull request from `feature-falls-and-categories` into `main`. The changes
show both models, the new YAML file and the four tests. The reviewer can query
your schemas to see the results. They approve and merge it. This is the last
manual step.

### Step 9: Snowflake releases it

Within 5 minutes both task graphs fetch `main`, redeploy their dbt project and
build shared DEV and production. To run them straight away, use `EXECUTE TASK`
in `orchestration/02_operate.sql`. Check first that no DEV run for `main` is in
progress: two at once redeploy the same project, and one can fail.

- The `TASK_HISTORY` query in `orchestration/02_operate.sql` shows the tasks succeeded in both environments.
- In Snowsight, the task's **Run History** and **Transformation » dbt Projects** show the new runs.
- Query 6 shows 30 incidents and 10 falls in your branch, shared DEV and production.
- Query 7, second statement, shows the production totals by category.

Bring your local `main` up to date:

```bash
git switch main
git pull
```

### Step 10: A failed test stops the production release

`orchestration/03_bad_record_prod.sql` lands the same invalid record in production
bronze and runs the task graph. `BUILD_SILVER` fails on the accepted-values test
and `BUILD_GOLD` doesn't run, so production gold keeps its last good results. The
Snowsight task graph shows where it stopped. Step 4 of the script removes the
record and runs the graph again.

---

## Expected results

### Monthly incidents (after step 3)

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

### Incidents by category (after step 4)

27 rows. Totals across all facilities and months:

| Category | Incidents |
|---|---:|
| Fall | 10 |
| Other | 8 |
| Wound | 7 |
| Medication Error | 5 |

The expected-value tests are written for this sample data and need updating if the
data changes.

## Tests included

| Test | Checks |
|---|---|
| `unique`, `not_null` | Facility, resident and incident IDs are present and unique |
| `accepted_values` | State codes and incident categories are valid |
| `relationships` | Every resident belongs to a known facility; every incident to a known resident |
| `assert_one_row_per_facility_month` | Monthly gold has one row per facility per month |
| `assert_gold_reconciles_to_silver` | Monthly gold counts every silver incident exactly once |
| `assert_expected_monthly_counts` | Monthly gold matches the expected counts for the sample data |
| `assert_expected_monthly_falls` | Fall counts match the expected values |
| `assert_fall_count_bounds` | Falls are between zero and total incidents |
| `assert_one_row_per_facility_month_category` | Category gold has one row per facility, month and category |
| `assert_category_totals_match_monthly` | Category counts add up to the monthly totals |

---

## Using Azure DevOps

### Azure Repos instead of GitHub

The workflow and the task graphs are the same. Only the Git
connection changes. Azure Repos are usually private, so Snowflake reads the
repository with a personal access token stored as a Snowflake secret. The steps
are in the comments of `setup/02_github_integration.sql` and
`setup/03_connect_github.sql`.

| | GitHub | Azure Repos |
|---|---|---|
| Credentials | None (public repository) | Personal access token with Code (Read) scope, stored as a Snowflake `SECRET` |
| `API_ALLOWED_PREFIXES` | `https://github.com/<user>` | `https://dev.azure.com/<org>` |
| `ORIGIN` | `https://github.com/<user>/<repo>.git` | `https://dev.azure.com/<org>/<project>/_git/<repo>` |
| Git repository objects | No credentials | Add `GIT_CREDENTIALS = <secret>` |

Create the token under a service account and plan for rotating it before it expires.

### Adding Azure Pipelines

In this project, engineers build their branch in their own schemas before opening
a pull request, and the task graphs release whatever is merged to `main`. Azure
Pipelines would typically add:

| Addition | What it gives you |
|---|---|
| A pipeline on each pull request that builds the branch (as the DEV task graph does) or runs `dbt build` into a CI schema | Tests must pass before a pull request can be merged, without relying on the engineer to run them |
| Branch policies on `main` | Merges only through reviewed pull requests |
| A release pipeline that runs `snow dbt deploy` on merge, with an approval gate before production | Deployment controlled and logged by the pipeline. Snowflake no longer reads the repository, so no token is needed, and `DEPLOY_FROM_MAIN` (and the DEV `DEPLOY` task) is removed from the task graphs |
| A service user with key-pair or workload identity authentication | No personal credentials in automation |
| A task schedule matched to data arrival, for example after the nightly Data Factory load | Builds once per load instead of every 5 minutes |

---

## Optional: running dbt on your own machine

Some engineers prefer to try changes before pushing, or to use the dbt extension
in VS Code. `profiles.yml` has a `personal` target that writes to the same
`<DEV_NAME>_SILVER` and `<DEV_NAME>_GOLD` schemas as the DEV task graph.

```bash
# macOS: makes the settings visible to VS Code too. Restart VS Code afterwards.
launchctl setenv SNOWFLAKE_ACCOUNT <org>-<account>
launchctl setenv SNOWFLAKE_USER <user>
launchctl setenv SNOWFLAKE_ROLE <role>
launchctl setenv SNOWFLAKE_WAREHOUSE <warehouse>
launchctl setenv DBT_DEV_PREFIX <DEV_NAME>

python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt

dbt build --profiles-dir .
dbt docs generate --profiles-dir . && dbt docs serve --port 8080   # lineage graph
```

On Windows, set the variables as user environment variables in System
Properties. The first dbt command opens a Snowflake sign-in page in your browser.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `DEPLOY` fails with `BAD_INPUT` | `dev_name` must be letters, digits or `_`; branch names can contain letters, digits, `.`, `-` and `_`. Rename a branch containing `/`. |
| Your branch run doesn't pick up your latest change | Check the commit was pushed (`git status` shows "up to date with origin"). |
| `Set DBT_DEV_PREFIX to your name` | A personal build was run without a developer name. Run the DEV task graph with `dev_name`, or set `DBT_DEV_PREFIX` when running locally. |
| Queries in `walkthrough/queries.sql` say an object doesn't exist | Set `dev_prefix` and run the SET statements under 0. Your schemas exist after your first branch run. |
| Query 6 says `FALL_COUNT` is invalid | Shared DEV or production hasn't been built from the merged change yet. Wait for the next run or run `EXECUTE TASK`. |
| Running locally: sign-in error mentioning a SAML identity provider | The profile uses Snowflake's own sign-in (`oauth_authorization_code`). Check `profiles.yml` hasn't been changed to `externalbrowser`, which needs SSO set up on the account. |

---

## Setting up your own environment

To run this in another Snowflake account, run these once, in order, with a role
that can create databases and tasks and a warehouse it can use. The scripts use
SYSADMIN and COMPUTE_WH; change them if yours differ.

| Order | File | What it does |
|---|---|---|
| 1 | `setup/01_land_bronze.sql` | Creates `ESTIA_DBT_DEMO_DEV` or `ESTIA_DBT_DEMO_PROD` with sample bronze data. Run once for each, changing `demo_db`. |
| 2 | Push this project to your own Git repository | Snowflake deploys from its branches. |
| 3 | `setup/02_github_integration.sql` | Runs as ACCOUNTADMIN. Lets Snowflake read the repository, and grants SYSADMIN the integration and `EXECUTE TASK`. Set your repository URL first. |
| 4 | `setup/03_connect_github.sql` | Runs as SYSADMIN. In each database, creates the `DBT` schema, the Git repository object and the dbt project from `main`. Set your repository URL first. |
| 5 | `orchestration/01_create_task_graph.sql` | Creates the DEV and PROD task graphs. |
| 6 | `orchestration/02_operate.sql` | Starts both schedules and runs them once. All tasks should succeed. |

Engineers need a role that can use the DEV Git repository, create dbt projects
and schemas in `ESTIA_DBT_DEMO_DEV` and use the warehouse. The demo uses SYSADMIN
for everyone; a team would normally have a separate developer role.

While the schedules run, the warehouse starts every 5 minutes. Pause them with
the `SUSPEND` statements in `orchestration/02_operate.sql` when you're not using
the project.

## References

- [dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake)
- [Deploy dbt project objects](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake-deploy)
- [Setting up Snowflake to use Git](https://docs.snowflake.com/en/developer-guide/git/git-setting-up)
- [Introduction to tasks](https://docs.snowflake.com/en/user-guide/tasks-intro)
- [Snowflake extension for VS Code](https://docs.snowflake.com/en/user-guide/vscode-ext)
- [dbt data tests](https://docs.getdbt.com/docs/build/data-tests)
