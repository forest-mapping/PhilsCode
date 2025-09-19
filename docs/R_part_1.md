Excellent — these R scripts are basically the **data ingestion and preprocessing pipeline** that produce the FIA **direct estimates + variances** (the “design-based” inputs) that then get used in the Fay–Herriot models you saw in the paper.

Let’s go step by step and connect it to the SQL query you already examined:

---

## **1. Database Connection & Setup**

```r
library(RPostgreSQL)
drv <- dbDriver("PostgreSQL")
con <- DBI::dbConnect(drv, dbname = "fiadb")
```

* Loads the PostgreSQL driver and connects to the FIA Database (FIADB).
* If `con` doesn’t exist yet, a fallback connection is created interactively (asking for a password).

---

## **2. SQL Query Loader**

```r
readQuery <- function(x) {
  readChar(x, file.info(x)$size)
}

base_tree_query <- readQuery("tree_estn_errors_SE2017.sql")
```

* Reads the full contents of your SQL query (the one you showed earlier) into a character string.
* This will later have **placeholders substituted** (`%tree_var%`, `%by%`) before execution.

---

## **3. getEstimate() Function**

This is the key function that ties R to the SQL query.

```r
getEstimate <- function(tree_table_var = "DRYBIO_AG",
                        base_query,
                        by = "PLOT.STATECD") {
  # Replace placeholders
  query <- gsub("%by%", by, base_query)
  query <- gsub("%tree_var%", tree_table_var, query)

  # Convert biomass from pounds → tons if needed
  if (grepl("DRYBIO", tree_table_var)) {
    query <- gsub(tree_table_var, paste0(tree_table_var, " / 2000"), query)
  }

  value <- dbGetQuery(con, query)
  ...
}
```

### What it does:

* Dynamically **inserts the attribute name** (e.g., `VOLCFGRS`, `DRYBIO_AG`) into the SQL query.
* Inserts the **grouping level** (state, county, or county×surveyunit).
* Executes the SQL query on FIADB, returning a data frame with:

  * `estimate`, `var_of_estimate`, `total_plots`, etc.
* Cleans up codes into `STATECD` and `YEAR` fields.

**Connection to paper:**
This function is how the authors produce their **county-level direct estimates** of volume and biomass + sampling variance — the inputs that go into the Fay–Herriot SAE models.

---

## **4. Running Estimates at County and State Level**

```r
vol_by_fips_su <- getEstimate("VOLCFGRS", base_tree_query,
                              "PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD *0.1")

bio_by_fips_su <- getEstimate("DRYBIO_AG", base_tree_query,
                              "PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD *0.1")
```

* Runs `getEstimate()` **for every county + survey unit combination**.
* Creates two datasets:

  * `vol_by_fips_su` → county-level gross volume + variance
  * `bio_by_fips_su` → county-level biomass + variance
* Saves them as RDS files for reproducibility.

---

## **5. Organizing the Data**

```r
bio_by_fips_su$code <- as.character(
  bio_by_fips_su$`PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD *0.1` * 10
)
bio_by_fips_su$surveyunit <- str_sub(bio_by_fips_su$code, -1)
bio_by_fips_su$co_fips <- as.numeric(substr(bio_by_fips_su$code, 1, 5))
```

* Cleans up county + survey unit codes into:

  * **co\_fips** → 5-digit FIPS county code
  * **surveyunit** → FIA survey unit (for assigning mountain indicator later)

Similar transformations are applied to volume data.

---

## **6. Unit Conversion & “Long Format” Data**

```r
calc_vol_bio <- function(statecode) {
  df1 <- vol_by_fips_su %>%
    mutate(response = "Volume",
           value = VOLCFGRS * 0.0283168 / 1e6,
           var   = var_of_estimate * (0.0283168 / 1e6)^2)
  ...
  df2 <- bio_by_fips_su %>%
    mutate(response = "Biomass",
           value = DRYBIO_AG * 0.453592 / 1e6,
           var   = var_of_estimate * (0.453592 / 1e6)^2)
  ...
  rbind(df1, df2)
}
```

* Converts:

  * **Volume:** ft³ → **million m³**
  * **Biomass:** pounds → **million kg**
  * And scales variances accordingly.
* Returns a **tidy long-format dataset** with both Volume and Biomass rows.

---

## **7. Adding Mountain/Non-Mountain Indicator**

```r
mountain_codes <- read.csv("../mountain_ref.csv")
fia_estimates <- left_join(fia_estimates, mountain_codes)
```

* Joins in a survey-unit–based indicator (M = 1 for mountain units, 0 otherwise).
* This is used as an **interaction term** in the Fay–Herriot regression models (M*B5, M*B10, …).

---

## **8. Final Output**

```r
saveRDS(fia_estimates, "fia_estimates_TN_NC_VA.RDS")
```

* Saves the **county-level FIA direct estimates + variances + mountain code** in one long-format file.
* This RDS file becomes the **input to the modeling stage** (`sae` package fitting of Fay–Herriot models).

---

## **How This Fits into the Paper**

* **SQL query:** does the *design-based estimation* (compute unbiased totals + variances).
* **R wrapper (`getEstimate`) + preprocessing:** executes that query for biomass & volume, cleans the results, converts units, and organizes by county/survey unit.
* **calc\_vol\_bio() + join with mountain codes:** prepares the data in the exact shape required for the **area-level Fay–Herriot models** (direct estimates + sampling variances + predictors like mountain indicator).

