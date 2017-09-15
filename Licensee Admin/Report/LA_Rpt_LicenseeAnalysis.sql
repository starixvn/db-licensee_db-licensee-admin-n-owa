USE bodb_licensee
go

declare
	@PartyIDs		VARCHAR(1000)='14,19,20,22,23,24,26,27,33,39,40,42,43,44,45,46,47,48,49,54,55,56,87,89,92,93,100,101,120,15,29,31,34,35,36,37,38,41,53,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,88,90,91,95,97,125,224,16,17,52,99',
	@ProductCodes	VARCHAR(1000)='SB,BA,AB',
	@FromDate		SMALLDATETIME='20160101',
	@ToDate			SMALLDATETIME='20160131',
	@BaseCurrency	VARCHAR(20) = 'EUR'

BEGIN
	SET NOCOUNT ON
	
	-- remove un-support products
	SET @ProductCodes = STUFF((
		SELECT ',' + ProductPrefix
		FROM dbo.strSplit(@ProductCodes,',') p1
		INNER JOIN dbo.LA_f_Products3rd('') p2 ON p1.val=p2.ProductPrefix
		WHERE p2.ProductID NOT IN (1,3,7,9,13,14,15,16,17,19,25)
		FOR XML PATH('')
	),1,1,'')	

	-- 1. Party groups
	-- select all parties in the same group
	DECLARE @PartyIdTable TABLE (PartyId INT, IsSelected BIT)
	INSERT INTO @PartyIdTable SELECT val, 1 FROM dbo.strSplit(@PartyIDs, ',')

	DECLARE @PartyGroup AS TABLE (PartyGroupId INT, PartyId INT)
	INSERT	INTO @PartyGroup(PartyGroupId, PartyId)
	(
		SELECT	PartyGroupId, PartyId
		FROM	bodb_licensee.dbo.LA_PartyGroupAssignment WITH(NOLOCK)
		WHERE	PartyGroupId IN (	SELECT	p1.PartyGroupId
									FROM	bodb_licensee.dbo.LA_PartyGroupAssignment p1 WITH(NOLOCK)
									WHERE	p1.PartyId IN (SELECT p2.PartyId FROM @PartyIdTable p2))
	)

	INSERT INTO @PartyIdTable
	SELECT PartyId, 0 FROM @PartyGroup WHERE PartyId NOT IN (SELECT p2.PartyId FROM @PartyIdTable p2)

	SET @PartyIds = STUFF((SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM @PartyIdTable FOR XML PATH('')),1,1,'')
	-- End region

	-- 2. Region: Party charge info
	DECLARE @PartyChargeInfo AS TABLE(
		PartyName	VARCHAR(100),
		GroupName	VARCHAR(100),
		PartyId		INT,
		LicenseeId	INT,
		ProductID	INT,
		Rate		DECIMAL(9,8),
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME,
		ProductCode	VARCHAR(10)
	)
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate,ProductCode)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate,p.ProductPrefix
		FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
		INNER JOIN dbo.LA_f_Products3rd('') p ON p.ProductID=ci.ProductID
		WHERE	DI_Rate > 0
	)

	DECLARE @PartyList AS TABLE (PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentID INT)
	INSERT INTO @PartyList
	EXEC dbo.LA_PartyListSel

	UPDATE p SET
		PartyName = pl.PartyName,
		GroupName = CASE WHEN pl.ParentID = 1 THEN 'OW' ELSE 'Boping' END
	FROM @PartyChargeInfo p
	INNER JOIN @PartyList pl ON p.PartyId = pl.PartyId
	WHERE pl.ParentID IN (1,11,98)
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
		WHERE mf.FeeTypeId = 1
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
			AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
			AND mf.PartyId IN (SELECT p.PartyId FROM @PartyIdTable p)
			AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
				OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
				OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
			)
	)

	UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
	INNER JOIN #Exchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID
	-- End region

	-- 5. get licensee/customer and currency info
	--
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
	--
	DECLARE @BalanceUpDay TABLE (BalanceUpDay DATETIME, MoveBetsDay DATETIME)
	INSERT INTO @BalanceUpDay EXEC bodb02.dbo.Lrf_SelBalanceUpDay
	
	DECLARE @MoveBetsDay DATETIME = (SELECT TOP 1 MoveBetsDay FROM @BalanceUpDay)
	-- end region

	-- 7. if data from moveBetsDay: get data from bettrans
	-- else get data from rptWinLoss2
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
		INSERT INTO #Data(ReportDate, CurrencyId, BetFrom, Turnover, LicenseeWinLoss, ProductId,PartyId)
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
				INNER JOIN dbo.LA_f_Products3rd('') p ON p.ProductID = bt.ProductID
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
			INNER JOIN dbo.LA_f_Products3rd('') p ON p.ProductPrefix=ps.ProductCode
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
	UPDATE d SET LicensingFee = SUM(d.LicenseeWinLoss * p.Rate), FeeAfterDiscount=0,FeeAfterRebate=0
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

	DROP TABLE #Exchange
	DROP TABLE #LicenseeCustInfo
	DROP TABLE #Data
END

