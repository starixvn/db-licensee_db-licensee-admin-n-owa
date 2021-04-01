/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210401@Parsons
	DB: DBCUST.bodb_Licensee
	Task: LA/NAP - Change back Setting of boma365, GESAB, WKCUR, WKPHIL, VWIN66 to EUR base currency [#FeatureID 152655]
	Description: Remove CNY code
*/
USE bodb_Licensee 
GO

PRINT 'Prepare Licensee List: 5 records'
DECLARE @CNY_LicenseeCodeTable TABLE(PartyID INT, PartyName VARCHAR(50), LicenseeCode VARCHAR(50))
INSERT INTO @CNY_LicenseeCodeTable(PartyID, PartyName, LicenseeCode)
VALUES	(43, 	'BOMA365', 	'PHL-LSEE-BOMA365 CNY')
		,(395, 	'GESAB', 	'PHL-LSEE-GESAB CNY')
		,(379, 	'WKCUR', 	'PHL-LSEE-WKCUR CNY')
		,(380, 	'WKPHIL', 	'PHL-LSEE-WKPHIL CNY')
		,(348, 	'VWIN66', 	'PHL-LSEE-VWIN66 CNY')

PRINT 'DELETE 5 Licensee Codes'
DELETE p WITH (ROWLOCK, UPDLOCK)
FROM OAS_PartyBaseCurrency p
INNER JOIN @CNY_LicenseeCodeTable c ON p.PartyID = c.PartyID AND p.LicenseeCode = c.LicenseeCode AND p.BaseCurrencyId = 13 -- CNY