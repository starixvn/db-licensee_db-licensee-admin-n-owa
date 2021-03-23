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
		(232, 	6,	'PHL-LSEE-MAY88 EUR', 	'20190801', 	'20190831')
		,(239, 	6,	'', 	'20170201', 	'20500101')
		,(278, 	6,	'', 	'20171101', 	'20500101')
		,(290, 	6,	'', 	'20180101', 	'20500101')
		,(321, 	6,	'PHL-LSEE-PCDD EUR', 	'20190801', 	'20190831')
		,(392, 	6,	'PHL-LSEE-YABO3 EUR', 	'20190801', 	'20500101')
		,(399, 	6,	'PHL-LSEE-DATANG EUR', 	'20190801', 	'20500101')
		,(465, 	6,	'PHL-LSEE-TIC88 EUR', 	'20190801', 	'20500101')
		,(474, 	6,	'PHL-LSEE-RICBET EUR', 	'20190801', 	'20500101')
		,(510, 	6,	'PHL-LSEE-WGAMING EUR', 	'20201201', 	'20500101')
		,(511, 	6,	'PHL-LSEE-GOATBET EUR', 	'20201201', 	'20500101')
		,(518, 	6,	'PHL-LSEE-UNOGAMING EUR', 	'20201201', 	'20500101')
		,(524, 	6,	'PHL-LSEE-COMEBET EUR', 	'20210101', 	'20500101')
		,(525, 	6,	'PHL-LSEE-EASYWIN22 EUR', 	'20190801', 	'20500101')
		,(538, 	6,	'PHL-LSEE-ECBET88 EUR', 	'20190801', 	'20500101')
)v(PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)