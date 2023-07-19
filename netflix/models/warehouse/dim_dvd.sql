{{config(materialized='table')}}

with dim_dvd as (

    select * exclude (ingestion_timestamp) from {{ref('stg_dvd')}}
)

select *  from dim_dvd