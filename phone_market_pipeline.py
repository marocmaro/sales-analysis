"""
Amazon US "phone" search — data cleaning, feature engineering, validation
and Power BI export.

Data Analysis Diploma, Final Project.

What this script does
    1. Loads the raw scrape   01_Data/raw/phone_search_raw.csv   (340 rows x 20 cols)
    2. Fixes the 17 documented data-quality problems (same rules as the notebook)
    3. Engineers the analysis features (brand, category, condition, bands, flags)
    4. Exports
         01_Data/clean/phones_clean.csv      311 rows x 45 cols  (input for SQL Server)
         01_Data/clean/rejected_rows.csv     rows removed, with the reason
         04_PowerBI/data/fact_listing.csv    star schema for the Power BI file
         04_PowerBI/data/dim_brand.csv
         04_PowerBI/data/dim_category.csv
         04_PowerBI/data/dim_price_band.csv
    5. Runs the validation checks (same logic as 03_SQL/03_data_validation.sql)
       and prints the control totals that the Power BI cards must match.

How to run
    pip install pandas numpy
    python phone_market_pipeline.py                 (run from any folder)
    python phone_market_pipeline.py --root "C:/Phone_Market_Project"

The script stops with an error if any validation check fails, so a bad
file never reaches SQL Server or Power BI.
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

SNAPSHOT_DATE = pd.Timestamp("2024-09-19")   # derived from "Tomorrow, Sep 20" in the delivery text

PRICE_BANDS = ["<$50", "$50–99", "$100–199", "$200–399", "$400–799", "$800+"]
PRICE_EDGES = [0, 50, 100, 200, 400, 800, 10_000]

# Expected control totals (from the cleaning report). The script checks them.
EXPECTED = {
    "rows": 311,
    "brands": 41,
    "units": 130_550,
    "revenue": 20_680_783.50,
}


# =====================================================================
# 1. Load
# =====================================================================
def load_raw(path: Path) -> pd.DataFrame:
    raw = pd.read_csv(path)
    print(f"[load] {path.name}: {raw.shape[0]} rows x {raw.shape[1]} columns")
    return raw


def profile(raw: pd.DataFrame) -> None:
    """Print the facts that prove each problem exists before fixing it."""
    title = raw["product_title"].astype("string")
    print("[profile] exact duplicate rows      :", int(raw.duplicated().sum()))
    print("[profile] duplicate ASINs (any diff):", int(raw["asin"].duplicated().sum()))
    print("[profile] titles with HTML entities :", int(title.str.contains("&amp;|&quot;|&#", regex=True).sum()))
    print("[profile] rows with no price        :", int(raw["product_price"].isna().sum()))


# =====================================================================
# 2. Cleaning helpers
# =====================================================================
def money(s: pd.Series) -> pd.Series:
    """'$1,614.99 ' -> 1614.99   (problem 3)"""
    return pd.to_numeric(
        s.astype("string").str.replace(r"[\$,\s]", "", regex=True), errors="coerce"
    )


def parse_units(text) -> float:
    """'1K+ bought in past month' -> 1000. Labels scraped by mistake -> NaN (problems 7, 8)."""
    if pd.isna(text):
        return np.nan
    m = re.match(r"(\d+(?:\.\d+)?)(K?)\+ bought", str(text))
    if not m:
        return np.nan
    return int(float(m.group(1)) * (1000 if m.group(2) else 1))


def sales_band(units: int) -> str:
    if units == 0:
        return "0. <50 / not shown"
    if units < 200:
        return "1. 50–199"
    if units < 500:
        return "2. 200–499"
    if units < 1000:
        return "3. 500–999"
    return "4. 1K+"


def first_date(text) -> pd.Timestamp:
    """First 'Mon DD' in the delivery text, year 2024 (problem 11)."""
    if pd.isna(text):
        return pd.NaT
    m = re.search(r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{1,2})", str(text))
    return pd.Timestamp(f"2024-{m.group(1)}-{m.group(2)}") if m else pd.NaT


# ---- Brand / category rules (problems 15, 16) ----
CARRIER_PREFIX = (
    r"^(\[New\]\s*|TracFone\s*\|?\s*|Total by Verizon\s*\|?\s*|Simple Mobile\s*\|?\s*"
    r"|Straight Talk\s*|Prepaid\s+)"
)
BRANDS = {  # regex anchored at the start of the title -> canonical brand
    r"samsung": "Samsung", r"moto(rola)?\b": "Motorola", r"apple|iphone": "Apple", r"google": "Google",
    r"oneplus": "OnePlus", r"nokia": "Nokia", r"panasonic": "Panasonic", r"vtech": "VTech", r"at&t": "AT&T",
    r"tcl": "TCL", r"alcatel": "Alcatel", r"blu\b": "BLU", r"doogee": "DOOGEE", r"xiaomi": "Xiaomi",
    r"nothing|cmf": "Nothing", r"kyocera": "Kyocera", r"cat\b": "CAT", r"umidigi": "UMIDIGI", r"nuu": "NUU",
    r"simbros": "SIMBROS", r"bold\b": "Bold", r"blackview": "Blackview", r"cubot": "CUBOT", r"oukitel": "OUKITEL",
    r"lively": "Lively", r"gabb": "Gabb", r"hamilton": "Hamilton", r"hellobaby": "HelloBaby", r"zte": "ZTE",
    r"yealink": "Yealink", r"xblue": "XBLUE", r"smpl": "SMPL", r"sangyn": "Sangyn", r"scosche": "Scosche",
    r"spidercase": "SPIDERCASE", r"team luxury": "TEAM LUXURY", r"tocol": "TOCOL", r"toneof": "TONEOF",
    r"sensyne": "Sensyne", r"agm\b": "AGM",
}
MAJOR_OEM = {"Samsung", "Apple", "Motorola", "Google", "OnePlus"}

ACCESSORY = (r"\b(case|holder|mount|tripod|gimbal|charger|power bank|ring light|sim card"
             r"|charging shelf|bluetooth speaker)\b")
LANDLINE = (r"cordless|corded|landline|telephone|\bdect\b|answering|handset|ip phone|office phone"
            r"|add-on phone|wall phone|speakerphone|image phone")
BASIC = r"\bflip\b|smartflip|feature phone|basic cell phone|jitterbug|nokia 110"


def get_brand(title: str) -> str:
    s = re.sub(CARRIER_PREFIX, "", title, flags=re.I).lstrip("|- ").strip()
    for pat, brand in BRANDS.items():
        if re.match(pat, s, flags=re.I):
            return brand
    return "Generic / Unbranded"


def get_seller_channel(title: str) -> str:
    m = re.match(r"^(TracFone|Total by Verizon|Simple Mobile|Straight Talk)", title, flags=re.I)
    names = {"tracfone": "TracFone", "total by verizon": "Total by Verizon",
             "simple mobile": "Simple Mobile", "straight talk": "Straight Talk"}
    return names[m.group(1).lower()] if m else "Open market"


def get_category(title: str) -> str:
    tl = title.lower()
    if re.search(r"\btoys?\b", tl):
        return "Kids Toy Phone"
    if re.search(LANDLINE, tl) and not re.search(r"android|smartphone", tl):
        return "Landline / Cordless"
    if re.search(ACCESSORY, tl) and not re.search(r"galaxy|pixel|moto|nokia|redmi", tl[:40]):
        return "Accessory"
    if re.search(BASIC, tl) and not re.search(r"galaxy|smartphone|\d+g/\d+gb", tl):
        return "Basic / Flip Phone"
    return "Smartphone"


def storage_gb(title: str) -> float:
    t = title.replace("ROM", "").replace("Storage", "")
    pairs = re.findall(r"(\d+)\s?(?:GB)?\s?[/+]\s?(\d+)\s?(?:GB|\|)", t, flags=re.I)
    vals = [int(x) for p in pairs for x in p] + [int(x) for x in re.findall(r"(\d+)\s?GB", t, flags=re.I)]
    if not vals:
        vals += [int(x) * 1024 for x in re.findall(r"(\d)\s?TB", t)]
    vals = [v for v in vals if v in (4, 8, 16, 32, 64, 128, 256, 512, 1024)]
    return float(max(vals)) if vals else np.nan


# =====================================================================
# 3. Clean + feature engineering
# =====================================================================
def clean(raw: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    df = raw.copy()
    df["search_rank"] = np.arange(1, len(df) + 1)

    # Problems 1-2: duplicates
    n0 = len(df)
    df = df.drop_duplicates(subset=list(raw.columns))
    n1 = len(df)
    df = df.drop_duplicates(subset="asin", keep="first")
    n2 = len(df)
    print(f"[clean] duplicates: {n0} -> {n1} exact (-{n0 - n1}) -> {n2} by ASIN (-{n1 - n2})")

    # Problems 3-5: prices, missing prices, discounts
    df["price"] = money(df["product_price"])
    df["list_price"] = money(df["product_original_price"])
    df["min_offer_price"] = money(df["product_minimum_offer_price"])

    rejected = df[df["price"].isna()].assign(reject_reason="No price / currency (offer unavailable)")
    df = df[df["price"].notna()].copy()

    df["has_discount"] = df["list_price"].notna()
    df["list_price"] = df["list_price"].fillna(df["price"])
    df["discount_amt"] = (df["list_price"] - df["price"]).round(2)
    df["discount_pct"] = (df["discount_amt"] / df["list_price"]).round(4)
    print(f"[clean] rows kept: {len(df)} | rejected (no price): {len(rejected)}")

    # Problem 6: HTML codes and spacing in titles
    df["title"] = (df["product_title"].astype(str).map(html.unescape)
                   .str.replace("\u200b", "", regex=False)
                   .str.replace(r"\s+", " ", regex=True).str.strip())

    # Problems 7-9: sales badge -> units (lower bound)
    df["monthly_units_min"] = df["sales_volume"].map(parse_units)
    df["sales_badge_shown"] = df["monthly_units_min"].notna()
    df["monthly_units_min"] = df["monthly_units_min"].fillna(0).astype(int)
    df["sales_band"] = df["monthly_units_min"].map(sales_band)
    df["est_monthly_revenue"] = (df["price"] * df["monthly_units_min"]).round(2)

    # Problems 10-12: stock and delivery
    stock_pat = r"Only (\d+) left in stock"
    avail = df["product_availability"].astype("string")
    deliv = df["delivery"].astype("string")
    stock = avail.str.extract(stock_pat)[0].fillna(deliv.str.extract(stock_pat)[0])
    df["stock_left"] = pd.to_numeric(stock).astype("float64")
    df["is_low_stock"] = df["stock_left"].le(10).fillna(False).astype(bool)
    df["out_of_stock"] = deliv.str.contains("out of stock", case=False, na=False).astype(bool)

    d = deliv.str.replace(r"Only \d+ left in stock.*", "", regex=True).str.strip()
    df["free_delivery"] = d.str.startswith("FREE", na=False).astype(bool)
    df["delivery_fee"] = pd.to_numeric(d.str.extract(r"^\$(\d+\.\d+) delivery")[0]).fillna(0)
    df["delivery_date"] = d.map(first_date)
    df["days_to_delivery"] = (df["delivery_date"] - SNAPSHOT_DATE).dt.days
    df["fast_delivery_option"] = d.str.contains("fastest delivery", na=False).astype(bool)

    # Problem 14: coupons
    c = df["coupon_text"].astype("string")
    df["has_coupon"] = c.notna()
    df["coupon_type"] = np.select(
        [c.str.contains("%", na=False), c.str.contains(r"\$", na=False)],
        ["Percent", "Fixed $"], "No coupon")
    df["coupon_value"] = pd.to_numeric(c.str.extract(r"(\d+(?:\.\d+)?)")[0]).fillna(0)
    df["coupon_saving_usd"] = np.where(df["coupon_type"] == "Percent",
                                       df["price"] * df["coupon_value"] / 100,
                                       df["coupon_value"]).round(2)
    df["net_price_after_coupon"] = (df["price"] - df["coupon_saving_usd"]).round(2)

    # Problems 15-16: brand, channel, category from the title
    df["brand"] = df["title"].map(get_brand)
    df["seller_channel"] = df["title"].map(get_seller_channel)
    df["category"] = df["title"].map(get_category)

    mobile = df["category"].isin(["Smartphone", "Basic / Flip Phone"])
    tl = df["title"].str.lower()
    df["condition"] = np.where(tl.str.contains("renewed"), "Renewed", "New")
    df["lock_status"] = np.select(
        [~mobile, tl.str.contains(r"\bunlocked\b"), tl.str.contains(r"\blocked\b|verizon|t-mobile|tmobile|prepaid")],
        ["Not applicable", "Unlocked", "Carrier-locked"], "Not stated")
    df["is_5g"] = (mobile & tl.str.contains(r"\b5g\b")).astype(bool)
    df["storage_gb"] = np.where(df["category"] == "Smartphone", df["title"].map(storage_gb), np.nan)

    df["price_band"] = pd.cut(df["price"], PRICE_EDGES, labels=PRICE_BANDS, right=False).astype(str)

    # Problem 17: ratings blank for unrated products stay blank
    df["star_rating"] = df["product_star_rating"]
    df["is_rated"] = df["product_num_ratings"] > 0
    df["rating_band"] = (pd.cut(df["star_rating"], [0, 3.5, 4.0, 4.5, 5.01],
                                labels=["<3.5", "3.5–3.9", "4.0–4.4", "4.5–5.0"], right=False)
                         .astype(object).fillna("Not rated"))

    # Problem 13: empty / constant columns are simply not selected
    final = df.rename(columns={"product_num_ratings": "num_ratings", "product_num_offers": "num_offers"})[[
        "asin", "search_rank", "title", "brand", "category", "condition", "lock_status", "seller_channel",
        "is_5g", "storage_gb", "price", "list_price", "discount_amt", "discount_pct", "has_discount",
        "min_offer_price", "price_band", "star_rating", "rating_band", "num_ratings", "is_rated", "num_offers",
        "is_best_seller", "is_amazon_choice", "is_prime", "climate_pledge_friendly", "has_variations",
        "monthly_units_min", "sales_badge_shown", "sales_band", "est_monthly_revenue",
        "stock_left", "is_low_stock", "out_of_stock", "free_delivery", "delivery_fee", "delivery_date",
        "days_to_delivery", "fast_delivery_option",
        "has_coupon", "coupon_type", "coupon_value", "coupon_saving_usd", "net_price_after_coupon"]].copy()
    final["snapshot_date"] = SNAPSHOT_DATE.date()
    final["delivery_date"] = final["delivery_date"].dt.date
    rejected = rejected[list(raw.columns) + ["reject_reason"]]
    return final.reset_index(drop=True), rejected


# =====================================================================
# 4. Star schema for Power BI
# =====================================================================
def build_star_schema(final: pd.DataFrame) -> dict[str, pd.DataFrame]:
    dim_brand = pd.DataFrame({"brand_name": sorted(final["brand"].unique())})
    dim_brand["brand_key"] = np.arange(1, len(dim_brand) + 1)
    dim_brand["brand_tier"] = np.where(dim_brand["brand_name"].isin(MAJOR_OEM), "Major OEM",
                                       np.where(dim_brand["brand_name"] == "Generic / Unbranded",
                                                "Generic", "Challenger"))

    dim_category = pd.DataFrame({"category_name": sorted(final["category"].unique())})
    dim_category["category_key"] = np.arange(1, len(dim_category) + 1)
    dim_category["category_group"] = np.where(
        dim_category["category_name"].isin(["Smartphone", "Basic / Flip Phone"]), "Mobile handset", "Non-handset")

    dim_price_band = pd.DataFrame({
        "price_band_key": range(1, 7),
        "price_band_name": PRICE_BANDS,
        "min_price": [0, 50, 100, 200, 400, 800],
        "max_price": [49.99, 99.99, 199.99, 399.99, 799.99, 99999],
    })

    fact = final.merge(dim_brand[["brand_name", "brand_key"]], left_on="brand", right_on="brand_name", how="left") \
                .merge(dim_category[["category_name", "category_key"]], left_on="category",
                       right_on="category_name", how="left") \
                .merge(dim_price_band[["price_band_name", "price_band_key"]], left_on="price_band",
                       right_on="price_band_name", how="left")

    fact["network"] = np.where(fact["is_5g"], "5G", "4G / other")
    fact["stock_risk"] = np.select(
        [fact["is_low_stock"] & (fact["monthly_units_min"] >= 500), fact["is_low_stock"]],
        ["High risk", "Watch"], "OK")
    stock = fact["stock_left"].astype("float64")
    fact["stock_status"] = np.select(
        [(stock <= 3).to_numpy(bool), (stock <= 10).to_numpy(bool)], ["Critical", "Watch"], "")
    fact["product_short"] = np.where(fact["title"].str.len() > 60, fact["title"].str[:60] + "…", fact["title"])
    fact["review_bucket"] = pd.cut(fact["num_ratings"], [-1, 99, 999, 4999, np.inf],
                                   labels=["1. <100 reviews", "2. 100–999", "3. 1K–4.9K", "4. 5K+"]).astype(str)
    fact["review_bucket_order"] = fact["review_bucket"].str[0].astype(int)
    fact["sales_band_order"] = fact["sales_band"].str[0].astype(int)

    fact = fact.drop(columns=["brand_name", "category_name", "price_band_name"])
    for col in ["storage_gb", "stock_left", "days_to_delivery"]:   # whole numbers, blank when unknown
        fact[col] = fact[col].round().astype("Int64")

    return {"fact_listing": fact, "dim_brand": dim_brand[["brand_key", "brand_name", "brand_tier"]],
            "dim_category": dim_category[["category_key", "category_name", "category_group"]],
            "dim_price_band": dim_price_band}


# =====================================================================
# 5. Validation (mirrors 03_SQL/03_data_validation.sql)
# =====================================================================
def validate(final: pd.DataFrame, star: dict[str, pd.DataFrame]) -> list[str]:
    fact = star["fact_listing"]
    failures = []

    def check(name: str, bad: int) -> None:
        status = "PASS" if bad == 0 else "FAIL"
        print(f"[validate] {status}  {name}: {bad}")
        if bad:
            failures.append(name)

    check("V1 staged rows different from loaded rows", abs(len(final) - len(fact)))
    check("V2 duplicate ASINs", int(final["asin"].duplicated().sum()))
    check("V3 prices failing conversion", int(final["price"].isna().sum()))
    check("V4 list price below price", int((final["list_price"] < final["price"]).sum()))
    check("V4 min offer above price", int((final["min_offer_price"].fillna(0) > final["price"]).sum()))
    check("V4 rating outside 1 to 5", int(((final["star_rating"] < 1) | (final["star_rating"] > 5)).sum()))
    check("V4 rating without reviews", int((final["star_rating"].notna() & (final["num_ratings"] == 0)).sum()))
    check("V4 revenue different from price x units",
          int(((final["price"] * final["monthly_units_min"]).round(2) - final["est_monthly_revenue"]).abs()
              .gt(0.01).sum()))
    check("V5 negative delivery days", int((final["days_to_delivery"] < 0).sum()))
    check("V6 orphan brand keys", int(fact["brand_key"].isna().sum()))
    check("V6 orphan category keys", int(fact["category_key"].isna().sum()))
    check("V6 orphan price band keys", int(fact["price_band_key"].isna().sum()))
    check("V7 rows vs expected", abs(len(final) - EXPECTED["rows"]))
    check("V7 brands vs expected", abs(final["brand"].nunique() - EXPECTED["brands"]))
    check("V7 units vs expected", abs(int(final["monthly_units_min"].sum()) - EXPECTED["units"]))
    check("V7 revenue vs expected (cents)",
          int(round(abs(final["est_monthly_revenue"].sum() - EXPECTED["revenue"]) * 100)))
    return failures


def control_totals(final: pd.DataFrame, star: dict[str, pd.DataFrame]) -> None:
    fact = star["fact_listing"]
    rev = final["est_monthly_revenue"].sum()
    upl = lambda mask: final.loc[mask, "monthly_units_min"].mean()
    disc, nodisc = upl(final["has_discount"]), upl(~final["has_discount"])
    rows = [
        ("Total Listings", f"{len(final):,}"),
        ("Brands", f"{final['brand'].nunique()}"),
        ("Est Units", f"{final['monthly_units_min'].sum():,}"),
        ("Est Revenue", f"${rev:,.2f}"),
        ("Median Price", f"${final['price'].median():,.2f}"),
        ("Avg Rating", f"{final['star_rating'].mean():.2f}"),
        ("% Listings Discounted", f"{final['has_discount'].mean() * 100:.1f}%"),
        ("Samsung revenue share", f"{final.loc[final.brand == 'Samsung', 'est_monthly_revenue'].sum() / rev * 100:.1f}%"),
        ("Smartphone revenue share",
         f"{final.loc[final.category == 'Smartphone', 'est_monthly_revenue'].sum() / rev * 100:.1f}%"),
        ("Low stock listings", f"{int(final['is_low_stock'].sum())}"),
        ("High risk listings", f"{int((fact['stock_risk'] == 'High risk').sum())}"),
        ("High Risk Revenue", f"${fact.loc[fact.stock_risk == 'High risk', 'est_monthly_revenue'].sum():,.0f}"),
        ("Units per listing discounted vs not", f"{disc:.0f} vs {nodisc:.0f} ({(disc / nodisc - 1) * 100:+.0f}%)"),
    ]
    print("\nControl totals (the Power BI cards must show the same values with no filters):")
    for k, v in rows:
        print(f"  {k:<38}{v}")


# =====================================================================
# 6. Main
# =====================================================================
def main() -> int:
    parser = argparse.ArgumentParser(description="Phone market cleaning pipeline")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1],
                        help="Project root folder (contains 01_Data, 04_PowerBI)")
    args = parser.parse_args()
    root: Path = args.root

    raw_path = root / "01_Data" / "raw" / "phone_search_raw.csv"
    clean_dir = root / "01_Data" / "clean"
    pbi_dir = root / "04_PowerBI" / "data"
    clean_dir.mkdir(parents=True, exist_ok=True)
    pbi_dir.mkdir(parents=True, exist_ok=True)

    raw = load_raw(raw_path)
    profile(raw)
    final, rejected = clean(raw)
    star = build_star_schema(final)

    failures = validate(final, star)
    if failures:
        print(f"\nSTOPPED: {len(failures)} validation check(s) failed. Nothing was exported.")
        return 1

    final.to_csv(clean_dir / "phones_clean.csv", index=False, encoding="utf-8")
    rejected.to_csv(clean_dir / "rejected_rows.csv", index=False, encoding="utf-8")
    for name, table in star.items():
        table.to_csv(pbi_dir / f"{name}.csv", index=False, encoding="utf-8")

    print(f"\n[export] {clean_dir / 'phones_clean.csv'}  ({final.shape[0]} x {final.shape[1]})")
    print(f"[export] {clean_dir / 'rejected_rows.csv'}  ({len(rejected)} rows)")
    for name, table in star.items():
        print(f"[export] {pbi_dir / (name + '.csv')}  ({table.shape[0]} x {table.shape[1]})")

    control_totals(final, star)
    return 0


if __name__ == "__main__":
    sys.exit(main())
