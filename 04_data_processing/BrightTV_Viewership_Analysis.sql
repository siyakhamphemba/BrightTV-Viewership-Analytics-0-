-- Databricks notebook source
-- ============================================================
-- BRIGHTTV VIEWERSHIP ANALYSIS
-- Author: Siyakha Ntuli
-- Date: June 2026
-- Purpose: Analyse user profiles and viewership data to provide
--          insights on consumption trends and growth opportunities
-- ============================================================

-- ============================================================
-- SECTION 1: DATA EXPLORATION
-- Purpose: Understand the structure and content of raw tables
--          before any transformation or analysis
-- ============================================================

-- Inspect column names and data types for user profile table
DESCRIBE workspace.brightlearn.bright_tv_user_profile;

-- Inspect column names and data types for viewership table
DESCRIBE workspace.brightlearn.bright_tv_viewership;

-- Preview first 100 rows of user profiles to understand the data
-- Check for nulls, ghost profiles (no name), and age = 0

SELECT *
FROM workspace.brightlearn.bright_tv_user_profile
LIMIT 100;

-- Preview first 100 rows of viewership to understand session structure
-- Check date format, duration format and duplicate UserID column
SELECT *
FROM workspace.brightlearn.bright_tv_viewership
LIMIT 100;

-- ============================================================
-- SECTION 2: DATA VALIDATION
-- Purpose: Validate join keys, check row counts and explore
--          distinct values before building master dataset
-- ============================================================

-- Test JOIN between viewership (fact) and user profiles (dimension)
-- Using LEFT JOIN to preserve all viewing sessions including ghost profiles
-- Ghost profiles have viewing activity but incomplete demographic info
-- We soft exclude them from demographic analysis but retain their sessions
SELECT *
FROM workspace.brightlearn.bright_tv_viewership
LEFT JOIN workspace.brightlearn.bright_tv_user_profile
ON workspace.brightlearn.bright_tv_viewership.UserID = workspace.brightlearn.bright_tv_user_profile.UserID;

-- Validate total record count after JOIN
-- Expected: ~10,001 rows matching viewership table
-- Significant deviation would indicate a JOIN issue
SELECT COUNT(*) AS total_records
FROM workspace.brightlearn.bright_tv_viewership
LEFT JOIN workspace.brightlearn.bright_tv_user_profile
ON workspace.brightlearn.bright_tv_viewership.UserID = workspace.brightlearn.bright_tv_user_profile.UserID;

-- Explore distinct provinces to check for inconsistencies
-- Expected: 9 SA provinces + possible nulls/unknowns from ghost profiles
SELECT DISTINCT `province`
FROM workspace.brightlearn.bright_tv_viewership
LEFT JOIN workspace.brightlearn.bright_tv_user_profile
ON workspace.brightlearn.bright_tv_viewership.UserID = workspace.brightlearn.bright_tv_user_profile.UserID;

-- Explore distinct channels to understand content landscape
-- Used to determine if channel grouping using CASE is feasible
SELECT DISTINCT `channel2`
FROM workspace.brightlearn.bright_tv_viewership
LEFT JOIN workspace.brightlearn.bright_tv_user_profile
ON workspace.brightlearn.bright_tv_viewership.UserID = workspace.brightlearn.bright_tv_user_profile.UserID;

-- Test customer name concatenation before adding to master query
SELECT Name || ' ' || Surname AS customer_name
FROM workspace.brightlearn.bright_tv_viewership
LEFT JOIN workspace.brightlearn.bright_tv_user_profile
ON workspace.brightlearn.bright_tv_viewership.UserID = workspace.brightlearn.bright_tv_user_profile.UserID;

-- ============================================================
-- SECTION 3: MASTER CTE - bright_tv_master
-- Purpose: Create a single clean analytical foundation by:
--          1. Joining viewership (fact) with user profiles (dimension)
--          2. Converting UTC timestamps to SA time (UTC+2)
--          3. Extracting date dimensions for trend analysis
--          4. Converting duration from timestamp to minutes for aggregation
--          5. Standardising demographics using CASE statements
--          6. Flagging social media and email presence for targeting
--
-- Why a CTE and not direct queries on raw tables?
--          A CTE keeps raw data untouched and allows all cleaning
--          and transformation to happen in one reproducible place.
--          All analysis queries below reference this clean layer
--          ensuring consistency across every insight.
-- ============================================================

