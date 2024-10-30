WITH 
cohort as (
	select * 
	from @target_database_schema.@target_cohort_table
	where cohort_definition_id = 1385
	), 
Tdrug as (
    select T2.SUBJECT_ID, 
	       T2.cohort_start_date,
           T1.drug_exposure_start_date, 
           T1.drug_exposure_end_date,
	       T1.drug_concept_id,
	       T3.concept_name,
	       T1.route_source_value,
	       T4.ancestor_concept_id,
	       T5.concept_name as ingredient_name,
	       T1.quantity,
	       T1.days_supply, 
	       T1.dose_unit_source_value
    from @cdm_database_schema.DRUG_EXPOSURE T1
    join cohort T2 on T1.person_id = T2.SUBJECT_ID 
    join @cdm_database_schema.CONCEPT T3 on T1.drug_concept_id = T3.concept_id
    join @cdm_database_schema.CONCEPT_ANCESTOR T4 on T1.drug_concept_id = T4.descendant_concept_id 
    join @cdm_database_schema.CONCEPT T5 on T4.ancestor_concept_id = T5.concept_id 
    join @target_database_schema.@target_cohort_table_steroidlist T6 on T5.concept_name = T6.Drug_Name 
    where T5.concept_class_id = 'ingredient' 
          and T1.drug_exposure_end_date >= DATEADD(day, -180, T2.cohort_start_date) 
          and T1.drug_exposure_start_date < DATEADD(day, 180, T2.cohort_start_date)
	), 
Tdate as (
    select SUBJECT_ID, 
           cohort_start_date, 
		   drug_exposure_start_date AS drug_exposure_date, 
		   drug_exposure_end_date, 
		   ingredient_name,
		   quantity	
    from Tdrug
    union all
    select SUBJECT_ID, 
           cohort_start_date, 
	       DATEADD(day, 1, drug_exposure_date), 
	       drug_exposure_end_date, 
	       ingredient_name,
	       quantity
    from Tdate
    where drug_exposure_date < drug_exposure_end_date
    ), 
Tcumul as (
    select SUBJECT_ID,
           cohort_start_date,
           ingredient_name,
           sum(case 
                 when drug_exposure_date >= DATEADD(day, -180, cohort_start_date) 
                      and drug_exposure_date < cohort_start_date then quantity
                 else 0 
               end) as cumulative_dose_prior,
           sum(case 
                 when drug_exposure_date >= cohort_start_date 
                      and drug_exposure_date < DATEADD(day, 180, cohort_start_date) then quantity
                 else 0 
               end) as cumulative_dose_after
    from Tdate
    group by SUBJECT_ID, 
             cohort_start_date, 
             ingredient_name 
    )
SELECT * INTO @target_database_schema.@target_cohort_table_DupiAll6_temp FROM Tcumul
OPTION (MAXRECURSION 5000);
SELECT distinct SUBJECT_ID,
       cohort_start_date,
	   sum(cumulative_dose_prior*case 
	              when ingredient_name = 'prednisolone' then 1
                  when ingredient_name = 'prednisone' then 1
	              when ingredient_name = 'deflazacort' then 5/7.5
				  when ingredient_name = 'hydrocortisone' then 5/20
				  when ingredient_name = 'cortisone' then 5/25
				  when ingredient_name = 'methylprednisolone' then 5/4
				  when ingredient_name = 'triamcinolone' then 5/4
				  when ingredient_name = 'dexamethasone' then 5/0.75
				  when ingredient_name = 'betamethasone' then 5/0.6
				  end) as total_cumulative_dose_prior,
	   sum(cumulative_dose_after*case 
	              when ingredient_name = 'prednisolone' then 1
                  when ingredient_name = 'prednisone' then 1
	              when ingredient_name = 'deflazacort' then 5/7.5
				  when ingredient_name = 'hydrocortisone' then 5/20
				  when ingredient_name = 'cortisone' then 5/25
				  when ingredient_name = 'methylprednisolone' then 5/4
				  when ingredient_name = 'triamcinolone' then 5/4
				  when ingredient_name = 'dexamethasone' then 5/0.75
				  when ingredient_name = 'betamethasone' then 5/0.6
				  end) as total_cumulative_dose_after
INTO @target_database_schema.@target_cohort_table_DupiAll6
FROM @target_database_schema.@target_cohort_table_DupiAll6_temp
GROUP BY SUBJECT_ID, 
         cohort_start_date;
DROP TABLE @target_database_schema.@target_cohort_table_DupiAll6_temp;