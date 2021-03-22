/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210322@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Insert Non-Official-Licensee Into OAS_PartyBaseCurrency
*/
USE bodb_Licensee 
GO

PRINT 'Insert Non-Official-Licensee Into OAS_PartyBaseCurrency'
INSERT INTO OAS_PartyBaseCurrency(PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
SELECT PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate
FROM (VALUES
		(342, 	'18Luck', 6, 'PHL-LSEE-18LUCK CNY', 	'20190801', 	'2050-01-31')
		,(415, 	'24AVIA', 6, 'PHL-LSEE-24AVIA CNY',  '20190801', 	'2050-01-31')
)v(PartyID, PartyName, BaseCurrencyId, LicenseeCode, FromDate, ToDate)