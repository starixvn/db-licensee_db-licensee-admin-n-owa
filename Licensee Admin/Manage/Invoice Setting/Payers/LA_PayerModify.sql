/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerModify]
	@PayerID					INT
	, @BrandName				VARCHAR (100)	= ''
	, @CompanyName				NVARCHAR (100)	= ''
	, @Description				NVARCHAR (255)	= ''
	, @AttnName					NVARCHAR (125)	= ''
	, @Address1					NVARCHAR (255)	= ''
	, @Address2					NVARCHAR (255)	= ''
	, @PayerName				VARCHAR (50)
	, @UserID					INT
	, @IsActive					BIT				= 1
	, @IsDeposit				BIT				= 1
	, @LoginIP					VARCHAR (50)	= ''
	, @ErrCode					INT				= 0  OUTPUT
	, @ErrMsg					NVARCHAR(1000)	= '' OUTPUT
	, @InvoiceLanguage 			VARCHAR(7)		= ''
	, @BaseCurrencySettingXml	NVARCHAR(MAX)	= ''
	, @CompanyName2				NVARCHAR (100)	= ''
	, @AttnName2				NVARCHAR (125)	= ''
AS
/*
	Created: 20150415@Florent
	Task : Modify Payer infomartion
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20150918@Victor: Support Chinese on Settings
		- 20161109@bruce.bui: edit non official payer
			1: official payer
			5: non-official payer
		- 20161124@scofield: check unique BrandName
		- 20180318@mason: Add @InvoiceLanguage parameter [#110445]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20190829@Bruce: Adding Licensee Code [#111586]
		- 20210315@Happy: Change BaseCurrency Of Licensee [#151466]
		- 20210811@Danny: Adding AttnName2, CompanyName2 into OAS_PartyDetail [#FeatureID 158133]
		- 20230310@Danny: Insert new log with more information [#FeatureID 175125]
	
	Param's Explannation: 
		@BaseCurrencySettingXml = <Root>
									<BaseCurrencySetting>
										<BaseCurrencyId>6</BaseCurrencyId>
										<LicenseeCode>PHL-LSEE-12BET EUR</LicenseeCode>
										<FromDate>20100101</FromDate>
										<ToDate>20500101</ToDate>
									</BaseCurrencySetting>
									<BaseCurrencySetting>
										<BaseCurrencyId>13</BaseCurrencyId>
										<LicenseeCode>XXX</LicenseeCode>
										<FromDate>20210301</FromDate>
										<ToDate>20500101</ToDate>
									</BaseCurrencySetting>
									<BaseCurrencySetting>
										<BaseCurrencyId>6</BaseCurrencyId>
										<LicenseeCode>PHL-LSEE-12BET EUR</LicenseeCode>
										<FromDate>20210308</FromDate>
										<ToDate>20500101</ToDate>
									</BaseCurrencySetting>
								</Root>
*/
BEGIN
	SET NOCOUNT ON
	
	-- For writing log
	DECLARE @startRun	DATETIME
		, @endRun		DATETIME
		, @duration		INT
		, @logSPData	NVARCHAR(MAX)
		, @logSPDataOld NVARCHAR(MAX)

	-- Time start
	SET @startRun = GETDATE()

	IF EXISTS (SELECT 1 FROM dbo.OAS_Party p WITH (NOLOCK) WHERE p.PartyID = @PayerID)
	BEGIN
		--write log old
		SELECT @logSPDataOld = (
			SELECT	 Op2.PartyName							AS 'pi.pn'
					,CASE WHEN x.ToParty = 1 THEN 'ONEWorks'
						  WHEN x.ToParty = 9 THEN 'Cozni'
						  WHEN x.ToParty = 11 THEN 'Boping'	
						  WHEN x.ToParty = 98 THEN 'Zelianta'	
					 END									AS 'pi.bg' 
					,od.BrandName							AS 'pi.bn'
					,od.Description							AS 'pi.dc'
					,od.InvoiceLanguage						AS 'pi.iv'
					,od.LaunchDate							AS 'pi.ld'
					,od.SuspendedDate						AS 'pi.sd'
					,od.TerminatedDate						AS 'pi.tmd'

					,od.CompanyName		AS 'a1.cn1'
					,od.AttnName		AS 'a1.an1'
					,od.Address1		AS 'a1.ad1'
					,od.CompanyName2	AS 'a2.cn2'
					,od.AttnName2		AS 'a2.an2'
					,od.Address2		AS 'a2.ad2'
					,ci.baseCurrInfo    AS 'bcs'
			FROM OAS_PartyDetail od WITH(NOLOCK)
			INNER JOIN OAS_Party op2 WITH(NOLOCK)  ON od.PartyID = op2.PartyID
			OUTER APPLY (SELECT TOP 1 ToParty FROM OAS_ChargeInfo oc WITH(NOLOCK) WHERE od.PartyID = oc.FromParty AND oc.ChargeType = 1 ) x
			OUTER APPLY (
							SELECT
							(
							SELECT CASE WHEN op.BaseCurrencyId = 142 THEN 'USDT' ELSE e.Code END  'c', 
									op.LicenseeCode 'lc', 
									op.FromDate 'fd', 
									op.ToDate  'td'
							FROM OAS_PartyBaseCurrency op WITH(NOLOCK) 
							INNER JOIN CustDB.dbo.exchange e WITh(NOLOCK) ON op.BaseCurrencyId = e.ExchangeId
							WHERE op.PartyID = od.PartyID FOR JSON PATH , INCLUDE_NULL_VALUES    
							) AS  baseCurrInfo
						) ci
			WHERE od.PartyID = @PayerID FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
		)

		UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK, UPDLOCK)
		SET CompanyName = @CompanyName
			, AttnName = @AttnName
			, Description = @Description
			, Address1 = @Address1
			, Address2 = @Address2
			, InvoiceLanguage = @InvoiceLanguage
			, CompanyName2 = @CompanyName2
			, AttnName2 = @AttnName2
		WHERE PartyId = @PayerID

		-- only non-official payer can edit payer name, status, deposit status
		IF (SELECT PartyType FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID = @PayerID) = 5
		BEGIN
			-- check duplicate name
			IF EXISTS (
				SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK)
				WHERE PartyType IN (1,5) AND PartyID != @PayerID AND PartyName = @PayerName
			) BEGIN
				SELECT @ErrCode = 101,@ErrMsg = 'Payer Name is existed in the system, please try again!'
				RETURN
			END
			
			UPDATE dbo.OAS_Party WITH (ROWLOCK, UPDLOCK)
			SET PartyName = @PayerName
			WHERE PartyId = @PayerID

			UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK, UPDLOCK)
			SET StatusId = @IsActive, IsDeposit = @IsDeposit
			WHERE PartyId = @PayerID
		END
		
		IF EXISTS (
			SELECT 1 FROM dbo.OAS_PartyDetail WITH(NOLOCK)
			WHERE PartyId != @PayerID AND @BrandName != '' AND BrandName = @BrandName
		) BEGIN
			SELECT @ErrCode = 101,@ErrMsg = 'Payer Brand Name is existed in the system, please try again!'
			RETURN
		END
		
		UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK, UPDLOCK)
		SET BrandName = @BrandName
		WHERE PartyId = @PayerID
		
		-- Update base currency settings
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
			
			--Should have at least one base currency
			IF NOT EXISTS (SELECT 1 FROM @BaseCurrencySetting)
			BEGIN
				SELECT @ErrMsg = 'Should has at least 1 base currency setting.', @ErrCode = 506
				RETURN
			END
			
			--Region Update Base Currency Settings
			;MERGE dbo.OAS_PartyBaseCurrency WITH(ROWLOCK, UPDLOCK) AS t
			USING @BaseCurrencySetting AS s
			ON (t.PartyID = @PayerID AND t.BaseCurrencyId = s.BaseCurrencyId AND t.FromDate = s.FromDate)
			WHEN MATCHED
				THEN UPDATE SET t.LicenseeCode = s.LicenseeCode,
								t.ToDate = s.ToDate
			WHEN NOT MATCHED BY TARGET
				THEN INSERT(PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
						VALUES(@PayerID, s.BaseCurrencyId, s.LicenseeCode, s.FromDate, s.ToDate)
			WHEN NOT MATCHED BY SOURCE AND t.PartyID = @PayerID
				THEN DELETE;
			--Endregion
		END

		SELECT @logSPData = (
			SELECT	 Op2.PartyName							AS 'pi.pn'
					,CASE WHEN x.ToParty = 1 THEN 'ONEWorks'
						  WHEN x.ToParty = 9 THEN 'Cozni'
						  WHEN x.ToParty = 11 THEN 'Boping'	
						  WHEN x.ToParty = 98 THEN 'Zelianta'	
					 END									AS 'pi.bg' 
					,od.BrandName							AS 'pi.bn'
					,od.Description							AS 'pi.dc'
					,od.InvoiceLanguage						AS 'pi.iv'
					,od.LaunchDate							AS 'pi.ld'
					,od.SuspendedDate						AS 'pi.sd'
					,od.TerminatedDate						AS 'pi.tmd'

					,od.CompanyName		AS 'a1.cn1'
					,od.AttnName		AS 'a1.an1'
					,od.Address1		AS 'a1.ad1'
					,od.CompanyName2	AS 'a2.cn2'
					,od.AttnName2		AS 'a2.an2'
					,od.Address2		AS 'a2.ad2'
					,ci.baseCurrInfo    AS 'bcs'
			FROM OAS_PartyDetail od WITH(NOLOCK)
			INNER JOIN OAS_Party op2 WITH(NOLOCK)  ON od.PartyID = op2.PartyID
			OUTER APPLY (SELECT TOP 1 ToParty FROM OAS_ChargeInfo oc WITH(NOLOCK) WHERE od.PartyID = oc.FromParty AND oc.ChargeType = 1 ) x
			OUTER APPLY (
							SELECT
							(
							SELECT CASE WHEN op.BaseCurrencyId = 142 THEN 'USDT' ELSE e.Code END  'c', 
									op.LicenseeCode 'lc', 
									op.FromDate 'fd', 
									op.ToDate  'td'
							FROM OAS_PartyBaseCurrency op WITH(NOLOCK) 
							INNER JOIN CustDB.dbo.exchange e WITh(NOLOCK) ON op.BaseCurrencyId = e.ExchangeId
							WHERE op.PartyID = od.PartyID FOR JSON PATH , INCLUDE_NULL_VALUES    
							) AS  baseCurrInfo
						) ci
			WHERE od.PartyID = @PayerID FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
		)

		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	END
	ELSE
	BEGIN
		SELECT @ErrCode = 101
		,@ErrMsg = 'Cannot save the Payer because it existed in the system, please try again!'
		RETURN
	END

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_PayerModify'
		,@CustId		= @PayerID
		,@Duration		= @duration
		,@TrackingValue2 = @logSPData
		,@TrackingValue = @logSPDataOld
		,@ActionID		= 1001
END
GO