{{ config(materialized='incremental')}}


with source as (

    select * from {{source('netflix', 'membership')}}
)

select * from source