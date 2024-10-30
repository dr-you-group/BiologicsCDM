SELECT * INTO @target_database_schema.@target_cohort_table_steroidlist 
FROM (VALUES
(1, 'prednisolone'),
(2, 'prednisone'),
(3, 'deflazacort'),
(4, 'hydrocortisone'),
(5, 'cortisone'),
(6, 'methylprednisolone'),
(7, 'triamcinolone'),
(8, 'dexamethasone'),
(9, 'betamethasone')
) AS steroids(id, Drug_Name);

