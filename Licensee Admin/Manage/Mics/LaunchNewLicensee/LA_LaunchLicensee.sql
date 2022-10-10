/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_LaunchLicensee]
	@NonOfficialPartyId		INT,
	@LicenseeId				INT,
	@PayerName				VARCHAR(50),
	@BrandName				VARCHAR(100)	= '',
	@LicenseeCode			VARCHAR(50)		= '',
	@BaseCurrencyId			TINYINT,
	@LaunchDate				DATE, 
	@BillingGroupId			INT,
	@ProductIds				VARCHAR(1000)	= '',
	@InvoiceLanguage		VARCHAR(7)		= '',
	@ChargeInfoSettingData	NVARCHAR(MAX),
	@UserId					INT,
	@LoginIP				VARCHAR (50)	= '',
	@NewPartyId				INT				= 0		OUTPUT,
	@ErrCode				INT				= 0		OUTPUT,
	@ErrMsg					VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20190107@Parsons
	Task : Launch new licensee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20190107@Parsons: Launch new licensee
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20190829@Bruce: Adding Licensee Code [#111586] 
		- 20210324@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
		- 20210811@Danny: Adding @InvoiceLanguage [#FeatureID 158133]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20220623@Percy: Remove dropdown function & user [RedmineID: #166504]
		- 20220831@Malcolm: Automate the PT adjustment when the charge rate is changed [RemineID: #171705]

	Param's Explannation: 
						@ChargeInfoSettingData = '<Root>
								<ChargeInfoSetting>
									<ProductId>0</ProductId>
									<Rate>0.15</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>15% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
								<ChargeInfoSetting>
									<ProductId>1</ProductId>
									<Rate>0.1</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>10% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE 
		@StartRun		DATETIME = CURRENT_TIMESTAMP, 
		@EndRun			DATETIME, 
		@Duration		INT, 
		@Doing			NVARCHAR(MAX)

	SELECT @ErrCode = 0, @ErrMsg = ''

	-- Prepare input params
	DECLARE @Products TABLE (ProductId INT)
	DECLARE @ChargeInfoSettings	TABLE (ProductId INT, Rate MONEY, Remark NVARCHAR(400), BasisOfBilling NVARCHAR(500), ChargeType INT, FromDate DATE, ToDate DATE)
	DECLARE @MinFeeSettings	TABLE (ProductId TINYINT, FeeTypeId TINYINT, FeeAmount MONEY, FromDate DATE, ToDate DATE, MinFeeTerm NVARCHAR(1000), [Priority] TINYINT, MonthOfDeduction TINYINT)
	DECLARE @ChargeInfo TABLE (ChargeId INT, ProductId INT, ProductName VARCHAR(50), Rate MONEY, ChargeType INT, FromDate DATE, ToDate DATE, CurrencyId INT, SystemId INT, IsValid BIT DEFAULT(1))
	DECLARE @AMF MONEY, @BillingGroupName NVARCHAR(50), @BillerId INT, @FirstDateOfMonth DATE, @SiteName VARCHAR(20) ='', @InputPT VARCHAR(MAX) = '', @ChargeRateXML XML, @Username VARCHAR(50)
	
	-- Charge Rate, Min Fee
	BEGIN TRY
		DECLARE @ChargeInfoSettingXML XML = CONVERT(XML, @ChargeInfoSettingData)
		
		INSERT INTO @ChargeInfoSettings (ProductId, Rate, Remark, BasisOfBilling, ChargeType, FromDate, ToDate)
		SELECT
			t.c.value('(ProductId/text())[1]', 'INT')					AS ProductId
			,t.c.value('(Rate/text())[1]', 'MONEY')						AS Rate
			,t.c.value('(Remark/text())[1]', 'NVARCHAR(400)')			AS Remark
			,t.c.value('(BasisOfBilling/text())[1]', 'NVARCHAR(500)')	AS BasisOfBilling
			,t.c.value('(ChargeType/text())[1]', 'INT')					AS ChargeType
			,t.c.value('(FromDate/text())[1]', 'DATE')					AS FromDate
			,t.c.value('(ToDate/text())[1]', 'DATE')					AS ToDate
		FROM @ChargeInfoSettingXML.nodes('Root/ChargeInfoSetting') t(c)
		OPTION (OPTIMIZE FOR (@ChargeInfoSettingXML = NULL))
	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'Charge info setting data invalid. Please try again.', @ErrCode =  501
		RETURN
	END CATCH

	-- Validate input params
	BEGIN
		IF @NonOfficialPartyId > 0 AND NOT EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID = @NonOfficialPartyId) 
		BEGIN
			SELECT @ErrMsg = 'Party not found. Please try again.', @ErrCode =  505
			RETURN
		END

		IF EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID <> @NonOfficialPartyId AND PartyName = @PayerName) 
		BEGIN
			SELECT @ErrMsg = 'Party name has already been existed. Please try again.', @ErrCode =  506
			RETURN
		END

		IF EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE OldRefID = @LicenseeId AND PartyType = 1) 
		BEGIN
			SELECT @ErrMsg = 'Party has already been launched.', @ErrCode =  507
			RETURN
		END
	END

	INSERT INTO @Products (ProductId)
	SELECT value FROM STRING_SPLIT(@ProductIds, ',')

	SELECT @Username = Username FROM LA_User WITH(NOLOCK) WHERE UserID = @UserID 

	SELECT @FirstDateOfMonth = DATEADD(MONTH, DATEDIFF(MONTH, 0, @LaunchDate), 0)

	SELECT @BillingGroupName = PartyName
	FROM dbo.OAS_Party WITH(NOLOCK)
	WHERE PartyId = @BillingGroupId

	SELECT @BillerId = PartyId
	FROM dbo.LA_BillerInfo WITH(NOLOCK)
	WHERE BillerName = CASE @BillingGroupName
						WHEN 'Boping' THEN @BillingGroupName
						WHEN 'Zelianta' THEN @BillingGroupName + ' Limited'
						ELSE '' END

	SELECT @AMF = SUM(ISNULL(d.Income, 0))
	FROM dbo.LA_InvoiceHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceStatement d WITH(NOLOCK) ON h.InvoiceHeaderId = d.InvoiceHeaderId
	WHERE h.InvoiceType = 7 AND d.InvItemTypeId = 3 -- AMF in Setup fee
		AND h.StatusId = 0 AND h.Environment = 'LOCAL'					
		AND h.PartyId = @NonOfficialPartyId
		AND h.CurrencyId = @BaseCurrencyId

	-- Launch licensee
	BEGIN TRY
		-- LicenseeProduct3rd
		UPDATE dbo.LicenseeProduct3rd WITH(ROWLOCK)
		SET EffectiveDate = @LaunchDate
		WHERE LicenseeId = @LicenseeId

		-- OAS_Party
		IF @NonOfficialPartyId > 0
		BEGIN
			UPDATE dbo.OAS_Party WITH(ROWLOCK)
			SET OldRefID   = @LicenseeId
				,SetupName = PartyName
				,PartyType = 1
				,PartyName = @PayerName
			WHERE PartyID = @NonOfficialPartyId

			SET @NewPartyId = @NonOfficialPartyId
		END
		ELSE
		BEGIN
			INSERT INTO dbo.OAS_Party (PartyName, PartyType, OldRefID)
			VALUES (@PayerName, 1, @LicenseeId)

			SET @NewPartyId = SCOPE_IDENTITY()
		END

		-- OAS_PartyDetail
		IF EXISTS (SELECT 1 FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE PartyID = @NewPartyId)
			UPDATE dbo.OAS_PartyDetail WITH(ROWLOCK)
			SET BrandName = @BrandName
				,BaseCurrencyId = @BaseCurrencyId
				,StatusId = 1
				,LicenseeCode = @LicenseeCode
				,InvoiceLanguage = @InvoiceLanguage
				,LaunchDate = @LaunchDate
			WHERE PartyID = @NewPartyId
		ELSE
			INSERT INTO dbo.OAS_PartyDetail (PartyID, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm, BaseCurrencyId, StatusId, LicenseeCode, InvoiceLanguage, LaunchDate)
			SELECT @NewPartyId, IsDeposit, @BrandName, CompanyName, IsAllowedMemberComm, @BaseCurrencyId, 1, @LicenseeCode, @InvoiceLanguage, @LaunchDate
			FROM dbo.Licensees WITH(NOLOCK)
			WHERE LicenseeID = @LicenseeId

		-- OAS_PartyBaseCurrency
		IF EXISTS (SELECT 1 FROM dbo.OAS_PartyBaseCurrency WITH(NOLOCK) WHERE PartyID = @NewPartyId)
			DELETE dbo.OAS_PartyBaseCurrency WITH(ROWLOCK) WHERE PartyID = @NewPartyId
			
		INSERT INTO dbo.OAS_PartyBaseCurrency (PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
		VALUES (@NewPartyId, @BaseCurrencyId, ISNULL(@LicenseeCode, ''), @FirstDateOfMonth, '2050-01-01')

		-- OAS_ChargeInfo
		INSERT INTO dbo.OAS_ChargeInfo (ProductID, FromParty, ToParty, ParentChargeID, Rate, Remark, BasisOfBilling, ChargeType, FirstOfBilling, FromDate, ToDate, BaseCurrencyId)
			OUTPUT INSERTED.ChargeID, INSERTED.ProductID, inserted.Rate, inserted.ChargeType, inserted.FromDate, inserted.ToDate, 2, 0
				INTO @ChargeInfo (ChargeID, ProductId, Rate, ChargeType, FromDate, ToDate, SystemId, CurrencyId)
		SELECT ProductId, @NewPartyId, @BillingGroupId, 0, Rate, Remark, BasisOfBilling, ChargeType, FromDate, FromDate, ToDate, @BaseCurrencyId
		FROM @ChargeInfoSettings

		IF @BillingGroupId = 1 -- OW
			INSERT INTO @ChargeInfo (ChargeId, ProductId, SystemId)
			SELECT ChargeId, ProductId, 4
			FROM @ChargeInfo
			WHERE ProductId IN (0, 2, 3, 4, 5, 10, 11, 12) -- SB,NG,BA,LC,VS,AGC,GD,VG
		
		-- LA_ChargeInfo_SystemMapping
		INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
		SELECT ChargeId, SystemID FROM @ChargeInfo

		IF ISNULL(@AMF, 0) > 0
			UPDATE @MinFeeSettings
			SET MonthOfDeduction = CEILING(@AMF / NULLIF(FeeAmount, 0))
			WHERE FeeTypeId = 1 AND ProductId = 0
		
		-- LA_MinFee
		INSERT INTO dbo.LA_MinFee (PartyId, ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], CurrencyId, MonthOfDeduction)
		SELECT @NewPartyId, ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], @BaseCurrencyId, MonthOfDeduction 
		FROM @MinFeeSettings

		-- LA_InvoiceSetting
		IF ISNULL(@BillerId, 0) <> 0
			INSERT INTO dbo.LA_InvoiceSetting (FromPartyId, ToPartyId, ProductId, InvTypeId, InvTempId, BankId, ActiveAddress)
			SELECT @NewPartyId, @BillerId, ProductId, InvTypeId, InvTemplateId, 0 AS BankId, 1 AS ActiveAddress
			FROM (
				SELECT InvTemplateId, InvTemplateName
					,CASE InvTemplateName
						WHEN @BillingGroupName THEN 1 -- Software Data & Licensing Fees
						WHEN 'Credit' THEN 4 -- Credit Note
						ELSE 5 -- Debit Note
						END AS InvTypeId
				FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
				WHERE 1 = CASE InvTemplateName
							WHEN @BillingGroupName THEN 1
							WHEN 'Credit' THEN 1
							WHEN 'Debit' + CASE WHEN @BillingGroupName = 'Zelianta' THEN '-Zelianta' ELSE '' END THEN 1
							ELSE 0 END
			) ivt
				OUTER APPLY (
					SELECT p.ProductId
					FROM @Products p
						INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON p.ProductId = c.ProductId
					WHERE c.FromParty = @NewPartyId AND c.ToParty = @BillingGroupId
						AND c.FromDate = @LaunchDate
						AND ivt.InvTemplateName IN ('Boping', 'Zelianta')
				) p

		-- LA_UserParty
		DECLARE @ExcludeUsers TABLE (UserName VARCHAR(50))
		DECLARE @ExcludeUsersJson VARCHAR(4000)
		
		SELECT @ExcludeUsersJson = a.[Value]
		FROM dbo.LA_SystemSettings s WITH (NOLOCK)
			CROSS APPLY (SELECT t.[Value] FROM OPENJSON(s.[Value]) t) a
		WHERE s.[Key] = 'LaunchLicensee_ExcludeUser'
		
		;WITH CTE_ExcludeUsers AS (
			SELECT [Name], Users
			FROM OPENJSON(@ExcludeUsersJson) WITH (
				[Name] VARCHAR(100) '$.Name',
				Users NVARCHAR(MAX) '$.Users' AS JSON
			)
		)
		INSERT INTO @ExcludeUsers (UserName)
		SELECT b.[Value]
		FROM CTE_ExcludeUsers u
			CROSS APPLY (
				SELECT a.[Value] FROM OPENJSON(u.Users) a
			) b
		WHERE u.[Name] = @BillingGroupName

		INSERT INTO dbo.LA_UserParty (UserID, PartyID, Modifydate, Modifier, StatusID)
		SELECT UserID, @NewPartyId, GETDATE(), @UserID, 1
		FROM dbo.LA_User u WITH (NOLOCK)
			LEFT JOIN @ExcludeUsers eu ON u.Username = eu.UserName
		WHERE StatusID = 1 -- Active users
			AND eu.UserName IS NULL

		-- LA_FunctionParty
		INSERT INTO dbo.LA_FunctionParty (FunctionID, PartyID)
		SELECT FunctionID, @NewPartyId
		FROM dbo.LA_Function WITH (NOLOCK) 
		WHERE StatusID = 1 -- Active functions
	END TRY
	BEGIN CATCH
		-- Rollback
		IF @NonOfficialPartyId > 0
		BEGIN
			UPDATE dbo.OAS_Party
			SET OldRefID   = NULL
				,SetupName = NULL
				,PartyType = 5
				,PartyName = ISNULL(SetupName, PartyName)
			WHERE PartyId = @NonOfficialPartyId

			UPDATE dbo.OAS_PartyDetail
			SET StatusId = 0
			WHERE PartyId = @NonOfficialPartyId
		END
		ELSE
		BEGIN
			DELETE dbo.OAS_Party WHERE PartyId = @NewPartyId
			DELETE dbo.OAS_PartyDetail WHERE PartyId = @NewPartyId
		END

		DELETE l
		FROM dbo.LA_ChargeInfo_SystemMapping l
			INNER JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON l.ChargeID = c.ChargeID
		WHERE c.FromParty = @NewPartyId

		DELETE dbo.OAS_PartyBaseCurrency WHERE PartyId = @NewPartyId
		DELETE dbo.OAS_ChargeInfo WHERE FromParty = @NewPartyId
		DELETE dbo.LA_InvoiceSetting WHERE FromPartyId = @NewPartyId
		DELETE dbo.LA_UserParty WHERE PartyId = @NewPartyId
		DELETE dbo.LA_FunctionParty WHERE PartyId = @NewPartyId

		SELECT @ErrMsg = 'Launch licensee failed. Please try again.', @ErrCode =  503
		RETURN
	END CATCH

	--Update NAP PT
	DECLARE @CurrentDate DATE = CONVERT(DATE, GETDATE())

	UPDATE @ChargeInfo
		SET IsValid = 0
	WHERE @CurrentDate NOT BETWEEN FromDate AND ToDate

	DELETE FROM @ChargeInfo WHERE ProductId IN (14, 17) OR  ToDate < @CurrentDate
	
	SELECT @SiteName = l.LicenseeName
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.Licensees l WITH(NOLOCK) ON p.OldRefID = l.LicenseeID
	WHERE l.IsDeposit = 1 AND p.PartyID = @NewPartyId

	UPDATE c
		SET c.ProductId = CASE WHEN c.ProductId = 0 THEN 1 ELSE p.ProductId END, c.ProductName = CASE WHEN c.ProductId = 0 THEN 'Sportsbook' ELSE pr.ProductName END
	FROM @ChargeInfo c
		LEFT JOIN dbo.Product3rd pr WITH(NOLOCK) ON pr.Productid = c.ProductId
		LEFT JOIN DBPRO.bodb02.dbo.Products p WITH (NOLOCK) ON p.ProductPrefix = pr.ProductPrefix

	--Not update PT for SA Gaming Tips Amt Due	
	IF EXISTS (SELECT 1 FROM @ChargeInfo WHERE ProductId = 39)
	BEGIN
		DELETE c
		FROM @ChargeInfo c
		WHERE EXISTS (
			SELECT 1 FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
			WHERE ci.ChargeID = c.ChargeID AND ci.ChargeType = 12 --  Tips Amt Due
		) AND c.ProductId = 39
	END

	/*Delete prevent updating unexpected NAP PT value*/
	/*Sportsbook charge rate > 12% (exclude 9wickets licensee) or CandyA18, HX9Candy licensee*/
	UPDATE c
		SET c.Rate = -1
	FROM @ChargeInfo c 
	WHERE c.ProductId = 1 AND (c.Rate > 0.12 AND @SiteName <> '9wickets') OR @SiteName IN ('CandyA18', 'HX9Candy')

	/*2.new charge rate is same as same charge rate*/
	DELETE c
	FROM @ChargeInfo C
	WHERE NOT EXISTS (SELECT 1 FROM @ChargeInfo r WHERE r.ChargeID = c.ChargeID AND r.Rate <> -1)
		AND c.IsValid = 1
		
	/*2.Sportsbook charge rate > 12% (exclude 9wickets licensee) or Sportsbook charge rate = 0 or CandyA18, HX9Candy licensee%*/
	DELETE c
	FROM @ChargeInfo c
	WHERE EXISTS (
		SELECT 1 FROM @ChargeInfo r 
		WHERE r.ChargeID = c.ChargeID 
			AND ((((r.Rate > 0.12 AND @SiteName <> '9wickets') OR r.Rate = 0) AND c.ProductId = 1) OR @SiteName IN ('CandyA18', 'HX9Candy'))
		)

	SELECT @InputPT = CONVERT(VARCHAR(MAX), 
	(
		SELECT 
			ProductId AS '@PID'
			,CurrencyId AS '@CID'
			,CASE WHEN Rate = -1 THEN -1 ELSE 100 * (1 - Rate) END AS '@PT' -- [-1] : not update
		FROM @ChargeInfo 
		WHERE IsValid = 1
		FOR XML PATH ('PT'), ROOT('ROOT')
	))

	IF @SiteName NOT IN ('', 'CandyA18', 'HX9Candy') AND ISNULL(@InputPT, '') <> ''
	BEGIN
		EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_PTSettingUpd
			@Site = @SiteName
			,@InputPT = @InputPT
			,@UserID = @UserID
			,@Username = @Username
			,@IP = @LoginIP
			,@ErrCode = @ErrCode OUTPUT
			,@ErrMsg = @ErrMsg OUTPUT
	END

	IF (@ErrCode  <> 0 OR EXISTS (SELECT 1 FROM @ChargeInfo WHERE IsValid = 0)) AND @SiteName NOT IN  ('', 'CandyA18', 'HX9Candy')
	BEGIN
		IF @ErrCode <> 0
		BEGIN
			SELECT 	@ErrMsg = STUFF((SELECT ',' + ProductName
					FROM @ChargeInfo 
					WHERE IsValid = 1
					FOR XML PATH('')), 1, 1, '') + ': '+ @ErrMsg + CHAR(13)
		END

		SELECT @ErrMsg =  ISNULL(@ErrMsg, '') + ProductName + ': NAP PT update failed due to it''s not current charge rate' + CHAR(13)
		FROM @ChargeInfo
		WHERE IsValid = 0

		SET @ErrCode = 0
	END
	-- Write log
	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, @EndRun)

	SET @Doing =(SELECT	@NonOfficialPartyId	AS NonOfficialPartyId,
						@LicenseeId			AS LicenseeId,
						@PayerName			AS PayerName,
						@LicenseeCode		AS LicenseeCode,
						@BrandName			AS BrandName,
						@BaseCurrencyId		AS BaseCurrencyId,
						@LaunchDate			AS LaunchDate, 
						@BillingGroupId		AS BillingGroupId,
						@ProductIds			AS ProductIds, 
						@ChargeInfoSettingData	AS ChargeInfoSettingData
						FOR XML PATH('')) 

	EXEC CustDB.dbo.WriteLog_UserLog_UserControl_Wrapper
		@CustID		= 0,
		@Doing		= @Doing,
		@UserID		= @UserID,
		@TypeID		= 0,
		@ActionID	= 5535,
		@Duration	= @Duration
END
GO