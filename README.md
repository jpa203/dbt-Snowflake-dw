# Redshift-DBT-Airflow

Cloud Datawarehouse Solution

- Postgres to RDS
- RDS to S3 (DMS)

- DBT
- Airflow (Orchestration)
- ELT
- Testing
- Data Validation (Slack automation)
- Security
- Analytics
- Visualization

## Use-Case

We work for Streamberry, a fictious video streaming platform. The company has been relying mainly on an on-premise database since 2018 but its growth in popularity means it wants to scale operations to include cloud-based solutions.

Currently, Streamberry is unable to handle the volume and velocity of streaming services. Thus, day-to-day operations have been hindered by a lack of scability and perfomance issues.

As it moves towards cloud-first infrastructure, Streamberry has asked its data team to incorporate a data warehouse as part of its migration, and in order to help leverage insights and analytics moving forward.

Streamberry has decided to migrates its existing OLTP database system to Amazon Web Services where it will leverage fault-tolerance frameworks and high availability multi-AZ deployment. For its data warehosue solution, the company has decided to use Snowflake.

The data engineering team decided that it will build its data warehouse using Kimball's Dimensional Modelling - a bottom up approach that prioritizes low initial investment through data marts and self service reporting (through easy integration with BI tools). Stakeholders agreed this was the most effective approach for a greenfield project.

## Requirements Gathering

    * Customer Overview
        Streamberry wants to understand its customer base better i.e. how long they rent dvds for, popular payment types, total spending etc. 

        Key Questions:
            - How much does a customer spend on average per month?
            - What's the most popular membership?

    * Product Inventory
        Streamberry offers streaming and physical dvd copies. The company wants to keep track of its physical inventory, including how many dvds have been lost - in an effor to see whether offering physical dvds is still profitable moving forward.

        Key Questions:
            - How many DVDs are lost per month?
            - Do we stock more DVDS than we need to?
    
    * DVD Tracking
        Track DVD information, such as ratings, actors, genres - to help understand the market and which movies and actors are most popular currently. 
            - Which actor is most popular right now?
            - Which genre is most popular?
            - What is the most popular rating for rented dvds?

## Data Profiling

The data has been migrated from on-premise to AWS RDS, where it was then moved to staging tables in Snowflake.

A number of high cardinaity attributes have been identified, including dvd (~4000) and member (~1000).

Our ERD shows that there are several bridge tables, where we can expect the tables to grow even bigger, including Rental and RentalQueue. It is also worth noting the relationships in both tables differ - RentalQueue has a strong relationship with DVD and Member but is a weak entity. This means a record can only exist if a memberid and dvdid is present.

Rental is a strong entity - though it is connected to MemberID and DVDID via foreign keys, its primary key is a synthetic key called RentalID.

We can also expect Payments to grow - as each member can/will have multiple payments.

We know, as data engineers at Streamberry, that the data is highly normalized and therefore we shouldn't expect much (if any) redundancy. 

## High Level Entities

After data profiling, a meeting was held with Streamberry to validate our process and discuss some discrepencies and how to handle them moving forward.

A conclusion was reached to proceed as intended, the business and data engineers agreed on high level entities that will be reflected in the data warehouse:

- DVDs

- Members

- Rentals

- Payment

- Location

- Date

A date dim doesn't exist in our schema but is a must for a dimensional data warehouse.

## Bus Matrix

A bus matrix is a visual representation or framework used for organizing and understanding the relationships between business processes, data sources and data dimensions.

It provides a structured view of the business processes and the corresponding dimensions that are relevant to the organization.

Business Processes: High-level activities or functions performed within the organization (sales, marketing, finance, hr etc.)

Data Dimensions: Attribures that describe the data related to the business processes.

Bus Matrix helps identify which data dimensions are relevant to each business process and vice versa.

/Users/jazzopardi/dev/datawarehouse/BusMatrix.png

## Source To Target Mapping

After exploring and validating the data, it is time to map our staging tables to our dimension and fact tables. Several transformations will be carried out in this intermediary step, to shape our data so that it conforms to the business requirements defined above.

In addition to data transformation, we will also introduce our data dimension here.

Depending on the scenario and data architecture layers, source-to-target mapping may be carried out for every stage i.e. from source to data lake, from data lake to staging, from staging to data mart/warehouse and then from data warehouse to one big table.

However, since we know that the data was kept in a highly normalized OLTP database, we have a 99% guarantee of data integrity and much of this stage would consist of a 1:1 mapping.

This changes when we consider the level of grain and subsequent aggregations that must take place to transform our data from an OLTP system to a datawarehouse OLAP system with facts and dims.

## Dimensional Modeling

This is where the model comes in, with explanations.

## Understanding DBT

- macros are like functions (dry sql code - "don't repeat yourself")
    - jinja - templating language - can make your code more dynamic - can write for loops in sql code {% for x in y %} {% endfor %}

    - can create a macro once with a template and use it across your dbt project '

- models - where sql files are stored - where the transformations happen.

- snapshots - type 2 scds get saved here
- test (assertions for testing )



# Notes

So we create our models in the models file and then define sql statemnts to trasnform our data - in this case, we just moved member table from public
to the warehouse stage (but we will need to perform transformations so wait till next video)

 you define a 'source.yml' file which is where the source data is coming from - in this case we defined it as the public schema and listed all table names
  we then used jinja language to extract all data and put it in a new table - again we need to change this to be able to perform some transformations as well. 

  dbt compile && dbt run 



  -- we create our staging tables, where we do some data transformation, cleansing etc:
    - stg_member:

            -- added two columns, ingestion_timestamp and current_flag to represent SCD2 - using incremental  (do I need this for future data?)
            -- also added initials for members

doing data transformations in dbt to get it ready for dimensioanl modelling 



## Fact Tables

fact_inventory

- An ingestion timestamp was added to the dvd column - in this scenario, the business takes a snapshot of the dvd table at the end of each day - using a stored procedure - and stores it in a historical dvd table. This allows our data warehouse to join on the dvd table and capture the last timestamp for a given month, so that we can join it on our fact table


So for fact_inventory, we take a snapshot of the inventory at the end of every month, calculating how much of each dvd was on shelf compared to rented. 
We do this by extracting the last timestamp from the dvd history table and then joining it onto our month table, where it sits at the month level. 

At the end of each day, the dw copies data from the OLTP database and produces a timestamp with the DVD column
This timestamp is then used to calculate end-of-month aggregates for ddvd inventory, including how much dvd is in stock each month - it joins to a dim_months table
to allow for better analysis moving forward, so analysts can compare how many dvds are in stock, on rent, lost etc. on a month to month basis. 

We implmement a SC2 for the members dimension - by creating a downstream pipeline where we detect any changes
from the source data in based on a 'check' test (defining what columns we want to check) and then log these changes in our staging table, where a CASE statement was used to create a new 'current_flag' column with values 'Y' or 'N'  to indicate whether the row is the most recent or not.

This way, we are able to keep track of a member's history in case they change their name, address, phone number, email etc.

{show example}

