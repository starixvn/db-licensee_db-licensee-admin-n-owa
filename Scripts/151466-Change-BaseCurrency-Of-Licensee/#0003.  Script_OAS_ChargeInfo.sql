/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210317@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: End Sportsbook settings & create a new one with a different charge rate
*/
USE bodb_Licensee 
GO


DECLARE @ToDate DATE = '2050-01-01', @CurrentDate DATE = GETDATE()
DECLARE @SB_ChargeInfoSettings	TABLE (PartyId INT, PartyName VARCHAR(50), Current_ChargeID INT, Rate MONEY, Remark NVARCHAR(400), FirstOfBilling DATE, BasisOfBilling NVARCHAR(500), ChargeType INT, FromDate DATE, ToDate DATE, BaseCurrencyID INT) 

PRINT 'Prepare new SB term settings here: 999 records'
BEGIN
	INSERT INTO @SB_ChargeInfoSettings(PartyId, PartyName, Rate, FromDate, ToDate)
	VALUES(14, '12Bet', 0.1, '20210301', '20500101')
		 ,(72, '9Club', 0.07, '20210301', '20500101')
END

PRINT 'Step 1. Find exactly current SB settings'
BEGIN
	UPDATE p
	SET	p.Current_ChargeID = ci_2.ChargeID,
		p.FirstOfBilling = ci_2.FirstOfBilling,
		p.BasisOfBilling = ci_2.BasisOfBilling,
		p.ChargeType = ci_2.ChargeType
	FROM @SB_ChargeInfoSettings p
	CROSS APPLY
	(
		SELECT TOP 1 ci.ChargeID, FirstOfBilling, BasisOfBilling, ChargeType
		FROM OAS_ChargeInfo ci WITH(NOLOCK)
		WHERE ci.ToDate >= @CurrentDate AND ci.FromParty = p.PartyID AND ci.ProductID = 0 -- SB only
		ORDER BY ToDate DESC
	) ci_2
END

PRINT 'Step 2. End current SB settings'
BEGIN
	UPDATE ci
	SET ci.ToDate = DATEADD(DAY, -1, p.FromDate) 
	FROM OAS_ChargeInfo ci WITH (NOLOCK)
	INNER JOIN @SB_ChargeInfoSettings p ON ci.FromParty = p.PartyId
END

PRINT 'Step 3. Add new SB settings with a different charge rate '
BEGIN
	PRINT 'Step 3.1: OAS_ChargeInfo'

	PRINT 'Step 3.2: LA_ChargeInfo_SystemMapping'
END