/*<info serverAlias="DBCUST-bodb_licensee"></info>*/
/*
	Created: 20230412@Danny
	DB: DBCUST-bodb_Licensee
	Task: Change 3rd charge rate for Exchange
	ProductId = 31
*/
USE bodb_Licensee
GO

DECLARE @ExchangePartyID INT, @CurrentChargeID INT, @NewChargeID INT
DECLARE @EndDate DATE = '2023-04-30'
DECLARE @NewStartDate DATE = '2023-05-01'

SELECT @ExchangePartyID = PartyID FROM OAS_Party WITH (NOLOCK) WHERE PartyName ='Exchange'

SELECT @CurrentChargeID = ChargeID 
FROM  dbo.OAS_ChargeInfo c WITH (NOLOCK)
WHERE ProductID = 31 AND FromDate <= @EndDate AND ToDate >= @EndDate AND ToParty = @ExchangePartyID AND FromParty = 1

--SELECT @ExchangePartyID, @CurrentChargeID

IF @CurrentChargeID > 0 
BEGIN
	-- End Currrent setting
	UPDATE dbo.OAS_ChargeInfo  WITH (ROWLOCK)
	SET  ToDate = @EndDate
	WHERE ChargeID = @CurrentChargeID

	-- Insert new Setting
	IF NOT EXISTS (SELECT TOP 1 1 FROM OAS_ChargeInfo WITH(NOLOCK) WHERE ToParty = @ExchangePartyID AND ProductId = 31 AND FromDate <= @NewStartDate AND ToDate >= @NewStartDate  AND FromParty = 1)
	BEGIN

		INSERT INTO dbo.OAS_ChargeInfo (ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate)
		SELECT TOP 1 ProductId, FromParty, ToParty, ParentChargeId, 0.1 Rate, ChargeType, @NewStartDate, '2050-01-01'ToDate
		FROM dbo.OAS_ChargeInfo  WITH (NOLOCK) WHERE ChargeID = @CurrentChargeID;

		SET @NewChargeID = SCOPE_IDENTITY()

		INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
		SELECT @NewChargeID, 2 AS SystemId
	END
END