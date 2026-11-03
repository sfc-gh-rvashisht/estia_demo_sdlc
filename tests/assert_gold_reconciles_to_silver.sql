-- Every incident in silver should be counted exactly once in gold.
select
    (select count(*) from {{ ref('silver_incidents') }}) as source_count,
    (select coalesce(sum(incident_count), 0) from {{ ref('gold_facility_monthly_incidents') }}) as reported_count
where source_count <> reported_count
