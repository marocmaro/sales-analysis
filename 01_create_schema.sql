/* =====================================================================
   Phone Market Analysis — 01_create_schema.sql
   Platform : Microsoft SQL Server 2019+ (works on SQL Server Express)
   Purpose  : Create database, a raw staging table and a star schema
              (1 fact + 3 dimensions) that Power BI imports.
   Run order: 01 → 02 → 03 → 04 → 05
   ===================================================================== */

IF DB_ID('PhoneMarket') IS NULL CREATE DATABASE PhoneMarket;
GO
USE PhoneMarket;
GO
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('dw')  IS NULL EXEC('CREATE SCHEMA dw');
GO

/* ---------- Staging: every column as text, exactly as the CSV --------
   Loading as NVARCHAR first means a single bad value cannot break the
   whole load; types are enforced in step 02 with TRY_CAST.            */
DROP TABLE IF EXISTS stg.phones_clean;
CREATE TABLE stg.phones_clean (
    asin NVARCHAR(20), search_rank NVARCHAR(10), title NVARCHAR(600), brand NVARCHAR(60),
    category NVARCHAR(40), condition NVARCHAR(20), lock_status NVARCHAR(20), seller_channel NVARCHAR(40),
    is_5g NVARCHAR(10), storage_gb NVARCHAR(10), price NVARCHAR(20), list_price NVARCHAR(20),
    discount_amt NVARCHAR(20), discount_pct NVARCHAR(20), has_discount NVARCHAR(10), min_offer_price NVARCHAR(20),
    price_band NVARCHAR(20), star_rating NVARCHAR(10), rating_band NVARCHAR(20), num_ratings NVARCHAR(20),
    is_rated NVARCHAR(10), num_offers NVARCHAR(10), is_best_seller NVARCHAR(10), is_amazon_choice NVARCHAR(10),
    is_prime NVARCHAR(10), climate_pledge_friendly NVARCHAR(10), has_variations NVARCHAR(10),
    monthly_units_min NVARCHAR(20), sales_badge_shown NVARCHAR(10), sales_band NVARCHAR(30),
    est_monthly_revenue NVARCHAR(20), stock_left NVARCHAR(10), is_low_stock NVARCHAR(10), out_of_stock NVARCHAR(10),
    free_delivery NVARCHAR(10), delivery_fee NVARCHAR(20), delivery_date NVARCHAR(20), days_to_delivery NVARCHAR(10),
    fast_delivery_option NVARCHAR(10), has_coupon NVARCHAR(10), coupon_type NVARCHAR(20), coupon_value NVARCHAR(20),
    coupon_saving_usd NVARCHAR(20), net_price_after_coupon NVARCHAR(20), snapshot_date NVARCHAR(20)
);
GO

/* ---------- Dimensions ---------- */
DROP TABLE IF EXISTS dw.fact_listing;
DROP TABLE IF EXISTS dw.dim_brand;
DROP TABLE IF EXISTS dw.dim_category;
DROP TABLE IF EXISTS dw.dim_price_band;

CREATE TABLE dw.dim_brand (
    brand_key   INT IDENTITY(1,1) PRIMARY KEY,
    brand_name  NVARCHAR(60) NOT NULL UNIQUE,
    brand_tier  NVARCHAR(20) NOT NULL      -- 'Major OEM' / 'Challenger' / 'Generic'
);

CREATE TABLE dw.dim_category (
    category_key  INT IDENTITY(1,1) PRIMARY KEY,
    category_name NVARCHAR(40) NOT NULL UNIQUE,
    is_handset    BIT NOT NULL            -- 1 = mobile phone (smartphone / basic)
);

CREATE TABLE dw.dim_price_band (
    price_band_key  INT PRIMARY KEY,      -- also the sort order in Power BI
    price_band_name NVARCHAR(20) NOT NULL UNIQUE,
    min_price       DECIMAL(10,2) NOT NULL,
    max_price       DECIMAL(10,2) NOT NULL
);

/* ---------- Fact: one row per unique Amazon listing (ASIN) ---------- */
CREATE TABLE dw.fact_listing (
    asin                   VARCHAR(20)   NOT NULL PRIMARY KEY,
    search_rank            INT           NOT NULL,
    title                  NVARCHAR(600) NOT NULL,
    brand_key              INT NOT NULL REFERENCES dw.dim_brand(brand_key),
    category_key           INT NOT NULL REFERENCES dw.dim_category(category_key),
    price_band_key         INT NOT NULL REFERENCES dw.dim_price_band(price_band_key),
    condition              VARCHAR(10)   NOT NULL CHECK (condition IN ('New','Renewed')),
    lock_status            VARCHAR(20)   NOT NULL,
    seller_channel         VARCHAR(40)   NOT NULL,
    is_5g                  BIT NOT NULL,
    storage_gb             INT NULL,
    price                  DECIMAL(10,2) NOT NULL CHECK (price > 0),
    list_price             DECIMAL(10,2) NOT NULL,
    discount_amt           DECIMAL(10,2) NOT NULL,
    discount_pct           DECIMAL(6,4)  NOT NULL CHECK (discount_pct BETWEEN 0 AND 1),
    has_discount           BIT NOT NULL,
    min_offer_price        DECIMAL(10,2) NULL,
    star_rating            DECIMAL(3,1)  NULL CHECK (star_rating BETWEEN 1 AND 5),
    rating_band            VARCHAR(20)   NOT NULL,
    num_ratings            INT NOT NULL,
    num_offers             INT NOT NULL,
    is_best_seller         BIT NOT NULL,
    is_amazon_choice       BIT NOT NULL,
    is_prime               BIT NOT NULL,
    climate_pledge_friendly BIT NOT NULL,
    has_variations         BIT NOT NULL,
    monthly_units_min      INT NOT NULL,
    sales_badge_shown      BIT NOT NULL,
    sales_band             VARCHAR(30)   NOT NULL,
    est_monthly_revenue    DECIMAL(14,2) NOT NULL,
    stock_left             INT NULL,
    is_low_stock           BIT NOT NULL,
    out_of_stock           BIT NOT NULL,
    free_delivery          BIT NOT NULL,
    delivery_fee           DECIMAL(8,2)  NOT NULL,
    delivery_date          DATE NULL,
    days_to_delivery       INT NULL,
    has_coupon             BIT NOT NULL,
    coupon_type            VARCHAR(10)   NOT NULL,
    coupon_saving_usd      DECIMAL(10,2) NOT NULL,
    net_price_after_coupon DECIMAL(10,2) NOT NULL,
    snapshot_date          DATE NOT NULL,
    CONSTRAINT ck_list_ge_price CHECK (list_price >= price)
);
GO
