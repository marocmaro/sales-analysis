/* =====================================================================
   03_data_validation.sql — prove the load is complete and correct.
   Every query should return the "expected" value in the comment.
   ===================================================================== */
USE PhoneMarket;
GO

-- V1  Row reconciliation: staging vs fact                     expect 311 | 311
SELECT (SELECT COUNT(*) FROM stg.phones_clean) AS staged,
       (SELECT COUNT(*) FROM dw.fact_listing)  AS loaded;

-- V2  No duplicate products                                   expect 0 rows
SELECT asin, COUNT(*) AS n FROM stg.phones_clean GROUP BY asin HAVING COUNT(*) > 1;

-- V3  Values that failed type conversion (TRY_CAST → NULL)     expect 0
SELECT COUNT(*) AS bad_prices
FROM stg.phones_clean WHERE TRY_CAST(price AS DECIMAL(10,2)) IS NULL;

-- V4  Business-rule checks                                    expect 0 on every column
SELECT
  SUM(IIF(list_price < price, 1, 0))                         AS list_below_price,
  SUM(IIF(min_offer_price > price, 1, 0))                    AS min_offer_above_price,
  SUM(IIF(star_rating NOT BETWEEN 1 AND 5, 1, 0))            AS rating_out_of_range,
  SUM(IIF(num_ratings = 0 AND star_rating IS NOT NULL, 1, 0)) AS rating_without_reviews,
  SUM(IIF(est_monthly_revenue <> ROUND(price*monthly_units_min,2), 1, 0)) AS revenue_mismatch
FROM dw.fact_listing;

-- V5  Null profile of the fact table (nulls are expected only where documented)
SELECT
  SUM(IIF(star_rating   IS NULL,1,0)) AS null_rating,      -- 3  (products with 0 reviews)
  SUM(IIF(storage_gb    IS NULL,1,0)) AS null_storage,     -- non-smartphones + titles without GB
  SUM(IIF(stock_left    IS NULL,1,0)) AS null_stock,       -- in stock (no "Only N left" message)
  SUM(IIF(delivery_date IS NULL,1,0)) AS null_delivery_dt  -- "FREE delivery" with no date shown
FROM dw.fact_listing;

-- V6  Referential integrity (no orphan keys)                  expect 0
SELECT COUNT(*) AS orphan_rows
FROM dw.fact_listing f
LEFT JOIN dw.dim_brand b    ON b.brand_key = f.brand_key
LEFT JOIN dw.dim_category c ON c.category_key = f.category_key
WHERE b.brand_key IS NULL OR c.category_key IS NULL;

-- V7  Control totals — must match the Python notebook and Power BI cards
SELECT COUNT(*)                       AS listings,             -- 311
       COUNT(DISTINCT brand_key)      AS brands,               -- 41
       SUM(monthly_units_min)         AS units_min,            -- 130,550
       SUM(est_monthly_revenue)       AS revenue_min,          -- 20,680,783.50
       CAST(AVG(star_rating) AS DECIMAL(4,2)) AS avg_rating    -- 4.09
FROM dw.fact_listing;
GO
