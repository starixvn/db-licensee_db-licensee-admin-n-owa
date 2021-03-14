/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210314@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Script_Init_OAS_PartyBaseCurrency_data.
*/
USE bodb_Licensee 
GO

DECLARE @FromDate DATE = '2010-01-01', @ToDate DATE = '2021-02-28'

INSERT INTO OAS_PartyBaseCurrency(PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
SELECT PartyID, ISNULL(BaseCurrencyId, 6) BaseCurrencyId, ISNULL(LicenseeCode, ''),  @FromDate, @ToDate
FROM [dbo].[OAS_PartyDetail] WITH (NOLOCK) 

GO