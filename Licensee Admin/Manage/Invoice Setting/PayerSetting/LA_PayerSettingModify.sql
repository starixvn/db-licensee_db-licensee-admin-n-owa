/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingModify]
	@PayerID				INT	
	,@LaunchDate			DATE = NULL
	,@SuspendedDate			DATE = NULL
	,@TerminatedDate		DATE = NULL
	,@ChargeSettingXML		NVARCHAR (MAX)
	,@MinFeeSettingXML		NVARCHAR (MAX)
	,@WaiveSettingXML		NVARCHAR (MAX)
	,@UserID				INT
	,@LoginIP				VARCHAR (50)	= ''
	,@ErrCode				INT				= 0		OUTPUT
	,@ErrMsg				NVARCHAR(1000)	= ''	OUTPUT	
AS
/*  
	 Created: 2015042$@Florent
	 Task : Add/ Modify Minfee setting
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:     
		- 20150918@Victor: Support Chinese on Settings
		- 20170220@bruce: update payer settings [#70050]
		- 20180706@bruce: enhance discount group [#94282]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20200831@Mason: Remove redundant code of @PayerGroupId [#138249]
		- 20210318@Mason: Change Base Currency Of Licensee [#151466]
		- 20220118@Percy: Add Licensee Status Setting [RedmineID: #166751]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20220831@Malcolm: Automate the PT adjustment when the charge rate is changed [RemineID: #171705]
		- 20221205@Danny: Remove Hx9candy From Crypto Licensee List [RedmineID: #181279]
		- 20231113@Danny: Support to remove up-coming waive period [RedmineID: #194868]
		- 20240527@Danny: Automate the PT adjustment when the Exchange charge rate is changed [RemineID: #201477]
		- 20250225@Danny: Integrate Double S System Inc group Licensees [RedmineID: #217961]
		- 20250529@Eddie: Enhancement of deleting the setting [RedmineID: #223299]

	 Params:	
		+ @ChargeSettingXML:
					<ChargeSettings>
						<ChargeSetting>
							<ChargeId>3483</ChargeId>
							<ProductId>2</ProductId>
							<FirstBilling>20130101</FirstBilling>
							<BasisBilling>15% of Gro1ss Win</BasisBilling>
							<BettypeRef>0</BettypeRef>
							<Rate>0.9</Rate><
							ChargeType>1</ChargeType>
							<FromDate>20180801</FromDate>
							<ToDate>20250531</ToDate>
							<ChargeSettingByCurrencies>
								<ChargeSettingByCurrency>
									<CurrencyId>1</CurrencyId>
									<Rate>0.2</Rate>
								</ChargeSettingByCurrency>
								<ChargeSettingByCurrency>
									<CurrencyId>2</CurrencyId>
									<Rate>0.3</Rate>
								</ChargeSettingByCurrency>
							</ChargeSettingByCurrencies>
						</ChargeSetting>
					</ChargeSettings>
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ProductListAll VARCHAR(100) = ''
		   ,@SiteName VARCHAR(20) = ''
		   ,@InputPT VARCHAR(MAX) = ''
		   ,@ChargeSettingXMLOUT XML
		   ,@Username VARCHAR(50)
		   ,@CurrentDate DATE
		   ,@LogSPData NVARCHAR(MAX)
		   ,@LogSPDataOld NVARCHAR(MAX)
		   ,@LogActionID INT = 1001
		   ,@StartRun DATETIME
		   ,@EndRun DATETIME
		   ,@Duration INT
		   ,@IsWriteLogPayer BIT
		   ,@InputPTExchange VARCHAR(MAX) = ''
		   ,@ErrCodeExchange INT = 0
		   ,@ErrMsgExchange NVARCHAR(1000) = ''
		   ,@MinFeeInsertedList VARCHAR(100)
		   ,@WaiveInsertedList VARCHAR(100)
		   ,@Old_LaunchDate DATE
		   ,@Old_SuspendedDate DATE
		   ,@Old_TerminatedDate DATE
		   ,@ChargeSettingsXML XML

	DECLARE @ChargeRate TABLE (ChargeID INT, ProductId INT, ProductName VARCHAR(50), Rate MONEY, CurrencyId INT, FromDate DATETIME, ToDate DATETIME, IsValid BIT DEFAULT(1), IsChangedRate BIT, IsChangedDate BIT)

	DECLARE @tmpPartyOfferCrypto TABLE (PartyId INT)

	DECLARE @T_ChargeId TABLE (ChargeID INT)

	-- Time start
	SET @StartRun = GETDATE()

	SELECT @Username = Username FROM LA_User WITH(NOLOCK) WHERE UserID = @UserID 

	SELECT @ChargeSettingsXML = CONVERT(XML, @ChargeSettingXML)
	
	INSERT INTO @T_ChargeId(ChargeID)
	SELECT DISTINCT t.c.value('(ChargeId/text())[1]', 'INT') AS ChargeID
	FROM @ChargeSettingsXML.nodes('ChargeSettings/ChargeSetting') AS t(c)
	OPTION (OPTIMIZE FOR (@ChargeSettingsXML = NULL))

	-- Update LaunchDate/SuspendedDate/TerminatedDate
	SELECT  @Old_LaunchDate = LaunchDate, @Old_SuspendedDate = SuspendedDate, @Old_TerminatedDate = TerminatedDate
	FROM dbo.OAS_PartyDetail WITH (NOLOCK)
	WHERE PartyId = @PayerId

	IF (ISNULL(@Old_LaunchDate,'') <> ISNULL(@LaunchDate,'') OR ISNULL(@Old_SuspendedDate,'') <> ISNULL(@SuspendedDate,'') OR ISNULL(@Old_TerminatedDate,'') <> ISNULL(@TerminatedDate,''))
		SELECT @IsWriteLogPayer = 1
	
	IF @IsWriteLogPayer = 1
	BEGIN
		--write log old
		SELECT @LogSPDataOld = (
			SELECT Op2.PartyName							AS 'pi.pn'
				  ,x.GroupName								AS 'pi.bg' 
				  ,od.BrandName								AS 'pi.bn'
				  ,od.Description							AS 'pi.dc'
				  ,od.InvoiceLanguage						AS 'pi.iv'
				  ,FORMAT(od.LaunchDate,'MMM dd, yyyy') 	AS 'pi.ld'
				  ,FORMAT(od.SuspendedDate,'MMM dd, yyyy')	AS 'pi.sd'
				  ,FORMAT(od.TerminatedDate,'MMM dd, yyyy') AS 'pi.tmd'
				  ,od.CompanyName							AS 'a1.cn1'
				  ,od.AttnName								AS 'a1.an1'
				  ,od.Address1								AS 'a1.ad1'
				  ,od.CompanyName2							AS 'a2.cn2'
				  ,od.AttnName2								AS 'a2.an2'
				  ,od.Address2								AS 'a2.ad2'
				  ,ci.baseCurrInfo  						AS 'bcs'
			FROM dbo.OAS_PartyDetail od WITH (NOLOCK)
				INNER JOIN dbo.OAS_Party op2 WITH (NOLOCK) ON od.PartyID = op2.PartyID
				OUTER APPLY(
					SELECT TOP 1 oc.ToParty, pg.GroupName
					FROM dbo.OAS_ChargeInfo oc WITH (NOLOCK) 
						INNER JOIN dbo.LA_f_BillingGroupSel() pg ON pg.PartyId = oc.ToParty
					WHERE od.PartyID = oc.FromParty
					  AND oc.ChargeType = 1
					  AND GETDATE() BETWEEN oc.FromDate AND oc.Todate
				) x
				OUTER APPLY(
					SELECT (
						SELECT CASE WHEN op.BaseCurrencyId = 142 THEN 'USDT' ELSE e.Code END AS 'c'
							  ,op.LicenseeCode AS 'lc'
							  ,op.FromDate 	   AS 'fd'
							  ,op.ToDate 	   AS 'td'
							  ,CONVERT(VARCHAR(10), op.PartyID) + CONVERT(VARCHAR(10), op.BaseCurrencyId) + CONVERT(CHAR(8), op.FromDate, 112) AS FakeID
						FROM OAS_PartyBaseCurrency op WITH (NOLOCK)
							INNER JOIN CustDB.dbo.exchange e WITH (NOLOCK) ON op.BaseCurrencyId = e.ExchangeId
						WHERE op.PartyID = od.PartyID
						FOR JSON PATH, INCLUDE_NULL_VALUES
					) AS  baseCurrInfo
				) ci
			WHERE od.PartyID = @PayerID
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES    
		)
	END

	BEGIN TRY
		UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
		SET LaunchDate = @LaunchDate, SuspendedDate = @SuspendedDate, TerminatedDate = @TerminatedDate
		WHERE PartyId = @PayerId
	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 101, @ErrMsg = 'Update failed. Please try again.'
		RETURN
	END CATCH

	--Minfee
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @MinFeeSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode OUTPUT
		, @ErrMsg				= @ErrMsg OUTPUT
		, @MinfeeInsertedList	= @MinFeeInsertedList OUTPUT
		, @FeeTypeId			= 1

	IF @ErrCode <> 0
	BEGIN
		--Rollback LaunchDate/SuspendedDate/TerminatedDate
		UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
		SET LaunchDate = @Old_LaunchDate, SuspendedDate = @Old_SuspendedDate, TerminatedDate = @Old_TerminatedDate
		WHERE PartyId = @PayerId

		--Rollback Minfee
		IF ISNULL(@MinFeeInsertedList, 0) <> 0
		BEGIN
			DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)
			WHERE PartyId = @PayerID
			  AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@MinFeeInsertedList, ','))
		END
		RETURN
	END

	--Waive
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @WaiveSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode OUTPUT
		, @ErrMsg				= @ErrMsg OUTPUT
		, @MinfeeInsertedList	= @WaiveInsertedList OUTPUT
		, @FeeTypeId			= 2

	IF @ErrCode <> 0 
	BEGIN
		--Rollback LaunchDate/SuspendedDate/TerminatedDate
		UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
		SET LaunchDate = @Old_LaunchDate, SuspendedDate = @Old_SuspendedDate, TerminatedDate = @Old_TerminatedDate
		WHERE PartyId = @PayerId

		--Rollback Minfee
		IF ISNULL(@MinFeeInsertedList, 0) <> 0
		BEGIN
			DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)
			WHERE PartyId = @PayerID
			AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@MinFeeInsertedList, ','))
		END

		--Rollback waive
		IF ISNULL(@WaiveInsertedList, 0) <> 0
		BEGIN
			DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)
			WHERE PartyId = @PayerID
			AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@WaiveInsertedList, ','))
		END
		RETURN
	END

	--Modify Chargerate Setting
	IF EXISTS ( SELECT 1 FROM @T_ChargeId WHERE ChargeID >= 0 )
	BEGIN
		EXEC dbo.LA_ChargeRateSettingModify
			@PayerID			  = @PayerID
			,@ChargeSettingXML	  = @ChargeSettingXML
			,@UserID			  = @UserID
			,@LoginIP			  = @LoginIP
			,@ErrCode			  = @ErrCode OUTPUT
			,@ErrMsg			  = @ErrMsg OUTPUT		
			,@ChargeSettingXMLOUT = @ChargeSettingXMLOUT OUTPUT

		IF @ErrCode <> 0
		BEGIN
			--Rollback LaunchDate/SuspendedDate/TerminatedDate
			UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
			SET LaunchDate = @Old_LaunchDate, SuspendedDate = @Old_SuspendedDate, TerminatedDate = @Old_TerminatedDate
			WHERE PartyId = @PayerId

			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
			BEGIN
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)
				WHERE PartyId = @PayerID
				AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@MinFeeInsertedList, ','))
			END

			--Rollback waive
			IF ISNULL(@WaiveInsertedList, 0) <> 0
			BEGIN
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)
				WHERE PartyId = @PayerID
				AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@WaiveInsertedList, ','))
			END
			RETURN
		END
	END

	IF EXISTS ( SELECT 1 FROM @T_ChargeId WHERE ChargeID < 0 )
	BEGIN
		EXEC dbo.SH_ChargeRateSettingDel
			@PayerID		   = @PayerID
			,@ChargeSettingXML = @ChargeSettingXML
			,@UserID		   = @UserID
			,@LoginIP		   = @LoginIP
			,@ErrCode		   = @ErrCode OUTPUT
			,@ErrMsg		   = @ErrMsg OUTPUT

		IF @ErrCode <> 0
		BEGIN
			--Rollback LaunchDate/SuspendedDate/TerminatedDate
			UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
			SET LaunchDate = @Old_LaunchDate, SuspendedDate = @Old_SuspendedDate, TerminatedDate = @Old_TerminatedDate
			WHERE PartyId = @PayerId

			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
			BEGIN
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)
				WHERE PartyId = @PayerID
				AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@MinFeeInsertedList, ','))
			END

			--Rollback waive
			IF ISNULL(@WaiveInsertedList, 0 ) <> 0
			BEGIN
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)
				WHERE PartyId = @PayerID
				AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@WaiveInsertedList, ','))
			END
			RETURN
		END
	END

	IF @IsWriteLogPayer = 1
	BEGIN
		SELECT @LogSPData = (
			SELECT Op2.PartyName							AS 'pi.pn'
				  ,x.GroupName								AS 'pi.bg' 
				  ,od.BrandName								AS 'pi.bn'
				  ,od.Description							AS 'pi.dc'
				  ,od.InvoiceLanguage						AS 'pi.iv'
				  ,FORMAT(od.LaunchDate,'MMM dd, yyyy') 	AS 'pi.ld'
				  ,FORMAT(od.SuspendedDate,'MMM dd, yyyy')	AS 'pi.sd'
				  ,FORMAT(od.TerminatedDate,'MMM dd, yyyy') AS 'pi.tmd'
				  ,od.CompanyName							AS 'a1.cn1'
				  ,od.AttnName								AS 'a1.an1'
				  ,od.Address1								AS 'a1.ad1'
				  ,od.CompanyName2							AS 'a2.cn2'
				  ,od.AttnName2								AS 'a2.an2'
				  ,od.Address2								AS 'a2.ad2'
				  ,ci.baseCurrInfo  						AS 'bcs'
			FROM dbo.OAS_PartyDetail od WITH (NOLOCK)
				INNER JOIN dbo.OAS_Party op2 WITH (NOLOCK) ON od.PartyID = op2.PartyID
				OUTER APPLY(
					SELECT TOP 1 oc.ToParty, pg.GroupName
					FROM dbo.OAS_ChargeInfo oc WITH(NOLOCK) 
						INNER JOIN dbo.LA_f_BillingGroupSel() pg ON pg.PartyId = oc.ToParty
					WHERE od.PartyID = oc.FromParty
					  AND oc.ChargeType = 1
					  AND GETDATE() BETWEEN oc.FromDate AND oc.Todate
				) x
				OUTER APPLY(
					SELECT(
						SELECT CASE WHEN op.BaseCurrencyId = 142 THEN 'USDT' ELSE e.Code END AS 'c'
							  ,op.LicenseeCode AS 'lc' 
							  ,op.FromDate 	   AS 'fd'
							  ,op.ToDate 	   AS 'td'
							  ,CONVERT(VARCHAR(10), op.PartyID) + CONVERT(VARCHAR(10), op.BaseCurrencyId) + CONVERT(CHAR(8), op.FromDate, 112) AS FakeID
						FROM OAS_PartyBaseCurrency op WITH (NOLOCK) 
							INNER JOIN CustDB.dbo.exchange e WITH (NOLOCK) ON op.BaseCurrencyId = e.ExchangeId
						WHERE op.PartyID = od.PartyID
						FOR JSON PATH, INCLUDE_NULL_VALUES 
					) AS baseCurrInfo
				) ci
			WHERE od.PartyID = @PayerID
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
		)

		SET @EndRun = GETDATE()
		SET @Duration = DATEDIFF(MILLISECOND, @StartRun, @EndRun)

		-- Write Log
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_PayerSettingModify'
			,@CustId		= @PayerID
			,@Duration		= @Duration
			,@TrackingValue2 = @LogSPData
			,@TrackingValue = @LogSPDataOld
			,@ActionID		= @LogActionID
	END

	-- Update on NAP
	INSERT INTO @ChargeRate (ChargeId, FromDate, ToDate, ProductId, Rate, IsChangedRate, IsChangedDate, CurrencyId)
	SELECT
		t.c.value('(ChargeId/text())[1]', 'INT') AS ChargeId
		,t.c.value('(FromDate/text())[1]', 'DATETIME') AS FromDate
		,t.c.value('(ToDate/text())[1]', 'DATETIME') AS ToDate
		,t.c.value('(ProductId/text())[1]', 'INT') AS ProductId
		,t.c.value('(Rate/text())[1]', 'MONEY') AS Rate
		,t.c.value('(IsChangedRate/text())[1]', 'BIT') AS IsChangedRate
		,t.c.value('(IsChangedDate/text())[1]', 'BIT') AS IsChangedDate
		,0 AS CurrencyId
	FROM @ChargeSettingXMLOUT.nodes('ChargeSettings/ChargeSetting') AS t(c)
	OPTION (OPTIMIZE FOR (@ChargeSettingXMLOUT = NULL))

	SELECT @CurrentDate = CONVERT(DATE, GETDATE())

	UPDATE @ChargeRate
		SET IsValid = 0
	WHERE @CurrentDate NOT BETWEEN FromDate AND ToDate

	INSERT INTO @tmpPartyOfferCrypto(PartyId)
	SELECT PartyID FROM LA_f_CryptoPartyListSel()

	SELECT @SiteName = l.LicenseeName
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.Licensees l WITH(NOLOCK) ON p.OldRefID = l.LicenseeID
	WHERE l.IsDeposit = 1 AND p.PartyID = @PayerID

	DELETE cr
	FROM @ChargeRate cr
	WHERE cr.ProductId IN (14, 17, 3, 10, 13, 16) OR  cr.ToDate < @CurrentDate OR @PayerID IN (SELECT x.PartyId FROM @tmpPartyOfferCrypto x) 
		OR EXISTS (
			SELECT 1 
			FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
			WHERE ci.ChargeID = cr.ChargeID AND cr.ProductId = 39 AND ci.ChargeType = 12
		)

	UPDATE c
		SET c.ProductId = CASE WHEN c.ProductId = 0 THEN 1 ELSE p.ProductId END, c.ProductName = CASE WHEN c.ProductId = 0 THEN 'Sportsbook' ELSE pr.ProductName END
	FROM @ChargeRate c
		LEFT JOIN dbo.Product3rd pr WITH(NOLOCK) ON pr.Productid = c.ProductId
		LEFT JOIN DBPRO.bodb02.dbo.Products p WITH (NOLOCK) ON p.ProductPrefix = pr.ProductPrefix

	;WITH CTE_ChargeId AS 
	(
		SELECT DISTINCT ChargeID, ProductId, ProductName, IsChangedDate FROM @ChargeRate WHERE IsValid = 1
	),CTE_ExistingCurrency AS
	(
		SELECT cr.ChargeID, cr.CurrencyID, c.ProductId, c.ProductName, CASE WHEN c.IsChangedDate = 1 THEN cr.Rate ELSE -1 END AS Rate
		FROM dbo.LA_ChargeRateByCurrency cr WITH(NOLOCK)
			INNER JOIN CTE_ChargeId c ON c.ChargeID = cr.ChargeID
	)
	INSERT INTO @ChargeRate (ChargeID, ProductId, ProductName, CurrencyId, Rate, IsValid)
	SELECT ChargeID, ProductId, ProductName, CurrencyID, Rate, 1 
	FROM CTE_ExistingCurrency

	/*1.Sportsbook charge rate > 12% (exclude 9wickets licensee) licensee*/
	UPDATE c
		SET c.Rate = CASE WHEN c.ProductId = 1 AND (c.Rate > 0.12 AND @SiteName <> '9wickets') THEN -1 
		                  WHEN c.CurrencyId = 0 THEN CASE WHEN c.IsChangedRate = 1 OR c.IsChangedDate = 1 THEN c.Rate ELSE -1 END 
					 ELSE c.Rate END  
	FROM @ChargeRate c 

	/*Delete prevent updating unexpected NAP PT value*/
	DELETE c
	FROM @ChargeRate c
	WHERE NOT EXISTS (SELECT 1 FROM @ChargeRate r WHERE r.ChargeID = c.ChargeID AND r.Rate <> -1)
	
	SELECT @InputPT = CONVERT(VARCHAR(MAX), 
	(
		SELECT 
			ProductId AS '@PID'
			,CurrencyId AS '@CID'
			,CASE WHEN Rate = -1 THEN -1 ELSE 100 * (1 - Rate) END AS '@PT' -- [-1] : not update
		FROM @ChargeRate 
		WHERE IsValid = 1 AND ProductId <> 31
		FOR XML PATH ('PT'), ROOT('ROOT')
	))

	SELECT @InputPTExchange = CONVERT(VARCHAR(MAX), 
	(
		SELECT 
			ProductId AS '@PID'
			,CurrencyId AS '@CID'
			,CASE WHEN Rate = -1 THEN -1 ELSE 100 * (1 - Rate) END AS '@PT' -- [-1] : not update
		FROM @ChargeRate 
		WHERE IsValid = 1 AND ProductId = 31 
		FOR XML PATH ('PT'), ROOT('ROOT')
	))

	IF ISNULL(@SiteName, '') <> '' AND ( ISNULL(@InputPT, '') <> '' OR  ISNULL(@InputPTExchange, '') <> '' )
	BEGIN
		IF ISNULL(@InputPT, '') <> ''
			EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_PTSettingUpd
				@Site = @SiteName
				,@InputPT = @InputPT
				,@UserID = @UserID
				,@Username = @Username
				,@IP = @LoginIP
				,@ErrCode = @ErrCode OUTPUT
				,@ErrMsg = @ErrMsg OUTPUT

		IF ISNULL(@InputPTExchange, '') <> ''
			EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_ChargePTUpd
				@Site = @SiteName
				,@InputPT = @InputPTExchange
				,@UserID = @UserID
				,@Username = @Username
				,@IP = @LoginIP
				,@ErrCode = @ErrCodeExchange OUTPUT
				,@ErrMsg = @ErrMsgExchange  OUTPUT
	END

	IF (@ErrCode  <> 0 OR @ErrCodeExchange <> 0 OR EXISTS (SELECT 1 FROM @ChargeRate WHERE IsValid = 0)) AND ISNULL(@SiteName, '') <> ''
	BEGIN
		IF @ErrCode <> 0 OR @ErrCodeExchange <> 0
		BEGIN
			IF @ErrCode <> 0
				SELECT 	@ErrMsg = ISNULL(@ErrMsg, '') + STUFF((SELECT ',' + ProductName
						FROM @ChargeRate 
						WHERE IsValid = 1 AND ProductId <> 31
						FOR XML PATH('')), 1, 1, '') + ': '+ @ErrMsg + '<br>'
			IF @ErrCodeExchange <> 0
				SELECT 	@ErrMsg = ISNULL(@ErrMsg, '') + STUFF((SELECT ',' + ProductName
						FROM @ChargeRate 
						WHERE IsValid = 1 AND ProductId = 31
						FOR XML PATH('')), 1, 1, '') + ': '+ @ErrMsgExchange + '<br>'
		END

		SELECT @ErrMsg =  ISNULL(@ErrMsg, '') + ProductName + ': NAP PT update failed due to it''s not current charge rate' + '<br>'
		FROM @ChargeRate
		WHERE IsValid = 0 

		SET @ErrCode = 0
		RETURN
	END


END
GO