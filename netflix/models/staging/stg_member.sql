{{ config(materialized='table')}}

with stg_snapshot as (

select * from {{ref('members_snapshot')}}

)

select 
memberid,
memberfirstname,
memberlastname,
memberinitial, 
memberaddres,
memberaddressid,
memberphone,
memberemail, 
memberpassword,
membershipid,
membershipsincedate, 
current_timestamp() as ingestion_timestamp,
CASE 
    WHEN  dbt_valid_to is null then 'Y'
    WHEN  dbt_valid_to is not null then 'N'
end as current_flag 

from stg_snapshot
