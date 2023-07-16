-- cleaning spelling mistakes
-- removing one column

{{ config(materialized='incremental')}}

with dim_membership as (

    select
    membershipid, 
    memmbershiptype as membershiptype,
    membershiplimitpermonth,
    membershipmonthlyprice,
    membershipmonthlytax,
    membershipdvdlostprice
    
     from {{ref('stg_membership')}}

)

select * from dim_membership