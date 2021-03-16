/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210314@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Script_Init_OAS_PartyBaseCurrency_data.
*/
USE bodb_Licensee 
GO

DECLARE @ToDate DATE = '2050-01-01'

INSERT INTO OAS_PartyBaseCurrency(PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
SELECT p.PartyID, ISNULL(BaseCurrencyId, 6) BaseCurrencyId, ISNULL(LicenseeCode, ''),  ci.LaunchedDate, @ToDate
FROM OAS_Party p WITH (NOLOCK)
INNER JOIN  OAS_PartyDetail d WITH (NOLOCK) ON p.PartyID = d.PartyID
INNER JOIN 
(
	 SELECT FromParty AS PartyID, MIN(FromDate) AS LaunchedDate
	 FROM OAS_ChargeInfo ci WITH(NOLOCK)
	 GROUP BY FromParty
)ci ON p.PartyID = ci.PartyID
WHERE p.PartyType IN (1,5) AND ISNULL(d.IsDeposit, 0) = 1
ORDER by p.PartyID 
GO