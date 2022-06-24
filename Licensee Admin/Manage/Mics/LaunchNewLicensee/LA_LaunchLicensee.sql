/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee]
	@NonOfficialPartyId		INT,
	@LicenseeId				INT,
	@LicenseeName			VARCHAR(50),
	@BrandName				VARCHAR(100)	= '',
	@LicenseeCode			VARCHAR(50)		= '',
	@BaseCurrencyId			TINYINT,
	@LaunchDate				DATE, 
	@GroupId				INT,
	@ProductIds				VARCHAR(1000)	= '', 
	@ChargeInfoSettingData	NVARCHAR(MAX),
	@MinFeeSettingData		NVARCHAR(MAX)	= '',
	@UserId					INT, 
	@ErrCode				INT				= 0		OUTPUT, 
	@ErrMsg					VARCHAR(4000)	= ''	OUTPUT,
	@InvoiceLanguage		VARCHAR(7)		= ''
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
		@StartRun		DATETIME, 
		@EndRun			DATETIME, 
		@Duration		INT, 
		@Doing			NVARCHAR(MAX)

	SET @StartRun = GETDATE()

	DECLARE @Products TABLE (ProductId INT)
	
	INSERT INTO @Products(ProductId)
	SELECT value FROM STRING_SPLIT(@ProductIds, ',')

	-- #Region LicenseeProduct3rd
	UPDATE dbo.LicenseeProduct3rd WITH(ROWLOCK)
	SET EffectiveDate = @LaunchDate
	WHERE LicenseeId = @LicenseeId
	-- #Endregion LicenseeProduct3rd
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert/Update LicenseeProduct3rd failed. Please try again.', @ErrCode =  503
		RETURN
	END

	SET @ErrCode = 0
	
	DECLARE @NewPartyId	INT = 0
	EXEC dbo.LA_LaunchLicensee_PartyIns @NonOfficialPartyId, @LicenseeId, @LicenseeName, @BrandName, @LicenseeCode, @BaseCurrencyId, @LaunchDate, @NewPartyId OUTPUT, @ErrCode OUTPUT, @ErrMsg OUTPUT, @InvoiceLanguage
	
	IF @ErrCode = 0
	BEGIN
		EXEC dbo.LA_LaunchLicensee_ChargeInfoIns @NewPartyId, @GroupId, @ChargeInfoSettingData, @ErrCode OUTPUT, @ErrMsg OUTPUT  
	END
	
	IF @ErrCode = 0
	BEGIN
		EXEC dbo.LA_LaunchLicensee_MinFeeIns @NewPartyId, @BaseCurrencyId, @MinFeeSettingData, @ErrCode OUTPUT, @ErrMsg OUTPUT
	END

	IF @ErrCode = 0
	BEGIN
		DECLARE @InvoiceSettingData VARCHAR(MAX)

		DECLARE @GroupName NVARCHAR(50)
		SELECT  @GroupName = CASE BillerName WHEN 'Zelianta Limited' THEN 'Zelianta' ELSE 'Boping' END
		FROM dbo.LA_BillerInfo WITH (NOLOCK)
		WHERE BillerName IN ('Boping', 'Zelianta Limited')
			AND PartyId = @GroupId

		IF ISNULL(@GroupName, '') <> ''
		BEGIN
			SELECT @InvoiceSettingData = CONVERT(VARCHAR(MAX),
				(SELECT
					p.ProductId			AS '@ProductId'
					,ivt.InvTypeId		AS '@InvTempId'
					,ivt.InvTemplateId	AS '@InvTypeId'
					,0					AS '@BankId'
					,1					AS '@ActiveAddress'
				FROM (
					SELECT InvTemplateId, InvTemplateName
						,CASE InvTemplateName
							WHEN @GroupName THEN 1 -- Software Data & Licensing Fees
							WHEN 'Credit' THEN 4 -- Credit Note
							ELSE 5 -- Debit Note
							END AS InvTypeId
					FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
					WHERE 1 = CASE InvTemplateName
								WHEN @GroupName THEN 1
								WHEN 'Credit' THEN 1
								WHEN 'Debit' + CASE WHEN @GroupName = 'Zelianta' THEN '-Zelianta' ELSE '' END THEN 1
								ELSE 0 END
				) ivt
					OUTER APPLY (
						SELECT p.ProductId FROM @Products p WHERE ivt.InvTemplateName IN (('Boping', 'Zelianta')
					) p
				FOR XML PATH('row'), ROOT('root')))

			EXEC dbo.LA_LaunchLicensee_InvoiceSettingIns @NewPartyId, @GroupId, @InvoiceSettingData, @ErrCode OUTPUT, @ErrMsg OUTPUT
		END
	END
	
	IF @ErrCode = 0
	BEGIN
		INSERT INTO LA_UserParty (UserID, PartyID, Modifydate, Modifier, StatusID)
		SELECT UserID, @NewPartyId, GETDATE(), @UserID, 1
		FROM dbo.LA_User WITH (NOLOCK) 
		WHERE StatusID = 1 -- Active users

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = 'Insert LA_UserParty failed. Please try again.', @ErrCode =  503
		END
	END

	IF @ErrCode = 0
	BEGIN
		INSERT INTO dbo.LA_FunctionParty (FunctionID, PartyID)
		SELECT FunctionID, @NewPartyId
		FROM dbo.LA_Function WITH (NOLOCK) 
		WHERE StatusID = 1 -- Active functions

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = 'Insert LA_FunctionParty failed. Please try again.', @ErrCode =  503
		END
	END

	IF @ErrCode <> 0
	BEGIN
		EXEC dbo.LA_LaunchLicensee_Rollback @NewPartyId, @GroupId
		RETURN
	END

	-- #Region: Write Log
	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, @EndRun)

	SET @Doing =(SELECT	@NonOfficialPartyId	AS NonOfficialPartyId,
						@LicenseeId			AS LicenseeId,
						@LicenseeName		AS LicenseeName,
						@LicenseeCode		AS LicenseeCode,
						@BrandName			AS BrandName,
						@BaseCurrencyId		AS BaseCurrencyId,
						@LaunchDate			AS LaunchDate, 
						@GroupId			AS GroupId,
						@ProductIds			AS ProductIds, 
						@ChargeInfoSettingData	AS ChargeInfoSettingData,
						@MinFeeSettingData	AS MinFeeSettingData
						FOR XML PATH('')) 

	EXEC CustDB.dbo.WriteLog_UserLog_UserControl_Wrapper
		@CustID		= 0,
		@Doing		= @Doing,
		@UserID		= @UserID,
		@TypeID		= 0,
		@ActionID	= 5535,
		@Duration	= @Duration

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = ERROR_MESSAGE() , @ErrCode = 503
	END
	-- #Endregion: Write Log
END
GO

