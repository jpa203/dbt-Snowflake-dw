{{ config(materialized='table')}}

with source as (

select * from {{source('netflix', 'payment')}}

)

select * from source