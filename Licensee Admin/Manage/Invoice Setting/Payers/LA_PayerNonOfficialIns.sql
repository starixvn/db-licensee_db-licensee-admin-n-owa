/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerNonOfficialIns]
	@BrandName			VARCHAR (100)	= ''
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
	, @PlatformId 		TINYINT = 1
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
		- 20230310@Danny: Insert new log with more information [#FeatureID 175125]
		- 20231228@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
		- 20250321@Eddie: Add Payer Platform [RedmineID: #217740]

	Param's Explanation:
		- @PlatformId: 1 (Saba Sports), 2 (SabaPlay), 3 (SabaSports&SabaPlay)
*/
BEGIN

	SET NOCOUNT ON

	-- For writing log
	DECLARE @startRun	DATETIME
		, @endRun		DATETIME
		, @duration		INT
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
			WHERE(a.FromDate <= b.ToDate AND a.ToDate >= b.FromDate))
		BEGIN
			SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date.', @ErrCode = 506
			RETURN
		END
	END
	-- End region Get Base currency setting from xml
	
	INSERT INTO dbo.OAS_Party(PartyName, Description, PartyType, PlatformId)
	VALUES (@PayerName, 'Non-Official', 5, @PlatformId)

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

	SELECT @LogData = (
			SELECT	 op2.PartyName							AS 'pi.pn'
					,x.GroupName							AS 'pi.bg' 
					,od.BrandName							AS 'pi.bn'
					,od.Description							AS 'pi.dc'
					,od.InvoiceLanguage						AS 'pi.iv'
					,FORMAT (od.LaunchDate,'MMM dd, yyyy') 	AS 'pi.ld'
					,FORMAT (od.SuspendedDate,'MMM dd, yyyy')	AS 'pi.sd'
					,FORMAT (od.TerminatedDate,'MMM dd, yyyy') AS 'pi.tmd'
					,pl.PlatformName AS 'pi.pp'
					,od.CompanyName		AS 'a1.cn1'
					,od.AttnName		AS 'a1.an1'
					,od.Address1		AS 'a1.ad1'
					,od.CompanyName2	AS 'a2.cn2'
					,od.AttnName2		AS 'a2.an2'
					,od.Address2		AS 'a2.ad2'
					,ci.baseCurrInfo    AS 'bcs'
			FROM OAS_PartyDetail od WITH(NOLOCK)
			INNER JOIN OAS_Party op2 WITH(NOLOCK) ON od.PartyID = op2.PartyID
			INNER JOIN dbo.LA_f_PayerPlatform_Sel() pl ON pl.PlatformId = op2.PlatformId 
			OUTER APPLY (SELECT TOP 1 oc.ToParty , pg.GroupName
						 FROM OAS_ChargeInfo oc WITH(NOLOCK) 
						 INNER JOIN dbo.LA_f_BillingGroupSel() pg ON pg.PartyId = oc.ToParty
						 WHERE od.PartyID = oc.FromParty AND oc.ChargeType = 1 ) x
			OUTER APPLY (
							SELECT
							(
							SELECT CASE WHEN op.BaseCurrencyId = 142 THEN 'USDT' ELSE e.Code END  'c', 
									op.LicenseeCode 'lc', 
									op.FromDate 'fd', 
									op.ToDate  'td',
									CONVERT(VARCHAR(10),op.PartyID) +CONVERT(VARCHAR(10), op.BaseCurrencyId) + Convert(CHAR(8),op.FromDate,112) AS FakeID
							FROM OAS_PartyBaseCurrency op WITH(NOLOCK) 
							INNER JOIN CustDB.dbo.exchange e WITh(NOLOCK) ON op.BaseCurrencyId = e.ExchangeId
							WHERE op.PartyID = od.PartyID FOR JSON PATH , INCLUDE_NULL_VALUES    
							) AS  baseCurrInfo
						) ci
			WHERE od.PartyID = @PayerID FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES  
		)

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	-- Write Log
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_PayerNonOfficialIns'
		,@CustId		= @PayerID
		,@Duration		= @duration
		,@TrackingValue2	 = @LogData
		,@TrackingValue	 = NULL
		,@ActionID		= 1000
END
GO
