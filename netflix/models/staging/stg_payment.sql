{{ config(materialized='incremental')}}

with source as (

select * from {{source('netflix', 'payment')}}

)

select * from source