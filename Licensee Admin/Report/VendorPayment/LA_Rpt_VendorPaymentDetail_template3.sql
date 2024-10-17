/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template3]
	@PartyIds			VARCHAR(MAX)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@SportType			INT	= 0 
	,@BetType			INT	= 0 
	,@drawfilter		SMALLINT	= 1 
	,@BaseCurrencyName	VARCHAR(10)	= 'EUR'
	,@TimeZoneId		INT
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template3 - Template for Virtual Sports product, including some specific info such as: Sport Type, Bet Type)
 * Revisions
	- 20210615@Danny: Initialize SP [#168387]
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	- 20240301@Danny: LicensingFee And PaytoSupplier figure based on setting [RemineID: #199478]
	- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
	- 20241016@Danny: Extend parameter data length [RemineID: #212252]
 */

BEGIN
	SET NOCOUNT ON

	DECLARE @ProductCode VARCHAR(50), @CutoffDate_BaseOnSetting DATETIME = '2024-03-01'
	SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	DECLARE @IsConvertNegativeFeeToZero BIT, @IsConvertNegativePaytoSupplierToZero BIT
	SELECT @IsConvertNegativeFeeToZero = IsConvertNegativeFeeToZero, @IsConvertNegativePaytoSupplierToZero = IsConvertNegativePaytoSupplierToZero  FROM dbo.LA_VendorPaymentSetting WITH(NOLOCK) WHERE ProductId = @ProductID

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	DECLARE @ChargeInfos AS TABLE (
		ChargeID		INT
		,PartyID		INT
		,PartyName		VARCHAR(50)
		,ParentID		INT		
		,LicenseeID		INT
		,IsDeposit		INT
		,ProductID		INT
		,Rate			MONEY		
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
		)
		
	DECLARE @Charge3rdInfos AS TABLE (
		PartyID			INT	
		,IsDeposit		INT
		,ProductID		INT
		,Rate			MONEY		
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
		)	

	-- Region: Charge Info	
	INSERT INTO @ChargeInfos(ChargeID, PartyId, ProductID, LicenseeId, IsDeposit, Rate, Fromdate, Todate)
	(
		SELECT c.ChargeID, c.PartyID, c.ProductID, c.LicenseeID, c.isDeposit, c.DI_Rate, c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, @ProductCode) c 
	)	
	
	DELETE @ChargeInfos
	WHERE IsDeposit = 1 AND Rate = 0	
	
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT, IsKeepNegativeAmount BIT DEFAULT 0)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel

	UPDATE @PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0

	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM @PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId
		
	DELETE p
	FROM @PartyList p
	WHERE NOT EXISTS (SELECT 1 FROM @ChargeInfos ci WHERE ci.PartyId = p.PartyId)
			
	UPDATE ci
	SET ci.PartyName = p.PartyName,
		ci.ParentID = p.ParentId
	FROM @ChargeInfos ci
	INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	
	-- End region

	-- Region: Charge 3rd
	INSERT INTO @Charge3rdInfos ( PartyID ,IsDeposit ,ProductID ,Rate ,Fromdate ,Todate )	
	(
		SELECT c.PartyID, c.isDeposit, c.ProductID, c.DI_Rate, c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') c 
		UNION ALL
		SELECT 999, 0, @ProductID, 0.01, @FromDate, @ToDate
	)	

	-- End Region: Charge 3rd

	-- Region: Get Echange Rate
	SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
	INTO #TempExchange
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- End region: Get Exchange Rate

	-- Region: Return Result
	CREATE TABLE #Result (
		PartyId			INT,
		PartyName		VARCHAR(100),
		WinLossDate		DATETIME,
		SportType		SMALLINT,
		BetType			SMALLINT,
		BetCount		INT,
		Turnover		MONEY,
		GrossWinloss	MONEY,
		PayToSupplier	MONEY,
		OneworksIncome	MONEY,
		NetIncome		MONEY
	)

	;WITH d AS (
		SELECT b.rptDate, b.currencyID, c.PartyID, c.PartyName, l.sporttype, b.bettype
			, SUM(CASE
					WHEN @drawfilter IN (2,3) AND b.status = 111 THEN 0.0
					WHEN @drawfilter IN (2,3) AND (b.status = 114 OR b.status = 115) THEN b.Turnover * 0.5
				ELSE b.Turnover END) AS Turnover
			, SUM(-b.Winloss) AS GrossWinloss
			, SUM(-b.Winloss * c3.Rate) AS PayToSupplier
			, SUM(-b.Winloss * ISNULL(cr.Rate, c.Rate)) AS OneworksIncome
			, SUM(CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0 ELSE BetCount END) AS BetCount
		FROM bodb_licenseereport.dbo.rpt_Betting b WITH ( NOLOCK)
			INNER JOIN @ChargeInfos c ON c.LicenseeID = b.siteID AND b.rptDate BETWEEN c.Fromdate AND c.Todate
			INNER JOIN @Charge3rdInfos c3 ON c3.PartyID = c.ParentID AND b.rptDate BETWEEN c3.Fromdate AND c3.Todate
			LEFT JOIN bodb02.dbo.League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = c.ChargeId AND cr.CurrencyId = b.CurrencyId
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.status NOT IN (-1, 101, 102, 103)
			AND b.CurrencyID NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
			AND b.bettype IN (SELECT bettype FROM dbo.LA_f_BettypeProductMapping(0,@ProductCode))
			AND (	( @Sporttype = 0 AND l.sporttype IN (SELECT DISTINCT SportType FROM bodb02.dbo.SportBettypeMatrix x WITH(NOLOCK) WHERE x.ProductID = @ProductID))
					OR ( @Sporttype<>0 AND l.Sporttype = @Sporttype)
				)
			AND (@bettype = 0 OR (b.bettype = @bettype AND @bettype <> 0))
			AND b.customercategory NOT IN (27,28)
		GROUP BY b.rptDate,b.currencyID,c.PartyID,c.PartyName,l.sporttype, b.bettype
	)
	INSERT INTO #Result(PartyId, PartyName, WinLossDate, SportType, BetType, BetCount, Turnover, GrossWinloss, PayToSupplier, OneworksIncome, NetIncome)
	SELECT
		d.PartyId,
		d.PartyName,
		d.rptDate AS WinLossDate,
		d.SportType,
		d.BetType,
		SUM(d.betcount) AS BetCount,
		SUM(d.turnover * ex.Rate)		AS Turnover,
		SUM(d.GrossWinloss * ex.Rate)	AS GrossWinloss,
		SUM(d.PayToSupplier * ex.Rate)	AS PayToSupplier,
		SUM(d.OneworksIncome * ex.Rate)	AS OneworksIncome,
		SUM((d.OneworksIncome - d.PayToSupplier) * ex.Rate) AS NetIncome
	FROM d
		INNER JOIN #TempExchange ex ON d.rptDate = ex.exchangedate and d.currencyID = ex.ExchangeId		
	GROUP BY d.PartyId, d.sporttype, d.bettype, d.rptDate, d.PartyName
	
	
	Update r
	SET PayToSupplier = GrossWinloss * ci_3rd.Rate,
		NetIncome = OneworksIncome - (GrossWinloss * ci_3rd.Rate)
	FROM #Result r
		INNER JOIN @Charge3rdInfos ci_3rd ON r.PartyId = ci_3rd.PartyId

	DECLARE @TotalByParty TABLE 
	(	
		PartyId					INT,
		Total_PayToSupplier		MONEY,
		Total_OneworksIncome	MONEY,
		IsKeepNegativeAmount	BIT
	)

	INSERT INTO @TotalByParty (PartyId, Total_PayToSupplier, Total_OneworksIncome, IsKeepNegativeAmount)
	SELECT	r.PartyId, SUM(PayToSupplier), SUM(OneworksIncome), p.IsKeepNegativeAmount
	FROM	#Result r
	INNER JOIN @PartyList p ON r.PartyId = p.PartyId
	GROUP BY r.PartyId, p.IsKeepNegativeAmount



	SELECT	r.PartyName, 
			FORMAT (r.WinLossDate, 'MMMM yyyy') WinLossDate, 
			r.SportType, 
			ISNULL(sp.SportName,r.SportType) SportTypeName,
			r.BetType,
			CASE WHEN typeid BETWEEN 81 AND 120 THEN 'NG - ' + b.typenamee
			 WHEN typeid BETWEEN 1201 AND 1299 THEN 'VS - ' + b.typenamee +
				CASE WHEN b.typeid = 1204 THEN ' (Soccer)'
					 WHEN b.typeid = 1235 THEN ' (Tennis)'
					 ELSE ''
				END
			 ELSE ISNULL(b.typenamee, r.BetType)
			END BetTypeName,
			r.BetCount AS TotalTransaction, 
			r.Turnover, 
			r.GrossWinloss AS GrossWin, 
			
			CASE WHEN @FromDate < @CutoffDate_BaseOnSetting THEN CASE WHEN tp.Total_PayToSupplier < 0 THEN 0 ELSE r.PayToSupplier END
				 WHEN  @FromDate >= @CutoffDate_BaseOnSetting THEN CASE WHEN tp.Total_PayToSupplier < 0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE r.PayToSupplier END
				 END PayToSupplier, 
			CASE WHEN  @FromDate < @CutoffDate_BaseOnSetting THEN  CASE WHEN tp.Total_OneworksIncome < 0 AND tp.IsKeepNegativeAmount = 0 THEN 0 ELSE r.OneworksIncome END
			     WHEN  @FromDate >= @CutoffDate_BaseOnSetting THEN CASE WHEN tp.Total_OneworksIncome < 0 AND @IsConvertNegativeFeeToZero = 1 AND IsKeepNegativeAmount = 0 THEN 0 ELSE r.OneworksIncome END
			END AS AmountCompany, 

			CASE WHEN  @FromDate < @CutoffDate_BaseOnSetting THEN  CASE WHEN tp.Total_OneworksIncome < 0 AND tp.IsKeepNegativeAmount = 0 THEN 0 ELSE r.OneworksIncome END
			     WHEN  @FromDate >= @CutoffDate_BaseOnSetting THEN CASE WHEN tp.Total_OneworksIncome < 0 AND @IsConvertNegativeFeeToZero = 1 AND IsKeepNegativeAmount = 0 THEN 0 ELSE r.OneworksIncome END
			END
			- 
			CASE WHEN @FromDate < @CutoffDate_BaseOnSetting THEN CASE WHEN tp.Total_PayToSupplier < 0 THEN 0 ELSE r.PayToSupplier END
				 WHEN  @FromDate >= @CutoffDate_BaseOnSetting THEN CASE WHEN tp.Total_PayToSupplier < 0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE r.PayToSupplier END
			END NetIncome
	FROM #Result r
	INNER JOIN @TotalByParty tp ON r.PartyId = tp.PartyId
	LEFT JOIN bodb02.dbo.Sports sp WITH(NOLOCK) ON sp.SportType = r.SportType
	LEFT JOIN bodb02.dbo.bettype b WITH(NOLOCK) ON b.typeid = r.BetType
	ORDER BY r.PartyName, r.WinLossDate ASC,  r.sporttype, r.bettype
	-- End Region: Return Result

	DROP TABLE  #TempExchange	
	DROP TABLE  #Result	
	
END
GO