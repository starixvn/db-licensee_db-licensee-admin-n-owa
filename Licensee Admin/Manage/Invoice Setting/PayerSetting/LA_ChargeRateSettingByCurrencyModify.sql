/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[LA_ChargeRateSettingByCurrencyModify]
	 @ChargeID						INT
	,@MasterRate					MONEY
	,@DetailChargeRateSettingXml	NVARCHAR (MAX)
	,@UserID						INT
	,@LoginIP						VARCHAR (50) = ''
	,@ErrCode						INT = 0 OUTPUT
	,@ErrMsg						NVARCHAR(1000) = '' OUTPUT
AS
/*
	 Created: 20191202@Parsons
	 Task: 
	 DB: DBCUST.bodb_Licensee

	 Revisions:
		- 20191202@Parsons: Setup billing terms by Currency  [#120005]
		- 20220831@Malcolm: Automate the PT adjustment when the charge rate is changed [RemineID: #171705]
		- 20221205@Danny Remove Hx9candy From Crypto Licensee List [RedmineID: #181279]
		- 20230310@Danny: Insert new log with more information [#FeatureID 175125]
	 Params:
		+ @DetailChargeRateSettingXml: '<ChargeSettings>
								  <ChargeSetting>
									<ChargeId>1994</ChargeId>
									<CurrencyId>1</CurrencyId>
									<Rate>0.2</Rate>
								  </ChargeSetting>
								  <ChargeSetting>
									<ChargeId>1994</ChargeId>
									<CurrencyId>1</CurrencyId>
									<Rate>0.3</Rate>
								  </ChargeSetting>
								</ChargeSettings>'
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @logChargeRateOld NVARCHAR(MAX), @logChargeRate NVARCHAR(MAX), @logChargeRateActionID INT
	DECLARE @ChargeSettings AS TABLE (ChargeID INT, CurrencyId INT, Rate MONEY)
	DECLARE @ChargRateUpd AS TABLE (ChargeID INT, CurrencyId INT, Rate MONEY)
	DECLARE @StartRun		DATETIME = CURRENT_TIMESTAMP, 
			@EndRun			DATETIME, 
			@Duration		INT
	DECLARE @SiteName VARCHAR(20) = '', @ProductId INT, @Product3rdId INT, @ProductName VARCHAR(50), @InputPT VARCHAR(MAX) = '', @PartyID INT, @LicenseeID INT
	SELECT @SiteName = l.LicenseeName , @PartyID = p.PartyID, @LicenseeID = l.LicenseeID
	FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK) 
		INNER JOIN dbo.OAS_Party p  WITH(NOLOCK) ON p.PartyID = ci.FromParty
		INNER JOIN dbo.Licensees l WITH(NOLOCK) ON l.LicenseeID = p.OldRefID
	WHERE ci.ChargeID = @ChargeID AND l.IsDeposit = 1

	DECLARE @tmpPartyOfferCrypto TABLE (PartyId INT)
	INSERT INTO @tmpPartyOfferCrypto(PartyId)
	SELECT  PartyID FROM LA_f_CryptoPartyListSel()

	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @DetailChargeRateSettingXml
	BEGIN TRY
		INSERT INTO @ChargeSettings(ChargeId, CurrencyId, Rate)
		SELECT ChargeID, CurrencyId, Rate
		FROM OPENXML(@idoc, 'ChargeSettings/ChargeSetting')
		WITH 
		(
			 ChargeId		INT   'ChargeId'
			,CurrencyId	    INT   'CurrencyId'
			,Rate			MONEY 'Rate'
		)
	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'There''s something wrong with Charge rate settings, update failed. Please try again.', @ErrCode = 504
		RETURN
	END CATCH
	EXEC sp_xml_removedocument @idoc

	DECLARE @UserName VARCHAR(50) = '', @CurrentDate DATE = CONVERT(DATE, GETDATE()), @OldMasterRate MONEY, @ToDate DATETIME

	SELECT @OldMasterRate = Rate FROM OAS_ChargeInfo WITH(NOLOCK) WHERE ChargeID = @ChargeID

	SELECT @UserName = Username FROM dbo.LA_User WITH(NOLOCK) WHERE UserID = @UserID
	-- Get Charge Rate to update 
	INSERT INTO @ChargRateUpd (ChargeID, CurrencyId, Rate)
	SELECT ChargeID, 0, CASE WHEN @MasterRate = Rate THEN -1 ELSE @MasterRate END -- Rate = -1 => not update
	FROM dbo.OAS_ChargeInfo WITH(NOLOCK)
	WHERE ChargeID = @ChargeID 

	INSERT INTO @ChargRateUpd (ChargeID, CurrencyId, Rate)
	SELECT c.ChargeID, c.CurrencyId, CASE WHEN ISNULL(cr.Rate, c.Rate - 1) = c.Rate THEN -1 ELSE c.Rate END
	FROM @ChargeSettings c	
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH(NOLOCK) ON cr.CurrencyID = c.CurrencyId AND cr.ChargeID = @ChargeID

	IF NOT EXISTS (SELECT 1 FROM @ChargRateUpd c WHERE Rate <> -1) 	
	   AND EXISTS (
			SELECT 1 
			FROM dbo.LA_ChargeRateByCurrency lc WITH(NOLOCK) 
				LEFT JOIN @ChargeSettings s ON s.CurrencyId = lc.CurrencyID
			WHERE lc.ChargeID = @ChargeID AND s.ChargeID IS NULL
		)
	BEGIN
		UPDATE @ChargRateUpd
			SET Rate = @MasterRate
		WHERE CurrencyId = 0
	END
	 
	BEGIN TRY
	-- Old data

		;WITH t AS
		(
			SELECT		op.PartyName,
						od.BrandName,
						CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END Product,
						oc.FromDate,
						oc.ToDate,
						oc.FirstOfBilling,
						oc.BasisOfBilling,
						(CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + '%') Rate,
						STRING_AGG(x.Code,',') Currs,
						CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate
			FROM OAS_Party op WITH(NOLOCK)
			INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON op.PartyID = od.PartyID
			INNER JOIN Licensees l WITH(NOLOCK) ON op.OldRefID = l.LicenseeID
			INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON op.PartyID = oc.FromParty AND oc.ProductID IN ( 0,2) and oc.FromDate <=GETDATE() AND GETDATE() <= oc.ToDate 
			CROSS APPLY (
				SELECT DISTINCT lc.Currency, CASE WHEN e.ExchangeId IN (96,202) THEN e.Code + ' (' + e.currency + ')' ELSE e.Code END Code
				FROM LicenseeCust lc  WITH(NOLOCK) 
				INNER JOIN  CustDB.dbo.exchange e with(nolock) on lc.Currency = e.ExchangeId
				WHERE lc.LicenseeID = l.LicenseeID and lc.roleID = 2 and e.ExchangeId <> 20
			) x
			LEFT JOIN  LA_ChargeRateByCurrency lcr WITH(NOLOCK) ON oc.ChargeID = lcr.ChargeID AND x.Currency = lcr.CurrencyID
			LEFT JOIN  Product3rd p3 WITH(NOLOCK) ON oc.ProductID = p3.Productid
			WHERE op.PartyID = @PartyID AND oc.ChargeID = @ChargeID
			GROUP BY op.PartyName,
						od.BrandName,
						CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END,
						oc.FromDate,
						oc.ToDate,
						oc.FirstOfBilling,
						oc.BasisOfBilling,
						CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + '%',
						CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END
		) 
		, t1 AS
		(
			SELECT t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,STRING_AGG(cr.r, CHAR(13)) AS r
			FROM t
			CROSS APPLY (
					SELECT CASE WHEN t.isMasterRate = 1 AND EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'Others ' 
								WHEN t.isMasterRate = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'All ' 
								ELSE '' END + '('+ t.Currs + ') - ' + Rate AS r
			) cr
			GROUP BY t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling
		) SELECT @logChargeRateOld = 
				(
				SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn', crs.crs AS 'crs'
				FROM t1 t 
				CROSS APPLY 
				(
					SELECT 
					(
						SELECT  u.Product p ,  u.FromDate fd, u.ToDate td , u.FirstOfBilling fb, u.BasisOfBilling bb , u.r
						FROM t1 u  WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName FOR JSON PATH
					) crs
				) crs  
				GROUP BY t.PartyName, t.BrandName, crs.crs
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
		)

		-- Update master rate
		UPDATE OAS_ChargeInfo WITH(ROWLOCK)
		SET Rate = @MasterRate
		WHERE ChargeID = @ChargeID

		-- Insert charge rate by currency
		;MERGE [dbo].[LA_ChargeRateByCurrency] WITH(ROWLOCK, UPDLOCK) AS t
		USING @ChargeSettings AS s
		ON (t.ChargeId = s.ChargeID AND t.CurrencyID = s.CurrencyID)
		WHEN NOT MATCHED BY TARGET
			THEN INSERT(ChargeId, CurrencyID, Rate)
					VALUES(s.ChargeId, s.CurrencyID, s.Rate)
		WHEN MATCHED
			THEN UPDATE SET Rate = s.Rate
		WHEN NOT MATCHED BY SOURCE AND t.ChargeId = @ChargeId
			THEN DELETE;

		;WITH t AS
		(
			SELECT		op.PartyName,
						od.BrandName,
						CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END Product,
						oc.FromDate,
						oc.ToDate,
						oc.FirstOfBilling,
						oc.BasisOfBilling,
						(CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + '%') Rate,
						STRING_AGG(x.Code,',') Currs,
						CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate
			FROM OAS_Party op WITH(NOLOCK)
			INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON op.PartyID = od.PartyID
			INNER JOIN Licensees l WITH(NOLOCK) ON op.OldRefID = l.LicenseeID
			INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON op.PartyID = oc.FromParty AND oc.ProductID IN ( 0,2) and oc.FromDate <=GETDATE() AND GETDATE() <= oc.ToDate 
			CROSS APPLY (
				SELECT DISTINCT lc.Currency, CASE WHEN e.ExchangeId IN (96,202) THEN e.Code + ' (' + e.currency + ')' ELSE e.Code END Code
				FROM LicenseeCust lc  WITH(NOLOCK) 
				INNER JOIN  CustDB.dbo.exchange e with(nolock) on lc.Currency = e.ExchangeId
				WHERE lc.LicenseeID = l.LicenseeID and lc.roleID = 2 and e.ExchangeId <> 20
			) x
			LEFT JOIN  LA_ChargeRateByCurrency lcr WITH(NOLOCK) ON oc.ChargeID = lcr.ChargeID AND x.Currency = lcr.CurrencyID
			LEFT JOIN  Product3rd p3 WITH(NOLOCK) ON oc.ProductID = p3.Productid
			WHERE op.PartyID = @PartyID AND oc.ChargeID = @ChargeID
			GROUP BY op.PartyName,
						od.BrandName,
						CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END,
						oc.FromDate,
						oc.ToDate,
						oc.FirstOfBilling,
						oc.BasisOfBilling,
						CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + '%',
						CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END
		) 
		, t1 AS
		(
			SELECT t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,STRING_AGG(cr.r, CHAR(13)) AS r
			FROM t
			CROSS APPLY (
					SELECT CASE WHEN t.isMasterRate = 1 AND EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'Others ' 
								WHEN t.isMasterRate = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'All ' 
								ELSE '' END + '('+ t.Currs + ') - ' + Rate AS r
			) cr
			GROUP BY t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling
		) SELECT @logChargeRate = 
				(
				SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn', crs.crs AS 'crs'
				FROM t1 t 
				CROSS APPLY 
				(
					SELECT 
					(
						SELECT  u.Product p ,  u.FromDate fd, u.ToDate td , u.FirstOfBilling fb, u.BasisOfBilling bb , u.r
						FROM t1 u  WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName FOR JSON PATH
					) crs
				) crs  
				GROUP BY t.PartyName, t.BrandName, crs.crs
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
		)

		SET @EndRun = GETDATE()
		SET @Duration = DATEDIFF(MILLISECOND, @StartRun, @EndRun)

		--  Write Log ChargeRate Setting
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_ChargeRateSettingByCurrencyModify'
			,@CustId		= @PartyID
			,@Duration		= @duration
			,@TrackingValue2 = @logChargeRate
			,@TrackingValue = @logChargeRateOld
			,@ActionID		 = 1201
	END TRY
	BEGIN CATCH 
		SELECT @ErrCode = ERROR_NUMBER(), @ErrMsg = ERROR_MESSAGE()
		
		UPDATE OAS_ChargeInfo WITH(ROWLOCK)
			SET Rate = @OldMasterRate
		WHERE ChargeID = @ChargeID
		
		RETURN
	END CATCH

	-- Update PT on NAP
	SELECT 
		@ProductId = CASE WHEN ci.ProductID = 0  THEN 1 ELSE p.ProductID END
		,@ProductName = CASE WHEN ci.ProductId = 0 THEN 'Sportsbook' ELSE pr.ProductName END
		,@Product3rdId = ci.ProductID
		,@ToDate = ci.ToDate
	FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
		LEFT JOIN dbo.Product3rd pr WITH(NOLOCK) ON pr.Productid = ci.ProductID
		LEFT JOIN DBPRO.bodb02.dbo.Products p WITH (NOLOCK) ON p.ProductPrefix = pr.ProductPrefix
	WHERE ci.ChargeID = @ChargeID

	/*Delete prevent updating unexpected NAP PT value*/
	DELETE c
	FROM @ChargRateUpd c
	WHERE @Product3rdId IN (14, 17, 3, 31, 10, 13, 16) OR @PartyID IN (SELECT x.PartyId FROM @tmpPartyOfferCrypto x)
		OR EXISTS (
				SELECT 1 
				FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
				WHERE ci.ChargeID = c.ChargeID AND @Product3rdId = 39 AND ci.ChargeType = 12
			)
		OR @ToDate < @CurrentDate

	/*not update Sportsbook charge rate > 12% (exclude 9wickets licensee) or Sportsbook charge rate = 0 or CandyA18 licensees*/
	UPDATE c
		SET c.Rate = -1
	FROM @ChargRateUpd c
	WHERE @ProductId = 1 AND (c.Rate > 0.12 AND @SiteName <> '9wickets')
		
	/*delete new charge rate is same as same charge rate*/
	DELETE c
	FROM @ChargRateUpd c
	WHERE NOT EXISTS (SELECT 1 FROM @ChargRateUpd WHERE Rate <> -1)

	SELECT @InputPT = CONVERT(VARCHAR(MAX),
	(
		SELECT 
			@ProductId AS '@PID'
			,CurrencyId AS '@CID'
			,CASE WHEN Rate = -1 THEN -1 ELSE 100* (1 - Rate) END AS '@PT' -- -1 : not update
		FROM @ChargRateUpd 
		FOR XML PATH('PT'), ROOT('ROOT')
	))
	
	IF ISNULL(@SiteName, '') <> '' AND ISNULL(@InputPT, '') <> '' 
	BEGIN
		IF EXISTS (SELECT 1 FROM dbo.OAS_ChargeInfo WITH(NOLOCK) WHERE ChargeID = @ChargeID AND @CurrentDate NOT BETWEEN FromDate AND ToDate)
		BEGIN
			SELECT @ErrCode = 0, @ErrMsg =  @ProductName + ': NAP PT update failed due to it''s not current charge rate.'
			RETURN
		END

		EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_PTSettingUpd 
			@Site = @SiteName
			,@InputPT = @InputPT
			,@UserID = @UserID
			,@UserName = @UserName
			,@IP = @LoginIP
			,@ErrCode = @ErrCode OUTPUT
			,@ErrMsg = @ErrMsg OUTPUT

		IF @ErrCode <> 0
		BEGIN
			SELECT @ErrCode = 0, @ErrMsg = @ProductName + ': ' + @ErrMsg
			RETURN
		END
	END

END
GO