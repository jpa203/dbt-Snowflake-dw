-- cleaning spelling mistakes
-- removing one column

{{ config(materialized='table')}}

with dim_membership as (

    select
    membershipid, 
    memmbershiptype as membershiptype
    from {{ref('stg_membership')}}

)

select * from dim_membership