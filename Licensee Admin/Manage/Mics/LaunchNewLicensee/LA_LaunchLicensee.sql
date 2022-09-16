/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee]
	@NonOfficialPartyId		INT,
	@LicenseeId				INT,
	@PayerName				VARCHAR(50),
	@BrandName				VARCHAR(100)	= '',
	@LicenseeCode			VARCHAR(50)		= '',
	@BaseCurrencyId			TINYINT,
	@LaunchDate				DATE, 
	@ProductIds				VARCHAR(1000)	= '',
	@InvoiceLanguage		VARCHAR(7)		= '',
	@MinFeeSettingData		NVARCHAR(MAX)	= '',
	@UserId					INT,
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

							@MinFeeSettingData = '<Root>
								<MinFeeSetting>
									<ProductId>0</ProductId>
									<FeeTypeId>1</FeeTypeId>
									<FeeAmount>5000</FeeAmount>
									<BaseCurrencyID>6</BaseCurrencyID>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
									<MinFeeTerm>EUR 5,000 (Waived for the first 3 months after launched)</MinFeeTerm>
									<Priority>1</Priority>
								</MinFeeSetting>
								<MinFeeSetting>
									<ProductId>0</ProductId>
									<FeeTypeId>2</FeeTypeId>
									<FeeAmount></FeeAmount>
									<BaseCurrencyID>6</BaseCurrencyID>
									<FromDate>20190108</FromDate>
									<ToDate>20190407</ToDate>
									<MinFeeTerm></MinFeeTerm>
									<Priority>2</Priority>
								</MinFeeSetting>
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
	DECLARE @ChargeInfo TABLE (ChargeId INT, ProductId INT, SystemId INT)
	DECLARE @AMF MONEY, @BillingGroupName NVARCHAR(50), @BillerId INT, @FirstDateOfMonth DATE
	
	-- Charge Rate, Min Fee
	BEGIN TRY
		DECLARE @MinFeeSettingXML XML = CONVERT(XML, @MinFeeSettingData)

		INSERT INTO @MinFeeSettings (ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority])
		SELECT
			t.c.value('(ProductId/text())[1]', 'INT')					AS ProductId
			,t.c.value('(FeeTypeId/text())[1]', 'TINYINT')				AS FeeTypeId
			,t.c.value('(FeeAmount/text())[1]', 'MONEY')				AS FeeAmount
			,t.c.value('(FromDate/text())[1]', 'DATE')					AS FromDate
			,t.c.value('(ToDate/text())[1]', 'DATE')					AS ToDate
			,t.c.value('(MinFeeTerm/text())[1]', 'NVARCHAR(1000)')		AS MinFeeTerm
			,t.c.value('(Priority/text())[1]', 'TINYINT')				AS [Priority]
		FROM @MinFeeSettingXML.nodes('Root/MinFeeSetting') t(c)
		OPTION (OPTIMIZE FOR (@MinFeeSettingXML = NULL))
	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'Charge info/Min fee setting data invalid. Please try again.', @ErrCode =  501
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

	SELECT @FirstDateOfMonth = DATEADD(MONTH, DATEDIFF(MONTH, 0, @LaunchDate), 0)

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

		IF ISNULL(@AMF, 0) > 0
			UPDATE @MinFeeSettings
			SET MonthOfDeduction = CEILING(@AMF / NULLIF(FeeAmount, 0))
			WHERE FeeTypeId = 1 AND ProductId = 0
		
		-- LA_MinFee
		INSERT INTO dbo.LA_MinFee (PartyId, ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], CurrencyId, MonthOfDeduction)
		SELECT @NewPartyId, ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], @BaseCurrencyId, MonthOfDeduction 
		FROM @MinFeeSettings

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

		DELETE dbo.OAS_PartyBaseCurrency WHERE PartyId = @NewPartyId
		DELETE dbo.LA_MinFee WHERE PartyID = @NewPartyId
		DELETE dbo.LA_UserParty WHERE PartyId = @NewPartyId
		DELETE dbo.LA_FunctionParty WHERE PartyId = @NewPartyId

		SELECT @ErrMsg = 'Launch licensee failed. Please try again.', @ErrCode =  503
		RETURN
	END CATCH
	
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
						@ProductIds			AS ProductIds, 
						@MinFeeSettingData	AS MinFeeSettingData
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