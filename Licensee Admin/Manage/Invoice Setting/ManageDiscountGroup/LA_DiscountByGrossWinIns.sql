/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountByGrossWinIns]
	@DiscountGroupName		NVARCHAR(110)
	,@DiscountGroupType		TINYINT
	,@CurrencyId			TINYINT
	,@FromDate				DATE
	,@ToDate				DATE
	,@CalculationProductIds VARCHAR(MAX) = '0'
	,@DiscountProductIds	VARCHAR(MAX) = '0'
	,@RateSettingsData		VARCHAR(MAX) = ''
	,@PartySettingsData		NVARCHAR(MAX) = ''
	,@CurrencySettingsData	VARCHAR(MAX) = ''
	,@UserId				INT
	,@LoginIP				VARCHAR(50) = ''
	,@ErrCode				INT = 0 OUTPUT
	,@ErrMsg				VARCHAR(4000)= '' OUTPUT
	,@GroupIdOut			SMALLINT = 0 OUTPUT
AS

/*  
	 Created: 20211101@Percy
	 DB: DBCUST.bodb_licensee
	 Task: Manage Discount Group - Discount By Gross Win
	 
	 Revisions:
		- 20211101@Percy: Initialize SP [RedmineID: #162158]
		- 20220210@Percy: Support Tier Rebate [RedmineID: #163495]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
		- 20230331@Danny: Insert new log with more information [#FeatureID 175125]
	 
	 Params:
		@RateSettingsData = '<Root>
								<RateSetting>
									<FromAmount>1</FromAmount>
									<ToAmount>10000</ToAmount>
									<ChargeRateAfterDiscount>0.05</ChargeRateAfterDiscount>
								</RateSetting>
								<RateSetting>
									<FromAmount>10001</FromAmount>
									<ToAmount>20000</ToAmount>
									<ChargeRateAfterDiscount>0.1</ChargeRateAfterDiscount>
								</RateSetting>
							</Root>'
		@PartySettingsData = '<Root>
								<PartySetting>
									<PartyId>1</PartyId>
									<Remark>hello1</Remark>
								</PartySetting>
								<PartySetting>
									<PartyId>2</PartyId>
									<Remark>hello2</Remark>
								</PartySetting>
							</Root>'
		@CurrencySettingsData = '<Root>
								<CurrencySetting>
									<PartyId>1</PartyId>
									<CurrencyId>2</CurrencyId>
									<CalculationType>0</CalculationType>
								</CurrencySetting>
								<CurrencySetting>
									<PartyId>3</PartyId>
									<CurrencyId>4</CurrencyId>
									<CalculationType>1</CalculationType>
								</CurrencySetting>
							</Root>'
					. CalculationType: Discount-Calculate (binary)
						00 = 0 = None
						01 = 1 = Calculate only
						10 = 2 = Discount only
						11 = 3 = Calculate & Discount
*/

