# Power BI Build Guide — Phone Market Dashboard

## Fast path: open the ready-made dashboard (5 minutes)

The folder contains a complete Power BI project, `Phone_Market_Dashboard.pbip`, with the data model, relationships, 54 measures, the theme and both dashboard pages already built.

| Step | Action |
|---|---|
| 1 | Copy the project folder to `C:\Phone_Market_Project\` (or keep it elsewhere and change the parameter in step 4). |
| 2 | Run `python 02_Python/phone_market_pipeline.py`. It cleans the raw data, validates it and writes the four CSV files into `04_PowerBI/data/`. |
| 3 | Double-click `04_PowerBI/Phone_Market_Dashboard.pbip` (Power BI Desktop, recent version). |
| 4 | If the folder is not `C:\Phone_Market_Project\`: Home → Transform data → **Edit parameters** → set `DataFolder` to your `…\04_PowerBI\data\` path (keep the final backslash). |
| 5 | Home → **Refresh**. The project opens without cached data, so visuals stay empty until the first refresh. |
| 6 | Check the cards against the control totals at the bottom of this guide. |
| 7 | File → **Save as** → type `.pbix` → `04_PowerBI/Phone_Market_Dashboard.pbix` (the single file to submit), then take the screenshots for slides 9 and 10. |

If Power BI Desktop says it cannot open the project, update Desktop, or enable File → Options → Preview features → "Power BI Project (.pbip) save option", "Store semantic model using TMDL format" and "Store reports using enhanced metadata format (PBIR)", then restart.

What the ready-made file adds beyond the manual build below: dynamic card subtitles (they recalculate with every slicer), a dynamic brand-chart title, Top 8 brands and Top 8 products driven by DAX ranking so they re-rank when you filter, slicers synced across both pages, a disconnected `Promo_Lever` table so all three promotion levers sit in one chart, and log-scale axes on the scatter.

The manual build steps below remain valid if you prefer to build it yourself or need to explain each step in the presentation.

---

Expected time: **60–90 minutes**. The two mockup images in this folder show the finished layout.
Every number on the finished dashboard should match the **control totals** at the bottom of this guide.

---

## Step 0 — Prerequisites
| Need | Notes |
|---|---|
| Power BI Desktop (free, Windows) | Microsoft Store or microsoft.com/power-bi |
| SQL Server Express + SSMS (optional) | Needed only for Option A. Without it, use Option B (CSV) |
| Project folder | Copy the folder to `C:\Phone_Market_Project\` so the file paths in the scripts work unchanged |

## Step 1 — Prepare the data (already done for you)
1. `02_Python/01_data_cleaning_eda.ipynb` → produces `01_Data/clean/phones_clean.csv` (311 rows × 45 columns).
2. In SSMS run `03_SQL/01` → `02` → `03` → `04`. Script 03 must show 311 | 311 and zeros on every check.

## Step 2 — Load data into Power BI
**Option A (SQL Server, recommended — shows SQL + Power BI integration)**
1. Home → Get data → **SQL Server** → Server `localhost` (or `localhost\SQLEXPRESS`), Database `PhoneMarket`, mode **Import**.
2. Tick the four views `dw.vw_pbi_fact_listing`, `vw_pbi_dim_brand`, `vw_pbi_dim_category`, `vw_pbi_dim_price_band` → **Transform Data**.
3. Rename the queries to `Fact_Listing`, `Dim_Brand`, `Dim_Category`, `Dim_PriceBand` → Close & Apply.

**Option B (CSV only)** — load the four files in `04_PowerBI/data/` written by `phone_market_pipeline.py` (fact plus three dimensions, keys already assigned), or paste the "Option B" code from `PowerQuery_M.pq` into a Blank Query named `Fact_Listing`. Then create the dimension tables:
right-click `Fact_Listing` → Reference → keep only `brand` → Remove duplicates → name it `Dim_Brand` (repeat for `category`, `price_band` + `price_band_key`).

## Step 3 — Data model (Model view)
| From (many) | To (one) | Cardinality / direction |
|---|---|---|
| `Fact_Listing[brand_key]` | `Dim_Brand[brand_key]` | Many-to-one, single |
| `Fact_Listing[category_key]` | `Dim_Category[category_key]` | Many-to-one, single |
| `Fact_Listing[price_band_key]` | `Dim_PriceBand[price_band_key]` | Many-to-one, single |

* `Dim_PriceBand[price_band_name]` → Column tools → **Sort by column** → `price_band_key` (so bands sort $ low→high, not alphabetically).
* `Fact_Listing[sales_band]` already sorts correctly (prefix 0.–4.).
* Hide the key columns in report view (right-click → Hide in report view).
* Format: `price`, `est_monthly_revenue` → Currency $; `discount_pct` → Percentage.

## Step 4 — Measures
Home → Enter data → name the table `_Measures` → Load. Then add every measure in `DAX_Measures.dax` (Modeling → New measure, paste one at a time).
Delete the default column of `_Measures` — it then becomes a measure table with a calculator icon.

## Step 5 — Theme
View → Themes → **Browse for themes** → `PhoneMarket_Theme.json`. Canvas: View → Page view → 16:9, 1280×720.

## Step 6 — Page 1 "Market Overview" (see `dashboard_mockup_page1_overview.png`)
| # | Visual | Fields |
|---|---|---|
| 1 | Shape/text header (navy `#14325C`) | Title + subtitle |
| 2 | 5 × **Slicer** (Dropdown) | `Dim_Category[category_name]`, `Dim_Brand[brand_name]`, `Fact_Listing[condition]`, `Dim_PriceBand[price_band_name]`, `Fact_Listing[lock_status]` |
| 3 | 6 × **Card (new)** | `[Total Listings]`, `[Est Units]`, `[Est Revenue]`, `[Median Price]`, `[Avg Rating]`, `[% Listings Discounted]` |
| 4 | **Clustered bar** — Revenue by category | Y: `category_name`, X: `[Est Revenue]`, data labels on |
| 5 | **Clustered bar** — Top 8 brands | Y: `brand_name`, X: `[Est Revenue]`; Filters pane → brand_name → Top N = 8 by `[Est Revenue]`; title = `[Title - Brand Chart]` (fx) |
| 6 | **Donut** — New vs Renewed | Legend: `condition`, Values: `[Est Revenue]`; visual-level filter category = Smartphone |
| 7 | **Clustered column** — Revenue by price band | X: `price_band_name`, Y: `[Est Revenue]`; filter category = Smartphone; highlight the $200–399 bar (Columns → colour per category) |
| 8 | **Table** — Top products | `product_short`, `brand_name`, `price`, `monthly_units_min`, `est_monthly_revenue`; Top N = 8 by `[Est Revenue]` |

