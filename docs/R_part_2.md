Great — now we’re looking at the **final data assembly step** before model fitting. This script does two major things:

1. **Tabulates county-level CHM distributions** for NAIP (noWater, GEDI-masked, NLCD-masked) — just like the earlier GEDI script did for GEDI CHM.
2. **Merges those CHM summaries with FIA direct estimates + variances** to produce the combined modeling dataset used in the Fay–Herriot models.

Let’s break it down carefully.

---

## **Part 1: Tabulate NAIP CHM Height Distributions**

This section mirrors what we saw earlier for GEDI CHM, but now it’s applied to NAIP-derived CHM rasters.

### **Setup**

* Loads county shapefiles, FIA reference tables, state code lookup.
* Reads state argument (e.g. `TN`, `VA`, `NC`).
* Sets paths for NAIP CHMs:

  * `noWater` (just removes water pixels)
  * `GEDI` (masked to GEDI canopy coverage)
  * `NLCD` (masked to forest land-cover classes)

### **Loop Over Counties**

For each county in the state:

1. **Read CHM raster** for the chosen mask.
2. **Bin pixel heights** into 5 m classes:

   ```
   0–5, 5–10, 10–15, 15–20, 20–25, 25–30, 30–35
   ```
3. **Tabulate frequency** of pixels in each bin.
4. Convert pixel counts → area (km²):

   * NAIP CHM resolution is 10 m → each pixel = 100 m² → area = count × 100 ÷ 1e6.

### **Output**

* Combines all counties into a single data frame (`chm_dist`).
* Writes CSV: `CHM_dist_by_county.csv` (one per mask, per state).

These CSVs are the *predictor variable source tables* for the SAE models.

---

## **Part 2: Tabulate GEDI and NLCD-Masked NAIP CHM**

The script then repeats the same procedure for:

* **GEDI-masked NAIP CHM**
* **NLCD-masked NAIP CHM**

This yields three parallel CSV files per state:

* `noWater` (minimal filtering)
* `GEDI` (pixel-level mask based on GEDI coverage)
* `NLCD` (mask based on land cover classification)

---

## **Part 3: Merge CHM Predictors with FIA Direct Estimates**

Now comes the **critical modeling dataset construction** step.

### **Load FIA Direct Estimates**

```r
FIA_est_fn <- dir(path_RDS, pattern = "^fia_estimates.*.RDS$")
FIA_estimates <- do.call(rbind, lapply(FIA_est_fn, function(x) readRDS(file.path(path_RDS, x)))) %>%
  mutate(STATECD = as.integer(STATECD)) %>%
  rename(COUNTY_FIPS = co_fips)
```

* Reads previously computed county-level FIA estimates + variances.
* Harmonizes key columns.

### **Load and Pivot CHM Distributions**

For each state, two separate `calc_chm()` functions are defined:

#### **1. GEDI CHM**

```r
df1 <- read.csv(...GEDI default...) %>% mutate(SOURCE="GEDI_default")
df2 <- read.csv(...GEDI NLCD...)   %>% mutate(SOURCE="GEDI_NLCD")
df  <- rbind(df1, df2) %>% pivot_wider(names_from=BIN_HT, values_from=km2)
```

* Reads county-level GEDI CHM distribution tables (default and NLCD-filtered).

* Pivots them into wide format:
  \| COUNTY\_FIPS | SOURCE | `0` | `5` | `10` | `15` | ... |
  so each column is the area (km²) of that bin height class.

* Creates **one row per county per CHM type**.

* Joins with FIA direct estimates → creates `FIA_GEDI` dataset.

#### **2. NAIP CHM**

Exactly the same, but with:

* `NAIP_noWater`
* `NAIP_GEDI`
* `NAIP_NLCD`

→ Creates `FIA_NAIP` dataset.

---

## **Part 4: Save the Modeling Dataset**

Finally, all these are saved for downstream modeling:

```r
saveRDS(FIA_GEDI, "/data/GEDI/FIA_GEDI_for_Fay-Herriot.RDS")
saveRDS(FIA_NAIP, "/data/NAIP/FIA_GEDI_for_Fay-Herriot.RDS")
saveRDS(rbind(FIA_GEDI, FIA_NAIP),
        "/data/FIADB/RDS/FIA_GEDI_for_Fay-Herriot.RDS")
```

This is the **final input file** used in the model-fitting stage. Each row now contains:

* County ID
* Direct estimate (`value`) and its sampling variance (`var`)
* CHM-derived predictor variables (area per height bin)
* SOURCE label (GEDI/NAIP, default or filtered)

---

## **Why This Matters for the Paper**

This script represents **Step 3 in the analysis pipeline**:

1. **SQL + R Step:** Compute unbiased county-level FIA direct estimates + variances.
2. **Raster Processing Step:** Summarize CHM height distributions by county for NAIP and GEDI.
3. **Merge Step (this script):** Create a single “modeling table” with:

   * Response = FIA estimate
   * Known sampling variance
   * Predictors = canopy height class areas
   * Optional covariates (mountain code, etc.)
4. **Next Step:** Fit Fay–Herriot models (EBLUPs) using `sae::eblupFH()` or equivalent.

---

### **Summary Table of This Step**

| **Step**       | **Input**                           | **Output**                       | **Purpose**                                   |
| -------------- | ----------------------------------- | -------------------------------- | --------------------------------------------- |
| CHM tabulation | NAIP/NAIP-masked rasters            | County-level km² per height bin  | Converts high-res raster data into predictors |
| FIA merge      | FIA estimates (direct) + CHM tables | `FIA_GEDI` & `FIA_NAIP` datasets | Assembles model-ready table                   |
| Save           | RDS files                           | Modeling datasets                | Used as input to FH SAE models                |

---

Would you like me to go through the **actual Fay–Herriot model-fitting code** (likely in a later script — look for `sae::eblupFH()`, `lm()`, or AIC/Wald test code)? That’s where they fit models with different CHM sources, compare precision gains, and produce the results summarized in the paper.






