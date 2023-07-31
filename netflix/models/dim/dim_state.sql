-- cleaning data and performing transformations 

{{ config(materialized='table')}}

with dim_state as (
    select *
    from {{ref ('stg_state')}}

)

select * from dim_state

