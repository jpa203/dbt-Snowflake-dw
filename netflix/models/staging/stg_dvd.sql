{{ config(
    materialized='incremental',
    unqiue_key='dvdid')}}

with source as (

    select * from {{source('netflix','dvd')}}
)

select *, current_timestamp() as ingestion_timestamp from source

{% if is_incremental() %}


  where dvdid not in (select distinct(dvdid) from {{ this }})

{% endif %}