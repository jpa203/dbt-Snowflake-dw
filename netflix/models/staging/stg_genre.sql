{{ config(materialized='table')}}

with source as (

    select * from {{source('netflix','genre')}}
)

select * from source