/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210511@Percy
	DB: DBCUST.bodb_licensee
	Task: Add Charge Rate settings for Sport Lottery
*/

USE bodb_licensee
GO

--- From Credit to OW
	INSERT INTO dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
	VALUES (63, 25, 1, 0, 0, 1, '2021-03-29', '2050-01-01')
		,(63, 30, 1, 0, 0, 1, '2021-03-29', '2050-01-01')

-- LA System Mapping
	INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeId ,SystemId)
	SELECT ChargeId, 2
	FROM dbo.OAS_ChargeInfo WITH (NOLOCK)
	WHERE FromParty IN (25, 30)
		AND ToParty = 1
		AND ProductId = 63 