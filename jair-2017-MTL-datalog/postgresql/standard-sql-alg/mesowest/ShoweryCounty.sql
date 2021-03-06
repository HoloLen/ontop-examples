CREATE TEMPORARY TABLE C4_RAIN AS
WITH RAIN AS ( 
SELECT SID, dFrom, dTo
FROM ( 
SELECT date_time AS dTo, precip_accum_one_hour_set_1 AS currP1,
lag(date_time, 1) OVER (PARTITION BY station_id ORDER BY date_time) AS dFrom,
lag(precip_accum_one_hour_set_1) OVER (PARTITION BY station_id ORDER BY date_time) AS prevP1,
station_id AS SID, air_temp_set_1,
ROW_NUMBER() OVER(PARTITION BY station_id ORDER BY date_time) AS rnm  
FROM tb_newyorkdata2005) as sub 
WHERE ((currP1 > prevP1) OR ((currP1 < prevP1) AND (prevP1 > 0))) AND air_temp_set_1 > 5 AND rnm > 1 AND dTo - dFrom <= interval '1 day'), 

C1_RAIN (Start_ts, End_ts, ts, SID) AS (
SELECT 1, 0 , dFrom, SID
FROM RAIN 
UNION ALL
SELECT 0, 1, dTo, SID
FROM RAIN  
),

