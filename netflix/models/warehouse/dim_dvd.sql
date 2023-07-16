{{config(materialized='table')}}

with dim_dvd as (

    select * from {{ref('stg_dvd')}}
)

select * from dim_dvd