## Introduction

This project is an exercise in creating a cloud data warehouse solution using AWS, Snowflake, dbt and Apache Airflow. The solutions presented below mimick a real-life scenario where a growing company wants to move from on-premise solutions to the cloud, in anticipation of business growth and to introduce practices for long-term cost cutting measures.

## Project Outline

We work for Streamberry, a fictious video streaming platform. The company has used an on-premise database since 2018 but its growth in popularity means it wants to scale operations to include cloud-based solutions.

Currently, Streamberry is unable to handle the volume and velocity of streaming services. Thus, day-to-day operations, including business intelligence, have been hindered by a lack of scalability and performance issues.

As it moves towards cloud-first infrastructure, Streamberry has asked its data team to incorporate a data warehouse as part of its migration. It hopes to lessen the burden on its production environment while simultaneously leveraging insights and analytics moving forward.

Streamberry has decided to migrates its existing OLTP database system to Amazon Web Services Relational Database Services (RDS) where it will leverage fault-tolerance frameworks and high availability multi-AZ deployment. For its data warehouse solution, the company will use Snowflake.

The data engineering team will model the data warehouse using Kimball's Dimensional Modeling - a bottom-up approach that prioritizes low initial investment through data marts and self-service reporting (through easy integration with BI tools). Stakeholders agreed this was the most effective approach for a greenfield project.

![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/0a30635d-34aa-4dd5-8cb3-f08d8e07c8b6)


## Requirements Gathering

    * Customer Overview
        Streamberry wants to understand its customer base better by analzying their value over the time they have been members, and potentially offer discounts to those who ask for it. 

        Key Questions:
            - Who are our most valued customers?
            - Which state is most popular? 
            - What discounts on future membership can we offer them?

    * Product Inventory
        Streamberry offers streaming and physical dvd copies. The company wants to keep track of its physical inventory, including how many physical copies of dvd remain on shelf at the end of each month, to assess whether it is over/under stocking. 

        Key Questions:
            - How many DVDs are lost per month?
            - Do we stock more DVDS than we need to?
    
    * Ratings Tracking
        Streamberry wants to know which genres are most popular with customers so that it can tailor recommendations accordingly. 

        Key Questions:
            - What is the average rating per genre per customer?

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

- Payment

- Location

- Date

A date dimension doesn't exist in our schema but is a must for a dimensional data warehouse.

## Bus Matrix

![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/6dffa2c4-e010-4300-b4fc-e9b1d1292400)


A bus matrix is a visual representation or framework used for organizing and understanding the relationships between business processes, data sources and data dimensions.

It provides a structured view of the business processes and the corresponding dimensions that are relevant to the organization.

Business Processes: High-level activities or functions performed within the organization (sales, marketing, finance, hr etc.)

Data Dimensions: Attribures that describe the data related to the business processes.

Bus Matrix helps identify which dimensions are relevant to each business process and vice versa.

## Source To Target Mapping

After exploring and validating the data, it is time to map our staging tables to our dimension and fact tables. Several transformations will be carried out in this intermediary step, to shape our data so that it conforms to the business requirements defined above.

In addition to data transformation, we will also introduce our date dimension here.

Depending on the scenario and data architecture, source-to-target mapping may be carried out for every stage i.e. from source to data lake, from data lake to staging, from staging to data mart/warehouse and then from data warehouse to one big table.

However, since we know that the data was kept in a highly normalized OLTP database, we have a high guarantee of data integrity and much of this stage would consist of a 1:1 mapping.

This changes when we consider the level of grain and subsequent aggregations that must take place to transform our data from an OLTP system to a datawarehouse OLAP system with facts and dims.

## Dimensional Modeling

 ![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/69773bba-9653-4cb8-8ab6-2a20d38b6372)

We have created our physical ERD which will help provide visual guidance throughout this process. In addition to the fact and dim tables defined above, two date dimensions have been added to the mix - dim_date and dim_month - to reflect the different levels of grain in our model.

We have also highlighted Slowly Changing Dimensions(SCDs) that will need to be taken into consideration when building our data warehouse - primarily SCD2, which presevers history by creating multiple records for a given natural key using a surrogate key or different version numbers.

This is evident in the dim_members table in our ER diagram. How will we track a customer's change in address, last name or phone number to ensure their value is retained and discounts are applied accordingly?

## Understanding dbt

This project is an exercise in understanding and utilizing dbt.

dbt will be used to transform our tables from our source into the Streamberry data warehouse, using sql files defined in the "models" directory to create repeatable templates for future use.

Jinja, dbt's native templating language, let's us define logic and macros in a hybrid manner between Python and SQL. Jinja is simple and easy to use, and, with a few lines of code, allows the user to create dynamic templates that can be customized to fit specific needs.

This project will also capture SCD2s using the 'snapshots' directory and configurations with specific check columns for the values of most interest to us.

i.e.

![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/da8e74d2-0eb9-4256-b99d-daf1cdaf19db)


check_cols = ['memberlastname', 'memberinitial', 'memberaddres', 'memberphone', 'memberemail']

In this case, unlike our other dim tables, the dim_members table will pull data from the snapshots table, as opposed to the staging tables, to preserve the SCD2 state.

