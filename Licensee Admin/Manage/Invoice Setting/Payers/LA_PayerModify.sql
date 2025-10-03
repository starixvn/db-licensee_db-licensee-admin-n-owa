/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
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
	, @PlatformId				TINYINT
	, @LaunchDate				DATE			= NULL
	, @SuspendedDate			DATE			= NULL
	, @TerminatedDate			DATE			= NULL
	, @BalanceCarryForwardSettingXml	NVARCHAR(MAX)	= ''
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
		- 20250225@Danny: Integrate Double S System Inc group Licensees [RedmineID: #217961]
		- 20250210@Danny: Allow Editing Payer Base Currency Without Affecting Billing [#FeatureID 216841]
		- 20250321@Eddie: Update Payer Platform [RedmineID: #217740]
		- 20250506@Danny: update ExchangeID data Type [RedmineID: #221242]
		- 20250915@Danny: Balance Carry Forward setting [RedmineID: #225392]
	
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

		@BalanceCarryForwardSettingXml = <Root>
									<BalanceCarryForwardSetting>
										<IsBalanceCarryForward>1</IsBalanceCarryForward>
										<FromDate>20100101</FromDate>
										<ToDate>20500101</ToDate>
									</BalanceCarryForwardSetting>
									<BalanceCarryForwardSetting>
										<IsBalanceCarryForward>1</IsBalanceCarryForward>
										<FromDate>20210301</FromDate>
										<ToDate>20500101</ToDate>
									</BalanceCarryForwardSetting>
									<BalanceCarryForwardSetting>
										<IsBalanceCarryForward>0</IsBalanceCarryForward>
										<FromDate>20210308</FromDate>
										<ToDate>20500101</ToDate>
									</BalanceCarryForwardSetting>
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
		, @MaxInvoiceDate DATETIME

	-- Time start
	SET @startRun = GETDATE()

	IF EXISTS (SELECT 1 FROM dbo.OAS_Party p WITH (NOLOCK) WHERE p.PartyID = @PayerID)
	BEGIN
		--write log old
		SELECT @logSPDataOld = (
			SELECT	 Op2.PartyName								AS 'pi.pn'
					,x.GroupName								AS 'pi.bg' 
					,od.BrandName								AS 'pi.bn'
					,od.Description								AS 'pi.dc'
					,od.InvoiceLanguage							AS 'pi.iv'
					,FORMAT (od.LaunchDate,'MMM dd, yyyy') 		AS 'pi.ld'
					,FORMAT (od.SuspendedDate,'MMM dd, yyyy')	AS 'pi.sd'
					,FORMAT (od.TerminatedDate,'MMM dd, yyyy') 	AS 'pi.tmd'
					,pl.PlatformName 	AS 'pi.pp'
					,od.CompanyName		AS 'a1.cn1'
					,od.AttnName		AS 'a1.an1'
					,od.Address1		AS 'a1.ad1'
					,od.CompanyName2	AS 'a2.cn2'
					,od.AttnName2		AS 'a2.an2'
					,od.Address2		AS 'a2.ad2'
					,ci.baseCurrInfo    AS 'bcs'
					,bcf.bcfInfo		AS 'bcfs'
			FROM OAS_PartyDetail od WITH(NOLOCK)
			INNER JOIN OAS_Party op2 WITH(NOLOCK)  ON od.PartyID = op2.PartyID
			INNER JOIN dbo.LA_f_PayerPlatform_Sel() pl ON pl.PlatformId = op2.PlatformId
			OUTER APPLY (SELECT TOP 1 oc.ToParty , pg.GroupName
						 FROM OAS_ChargeInfo oc WITH(NOLOCK) 
						 INNER JOIN dbo.LA_f_BillingGroupSel() pg ON pg.PartyId = oc.ToParty
						 WHERE od.PartyID = oc.FromParty AND oc.ChargeType = 1 AND GETDATE() BETWEEN oc.FromDate AND oc.Todate ) x
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
			OUTER APPLY (
							SELECT
							(
							SELECT  CONVERT(VARCHAR(10),op.PartyID)  + CONVERT(CHAR(8),op.FromDate,112) AS FakeID,
									CASE WHEN op.IsBalanceCarryForward = 0 THEN 'Do not carry forward losses' ELSE 'Carry forward losses' END  'ibcf', 
									op.FromDate 'bfd', 
									op.ToDate  'btd'
							FROM SH_SabaPlay_BalanceCarryForwardSetting op WITH(NOLOCK) 
							WHERE op.PartyID = od.PartyID FOR JSON PATH , INCLUDE_NULL_VALUES    
							) AS  bcfInfo
						) bcf
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
			SET PartyName = @PayerName, PlatformId = @PlatformId
			WHERE PartyId = @PayerID

			UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK, UPDLOCK)
			SET StatusId = @IsActive, IsDeposit = @IsDeposit
			WHERE PartyId = @PayerID
		END

		--only update PlatformId for diff non-official payer
		IF (SELECT PartyType FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID = @PayerID) <> 5
		BEGIN
			UPDATE dbo.OAS_Party WITH (ROWLOCK, UPDLOCK)
			SET PlatformId = @PlatformId
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
		SET BrandName = @BrandName, LaunchDate = @LaunchDate, SuspendedDate = @SuspendedDate, TerminatedDate = @TerminatedDate
		WHERE PartyId = @PayerID
		
		-- Update base currency settings
		IF ISNULL(@BaseCurrencySettingXml, '') <> ''
		BEGIN
			DECLARE @BaseCurrencySetting TABLE(Idx INT IDENTITY(1, 1)
												, BaseCurrencyId INT
												, LicenseeCode VARCHAR(50)
												, FromDate DATE
												, ToDate DATE)
			DECLARE @docHandler INT
			
			BEGIN TRY
				EXEC sp_xml_preparedocument @docHandler OUTPUT, @BaseCurrencySettingXml
				INSERT INTO @BaseCurrencySetting(BaseCurrencyId, LicenseeCode, FromDate, ToDate)
				SELECT BaseCurrencyId, LicenseeCode, FromDate, ToDate
				FROM OPENXML(@docHandler, 'Root/BaseCurrencySetting')
				WITH(BaseCurrencyId INT 'BaseCurrencyId',
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

			SELECT @MaxInvoiceDate = MAX(InvoiceDate) FROM LA_InvoiceHeader WITH(NOLOCK) WHERE PartyId = @PayerID AND StatusId <> - 1 

			IF @MaxInvoiceDate IS NOT NULL
			BEGIN
				DECLARE @Old_MinSettingDate DATETIME, @Old_MaxSettingDate DATETIME, @New_MinSettingDate DATETIME, @New_MaxSettingDate DATETIME, @cnt INT

				SELECT @Old_MinSettingDate = MIN(FromDate), @Old_MaxSettingDate = MAX(Todate)
				FROM OAS_PartyBaseCurrency  WITH(NOLOCK)
				WHERE	PartyID = @PayerID

				SELECT @New_MinSettingDate = MIN(FromDate), @New_MaxSettingDate = MAX(Todate)
				FROM @BaseCurrencySetting  
			
				;WITH t AS (
					SELECT @Old_MinSettingDate as _start, EOMONTH (@Old_MinSettingDate) as _end
					UNION ALL
					SELECT DATEADD(MONTH,1,_start), EOMONTH (DATEADD(MONTH,1,_start))
					FROM t
					WHERE EOMONTH (DATEADD(MONTH,1,_start)) <= @Old_MaxSettingDate
				), old_setting AS
				(
					SELECT  t._start, t._end, op.BaseCurrencyId
					FROM	t 
					INNER JOIN OAS_PartyBaseCurrency op WITH(NOLOCK) ON t._start BETWEEN op.FromDate AND op.ToDate AND t._end BETWEEN op.FromDate AND op.ToDate
					WHERE op.PartyID = @PayerID AND t._end <= @MaxInvoiceDate
				),u AS (
					SELECT @New_MinSettingDate as _start, EOMONTH (@New_MinSettingDate) as _end
					UNION ALL
					SELECT DATEADD(MONTH,1,_start), EOMONTH (DATEADD(MONTH,1,_start))
					FROM u
					WHERE EOMONTH (DATEADD(MONTH,1,_start)) <= @New_MaxSettingDate
				), new_setting AS
				(
					SELECT  u._start, u._end, op.BaseCurrencyId
					FROM	u 
					INNER JOIN @BaseCurrencySetting op ON u._start BETWEEN op.FromDate AND op.ToDate AND u._end BETWEEN op.FromDate AND op.ToDate
					WHERE u._end <= @MaxInvoiceDate
				)
				SELECT @cnt = COUNT(1) 
				FROM old_setting o INNER JOIN new_setting n ON o._start = n._start AND o._end = n._end 
				WHERE o.BaseCurrencyId <> n.BaseCurrencyId
				OPTION (MAXRECURSION 0)

				IF @cnt > 0
				BEGIN
					SELECT @ErrMsg = 'Cannot Save the Setting which impacts the past billing data. Please re-check the From Date/To Date!', @ErrCode = 506
					RETURN
				END
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

			-- Get Balance Carry Forward Setting from xml
		IF ISNULL(@BalanceCarryForwardSettingXml, '') <> ''
		BEGIN
			DECLARE @BalanceCarryForwardSetting TABLE(Idx INT IDENTITY(1, 1)
												, IsBalanceCarryForward BIT
												, FromDate DATE
												, ToDate DATE)
			DECLARE @docHandler_bcf INT
			
			BEGIN TRY
				EXEC sp_xml_preparedocument @docHandler_bcf OUTPUT, @BalanceCarryForwardSettingXml
				INSERT INTO @BalanceCarryForwardSetting(IsBalanceCarryForward, FromDate, ToDate)
				SELECT IsBalanceCarryForward, FromDate, ToDate
				FROM OPENXML(@docHandler_bcf, 'Root/BalanceCarryForwardSetting')
				WITH(	IsBalanceCarryForward BIT 'IsBalanceCarryForward',
						FromDate DATE 'FromDate',
						ToDate DATE 'ToDate')
						
				EXEC sp_xml_removedocument @docHandler_bcf
			END TRY
			BEGIN CATCH
				SELECT @ErrMsg = 'Balance Carry Forward setting data invalid. Please try again.', @ErrCode = 100
				RETURN
			END CATCH

			-- Should have at least 1 base currency setting
			IF NOT EXISTS (SELECT TOP 1 1 FROM @BalanceCarryForwardSetting)
			BEGIN
				SELECT @ErrMsg = 'Should have at least 1 balance carry forward setting.', @ErrCode = 506
				RETURN
			END
			
			--FromDate must less than ToDate
			IF EXISTS (SELECT TOP 1 1 FROM @BalanceCarryForwardSetting WHERE FromDate > ToDate)
			BEGIN
				SELECT @ErrMsg = 'FromDate could not be later than ToDate', @ErrCode = 506
				RETURN
			END
			
			--Duplicated from date/ to date between settings
			IF EXISTS (
				SELECT TOP 1 1
				FROM @BalanceCarryForwardSetting a 
					LEFT JOIN @BalanceCarryForwardSetting b ON a.Idx <> b.Idx 
				WHERE(a.FromDate <= b.ToDate AND a.ToDate >= b.FromDate))
			BEGIN
				SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date.', @ErrCode = 506
				RETURN
			END

			--Region Update Base Currency Settings
			;MERGE dbo.SH_SabaPlay_BalanceCarryForwardSetting WITH(ROWLOCK, UPDLOCK) AS t
			USING @BalanceCarryForwardSetting AS s
			ON (t.PartyID = @PayerID AND t.FromDate = s.FromDate)
			WHEN MATCHED
				THEN UPDATE SET t.IsBalanceCarryForward = s.IsBalanceCarryForward,
								t.ToDate = s.ToDate
			WHEN NOT MATCHED BY TARGET
				THEN INSERT(PartyID, IsBalanceCarryForward, FromDate, ToDate)
						VALUES(@PayerID, s.IsBalanceCarryForward,  s.FromDate, s.ToDate)
			WHEN NOT MATCHED BY SOURCE AND t.PartyID = @PayerID
				THEN DELETE;
		END
		-- End region Get Balance Carry Forward Setting from xml

		SELECT @logSPData = (
			SELECT	 op2.PartyName								AS 'pi.pn'
					,x.GroupName								AS 'pi.bg' 
					,od.BrandName								AS 'pi.bn'
					,od.Description								AS 'pi.dc'
					,od.InvoiceLanguage							AS 'pi.iv'
					,FORMAT (od.LaunchDate,'MMM dd, yyyy') 		AS 'pi.ld'
					,FORMAT (od.SuspendedDate,'MMM dd, yyyy')	AS 'pi.sd'
					,FORMAT (od.TerminatedDate,'MMM dd, yyyy') 	AS 'pi.tmd'
					,pl.PlatformName 	AS 'pi.pp'
					,od.CompanyName		AS 'a1.cn1'
					,od.AttnName		AS 'a1.an1'
					,od.Address1		AS 'a1.ad1'
					,od.CompanyName2	AS 'a2.cn2'
					,od.AttnName2		AS 'a2.an2'
					,od.Address2		AS 'a2.ad2'
					,ci.baseCurrInfo    AS 'bcs'
					,bcf.bcfInfo		AS 'bcfs'
			FROM OAS_PartyDetail od WITH(NOLOCK)
			INNER JOIN OAS_Party op2 WITH(NOLOCK) ON od.PartyID = op2.PartyID
			INNER JOIN dbo.LA_f_PayerPlatform_Sel() pl ON pl.PlatformId = op2.PlatformId
			OUTER APPLY (SELECT TOP 1 oc.ToParty , pg.GroupName
						 FROM OAS_ChargeInfo oc WITH(NOLOCK) 
						 INNER JOIN dbo.LA_f_BillingGroupSel() pg ON pg.PartyId = oc.ToParty
						 WHERE od.PartyID = oc.FromParty AND oc.ChargeType = 1 AND GETDATE() BETWEEN oc.FromDate AND oc.Todate ) x
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
			OUTER APPLY (
						SELECT
						(
						SELECT  CONVERT(VARCHAR(10),op.PartyID)  + CONVERT(CHAR(8),op.FromDate,112) AS FakeID,
								CASE WHEN op.IsBalanceCarryForward = 0 THEN 'Do not carry forward losses' ELSE 'Carry forward losses' END  'ibcf', 
								op.FromDate 'bfd', 
								op.ToDate  'btd'
						FROM SH_SabaPlay_BalanceCarryForwardSetting op WITH(NOLOCK) 
						WHERE op.PartyID = od.PartyID FOR JSON PATH , INCLUDE_NULL_VALUES    
						) AS  bcfInfo
					) bcf
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