/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountIns]
	@GroupName			VARCHAR(50),
	@DiscountGroupType	TINYINT, 
	@CurrencyId			TINYINT,
	@FromDate			DATE, 
	@ToDate				DATE, 
	@CalculationProductIds VARCHAR(512) = '', 
	@DiscountProductIds VARCHAR(512) = '',
	@CalculationType	INT, 
	@RateSettingsData	VARCHAR(MAX) = '', 
	@PartySettingsData	VARCHAR(MAX) = '', 
	@UserId				INT, 
	@LoginIp			VARCHAR (50)	= '', 
	@ErrCode			INT = 0 OUTPUT, 
	@ErrMsg				VARCHAR(4000)= '' OUTPUT, 
	@GroupIdOut			SMALLINT = 0 OUTPUT
AS
/*  
	Created: 20180702@Parsons [#94282]
	Task : Enhance Manage Discount group function to support more discount schemes
	DB: DB052.bodb_licensee   

	Revisions:  

	 Params:
		@RateSettingsData = '<Root>
								<RateSetting>
									<SeqNo>1</SeqNo>
									<FromAmount>1</FromAmount>
									<ToAmount>10000</ToAmount>
									<Rate>0.5</Rate>
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
									<Remark>hello1</Remark>
									<IsApplyDiscount>1</IsApplyDiscount>
								</PartySetting>
								<PartySetting>
									<PartyId>2</PartyId>
									<Remark>hello2</Remark>
									<IsApplyDiscount>0</IsApplyDiscount>
								</PartySetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @MaxAmountValue MONEY = 10000000000000
	
	--check empty
	IF ISNULL(@GroupName, '') = ''
	BEGIN
		SELECT @ErrCode = 501, @ErrMsg = 'Please fill out group name.'
		RETURN
	END

	DECLARE @Products TABLE (ProductId TINYINT, IsDiscount BIT, IsCalculation BIT)
	DECLARE @PartySettings	TABLE (PartyId SMALLINT, Remark NVARCHAR(500), IsApplyDiscount BIT)
	DECLARE @RateSettings	TABLE (FromAmount MONEY, ToAmount MONEY, Rate MONEY, RowIndex INT)
	
	DECLARE @docHandler INT

	--parse product discount group
	IF @CalculationProductIds = '' OR @DiscountProductIds = ''
	BEGIN
		SELECT @ErrMsg = 'Please select at least 1 product!', @ErrCode = 503
		RETURN	
	END

	INSERT INTO @Products(ProductId, IsDiscount, IsCalculation)
	SELECT val, 0, 1 FROM bodb02.dbo.strSplit(@CalculationProductIds, ',')
	
	;MERGE @Products AS t 
	USING bodb02.dbo.strSplit(@DiscountProductIds, ',') AS s ON t.ProductId = s.val
		WHEN MATCHED THEN UPDATE SET IsDiscount = 1
		WHEN NOT MATCHED THEN INSERT (ProductId, IsDiscount, IsCalculation) VALUES(s.val, 1, 0);

	--parse assigned payer to group
	IF @PartySettingsData <> ''
	BEGIN
		EXEC sp_xml_preparedocument @docHandler OUTPUT, @PartySettingsData
		INSERT INTO @PartySettings(PartyId, Remark, IsApplyDiscount)
		SELECT PartyId, Remark,  IsApplyDiscount
		FROM OPENXML(@docHandler, 'Root/PartySetting')
		WITH (PartyId	INT 'PartyId', 
				Remark	NVARCHAR(4000) 'Remark', 
				IsApplyDiscount BIT 'IsApplyDiscount')
	
		EXEC sp_xml_removedocument @docHandler
	END
	--parse setting rate
	IF @RateSettingsData <> ''
	BEGIN
		EXEC sp_xml_preparedocument @docHandler OUTPUT, @RateSettingsData
		INSERT INTO @RateSettings(FromAmount, ToAmount, Rate)
		SELECT FromAmount, 
				CASE WHEN ToAmount = 'Unlimited' THEN @MaxAmountValue ELSE CAST(ToAmount AS MONEY) END, 
				CAST(Rate AS MONEY)
		FROM OPENXML(@docHandler, 'Root/RateSetting')
		WITH (FromAmount MONEY 'FromAmount', 
				ToAmount VARCHAR(50) 'ToAmount', 
				Rate DECIMAL(9, 8) 'Rate' )
	
		EXEC sp_xml_removedocument @docHandler
	END

	--check required fields
	IF @FromDate IS NULL 
		OR @ToDate IS NULL
		OR ISNULL(@CurrencyId, 0) = 0
		OR (NOT EXISTS (SELECT 1 FROM @RateSettings))
	BEGIN
		SELECT @ErrMsg = 'Please fill all required field.', @ErrCode = 503
		RETURN
	END

	--overlap rank discount
	IF EXISTS (SELECT TOP 1 1 FROM @RateSettings)
		AND EXISTS (SELECT TOP 1 1
				FROM @RateSettings s1
					INNER JOIN @RateSettings s2 ON s1.RowIndex + 1 = s2.RowIndex
				WHERE s1.ToAmount >= s2.FromAmount
					OR s1.FromAmount < 0)
	BEGIN
		SELECT @ErrMsg = 'The rank is overlapped with the other please input another rank.', @ErrCode = 506
		RETURN
	END
	
	--Rate value less than zero
	IF EXISTS (SELECT TOP 1 1 FROM @RateSettings)
		AND EXISTS (SELECT TOP 1 1 FROM @RateSettings WHERE Rate <= 0)
	BEGIN
		SELECT @ErrMsg = 'Please enter rate number greater than zero.', @ErrCode =  503
		RETURN
	END

	--#Region Insert
	--insert discount group header
	INSERT INTO dbo.LA_DiscountGroupHeader(DiscountGroupName, DiscountGroupType, CurrencyId, FromDate, ToDate, [Priority], CalculationType,ModifiedDate)
	VALUES(@GroupName, @DiscountGroupType, @CurrencyId, @FromDate, @ToDate, 1, @CalculationType,GETDATE())

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode =  503
		RETURN
	END

	SET @GroupIdOut = SCOPE_IDENTITY()
	IF ISNULL(@GroupIdOut, 0) = 0
	BEGIN
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode =  503
		RETURN
	END

	--insert discount group assignment
	INSERT INTO dbo.LA_DiscountGroupAssignment(DiscountGroupId, PartyID, Remark, IsApplyDiscount)
	SELECT DISTINCT @GroupIdOut, PartyId, Remark, IsApplyDiscount
	FROM @PartySettings

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode =  503
		RETURN	
	END

	--insert discount group detail
	INSERT INTO dbo.LA_DiscountGroupDetail(DiscountGroupId, FromAmount, ToAmount, Rate)
	SELECT @GroupIdOut, FromAmount, ToAmount, Rate
	FROM @RateSettings

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode =  503
		RETURN	
	END

	--insert discount group product
	INSERT INTO dbo.LA_DiscountGroupProduct(DiscountGroupId, ProductId, IsDiscountProduct, IsCalculationProduct)
	SELECT @GroupIdOut, ProductId, IsDiscount, IsCalculation
	FROM @Products

	IF @@ERROR <> 0
	BEGIN
		DELETE dbo.LA_DiscountGroupHeader WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		DELETE dbo.LA_DiscountGroupDetail WITH(ROWLOCK) WHERE DiscountGroupId = @GroupIdOut
		SELECT @ErrMsg = 'Insert failed. Please try again.', @ErrCode =  503
		RETURN	
	END
	--#Endregion Insert
END
GO