Slicers: View → **Sync slicers** → tick both pages so a filter carries across.

## Step 7 — Page 2 "Drivers & Risk" (see `dashboard_mockup_page2_drivers_risk.png`)
| # | Visual | Fields |
|---|---|---|
| 1 | 4 × Card | `[Units per Listing - Discounted]` (subtitle: `[Discount Uplift %]`), `[Units per Listing - Unlocked]`, `[Low Stock Listings]`, `[High Risk Revenue]` |
| 2 | **Clustered bar** — Units by review count | Create a calculated column first (below), Y: `review_bucket`, X: `[Units per Listing]` |
| 3 | **Clustered bar** — Promotion levers | Three small bars or one bar with Y: `has_discount`/`has_coupon`/`is_prime`, X: `[Units per Listing]` |
| 4 | **Scatter** — Price vs units | X: `price` (log scale), Y: `monthly_units_min` (log), Size: `num_ratings`, Legend: `condition`, Values: `asin`; filter category = Smartphone and monthly_units_min > 0 |
| 5 | **Table** — Stock-out watch-list | `stock_risk`, `product_short`, `brand_name`, `price`, `stock_left`, `monthly_units_min`, `est_monthly_revenue`; filter stock_risk = "High risk"; Cell elements → font colour → fx → field value `[Risk Colour]` |

```DAX
review_bucket =                       // calculated column on Fact_Listing
SWITCH ( TRUE (),
    Fact_Listing[num_ratings] < 100,  "1. <100 reviews",
    Fact_Listing[num_ratings] < 1000, "2. 100–999",
    Fact_Listing[num_ratings] < 5000, "3. 1K–4.9K",
    "4. 5K+" )
```

## Step 8 — Finishing touches
* Add **tooltips**: on each bar chart add `[Total Listings]`, `[Avg Rating]`, `[Revenue Share %]` to the Tooltips well.
* Add a **drill-through** page "Brand detail": drill-through field `brand_name`, show cards + product table.
* Add a text box footnote: *"Units = Amazon 'X+ bought in past month' badge (lower bound). Revenue = price × units. Snapshot 19 Sep 2024."*
* Optional: Edit interactions so the donut cross-filters the price-band chart.
* Save as `04_PowerBI/Phone_Market_Dashboard.pbix`, then take screenshots of both pages for the PowerPoint (replace the mockup images on slides 9–10).

## Control totals (all filters cleared)
| Measure | Expected |
|---|---|
| Total Listings | 311 |
| Brands (distinct) | 41 |
| Est Units | 130,550 |
| Est Revenue | $20,680,783.50 |
| Median Price | $113.87 |
| Avg Rating | 4.09 |
| % Listings Discounted | 44.1 % |
| Samsung revenue share | 47.0 % |
| Smartphone revenue share | 87.3 % |
| High Risk Revenue (9 listings) | $2,089,050 |
| Units per Listing – Discounted / Not | 512 / 347 (+48 %) |
