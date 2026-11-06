# dbt on Snowflake with Azure DevOps: developing, testing and releasing data models

This project sets up a day-to-day dbt workflow on Snowflake, with code in Azure
Repos and every deployment done by Azure Pipelines:

1. An engineer changes an existing model and adds a new one on a Git branch.
2. They push the branch, and a pipeline builds and tests it in their own
   development schemas.
3. Bad source data arrives, and a dbt test stops it reaching the reports.
4. The change is reviewed through a pull request. The same pipeline must pass
   before it can be merged.
5. A release pipeline deploys the merged code to shared development, then to
   production after an approval.

It uses a medallion architecture (bronze, silver, gold) and sample aged care
incident data. All facility names, resident IDs and incidents are sample data.
Use it as a starting point: replace the sample sources and models with your own.

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

DEV and PROD are two databases in the same Snowflake account. dbt runs inside
Snowflake; Azure Pipelines uploads the code and starts each run. Nobody builds
from their own machine.

| Environment | Where models are built | Built from | Built by |
|---|---|---|---|
| Your branch | `ESTIA_DBT_DEMO_DEV.<NAME>_SILVER` and `<NAME>_GOLD` | Your feature branch | `dbt-ci`, on every push |
| Pull request | `ESTIA_DBT_DEMO_DEV.CI_PR_<id>_SILVER` and `_GOLD` | The pull request | `dbt-ci`, as the branch policy check |
| Shared DEV | `ESTIA_DBT_DEMO_DEV.SILVER` and `GOLD` | `main` | `dbt-release` on merge, `dbt-refresh` on a schedule |
| Production | `ESTIA_DBT_DEMO_PROD.SILVER` and `GOLD` | `main` | `dbt-release` after approval, `dbt-refresh` on a schedule |

Each engineer builds into their own schemas, so several people can work on the
same model at once without affecting each other. Shared DEV always shows what
is on `main` against development data.

### The pipelines

| Pipeline | File | Runs when | Does |
|---|---|---|---|
| 1. `dbt-ci` | `pipelines/dbt-ci.yml` | Push to `feature/*`; pull requests into `main`; Run pipeline | Deploys the branch as `DBT_<NAME>` and runs `dbt build` into `<NAME>_SILVER/_GOLD` (or `CI_PR_<id>_`). A failed test fails the run and blocks the pull request. |
| 2. `dbt-release` | `pipelines/dbt-release.yml` | Merge to `main` | **DEV stage:** deploys `ESTIA_MEDALLION` and builds shared DEV. **Approval** on the `estia-prod` environment. **PROD stage:** deploys the same commit and builds PROD. |
| 3. `dbt-refresh` | `pipelines/dbt-refresh.yml` | Daily schedule, or Run pipeline | Rebuilds DEV and PROD from new bronze data with the version already released. Deploys nothing. |

`pipelines/templates/dbt-steps.yml` holds the steps all three share: sign in to
Snowflake, `snow dbt deploy`, `snow dbt execute ... build`.

```
feature/jsmith/falls-count ─► push ─► dbt-ci ─► JSMITH_SILVER/_GOLD
                                         │
                       pull request ─► dbt-ci ─► CI_PR_<id>_SILVER/_GOLD ─► review ─► merge to main
                                                                                          │
                                         dbt-release: DEV stage ◄─────────────────────────┘
                                         ESTIA_DBT_DEMO_DEV.SILVER/GOLD
                                                    │
                                              approval (estia-prod)
                                                    │
                                         dbt-release: PROD stage
                                         ESTIA_DBT_DEMO_PROD.SILVER/GOLD
```

In every run, if a silver test fails, dbt skips the gold models, so reports
keep their last good results.

### How the pipelines sign in

There are no passwords or tokens to store. Each pipeline signs in with a
short-lived token from an Azure DevOps service connection (workload identity
federation), and Snowflake checks it against a service user that trusts only
that connection.

