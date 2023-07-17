{{ config(materialized='table')}}

with source as (

    select * from {{source('netflix','dvd')}}
)

select *, current_timestamp() as ingestion_timestamp from source