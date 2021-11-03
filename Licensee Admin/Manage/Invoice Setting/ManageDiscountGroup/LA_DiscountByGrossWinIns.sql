/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountByGrossWinIns]
	@DiscountGroupName		NVARCHAR(50)
	,@CurrencyId			TINYINT
	,@FromDate				DATE
	,@ToDate				DATE
	,@ProductIds			VARCHAR(MAX) = ''
	,@RateSettingsData		VARCHAR(MAX) = ''
	,@PartySettingsData		NVARCHAR(MAX) = ''
	,@CurrencySettingsData	VARCHAR(MAX) = ''
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
	 
	 Params:
		@RateSettingsData = '<Root>
								<RateSetting>
									<SeqNo>1</SeqNo>
									<FromAmount>1</FromAmount>
									<ToAmount>10000</ToAmount>
									<Rate>0.05</Rate>
								</RateSetting>
								<RateSetting>
									<SeqNo>2</SeqNo>
									<DiscountDetailId>1</DiscountDetailId>
									<FromAmount>10001</FromAmount>
									<ToAmount>20000</ToAmount>
									<Rate>0.1</Rate>
								</RateSetting>
							</Root>'
		@PartySettingsData = '<Root>
								<PartySetting>
									<PartyId>1</PartyId>
									<ChargeRate>0.1<ChargeRate>
									<Remark>hello1</Remark>
								</PartySetting>
								<PartySetting>
									<PartyId>2</PartyId>
									<ChargeRate>0.1<ChargeRate>
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
	
	-- Validate input data
	BEGIN
		IF ISNULL(@DiscountGroupName, '') = ''
		BEGIN
			SELECT @ErrCode = 501, @ErrMsg = 'Please fill out group name.'
			RETURN
		END

		IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK) WHERE DiscountGroupName = @DiscountGroupName AND DiscountGroupType <> 2) -- 2: Rebate
		BEGIN
			SELECT @ErrCode = 502, @ErrMsg = 'Group name exists. Please try again.'
			RETURN
		END

		IF ISNULL(@ProductIds, '') = ''
		BEGIN
			SELECT @ErrCode = 503, @ErrMsg = 'Please select at least 1 product.'
			RETURN
		END
	END

	DECLARE @ToBeCalculated TINYINT = 1
	DECLARE @ToBeDiscounted TINYINT = 0
	DECLARE @CalculateAndDiscount TINYINT = 10
	DECLARE @MaxAmountValue MONEY = 10000000000000 --  10,000,000,000,000

	-- Prepare input data
	DECLARE @PartyXML XML = CONVERT(XML, @PartySettingsData)
	DECLARE @CurrencyXML XML = CONVERT(XML, @CurrencySettingsData)
	DECLARE @TierRateSettingXML XML = CONVERT(XML, @RateSettingsData)

	DECLARE @ProductList TABLE (ProductId TINYINT)
	DECLARE @PartyList	TABLE (PartyId INT, ChargeRate FLOAT, Remark NVARCHAR(500))
	DECLARE @CurrencyList TABLE (PartyId INT, CurrencyId INT, CalculationType TINYINT)
	DECLARE @TierRateSetting TABLE (RowId INT, FromAmount MONEY, ToAmount MONEY, Rate MONEY)

	BEGIN
		INSERT INTO @ProductList (ProductId)
		SELECT DISTINCT val FROM dbo.strSplit(@ProductIds, ',')

		DELETE p
		FROM @ProductList p
			LEFT JOIN dbo.LA_f_Products3rd('') pd ON p.ProductId = pd.ProductId
		WHERE pd.ProductId IS NULL

		IF NOT EXISTS (SELECT 1 FROM @ProductList)
		BEGIN
			SELECT @ErrCode = 504, @ErrMsg = 'Product(s) do not exist.'
			RETURN
		END

		INSERT INTO @PartyList (PartyId, ChargeRate, Remark)
		SELECT t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
			,t.c.value('(ChargeRate/text())[1]', 'FLOAT') AS ChargeRate
			,t.c.value('(Remark/text())[1]', 'NVARCHAR(500)') AS Remark
		FROM @PartyXML.nodes('Root/PartySetting') AS t(c)

		INSERT INTO @CurrencyList (PartyId, CurrencyId, CalculationType)
		SELECT t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
			,t.c.value('(CurrencyId/text())[1]', 'INT') AS CurrencyId
			,t.c.value('(CalculationType/text())[1]', 'TINYINT') AS CalculationType
		FROM @CurrencyXML.nodes('Root/CurrencySetting') AS t(c)

		INSERT INTO @TierRateSetting (RowId, FromAmount, ToAmount, Rate)
		SELECT t.c.value('(SeqNo/text())[1]', 'INT') AS RowId
			,t.c.value('(FromAmount/text())[1]', 'FLOAT') AS FromAmount
			,t.c.value('(ToAmount/text())[1]', 'NVARCHAR(500)') AS ToAmount
			,t.c.value('(Rate/text())[1]', 'FLOAT') AS Rate
		FROM @TierRateSettingXML.nodes('Root/RateSetting') AS t(c)
	END

	-- Insert data
	BEGIN TRY
		INSERT INTO dbo.LA_DiscountGroupHeader (DiscountGroupName, DiscountGroupType, CurrencyId, FromDate, ToDate, Priority, ModifiedDate)
		VALUES (@DiscountGroupName, 13, @CurrencyId, @FromDate, @ToDate, 1, GETDATE())

		SET @GroupIdOut = SCOPE_IDENTITY()

		IF ISNULL(@GroupIdOut, 0) = 0
		BEGIN
			SELECT @ErrCode =  510, @ErrMsg = 'Insert failed. Please try again.'
			RETURN
		END

		INSERT INTO dbo.LA_DiscountGroupAssignment (DiscountGroupId, PartyId, Remark, IsApplyDiscount, IsSpecialTreatment)
		SELECT @GroupIdOut, PartyId, Remark, 1 AS IsApplyDiscount, 0 AS IsSpecialTreatment
		FROM @PartyList

		INSERT INTO dbo.LA_DiscountGroupCurrency (DiscountGroupId, PartyId, CurrencyId, CalculationType)
		SELECT @GroupIdOut, PartyId, CurrencyId, CalculationType
		FROM @CurrencyList
	END TRY
	BEGIN CATCH
		SELECT @ErrCode =  510, @ErrMsg = 'Insert failed. Please try again.'
		RETURN
	END CATCH
END
GO