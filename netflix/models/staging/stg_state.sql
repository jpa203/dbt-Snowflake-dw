{{ config(materialized='table')}}

with source as (

select * from {{source('netflix', 'state')}}

)

select * from source

