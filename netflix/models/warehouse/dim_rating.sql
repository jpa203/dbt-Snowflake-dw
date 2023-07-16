{{config(materialized = 'table')}}

with dim_rating as (
    select * from {{ref('stg_rating')}}
)

select * from dim_rating