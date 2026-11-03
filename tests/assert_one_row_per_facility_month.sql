-- Each facility should appear once per month. Returns any duplicates; no rows means pass.
select facility_id, incident_month, count(*) as row_count
from {{ ref('gold_facility_monthly_incidents') }}
group by facility_id, incident_month
having count(*) <> 1