In other words, **these scripts are the “data preparation” pipeline**. After this, the next step is fitting the SAE models (`lm()` + `sae::eblupFH()`) using CHM-derived predictors.





Perfect — these two scripts are the **remote sensing data processing pipeline** that builds the predictors for the Fay–Herriot models. Together, they do for the CHMs what the SQL/R pipeline did for FIA plot data: they turn raw spatial data into **county-level predictor variables**.

Let’s break them down carefully.

---

## **Script 1: `Extract_County_CHM_NAIP_serial.R`**

### **Purpose**

* Take **NAIP-derived canopy height models (CHMs)** (already precomputed per state, 10 m grid).
* Apply two masks:

  1. **GEDI mask:** keeps only areas where GEDI CHM > 0 (forested/vegetated areas from GEDI).
  2. **NLCD forest mask:** keeps only NLCD classes 41–43 (forest) and 90 (woody wetlands).
* Output **county-level masked CHM rasters** for each mask type (saved to disk).

### **Key Steps**

1. **Setup & Inputs**

   * Paths for NAIP CHM, GEDI CHM, NLCD, county shapefiles.
   * Takes the state name as a command-line argument.
   * Loads FIA county reference table (to cross-walk between county names and FIA codes).

2. **Loop over counties**

   * For each county in the target state:

     * Read the NAIP CHM (unmasked).
     * Read corresponding GEDI CHM and NLCD mask.
     * Reproject GEDI and NLCD rasters to match the NAIP CHM CRS and resolution (10 m).
     * Resample them to align pixel grids.

3. **Apply Masks**

   * **GEDI mask:**
     Sets NAIP CHM cells to NA if GEDI CHM cell is NA, and sets them to 0 if GEDI cell is 0.
   * **NLCD mask:**
     Same as above but using NLCD forest mask.

4. **Write Outputs**

   * Save masked NAIP CHM rasters to separate directories (`CHM/GEDI/` and `CHM/NLCD/`).
   * Save PNG previews for QC.

**In context:**
This script produces the **NAIP\_noWater, NAIP\_GFCHM, and NAIP\_NLCD** predictor layers used in the paper. These layers are then summarized by county to produce 5 m height class proportions — the B5, B10, … predictor variables in the Fay–Herriot model.

---

## **Script 2: (Second block you pasted)**

This script is similar but focused on **GEDI-derived CHM** itself, not NAIP.

### **Purpose**

* Tabulate **GEDI CHM height distributions** (with and without NLCD forest mask) by county.
* Create predictor variables (area per height class) for SAE models.

### **Key Steps**

1. **Setup & Inputs**

   * Loads US county shapefile, FIA county table, FIA survey unit table, state reference table.
   * Sets paths to GEDI CHM rasters (`default` = all land, `NLCD` = forested land only).
   * Takes state abbreviation as command-line argument.

2. **County Loop: Default GEDI CHM**

   * For each county:

     * Read its GEDI CHM raster (30 m resolution).
     * Set values > 100 m to NA (remove artifacts/water).
     * **Bin canopy height into 5 m classes:** 0–5, 5–10, 10–15, … 30–35 m.
     * Count number of pixels in each bin.
     * Convert counts → km² (each 30 m pixel = 900 m²).
     * Record STATECD, COUNTYCD, county name, and bin.

3. **Output**

   * Combine all counties’ data into a single table (`chm_dist`).
   * Write to CSV (`CHM_dist_by_county.csv`).

4. **Repeat for NLCD-masked GEDI CHM**

   * Same process as above but using CHM already masked to NLCD forest classes.
   * Produces a parallel CSV of county-level height class areas.

---

## **What These Scripts Produce**

After running these two scripts for all states of interest, you end up with:

* **For NAIP:**
  County-level CHM rasters (masked and unmasked).
* **For GEDI:**
  County-level CHM *bin tables* (area in km² per 5 m height class).
* These tables become **predictor variables** (B5, B10, …) in the Fay–Herriot model.

For example, a row for a county might look like:

| STATECD | COUNTYCD | BIN\_HT | km2   |
| ------- | -------- | ------- | ----- |
| 47      | 001      | 0       | 50.3  |
| 47      | 001      | 5       | 102.7 |
| 47      | 001      | 10      | 87.1  |
| ...     | ...      | ...     | ...   |

Then in modeling, they are pivoted wide:

| COUNTY | B5    | B10  | B15 | ... |
| ------ | ----- | ---- | --- | --- |
| 47001  | 102.7 | 87.1 | ... |     |

so that `B5`, `B10`, etc. can enter the regression model as area proportions.

---

## **Connection to the Paper**

These two scripts are **Step 2 of the SAE workflow**:

1. **Step 1 (earlier scripts):** Produce FIA direct estimates + variances.
2. **Step 2 (these scripts):** Produce county-level auxiliary variables from remote sensing (CHM height class proportions).
3. **Step 3 (next scripts):** Merge the two datasets and fit Fay–Herriot models (`sae::eblupFH()`), yielding EBLUPs and comparing precision gains for NAIP vs GEDI.

---

Would you like me to explain **the model-fitting step itself** (Fay–Herriot modeling, EBLUP calculation, model selection using AIC, Wald χ², etc.) if you have those R scripts? That’s where everything comes together and produces the results/precision gains from the paper.