WITH bright_tv_master AS (
    SELECT 
        v.UserID,
        v.channel2,

        -- Convert recording time from UTC to South Africa Standard Time (UTC+2)
        -- SA does not observe daylight saving so +2 hours applies year round
        DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm')) AS sa_record_date,

        v.`Duration 2`,
        u.Age,
        u.Gender,
        u.Race,
        u.Province,
        u.`Social Media Handle`,
        u.Email,

        -- Combine first and last name into a single customer name field
        u.Name || ' ' || u.Surname AS customer_name,

        -- Extract individual date components from SA time for trend analysis
        DATE(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS date_only,
        MONTH(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS month,
        YEAR(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS year,
        DAY(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS day,

        -- Extract hour for peak viewing time analysis (0-23 format)
        HOUR(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS hour_of_day,

        -- Extract day of week for identifying low consumption days (1=Sunday, 7=Saturday)
        DAYOFWEEK(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS day_of_week,

        -- Convert duration from timestamp format to total minutes
        -- This enables SUM and AVG calculations for consumption analysis
        -- Sessions under 1 minute are retained here but can be filtered in analysis queries
        (HOUR(TO_TIMESTAMP(`Duration 2`)) * 60 + MINUTE(TO_TIMESTAMP(`Duration 2`))) AS duration_minutes,

        -- Flag whether subscriber has a social media handle
        -- Useful for targeting digital marketing campaigns
        CASE
            WHEN u.`Social Media Handle` = 'None' THEN 'No Social Media' 
            ELSE 'Has Social Media'
        END AS social_media_presence,

        -- Flag whether subscriber has a valid email address
        -- Useful for email marketing and re-engagement campaigns
        CASE 
            WHEN u.Email IS NULL OR u.Email = '' OR u.Email = 'None' THEN 'No Email'
            ELSE 'Has Email'
        END AS email_presence,

        -- Group ages into meaningful life stage segments for content targeting
        CASE 
            WHEN u.age BETWEEN 0 AND 12 THEN 'Kids'
            WHEN u.age BETWEEN 13 AND 17 THEN 'Teenagers'
            WHEN u.age BETWEEN 18 AND 29 THEN 'Youth'
            WHEN u.age BETWEEN 30 AND 59 THEN 'Adults'
            WHEN u.age >= 60 THEN 'Pensioners'
            ELSE 'Unknown Age'
        END AS age_group,

        -- Standardise gender values and flag unknowns (ghost profiles)
        CASE 
            WHEN u.gender = 'male' THEN 'Male'
            WHEN u.gender = 'female' THEN 'Female'
            ELSE 'Unknown Gender'
        END AS gender_cleaned,

        -- Standardise race values and flag unknowns
        CASE 
            WHEN u.race = 'white' THEN 'White'
            WHEN u.race = 'black' THEN 'Black'
            WHEN u.race = 'coloured' THEN 'Coloured'
            ELSE 'Unknown Race'
        END AS race_cleaned,

        -- Standardise province values and flag unknowns from ghost profiles
        CASE 
            WHEN u.province = 'None' OR u.province IS NULL THEN 'Unknown Province'
            ELSE u.province
        END AS province_cleaned,

        -- Map day of week number to actual day name
        CASE day_of_week
            WHEN 1 THEN 'Sunday'
            WHEN 2 THEN 'Monday'
            WHEN 3 THEN 'Tuesday'
            WHEN 4 THEN 'Wednesday'
            WHEN 5 THEN 'Thursday'
            WHEN 6 THEN 'Friday'
            WHEN 7 THEN 'Saturday'
        END AS day_name

    FROM workspace.brightlearn.bright_tv_viewership v
    LEFT JOIN workspace.brightlearn.bright_tv_user_profile u
    ON v.UserID = u.UserID
)

SELECT *
FROM bright_tv_master;

-- ============================================================
-- SECTION 3B: CREATE VIEW - bright_tv_master
-- Initially a CTE was used to build and test all transformations
-- However a CTE cannot be reused across multiple queries
-- After research a view was created as a permanent reusable layer
-- Any query in this notebook can now reference bright_tv_master
-- without repeating the JOIN and transformations every time
-- ============================================================

CREATE OR REPLACE VIEW bright_tv_master AS
SELECT 
    v.UserID,
    v.channel2,
    DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm')) AS sa_record_date,
    v.`Duration 2`,
    u.Age,
    u.Gender,
    u.Race,
    u.Province,
    u.`Social Media Handle`,
    u.Email,
    u.Name || ' ' || u.Surname AS customer_name,
    DATE(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS date_only,
    MONTH(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS month,
    YEAR(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS year,
    DAY(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS day,
    HOUR(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS hour_of_day,
    DAYOFWEEK(DATEADD(HOUR, 2, TO_TIMESTAMP(v.RecordDate2, 'M/d/yyyy H:mm'))) AS day_of_week,
    (HOUR(TO_TIMESTAMP(`Duration 2`)) * 60 + MINUTE(TO_TIMESTAMP(`Duration 2`))) AS duration_minutes,
    CASE
        WHEN u.`Social Media Handle` = 'None' THEN 'No Social Media' 
        ELSE 'Has Social Media'
    END AS social_media_presence,
    CASE 
        WHEN u.Email IS NULL OR u.Email = '' OR u.Email = 'None' THEN 'No Email'
        ELSE 'Has Email'
    END AS email_presence,
    CASE 
        WHEN u.age BETWEEN 0 AND 12 THEN 'Kids'
        WHEN u.age BETWEEN 13 AND 17 THEN 'Teenagers'
        WHEN u.age BETWEEN 18 AND 29 THEN 'Youth'
        WHEN u.age BETWEEN 30 AND 59 THEN 'Adults'
        WHEN u.age >= 60 THEN 'Pensioners'
        ELSE 'Unknown Age'
    END AS age_group,
    CASE 
        WHEN u.gender = 'male' THEN 'Male'
        WHEN u.gender = 'female' THEN 'Female'
        ELSE 'Unknown Gender'
    END AS gender_cleaned,
    CASE 
        WHEN u.race = 'white' THEN 'White'
        WHEN u.race = 'black' THEN 'Black'
        WHEN u.race = 'coloured' THEN 'Coloured'
        ELSE 'Unknown Race'
    END AS race_cleaned,
    CASE 
        WHEN u.province = 'None' OR u.province IS NULL THEN 'Unknown Province'
        ELSE u.province
    END AS province_cleaned,
      CASE day_of_week
            WHEN 1 THEN 'Sunday'
            WHEN 2 THEN 'Monday'
            WHEN 3 THEN 'Tuesday'
            WHEN 4 THEN 'Wednesday'
            WHEN 5 THEN 'Thursday'
            WHEN 6 THEN 'Friday'
            WHEN 7 THEN 'Saturday'
        END AS day_name
FROM workspace.brightlearn.bright_tv_viewership v
LEFT JOIN workspace.brightlearn.bright_tv_user_profile u
ON v.UserID = u.UserID;

SELECT *
FROM  bright_tv_master;

SELECT gender_cleaned, COUNT(DISTINCT UserID) AS unique_subscribers_by_gender
FROM bright_tv_master
GROUP BY gender_cleaned
ORDER BY unique_subscribers_by_gender DESC;

SELECT gender_cleaned,COUNT(*) AS sessions_by_gender
FROM bright_tv_master
GROUP BY gender_cleaned
ORDER BY sessions_by_gender DESC;

SELECT age_group,COUNT(DISTINCT UserID) AS unique_subscribers_by_age_group
FROM bright_tv_master
GROUP BY age_group
ORDER BY unique_subscribers_by_age_group DESC;

SELECT age_group,COUNT(*) AS sessions_by_age_group
FROM bright_tv_master
GROUP BY age_group
ORDER BY sessions_by_age_group DESC;

SELECT province_cleaned,COUNT(DISTINCT UserID) AS unique_subscribers_by_province
FROM bright_tv_master
GROUP BY province_cleaned
ORDER BY unique_subscribers_by_province DESC;

SELECT race_cleaned, COUNT(DISTINCT UserID) AS unique_subscribers_by_race
FROM bright_tv_master
GROUP BY race_cleaned
ORDER BY unique_subscribers_by_race DESC;


SELECT hour_of_day, SUM(duration_minutes)
FROM bright_tv_master
GROUP BY hour_of_day
ORDER BY hour_of_day ASC;


SELECT channel2,SUM(duration_minutes)
FROM bright_tv_master
GROUP BY channel2
ORDER BY SUM(duration_minutes) DESC;


SELECT day_of_week, COUNT(*),SUM(duration_minutes)
FROM  bright_tv_master
GROUP BY day_of_week
ORDER BY day_of_week ASC;



SELECT year,month,COUNT(*),SUM(duration_minutes)
FROM bright_tv_master
GROUP BY year,month
ORDER BY year,month ASC;


SELECT age_group,channel2,COUNT(*)
FROM bright_tv_master
GROUP BY age_group,channel2
ORDER BY age_group,COUNT(*) DESC;


SELECT gender_cleaned,channel2,COUNT(*)
FROM bright_tv_master
GROUP BY gender_cleaned,channel2
ORDER BY COUNT(*) ASC;


SELECT date_only,SUM(duration_minutes)
FROM bright_tv_master
GROUP BY date_only
ORDER BY SUM(duration_minutes) ASC
LIMIT 10;



SELECT province_cleaned,SUM(duration_minutes)
FROM bright_tv_master
WHERE  province_cleaned != 'Unknown Province'
GROUP BY province_cleaned;

-- ============================================================
-- SECTION 3C: CREATE VIEW - bright_tv_low_consumption
-- Purpose: Pre-aggregated bottom 10 lowest consumption days
-- Feeds directly into Lowest Consumption Days dashboard visual
-- ============================================================

CREATE OR REPLACE VIEW workspace.brightlearn.bright_tv_low_consumption AS
SELECT 
    date_only,
    DATE_FORMAT(date_only, 'dd MMM yyyy') AS consumption_date,
    DAYOFWEEK(date_only) AS day_number,
    SUM(duration_minutes) AS total_minutes
FROM bright_tv_master
GROUP BY date_only
ORDER BY total_minutes ASC
LIMIT 10;