C2_RAIN AS (
SELECT 
SUM(Start_ts) OVER (PARTITION BY SID ORDER BY ts, End_ts ROWS UNBOUNDED PRECEDING) AS Crt_Total_ts_1,
SUM(End_ts) OVER (PARTITION BY SID ORDER BY ts, End_ts ROWS UNBOUNDED PRECEDING) AS Crt_Total_ts_2,
SUM(Start_ts) OVER (PARTITION BY SID ORDER BY ts, End_ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS Prv_Total_ts_1,
SUM(End_ts) OVER (PARTITION BY SID ORDER BY ts, End_ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS Prv_Total_ts_2,
ts,
SID
FROM C1_RAIN
),

C3_RAIN AS (
SELECT (Crt_Total_ts_1 - Crt_Total_ts_2) AS Crt_Total_ts, (Prv_Total_ts_1 - Prv_Total_ts_2) AS Prv_Total_ts, ts, SID 
FROM C2_RAIN
WHERE (Crt_Total_ts_1 - Crt_Total_ts_2) = 0 OR (Prv_Total_ts_1 - Prv_Total_ts_2) = 0 OR (Prv_Total_ts_1 - Prv_Total_ts_2) IS NULL
)

SELECT SID, prevTs AS dFrom, ts AS dTo FROM (
SELECT SID, LAG(ts,1) OVER (PARTITION BY SID ORDER BY ts, crt_total_ts) As prevTs,
ts,
Crt_Total_ts
FROM C3_RAIN) F 
WHERE Crt_Total_ts = 0;


CREATE TEMPORARY TABLE DIAMONDRAIN AS 
SELECT SID, dFrom, (dTo + interval '30 minutes') AS dTo 
FROM C4_RAIN; 

CREATE TEMPORARY TABLE C4_DRY AS
WITH DRY AS ( 
SELECT SID, dFrom, dTo
FROM ( 
SELECT date_time AS dTo, precip_accum_one_hour_set_1 AS currP1, 
lag(date_time, 1) OVER (PARTITION BY station_id ORDER BY date_time) AS dFrom,
lag(precip_accum_one_hour_set_1) OVER (PARTITION BY station_id ORDER BY date_time) AS prevP1,
station_id AS SID, air_temp_set_1,
ROW_NUMBER() OVER(PARTITION BY station_id ORDER BY date_time) AS rnm  
FROM tb_newyorkdata2005) as sub 
WHERE ((currP1 = prevP1) OR (currP1 = 0)) AND rnm > 1 AND dTo - dFrom <= interval '1 day'), 

C1_DRY (Start_ts, End_ts, ts, SID) AS (
SELECT 1, 0 , dFrom, SID
FROM DRY 
UNION ALL
SELECT 0, 1, dTo, SID
FROM DRY  
),

C2_DRY AS (
SELECT 
SUM(Start_ts) OVER (PARTITION BY SID ORDER BY ts, End_ts ROWS UNBOUNDED PRECEDING) AS Crt_Total_ts_1,
SUM(End_ts) OVER (PARTITION BY SID ORDER BY ts, End_ts ROWS UNBOUNDED PRECEDING) AS Crt_Total_ts_2,
SUM(Start_ts) OVER (PARTITION BY SID ORDER BY ts, End_ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS Prv_Total_ts_1,
SUM(End_ts) OVER (PARTITION BY SID ORDER BY ts, End_ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS Prv_Total_ts_2,
ts,
SID
FROM C1_DRY
),

C3_DRY AS (
SELECT (Crt_Total_ts_1 - Crt_Total_ts_2) AS Crt_Total_ts, (Prv_Total_ts_1 - Prv_Total_ts_2) AS Prv_Total_ts, ts, SID 
FROM C2_DRY
WHERE (Crt_Total_ts_1 - Crt_Total_ts_2) = 0 OR (Prv_Total_ts_1 - Prv_Total_ts_2) = 0 OR (Prv_Total_ts_1 - Prv_Total_ts_2) IS NULL
)

SELECT SID, prevTs AS dFrom, ts AS dTo FROM (
SELECT SID, LAG(ts,1) OVER (PARTITION BY SID ORDER BY ts, crt_total_ts) As prevTs,
ts,
Crt_Total_ts
FROM C3_DRY) F 
WHERE Crt_Total_ts = 0;

CREATE INDEX DIAMONDRAIN_IDX_FROM_TO ON DIAMONDRAIN (dFrom,dTo);
CREATE INDEX DRY_IDX_FROM_TO ON C4_DRY (dFrom,dTo);

CREATE TEMPORARY TABLE LOCATIONOFRAD AS
WITH DIAMONDRAINANDDRY AS (
SELECT DIAMONDRAIN.SID AS SID,
CASE 
WHEN DIAMONDRAIN.dFrom > C4_DRY.dFrom AND C4_DRY.dTo > DIAMONDRAIN.dFrom THEN DIAMONDRAIN.dFrom
WHEN C4_DRY.dFrom > DIAMONDRAIN.dFrom AND DIAMONDRAIN.dTo > C4_DRY.dFrom THEN C4_DRY.dFrom
WHEN DIAMONDRAIN.dFrom = C4_DRY.dFrom THEN DIAMONDRAIN.dFrom
END AS dFrom,
CASE 
WHEN DIAMONDRAIN.dTo < C4_DRY.dTo AND DIAMONDRAIN.dTo > C4_DRY.dFrom THEN DIAMONDRAIN.dTo
WHEN C4_DRY.dTo < DIAMONDRAIN.dTo AND C4_DRY.dTo > DIAMONDRAIN.dFrom THEN C4_DRY.dTo
WHEN DIAMONDRAIN.dTo = C4_DRY.dTo THEN DIAMONDRAIN.dTo
END AS dTo
FROM DIAMONDRAIN, C4_DRY
WHERE DIAMONDRAIN.SID = C4_DRY.SID AND 
((DIAMONDRAIN.dFrom > C4_DRY.dFrom AND C4_DRY.dTo > DIAMONDRAIN.dFrom) OR (C4_DRY.dFrom > DIAMONDRAIN.dFrom AND DIAMONDRAIN.dTo > C4_DRY.dFrom) OR (DIAMONDRAIN.dFrom = C4_DRY.dFrom)) AND
((DIAMONDRAIN.dTo < C4_DRY.dTo AND DIAMONDRAIN.dTo > C4_DRY.dFrom) OR (C4_DRY.dTo < DIAMONDRAIN.dTo AND C4_DRY.dTo > DIAMONDRAIN.dFrom) OR (DIAMONDRAIN.dTo = C4_DRY.dTo))	
),

L1_DIAMONDRAINANDDRY AS (
SELECT county AS dLocation, dFrom, dTo FROM DIAMONDRAINANDDRY, tb_metadata WHERE SID = stid
),

L2_DIAMONDRAINANDDRY (Start_ts, End_ts, ts, dLocation) AS (
SELECT 1, 0 , dFrom, dLocation
FROM L1_DIAMONDRAINANDDRY 
UNION ALL
SELECT 0, 1, dTo, dLocation
FROM L1_DIAMONDRAINANDDRY  
),

L3_DIAMONDRAINANDDRY AS (
SELECT 
SUM(Start_ts) OVER (PARTITION BY dLocation ORDER BY ts, End_ts ROWS UNBOUNDED PRECEDING) AS Crt_Total_ts_1,
SUM(End_ts) OVER (PARTITION BY dLocation ORDER BY ts, End_ts ROWS UNBOUNDED PRECEDING) AS Crt_Total_ts_2,
SUM(Start_ts) OVER (PARTITION BY dLocation ORDER BY ts, End_ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS Prv_Total_ts_1,
SUM(End_ts) OVER (PARTITION BY dLocation ORDER BY ts, End_ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS Prv_Total_ts_2,
ts,
dLocation
FROM L2_DIAMONDRAINANDDRY
),

L4_DIAMONDRAINANDDRY AS (
SELECT (Crt_Total_ts_1 - Crt_Total_ts_2) AS Crt_Total_ts, (Prv_Total_ts_1 - Prv_Total_ts_2) AS Prv_Total_ts, ts, dLocation 
FROM L3_DIAMONDRAINANDDRY
WHERE (Crt_Total_ts_1 - Crt_Total_ts_2) = 0 OR (Prv_Total_ts_1 - Prv_Total_ts_2) = 0 OR (Prv_Total_ts_1 - Prv_Total_ts_2) IS NULL
)

SELECT dLocation, prevTs AS dFrom, ts AS dTo FROM (
SELECT dLocation, LAG(ts,1) OVER (PARTITION BY dLocation ORDER BY ts, crt_total_ts) As prevTs,
ts,
Crt_Total_ts
FROM L4_DIAMONDRAINANDDRY) F 
WHERE Crt_Total_ts = 0;


CREATE TEMPORARY TABLE LOCATIONOFRAIN AS
WITH L1_LOCATIONOFRAIN AS (
SELECT county AS cLocation, dFrom, dTo FROM C4_RAIN, tb_metadata WHERE SID = stid
),

L2_LOCATIONOFRAIN (Start_ts, End_ts, ts, cLocation) AS (
SELECT 1, 0 , dFrom, cLocation
FROM L1_LOCATIONOFRAIN 
UNION ALL
SELECT 0, 1, dTo, cLocation
FROM L1_LOCATIONOFRAIN  
),

L3_LOCATIONOFRAIN AS (
SELECT 
SUM(Start_ts) OVER (PARTITION BY cLocation ORDER BY ts, End_ts ROWS UNBOUNDED PRECEDING) AS Crt_Total_ts_1,
SUM(End_ts) OVER (PARTITION BY cLocation ORDER BY ts, End_ts ROWS UNBOUNDED PRECEDING) AS Crt_Total_ts_2,
SUM(Start_ts) OVER (PARTITION BY cLocation ORDER BY ts, End_ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS Prv_Total_ts_1,
SUM(End_ts) OVER (PARTITION BY cLocation ORDER BY ts, End_ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS Prv_Total_ts_2,
ts,
cLocation
FROM L2_LOCATIONOFRAIN
),

L4_LOCATIONOFRAIN AS (
SELECT (Crt_Total_ts_1 - Crt_Total_ts_2) AS Crt_Total_ts, (Prv_Total_ts_1 - Prv_Total_ts_2) AS Prv_Total_ts, ts, cLocation
FROM L3_LOCATIONOFRAIN
WHERE (Crt_Total_ts_1 - Crt_Total_ts_2) = 0 OR (Prv_Total_ts_1 - Prv_Total_ts_2) = 0 OR (Prv_Total_ts_1 - Prv_Total_ts_2) IS NULL
)

SELECT cLocation, prevTs AS dFrom, ts AS dTo FROM (
SELECT cLocation, LAG(ts,1) OVER (PARTITION BY cLocation ORDER BY ts, crt_total_ts) As prevTs,
ts,
Crt_Total_ts
FROM L4_LOCATIONOFRAIN) F 
WHERE Crt_Total_ts = 0;

CREATE INDEX LOCATIONOFRAIN_IDX_FROM_TO ON LOCATIONOFRAIN (dFrom,dTo);
CREATE INDEX LOCATIONOFRAD_IDX_FROM_TO ON LOCATIONOFRAD (dFrom,dTo);

SELECT LOCATIONOFRAIN.cLocation AS county,
CASE 
WHEN LOCATIONOFRAIN.dFrom > LOCATIONOFRAD.dFrom AND LOCATIONOFRAD.dTo > LOCATIONOFRAIN.dFrom THEN LOCATIONOFRAIN.dFrom
WHEN LOCATIONOFRAD.dFrom > LOCATIONOFRAIN.dFrom AND LOCATIONOFRAIN.dTo > LOCATIONOFRAD.dFrom THEN LOCATIONOFRAD.dFrom
WHEN LOCATIONOFRAIN.dFrom = LOCATIONOFRAD.dFrom THEN LOCATIONOFRAIN.dFrom
END AS dFrom,
CASE 
WHEN LOCATIONOFRAIN.dTo < LOCATIONOFRAD.dTo AND LOCATIONOFRAIN.dTo > LOCATIONOFRAD.dFrom THEN LOCATIONOFRAIN.dTo
WHEN LOCATIONOFRAD.dTo < LOCATIONOFRAIN.dTo AND LOCATIONOFRAD.dTo > LOCATIONOFRAIN.dFrom THEN LOCATIONOFRAD.dTo
WHEN LOCATIONOFRAIN.dTo = LOCATIONOFRAD.dTo THEN LOCATIONOFRAIN.dTo
END AS dTo
FROM LOCATIONOFRAIN, LOCATIONOFRAD
WHERE LOCATIONOFRAIN.cLocation = LOCATIONOFRAD.dLocation AND
((LOCATIONOFRAIN.dFrom > LOCATIONOFRAD.dFrom AND LOCATIONOFRAD.dTo > LOCATIONOFRAIN.dFrom) OR (LOCATIONOFRAD.dFrom > LOCATIONOFRAIN.dFrom AND LOCATIONOFRAIN.dTo > LOCATIONOFRAD.dFrom) OR (LOCATIONOFRAIN.dFrom = LOCATIONOFRAD.dFrom)) AND
((LOCATIONOFRAIN.dTo < LOCATIONOFRAD.dTo AND LOCATIONOFRAIN.dTo > LOCATIONOFRAD.dFrom) OR (LOCATIONOFRAD.dTo < LOCATIONOFRAIN.dTo AND LOCATIONOFRAD.dTo > LOCATIONOFRAIN.dFrom) OR (LOCATIONOFRAIN.dTo = LOCATIONOFRAD.dTo));
