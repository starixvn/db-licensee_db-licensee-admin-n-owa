USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_DiscountModify @GroupId SMALLINT = 0
	, @GroupName VARCHAR(50)
	, @GroupType TINYINT
	, @CurrencyId TINYINT
	, @FromDate DATE
	, @ToDate DATE
	, @IsEdit BIT
	, @ProductXml VARCHAR(4000) = ''
	, @AssignedPayersXml VARCHAR(MAX) = ''
	, @RateSettingsXml VARCHAR(MAX) = ''

	, @UserId INT
	, @LoginIp VARCHAR (50)	= ''

	, @ErrCode INT = 0 OUTPUT
	, @ErrMsg VARCHAR(4000)= '' OUTPUT
	, @GroupIdOut SMALLINT = 0 OUTPUT
AS
/*  
	 Created: 20150421@Patrick
	 Task : Add new or edit existing discount
	 DB: DB052.bodb_Licensee
   
	 Revisions:
	 Params:
		@ProductXml = '<Root>
							<AssignedProduct>
								<ProductId>1</ProductId>
							</AssignedProduct>
							<AssignedProduct>
								<ProductId>2</ProductId>
							</AssignedProduct>
						</Root>'
		@AssignedPayersXml = '<Root>
								<AssignedPayer>
									<PayerId>1</PayerId>
								</AssignedPayer>
								<AssignedPayer>
									<PayerId>2</PayerId>
								</AssignedPayer>
							</Root>'
		@RateSettingsXml = '<Root>
								<RateSetting>
									<SeqNo>1</SeqNo>
									<FromAmount>1</FromAmount>
									<ToAmount>10000</ToAmount>
									<Rate>0.5</Rate>
								</RateSetting>
								<RateSetting>
									<SeqNo>2</SeqNo>
									<FromAmount>10001</FromAmount>
									<ToAmount>20000</ToAmount>
									<Rate>0.1</Rate>
								</RateSetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun DATETIME, @duration INT, @logSPData VARCHAR(MAX)
		, @logSPDataOld	VARCHAR(MAX), @xml XML, @MaxAmountValue MONEY = 10000000000000--922,337,203,685,477.5807
	SET @startRun = GETDATE()
	
	--check empty
	IF ISNULL(@GroupName, '') = ''
	BEGIN
		SELECT @ErrCode = 501, @ErrMsg = 'Group name required.'
		RETURN
	END

	--check exists
	IF EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName AND DiscountGroupType = @GroupType)
	BEGIN
		SELECT @ErrCode = 502, @ErrMsg = 'Group name exists. Please try again.'
		RETURN
	END

	DECLARE @Products TABLE (ProductId TINYINT)
	DECLARE @Payers TABLE (PayerId INT)
	DECLARE @RateSettings TABLE (RowIndex TINYINT IDENTITY(1,1), SeqNo TINYINT, FromAmount MONEY, ToAmount MONEY, Rate MONEY)
	DECLARE @RateSettingsTmp TABLE (SeqNo TINYINT, FromAmount MONEY, ToAmount MONEY, Rate MONEY)
	
	DECLARE @docHandler INT
	--parse product discount group
	IF @ProductXml = ''
	BEGIN
		SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
			, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
		RETURN	
	END

	EXEC sp_xml_preparedocument @docHandler OUTPUT, @ProductXml
	INSERT INTO @Products(ProductId)
	SELECT CAST(ProductId AS TINYINT)
	FROM OPENXML(@docHandler, '/Root/AssignedProduct')
	WITH (ProductId VARCHAR(10) 'ProductId')
	
	EXEC sp_xml_removedocument @docHandler

	--parse assigned payer to group
	IF @AssignedPayersXml <> ''
	BEGIN
		EXEC sp_xml_preparedocument @docHandler OUTPUT, @AssignedPayersXml
		INSERT INTO @Payers(PayerId)
		SELECT CAST(PayerId AS INT)
		FROM OPENXML(@docHandler, '/Root/AssignedPayer')
		WITH (PayerId VARCHAR(20) 'PayerId')
	
		EXEC sp_xml_removedocument @docHandler
	END
	--parse setting rate
	IF @RateSettingsXml <> ''
	BEGIN
		EXEC sp_xml_preparedocument @docHandler OUTPUT, @RateSettingsXml
		INSERT INTO @RateSettingsTmp(SeqNo, FromAmount, ToAmount, Rate)
		SELECT CAST(SeqNo AS TINYINT)
			, CAST(FromAmount AS MONEY)
			, CASE WHEN ToAmount = 'Unlimited' THEN @MaxAmountValue ELSE CAST(ToAmount AS MONEY) END
			, CAST(Rate AS MONEY)
		FROM OPENXML(@docHandler, 'Root/RateSetting')
		WITH (SeqNo VARCHAR(20) 'SeqNo'
			, FromAmount VARCHAR(50) 'FromAmount'
			, ToAmount VARCHAR(50) 'ToAmount'
			, Rate VARCHAR(50) 'Rate'
		)
	
		EXEC sp_xml_removedocument @docHandler
	END
	--check duplicated SeqNo
	INSERT INTO @RateSettings(SeqNo, FromAmount, ToAmount, Rate)
		SELECT SeqNo, FromAmount, ToAmount, Rate
		FROM @RateSettingsTmp
		ORDER BY SeqNo ASC

	IF EXISTS (SELECT TOP 1 1 FROM @RateSettings GROUP BY SeqNo HAVING COUNT(1) > 1)
	BEGIN
		SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
			, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
		RETURN
	END

	--check required field
	IF @CurrencyId IS NULL OR @FromDate IS NULL OR @ToDate IS NULL
		OR (NOT EXISTS (SELECT 1 FROM @Products))
		--OR (NOT EXISTS (SELECT 1 FROM @RateSettings))
	BEGIN
		SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
			, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
		RETURN
	END

	--overlap range discount & product & payer
	DECLARE @PayerList VARCHAR(500)
	IF EXISTS (SELECT TOP 1 1 FROM @Payers)
		AND EXISTS (SELECT TOP 1 1
				FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
					INNER JOIN dbo.LA_DiscountGroupProduct d WITH(NOLOCK) ON h.DiscountGroupId = d.DiscountGroupId
					INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
					INNER JOIN @Payers p ON a.PartyID = p.PayerId
				WHERE (@FromDate BETWEEN FromDate AND ToDate)
					OR (@ToDate BETWEEN FromDate AND ToDate))
	BEGIN
		SET @PayerList = NULL
		SELECT @PayerList = COALESCE(@PayerList + ',' + '''' + CASE WHEN ISNULL(dd.BrandName, '') = '' THEN ISNULL(pp.PartyName, '') ELSE ISNULL(dd.BrandName, '') END + ''''
									, '''' + CASE WHEN ISNULL(dd.BrandName, '') = '' THEN ISNULL(pp.PartyName, '') ELSE ISNULL(dd.BrandName, '') END + '''')
		FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupProduct d WITH(NOLOCK) ON h.DiscountGroupId = d.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
			INNER JOIN @Payers p ON a.PartyID = p.PayerId
			INNER JOIN dbo.OAS_Party pp ON p.PayerId = pp.PartyID
			INNER JOIN dbo.OAS_PartyDetail dd WITH(NOLOCK) ON pp.PartyID = dd.PartyID
		WHERE (@FromDate BETWEEN FromDate AND ToDate)
			OR (@ToDate BETWEEN FromDate AND ToDate)
		
		SELECT @ErrMsg = CASE WHEN @GroupType = 1 THEN 'Payer ' + @PayerList + ' which being applied other discount at the time. Please check again.'
							ELSE 'Payer ' + @PayerList + ' which being applied other rebate at the time, please check again' END
			, @ErrCode = 505
		RETURN	
	END
	
	--overlap rank discount
	IF @GroupType = 1 --> discount
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM @RateSettings)
			AND EXISTS (SELECT TOP 1 1
					FROM @RateSettings s1
						INNER JOIN @RateSettings s2 ON s1.RowIndex + 1 = s2.RowIndex
					WHERE s1.ToAmount >= s2.FromAmount
						OR s1.FromAmount < 0)
		BEGIN
			SELECT @ErrMsg = 'The rank is overlapped with the other please input another rank.'
				, @ErrCode = 506
			RETURN
		END
	END
	
	IF EXISTS (SELECT TOP 1 1 FROM @RateSettings)
		AND EXISTS (SELECT 1 FROM @RateSettings WHERE Rate <= 0)
	BEGIN
		SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
			, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
		RETURN
	END

	--incorrect params value from IU
	IF @IsEdit = 0 AND EXISTS (SELECT 1 FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupName = @GroupName)
	BEGIN
		SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
			, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
		RETURN
	END

	IF @IsEdit = 0
	BEGIN
		--insert discount group header
		INSERT INTO dbo.LA_DiscountGroupHeader(DiscountGroupName, DiscountGroupType, CurrencyId, FromDate, ToDate, Priority)
		VALUES(@GroupName, @GroupType, @CurrencyId, @FromDate, @ToDate, CASE WHEN @GroupType = 1 THEN 1 ELSE 2 END)

		IF @@ERROR <> 0
			RETURN
		SET @GroupIdOut = SCOPE_IDENTITY()
		IF @GroupIdOut IS NULL OR @GroupIdOut = 0
		BEGIN
			SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
				, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
			RETURN
		END

		--insert discount group detail
		INSERT INTO dbo.LA_DiscountGroupDetail(DiscountGroupId, FromAmount, ToAmount, Rate)
		SELECT @GroupIdOut, FromAmount, ToAmount, Rate
		FROM @RateSettings

		IF @@ERROR <> 0
		BEGIN
			DELETE dbo.LA_DiscountGroupHeader WHERE DiscountGroupId = @GroupIdOut
			SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
				, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
			RETURN
		END

		--insert discount group product
		INSERT INTO dbo.LA_DiscountGroupProduct(DiscountGroupId, ProductId)
		SELECT @GroupIdOut, ProductId
		FROM @Products

		IF @@ERROR <> 0
		BEGIN
			DELETE dbo.LA_DiscountGroupHeader WHERE DiscountGroupId = @GroupIdOut
			DELETE dbo.LA_DiscountGroupDetail WHERE DiscountGroupId = @GroupIdOut
			SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
				, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
			RETURN
		END

		--insert discount group assignment
		INSERT INTO dbo.LA_DiscountGroupAssignment(DiscountGroupId, PartyID)
		SELECT @GroupIdOut, PayerId
		FROM @Payers

		IF @@ERROR <> 0
		BEGIN
			DELETE dbo.LA_DiscountGroupHeader WHERE DiscountGroupId = @GroupIdOut
			DELETE dbo.LA_DiscountGroupDetail WHERE DiscountGroupId = @GroupIdOut
			DELETE dbo.LA_DiscountGroupProduct WHERE DiscountGroupId = @GroupIdOut
			SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
				, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
			RETURN
		END

	END
	ELSE --edit case
	BEGIN
		IF @GroupId = 0 OR @GroupId IS NULL
		BEGIN
			SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
				, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
			RETURN
		END

		--validate list of Payers have applied to billing Invoice yet
		DECLARE @PayerIdBeingRemoveList VARCHAR(4000)
		SELECT COALESCE(@PayerIdBeingRemoveList + ',' + CAST(a.PartyId AS VARCHAR), CAST(a.PartyId AS VARCHAR))
		FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
		WHERE DiscountGroupId = @GroupId
			AND PartyId NOT IN (SELECT PayerId FROM @Payers)

		IF ISNULL(@PayerIdBeingRemoveList, '') <> ''
		BEGIN
			EXEC dbo.LA_Discount_ValidatePayerAssignment @DiscountId = @GroupId
				, @PayerIdList  = @PayerIdBeingRemoveList
				, @Mode = 'R'

				, @ErrCode = @ErrCode OUTPUT
				, @ErrMsg = @ErrMsg OUTPUT
			IF @ErrCode > 0
				RETURN
		END
		
		--get old data for write log
		SET @xml = (
				SELECT DiscountGroupId AS '@gd'
					, DiscountGroupName AS '@gn'
					, CurrencyId AS '@c'
					, FromDate AS '@fd'
					, ToDate AS '@td'
					, DiscountGroupType AS '@dt'
					, Priority AS '@pr'
					, (SELECT DiscountGroupId AS '@dg'
						, FromAmount AS '@fam'
						, ToAmount AS '@tam'
						, Rate AS '@r'
					FROM dbo.LA_DiscountGroupDetail WITH(NOLOCK)
					FOR XML PATH('x'), TYPE)
					, (SELECT DiscountGroupId AS '@gd'
						, ProductId AS '@p'
					FROM dbo.LA_DiscountGroupProduct
					FOR XML PATH('y'), TYPE)
					, (SELECT DiscountGroupId AS '@gd'
						, PartyID AS '@pa'
					FROM dbo.LA_DiscountGroupAssignment
					FOR XML PATH('z'), TYPE)
				FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupId = @GroupId
				FOR XML PATH('r'), TYPE)

		SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')

		--update discount group assingment
		;MERGE dbo.LA_DiscountGroupAssignment WITH(ROWLOCK, UPDLOCK) AS t
		USING @Payers AS s
		ON (t.DiscountGroupId = @GroupId)
		WHEN NOT MATCHED BY TARGET
			THEN INSERT(DiscountGroupId, PartyId)
				 VALUES(@GroupId, s.PayerId)
		WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
			THEN DELETE;

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
				, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
			RETURN
		END

		--update discount group product
		;MERGE dbo.LA_DiscountGroupProduct WITH(ROWLOCK, UPDLOCK) AS t
		USING @Products AS s
		ON (t.DiscountGroupId = @GroupId)
		WHEN NOT MATCHED BY TARGET
			THEN INSERT(DiscountGroupId, ProductId)
				 VALUES(@GroupId, s.ProductId)
		WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
			THEN DELETE;

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
				, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
			RETURN
		END

		--update discouunt group detail
		;MERGE dbo.LA_DiscountGroupDetail WITH(ROWLOCK, UPDLOCK) AS t
		USING @RateSettings AS s
		ON (t.DiscountGroupId = @GroupId)
		WHEN NOT MATCHED BY TARGET
			THEN INSERT(DiscountGroupId, FromAmount, ToAmount, Rate)
				 VALUES(@GroupId, s.FromAmount, s.ToAmount, s.Rate)
		WHEN MATCHED
			THEN UPDATE SET FromAmount = s.FromAmount, ToAmount = s.ToAmount, Rate = s.Rate
		WHEN NOT MATCHED BY SOURCE AND t.DiscountGroupId = @GroupId
			THEN DELETE;

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
				, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
			RETURN
		END

		--update discount group header
		UPDATE dbo.LA_DiscountGroupHeader WITH(ROWLOCK, UPDLOCK)
		SET DiscountGroupName = @GroupName
			, CurrencyId = CASE WHEN @GroupType = 1 THEN @CurrencyId ELSE 0 END
			, FromDate = @FromDate
			, ToDate = @ToDate
		WHERE DiscountGroupId = @GroupId

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = CASE WHEN @IsEdit = 0 THEN 'Insert failed. Please try again.' ELSE 'Update failed. Please try again.' END
				, @ErrCode = CASE WHEN @IsEdit = 0 THEN 503	ELSE 504 END
			RETURN
		END

		SET @GroupIdOut = @GroupId
		
	END
	--write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	SET @xml = (
			SELECT @GroupIdOut AS '@gd'
				, @GroupName AS '@gn'
				, @CurrencyId AS '@c'
				, @FromDate AS '@fd'
				, @ToDate AS '@td'
				, @GroupType AS '@dt'
				, CASE WHEN @GroupType = 1 THEN 1 ELSE 2 END AS '@pr'
				, (SELECT @GroupIdOut AS '@gd'
					, FromAmount AS '@fam'
					, ToAmount AS '@tam'
					, Rate AS '@r'
				FROM @RateSettings
				FOR XML PATH('x'), TYPE)
				, (SELECT @GroupIdOut AS '@gd'
					, ProductId AS '@p'
				FROM @Products
				FOR XML PATH('y'), TYPE)
				, (SELECT @GroupIdOut AS '@gd'
					, PayerId AS '@pa'
				FROM @Payers
				FOR XML PATH('z'), TYPE)
			FOR XML PATH('r'), TYPE)

		SET @logSpData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')

	--get log action
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_DiscountModify'
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog @UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_DiscountModify'
			, @CustId = 0
			, @ActionId = @ActionID
			, @Duration = @duration
			, @Data = @logSPData
			, @OldData = @logSPDataOld		
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP @UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = @LogSPData
			, @TrackingValue2 = @logSPDataOld
			, @duration = @duration
	END CATCH	
END
