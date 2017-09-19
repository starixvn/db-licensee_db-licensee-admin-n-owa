USE bodb_licensee
GO

ALTER PROC dbo.[LA_Rpt_LicenseeAnalysis] (
	@PartyIDs		VARCHAR(1000),
	@ProductCodes	VARCHAR(1000),
	@FromDate		SMALLDATETIME,
	@ToDate			SMALLDATETIME,
	@BaseCurrency	VARCHAR(20)		= 'EUR',
	@IsSkinView		BIT				= 0
)
AS
/*
	Created: BRUCE
	Date: 20170919
	Task: Licensee Analysis (support raw data) #redmind: https://nexdev.net/issues/78294
	DB: bodb_licensee

	Revisions:
		- 20170919@Bravo: create SP

	Notes: @FromDate, @ToDate should be a full month range
*/
BEGIN
	SET NOCOUNT ON
	
	-- remove un-support products
	DECLARE @Products AS TABLE (ProductId INT,ProductCode VARCHAR(10))

	INSERT INTO @Products(ProductCode,ProductId)
	SELECT DISTINCT p2.ProductPrefix,p2.ProductID
	FROM dbo.strSplit(@ProductCodes,',') p1
	INNER JOIN dbo.LA_f_Products3rd('') p2 ON p1.val=p2.ProductPrefix
	WHERE p2.ProductID NOT IN (1,3,7,9,13,14,15,16,17,19,25)

	SET @ProductCodes = STUFF((SELECT ',' + ProductCode FROM @Products FOR XML PATH('')),1,1,'')	

	-- 1. Party groups
	-- select all parties in the same group
	DECLARE @PartyIdTable TABLE (PartyId INT, IsSelected BIT)
	INSERT INTO @PartyIdTable SELECT DISTINCT val, 1 FROM dbo.strSplit(@PartyIDs, ',')

	DECLARE @PartyGroup AS TABLE (PartyGroupId INT, PartyId INT)
	INSERT	INTO @PartyGroup(PartyGroupId, PartyId)
	(
		SELECT	PartyGroupId, PartyId
		FROM	bodb_licensee.dbo.LA_PartyGroupAssignment WITH(NOLOCK)
		WHERE	PartyGroupId IN (	SELECT	p1.PartyGroupId
									FROM	bodb_licensee.dbo.LA_PartyGroupAssignment p1 WITH(NOLOCK)
									WHERE	p1.PartyId IN (SELECT p2.PartyId FROM @PartyIdTable p2))
			AND @IsSkinView = 0
	)

	INSERT INTO @PartyIdTable
	SELECT DISTINCT PartyId, 0 FROM @PartyGroup WHERE PartyId NOT IN (SELECT p2.PartyId FROM @PartyIdTable p2)

	SET @PartyIds = STUFF((SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM @PartyIdTable FOR XML PATH('')),1,1,'')
	-- End region

	-- 2. Region: Party charge info
	DECLARE @PartyChargeInfo AS TABLE(
		PartyId		INT,
		LicenseeId	INT,
		ProductID	INT,
		Rate		DECIMAL(9,8),
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME
	)
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate
		FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
		WHERE	DI_Rate > 0
	)
	-- End region
	
	-- 3. Region: Get exchange rate info
	CREATE	TABLE #Exchange (ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate DECIMAL(9,8))
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
	-- End region

	-- 4. Region: Minfee configs
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

	DECLARE @MinFeeGroup TABLE(
		FeeType			TINYINT,
		PartyId			INT,
		ProductId		INT,
		CurrencyId		INT,
		FeeAmount		MONEY,
		FromDate		DATETIME,
		ToDate			DATETIME,
		MinFeeProrate	MONEY,
		WaivedAmount	MONEY,
		TotalAmount		MONEY,
		MinFeeAmount	MONEY,
		AmountToCompany	MONEY,
		DaysOutOfWaiveTime  INT
	)

	INSERT INTO @MinFeeGroup(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
	(
		SELECT mf.FeeTypeId, mf.PartyId, mf.ProductId, mf.CurrencyId, mf.FeeAmount,
			CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
			CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate
		FROM dbo.LA_MinFee mf WITH(NOLOCK)
		WHERE @IsSkinView = 0 AND (mf.FeeTypeId = 1
			OR (mf.FeeTypeId = 2 AND EXISTS (
				SELECT PartyId FROM dbo.LA_MinFee m WITH(NOLOCK)
				WHERE m.FeeTypeId = 1
					AND m.PartyId = mf.PartyId
					AND m.ProductId = mf.ProductId
					AND ((m.FromDate BETWEEN @FirstDate AND @LastDate)
						OR (m.ToDate BETWEEN @FirstDate AND @LastDate)
						OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
					)
			))
			AND mf.ProductId IN (SELECT ProductId FROM @Products)
			AND mf.PartyId IN (SELECT p.PartyId FROM @PartyIdTable p)
			AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
				OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
				OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
			))
	)

	DELETE @MinFeeGroup WHERE ToDate < FromDate
	UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
	INNER JOIN #Exchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID
	-- End region

	-- 5. get licensee/customer and currency info
	-- Licensee customer info
	CREATE TABLE #LicenseeCustInfo(PartyId INT,LicenseeId INT, CustId INT, CurrencyId INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)

	-- KeenOcean has different currency
	DECLARE @KeenOceanID INT = (SELECT LicenseeID FROM dbo.Licensees WITH (NOLOCK) WHERE LicenseeName LIKE 'KeenOcean')
	DECLARE @RMB INT = (SELECT ExchangeID FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE currency = 'RMB')
	DECLARE @YUN INT = (SELECT ExchangeID FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE currency = 'YUN')

	;WITH Cust AS (
		SELECT c.LicenseeID, c.CustID, c.Currency, p.Fromdate, p.Todate,p.PartyId
		FROM dbo.LicenseeCust c WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON p.LicenseeId=c.LicenseeID
		WHERE c.Currency <> 20
		UNION ALL
		SELECT c.LicenseeID, c.CustID, @RMB Currency, p.Fromdate, p.Todate,p.PartyId
		FROM dbo.LicenseeCust c WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON p.LicenseeId=c.LicenseeID
		WHERE p.LicenseeID = @KeenOceanID AND Currency = @YUN
	)
	INSERT INTO #LicenseeCustInfo (LicenseeId, CustId, CurrencyId, Fromdate, Todate,PartyId)
	SELECT DISTINCT LicenseeId, CustId, Currency, Fromdate, Todate,PartyId
	FROM Cust

	CREATE CLUSTERED INDEX ix_LicenseeCustInfo_cl ON #LicenseeCustInfo(CustId, CurrencyId)
	-- end region

	-- 6. get move bet info
	DECLARE @BalanceUpDay TABLE (BalanceUpDay DATETIME, MoveBetsDay DATETIME)
	INSERT INTO @BalanceUpDay EXEC bodb02.dbo.Lrf_SelBalanceUpDay	
	DECLARE @MoveBetsDay DATETIME = (SELECT TOP 1 MoveBetsDay FROM @BalanceUpDay)
	-- end region

	-- 7. if data from moveBetsDay: get data from bettrans else get data from rptWinLoss2
	CREATE TABLE #Data (
		PartyId				INT,
		ReportDate			DATETIME,
		CurrencyId			INT,
		BetFrom				NVARCHAR(1),
		Turnover			MONEY,
		LicenseeWinLoss		MONEY,
		LicensingFee		MONEY,
		FeeAfterDiscount	MONEY,
		FeeAfterRebate		MONEY,
		ProductId			INT,
		IsApplyMinFee		BIT
	)
 
	 -- 7.1. get data from bettrans
	IF @ToDate > @MoveBetsDay
	BEGIN
		DECLARE @TempFromDate SMALLDATETIME = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY,1,@MoveBetsDay) ELSE @FromDate END
		INSERT INTO #Data(ReportDate, CurrencyId, BetFrom, Turnover, LicenseeWinLoss, ProductId, PartyId)
		(
			SELECT
				b.winlostdate,
				l.CurrencyId,
				CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END,
				SUM(b.stake * e.Rate),
				SUM(-(b.winlost - b.actual_stake) * e.Rate),
				p.ProductID,
				l.PartyId
			FROM bodb02.dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #LicenseeCustInfo l ON l.CustId=b.recommend AND b.currency=l.CurrencyId AND b.winlostdate BETWEEN l.Fromdate AND l.Todate
				INNER JOIN dbo.LA_f_BettypeProductMapping(0,@ProductCodes) bt ON bt.Bettype=b.bettype
				INNER JOIN @Products p ON p.ProductID = bt.ProductID
				INNER JOIN #Exchange e ON l.CurrencyId = e.ExchangeID AND b.winlostdate = e.ExchangeDate
			WHERE b.statusID IN (111, 112, 113) 
				AND b.winlostdate BETWEEN @TempFromDate AND @ToDate
				AND NOT EXISTS (SELECT 1 FROM dbo.LicenseeBATransaction ba WITH(NOLOCK) WHERE b.transid = ba.transid)
				AND b.bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY b.winlostdate, l.CurrencyId, CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END, p.ProductID,l.PartyId
		)
	END
	
	-- 7.2. get data from rptWinLoss2
	-- notes: ps.ProductId <> p.ProductId
	IF @FromDate <= @MoveBetsDay
	BEGIN
		DECLARE @TempToDate SMALLDATETIME = CASE WHEN @ToDate >= @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END
		INSERT INTO #Data(ReportDate, CurrencyId, BetFrom, Turnover, LicenseeWinLoss, ProductID,PartyId)
		(
			SELECT
				b.winlostdate,
				l.CurrencyId,
				CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END,
				SUM(b.turnover * e.Rate),
				SUM(-b.winlost * e.Rate),
				p.ProductID,
				l.PartyId
			FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH ( NOLOCK )
			INNER JOIN #LicenseeCustInfo l ON b.CustId = l.CustId AND b.Currency = l.CurrencyId AND b.winlostdate BETWEEN l.Fromdate AND l.Todate
			INNER JOIN bodb02.dbo.f_LicWinLoss_ProductSportType_Sel(@ProductCodes) ps ON ps.SportType = b.sporttype
			INNER JOIN #Exchange e ON l.CurrencyId = e.ExchangeID AND b.winlostdate = e.ExchangeDate
			INNER JOIN @Products p ON p.ProductCode=ps.ProductCode
			WHERE b.Winlostdate BETWEEN @FromDate AND @TempToDate
				AND b.roleid = 2 -- Sum on agent for better performance
				AND b.statusID NOT IN (-1, 101, 102, 103)
				AND b.bettype NOT IN (901,902,903,904,911,912,913,914)
				AND ISNULL(b.isBA,0) = 0
			GROUP BY b.winlostdate, l.CurrencyId, CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END,l.PartyId,p.ProductID
		)
	END
	-- end region
	
	-- 10. calculate licensing fee(amount to company)
	UPDATE d SET LicensingFee = (d.LicenseeWinLoss * p.Rate), FeeAfterDiscount=0,FeeAfterRebate=0
	FROM #Data d
	INNER JOIN @PartyChargeInfo p ON p.PartyId = d.PartyId AND p.ProductId=d.ProductId AND d.ReportDate BETWEEN p.FromDate AND p.ToDate
	-- end region

	-- 11. calculate min fee
	UPDATE t SET t.IsApplyMinFee = 0
	FROM #Data t
	INNER JOIN @MinFeeGroup m ON t.ProductId = m.ProductId
		AND (t.PartyId = m.PartyId )
		AND (t.ReportDate BETWEEN m.FromDate AND m.ToDate)
	WHERE m.FeeType=2

	-- 11.1 calculate minfee amount under waive time
	UPDATE amf
	SET MinFeeProrate = (DATEDIFF(DAY, FromDate, ToDate) + 1) * ((
			SELECT TOP 1 mfg.FeeAmount
			FROM @MinFeeGroup mfg
			WHERE mfg.FeeType = 1 AND mfg.PartyId = amf.PartyId AND mfg.ProductId = amf.ProductId
		) / @DaysInMonth)
	FROM @MinFeeGroup amf
	WHERE FeeType = 2

	-- 11.2 calculate amount to company under waived time
	UPDATE amf SET amf.WaivedAmount = ISNULL((
			SELECT SUM(td.LicensingFee)
			FROM #Data td 
			WHERE	amf.PartyId = td.PartyId AND
					amf.ProductId = td.ProductId AND
					td.ReportDate BETWEEN amf.FromDate AND amf.ToDate
		), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 2

	-- 11.3 calculate min fee prorate (min fee amount in month - minfee amount under waive time
	UPDATE amf SET
		amf.MinFeeProrate = ROUND((amf.FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1) -
								ISNULL((SELECT	SUM(f.MinFeeProrate)
										FROM	@MinFeeGroup f
										WHERE	f.FeeType = 2
												AND amf.PartyId = f.PartyId
												AND amf.ProductId = f.ProductId), 0)
							, 2),
		amf.WaivedAmount =  ISNULL((SELECT	SUM(f.WaivedAmount)
									FROM	@MinFeeGroup f
									WHERE	f.FeeType = 2 AND amf.PartyId = f.PartyId AND amf.ProductId = f.ProductId), 0),
		amf.MinFeeAmount =  ISNULL((SELECT	SUM(td.LicensingFee)
									FROM	#Data td
									WHERE	amf.PartyId = td.PartyId
											AND td.ReportDate BETWEEN amf.FromDate AND amf.ToDate
											AND td.IsApplyMinFee IS NULL
											AND amf.ProductId = td.ProductId), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1

	-- 11.4 calculate total amount to company = amount under waive time + amount out of waive range
	UPDATE	amf
	SET		amf.TotalAmount =  amf.MinFeeAmount + amf.WaivedAmount
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1
	
	-- 11.5 calculate total minfee by group
	DECLARE @TotalMinFees TABLE(
		PartyGroupId				INT,
		ProductId					INT,
		TotalMinFee					MONEY,
		TotalAmountUnderMinfeeTime	MONEY
	)
	INSERT	INTO @TotalMinFees(PartyGroupId,ProductId, TotalMinFee, TotalAmountUnderMinfeeTime)
	SELECT	pg.PartyGroupId,mf.ProductId,
			SUM(mf.MinFeeProrate),-- actual min fee in given time range
			SUM(CASE WHEN mf.MinFeeAmount < 0 THEN 0 ELSE mf.MinFeeAmount END) -- total amount to company under minfee time(exclude waive range)
	FROM @MinFeeGroup mf
	INNER JOIN @PartyGroup pg ON mf.PartyId = pg.PartyId
	WHERE	mf.FeeType = 1
	GROUP BY pg.PartyGroupId,mf.ProductId

	-- 11.6 update minfee group
	UPDATE amf
	SET amf.AmountToCompany = CASE
			WHEN t.TotalAmountUnderMinfeeTime < t.TotalMinFee AND amf.MinFeeAmount < amf.MinFeeProrate 
				THEN amf.MinFeeProrate + amf.WaivedAmount
			ELSE amf.TotalAmount
		END
	FROM @MinFeeGroup amf
	INNER JOIN @PartyGroup pg ON pg.PartyId = amf.PartyId
	INNER JOIN @TotalMinFees t ON amf.ProductId = t.ProductId AND t.PartyGroupId = pg.PartyGroupId
	WHERE amf.FeeType = 1

	-- 11.7 update minfee non-group
	UPDATE	amf
	SET		amf.AmountToCompany =	CASE WHEN amf.MinFeeAmount < amf.MinFeeProrate
											THEN amf.MinFeeProrate + amf.WaivedAmount
										ELSE amf.TotalAmount
									END
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1 AND amf.AmountToCompany IS NULL
	-- end region

	-- 12. Get discount group info
	DECLARE @DiscountGroupHeader AS TABLE (
		DiscountGroupId		INT,
		DiscountGroupType	TINYINT,
		PartyId				INT,
		CurrencyId			INT,
		FromDate			DATETIME,
		ToDate				DATETIME
	)

	INSERT INTO @DiscountGroupHeader(DiscountGroupId,DiscountGroupType,PartyId,CurrencyId,FromDate,ToDate)
	(
		SELECT dg.DiscountGroupId,dg.DiscountGroupType,dga.PartyId, dg.CurrencyId, dg.FromDate, dg.ToDate
		FROM dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupAssignment dga WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		WHERE @FromDate<= ToDate AND FromDate<=@ToDate
	)
	
	DELETE FROM @DiscountGroupHeader
	WHERE ToDate < (SELECT MAX(ToDate) FROM @DiscountGroupHeader WHERE DiscountGroupType = 1) AND DiscountGroupType = 1

	DELETE FROM @DiscountGroupHeader 
	WHERE ToDate < (SELECT MAX(ToDate) FROM @DiscountGroupHeader WHERE DiscountGroupType = 2) AND DiscountGroupType = 2
	
	DECLARE @DiscountGroup AS TABLE(
		DiscountGroupId		SMALLINT,
		DiscountGroupType	TINYINT,
		FromAmount			MONEY,
		ToAmount			MONEY,
		Rate				MONEY,
		PartyId				INT,
		ProductId			TINYINT,
		BaseCurrency		INT
	)

	INSERT INTO @DiscountGroup (DiscountGroupId, DiscountGroupType, FromAmount, ToAmount, Rate, PartyId, ProductId , BaseCurrency)	
	(
		SELECT dg.DiscountGroupId,
			dg.DiscountGroupType,
			dgd.FromAmount,
			dgd.ToAmount,
			dgd.Rate,
			dg.PartyID,
			dgp.ProductId,
			dg.CurrencyId
		FROM @DiscountGroupHeader dg 
			INNER JOIN dbo.LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dg.DiscountGroupId = dgd.DiscountGroupId
			INNER JOIN dbo.LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dg.DiscountGroupId = dgp.DiscountGroupId
		WHERE dgp.ProductId IN (SELECT DISTINCT ProductId FROM @Products)
	)

	UPDATE d SET
		d.FromAmount = d.FromAmount * e.Rate,
		d.ToAmount = d.ToAmount * e.Rate
	FROM @DiscountGroup d
	INNER JOIN #Exchange e ON e.ExchangeDate = @ToDate AND d.BaseCurrency = e.ExchangeID AND d.DiscountGroupType = 1
	-- End Region

	-- 13. sum by licensee
	;WITH a AS (
		SELECT d.PartyId, d.ProductId,
			SUM(d.Turnover)			Turnover,
			SUM(d.LicenseeWinLoss)	LicenseeWinLoss,
			SUM(d.LicensingFee)		LicensingFee,
			CAST(0 AS MONEY)		Discount,
			CAST(0 AS MONEY)		Rebate
		FROM #Data d
		INNER JOIN @PartyIdTable p ON d.PartyId=p.PartyId
		WHERE p.IsSelected = 1
		GROUP BY d.PartyId, d.ProductId
	)
	SELECT a.LicenseeWinLoss,a.PartyId,a.ProductId,a.Turnover,a.Discount,a.Rebate,
		CASE WHEN ISNULL(amf.AmountToCompany, a.LicensingFee) < 0 THEN CAST(0 AS MONEY)
		ELSE ISNULL(amf.AmountToCompany, a.LicensingFee) END AS LicensingFee
	INTO #SumByLicensee FROM a
	LEFT JOIN @MinFeeGroup amf ON amf.PartyId=a.PartyId AND amf.FeeType=1 AND amf.ProductId=a.ProductId
	
	-- insert data for party-product which has min fee but doesn't has bet ticket
	INSERT INTO #SumByLicensee(PartyId, ProductId, LicensingFee,LicenseeWinLoss,Turnover,Discount,Rebate)
	SELECT m.PartyId, m.ProductId, m.AmountToCompany, 0, 0, 0, 0
	FROM @MinFeeGroup m
	LEFT JOIN #SumByLicensee s ON m.PartyId = s.PartyId AND m.ProductId = s.ProductId
	WHERE m.FeeType = 1 AND s.PartyId IS NULL
	-- end region

	-- 14. Apply Discount/rebate
	;WITH t AS(
		SELECT SUM(s.LicensingFee) Total, s.PartyId, d.DiscountGroupId
		FROM #SumByLicensee s
		INNER JOIN (SELECT DISTINCT DiscountGroupId,PartyId,ProductId FROM @DiscountGroup WHERE DiscountGroupType = 1) AS d
			ON s.PartyId=d.PartyId AND s.ProductId=d.ProductId
		GROUP BY s.PartyId, d.DiscountGroupId
	)
	DELETE d
	FROM @DiscountGroup d
	INNER JOIN t ON t.DiscountGroupId = d.DiscountGroupId AND t.PartyId = d.PartyId
	WHERE d.DiscountGroupType = 1 AND t.Total NOT BETWEEN d.FromAmount AND d.ToAmount
	
	-- discount
	UPDATE s SET Discount =	(CASE WHEN -s.LicenseeWinLoss < 0 THEN 0 ELSE -s.LicenseeWinLoss * ISNULL(d3.Rate, 0) END) + 
							(CASE WHEN s.LicensingFee < 0 THEN 0 ELSE s.LicensingFee * ISNULL(d1.Rate, 0) END)
	FROM #SumByLicensee s
		LEFT JOIN @DiscountGroup d1 ON s.PartyId = d1.PartyId AND d1.ProductId = s.ProductId AND d1.DiscountGroupType = 1 -- discount by fee
		LEFT JOIN @DiscountGroup d3 ON s.PartyId = d3.PartyId AND d3.ProductId = s.ProductId AND d3.DiscountGroupType = 3 -- discount by winloss

	-- rebate
	UPDATE s SET Rebate = CASE WHEN (s.LicensingFee - s.Discount) < 0 THEN 0 ELSE (s.LicensingFee - s.Discount) * ISNULL(r.Rate, 0) END			
	FROM #SumByLicensee s
	LEFT JOIN @DiscountGroup r ON s.PartyId = r.PartyId AND r.ProductId = s.ProductId AND r.DiscountGroupType = 2 -- rebate = 2
	-- End Region	

	-- 15. licensee group
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentID INT)
	INSERT INTO @PartyList
	EXEC dbo.LA_PartyListSel
	-- end region

	IF @IsSkinView = 0
	BEGIN
		SELECT CASE WHEN p.ParentID = 1 THEN 'OW' ELSE 'Boping' END AS GroupName
			,p.PartyName AS [Name]
			,s.LicenseeWinLoss
			,s.Turnover
			,s.LicensingFee
			,s.Discount
			,s.Rebate
			,@FirstDate AS [Date]
			,pp.ProductCode
		FROM #SumByLicensee s
		INNER JOIN @PartyList p ON p.PartyId=s.PartyId
		INNER JOIN @Products pp ON s.ProductId=pp.ProductID
		WHERE p.ParentID IN (1,11,98)
	END
	ELSE
	BEGIN
		-- group by skin
		-- exclude minfee
		-- discount of each skin = total discount * (licensing fee/ total licensing fee)
		SELECT p.ParentID,d.BetFrom, d.ProductId,
			SUM(d.Turnover)			Turnover,
			SUM(d.LicenseeWinLoss)	LicenseeWinLoss,
			SUM(d.LicensingFee)		LicensingFee,
			CAST(0 AS MONEY)		Discount,
			CAST(0 AS MONEY)		Rebate
		INTO #SumBySkin
		FROM #Data d
		INNER JOIN @PartyList p ON p.PartyId=d.PartyId
		INNER JOIN @PartyIdTable pt ON pt.PartyId=p.PartyId
		WHERE p.ParentID IN (1,11,98) AND pt.IsSelected = 1
		GROUP BY p.ParentID,d.BetFrom, d.ProductId

		-- total discount by product
		;WITH t AS (
			SELECT p.ParentID,s.ProductId
				,SUM(s.LicensingFee)	AS TotalFee
				,SUM(s.Discount)		AS TotalDiscount
				,SUM(s.Rebate)			AS TotalRebate
			FROM #SumByLicensee s
			INNER JOIN @PartyList p ON p.PartyId=s.PartyId
			WHERE p.ParentID IN (1,11,98)
			GROUP BY p.ParentID,s.ProductId
		)
		UPDATE s SET 
			s.Discount = t.TotalDiscount * (s.LicensingFee / t.TotalFee),
			s.Rebate = t.TotalRebate * (s.LicensingFee / t.TotalFee)
		FROM #SumBySkin s
		INNER JOIN t ON t.ParentID=s.ParentID AND t.ProductId=s.ProductId

		SELECT CASE WHEN s.ParentID = 1 THEN 'OW' ELSE 'Boping' END AS GroupName
			,CASE	WHEN s.BetFrom = 'd' THEN 'Asia'
					WHEN s.BetFrom = 'a' THEN 'China'
					WHEN s.BetFrom = 'm' THEN 'WAP'
					WHEN s.BetFrom = 'e' OR s.BetFrom = 'u' THEN 'Euro'
					WHEN s.BetFrom = 's' OR s.BetFrom = 'l' THEN 'Smart'
				ELSE 'Other' END AS [Name]
			,s.LicenseeWinLoss
			,s.Turnover
			,s.LicensingFee
			,s.Discount
			,s.Rebate
			,@FirstDate AS [Date]
			,pp.ProductCode
		FROM #SumBySkin s
		INNER JOIN @Products pp ON s.ProductId=pp.ProductID

		DROP TABLE #SumBySkin
	END	

	DROP TABLE #Exchange
	DROP TABLE #LicenseeCustInfo
	DROP TABLE #Data
	DROP TABLE #SumByLicensee
END
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_LicenseeAnalysis] TO [bodbLicenseeNet] AS [dbo]
GRANT EXECUTE ON [dbo].[LA_Rpt_LicenseeAnalysis] TO [bodbAdminNet] AS [dbo]
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicenseeAnalysis] TO [vnteam] AS [dbo]