BEGIN
	SET NOCOUNT ON

	-- For log
	DECLARE @StartRun DATETIME, @Duration INT, @LogSPData NVARCHAR(MAX), @LogSPDataOld NVARCHAR(MAX)

	SET @StartRun = GETDATE()

	DECLARE @CutOffDate DATE = dbo.LA_f_DiscountByGrossWin_CutOffDate()
	
	DECLARE @MaxAmountValue MONEY = 10000000000000 --  10,000,000,000,000
	DECLARE @ProductId INT, @ChargeRate MONEY

	-- Prepare input data
	DECLARE @PartyXML XML = CONVERT(XML, @PartySettingsData)
	DECLARE @CurrencyXML XML = CONVERT(XML, @CurrencySettingsData)
	DECLARE @TierRateSettingXML XML = CONVERT(XML, @RateSettingsData)

	DECLARE @PartyList TABLE (PartyId INT, Remark NVARCHAR(500))
	DECLARE @CurrencyList TABLE (PartyId INT, CurrencyId INT, CalculationType TINYINT)
	DECLARE @TierRateSetting TABLE (RowId INT, FromAmount MONEY, ToAmount MONEY, ChargeRateAfterDiscount MONEY)
	DECLARE @ProductList TABLE (ProductId INT, CalculationType TINYINT)

	BEGIN TRY
		IF @FromDate < @CutOffDate
		BEGIN
			SELECT @ErrCode = 501, @ErrMsg = 'From Date must start from ' + CONVERT(VARCHAR(11), @CutOffDate, 106) + '.'
			RETURN
		END

		/*
			Product CalculationType
			 0 = discount only
			 1 = calculate only
			10 = discount & calculate
		*/
		INSERT INTO @ProductList (ProductId, CalculationType)
		SELECT DISTINCT value, 0 FROM STRING_SPLIT(@DiscountProductIds, ',')

		MERGE @ProductList AS s
		USING (
			SELECT DISTINCT value AS ProductId, 1 AS CalculationType
			FROM STRING_SPLIT(@CalculationProductIds, ',')
		) AS t ON s.ProductId = t.ProductId
		WHEN MATCHED THEN UPDATE SET s.CalculationType = 10
		WHEN NOT MATCHED BY TARGET THEN INSERT (ProductId, CalculationType) VALUES (ProductId, CalculationType);

		IF EXISTS (
			SELECT 1
			FROM @ProductList pl
				LEFT JOIN dbo.LA_f_Products3rd('') p ON pl.ProductId = p.ProductId
			WHERE p.ProductId IS NULL
		)
		BEGIN
			SELECT @ErrCode = 502, @ErrMsg = 'Product(s) do not exist.'
			RETURN
		END

		INSERT INTO @PartyList (PartyId, Remark)
		SELECT t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
			,ISNULL(t.c.value('(Remark/text())[1]', 'NVARCHAR(500)'), '') AS Remark
		FROM @PartyXML.nodes('Root/PartySetting') AS t(c)
		OPTION (OPTIMIZE FOR (@PartyXML = NULL))

		INSERT INTO @CurrencyList (PartyId, CurrencyId, CalculationType)
		SELECT t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
			,t.c.value('(CurrencyId/text())[1]', 'INT') AS CurrencyId
			,t.c.value('(CalculationType/text())[1]', 'TINYINT') AS CalculationType
		FROM @CurrencyXML.nodes('Root/CurrencySetting') AS t(c)
		OPTION (OPTIMIZE FOR (@CurrencyXML = NULL))

		INSERT INTO @TierRateSetting (RowId, FromAmount, ToAmount, ChargeRateAfterDiscount)
		SELECT ROW_NUMBER() OVER(ORDER BY FromAmount) AS RowId
			,FromAmount, CASE WHEN ToAmount = 'Unlimited' THEN @MaxAmountValue ELSE ToAmount END, Rate
		FROM (
			SELECT t.c.value('(FromAmount/text())[1]', 'FLOAT') AS FromAmount
				,t.c.value('(ToAmount/text())[1]', 'NVARCHAR(500)') AS ToAmount
				,t.c.value('(ChargeRateAfterDiscount/text())[1]', 'FLOAT') AS Rate
			FROM @TierRateSettingXML.nodes('Root/RateSetting') AS t(c)
		) t
		OPTION (OPTIMIZE FOR (@TierRateSettingXML = NULL))
	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 503, @ErrMsg = 'Parse XML failed.'
		RETURN
	END CATCH

	-- Validate input data
	BEGIN
		IF ISNULL(@DiscountGroupName, '') = ''
		BEGIN
			SELECT @ErrCode = 504, @ErrMsg = 'Please fill out group name.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK)
			WHERE DiscountGroupName = @DiscountGroupName AND DiscountGroupType IN (1, 3, 11, 13)
		)
		BEGIN
			SELECT @ErrCode = 505, @ErrMsg = 'Group name exists. Please try again.'
			RETURN
		END

		IF @FromDate IS NULL OR @ToDate IS NULL OR ISNULL(@CurrencyId, 0) = 0
			OR NOT EXISTS (SELECT 1 FROM @TierRateSetting)
		BEGIN
			SELECT @ErrCode = 506, @ErrMsg = 'Please fill all required fields.'
			RETURN
		END

		IF EXISTS (SELECT 1 FROM @TierRateSetting WHERE FromAmount < 0 OR FromAmount > ToAmount OR ChargeRateAfterDiscount < 0)
		BEGIN
			SELECT @ErrCode = 507, @ErrMsg = 'Please input valid amount.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM @TierRateSetting t1
				INNER JOIN @TierRateSetting t2 ON t1.RowId +1 = t2.RowId
			WHERE t1.ToAmount >= t2.FromAmount
		)
		BEGIN
			SELECT @ErrCode = 508, @ErrMsg = 'The rank is overlapped with the other. Please input another rank.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM @PartyList p
				LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
			WHERE bc.PartyId IS NULL OR bc.BaseCurrencyId <> @CurrencyId
		)
		BEGIN
			SELECT @ErrCode = 511, @ErrMsg = 'Please select licensees who have same Base Currency with discount setting.'
			RETURN
		END
	END

	-- Remove Terminated Or Suspended  Licensees
	DELETE t 
	FROM @PartyList t
	INNER JOIN OAS_PartyDetail op WITH(NOLOCK) ON t.PartyId = op.PartyID
	WHERE (op.TerminatedDate IS NOT NULL OR op.SuspendedDate IS NOT NULL)  AND ( op.TerminatedDate < @FromDate OR op.SuspendedDate < @FromDate)

	DELETE t 
	FROM @CurrencyList t
	INNER JOIN OAS_PartyDetail op WITH(NOLOCK) ON t.PartyId = op.PartyID
	WHERE (op.TerminatedDate IS NOT NULL OR op.SuspendedDate IS NOT NULL) AND ( op.TerminatedDate < @FromDate OR op.SuspendedDate < @FromDate)

	-- Insert data
	BEGIN TRY
		-- main table
		INSERT INTO dbo.LA_DiscountGroupHeader (DiscountGroupName, DiscountGroupType, CurrencyId, FromDate, ToDate, Priority, ModifiedDate)
		VALUES (@DiscountGroupName, @DiscountGroupType, @CurrencyId, @FromDate, @ToDate, 1, GETDATE())

		SET @GroupIdOut = SCOPE_IDENTITY()

		IF ISNULL(@GroupIdOut, 0) = 0
		BEGIN
			SELECT @ErrCode =  601, @ErrMsg = 'Insert failed. Please try again.'
			RETURN
		END

		-- party
		INSERT INTO dbo.LA_DiscountGroupAssignment (DiscountGroupId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment)
		SELECT @GroupIdOut, PartyId, Remark, 1 AS IsApplyDiscount, 0 AS IsSpecialTreatment
		FROM @PartyList

		-- currency
		INSERT INTO dbo.LA_DiscountGroupCurrency (DiscountGroupId, PartyId, CurrencyId, CalculationType)
		SELECT @GroupIdOut, PartyId, CurrencyId, CalculationType
		FROM @CurrencyList

		-- product
		INSERT INTO dbo.LA_DiscountGroupProduct (DiscountGroupId, ProductId, CalculationType)
		SELECT @GroupIdOut, ProductId, CalculationType
		FROM @ProductList

		-- tier rate setting
		INSERT INTO dbo.LA_DiscountGroupDetail (DiscountGroupId, FromAmount, ToAmount, ChargeRateAfterDiscount)
		SELECT @GroupIdOut, FromAmount, ToAmount, ChargeRateAfterDiscount
		FROM @TierRateSetting
		ORDER BY RowId

		-- Log data
		SELECT @LogSPData = (
			SELECT ld.DiscountGroupName 'gr.gn', 
					e.Code AS  'gr.e', 
					FORMAT (ld.FromDate,'MMM dd, yyyy') 'gr.af', 
					FORMAT (ld.ToDate,'MMM dd, yyyy') 'gr.at',
					STRING_AGG(CASE WHEN ldp.ProductId = 0 THEN 'Sportsbook' ELSE p3.ProductName END  ,', ') 'gr.p',
					l.l AS 'l',
					ds.s AS 'st'
			FROM LA_DiscountGroupHeader ld with(nolock) 
			INNER JOIN CUSTDB.dbo.Exchange e  with(nolock) ON ld.CurrencyId = e.ExchangeId
			INNER JOIN LA_DiscountGroupProduct ldp WITH(NOLOCK) ON ld.DiscountGroupId = ldp.DiscountGroupId 
			LEFT JOIN Product3rd p3 WITH(NOLOCK) ON ldp.ProductId = p3.Productid

			OUTER APPLY 
			(
				SELECT 
				(
					SELECT  PartyID AS FakeID ,PartyID AS pi,LicenseeName ln, Remark rm, 
					CASE WHEN SUM(NotCountInPert) = 0 THEN 'All (' ELSE '' END +STRING_AGG(CASE WHEN CountInPer = 1 THEN Curr END  ,', ') + CASE WHEN SUM(NotCountInPert) = 0 THEN ')' ELSE ''  END  cip,
					CASE WHEN SUM(NotAppliedDiscount) = 0 THEN 'All (' ELSE '' END +STRING_AGG(CASE WHEN AppliedDiscount = 1 THEN Curr END  ,', ') + CASE WHEN SUM(NotAppliedDiscount) = 0 THEN ')' ELSE '' END ap
					FROM 
						(
							SELECT  op.PartyID as PartyID ,op.PartyName AS LicenseeName, CASE WHEN lgc.CurrencyId = 142 THEN 'USDT' 
													WHEN lgc.CurrencyId IN (96, 202) THEN e.Code + ' ('+ e.currency+ ')'
													ELSE e.Code END AS Curr,
	  
									CASE WHEN lgc.CalculationType IN (1,3) THEN 1 ELSE 0 END CountInPer,
									CASE WHEN lgc.CalculationType IN (2,3) THEN 1 ELSE 0 END AppliedDiscount,
									CASE WHEN lgc.CalculationType IN (0,1)  THEN 1 ELSE 0 END NotAppliedDiscount,
									CASE WHEN lgc.CalculationType IN (0,2)  THEN 1 ELSE 0 END NotCountInPert,
									lga.Remark
							FROM LA_DiscountGroupAssignment lga WITH(NOLOCK)
							INNER JOIN OAS_Party op WITH(NOLOCK) ON lga.PartyID = op.PartyID
							INNER JOIN LA_DiscountGroupCurrency  lgc WITH(NOLOCK) ON lga.PartyID = lgc.PartyID AND lga.DiscountGroupId = lgc.DiscountGroupId
							INNER JOIN CUSTDB.dbo.Exchange e  with(nolock) ON lgc.CurrencyId = e.ExchangeId
							WHERE lga.DiscountGroupId = ld.DiscountGroupId
						) x  GROUP BY PartyID,LicenseeName, Remark FOR JSON PATH
					)l
			) l
			OUTER APPLY 
			(	
				SELECT 
				(
					SELECT FORMAT(FromAmount,'N','en-us') wlf, CASE WHEN ToAmount = 10000000000000.00 THEN 'Unlimited' ELSE FORMAT(ToAmount,'N','en-us') END wlt,  CAST (ChargeRateAfterDiscount * 100 AS VARCHAR(50)) + ' %' cr, ldg.DiscountGroupDetailId AS FakeID
					FROM LA_DiscountGroupDetail  ldg WITH(NOLOCK) 
					WHERE ldg.DiscountGroupId = ld.DiscountGroupId FOR JSON PATH
				) s
			) ds
			WHERE ld.DiscountGroupID = @GroupIdOut
			GROUP BY ld.DiscountGroupName, e.Code, FORMAT (ld.FromDate,'MMM dd, yyyy'), FORMAT (ld.ToDate,'MMM dd, yyyy'), l.l, ds.s
			FOR JSON PATH,  WITHOUT_ARRAY_WRAPPER 
		 )
		
	END TRY
	BEGIN CATCH
		-- Rollback data manually
		DELETE dbo.LA_DiscountGroupHeader WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupAssignment WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupCurrency WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupProduct WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail WHERE DiscountGroupId = @GroupIdOut

		SELECT @ErrCode =  601, @ErrMsg = 'Insert failed. Please try again.'
		RETURN
	END CATCH

	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, GETDATE())

	-- Write Log Discount Setting
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_DiscountByGrossWinIns'
		,@CustId		= @GroupIdOut
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPDataOld
		,@ActionID		 = 1600
END
GO