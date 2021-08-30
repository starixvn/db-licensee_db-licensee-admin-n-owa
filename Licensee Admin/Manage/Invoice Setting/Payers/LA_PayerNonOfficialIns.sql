/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerNonOfficialIns]
	@BrandName		VARCHAR (100)	= ''
	, @CompanyName		NVARCHAR (100)	= ''
	, @Description		NVARCHAR (255)	= ''
	, @AttnName			NVARCHAR (125)	= ''
	, @Address1			NVARCHAR (255)	= ''
	, @Address2			NVARCHAR (255)	= ''
	, @PayerName		VARCHAR (50)
	, @IsActive			BIT				= 1
	, @IsDeposit		BIT				= 1
	, @PayerId			INT				= 0  OUTPUT
	, @UserID			INT
	, @LoginIP			VARCHAR (50)	= ''
	, @ErrCode			INT				= 0  OUTPUT
	, @ErrMsg			NVARCHAR(1000)	= '' OUTPUT
	, @InvoiceLanguage	VARCHAR(7)
	, @BaseCurrencySettingXml	NVARCHAR(MAX)	= ''
	, @CompanyName2		NVARCHAR (100)	= ''
	, @AttnName2		NVARCHAR (125)	= ''
AS
/*
	Created: 20161109@bruce.bui
	Task : Insert non official payer
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20161124@scofield: check unique BrandName
		- 20180318@mason: Add @InvoiceLanguage parameter [#110445]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20190905@Bruce: Adding licensee code [#111586]
		- 20210316@Happy: Change BaseCurrency Of Licensee [#151466] 
		- 20210413@Happy: Support duo base currency [RedmineID: #152089]
		- 20210811@Danny: Adding AttnName2, CompanyName2 into OAS_PartyDetail [#FeatureID 158133]
*/
BEGIN

	SET NOCOUNT ON

	-- For writing log
	DECLARE @startRun	DATETIME
		, @endRun		DATETIME
		, @duration		INT
		, @xml			XML
		, @LogData		NVARCHAR(MAX)

	-- Time start
	SET @startRun = GETDATE()

	IF EXISTS (
		SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK)
		WHERE PartyType IN (1,5) AND PartyName = @PayerName
	) BEGIN
		SELECT @ErrCode = 101,@ErrMsg = 'Payer Name is existed in the system, please try again!'
		RETURN
	END
	
	IF EXISTS (
		SELECT 1 FROM dbo.OAS_PartyDetail WITH(NOLOCK)
		WHERE @BrandName != '' AND BrandName = @BrandName
	) BEGIN
		SELECT @ErrCode = 101,@ErrMsg = 'Payer Brand Name is existed in the system, please try again!'
		RETURN
	END

	-- Get Base currency setting from xml
	IF ISNULL(@BaseCurrencySettingXml, '') <> ''
	BEGIN
		DECLARE @BaseCurrencySetting TABLE(Idx INT IDENTITY(1, 1)
											, BaseCurrencyId TINYINT
											, LicenseeCode VARCHAR(50)
											, FromDate DATE
											, ToDate DATE)
		DECLARE @docHandler INT
			
		BEGIN TRY
			EXEC sp_xml_preparedocument @docHandler OUTPUT, @BaseCurrencySettingXml
			INSERT INTO @BaseCurrencySetting(BaseCurrencyId, LicenseeCode, FromDate, ToDate)
			SELECT BaseCurrencyId, LicenseeCode, FromDate, ToDate
			FROM OPENXML(@docHandler, 'Root/BaseCurrencySetting')
			WITH(BaseCurrencyId TINYINT 'BaseCurrencyId',
					LicenseeCode VARCHAR(50) 'LicenseeCode',
					FromDate DATE 'FromDate',
					ToDate DATE 'ToDate')
						
			EXEC sp_xml_removedocument @docHandler
		END TRY
		BEGIN CATCH
			SELECT @ErrMsg = 'Base Currency setting data invalid. Please try again.', @ErrCode = 100
			RETURN
		END CATCH

		-- Should have at least 1 base currency setting
		IF NOT EXISTS (SELECT TOP 1 1 FROM @BaseCurrencySetting)
		BEGIN
			SELECT @ErrMsg = 'Should have at least 1 base currency setting.', @ErrCode = 506
			RETURN
		END
			
		--FromDate must less than ToDate
		IF EXISTS (SELECT TOP 1 1 FROM @BaseCurrencySetting WHERE FromDate > ToDate)
		BEGIN
			SELECT @ErrMsg = 'FromDate could not be later than ToDate', @ErrCode = 506
			RETURN
		END
			
		--Duplicated from date/ to date between settings
		IF EXISTS (
			SELECT TOP 1 1
			FROM @BaseCurrencySetting a 
				LEFT JOIN @BaseCurrencySetting b ON a.Idx <> b.Idx 
			WHERE(a.FromDate <= b.ToDate AND a.ToDate >= B.FromDate))
		BEGIN
			SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date.', @ErrCode = 506
			RETURN
		END
	END
	-- End region Get Base currency setting from xml
	
	INSERT INTO dbo.OAS_Party(PartyName, Description, PartyType) VALUES (@PayerName, 'Non-Official', 5)
	SET @PayerId = SCOPE_IDENTITY()
	
	UPDATE @BaseCurrencySetting
	SET FromDate = DATEADD(MM, DATEDIFF(MM, 0, FromDate), 0)
	WHERE Idx = (SELECT TOP 1 Idx FROM @BaseCurrencySetting ORDER BY FromDate ASC)

	INSERT INTO dbo.OAS_PartyDetail(PartyId, BrandName, CompanyName, AttnName, Description, Address1, Address2, BaseCurrencyId, IsAllowedMemberComm, IsDeposit, StatusId, InvoiceLanguage, LicenseeCode, CompanyName2, AttnName2)
	SELECT TOP 1 @PayerId, @BrandName, @CompanyName, @AttnName, @Description, @Address1, @Address2, BaseCurrencyId, 0, @IsDeposit , @IsActive, @InvoiceLanguage, LicenseeCode, @CompanyName2, @AttnName2
	FROM @BaseCurrencySetting

	INSERT INTO dbo.OAS_PartyBaseCurrency(BaseCurrencyId, PartyID, FromDate, ToDate, LicenseeCode)
	SELECT b.BaseCurrencyId, @PayerId, b.FromDate, b.ToDate, b.LicenseeCode
	FROM @BaseCurrencySetting b

	SET @xml = (
		SELECT	p.PartyID			AS '@pid'
				, p.PartyName		AS '@pn'
				, pd.StatusId		AS '@s'
				, pd.IsDeposit		AS '@isd'
				, pd.BrandName		AS '@bn'
				, pd.CompanyName	AS '@cn'
				, pd.AttnName		AS '@an'
				, pd.Description	AS '@des'
				, pd.Address1		AS '@a1'
				, pd.Address2		AS '@a2'
				, pd.InvoiceLanguage AS '@il'
				, @BaseCurrencySettingXml AS '@bc'
				, pd.CompanyName2	AS '@cn2'
				, pd.AttnName2		AS '@an2'
		FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		WHERE p.PartyID = @PayerId
		FOR XML PATH('z'), ROOT('r')
	)

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)
	SELECT @LogData = CONVERT(NVARCHAR(MAX), @xml)

	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_PayerNonOfficialIns'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @LogData
		,@OldData		= ''
END
GO
