USE bodb_licensee
go

declare
	@PartyIDs		VARCHAR(1000)='14,19,20,22,23,24,26,27,33,39,40,42,43,44,45,46,47,48,49,54,55,56,87,89,92,93,100,101,120,15,29,31,34,35,36,37,38,41,53,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,88,90,91,95,97,125,224,16,17,52,99',
	@ProductCodes	VARCHAR(1000)='SB,BA,AB',
	@FromDate		SMALLDATETIME='20170101',
	@ToDate			SMALLDATETIME='20170131',
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

	DECLARE @PartyIdTable TABLE (PartyId INT, IsSelected BIT)
	INSERT INTO @PartyIdTable SELECT val, 1 FROM dbo.strSplit(@PartyIDs, ',')

	-- 1. Party groups
	-- select all parties in the same group
	;WITH p AS (
		SELECT DISTINCT a.PartyGroupId
		FROM dbo.LA_PartyGroupAssignment a WITH(NOLOCK)
		INNER JOIN @PartyIdTable p ON a.PartyId = p.PartyId
	)
	INSERT INTO @PartyIdTable
	SELECT c.PartyId, 0
	FROM dbo.LA_PartyGroupAssignment c WITH(NOLOCK)
	INNER JOIN p ON p.PartyGroupId = c.PartyGroupId AND c.PartyId NOT IN (SELECT pt.PartyId FROM @PartyIdTable pt)
	-- End region

	-- 2. Region: Party charge info
	DECLARE @NewPartyIds VARCHAR(2000) = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM @PartyIdTable FOR XML PATH(''))
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
		FROM dbo.LA_f_ChargeInfo(@NewPartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
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
	CREATE TABLE #LicenseeCustInfo(LicenseeId INT, CustId INT, CurrencyId INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)

	-- KeenOcean has different currency
	DECLARE @KeenOceanID INT = (SELECT LicenseeID FROM dbo.Licensees WITH (NOLOCK) WHERE LicenseeName LIKE 'KeenOcean')
	DECLARE @RMB INT = (SELECT ExchangeID FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE currency = 'RMB')
	DECLARE @YUN INT = (SELECT ExchangeID FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE currency = 'YUN')

	;WITH Cust AS (
		SELECT c.LicenseeID, c.CustID, c.Currency, p.Fromdate, p.Todate
		FROM dbo.LicenseeCust c WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON p.LicenseeId=c.LicenseeID
		WHERE c.Currency <> 20
		UNION ALL
		SELECT c.LicenseeID, c.CustID, @RMB Currency, p.Fromdate, p.Todate
		FROM dbo.LicenseeCust c WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON p.LicenseeId=c.LicenseeID
		WHERE p.LicenseeID = @KeenOceanID AND Currency = @YUN
	)
	INSERT INTO #LicenseeCustInfo (LicenseeId, CustId, CurrencyId, Fromdate, Todate)
	SELECT DISTINCT LicenseeId, CustId, Currency, Fromdate, Todate
	FROM Cust

	CREATE CLUSTERED INDEX ix_LicenseeCustInfo_cl ON #LicenseeCustInfo(CustId, CurrencyId)

	-- 6. get move bet info
	--
	DECLARE @BalanceUpDay TABLE (BalanceUpDay DATETIME, MoveBetsDay DATETIME)
	INSERT INTO @BalanceUpDay EXEC bodb02.dbo.Lrf_SelBalanceUpDay
	
	DECLARE @MoveBetsDay DATETIME = (SELECT TOP 1 MoveBetsDay FROM @BalanceUpDay)

	-- 7. if data from moveBetsDay: get data from bettrans
	-- else get data from rptWinLoss2
	CREATE TABLE #Data (LicenseeId INT, ReportDate DATETIME, CurrencyId INT, BetFrom NVARCHAR(1), Turnover MONEY, LicenseeWinLoss MONEY, ProductCode VARCHAR(10))
 
	 -- 8. get data from bettrans
	IF @ToDate > @MoveBetsDay
	BEGIN
		DECLARE @TempFromDate SMALLDATETIME = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY,1,@MoveBetsDay) ELSE @FromDate END
		INSERT INTO #Data(ReportDate, CurrencyId, BetFrom, Turnover, LicenseeWinLoss, ProductCode,LicenseeId)
		(
			SELECT
				b.winlostdate,
				l.CurrencyId,
				CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END,
				SUM(b.stake),
				SUM(-(b.winlost - b.actual_stake)),
				p.ProductPrefix,
				l.LicenseeId
			FROM bodb02.dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #LicenseeCustInfo l ON l.CustId=b.recommend AND b.currency=l.CurrencyId AND b.winlostdate BETWEEN l.Fromdate AND l.Todate
				INNER JOIN dbo.LA_f_BettypeProductMapping(0,@ProductCodes) bt ON bt.Bettype=b.bettype
				INNER JOIN dbo.LA_f_Products3rd('') p ON p.ProductID = bt.ProductID
			WHERE b.statusID IN (111, 112, 113) 
				AND b.winlostdate BETWEEN @TempFromDate AND @ToDate
				AND NOT EXISTS (SELECT 1 FROM dbo.LicenseeBATransaction ba WITH(NOLOCK) WHERE b.transid = ba.transid)
				AND b.bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY b.winlostdate, l.CurrencyId, CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END, p.ProductPrefix,l.LicenseeId
		)
	END
	
	-- get data from rptWinLoss2
	IF @FromDate <= @MoveBetsDay
	BEGIN
		DECLARE @TempToDate SMALLDATETIME = CASE WHEN @ToDate >= @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END
		INSERT INTO #Data(ReportDate, CurrencyId, BetFrom, Turnover, LicenseeWinLoss, ProductCode,LicenseeId)
		(
			SELECT
				b.winlostdate,
				l.CurrencyId,
				CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END,
				SUM(b.turnover),
				SUM(-b.winlost),
				ps.ProductCode,
				l.LicenseeId
			FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH ( NOLOCK )
			INNER JOIN #LicenseeCustInfo l ON b.CustId = l.CustId AND b.Currency = l.CurrencyId AND b.winlostdate BETWEEN l.Fromdate AND l.Todate
			INNER JOIN bodb02.dbo.f_LicWinLoss_ProductSportType_Sel(@ProductCodes) ps ON ps.SportType = b.sporttype
			WHERE b.Winlostdate BETWEEN @FromDate AND @TempToDate
				AND b.roleid = 2 -- Sum on agent for better performance
				AND b.statusID NOT IN (-1, 101, 102, 103)
				AND b.bettype NOT IN (901,902,903,904,911,912,913,914)
				AND ISNULL(b.isBA,0) = 0
			GROUP BY b.winlostdate, l.CurrencyId, CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END,l.LicenseeId
		)
	END

	SELECT p.GroupName, p.PartyName, d.ProductCode,d.BetFrom
		, SUM(d.Turnover * e.Rate) Turnover
		, SUM(d.LicenseeWinLoss * e.Rate) LicenseeWinLoss
		, SUM(d.LicenseeWinLoss * p.Rate * e.Rate) LicensingFee
		, CAST(0 AS MONEY) FeeAfterDiscount
		, CAST(0 AS MONEY) FeeAfterRebate
	INTO #Result
	FROM #Data d
	INNER JOIN #Exchange e ON d.CurrencyId = e.ExchangeID AND d.ReportDate = e.ExchangeDate
	INNER JOIN @PartyChargeInfo p ON p.LicenseeId = d.LicenseeId AND p.ProductCode=d.ProductCode AND d.ReportDate BETWEEN p.FromDate AND p.ToDate
	GROUP BY p.GroupName, p.PartyName, d.ProductCode,d.BetFrom



	DROP TABLE #Exchange
	DROP TABLE #LicenseeCustInfo
	DROP TABLE #Data
	DROP TABLE #Result
END
