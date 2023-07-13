{{ config(materialized='table')}}

with source as (

select * from {{source('netflix', 'member')}}

)
select * from source