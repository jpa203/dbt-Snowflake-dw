-- cleaning data and performing transformations 
        -- addinig intials
        -- solving for null values, for better query performance
        -- spelling check / renaming

{{ config(materialized='table')}}

with dim_payment as (

    select * from {{ ref ('stg_payment') }}
)

select * from dim_payment
