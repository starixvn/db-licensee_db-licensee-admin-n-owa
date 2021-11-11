/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountByGrossWinUpd]
	@DiscountGroupId		SMALLINT
	,@DiscountGroupName		NVARCHAR(110)
	,@CurrencyId			TINYINT
	,@FromDate				DATE
	,@ToDate				DATE
	,@ProductId				INT = 0
	,@RateSettingsData		VARCHAR(MAX) = ''
	,@PartySettingsData		NVARCHAR(MAX) = ''
	,@CurrencySettingsData	VARCHAR(MAX) = ''
	,@ErrCode				INT = 0 OUTPUT
	,@ErrMsg				VARCHAR(4000)= '' OUTPUT
AS

/*  
	 Created: 20211101@Percy
	 DB: DBCUST.bodb_licensee
	 Task: Manage Discount Group - Discount By Gross Win
	 
	 Revisions:
		- 20211101@Percy: Initialize SP [RedmineID: #162158]
	 
	 Params:
		@RateSettingsData = '<Root>
								<RateSetting>
									<DiscountDetailId>1</DiscountDetailId>
									<FromAmount>1</FromAmount>
									<ToAmount>10000</ToAmount>
									<Rate>0.05</Rate>
								</RateSetting>
								<RateSetting>
									<DiscountDetailId>2</DiscountDetailId>
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
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @CutOffDate DATE = dbo.LA_f_DiscountByGrossWin_CutOffDate()

	DECLARE @MaxAmountValue MONEY = 10000000000000 --  10,000,000,000,000
	DECLARE @ChargeRate MONEY

	-- Prepare input data
	DECLARE @PartyXML XML = CONVERT(XML, @PartySettingsData)
	DECLARE @CurrencyXML XML = CONVERT(XML, @CurrencySettingsData)
	DECLARE @TierRateSettingXML XML = CONVERT(XML, @RateSettingsData)

	DECLARE @PartyList	TABLE (PartyId INT, ChargeRate MONEY, Remark NVARCHAR(500))
	DECLARE @CurrencyList TABLE (PartyId INT, CurrencyId INT, CalculationType TINYINT)
	DECLARE @TierRateSetting TABLE (DiscountGroupDetailId INT, RowId INT, FromAmount MONEY, ToAmount MONEY, Rate MONEY)

	BEGIN TRY
		IF @FromDate < @CutOffDate
		BEGIN
			SELECT @ErrCode = 501, @ErrMsg = 'From Date must start from ' + CONVERT(VARCHAR(11), @CutOffDate, 106) + '.'
			RETURN
		END

		IF NOT EXISTS (SELECT 1 FROM dbo.LA_f_Products3rd('') WHERE ProductId = @ProductId)
		BEGIN
			SELECT @ErrCode = 502, @ErrMsg = 'Product(s) do not exist.'
			RETURN
		END

		INSERT INTO @PartyList (PartyId, ChargeRate, Remark)
		SELECT t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
			,t.c.value('(ChargeRate/text())[1]', 'FLOAT') AS ChargeRate
			,t.c.value('(Remark/text())[1]', 'NVARCHAR(500)') AS Remark
		FROM @PartyXML.nodes('Root/PartySetting') AS t(c)
		OPTION (OPTIMIZE FOR (@PartyXML = NULL))

		INSERT INTO @CurrencyList (PartyId, CurrencyId, CalculationType)
		SELECT t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
			,t.c.value('(CurrencyId/text())[1]', 'INT') AS CurrencyId
			,t.c.value('(CalculationType/text())[1]', 'TINYINT') AS CalculationType
		FROM @CurrencyXML.nodes('Root/CurrencySetting') AS t(c)
		OPTION (OPTIMIZE FOR (@CurrencyXML = NULL))

		INSERT INTO @TierRateSetting (DiscountGroupDetailId, RowId, FromAmount, ToAmount, Rate)
		SELECT DiscountGroupDetailId, ROW_NUMBER() OVER(ORDER BY FromAmount) AS RowId
			,FromAmount, CASE WHEN ToAmount = 'Unlimited' THEN @MaxAmountValue ELSE ToAmount END, Rate
		FROM (
			SELECT t.c.value('(DiscountDetailId/text())[1]', 'INT') AS DiscountGroupDetailId
				,t.c.value('(FromAmount/text())[1]', 'FLOAT') AS FromAmount
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
		IF NOT EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK) WHERE DiscountGroupId = @DiscountGroupId AND DiscountGroupType <> 2) -- 2: Rebate
		BEGIN
			SELECT @ErrCode = 504, @ErrMsg = 'This group does not exist. Please check again.'
			RETURN
		END

		IF ISNULL(@DiscountGroupName, '') = ''
		BEGIN
			SELECT @ErrCode = 505, @ErrMsg = 'Please fill out group name.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK)
			WHERE DiscountGroupName = @DiscountGroupName AND DiscountGroupType <> 2 -- 2: Rebate
				AND DiscountGroupId <> @DiscountGroupId AND DiscountGroupName NOT LIKE '%Expired%'
		)
		BEGIN
			SELECT @ErrCode = 506, @ErrMsg = 'Group name exists. Please try again.'
			RETURN
		END

		IF @FromDate IS NULL OR @ToDate IS NULL OR ISNULL(@CurrencyId, 0) = 0
			OR NOT EXISTS (SELECT 1 FROM @TierRateSetting)
		BEGIN
			SELECT @ErrCode = 507, @ErrMsg = 'Please fill all required fields.'
			RETURN
		END

		IF EXISTS (SELECT 1 FROM @TierRateSetting WHERE FromAmount < 0 OR FromAmount > ToAmount OR Rate < 0)
		BEGIN
			SELECT @ErrCode = 508, @ErrMsg = 'Please input valid amount.'
			RETURN
		END

		IF EXISTS (
			SELECT 1
			FROM @TierRateSetting t1
				INNER JOIN @TierRateSetting t2 ON t1.RowId +1 = t2.RowId
			WHERE t1.ToAmount >= t2.FromAmount
		)
		BEGIN
			SELECT @ErrCode = 509, @ErrMsg = 'The rank is overlapped with the other. Please input another rank.'
			RETURN
		END

		SELECT TOP 1 @ChargeRate = ChargeRate FROM @PartyList
		IF EXISTS (SELECT 1 FROM @TierRateSetting WHERE Rate >= @ChargeRate)
		BEGIN
			SELECT @ErrCode = 510, @ErrMsg = 'Charge Rate after Discount must be positive value.'
			RETURN
		END

		IF EXISTS (SELECT 1 FROM @PartyList HAVING COUNT(DISTINCT ChargeRate) > 1)
		BEGIN
			SELECT @ErrCode = 511, @ErrMsg = 'Please select licensees who have same Charge Rate with others.'
			RETURN
		END

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
			SELECT @ErrCode = 512, @ErrMsg = 'Please select licensees who have same Charge Rate with others.'
			RETURN
		END
	END

	-- Update data
	BEGIN TRY
		-- main table
		UPDATE dbo.LA_DiscountGroupHeader WITH (ROWLOCK)
		SET DiscountGroupName = @DiscountGroupName
			,CurrencyId = @CurrencyId
			,FromDate = @FromDate
			,ToDate = @ToDate
			,ModifiedDate = GETDATE()
		WHERE DiscountGroupId = @DiscountGroupId

		-- party
		;WITH CTE_DiscountGroupAssignment AS (
			SELECT DiscountGroupId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment
			FROM dbo.LA_DiscountGroupAssignment WITH (NOLOCK)
			WHERE DiscountGroupId = @DiscountGroupId
		)
		MERGE CTE_DiscountGroupAssignment AS t
		USING @PartyList AS s ON t.PartyId = s.PartyId
		WHEN MATCHED THEN UPDATE
			SET t.Remark = s.Remark
		WHEN NOT MATCHED BY TARGET THEN INSERT
			(DiscountGroupId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment)
			VALUES (@DiscountGroupId, PartyId, Remark, 1, 0)
		WHEN NOT MATCHED BY SOURCE THEN DELETE;

		-- currency
		;WITH CTE_DiscountGroupCurrency AS (
			SELECT DiscountGroupId, PartyId, CurrencyId, CalculationType
			FROM dbo.LA_DiscountGroupCurrency WITH (NOLOCK)
			WHERE DiscountGroupId = @DiscountGroupId
		)
		MERGE CTE_DiscountGroupCurrency AS t
		USING @CurrencyList AS s ON t.PartyId = s.PartyId AND t.CurrencyId = s.CurrencyId
		WHEN MATCHED THEN UPDATE
			SET t.CalculationType = s.CalculationType
		WHEN NOT MATCHED BY TARGET THEN INSERT
			(DiscountGroupId, PartyId, CurrencyId, CalculationType)
			VALUES (@DiscountGroupId, PartyId, CurrencyId, CalculationType)
		WHEN NOT MATCHED BY SOURCE THEN DELETE;

		-- product
		UPDATE dbo.LA_DiscountGroupProduct WITH (ROWLOCK)
		SET ProductId = @ProductId
		WHERE DiscountGroupId = @DiscountGroupId

		-- tier rate setting
		;WITH CTE_DiscountGroupDetail AS (
			SELECT DiscountGroupDetailId, DiscountGroupId, FromAmount, ToAmount, Rate
			FROM dbo.LA_DiscountGroupDetail WITH (NOLOCK)
			WHERE DiscountGroupId = @DiscountGroupId
		)
		MERGE CTE_DiscountGroupDetail AS t
		USING @TierRateSetting AS s ON t.DiscountGroupDetailId = s.DiscountGroupDetailId
		WHEN MATCHED THEN UPDATE
			SET t.FromAmount = s.FromAmount, t.ToAmount = s.ToAmount, t.Rate = s.Rate
		WHEN NOT MATCHED BY TARGET THEN INSERT
			(DiscountGroupId, FromAmount, ToAmount, Rate)
			VALUES (@DiscountGroupId, FromAmount, ToAmount, Rate)
		WHEN NOT MATCHED BY SOURCE THEN DELETE;
	END TRY
	BEGIN CATCH
		SELECT @ErrCode =  601, @ErrMsg = 'Insert failed. Please try again.'
		RETURN
	END CATCH
END
GO