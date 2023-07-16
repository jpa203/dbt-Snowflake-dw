{{ config(materialized='view')}}


with dim_date as (

    select * from {{ref ('stg_date')}}
)
select * from dim_date