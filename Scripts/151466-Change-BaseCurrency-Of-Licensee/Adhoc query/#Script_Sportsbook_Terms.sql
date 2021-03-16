/*
	Created: 20210314@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Scripts Sportsbook terms
*/
USE bodb_Licensee 
GO

DECLARE @SportsbookChargeRate_PartyTable TABLE(PartyID INT, PartyName VARCHAR(100), Rate MONEY, Max_ToDate DATE, CurrencyID INT, ChargeId INT)
DECLARE @CurrentDate DATE = GETDATE()

INSERT INTO @SportsbookChargeRate_PartyTable(PartyID, PartyName)
SELECT pd.PartyID, p.PartyName
FROM OAS_Party p
INNER JOIN OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID = pd.PartyID
ORDER BY p.PartyName

UPDATE p
SET p.Rate = ci_2.Rate,
	p.Max_ToDate = ci_2.ToDate,
	p.ChargeId = ci_2.ChargeID
FROM @SportsbookChargeRate_PartyTable p
CROSS APPLY
(
	SELECT TOP 1 ci.Rate, ToDate, ci.ChargeID
	FROM OAS_ChargeInfo ci WITH(NOLOCK)
	WHERE ci.ToDate >= @CurrentDate AND ci.FromParty = p.PartyID AND ci.ProductID = 0 -- SB only
	ORDER BY ToDate DESC
) ci_2

INSERT INTO @SportsbookChargeRate_PartyTable(PartyID, PartyName, Rate, Max_ToDate, CurrencyID)
SELECT p.PartyID, p.PartyName, ci.Rate, p.Max_ToDate, ci.CurrencyID
FROM @SportsbookChargeRate_PartyTable p
INNER JOIN [dbo].[LA_ChargeRateByCurrency] ci WITH(NOLOCK) ON p.ChargeID = ci.ChargeID

SELECT PartyID, PartyName, Rate, Max_ToDate, CurrencyID
FROM @SportsbookChargeRate_PartyTable
WHERE ISNULL(Rate, 0) <> 0 AND Max_ToDate >= @CurrentDate
ORDER BY PartyName