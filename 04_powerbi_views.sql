/* =====================================================================
   04_powerbi_views.sql — the semantic layer Power BI connects to.
   Power BI: Get Data → SQL Server → server name, database PhoneMarket
             → Import → select the 4 vw_pbi_* views.
   ===================================================================== */
USE PhoneMarket;
GO

CREATE OR ALTER VIEW dw.vw_pbi_fact_listing AS
SELECT f.asin, f.search_rank, f.title, f.brand_key, f.category_key, f.price_band_key,
       f.condition, f.lock_status, f.seller_channel,
       CASE WHEN f.is_5g = 1 THEN '5G' ELSE '4G / other' END              AS network,
       f.storage_gb, f.price, f.list_price, f.discount_amt, f.discount_pct, f.has_discount,
       f.min_offer_price, f.star_rating, f.rating_band, f.num_ratings, f.num_offers,
       f.is_best_seller, f.is_amazon_choice, f.is_prime, f.climate_pledge_friendly,
       f.monthly_units_min, f.sales_badge_shown, f.sales_band, f.est_monthly_revenue,
       f.stock_left, f.is_low_stock,
       CASE WHEN f.is_low_stock = 1 AND f.monthly_units_min >= 500
            THEN 'High risk' WHEN f.is_low_stock = 1 THEN 'Watch' ELSE 'OK' END AS stock_risk,
       f.free_delivery, f.days_to_delivery, f.has_coupon, f.coupon_type,
       f.coupon_saving_usd, f.net_price_after_coupon, f.snapshot_date,
       -- Short product name for visuals (first 60 characters)
       CONCAT(LEFT(f.title, 60), IIF(LEN(f.title) > 60, '…', ''))                AS product_short
FROM dw.fact_listing f;
GO

CREATE OR ALTER VIEW dw.vw_pbi_dim_brand AS
SELECT brand_key, brand_name, brand_tier FROM dw.dim_brand;
GO

CREATE OR ALTER VIEW dw.vw_pbi_dim_category AS
SELECT category_key, category_name,
       CASE WHEN is_handset = 1 THEN 'Mobile handset' ELSE 'Non-handset' END AS category_group
FROM dw.dim_category;
GO

CREATE OR ALTER VIEW dw.vw_pbi_dim_price_band AS
SELECT price_band_key, price_band_name, min_price, max_price FROM dw.dim_price_band;
GO

/* Pre-aggregated brand scorecard — handy for a table visual or for
   checking Power BI measures against SQL.                          */
CREATE OR ALTER VIEW dw.vw_brand_scorecard AS
SELECT b.brand_name, b.brand_tier,
       COUNT(*)                                        AS listings,
       SUM(f.monthly_units_min)                        AS units_min,
       SUM(f.est_monthly_revenue)                      AS revenue_min,
       CAST(100.0 * SUM(f.est_monthly_revenue)
            / SUM(SUM(f.est_monthly_revenue)) OVER () AS DECIMAL(5,1)) AS revenue_share_pct,
       CAST(AVG(f.price) AS DECIMAL(10,2))             AS avg_price,
       CAST(AVG(f.star_rating) AS DECIMAL(3,2))        AS avg_rating,
       SUM(f.num_ratings)                              AS total_reviews,
       RANK() OVER (ORDER BY SUM(f.est_monthly_revenue) DESC) AS revenue_rank
FROM dw.fact_listing f
JOIN dw.dim_brand b ON b.brand_key = f.brand_key
GROUP BY b.brand_name, b.brand_tier;
GO
