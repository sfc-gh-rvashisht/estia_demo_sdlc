-- Expected monthly incident counts for the sample data in setup/01_land_bronze.sql.
with expected as (
    select column1::varchar as facility_id,
           column2::date as incident_month,
           column3::integer as incident_count
    from values
        ('F001', '2026-01-01', 4), ('F002', '2026-01-01', 3), ('F003', '2026-01-01', 3),
        ('F001', '2026-02-01', 3), ('F002', '2026-02-01', 4), ('F003', '2026-02-01', 3),
        ('F001', '2026-03-01', 3), ('F002', '2026-03-01', 3), ('F003', '2026-03-01', 4)
), actual as (
    select * from {{ ref('gold_facility_monthly_incidents') }}
)
select expected.facility_id as expected_facility, actual.facility_id as actual_facility,
       expected.incident_month as expected_month, actual.incident_month as actual_month
from expected
full outer join actual
    on expected.facility_id = actual.facility_id
    and expected.incident_month = actual.incident_month
where expected.facility_id is null or actual.facility_id is null
   or actual.incident_count is null
   or expected.incident_count <> actual.incident_count
