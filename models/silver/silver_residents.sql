select
    trim(resident_id) as resident_id,
    trim(facility_id) as facility_id,
    _loaded_at
from {{ source('bronze', 'residents') }}
