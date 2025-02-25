#renv::status()
#renv::restore()

library(BiologicsCDMnew)
#Sys.setlocale(category = "LC_ALL", locale = "english")

# Optional: specify where the temporary files (used by the Andromeda package) will be created:
options(andromedaTempFolder = "C:/andromedaTemp")

# Maximum number of cores to be used:
maxCores <- parallel::detectCores()

# The folder where the study intermediate and result files will be written:
outputFolder <- ""

# Details for connecting to the server:
connectionDetails <- DatabaseConnector::createConnectionDetails(dbms = "sql server",
                                                                user = "",
                                                                password = "",
                                                                server = "")
conn <- connect(connectionDetails)

# The name of the database schema where the CDM data can be found:
cdmDatabaseSchema <- "CDM_v531_YUHS.CDM"

# The name of the database schema and table where the study-specific cohorts will be instantiated:
cohortDatabaseSchema <- "cohortdb.changhoonhan"
cohortTable <- "biologics_20241016_7"

# Some meta-information that will be used by the export function:
databaseId <- "BiologicsCDM"
databaseName <- "BiologicsCDM"
databaseDescription <- "OmalizumabDupilumab"

# For Oracle: define a schema that can be used to emulate temp tables:
oracleTempSchema <- NULL

execute(connectionDetails = connectionDetails,
        cdmDatabaseSchema = cdmDatabaseSchema,
        cohortDatabaseSchema = cohortDatabaseSchema,
        cohortTable = cohortTable,
        oracleTempSchema = oracleTempSchema,
        outputFolder = outputFolder,
        databaseId = databaseId,
        databaseName = databaseName,
        databaseDescription = databaseDescription,
        createCohorts = FALSE,
        synthesizePositiveControls = FALSE,
        runAnalyses = TRUE,
        packageResults = TRUE,
        maxCores = maxCores)

resultsZipFile <- file.path(outputFolder, "export", paste0("Results_", databaseId, ".zip"))
dataFolder <- file.path(outputFolder, "shinyData")

# You can inspect the results if you want:
prepareForEvidenceExplorer(resultsZipFile = resultsZipFile, dataFolder = dataFolder)
launchEvidenceExplorer(dataFolder = dataFolder, blind = TRUE, launch.browser = FALSE)


# Calculate dose reduction outcomes:
runDoseReduction(connectionDetails = connectionDetails,
                 cdmDatabaseSchema = cdmDatabaseSchema,
                 cohortDatabaseSchema = cohortDatabaseSchema,
                 cohortTable = cohortTable,
                 outputFolder = outputFolder)

# Inspect the results in Rstudio:
# prefix <- "Ped3", "Ped6", "All3", or "All6"
print(readRDS(file = file.path(DoseReductionFolder, paste0("contingency_table_", prefix, ".rds"))))
print(readRDS(file = file.path(DoseReductionFolder, paste0("wilcox_", prefix, ".rds"))))
print(readRDS(file = file.path(DoseReductionFolder, paste0("fisher_or_chi_", prefix, ".rds"))))


# Upload the results to the OHDSI SFTP server:
#privateKeyFileName <- ""
#userName <- ""
#uploadResults(outputFolder, privateKeyFileName, userName)
