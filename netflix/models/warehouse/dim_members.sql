-- cleaning data and performing transformations 
        -- addinig intials
        -- solving for null values, for better query performance
        -- spelling check / renaming

{{ config(materialized='table')}}

with dim_members as (
    select 
    memberid,
    memberfirstname,
    memberlastname,
    CONCAT(SUBSTRING(memberfirstname, 1, 1), SUBSTRING(memberlastname, 1, 1)) as memberinitials,
    COALESCE(NULLIF(memberaddres, ''), '1 Null Road') as memberaddress,
    COALESCE(NULLIF(memberphone, ''), 0) as memberphone,
    memberemail,
    memberpassword,
    membershipsincedate,
    current_flag as currentflag,
    ingestion_timestamp as effectivetimestamp
    from {{ref ('stg_member')}}

)

select * from dim_members

