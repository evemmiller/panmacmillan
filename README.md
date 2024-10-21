Results of the analysis can be found in the file publishing_data_results.csv
Additional columns have been included:
- isExcluded
    - TRUE if the edition has been excluded from confirmation, embargoed for a later date, marked as confidential or given the        status pre-Aquisition
- metadataIssues
    - True if there is missing data including
      
          a)	Extent
          b)	Format
          c)	Price Sync Template (for ebooks only)
      
      Based on current assumptions editions have not been excluded from confirmation due to this data being missing but this         can be updated if necessary.
- isSecondFormat
    - True if a paperback has been identified as being a second format, based on the existence of a first edition with the           same work reference
- earliestConfirmationDate
    - The earliest date an edition can be confirmed assuming that it has not been excluded (see isExcluded)
    - For most editions this is a year prior to its publication dates
    - For second edition paperbacks this is either a year prior to its publication date or 6 weeks after the earliest first          edition is published, whichever is later.
      
 The code used to clean and analyse the data can be found in macmillan_script.sql
 - determining first and second editions
       - the data quality in the column 'binding' appeared to be the best for identifying first editions, and therefore where           paperbacks should be classified as second editions
            - there are a number of nulls in the 'binding' column, however upon reviewing the data these are not related to                  physical books and so I felt comfortable excluding them in the identification of second editions as the primary                concern was the affect of an early paperback release on sales of the hardbacks and trade paperbacks. 
