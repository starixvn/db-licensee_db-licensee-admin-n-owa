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
	, @BaseCurrencyId	INT
	, @IsActive			BIT				= 1
	, @IsDeposit		BIT				= 1
	, @PayerId			INT				= 0  OUTPUT
	, @UserID			INT
	, @LoginIP			VARCHAR (50)	= ''
	, @ErrCode			INT				= 0  OUTPUT
	, @ErrMsg			NVARCHAR(1000)	= '' OUTPUT
	, @InvoiceLanguage	VARCHAR(7)
	, @LicenseeCode		VARCHAR (50) = ''
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


	SET @LicenseeCode = (CASE WHEN @LicenseeCode = '' THEN NULL ELSE @LicenseeCode END)

	INSERT INTO dbo.OAS_Party(PartyName, Description, PartyType) VALUES (@PayerName, 'Non-Official', 5)
	SET @PayerId = SCOPE_IDENTITY()

	INSERT INTO dbo.OAS_PartyDetail(PartyId, BrandName, CompanyName, AttnName, Description, Address1, Address2, BaseCurrencyId, IsAllowedMemberComm, IsDeposit, StatusId, InvoiceLanguage, LicenseeCode)
	VALUES(@PayerId, @BrandName, @CompanyName, @AttnName, @Description, @Address1, @Address2, @BaseCurrencyId, 0, @IsDeposit , @IsActive, @InvoiceLanguage, @LicenseeCode)

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
				, pd.BaseCurrencyId	AS '@bc'
				, pd.InvoiceLanguage AS '@il'
				, pd.LicenseeCode	 AS '@lc'
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
