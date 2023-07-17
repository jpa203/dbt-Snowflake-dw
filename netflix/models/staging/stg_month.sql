{{ config(materialized='table')}}

create or replace TABLE NETFLIX.NETFLIX_SCHEMA_STG_TABLES.STG_MONTH (
	YEAR NUMBER(38,0),
	MONTH VARCHAR(20),
	MONTHID NUMBER(38,0) NOT NULL,
	primary key (MONTHID)
)