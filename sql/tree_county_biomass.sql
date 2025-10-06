LOAD sqlite;
ATTACH IF NOT EXISTS './data/FS_FIADB.db' (type sqlite); 
USE FS_FIADB;

--COPY (


SELECT eval_grp,
       grp_by_attrib,
 sum(estimate_by_estn_unit.estimate) estimate,
 CASE
     WHEN sum(estimate_by_estn_unit.estimate) <> 0
     THEN abs(sqrt(sum(estimate_by_estn_unit.var_of_estimate)) /
          sum(estimate_by_estn_unit.estimate) * 100)
     ELSE 0
 END AS se_of_estimate_pct,
 sqrt(sum(estimate_by_estn_unit.var_of_estimate)) se_of_estimate,
 sum(estimate_by_estn_unit.var_of_estimate) var_of_estimate,
 sum(estimate_by_estn_unit.total_plots) total_plots,
 sum(estimate_by_estn_unit.non_zero_plots) non_zero_plots,
 sum(estimate_by_estn_unit.tot_pop_area_acres) tot_pop_ac
FROM
  (SELECT pop_eval_grp_cn,
          eval_grp,
          eval_grp_descr,
          SUM(COALESCE(CAST(ysum_hd AS DOUBLE), 0) * phase_1_summary.expns) estimate,
          phase_1_summary.n total_plots,
          SUM(phase_summary.number_plots_in_domain) domain_plots,
          SUM(phase_summary.non_zero_plots) non_zero_plots,
          total_area * total_area / phase_1_summary.n *
          ((SUM(w_h * phase_1_summary.n_h * (((coalesce(CAST(ysum_hd_sqr AS DOUBLE), 0) /
          phase_1_summary.n_h) - ((COALESCE(CAST(ysum_hd AS DOUBLE), 0) /
          phase_1_summary.n_h) * (COALESCE(CAST(ysum_hd AS DOUBLE), 0) /
          phase_1_summary.n_h))) / (phase_1_summary.n_h - 1)))) + 1 /
          phase_1_summary.n * (SUM((1 - w_h) * phase_1_summary.n_h *
          (((coalesce(CAST(ysum_hd_sqr AS DOUBLE), 0) / phase_1_summary.n_h) -
          ((COALESCE(CAST(ysum_hd AS DOUBLE), 0) / phase_1_summary.n_h) * (COALESCE(CAST(ysum_hd AS DOUBLE), 0) /
          phase_1_summary.n_h))) / (phase_1_summary.n_h - 1))))) var_of_estimate,
          total_area tot_pop_area_acres,
          grp_by_attrib
   FROM
     (SELECT PEV.cn eval_cn,
             PEG.eval_grp,
             PEG.eval_grp_descr,
             PEG.cn pop_eval_grp_cn,
             POP_STRATUM.estn_unit_cn,
             POP_STRATUM.expns,
             POP_STRATUM.cn pop_stratum_cn,
             POP_STRATUM.STATECD,
             p1pointcnt /
        (SELECT sum(str.p1pointcnt)
         FROM FS_FIADB.pop_stratum STR
         WHERE str.estn_unit_cn = pop_stratum.estn_unit_cn) w_h,

        (SELECT sum(str.p1pointcnt)
         FROM FS_FIADB.pop_stratum STR
         WHERE str.estn_unit_cn = pop_stratum.estn_unit_cn) n_prime,
             p1pointcnt n_prime_h,

        (SELECT sum(eu_s.area_used)
         FROM FS_FIADB.pop_estn_unit eu_s
         WHERE eu_s.cn = pop_stratum.estn_unit_cn) total_area,

        (SELECT sum(str.p2pointcnt)
         FROM FS_FIADB.pop_stratum STR
         WHERE str.estn_unit_cn = pop_stratum.estn_unit_cn) n,
             POP_STRATUM.p2pointcnt n_h
      FROM FS_FIADB.POP_EVAL_GRP PEG
      JOIN FS_FIADB.POP_EVAL_TYP PET ON (PET.EVAL_GRP_CN = PEG.CN)
      JOIN FS_FIADB.POP_EVAL PEV ON (PEV.CN = PET.EVAL_CN)
      JOIN FS_FIADB.POP_ESTN_UNIT PEU ON (PEV.CN = PEU.EVAL_CN)
      JOIN FS_FIADB.POP_STRATUM POP_STRATUM ON (PEU.CN = POP_STRATUM.ESTN_UNIT_CN)
      WHERE (PEG.EVAL_GRP = 372017)
            -- OR PEG.EVAL_GRP = 472017
            -- OR PEG.EVAL_GRP = 512017)
        AND PET.eval_typ = 'EXPVOL') phase_1_summary

   LEFT OUTER JOIN
     (SELECT pop_stratum_cn,
             estn_unit_cn,
             eval_cn,
             sum(y_hid_adjusted) ysum_hd,
             sum(y_hid_adjusted * y_hid_adjusted) ysum_hd_sqr,
             count(*) number_plots_in_domain,
             SUM(CASE y_hid_adjusted
                     WHEN 0 THEN 0
                     WHEN NULL THEN 0
                     ELSE 1
                 END) non_zero_plots,
             grp_by_attrib
      FROM
        (SELECT pop_stratum.cn AS pop_stratum_cn,
                peu.cn AS estn_unit_cn,
                pev.cn AS eval_cn,
                SUM((COALESCE(COALESCE(CAST(TREE.DRYBIO_AG AS DOUBLE), 0) *
                TREE.TPA_UNADJ *
                CASE
                WHEN TREE.DIA IS NULL THEN POP_STRATUM.ADJ_FACTOR_SUBP
                ELSE
                CASE LEAST(TREE.DIA, 5 - 0.001)
                WHEN TREE.DIA THEN POP_STRATUM.ADJ_FACTOR_MICR
                ELSE
                CASE LEAST(TREE.DIA, COALESCE(CAST(PLOT.MACRO_BREAKPOINT_DIA AS DOUBLE), 9999) - 0.001)
                WHEN TREE.DIA THEN CAST(POP_STRATUM.ADJ_FACTOR_SUBP AS DOUBLE)
                ELSE CAST(POP_STRATUM.ADJ_FACTOR_MACR AS DOUBLE)
                END
                END
                END, 0))) AS y_hid_adjusted,
PLOT.COUNTYCD AS grp_by_attrib
         FROM FS_FIADB.POP_EVAL_GRP PEG
         JOIN FS_FIADB.POP_EVAL_TYP PET ON (PET.EVAL_GRP_CN = PEG.CN)
         JOIN FS_FIADB.POP_EVAL PEV ON (PEV.CN = PET.EVAL_CN)
         JOIN FS_FIADB.POP_ESTN_UNIT PEU ON (PEV.CN = PEU.EVAL_CN)
         JOIN FS_FIADB.POP_STRATUM POP_STRATUM ON (PEU.CN = POP_STRATUM.ESTN_UNIT_CN)
         JOIN FS_FIADB.POP_PLOT_STRATUM_ASSGN ON (POP_PLOT_STRATUM_ASSGN.STRATUM_CN = POP_STRATUM.CN)
         JOIN FS_FIADB.PLOT ON (POP_PLOT_STRATUM_ASSGN.PLT_CN = PLOT.CN)
         JOIN FS_FIADB.PLOTGEOM ON (PLOT.CN = PLOTGEOM.CN)
         JOIN FS_FIADB.COND ON (COND.PLT_CN = PLOT.CN)
         JOIN FS_FIADB.TREE ON (TREE.PLT_CN = COND.PLT_CN
                                AND TREE.CONDID = COND.CONDID)
         WHERE TREE.STATUSCD = 1
           AND COND.COND_STATUS_CD = 1
           AND PET.EVAL_TYP = 'EXPVOL'
           AND (PEG.EVAL_GRP = 372017)
             --OR PEG.EVAL_GRP = 472017
             --OR PEG.EVAL_GRP = 512017)
           AND 1 = 1
         GROUP BY peu.cn,
                  pev.cn,
                  pop_stratum.cn,
                  plot.cn,
                  PLOT.STATECD,
                  PLOT.COUNTYCD) plot_summary
      GROUP BY pop_stratum_cn,
               estn_unit_cn,
               eval_cn,
               grp_by_attrib) phase_summary ON (phase_1_summary.pop_stratum_cn = phase_summary.pop_stratum_cn
                                                AND phase_1_summary.eval_cn = phase_summary.eval_cn
                                                AND phase_1_summary.estn_unit_cn = phase_summary.estn_unit_cn)
   GROUP BY phase_1_summary.pop_eval_grp_cn,
            phase_1_summary.eval_grp,
            phase_1_summary.eval_grp_descr,
            phase_1_summary.estn_unit_cn,
            phase_1_summary.total_area,
            phase_1_summary.n,
            grp_by_attrib) estimate_by_estn_unit
WHERE non_zero_plots IS NOT NULL
GROUP BY pop_eval_grp_cn,
         eval_grp,
         eval_grp_descr,
         grp_by_attrib
ORDER BY grp_by_attrib

--) TO 'output_COUNTY_BIOMASS.csv' (HEADER);