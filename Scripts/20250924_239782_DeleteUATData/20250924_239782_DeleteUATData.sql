/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20250924@Lionel
	DB: DBLIC.bodb_licenseereport
	Description: Delete UAT data
*/



USE bodb_licenseereport
-- DELETE SabaPlayPerformance 295 rows
DELETE FROM SabaPlayPerformance WITH (ROWLOCK) 
WHERE rptdate in ('2025-08-31','2025-09-21' )
		AND Environment='UAT'
