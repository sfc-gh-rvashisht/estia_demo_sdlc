select
    facilities.facility_id,
    facilities.facility_name,
    date_trunc('month', incidents.incident_date)::date as incident_month,
    count(*) as incident_count
from {{ ref('silver_incidents') }} as incidents
inner join {{ ref('silver_residents') }} as residents
    on incidents.resident_id = residents.resident_id
inner join {{ ref('silver_facilities') }} as facilities
    on residents.facility_id = facilities.facility_id
group by
    facilities.facility_id,
    facilities.facility_name,
    date_trunc('month', incidents.incident_date)::date
