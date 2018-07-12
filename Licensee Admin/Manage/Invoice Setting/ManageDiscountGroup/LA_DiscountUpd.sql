/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountUpd]
	@DiscountGroupId	SMALLINT = 0,
	@DiscountGroupName	NVARCHAR(50),
	@DiscountGroupType	TINYINT, 
	@CurrencyId			TINYINT,
	@FromDate			DATE, 
	@ToDate				DATE, 
	@CalculationProductIds VARCHAR(512) = '', 
	@DiscountProductIds VARCHAR(512) = '',
	@RateSettingsData	VARCHAR(MAX) = '', 
	@PartySettingsData	VARCHAR(MAX) = '', 
	@UserId				INT, 
	@LoginIp			VARCHAR (50)	= '', 
	@ErrCode			INT = 0 OUTPUT, 
	@ErrMsg				VARCHAR(4000)= '' OUTPUT
AS
/*  
	Created: 20180704@Parsons [#94282]
	Task : Enhance Manage Discount group function to support more discount schemes
	DB: DB052.bodb_licensee   

	Revisions:  
		- 20180704@Parsons: Update discount groups [#94282]
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
	DECLARE @ToBeCalculated TINYINT = 1
	DECLARE @ToBeDiscounted TINYINT = 0
	DECLARE @CalculateAndDiscount TINYINT = 10
	DECLARE @RebateGroupType TINYINT = 2

	--check empty
	IF ISNULL(@DiscountGroupName, '') = ''
	BEGIN
		SELECT @ErrCode = 501, @ErrMsg = 'Group name required.'
		RETURN
	END

	--check exists
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @DiscountGroupName AND DiscountGroupType != @RebateGroupType AND DiscountGroupId <> @DiscountGroupId)
	BEGIN
		SELECT @ErrCode = 502, @ErrMsg = 'Group name exists. Please try again.'
		RETURN
	END

	DECLARE @Products TABLE (ProductId TINYINT, CalculationType TINYINT)
	DECLARE @PartySettings	TABLE (PartyId SMALLINT, Remark NVARCHAR(500), IsApplyDiscount BIT)
	DECLARE @RateSettings	TABLE (DiscountDetailId SMALLINT, FromAmount MONEY, ToAmount MONEY, Rate MONEY, RowIndex INT)
	
	DECLARE @docHandler INT
	
	--parse product discount group
	IF @CalculationProductIds = '' OR @DiscountProductIds = ''
	BEGIN
		SELECT @ErrMsg = 'Please select at least 1 product!', @ErrCode = 503
		RETURN	
	END

	INSERT INTO @Products(ProductId, CalculationType)
	SELECT val, @ToBeCalculated FROM bodb02.dbo.strSplit(@CalculationProductIds, ',')
	
	;MERGE @Products AS t 
	USING bodb02.dbo.strSplit(@DiscountProductIds, ',') AS s ON t.ProductId = s.val
		WHEN MATCHED THEN UPDATE SET CalculationType = @CalculateAndDiscount
		WHEN NOT MATCHED THEN INSERT (ProductId, CalculationType) VALUES(s.val, @ToBeDiscounted);

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
		INSERT INTO @RateSettings(DiscountDetailId, FromAmount, ToAmount, Rate)
		SELECT	DiscountDetailId,
				FromAmount, 
				CASE WHEN ToAmount = 'Unlimited' THEN @MaxAmountValue ELSE CAST(ToAmount AS MONEY) END, 
				Rate
		FROM OPENXML(@docHandler, 'Root/RateSetting')
		WITH (	DiscountDetailId SMALLINT 'DiscountDetailId',
				FromAmount MONEY 'FromAmount', 
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
	
	--#Region Update
	IF ISNULL(@DiscountGroupId, 0) = 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.' , @ErrCode = 504
		RETURN
	END

	--update discount group assingment
	;MERGE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK, UPDLOCK) AS t
	USING @PartySettings AS s
	ON (t.DiscountGroupId = @DiscountGroupId AND t.PartyId = s.PartyId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, PartyID, Remark, IsApplyDiscount)
				VALUES(@DiscountGroupId, s.PartyId, s.Remark, s.IsApplyDiscount)
	WHEN MATCHED
		THEN UPDATE SET Remark = s.Remark, IsApplyDiscount = s.IsApplyDiscount
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @DiscountGroupId
		THEN DELETE;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.' , @ErrCode = 504
		RETURN
	END

	--update discount group product
	;MERGE dbo.LA_DiscountGroupProduct WITH(ROWLOCK, UPDLOCK) AS t
	USING @Products AS s
	ON (t.DiscountGroupId = @DiscountGroupId AND t.ProductId = s.ProductId)
	WHEN MATCHED THEN UPDATE SET CalculationType = s.CalculationType
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, ProductId, CalculationType)
				VALUES(@DiscountGroupId, s.ProductId, s.CalculationType)
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @DiscountGroupId
		THEN DELETE;
		
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.' , @ErrCode = 504
		RETURN
	END

	--update discouunt group detail
	;MERGE dbo.LA_DiscountGroupDetail WITH(ROWLOCK, UPDLOCK) AS t
	USING @RateSettings AS s
	ON (t.DiscountGroupDetailId = s.DiscountDetailId AND t.DiscountGroupId = @DiscountGroupId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(DiscountGroupId, FromAmount, ToAmount, Rate)
				VALUES(@DiscountGroupId, s.FromAmount, s.ToAmount, s.Rate)
	WHEN MATCHED
		THEN UPDATE SET FromAmount = s.FromAmount, ToAmount = s.ToAmount, Rate = s.Rate
	WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @DiscountGroupId
		THEN DELETE;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.' , @ErrCode = 504
		RETURN
	END

	--update discount group header
	UPDATE dbo.LA_DiscountGroupHeader WITH(ROWLOCK, UPDLOCK)
	SET DiscountGroupName = @DiscountGroupName, 
		CurrencyId = @CurrencyId, 
		FromDate = @FromDate, 
		ToDate = @ToDate,
		DiscountGroupType = @DiscountGroupType,
		ModifiedDate = GETDATE()
	WHERE DiscountGroupId = @DiscountGroupId
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.' , @ErrCode = 504
		RETURN
	END
		
	END
GO