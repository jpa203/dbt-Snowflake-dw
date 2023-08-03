from airflow import DAG
from datetime import datetime, timedelta
from airflow.operators.bash_operator import BashOperator
from airflow.utils.dates import days_ago

PATH_TO_DBT_PROJECT = "/Users/jazzopardi/dev/snowflake-dw/netflix"
PATH_TO_DBT_VENV = "/Users/jazzopardi/dev/dw/bin/activate"


default_args = {
    'owner': 'jazzopardi',
    'depends_on_past': False,
    'start_date': datetime(2023, 7, 31),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(seconds=5),
}

# Define the DAG objects
dag = DAG(
    'elt_dag',
    description = 'Test DAG',
    default_args=default_args,
    schedule_interval=timedelta(days=1),
    catchup=False
)

# Define tasks for each DAG
task_staging_dbt = BashOperator(
    task_id='staging',
    bash_command="source $PATH_TO_DBT_VENV && dbt run --select staging --exclude staging.stg_month+",
    env={"PATH_TO_DBT_VENV": PATH_TO_DBT_VENV},
    cwd=PATH_TO_DBT_PROJECT,
    dag=dag
)

task_dim_dbt = BashOperator(
    task_id='dimensions',
    bash_command="source $PATH_TO_DBT_VENV && dbt run --select dim",
    env={"PATH_TO_DBT_VENV": PATH_TO_DBT_VENV},
    cwd=PATH_TO_DBT_PROJECT,
    dag=dag
)

task_fact_dbt = BashOperator(
    task_id='facts',
    bash_command="source $PATH_TO_DBT_VENV && dbt run --select facts",
    env={"PATH_TO_DBT_VENV": PATH_TO_DBT_VENV},
    cwd=PATH_TO_DBT_PROJECT,
    dag=dag
)

task_staging_dbt >> task_dim_dbt
task_staging_dbt >> task_fact_dbt
