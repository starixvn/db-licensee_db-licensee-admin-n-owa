/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountByGrossWin_InsChargeRate]
	@PartyIds		VARCHAR(MAX)
	,@ProductId		INT
	,@FromDate		DATE
	,@ToDate		DATE
	,@ChargeRate	MONEY
	,@ErrCode		INT = 0 OUTPUT
	,@ErrMsg		VARCHAR(4000)= '' OUTPUT
AS

/*  
	 Created: 20211101@Percy
	 DB: DBCUST.bodb_licensee
	 Task: Manage Discount Group - Discount By Gross Win - Add new charge rate
	 
	 Revisions:
		- 20211101@Percy: Initialize SP [RedmineID: #162158]
*/

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #PartyList (PartyId INT PRIMARY KEY)
	INSERT INTO #PartyList (PartyId)
	SELECT DISTINCT val FROM dbo.strSplit(@PartyIds, ',')

	CREATE TABLE #ChargeRate (
		ChargeId INT, FromParty INT, ToParty INT, MinAmount MONEY, MaxAmount MONEY
		,Remark NVARCHAR(200), BaseCurrencyId TINYINT, FirstOfBilling DATE, BasisOfBilling NVARCHAR(4000)
	)
	INSERT INTO #ChargeRate (ChargeId, FromParty, ToParty, MinAmount, MaxAmount, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
	SELECT c.ChargeId, c.FromParty, c.ToParty, c.MinAmount, c.MaxAmount, c.Remark, c.BaseCurrencyId, c.FirstOfBilling, c.BasisOfBilling
	FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
		INNER JOIN #PartyList p ON c.FromParty = p.PartyId
	WHERE c.ToParty IN (1, 9, 11, 98)
		AND c.ProductId = @ProductId AND c.ChargeType = 1
		AND c.FromDate <= @ToDate AND c.ToDate >= @FromDate

	DECLARE @ChargeIdList TABLE (ChargeId INT)

	BEGIN TRY
		-- End current setting
		UPDATE c WITH (ROWLOCK)
		SET c.ToDate = DATEADD(DAY, -1, @FromDate)
		FROM dbo.OAS_ChargeInfo c
			INNER JOIN #ChargeRate cr ON c.ChargeId = cr.ChargeId

		-- Add new setting
		INSERT INTO dbo.OAS_ChargeInfo (
			ProductId, FromParty, ToParty, ParentChargeId, Rate, ChargeType, FromDate, ToDate
			,MinAmount, MaxAmount, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling
		)
		OUTPUT INSERTED.ChargeId INTO @ChargeIdList (ChargeId)
		SELECT
			@ProductId, FromParty, ToParty, 0 AS ParentChargeId, @ChargeRate, 1 AS ChargeType, @FromDate, @ToDate
			,MinAmount, MaxAmount, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling
		FROM #ChargeRate cr

		INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
		SELECT ChargeId, 2 AS SystemId FROM @ChargeIdList
	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 501, @ErrMsg = 'Insert new charge rate failed.'
	END CATCH
END
GO