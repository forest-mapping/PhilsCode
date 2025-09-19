This is the output from ChatGPT (who could see all the code and paper summary) when asked to break it down into a series of repeatable steps.  

---

## **Modular Workflow for FH Small-Area Estimation with Remote-Sensing Covariates**

### **Step 1 – Connect to Database and Extract FIA Direct Estimates**

**Inputs:**

* FIA database (PostgreSQL)
* SQL query templates (`tree_estn_errors_SE2017.sql`)

**Processing:**

* Connect to FIA database.
* Run parameterized SQL queries for **Volume (VOLCFGRS)** and **Biomass (DRYBIO\_AG)**.
* Aggregate by state/county/survey unit.
* Convert units (ft³ → m³, pounds → kg).
* Compute sampling variances.

**Outputs:**

* `bio_by_fips_su.RDS`
* `vol_by_fips_su.RDS`

These are the design-based direct estimates + variances.

---

### **Step 2 – Prepare FIA County-Level Long Dataset**

**Inputs:**

* `bio_by_fips_su.RDS`, `vol_by_fips_su.RDS`
* Mountain indicator table (`mountain_ref.csv`)

**Processing:**

* Merge biomass and volume into long format with a `response` column.
* Attach mountain codes and survey unit indicators.
* Standardize state and county FIPS codes.

**Outputs:**

* `fia_estimates_<states>.RDS`
  (long-format table: state, county, survey unit, response, value, variance)

---

### **Step 3 – Compute CHM Distributions (for Each Source)**

**Inputs:**

* CHM raster tiles per county per source
  (`NAIP_noWater`, `NAIP_GEDI`, `NAIP_NLCD`, `GEDI_default`, `GEDI_NLCD`)
* County shapefiles (`USCounties.shp`)

**Processing:**

* For each county, tabulate CHM pixels into bins (0–5 m, 5–10 m, …).
* Compute area (km²) per bin.
* Output a table per source with bin areas.

**Outputs:**

* `CHM_dist_by_county.csv` for each source/state.

---

### **Step 4 – Merge FIA and CHM Predictors**

**Inputs:**

* FIA long dataset (Step 2)
* CHM distributions (Step 3)

**Processing:**

* Reshape CHM distributions to wide format (bins as columns).
* Merge CHM predictors with FIA estimates by county.
* Optionally add interaction variables (e.g., M × B5).

**Outputs:**

* `FIA_GEDI_for_Fay-Herriot.RDS` (GEDI sources)
* `FIA_NAIP_for_Fay-Herriot.RDS` (NAIP sources)
* Optionally, one combined file: `FIA_for_FH.RDS`

---

### **Step 5 – All-Subsets Model Search**

**Inputs:**

* Combined modeling dataset (Step 4)

**Processing:**

* For each (State × Source × Response):

  * Generate all predictor combinations up to size *p*.
  * Fit Fay–Herriot model with `eblupFH_3`.
  * Record AIC, p-values, convergence status.
  * Select top *k* models by AIC (with all predictors significant).

**Outputs:**

* `best_<state>_<source>_<response>.RDS` (best model formula)
* Summary table: `Best_models.csv`

---

### **Step 6 – Refit Best Models and Compute Diagnostics**

**Inputs:**

* Best model formulas (Step 5)
* Modeling dataset (Step 4)

**Processing:**

* Refit using `eblupFH_3` with higher iteration cap.
* Extract AIC, reference variance, coefficients.
* Compute model diagnostics.

**Outputs:**

* `Best_model_coeficients.csv` (long format)
* `Best_model_coeficients_wide.csv` (wide format)
* Diagnostic plots (AIC barplots, refvar plots)

---

### **Step 7 – Compute EBLUPs and MSEs**

**Inputs:**

* Best model formulas (Step 5)
* Modeling dataset (Step 4)

**Processing:**

* Compute EBLUPs (model-based county estimates).
* Compute MSE and SER for each county.
* Compute residuals and synthetic predictions.

**Outputs:**

* `Best_model_EBLUPs.csv` (direct + EBLUP + SE + residuals)
* `Best_model_SERs.csv` (summary by state/source/response)

---

### **Step 8 – Visualization and Diagnostics**

**Inputs:**

* EBLUP outputs (Step 7)
* Coefficient outputs (Step 6)

**Processing:**

* Plot EBLUP vs direct estimates (shrinkage plots).
* Plot residuals by direct estimate (check for bias).
* Plot relative efficiencies (SER < 1 check).
* Barplots of coefficient frequency.

**Outputs:**

* Figures in `/Results/Plots` directory.
* Can be regenerated without re-running earlier steps.

---

### **Step 9 – Reporting / Integration**

**Inputs:**

* All CSV/RDS outputs from steps 2–8

**Processing:**

* Summarize improvements in precision (SER, RE).
* Compare sources (GEDI vs NAIP) and mask types.
* Produce publication-ready tables and graphics.

**Outputs:**

* Final tables for manuscript/report
* Exportable charts (PNG, PDF, etc.)

---

## **Why This Design Works**

* Each step produces **fully serializable outputs**.
* Each step has **well-defined inputs**, so you can re-run from any step without recomputing everything.
* Makes it easy to swap:

  * **Different data sources** (e.g., lidar-derived CHM, Sentinel canopy cover).
  * **Different estimators** (Fay–Herriot → robust FH → unit-level SAE models).
* Parallelizable: Steps 3, 5, and 7 can be run per state or per response in parallel.

---

I think these steps are a reasonable set of blocks to implement.  I think that some of these are probably too big - some should be separate blocks for the system.  For example, some of the visualization of outputs can be separated from the calculation of said output (or it can be a feature flag, so that is a choice).

However, there are some challenges about the exact way the code should be implemented to make it flexible for use on other approaches.  