/* =====================================================================
   02_load_data.sql — load the Python-cleaned CSV, then populate the
   star schema with type-safe conversions.
   >>> Change the file path below to where you saved phones_clean.csv <<<
   ===================================================================== */
USE PhoneMarket;
GO

TRUNCATE TABLE stg.phones_clean;

BULK INSERT stg.phones_clean
FROM 'C:\Phone_Market_Project\01_Data\clean\phones_clean.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"',
      FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
-- Alternative without BULK permissions: SSMS → right-click database →
-- Tasks → Import Flat File → target table stg.phones_clean.

SELECT COUNT(*) AS staged_rows FROM stg.phones_clean;   -- expect 311
GO

/* Helper conversion: Python writes booleans as 'True'/'False' and
   missing values as empty strings → convert to BIT / NULL.          */

/* ---------- dim_brand ---------- */
DELETE FROM dw.fact_listing; DELETE FROM dw.dim_brand; DELETE FROM dw.dim_category; DELETE FROM dw.dim_price_band;
DBCC CHECKIDENT ('dw.dim_brand', RESEED, 0);
DBCC CHECKIDENT ('dw.dim_category', RESEED, 0);

INSERT INTO dw.dim_brand (brand_name, brand_tier)
SELECT DISTINCT brand,
       CASE WHEN brand IN ('Samsung','Apple','Motorola','Google','OnePlus') THEN 'Major OEM'
            WHEN brand = 'Generic / Unbranded'                           THEN 'Generic'
            ELSE 'Challenger' END
FROM stg.phones_clean;

/* ---------- dim_category ---------- */
INSERT INTO dw.dim_category (category_name, is_handset)
SELECT DISTINCT category,
       CASE WHEN category IN ('Smartphone','Basic / Flip Phone') THEN 1 ELSE 0 END
FROM stg.phones_clean;

/* ---------- dim_price_band (static reference data) ---------- */
INSERT INTO dw.dim_price_band VALUES
 (1,'<$50',0,49.99),(2,'$50–99',50,99.99),(3,'$100–199',100,199.99),
 (4,'$200–399',200,399.99),(5,'$400–799',400,799.99),(6,'$800+',800,99999);
GO

/* ---------- fact_listing ---------- */
INSERT INTO dw.fact_listing
SELECT
    s.asin,
    TRY_CAST(s.search_rank AS INT),
    s.title,
    b.brand_key, c.category_key, pb.price_band_key,
    s.condition, s.lock_status, s.seller_channel,
    IIF(s.is_5g = 'True', 1, 0),
    TRY_CAST(TRY_CAST(NULLIF(s.storage_gb,'') AS FLOAT) AS INT),
    TRY_CAST(s.price AS DECIMAL(10,2)),
    TRY_CAST(s.list_price AS DECIMAL(10,2)),
    TRY_CAST(s.discount_amt AS DECIMAL(10,2)),
    TRY_CAST(s.discount_pct AS DECIMAL(6,4)),
    IIF(s.has_discount = 'True', 1, 0),
    TRY_CAST(NULLIF(s.min_offer_price,'') AS DECIMAL(10,2)),
    TRY_CAST(NULLIF(s.star_rating,'') AS DECIMAL(3,1)),
    s.rating_band,
    TRY_CAST(s.num_ratings AS INT),
    TRY_CAST(s.num_offers AS INT),
    IIF(s.is_best_seller = 'True', 1, 0),
    IIF(s.is_amazon_choice = 'True', 1, 0),
    IIF(s.is_prime = 'True', 1, 0),
    IIF(s.climate_pledge_friendly = 'True', 1, 0),
    IIF(s.has_variations = 'True', 1, 0),
    TRY_CAST(s.monthly_units_min AS INT),
    IIF(s.sales_badge_shown = 'True', 1, 0),
    s.sales_band,
    TRY_CAST(s.est_monthly_revenue AS DECIMAL(14,2)),
    TRY_CAST(TRY_CAST(NULLIF(s.stock_left,'') AS FLOAT) AS INT),
    IIF(s.is_low_stock = 'True', 1, 0),
    IIF(s.out_of_stock = 'True', 1, 0),
    IIF(s.free_delivery = 'True', 1, 0),
    TRY_CAST(s.delivery_fee AS DECIMAL(8,2)),
    TRY_CAST(NULLIF(s.delivery_date,'') AS DATE),
    TRY_CAST(TRY_CAST(NULLIF(s.days_to_delivery,'') AS FLOAT) AS INT),
    IIF(s.has_coupon = 'True', 1, 0),
    s.coupon_type,
    TRY_CAST(s.coupon_saving_usd AS DECIMAL(10,2)),
    TRY_CAST(s.net_price_after_coupon AS DECIMAL(10,2)),
    TRY_CAST(s.snapshot_date AS DATE)
FROM stg.phones_clean s
JOIN dw.dim_brand      b  ON b.brand_name      = s.brand
JOIN dw.dim_category   c  ON c.category_name   = s.category
JOIN dw.dim_price_band pb ON pb.price_band_name = s.price_band;

SELECT COUNT(*) AS fact_rows FROM dw.fact_listing;     -- expect 311
GO