Testing in dbt will also be conducted to ensure the validity of our data.

## Fact Tables

- fact_inventory
  
 ![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/8bd263d4-7bfe-4fdf-990e-f16672b8e07a)

An ingestion timestamp was added to the dvd column - in this scenario, the business takes a snapshot of the dvd table at the end of each day - using a stored procedure - and stores it in a historical dvd table. This allows our data warehouse to join on the dvd table and capture the last timestamp for a given month, giving us end of month totals, including how many copies of a dvd is in stock.

- fact_member

![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/600a2285-6542-4687-8467-d44b3ee2823c)


This fact table is at a transaction level and calculates a member's total value by finding the product of daily membership cost and  total days as a member. Based on a hierarchy established by the business, a discount coupon will be applied to membership fees ranging from 25% to 0%. As a member's total value increases, they will become eligible for more discounts, if they ask for one.

In order to keep track of a member's value, an SCD2 was implemented for dim_members - by creating a downstream pipeline where changes in the source data are detected based on a test. Those changes are logged in the staging table, where a CASE statement was used to create a new 'current_flag' column with values 'Y' or 'N'  to indicate whether the row is the most recent or not.

This way, we are able to keep track of a member's history in case they change their name, address, phone number, email etc.

- fact_review

 ![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/b944d08d-e11b-48e1-b435-3d000df87bf8)

This fact table represents a monthly snapshot of a user's average rating based on the genre. The business will use this fact table to tailor marketing campaigns to recommend dvds that fit the user's preferences based on their most preferred genre according to the ratings given.

The fact_review table sits at the month grain, meaning it takes an average of the ratings of all dvds rented out by a member, provided they leave a rating.

The source data does not have a natural primary key. To overcome this, in the staging layer, the dbt_utils package was used to generate a surrogate key for each record entering the data warehouse. This allowed us to join the fact_table back to the month dimension and define our grain as intended.

This involved the creation of a 'packages.yml' file where the 'dbt-labs/dbt_utils' package was defined befure running dbt deps.

## Testing / Unit Testing

As good practice, before and during deployment, it is important to conduct tests using assertitions to ensure the validity of the data
pipeline from source to destination.

dbt provides a robust framework to conduct both singular and generic tests, with a high level of customization to meet specific use cases.

To highlight as such, several generic tests were added to the Streamberry data warehouse, including some which are customized, as well as singluar tests to demonstrate the capability of dbt to conduct unit tests too.

![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/e0e426fe-e207-4fbd-9b0e-2b3a1e9e1378)

In the above screenshot, we run a simple generic test deliberately aimed to fail by accepting only 'test' as a value in the dvdtitle column in dvds. A good use case for this would be an attribute that has low cardinality.

We can apply any of the four test logics - not_null, unique, relationship and accepted values to our models, in addition to customizable tests provided by packages or self-made.

## Documentation

At this stage, our data warehosue has been built and we've implemented testing to ensure the validity of our data.

Best practice suggests that we provide documentation of our data warehouse, and we can achieve this by running a dbt command known as - dbt docs generate - which will compile our yml files into one json file to serve up as a website.

We can now call dbt docs serve to view our documentation on our local machine.

![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/9f56891b-681c-48bd-a018-7cc907a93dd3)


## Orchestration - Airflow

The architectue for Streamberry's data warehouse has been built. The company is ready to deploy it and hopes to gather useful insights over the years about its customers, dvd and consumer habits.

For the sake of automation and to presever low overhead, before deploying the data warehouse, the data engineering team wants to experiment with an orchestration tool. Apache Airflow will be used, backed by an SQLite database for dev/testing purposes. For production, the team will changes databases to a Postgres instance set up on AWS.

Airflow provides many benefits to orchestration and integrates well with dbt. With it's data-aware scheduling, Airflow DAGs can be scheduled based on updates to our staging tables and call our models to begin the ELT process.

Airflow was deployed as a Python script where it runs the BashOperator to execute our dbt tasks. The DAG has been established in sequential order, whereby a 'dbt run' command is first executed before the same is done on our dim and fact tables - this helps ensure the integrity of our data.

Because Streamberry expects to grow at a rapid rate, it is important to consider how we can optimzie our data warehouse for better read/write performance. While compute and storage is both expandable and cheap with cloud solutions, Streamberry wants to introduce good practices for the longevity of its data platform.

For this, certain tables that are expected to grow/change frequently have been amended to materialize incrementally based on timestamps. This incremental load means the dbt run command won't take into considerations records that have already been ingested.

This is particularly the case for SCD 0s, such as dvd, where we just append records, and don't want to run transformations on the whole  table again.

 ![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/83511d62-c87b-4b37-8230-674953a6762b)


## Visualization

As a final step, the data engineering team created a pipeline from the data warehouse to a business intelligience tool known as Tableau, to demonstrate the insights of their work and highlight the benefit it provides for business and data anlaysts alike.

 ![image](https://github.com/jpa203/dbt-Snowflake-dw/assets/104007355/7b800a41-7ccd-41e6-a1d1-329111dcca71)

