#' Run dose reduction analysis
#'
#' @details
#' This function will calculate the dose reduction outcomes.
#'
#' @param connectionDetails    An object of type \code{connectionDetails} as created using the
#'                             \code{\link[DatabaseConnector]{createConnectionDetails}} function in the
#'                             DatabaseConnector package.
#' @param cdmDatabaseSchema    Schema name where your patient-level data in OMOP CDM format resides.
#'                             Note that for SQL Server, this should include both the database and
#'                             schema name, for example 'cdm_data.dbo'.
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param outputFolder         Name of local folder where the results were generated; make sure to use forward slashes
#'                             (/). Do not use a folder on a network drive since this greatly impacts
#'                             performance.
#' @export



runDoseReduction <- function(connectionDetails,
                             cdmDatabaseSchema,
                             cohortDatabaseSchema,
                             cohortTable,
                             outputFolder) {
  DoseReductionFolder <- file.path(outputFolder, "DoseReduction")
  if (!file.exists(DoseReductionFolder)) {
    dir.create(DoseReductionFolder)
  }
  
  # Helper function to perform analysis for a given duration (3-month or 6-month)
  analyzeDoseReduction <- function(duration, prefix, type) {
    ParallelLogger::logInfo(paste0("Comparing cumulative steroid dose reduction (", duration, ", ", type, ")\n"))
    
    # Query for both Omalizumab and Dupilumab data
    query_oma <- paste0("SELECT * FROM ", cohortDatabaseSchema, ".", cohortTable, "_Oma", prefix)
    df_oma <- querySql(conn, query_oma)
    
    query_dupi <- paste0("SELECT * FROM ", cohortDatabaseSchema, ".", cohortTable, "_Dupi", prefix)
    df_dupi <- querySql(conn, query_dupi)
    
    # Compute reduction percentage and groupings for Omalizumab and Dupilumab
    categorizeDoseReduction <- function(df) {
      df %>%
        mutate(reduction_percentage = case_when(
          TOTAL_CUMULATIVE_DOSE_PRIOR == 0 ~ NA_real_, 
          TRUE ~ 100 * TOTAL_CUMULATIVE_DOSE_AFTER / TOTAL_CUMULATIVE_DOSE_PRIOR
        ),
        reduction_group = case_when(
          TOTAL_CUMULATIVE_DOSE_PRIOR == 0 ~ "no prior use", 
          TOTAL_CUMULATIVE_DOSE_AFTER == 0 ~ "stop use",
          TOTAL_CUMULATIVE_DOSE_AFTER <= TOTAL_CUMULATIVE_DOSE_PRIOR * 0.25 ~ "75% or more",
          TOTAL_CUMULATIVE_DOSE_AFTER <= TOTAL_CUMULATIVE_DOSE_PRIOR * 0.5 ~ "50% or more, below 75%",
          TOTAL_CUMULATIVE_DOSE_AFTER <= TOTAL_CUMULATIVE_DOSE_PRIOR * 0.75 ~ "25% or more, below 50%",
          TOTAL_CUMULATIVE_DOSE_AFTER < TOTAL_CUMULATIVE_DOSE_PRIOR ~ "below 25%",
          TOTAL_CUMULATIVE_DOSE_AFTER >= TOTAL_CUMULATIVE_DOSE_PRIOR ~ "no change or up"
        )) %>%
        mutate(reduction_group = factor(reduction_group, 
                                        levels = c("no prior use", "stop use", 
                                                   "75% or more", "50% or more, below 75%", 
                                                   "25% or more, below 50%", "below 25%", 
                                                   "no change or up")))
    }
    
    df_oma <- categorizeDoseReduction(df_oma)
    df_dupi <- categorizeDoseReduction(df_dupi)
    
    nona_oma <- df_oma %>% filter(!is.na(reduction_percentage))
    nona_dupi <- df_dupi %>% filter(!is.na(reduction_percentage))
    
    # Perform statistical analysis if there is enough data
    if (nrow(nona_oma) >= 2 & nrow(nona_dupi) >= 2) {
      grouped_oma <- nona_oma %>%
        group_by(reduction_group) %>%
        summarise(count = n())
      
      grouped_dupi <- nona_dupi %>%
        group_by(reduction_group) %>%
        summarise(count = n())
      
      wilcox_result <- wilcox.test(nona_oma$reduction_percentage, nona_dupi$reduction_percentage, alternative = "two.sided")
      
      r_table_oma <- table(nona_oma$reduction_group)
      r_table_dupi <- table(nona_dupi$reduction_group)
      
      contingency_table <- rbind(Omalizumab = r_table_oma, Dupilumab = r_table_dupi)
      
      # Log and remove categories with zero counts across both groups
      zero_count_columns <- which(colSums(contingency_table) == 0)
      
      if (length(zero_count_columns) > 0) {
        removed_categories <- colnames(contingency_table)[zero_count_columns]
        removed_categories <- removed_categories[removed_categories != "no prior use"]
        
        if (length(removed_categories) > 0) {
          ParallelLogger::logInfo(paste("Removed categories due to zero counts:", paste(removed_categories, collapse = ", ")))
        }
        
        contingency_table <- contingency_table[, colSums(contingency_table) > 0]
      }
      
      expected <- chisq.test(contingency_table, simulate.p.value = TRUE, B = 2000)$expected
      
      chi_or_fisher_result <- if (any(expected < 5)) {
        ParallelLogger::logInfo("Using Fisher's exact test because some expected frequencies are below 5\n")
        fisher.test(contingency_table)
      } else {
        ParallelLogger::logInfo("Using Chi-squared test because all expected frequencies are 5 or more\n")
        chisq.test(contingency_table)
      }
    } else {
      ParallelLogger::logInfo("Failed due to insufficient size\n")
      return(NULL)
    }
    
    # Save results
    ParallelLogger::logInfo("Saving results")
    write.csv(df_oma, file = file.path(DoseReductionFolder, paste0(prefix, "_Omalizumab.csv")), row.names = TRUE)
    write.csv(df_dupi, file = file.path(DoseReductionFolder, paste0(prefix, "_Dupilumab.csv")), row.names = TRUE)
    
    saveRDS(contingency_table, file = file.path(DoseReductionFolder, paste0("contingency_table_", prefix, ".rds")))
    saveRDS(wilcox_result, file = file.path(DoseReductionFolder, paste0("wilcox_", prefix, ".rds")))
    saveRDS(chi_or_fisher_result, file = file.path(DoseReductionFolder, paste0("fisher_or_chi_", prefix, ".rds")))
    }
  
  # Perform 3-month analysis for pediatric population
  analyzeDoseReduction("3month", "Ped3", "Pediatric")
  
  # Perform 6-month analysis for pediatric population
  analyzeDoseReduction("6month", "Ped6", "Pediatric")
  
  # Perform 3-month analysis for population of all ages
  analyzeDoseReduction("3month", "All3", "All ages")
  
  # Perform 6-month analysis for population of all ages
  analyzeDoseReduction("6month", "All6", "All ages")
}

