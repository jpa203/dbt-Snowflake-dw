{{ config(
    materialized='incremental',
    unqiue_key='dvdid')}}

with source as (

    select * from {{source('netflix','dvd')}}
)

select *, current_timestamp() as ingestion_timestamp from source

{% if is_incremental() %}


  where ingestion_timestamp >= (select max(ingestion_timestamp) from {{ this }})

{% endif %}