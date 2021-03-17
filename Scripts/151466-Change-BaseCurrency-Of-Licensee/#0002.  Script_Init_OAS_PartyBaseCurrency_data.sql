/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210314@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Script_Init_OAS_PartyBaseCurrency_data.
*/
USE bodb_Licensee 
GO

DECLARE @CutOffTime DATE = '20210301',
		@ToDate DATE = '2050-01-01',
		@CNY_CurrencyId INT = 13

PRINT 'Step 1: Old LicenseeCode settings: Move from OAS_PartyDetail to OAS_PartyBaseCurrency'
BEGIN
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
END

----------------------------------------------------------------------------------------------------------------------------
DECLARE @NewLicenseeCodeTable TABLE(PartyID INT, PartyName VARCHAR(50), LicenseeCode VARCHAR(50), FromDate DATE, ToDate DATE)
INSERT INTO @NewLicenseeCodeTable(PartyID, PartyName, LicenseeCode, FromDate, ToDate)
VALUES(14, '12Bet', 'PHL-LSEE-12Bet CNY', @CutOffTime, @ToDate)
	 ,(72, '9Club', 'PHL-LSEE-9Club CNY', @CutOffTime, @ToDate)

PRINT 'Step 2: New LicenseeCode settings'
BEGIN
	PRINT 'Step 2.1: End old settings'
	UPDATE p
	SET ToDate = DATEADD(DAY, -1, @CutOffTime) 
	FROM @NewLicenseeCodeTable n
	INNER JOIN OAS_PartyBaseCurrency p WITH(NOLOCK) ON n.PartyID = p.PartyID

	PRINT 'Step 2.2: Add new settings'
	INSERT INTO OAS_PartyBaseCurrency(PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
	SELECT PartyID, @CNY_CurrencyId, LicenseeCode, @CutOffTime, @ToDate
	FROM @NewLicenseeCodeTable
END