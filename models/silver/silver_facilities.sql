select
    trim(facility_id)   as facility_id,
    trim(facility_name) as facility_name,
    upper(trim(state))  as state,
    _loaded_at
from {{ source('bronze', 'facilities') }}
