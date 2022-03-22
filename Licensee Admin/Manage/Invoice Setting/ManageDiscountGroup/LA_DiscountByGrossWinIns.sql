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
	 
	 Params:
		@RateSettingsData = '<Root>
								<RateSetting>
									<FromAmount>1</FromAmount>
									<ToAmount>10000</ToAmount>
									<Rate>0.05</Rate>
								</RateSetting>
								<RateSetting>
									<FromAmount>10001</FromAmount>
									<ToAmount>20000</ToAmount>
									<Rate>0.1</Rate>
								</RateSetting>
							</Root>'
		@PartySettingsData = '<Root>
								<PartySetting>
									<PartyId>1</PartyId>
									<ChargeRate>0.1</ChargeRate>
									<Remark>hello1</Remark>
								</PartySetting>
								<PartySetting>
									<PartyId>2</PartyId>
									<ChargeRate>0.1</ChargeRate>
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
	DECLARE @StartRun DATETIME, @Duration INT, @LogSPData NVARCHAR(MAX)

	SET @StartRun = GETDATE()

	DECLARE @CutOffDate DATE = dbo.LA_f_DiscountByGrossWin_CutOffDate()
	
	DECLARE @MaxAmountValue MONEY = 10000000000000 --  10,000,000,000,000
	DECLARE @ProductId INT, @ChargeRate MONEY

	-- Prepare input data
	DECLARE @PartyXML XML = CONVERT(XML, @PartySettingsData)
	DECLARE @CurrencyXML XML = CONVERT(XML, @CurrencySettingsData)
	DECLARE @TierRateSettingXML XML = CONVERT(XML, @RateSettingsData)

	DECLARE @PartyList TABLE (PartyId INT, ChargeRate MONEY, Remark NVARCHAR(500))
	DECLARE @CurrencyList TABLE (PartyId INT, CurrencyId INT, CalculationType TINYINT)
	DECLARE @TierRateSetting TABLE (RowId INT, FromAmount MONEY, ToAmount MONEY, Rate MONEY)
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
		SELECT DISTINCT val, 0 FROM dbo.StrSplit(@DiscountProductIds, ',')

		MERGE @ProductList AS s
		USING (
			SELECT DISTINCT val AS ProductId, 1 AS CalculationType
			FROM dbo.StrSplit(@CalculationProductIds, ',')
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

		INSERT INTO @PartyList (PartyId, ChargeRate, Remark)
		SELECT t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
			,ISNULL(t.c.value('(ChargeRate/text())[1]', 'FLOAT'), 0) AS ChargeRate
			,ISNULL(t.c.value('(Remark/text())[1]', 'NVARCHAR(500)'), '') AS Remark
		FROM @PartyXML.nodes('Root/PartySetting') AS t(c)
		OPTION (OPTIMIZE FOR (@PartyXML = NULL))

		INSERT INTO @CurrencyList (PartyId, CurrencyId, CalculationType)
		SELECT t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
			,t.c.value('(CurrencyId/text())[1]', 'INT') AS CurrencyId
			,t.c.value('(CalculationType/text())[1]', 'TINYINT') AS CalculationType
		FROM @CurrencyXML.nodes('Root/CurrencySetting') AS t(c)
		OPTION (OPTIMIZE FOR (@CurrencyXML = NULL))

		INSERT INTO @TierRateSetting (RowId, FromAmount, ToAmount, Rate)
		SELECT ROW_NUMBER() OVER(ORDER BY FromAmount) AS RowId
			,FromAmount, CASE WHEN ToAmount = 'Unlimited' THEN @MaxAmountValue ELSE ToAmount END, Rate
		FROM (
			SELECT t.c.value('(FromAmount/text())[1]', 'FLOAT') AS FromAmount
				,t.c.value('(ToAmount/text())[1]', 'NVARCHAR(500)') AS ToAmount
				,t.c.value('(Rate/text())[1]', 'FLOAT') AS Rate
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

		IF EXISTS (SELECT 1 FROM @TierRateSetting WHERE FromAmount < 0 OR FromAmount > ToAmount OR Rate < 0)
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

		SELECT TOP 1 @ChargeRate = ChargeRate FROM @PartyList
		IF EXISTS (SELECT 1 FROM @TierRateSetting WHERE Rate >= @ChargeRate)
		BEGIN
			SELECT @ErrCode = 509, @ErrMsg = 'Charge Rate after Discount must be positive value.'
			RETURN
		END

		IF EXISTS (SELECT 1 FROM @PartyList HAVING COUNT(DISTINCT ChargeRate) > 1)
		BEGIN
			SELECT @ErrCode = 510, @ErrMsg = 'Please select licensees who have same Charge Rate with others.'
			RETURN
		END

		SELECT TOP 1 @ProductId = ProductId FROM @ProductList
		IF EXISTS (
			SELECT 1
			FROM @PartyList p
				LEFT JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK)
					ON p.PartyId = c.FromParty AND c.ProductId = @ProductId
						AND c.FromDate <= @ToDate AND c.ToDate >= @FromDate
						AND c.ToParty IN (1, 9, 11, 98) AND c.ChargeType = 1
			WHERE c.FromParty IS NULL OR p.ChargeRate <> c.Rate
		)
		BEGIN
			SELECT @ErrCode = 510, @ErrMsg = 'Please select licensees who have same Charge Rate with others.'
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
		INSERT INTO dbo.LA_DiscountGroupDetail (DiscountGroupId, FromAmount, ToAmount, Rate)
		SELECT @GroupIdOut, FromAmount, ToAmount, Rate
		FROM @TierRateSetting
		ORDER BY RowId
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

	-- Log data
	SELECT @LogSPData = CONVERT(NVARCHAR(MAX),
		(SELECT
			@GroupIdOut			AS '@gid'
			,@DiscountGroupName	AS '@gn'
			,@DiscountGroupType AS '@gt'
			,@CurrencyId		AS '@c'
			,@FromDate			AS '@fd'
			,@ToDate			AS '@td'
			,(
				SELECT
					PartyId		AS '@pid'
					,Remark		AS '@rm'
				FROM @PartyList
				FOR XML PATH('d'), TYPE
			)
			,(
				SELECT
					PartyId				AS '@pid'
					,CurrencyId			AS '@c'
					,CalculationType	AS '@ct'
				FROM @CurrencyList
				FOR XML PATH('d'), TYPE
			)
			,(
				SELECT
					ProductId			AS '@pid'
					,CalculationType	AS '@ct'
				FROM @ProductList
				FOR XML PATH('d'), TYPE
			)
			,(
				SELECT
					FromAmount	AS '@fa'
					,ToAmount	AS '@ta'
					,Rate		AS '@r'
				FROM @TierRateSetting
				FOR XML PATH('d'), TYPE
			)
			FOR XML PATH('h'), TYPE))

	-- Write log
	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, GETDATE())

	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserId
		,@IP			= @LoginIP
		,@LicenseeId	= 0
		,@CurrencyId	= 0
		,@SPName		= 'LA_DiscountByGrossWinIns'
		,@CustId		= 0
		,@Duration		= @Duration
		,@Data			= @LogSPData
		,@OldData		= NULL
END
GO