/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateGroupChange]
	@GroupId		INT,
	@PartyId		INT,
	@EffectiveDate	DATE,
	@UserId			INT = 0,
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= ''	OUTPUT,
	@LoginIP				VARCHAR (50)	= ''
AS
/*
	Created: 20190221@Parsons
	Task: Get Payer setting
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20190221@Parsons: Manage Payer Setting - changing party group [#109189]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20190801@Parsons: Validate billing configuration [#109600]
		- 20200113@Parsons: Billing term by currency [#120005]
		- 20200619@Happy: Increase the length of @ProductCode params [#128570]
		- 20220614@Danny: Use explicit temporary table  [RemineID: #174035]
		- 20230310@Danny: Insert new log with more information [#FeatureID 175125]

	Params:
	Example:
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #ChangeRateTable
	(
		ChargeID		INT,
		ProductID		INT,
		FromParty		INT,
		ToParty			INT,
		ParentChargeID	INT,
		Rate			MONEY,
		ChargeType		TINYINT,
		FromDate		DATE,
		ToDate			DATE,
		Remark			NVARCHAR(200),
		BaseCurrencyId	TINYINT,
		FirstOfBilling	DATE,
		BasisOfBilling	NVARCHAR(4000),
		[Status]		INT,
		IsInserted		BIT
	)

	DECLARE		@StartRun		DATETIME,
				@EndRun			DATETIME,
				@Duration		INT,
				@LogSPData		NVARCHAR(MAX),
				@LogSPDataOld	NVARCHAR(MAX),
				@LogActionID	INT = 1201
	SET @StartRun = GETDATE()

	DECLARE @IsActived INT = 1, @IsActivating INT = 2, @IsExpired INT = 3
	DECLARE @ProductListAll	VARCHAR(500) = '', @MinDate DATE, @MaxDate	DATE	
	
	SELECT @ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM dbo.LA_f_Products3rd('')
	WHERE ProductPrefix <> 'RB' -- dont support RB

	SELECT @MinDate = MIN(ci.FromDate), @MaxDate = MAX(ci.ToDate)
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
	INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
	WHERE ci.FromParty = @PartyId

	INSERT INTO #ChangeRateTable (ChargeID, ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling, [Status], IsInserted)
	SELECT DISTINCT c1.ChargeID, c1.ProductID, FromParty, ToParty, ParentChargeID, Rate, c1.ChargeType, c1.FromDate, c1.ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling,
			CASE
				WHEN c1.FromDate < @EffectiveDate AND c1.ToDate >= @EffectiveDate THEN @IsActived
				WHEN c1.FromDate >= @EffectiveDate THEN @IsActivating
				ELSE @IsExpired
			END AS [Status],
			0 AS IsInserted
	FROM OAS_ChargeInfo c1 WITH(NOLOCK)
	INNER JOIN dbo.LA_f_ChargeInfo(@PartyId, @MinDate, @MaxDate, @ProductListAll, 'OA', 1) c2 ON c1.ChargeID = c2.ChargeID

	-- Write old log
	;WITH t AS
	(
		SELECT		op.PartyName,
					od.BrandName,
					CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END Product,
					FORMAT (oc.FromDate,'MMM dd, yyyy') FromDate,
					FORMAT (oc.ToDate,'MMM dd, yyyy') ToDate,
					FORMAT (oc.FirstOfBilling,'MMM dd, yyyy') FirstOfBilling,
					oc.BasisOfBilling,
					(CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') Rate,
					STRING_AGG(x.Code,', ') Currs,
					CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate,
					oc.ChargeID AS FakeID,
					 CASE WHEN oc.ProductID = 3 THEN 'BA Commission'
						  WHEN oc.ChargeType = 1 THEN 'Licensing Fee'
						  WHEN oc.ChargeType = 5 THEN 'BetTrade Commision for SB'   
						  WHEN oc.ChargeType = 6 THEN 'Commision Share'
						  WHEN oc.ChargeType = 7 THEN 'Cash-in Share' 
						  WHEN oc.ChargeType = 12 THEN 'Tips Amt Due' 
						  WHEN oc.ChargeType = 13 THEN 'BetTrade Commision for BA' 
						END ChargeTypeName
		FROM OAS_Party op WITH(NOLOCK)
		INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON op.PartyID = od.PartyID
		INNER JOIN Licensees l WITH(NOLOCK) ON op.OldRefID = l.LicenseeID
		INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON op.PartyID = oc.FromParty
		CROSS APPLY (
			SELECT DISTINCT lc.Currency, CASE WHEN e.ExchangeId IN (96,202) THEN e.Code + ' (' + e.currency + ')' ELSE e.Code END Code
			FROM LicenseeCust lc  WITH(NOLOCK) 
			INNER JOIN  CustDB.dbo.exchange e with(nolock) on lc.Currency = e.ExchangeId
			WHERE lc.LicenseeID = l.LicenseeID and lc.roleID = 2 and e.ExchangeId <> 20
		) x
		LEFT JOIN  LA_ChargeRateByCurrency lcr WITH(NOLOCK) ON oc.ChargeID = lcr.ChargeID AND x.Currency = lcr.CurrencyID
		LEFT JOIN  Product3rd p3 WITH(NOLOCK) ON oc.ProductID = p3.Productid
		WHERE op.PartyID = @PartyId AND oc.ChargeID IN (SELECT z.ChargeID FROM #ChangeRateTable z WHERE z.[Status] = 1)
		GROUP BY op.PartyName,
					od.BrandName,
					CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END,
					FORMAT (oc.FromDate,'MMM dd, yyyy'),
					FORMAT (oc.ToDate,'MMM dd, yyyy'),
					FORMAT (oc.FirstOfBilling,'MMM dd, yyyy'),
					oc.BasisOfBilling,
					CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %',
					CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END,
					oc.ChargeID,
					 CASE WHEN oc.ProductID = 3 THEN 'BA Commission'
						  WHEN oc.ChargeType = 1 THEN 'Licensing Fee'
						  WHEN oc.ChargeType = 5 THEN 'BetTrade Commision for SB'   
						  WHEN oc.ChargeType = 6 THEN 'Commision Share'
						  WHEN oc.ChargeType = 7 THEN 'Cash-in Share' 
						  WHEN oc.ChargeType = 12 THEN 'Tips Amt Due' 
						  WHEN oc.ChargeType = 13 THEN 'BetTrade Commision for BA' 
					END
	) 
	, t1 AS
	(
		SELECT t.FakeID, t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName,STRING_AGG(cr.r, CHAR(13)) AS r
		FROM t
		CROSS APPLY (
				SELECT CASE WHEN t.isMasterRate = 1 AND EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'Others ' 
							WHEN t.isMasterRate = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'All ' 
							ELSE '' END + '('+ t.Currs + ') - ' + Rate AS r
		) cr
		GROUP BY t.FakeID, t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName
	) SELECT @logSPDataOld = 
			(
			SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn', crs.crs AS 'crs'
			FROM t1 t 
			CROSS APPLY 
			(
				SELECT 
				(
					SELECT  u.FakeID ,u.Product p ,  u.FromDate fd, u.ToDate td , u.FirstOfBilling fb, u.BasisOfBilling bb , u.r, u.ChargeTypeName t
					FROM t1 u  WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName FOR JSON PATH
				) crs
			) crs  
			GROUP BY t.PartyName, t.BrandName, crs.crs
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
		) 

	--Step1: Expire all active charge rates at EffectiveDate - 1
		-- 1.1 Update OAS_ChargeInfo
	UPDATE c1
	SET ToDate = DATEADD(DAY, -1, @EffectiveDate)
	FROM OAS_ChargeInfo c1 WITH(NOLOCK) 
	INNER JOIN #ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID
	WHERE [Status] = @IsActived

		-- 1.2 Update OAS_ChargeInfoSub
	UPDATE cs
	SET ToDate = DATEADD(DAY, -1, @EffectiveDate)
	FROM OAS_ChargeInfoSub cs WITH(NOLOCK) 
	INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID 
	WHERE [Status] = @IsActived

	IF @@Error > 0
	BEGIN
		UPDATE c1
		SET c1.ToDate = c2.ToDate
		FROM OAS_ChargeInfo c1 WITH(NOLOCK) 
		INNER JOIN #ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID
		WHERE [Status] = @IsActived

		UPDATE cs
		SET ToDate = c.ToDate
		FROM OAS_ChargeInfoSub cs WITH(NOLOCK) 
		INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID
		WHERE [Status] = @IsActived 

		SELECT @ErrMsg = 'Fail to expire all active charge rates: ' + ERROR_MESSAGE(), @ErrCode = 504
		RETURN
	END

	--Step2: Copy charge rates to new group with FromDate = Effective date
	DECLARE @InsertedResult TABLE (ChargeId INT, ProductId INT)
	
	-- 2.1 OAS_ChargeInfo & LA_ChargeRateByCurrency
	DECLARE @OldChargeId INT, @NewChargeId INT, @ProductId INT
	WHILE EXISTS (SELECT TOP 1 1 FROM #ChangeRateTable WHERE IsInserted = 0 AND [Status] = @IsActived)
	BEGIN
		SELECT TOP 1 @OldChargeId = ChargeID, @ProductId = ProductID FROM #ChangeRateTable WHERE IsInserted = 0 AND [Status] = @IsActived

		-- Insert OAS_ChargeInfo
		INSERT INTO OAS_ChargeInfo(ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling)
		SELECT ProductID, FromParty, @GroupId, ParentChargeID, Rate, ChargeType, @EffectiveDate, ToDate, Remark, BaseCurrencyId, FirstOfBilling, BasisOfBilling
		FROM #ChangeRateTable
		WHERE [Status] = @IsActived AND ChargeID = @OldChargeId

		SET @NewChargeId = SCOPE_IDENTITY()
		-- Insert InsertedResult
			INSERT INTO @InsertedResult(ChargeId, ProductId)
			VALUES(@NewChargeId, @ProductId)

		-- Insert LA_ChargeRateByCurrency
		INSERT INTO LA_ChargeRateByCurrency(ChargeID, CurrencyID, Rate)
		SELECT @NewChargeId, CurrencyID, Rate
		FROM LA_ChargeRateByCurrency
		WHERE ChargeID = @OldChargeId

		-- Exlude item which is inserted
		UPDATE #ChangeRateTable SET IsInserted = 1 WHERE ChargeID = @OldChargeId
	END

		-- 2.2 LA_ChargeInfo_SystemMapping
	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID, SystemID)
	SELECT ChargeID, 2
	FROM @InsertedResult

	IF @GroupId = 1 -- ONEWorks
	BEGIN
		INSERT INTO LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
		SELECT ci.ChargeID, 4
		FROM @InsertedResult ci
		WHERE ci.ProductId IN (SELECT p.ProductId FROM dbo.LRF_f_Products3rd('SB,NG,VS,LC,AGC,GD,VG,BA') p)
	END

		-- 2.3 OAS_ChargeInfoSub
	INSERT INTO OAS_ChargeInfoSub (ProductID, BettypeRef, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, BaseCurrencyId, FirstOfBilling, BasisOfBilling, ChargeIdRef)
	SELECT cs.ProductID, cs.BettypeRef, cs.FromParty, @GroupId , cs.ParentChargeID, cs.Rate, cs.ChargeType, @EffectiveDate, c.ToDate, cs.BaseCurrencyId, cs.FirstOfBilling, cs.BasisOfBilling, ins.ChargeId 
	FROM [dbo].[OAS_ChargeInfoSub] cs WITH(NOLOCK)
	INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID
	INNER JOIN @InsertedResult ins ON cs.ProductID = ins.ProductId
	WHERE [Status] = @IsActived

	IF @@Error > 0
	BEGIN
		UPDATE c1
		SET c1.ToDate = c2.ToDate
		FROM OAS_ChargeInfo c1 WITH(NOLOCK) 
		INNER JOIN #ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID
		WHERE [Status] = @IsActived

		DELETE c
		FROM OAS_ChargeInfo c 
		INNER JOIN @InsertedResult ins ON c.ChargeID = ins.ChargeID

		UPDATE cs
		SET ToDate = c.ToDate
		FROM OAS_ChargeInfoSub cs WITH(NOLOCK) 
		INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID 
		WHERE [Status] = @IsActived

		DELETE cs
		FROM OAS_ChargeInfoSub cs 
		INNER JOIN @InsertedResult ins ON cs.ChargeIdRef = ins.ChargeID

		SELECT @ErrMsg = 'Fail to copy charge rates to new group: ' + ERROR_MESSAGE(), @ErrCode = 505
		RETURN
	END

	/*Step3: Special case, 
		ex: FromDate: 5
			ToDate: 10
			EffectiveDate: 5
		=> Need only to update group
	*/
		-- 3.1 OAS_ChargeInfo
	UPDATE c1
	SET ToParty = @GroupId
	FROM OAS_ChargeInfo c1 WITH(NOLOCK) 
	INNER JOIN #ChangeRateTable c2 ON c1.ChargeID = c2.ChargeID
	WHERE [Status] = @IsActivating
		-- 3.2 OAS_ChargeInfoSub
	UPDATE cs
	SET ToParty = @GroupId
	FROM OAS_ChargeInfoSub cs WITH(NOLOCK) 
	INNER JOIN #ChangeRateTable c ON cs.ChargeIdRef = c.ChargeID
	WHERE [Status] = @IsActivating

	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF (MILLISECOND, @StartRun, @EndRun)

	-- Write new log
	;WITH t AS
	(
		SELECT		op.PartyName,
					od.BrandName,
					CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END Product,
					FORMAT (oc.FromDate,'MMM dd, yyyy') FromDate,
					FORMAT (oc.ToDate,'MMM dd, yyyy') ToDate,
					FORMAT (oc.FirstOfBilling,'MMM dd, yyyy') FirstOfBilling,
					oc.BasisOfBilling,
					(CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') Rate,
					STRING_AGG(x.Code,', ') Currs,
					CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate,
					oc.ChargeID AS FakeID,
					 CASE WHEN oc.ProductID = 3 THEN 'BA Commission'
						  WHEN oc.ChargeType = 1 THEN 'Licensing Fee'
						  WHEN oc.ChargeType = 5 THEN 'BetTrade Commision for SB'   
						  WHEN oc.ChargeType = 6 THEN 'Commision Share'
						  WHEN oc.ChargeType = 7 THEN 'Cash-in Share' 
						  WHEN oc.ChargeType = 12 THEN 'Tips Amt Due' 
						  WHEN oc.ChargeType = 13 THEN 'BetTrade Commision for BA' 
						END ChargeTypeName
		FROM OAS_Party op WITH(NOLOCK)
		INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON op.PartyID = od.PartyID
		INNER JOIN Licensees l WITH(NOLOCK) ON op.OldRefID = l.LicenseeID
		INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON op.PartyID = oc.FromParty
		CROSS APPLY (
			SELECT DISTINCT lc.Currency, CASE WHEN e.ExchangeId IN (96,202) THEN e.Code + ' (' + e.currency + ')' ELSE e.Code END Code
			FROM LicenseeCust lc  WITH(NOLOCK) 
			INNER JOIN  CustDB.dbo.exchange e with(nolock) on lc.Currency = e.ExchangeId
			WHERE lc.LicenseeID = l.LicenseeID and lc.roleID = 2 and e.ExchangeId <> 20
		) x
		LEFT JOIN  LA_ChargeRateByCurrency lcr WITH(NOLOCK) ON oc.ChargeID = lcr.ChargeID AND x.Currency = lcr.CurrencyID
		LEFT JOIN  Product3rd p3 WITH(NOLOCK) ON oc.ProductID = p3.Productid
		WHERE op.PartyID = @PartyId AND oc.ChargeID IN (
			SELECT ChargeID FROM  #ChangeRateTable z WHERE z.[Status] = 1
			UNION ALL
			SELECT ChargeID FROM  @InsertedResult z1 
		)
		GROUP BY op.PartyName,
					od.BrandName,
					CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END,
					FORMAT (oc.FromDate,'MMM dd, yyyy') ,
					FORMAT (oc.ToDate,'MMM dd, yyyy') ,
					FORMAT (oc.FirstOfBilling,'MMM dd, yyyy'),
					oc.BasisOfBilling,
					CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %',
					CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END,
					oc.ChargeID,
					CASE WHEN oc.ProductID = 3 THEN 'BA Commission'
						 WHEN oc.ChargeType = 1 THEN 'Licensing Fee'
						  WHEN oc.ChargeType = 5 THEN 'BetTrade Commision for SB'   
						  WHEN oc.ChargeType = 6 THEN 'Commision Share'
						  WHEN oc.ChargeType = 7 THEN 'Cash-in Share' 
						  WHEN oc.ChargeType = 12 THEN 'Tips Amt Due' 
						  WHEN oc.ChargeType = 13 THEN 'BetTrade Commision for BA' 
					END
	) 
	, t1 AS
	(
		SELECT t.FakeID, t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName,STRING_AGG(cr.r, CHAR(13)) AS r
		FROM t
		CROSS APPLY (
				SELECT CASE WHEN t.isMasterRate = 1 AND EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'Others ' 
							WHEN t.isMasterRate = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'All ' 
							ELSE '' END + '('+ t.Currs + ') - ' + Rate AS r
		) cr
		GROUP BY t.FakeID, t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName
	) SELECT @logSPData = 
			(
			SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn', crs.crs AS 'crs'
			FROM t1 t 
			CROSS APPLY 
			(
				SELECT 
				(
					SELECT  u.FakeID ,u.Product p ,  u.FromDate fd, u.ToDate td , u.FirstOfBilling fb, u.BasisOfBilling bb , u.r, u.ChargeTypeName t
					FROM t1 u  WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName FOR JSON PATH
				) crs
			) crs  
			GROUP BY t.PartyName, t.BrandName, crs.crs
			FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
		) 

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@SPName		= 'LA_ChargeRateGroupChange'
		,@CustId		= @PartyId
		,@Duration		= @duration
		,@TrackingValue2 = @logSPData
		,@TrackingValue  = @logSPDataOld
		,@ActionID		 = @LogActionID

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Fail to write log: ' + ERROR_MESSAGE() , @ErrCode = 506
	END

	DROP TABLE #ChangeRateTable
END
GO