/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210314@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Update Todate for all terminated licensees
*/
USE bodb_Licensee 
GO

PRINT 'Prepare Terminated Licensee List: 88 records'
DECLARE @TerminatedLicenseeTable TABLE(PartyID INT, PartyName VARCHAR(50), LicenseeCode VARCHAR(50))
INSERT INTO @TerminatedLicenseeTable(PartyID, PartyName, LicenseeCode)
VALUES
		(342, 	'18Luck', 	'PHL-LSEE-18LUCK CNY')
		,(415, 	'24AVIA', 	'PHL-LSEE-24AVIA CNY')

PRINT 'Update Todate for all terminated licensees'
UPDATE p
	SET ToDate = '2019-08-31'
FROM @TerminatedLicenseeTable t
	INNER JOIN OAS_PartyBaseCurrency p WITH(NOLOCK) ON t.PartyID = p.PartyID AND p.LicenseeCode = t.LicenseeCode
WHERE p.ToDate = '2050-01-01'