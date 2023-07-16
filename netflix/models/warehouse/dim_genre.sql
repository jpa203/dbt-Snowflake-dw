-- cleaning data and performing transformations 
        -- addinig intials
        -- solving for null values, for better query performance
        -- spelling check / renaming

{{ config(materialized='table')}}

with dim_genre as (

    select * from {{ ref ('stg_genre') }}
)

select * from dim_genre