| Service connection | Snowflake user | Role | Used by | Can reach |
|---|---|---|---|---|
| `snowflake-dev` | `SVC_ADO_DBT_DEV` | `ESTIA_DBT_DEV_DEPLOY` | `dbt-ci`, DEV stages | `ESTIA_DBT_DEMO_DEV` only |
| `snowflake-prod` | `SVC_ADO_DBT_PROD` | `ESTIA_DBT_PROD_DEPLOY` | PROD stages | `ESTIA_DBT_DEMO_PROD` only |

`dbt-ci` runs code that hasn't been reviewed yet, so its user can't reach PROD
at all. Setting a role on the connection wouldn't be enough: any SQL in the
session (a dbt hook or macro, for example) can switch to another role granted
to the same user. `snowflake-prod` is limited to `main` by a Branch control
check, and the PROD stage waits for an approval, so the only way to change PROD
is a reviewed, merged and approved release.

Snowflake doesn't read the repository itself, so no Git integration, API
integration or token is needed in Snowflake.

### Key dbt concepts

| Concept | Where to look | What it does |
|---|---|---|
| Model | `models/silver/*.sql`, `models/gold/*.sql` | A SELECT statement. dbt creates it as a table or view. |
| Source | `models/sources.yml` | Declares tables dbt reads but doesn't own (bronze). Used with `{{ source() }}`. |
| `ref()` | `models/gold/*.sql` | References another model. dbt uses these to work out build order and lineage. |
| Test | `models/schema.yml`, `tests/` | A query that returns invalid rows. No rows means the test passes. |
| `dbt build` | `snow dbt execute ... build` in the pipelines | Builds models and runs their tests, in dependency order. |
| dbt project object | Snowsight, Transformation » dbt Projects | A version of the project stored in Snowflake and run on Snowflake compute. Each pipeline run uploads a new version. |
| Target | `dbt_projects_profiles.yml` | Where a run writes: `personal` (a branch's own schemas), `dev` (shared DEV) or `prod`. |

### Project structure

```
├── dbt_project.yml              # Project settings: silver and gold are tables
├── dbt_projects_profiles.yml    # Targets used in Snowflake: personal, dev, prod
├── env.yml                      # Role, warehouse and schema prefix for runs in Snowflake
├── profiles.yml                 # Optional: running dbt on your own machine
├── requirements.txt             # Optional: dbt versions for running locally
├── models/
│   ├── sources.yml              # Bronze tables
│   ├── schema.yml               # Model descriptions and tests
│   ├── silver/                  # Cleaning and typing
│   └── gold/                    # Reporting
├── tests/                       # Custom tests on gold
├── macros/
│   └── generate_schema_name.sql # personal: <NAME>_SILVER/_GOLD. dev and prod: SILVER/GOLD
├── pipelines/
│   ├── dbt-ci.yml               # 1. Branches and pull requests
│   ├── dbt-release.yml          # 2. main to DEV, approval, PROD
│   ├── dbt-refresh.yml          # 3. Scheduled rebuild from new data
│   └── templates/dbt-steps.yml  # Steps shared by all three
├── setup/                       # One-off setup: sample data, roles, service users
├── docs/                        # Overview of the lifecycle and pipelines (HTML and PDF)
└── walkthrough/
    ├── queries.sql              # Queries to inspect each layer
    ├── bad_record_prod.sql      # Optional: a failed test in PROD
    ├── ticket-1-falls-count/    # Files for the model change, and an invalid record
    └── ticket-2-incidents-by-category/   # Files for the new model
```

---

## Setting up

Do this once, with someone who has ACCOUNTADMIN in Snowflake, can create
identities in Microsoft Entra, and is a project administrator in Azure DevOps.

### Values to replace

| Placeholder | Where | What to put | Example |
|---|---|---|---|
| `<ACCOUNT_IDENTIFIER>` | `pipelines/*.yml` | Snowflake account, `<org>-<account>` | `MYORG-MYACCOUNT` |
| `<WAREHOUSE>` | `setup/02_roles_and_service_users.sql` | Warehouse for dbt runs | `TRANSFORM_WH` |
| `<DEV_ISSUER>`, `<DEV_SUBJECT>` | `setup/02_roles_and_service_users.sql` | From the `snowflake-dev` service connection | Copy exactly |
| `<PROD_ISSUER>`, `<PROD_SUBJECT>` | `setup/02_roles_and_service_users.sql` | From the `snowflake-prod` service connection | Copy exactly |
| `<DEV_NAME>` | `walkthrough/queries.sql` | The name in your branch, in capitals | `JSMITH` |

The databases are named `ESTIA_DBT_DEMO_DEV` and `ESTIA_DBT_DEMO_PROD`. To use
other names, replace them throughout the project, including
`dbt_projects_profiles.yml`, `profiles.yml`, `macros/generate_schema_name.sql`,
`setup/` and `pipelines/`.

### Steps

| Order | Where | What to do |
|---|---|---|
| 1 | Azure Repos | Create the repository and push this project to `main`. |
| 2 | Snowflake | Run `setup/01_land_bronze.sql` as SYSADMIN, once with `demo_db` set to `ESTIA_DBT_DEMO_DEV` and once with `ESTIA_DBT_DEMO_PROD`. With real data, Azure Data Factory loads bronze instead. |
| 3 | Microsoft Entra | Create two Managed Identities (or App Registrations), one for DEV and one for PROD. |
| 4 | Azure DevOps | **Project Settings › Service connections › New › Azure Resource Manager › Workload Identity federation (manual)**. Create `snowflake-dev` with the DEV identity and `snowflake-prod` with the PROD identity. Open each one and copy its **Issuer** and **Subject**. |
| 5 | Snowflake | Paste the values into `setup/02_roles_and_service_users.sql`, replace `<WAREHOUSE>`, and run it with Execute All. It creates the `DBT` schemas, three roles and two service users. Grant `ESTIA_DBT_ENGINEER` to each engineer. |
| 6 | Azure DevOps | Install the [Snowflake CLI extension](https://marketplace.visualstudio.com/items?itemName=snowflake.build-release-task) in the organisation. |
| 7 | Azure DevOps | **Pipelines › Environments**: create `estia-dev`, and `estia-prod` with **Approvals** from the people who approve production releases. |
| 8 | Azure DevOps | Replace `<ACCOUNT_IDENTIFIER>` in the three pipeline files and push. **Pipelines › New pipeline** three times, pointing at `pipelines/dbt-ci.yml`, `dbt-release.yml` and `dbt-refresh.yml`. Rename them `dbt-ci`, `dbt-release` and `dbt-refresh`. |
| 9 | Azure DevOps | Service connection `snowflake-prod` › **Approvals and checks › Branch control**: allowed branches `refs/heads/main`. Under **Security**, allow only `dbt-release` and `dbt-refresh` to use it. |
| 10 | Azure DevOps | **Repos › Branches › main › Branch policies**: require a reviewer, and add **Build validation** with `dbt-ci`. |
| 11 | Azure DevOps | Run `dbt-release`. Approve the PROD stage. Both stages should succeed, and `ESTIA_MEDALLION` appears in each database under **Transformation » dbt Projects**. |

Set the `dbt-refresh` schedule to just after the Data Factory load finishes.
The time in the file is in UTC.

---

## Before you start (each engineer)

You need:

- VS Code with the [Snowflake extension](https://docs.snowflake.com/en/user-guide/vscode-ext)
- Git, and permission to push branches to the repository
- The `ESTIA_DBT_ENGINEER` role in Snowflake, and access to the pipelines in Azure DevOps

You don't need dbt installed: it runs inside Snowflake.

1. Clone the repository and open it in VS Code:

   ```bash
   git clone https://dev.azure.com/<ADO_ORG>/<ADO_PROJECT>/_git/<ADO_REPO>
   cd <ADO_REPO>
   ```

2. In the Snowflake extension, sign in and use the role `ESTIA_DBT_ENGINEER`.
3. Open `walkthrough/queries.sql`, set `dev_prefix` under statement 0 to the name
   you use in branch names, in capitals (`feature/jsmith/...` is `JSMITH`), and
   run the SET statements. Run them again in each new session.

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
   production projects, both named `ESTIA_MEDALLION`, and their runs. In Azure
   DevOps, open the last `dbt-release` run to see the two stages and the approval.

### Step 2: Create a branch

Two requests have come in:

| Request | Type of change |
|---|---|
| Add a falls count to the monthly incidents report | Change an existing model |
| Report monthly incidents per facility by category | Add a new model |

Name the branch `feature/<your name>/<description>`. `dbt-ci` uses the name to
choose your schemas.

```bash
git switch main
git pull
git switch -c feature/jsmith/falls-and-categories
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
environment's gold schema. The pipelines pick it up with no change.

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

### Step 6: Push the branch and let dbt-ci build it

```bash
git add models/gold/ models/schema.yml tests/
git status --short
git commit -m "Add monthly falls and incidents by category"
git push -u origin feature/jsmith/falls-and-categories
```

The push starts `dbt-ci`. In Azure DevOps, open **Pipelines › dbt-ci** and the
new run. It deploys your branch as `ESTIA_DBT_DEMO_DEV.DBT.DBT_JSMITH` and runs
`dbt build` into `JSMITH_SILVER` and `JSMITH_GOLD`. The log of the
**dbt build (personal)** step lists each model and test. The run is also listed
in Snowsight under **Transformation » dbt Projects** › `DBT_JSMITH`.

When the run succeeds:

- Query 4, first statement: your table now has `fall_count`. Shared DEV and
  production don't yet.
- Query 7, first statement: the new table has 27 rows.

To change something, edit, commit and push: each push builds again. To build a
branch with a different name, use **Run pipeline**, choose the branch and enter
the name.

### Step 7: Bad data arrives

The ingestion pipeline lands an incident with a mistyped category (`FALLL`) in
development bronze.

1. Run steps 1 and 2 in `walkthrough/ticket-1-falls-count/bad_record.sql`.
2. Run `dbt-ci` for your branch (**Run pipeline**, or push a commit). The test
   `accepted_values_silver_incidents_incident_type` fails, the run fails, and
   dbt skips the gold models because a test on the silver model they depend on
   failed.
3. Run query 5. The record is in development bronze and in your silver schema,
   because dbt builds each model before testing it. Your gold tables still hold
   their previous results, so reporting isn't affected. Production doesn't have
   the record.
4. Fix the data, not the test. Normally the source team corrects the record and
   the pipeline reloads the file. Step 4 of `bad_record.sql` simulates this. Run
   `dbt-ci` again: all tests pass.

dbt doesn't roll back models that were already built when a test fails. It skips
the models that depend on them.

Development bronze is shared. Until the record is fixed, it also fails the
shared DEV build and every other engineer's branch build.

### Step 8: Open a pull request

Open a pull request from your branch into `main`. The branch policy runs
`dbt-ci` for the pull request, into `CI_PR_<id>_SILVER` and `_GOLD`; the
pull request can't be completed until it passes. The changes show both models,
the new YAML file and the four tests. The reviewer can query your schemas to see
the results. They approve and complete it.

### Step 9: dbt-release releases it

Completing the pull request merges to `main`, which starts `dbt-release`:

1. The **DEV stage** deploys `ESTIA_MEDALLION` from `main` and builds shared DEV.
2. The **PROD stage** waits for approval on `estia-prod`. An approver reviews
   and approves it.
3. The PROD stage deploys the same commit and builds production.

Then:

- Query 6 shows 30 incidents and 10 falls in your branch, shared DEV and production.
- Query 7, second statement, shows the production totals by category.
- In Azure DevOps, **Pipelines › Environments › estia-prod** shows the
  deployment, the commit and who approved it.

Bring your local `main` up to date:

```bash
git switch main
git pull
```

### Step 10: A failed test protects production

`walkthrough/bad_record_prod.sql` lands the same invalid record in production
bronze. Run `dbt-refresh`: its PROD stage fails on the accepted-values test and
the gold models are skipped, so production gold keeps its last good results.
Step 4 of the script removes the record; run `dbt-refresh` again.

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

## Housekeeping

Each branch and pull request leaves a dbt project object (`DBT_<NAME>`,
`DBT_CI_PR_<id>`) and two schemas in DEV. Drop them when they're no longer
needed, for example as `ESTIA_DBT_DEV_DEPLOY`:

```sql
DROP DBT PROJECT IF EXISTS ESTIA_DBT_DEMO_DEV.DBT.DBT_CI_PR_123;
DROP SCHEMA IF EXISTS ESTIA_DBT_DEMO_DEV.CI_PR_123_SILVER;
DROP SCHEMA IF EXISTS ESTIA_DBT_DEMO_DEV.CI_PR_123_GOLD;
```

Instead of the `dbt-refresh` schedule, Azure Data Factory can start the refresh
at the end of its load, either by running `dbt-refresh` through the Azure DevOps
REST API, or with a Script activity that runs
`EXECUTE DBT PROJECT ESTIA_DBT_DEMO_PROD.DBT.ESTIA_MEDALLION ARGS = 'build --target prod'`.

---

## Optional: running dbt on your own machine

Some engineers prefer to try changes before pushing, or to use the dbt extension
in VS Code. `profiles.yml` has a `personal` target that writes to the same
`<NAME>_SILVER` and `<NAME>_GOLD` schemas as `dbt-ci`. It needs a role that can
create schemas in `ESTIA_DBT_DEMO_DEV`, which `ESTIA_DBT_ENGINEER` can't.

```bash
# macOS: makes the settings visible to VS Code too. Restart VS Code afterwards.
launchctl setenv SNOWFLAKE_ACCOUNT <org>-<account>
launchctl setenv SNOWFLAKE_USER <user>
launchctl setenv SNOWFLAKE_ROLE <role>
launchctl setenv SNOWFLAKE_WAREHOUSE <warehouse>
launchctl setenv DBT_DEV_PREFIX <NAME>

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
| **Configure Snowflake CLI** step fails, or `snow` can't sign in | Check the issuer and subject on the Snowflake user match the service connection exactly, `OIDC_AUDIENCE_LIST` is `api://AzureADTokenExchange`, and the step that fails maps `SNOWFLAKE_TOKEN`. |
| Sign-in blocked by a network policy | Microsoft-hosted agents have no fixed IP addresses. Use self-hosted agents with known addresses and allow those for the service users. |
| `dbt-ci` says it couldn't work out a name | Name the branch `feature/<name>/<description>`, or use **Run pipeline** and enter a name. Names start with a letter and use letters, digits and `_`. |
| `Set DBT_DEV_PREFIX to your name` | A personal build ran without a name. Run `dbt-ci` rather than executing the branch project directly. |
| PROD stage waits and never starts | It needs approval on the `estia-prod` environment. Check the approvers, and that `snowflake-prod`'s Branch control allows `refs/heads/main`. |
| `Insufficient privileges` in a deploy step | Check `setup/02_roles_and_service_users.sql` ran in full, and the service user's default role is the deploy role for that database. |
| Queries in `walkthrough/queries.sql` say an object doesn't exist | Set `dev_prefix` and run the SET statements under 0. Your schemas exist after your first `dbt-ci` run. |
| Query 6 says `FALL_COUNT` is invalid | Shared DEV or production hasn't been released from the merged change yet. Check `dbt-release` finished and PROD was approved. |
| Running locally: sign-in error mentioning a SAML identity provider | The profile uses Snowflake's own sign-in (`oauth_authorization_code`). Check `profiles.yml` hasn't been changed to `externalbrowser`, which needs SSO set up on the account. |

---

## References

- [dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake)
- [Understand CI/CD for dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake-ci-cd)
- [Tutorial: Set up CI/CD integrations on dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/tutorials/dbt-projects-on-snowflake-ci-cd-tutorial)
- [Snowflake CLI extension for Azure DevOps](https://docs.snowflake.com/en/developer-guide/snowflake-cli/cicd/azure-devops-extension)
- [Workload identity federation](https://docs.snowflake.com/en/user-guide/workload-identity-federation)
- [Azure Pipelines: environments and approvals](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments)
- [Snowflake extension for VS Code](https://docs.snowflake.com/en/user-guide/vscode-ext)
- [dbt data tests](https://docs.getdbt.com/docs/build/data-tests)
