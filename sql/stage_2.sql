-- Define the state codes we want to filter

LOAD sqlite;
ATTACH IF NOT EXISTS './data/FS_FIADB.db' (type sqlite); 
USE FS_FIADB;

COPY (


WITH vol AS (
    SELECT
        STATECD,
        CAST(SUBSTR(CAST((PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD * 0.1) * 10 AS BIGINT), 1, 5) AS INTEGER) AS co_fips,
        SUBSTR(CAST((PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD * 0.1) * 10 AS BIGINT)::VARCHAR, -1) AS surveyunit,
        'Volume' AS response,
        VOLCFGRS * 0.0283168 / 1e6 AS value,  -- convert ft³ → million m³
        var_of_estimate * POWER(0.0283168 / 1e6, 2) AS var, -- convert variance accordingly
        YEAR
    FROM read_csv('./data/stage0/output2.csv')  -- or read_csv_auto(...)
    WHERE STATECD IN (37, 47, 51)
),
bio AS (
    SELECT
        STATECD,
        CAST(SUBSTR(CAST((PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD * 0.1) * 10 AS BIGINT), 1, 5) AS INTEGER) AS co_fips,
        SUBSTR(CAST((PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD * 0.1) * 10 AS BIGINT)::VARCHAR, -1) AS surveyunit,
        'Biomass' AS response,
        DRYBIO_AG * 0.453592 / 1e6 AS value,  -- convert lb → million kg
        var_of_estimate * POWER(0.453592 / 1e6, 2) AS var, -- convert variance accordingly
        YEAR
    FROM read_parquet('./data/stage0/output1.csv')  -- or read_csv_auto(...)
    WHERE STATECD IN (37, 47, 51)
),
combined AS (
    SELECT * FROM vol
    UNION ALL
    SELECT * FROM bio
),
mountain_ref AS (
    SELECT *
    FROM read_csv_auto('./data/FIADB/mountain_ref.csv', columns = {'STATECD':'VARCHAR','surveyunit':'VARCHAR','mountain_code':'INTEGER'})
)
SELECT
    c.STATECD,
    c.co_fips,
    c.surveyunit,
    c.response,
    c.value,
    c.var,
    c.YEAR,
    m.mountain_code
FROM combined c
LEFT JOIN mountain_ref m
    ON c.STATECD = m.STATECD
   AND c.surveyunit = m.surveyunit
ORDER BY c.STATECD, c.co_fips, c.surveyunit, c.response

) TO "./output_stage2.csv" (HEADER);