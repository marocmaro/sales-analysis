/* =====================================================================
   05_business_questions.sql — analytical questions answered in SQL.
   Results feed the "Conclusion & Recommendations" slides.
   Note: units / revenue are LOWER-BOUND estimates (Amazon "X+ bought
   in past month" badge × current price).
   ===================================================================== */
USE PhoneMarket;
GO

-- Q1  Which product categories drive the market?
SELECT c.category_name,
       COUNT(*)                                   AS listings,
       SUM(f.monthly_units_min)                   AS units_min,
       SUM(f.est_monthly_revenue)                 AS revenue_min,
       CAST(100.0*SUM(f.est_monthly_revenue)/SUM(SUM(f.est_monthly_revenue)) OVER () AS DECIMAL(5,1)) AS revenue_share_pct,
       CAST(AVG(f.star_rating) AS DECIMAL(3,2))   AS avg_rating
FROM dw.fact_listing f JOIN dw.dim_category c ON c.category_key = f.category_key
GROUP BY c.category_name
ORDER BY revenue_min DESC;

-- Q2  Top 10 brands by estimated revenue, with share and running (Pareto) share
WITH b AS (
  SELECT d.brand_name, COUNT(*) AS listings, SUM(f.est_monthly_revenue) AS revenue_min
  FROM dw.fact_listing f JOIN dw.dim_brand d ON d.brand_key = f.brand_key
  GROUP BY d.brand_name)
SELECT TOP (10) brand_name, listings, revenue_min,
       CAST(100.0*revenue_min/SUM(revenue_min) OVER () AS DECIMAL(5,1)) AS share_pct,
       CAST(100.0*SUM(revenue_min) OVER (ORDER BY revenue_min DESC ROWS UNBOUNDED PRECEDING)
            /SUM(revenue_min) OVER () AS DECIMAL(5,1))                  AS cumulative_share_pct
FROM b ORDER BY revenue_min DESC;

-- Q3  Smartphone price sweet spot: where do units and revenue concentrate?
SELECT pb.price_band_key, pb.price_band_name,
       COUNT(*) AS listings, SUM(f.monthly_units_min) AS units_min, SUM(f.est_monthly_revenue) AS revenue_min,
       CAST(100.0*SUM(f.est_monthly_revenue)/SUM(SUM(f.est_monthly_revenue)) OVER () AS DECIMAL(5,1)) AS revenue_share_pct,
       CAST(AVG(f.star_rating) AS DECIMAL(3,2)) AS avg_rating
FROM dw.fact_listing f
JOIN dw.dim_category c   ON c.category_key = f.category_key
JOIN dw.dim_price_band pb ON pb.price_band_key = f.price_band_key
WHERE c.category_name = 'Smartphone'
GROUP BY pb.price_band_key, pb.price_band_name
ORDER BY pb.price_band_key;

-- Q4  New vs Renewed smartphones — velocity per listing
SELECT f.condition, COUNT(*) AS listings,
       CAST(AVG(f.price) AS DECIMAL(10,2))                   AS avg_price,
       CAST(AVG(1.0*f.monthly_units_min) AS DECIMAL(10,0))    AS avg_units_per_listing,
       SUM(f.est_monthly_revenue)                            AS revenue_min
FROM dw.fact_listing f JOIN dw.dim_category c ON c.category_key = f.category_key
WHERE c.category_name = 'Smartphone'
GROUP BY f.condition;

-- Q5  Do discounts, coupons and Prime move volume? (association, not causation)
SELECT 'Discount' AS lever, has_discount AS flag, COUNT(*) AS listings, AVG(1.0*monthly_units_min) AS avg_units FROM dw.fact_listing GROUP BY has_discount
UNION ALL
SELECT 'Coupon',   has_coupon, COUNT(*), AVG(1.0*monthly_units_min) FROM dw.fact_listing GROUP BY has_coupon
UNION ALL
SELECT 'Prime',    is_prime,   COUNT(*), AVG(1.0*monthly_units_min) FROM dw.fact_listing GROUP BY is_prime
ORDER BY lever, flag;

-- Q6  Unlocked vs carrier-locked handsets
SELECT f.lock_status, COUNT(*) AS listings,
       CAST(AVG(f.price) AS DECIMAL(10,2)) AS avg_price,
       CAST(AVG(1.0*f.monthly_units_min) AS DECIMAL(10,0)) AS avg_units
FROM dw.fact_listing f JOIN dw.dim_category c ON c.category_key = f.category_key
WHERE c.is_handset = 1
GROUP BY f.lock_status ORDER BY avg_units DESC;

-- Q7  Stock-out risk: fast sellers with 10 or fewer units left
SELECT f.asin, d.brand_name, LEFT(f.title,60) AS product, f.price,
       f.stock_left, f.monthly_units_min,
       f.est_monthly_revenue AS revenue_at_risk_min
FROM dw.fact_listing f JOIN dw.dim_brand d ON d.brand_key = f.brand_key
WHERE f.is_low_stock = 1 AND f.monthly_units_min >= 500
ORDER BY f.monthly_units_min DESC, f.stock_left;

-- Q8  Social proof: review volume vs sales velocity
SELECT CASE WHEN num_ratings < 100   THEN '1. <100 reviews'
            WHEN num_ratings < 1000  THEN '2. 100–999'
            WHEN num_ratings < 5000  THEN '3. 1K–4.9K'
            ELSE '4. 5K+' END AS review_bucket,
       COUNT(*) AS listings,
       CAST(AVG(1.0*monthly_units_min) AS DECIMAL(10,0)) AS avg_units,
       CAST(AVG(star_rating) AS DECIMAL(3,2))            AS avg_rating
FROM dw.fact_listing
GROUP BY CASE WHEN num_ratings < 100 THEN '1. <100 reviews' WHEN num_ratings < 1000 THEN '2. 100–999'
              WHEN num_ratings < 5000 THEN '3. 1K–4.9K' ELSE '4. 5K+' END
ORDER BY review_bucket;

-- Q9  Best product per brand (window function)
WITH r AS (
  SELECT d.brand_name, LEFT(f.title,60) AS product, f.price, f.monthly_units_min, f.est_monthly_revenue,
         ROW_NUMBER() OVER (PARTITION BY d.brand_name ORDER BY f.est_monthly_revenue DESC, f.search_rank) AS rn
  FROM dw.fact_listing f JOIN dw.dim_brand d ON d.brand_key = f.brand_key)
SELECT brand_name, product, price, monthly_units_min, est_monthly_revenue
FROM r WHERE rn = 1 AND est_monthly_revenue > 0
ORDER BY est_monthly_revenue DESC;

-- Q10 Concentration: share of revenue from the top 10% of listings
WITH ranked AS (
  SELECT est_monthly_revenue, NTILE(10) OVER (ORDER BY est_monthly_revenue DESC) AS decile
  FROM dw.fact_listing)
SELECT decile, COUNT(*) AS listings, SUM(est_monthly_revenue) AS revenue_min,
       CAST(100.0*SUM(est_monthly_revenue)/SUM(SUM(est_monthly_revenue)) OVER () AS DECIMAL(5,1)) AS share_pct
FROM ranked GROUP BY decile ORDER BY decile;
GO
