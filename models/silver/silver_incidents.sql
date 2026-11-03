select
    trim(incident_id)         as incident_id,
    trim(resident_id)         as resident_id,
    to_date(incident_date)    as incident_date,
    trim(incident_type)       as incident_type,
    _loaded_at
from {{ source('bronze', 'incidents') }}
