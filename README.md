# ICT371 Advanced Database - Question 9: Farmer Cooperative Maize Deliveries

Student: Patience Shaba (202409214)

Single script `q9_maize.sql` covering parts (a) to (g): tables and seed data, function, procedure, trigger, view, index with EXPLAIN, and a pg_cron scheduled job. Everything is created in its own schema `q9`, so it will not clash with the other questions.

## Run it (PostgreSQL 14+ with the pg_cron extension)
```
psql -d YOUR_DATABASE -f q9_maize.sql
```
Run it in the database that has pg_cron enabled (`cron.database_name` in postgresql.conf). The script can be re-run: it drops and recreates schema `q9` each time.

Test queries and expected rejections are shown as query results and NOTICE messages inside the script.
