{{ config(materialized='table')}}

with source as (

    select 
    dvdtitle,
    dvdreleasedate,
    theaterreleasedate from {{source('netflix','dvd')}}
)

select * from source