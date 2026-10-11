// =====================================================================
//  Power Query (M) — two ways to load the data. Use ONE of them.
//  Home → Transform data → New Source → Blank Query → Advanced Editor
// =====================================================================

// ---------- Option A (recommended): SQL Server views ----------
// Query name: Fact_Listing
let
    Source  = Sql.Database("localhost", "PhoneMarket"),          // change server name, e.g. "localhost\SQLEXPRESS"
    Fact    = Source{[Schema = "dw", Item = "vw_pbi_fact_listing"]}[Data]
in
    Fact

// Query name: Dim_Brand
let
    Source = Sql.Database("localhost", "PhoneMarket"),
    Dim    = Source{[Schema = "dw", Item = "vw_pbi_dim_brand"]}[Data]
in
    Dim

// Query name: Dim_Category
let
    Source = Sql.Database("localhost", "PhoneMarket"),
    Dim    = Source{[Schema = "dw", Item = "vw_pbi_dim_category"]}[Data]
in
    Dim

// Query name: Dim_PriceBand
let
    Source = Sql.Database("localhost", "PhoneMarket"),
    Dim    = Source{[Schema = "dw", Item = "vw_pbi_dim_price_band"]}[Data]
in
    Dim


// ---------- Option B (no SQL Server): read the cleaned CSV directly ----------
// Query name: Fact_Listing  (then build the dims with "Reference" → Remove other columns → Remove duplicates)
let
    Source   = Csv.Document(File.Contents("C:\Phone_Market_Project\01_Data\clean\phones_clean.csv"),
                            [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Headers  = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Typed    = Table.TransformColumnTypes(Headers, {
        {"search_rank", Int64.Type}, {"is_5g", type logical}, {"storage_gb", type number},
        {"price", Currency.Type}, {"list_price", Currency.Type}, {"discount_amt", Currency.Type},
        {"discount_pct", Percentage.Type}, {"has_discount", type logical}, {"min_offer_price", Currency.Type},
        {"star_rating", type number}, {"num_ratings", Int64.Type}, {"is_rated", type logical},
        {"num_offers", Int64.Type}, {"is_best_seller", type logical}, {"is_amazon_choice", type logical},
        {"is_prime", type logical}, {"climate_pledge_friendly", type logical}, {"has_variations", type logical},
        {"monthly_units_min", Int64.Type}, {"sales_badge_shown", type logical},
        {"est_monthly_revenue", Currency.Type}, {"stock_left", Int64.Type}, {"is_low_stock", type logical},
        {"out_of_stock", type logical}, {"free_delivery", type logical}, {"delivery_fee", Currency.Type},
        {"delivery_date", type date}, {"days_to_delivery", Int64.Type}, {"fast_delivery_option", type logical},
        {"has_coupon", type logical}, {"coupon_value", type number}, {"coupon_saving_usd", Currency.Type},
        {"net_price_after_coupon", Currency.Type}, {"snapshot_date", type date}}, "en-US"),
    StockRisk = Table.AddColumn(Typed, "stock_risk", each
                    if [is_low_stock] and [monthly_units_min] >= 500 then "High risk"
                    else if [is_low_stock] then "Watch" else "OK", type text),
    ShortName = Table.AddColumn(StockRisk, "product_short", each
                    if Text.Length([title]) > 60 then Text.Start([title], 60) & "…" else [title], type text),
    PriceBandKey = Table.AddColumn(ShortName, "price_band_key", each
                    List.PositionOf({"<$50","$50–99","$100–199","$200–399","$400–799","$800+"}, [price_band]) + 1, Int64.Type)
in
    PriceBandKey
