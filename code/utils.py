import pandas as pd
import sqlite3


def upload_table(table_name: str):
    sqlite_file = '/Users/jazzopardi/dev/datawarehouse/raw_data/database.sqlite'
    conn = sqlite3.connect(sqlite_file)
    df = pd.read_sql_query(f"SELECT * FROM {table_name}", conn)
    dest = f'/Users/jazzopardi/dev/datawarehouse/raw_data/{table_name}.csv'
    df.to_csv(dest, index=False)
    conn.close()
    return dest

