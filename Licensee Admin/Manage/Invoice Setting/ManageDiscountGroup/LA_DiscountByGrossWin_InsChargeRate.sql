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
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20220812@Danny: Add checking fresh-new licensee step  [RedmineID: #166504]
		- 20231225@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
*/

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #PartyList (PartyId INT PRIMARY KEY)
	INSERT INTO #PartyList (PartyId)
	SELECT DISTINCT value FROM STRING_SPLIT(@PartyIds, ',')

	CREATE TABLE #ChargeRate (
		ChargeId INT, FromParty INT, ToParty INT, MinAmount MONEY, MaxAmount MONEY
		,Remark NVARCHAR(200), BaseCurrencyId TINYINT, FirstOfBilling DATE, BasisOfBilling NVARCHAR(4000)
		,NewToDate DATE -- for update ToDate
		,launchDate DATE
		,isFreshNew BIT
	)
	INSERT INTO #ChargeRate (ChargeId, FromParty, ToParty, MinAmount, MaxAmount, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling, NewToDate, launchDate, isFreshNew)
	SELECT c.ChargeId, c.FromParty, c.ToParty, c.MinAmount, c.MaxAmount, c.Remark, c.BaseCurrencyId, c.FirstOfBilling, c.BasisOfBilling
		,CASE WHEN c.Rate <> @ChargeRate THEN DATEADD(DAY, -1, @FromDate) ELSE @ToDate END AS NewToDate, op.launchDate
		,CASE WHEN DATEDIFF(day, op.launchDate, GETDATE()) <= 30 AND li.BillerId IS NULL THEN 1 ELSE 0 END
	FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
		INNER JOIN #PartyList p ON c.FromParty = p.PartyId
		LEFT JOIN dbo.OAS_PartyDetail op WITH (NOLOCK) ON p.PartyId = op.PartyID
		OUTER APPLY (SELECT TOP 1 BillerId FROM dbo.LA_InvoiceHeader  li WITH (NOLOCK) WHERE li.BillerId = p.PartyId) li
	WHERE c.ToParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z )
		AND c.ProductId = @ProductId AND c.ChargeType = 1
		AND c.FromDate <= @ToDate AND c.ToDate >= @FromDate
		AND (c.Rate <> @ChargeRate OR c.ToDate <> @ToDate)

	DECLARE @ChargeIdList TABLE (ChargeId INT)

	BEGIN TRY
		 --End current setting 
		UPDATE c WITH (ROWLOCK)
		SET c.ToDate = cr.NewToDate
		FROM dbo.OAS_ChargeInfo c
			INNER JOIN #ChargeRate cr ON c.ChargeId = cr.ChargeId
		WHERE cr.isFreshNew = 0

		UPDATE c WITH (ROWLOCK)
		SET c.ToDate = @ToDate,
			c.Rate = @ChargeRate
		FROM dbo.OAS_ChargeInfo c
			INNER JOIN #ChargeRate cr ON c.ChargeId = cr.ChargeId
		WHERE cr.isFreshNew = 1

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
		WHERE cr.NewToDate = DATEADD(DAY, -1, @FromDate) AND cr.isFreshNew = 0

		INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeId, SystemId)
		SELECT ChargeId, 2 AS SystemId FROM @ChargeIdList
	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 501, @ErrMsg = 'Insert new charge rate failed.'
	END CATCH
END
GO