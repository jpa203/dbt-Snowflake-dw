{{ config(materialized='table')}}


with source as (

    select * from {{source('netflix', 'membership')}}
)

select * from source