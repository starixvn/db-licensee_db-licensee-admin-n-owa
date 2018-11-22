/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet,bodbLicenseeNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeAnalysis] (
	@PartyIDs		VARCHAR(4000),
	@ProductCodes	VARCHAR(200),
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
		- 20170919@Bruce: create SP [RedmineID: #78294]
		- 20171123@Sophia: Revise SP [RedmineID: #78294]
		- 20180716@bruce: add new group TEST for credit [#98126]

	Notes: @FromDate, @ToDate should be a full month range
	Example :  EXEC LA_Rpt_LicenseeAnalysis  @PartyIDs = '73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88', 
			@ProductCodes = 'RB,NG,BA,LC,VS,CS,BG,KN,PTCS,AGC,GD,VG,BT,MGCLC,HF,MGCRNG,AB,VB,NG2,FW,CO,VS2,LT',
			@FromDate =  '2017-01-01',  @ToDate = '2017-10-31' , @IsSkinView = 0
*/
BEGIN
	SET NOCOUNT ON

	-- discount type
	DECLARE @Rebate INT = 2
	DECLARE @DiscountIndividualFee INT = 1
	DECLARE @DiscountIndividualGrosswin INT = 3
	DECLARE @DiscountByGroupFee INT = 11
	DECLARE @DiscountByGroupGrosswin INT = 13

	-- calculation type
	DECLARE @ToBeDiscounted INT = 0
	DECLARE @ToBeCalculated INT = 1
	DECLARE @CalculateAndDiscount INT = 10

	-- remove un-support products
	DECLARE @Products AS TABLE (ProductId INT,ProductCode VARCHAR(10), ToBeDiscounted BIT)

	INSERT INTO @Products(ProductCode,ProductId, ToBeDiscounted)
	SELECT ProductPrefix,ProductID, 1
	FROM dbo.LA_f_Products3rd(@ProductCodes)
	WHERE ProductID NOT IN (1,3,7,9,13,14,15,16,17,19,25)

	-- 1.1 Party groups
	-- select all parties in the same group
	DECLARE @PartyIdTable TABLE (PartyId INT, IsSelected BIT)
	INSERT INTO @PartyIdTable SELECT DISTINCT val, 1 FROM dbo.strSplit(@PartyIDs, ',')

	DECLARE @PartyGroup AS TABLE (PartyGroupId INT, PartyId INT)
	
	IF @IsSkinView = 0
	BEGIN
		INSERT	INTO @PartyGroup(PartyGroupId, PartyId)
		(
			SELECT	PartyGroupId, PartyId
			FROM	dbo.LA_PartyGroupAssignment WITH(NOLOCK)
			WHERE	PartyGroupId IN (	SELECT	p1.PartyGroupId
										FROM	dbo.LA_PartyGroupAssignment p1 WITH(NOLOCK)
										WHERE	p1.PartyId IN (SELECT p2.PartyId FROM @PartyIdTable p2))
		)

		INSERT INTO @PartyIdTable
		SELECT DISTINCT PartyId, 0 FROM @PartyGroup WHERE PartyId NOT IN (SELECT p2.PartyId FROM @PartyIdTable p2)
	END

	-- 1.2 discount settings
	;WITH cte_DiscountGroup AS(
		SELECT DISTINCT a.DiscountGroupId, a.PartyID
		FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId=a.DiscountGroupId
		INNER JOIN @PartyIdTable b ON a.PartyID=b.PartyId
		WHERE b.IsSelected=1
			AND p.ProductId IN (SELECT c.ProductId FROM @Products c WHERE c.ToBeDiscounted=1)
			AND p.CalculationType IN (@ToBeDiscounted, @CalculateAndDiscount)
	)
	-- 1.3
	-- put parties in discount group to its own group
	-- put parties of individual discount group to new unique virtual group, indicate by discountid & partyid
	SELECT DISTINCT h.DiscountGroupId, h.DiscountGroupType, a.PartyID, p.ProductId, p.CalculationType, a.IsApplyDiscount, h.CurrencyId, h.FromDate,
		CASE
			WHEN h.DiscountGroupType IN (@DiscountIndividualFee, @DiscountIndividualGrosswin) THEN (CAST(h.DiscountGroupId AS INT) * 100000) + a.PartyID
			ELSE h.DiscountGroupId
		END CalculationGroup
	INTO #tmpDiscountSettings
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
	INNER JOIN cte_DiscountGroup c ON c.DiscountGroupId = h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId = h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
		AND (
			-- discount by group: get all party in same group
			h.DiscountGroupType IN (@DiscountByGroupFee,@DiscountByGroupGrosswin) OR
			-- discount by individual party: get only selected party
			a.PartyID = c.PartyID
		)
	WHERE h.DiscountGroupType != @Rebate AND h.FromDate <= @ToDate AND @FromDate <= h.ToDate

	-- 1.4 only 1 discount per month for product/party
	;WITH cte_Discount AS (
		SELECT DiscountGroupType, PartyID, ProductId, MAX(FromDate) FromDate
		FROM #tmpDiscountSettings
		GROUP BY DiscountGroupType, PartyID, ProductId
		HAVING COUNT(1) > 1
	)
	DELETE d FROM #tmpDiscountSettings d INNER JOIN cte_Discount c ON d.FromDate < c.FromDate
		AND c.PartyID = d.PartyID 
		AND c.ProductId = d.ProductId
		AND c.DiscountGroupType = d.DiscountGroupType

	-- 1.5 add discount calculation party
	INSERT INTO @PartyIdTable(PartyId,IsSelected)
	SELECT DISTINCT a.PartyID, 0
	FROM #tmpDiscountSettings a
	LEFT JOIN @PartyIdTable b ON a.PartyID = b.PartyId
	WHERE b.PartyId IS NULL AND a.CalculationType IN (@ToBeCalculated, @CalculateAndDiscount)

	-- 1.6 discount by currency
	DECLARE @tmpDiscountCurrency TABLE(DiscountGroupId SMALLINT, PartyId INT, CurrencyId INT)

	INSERT INTO @tmpDiscountCurrency(DiscountGroupId, PartyId, CurrencyId)
	SELECT c.DiscountGroupId, c.PartyID, c.CurrencyId
	FROM dbo.LA_DiscountGroupCurrency c WITH(NOLOCK)
	WHERE c.DiscountGroupId IN (SELECT DISTINCT d.DiscountGroupId FROM #tmpDiscountSettings d)

	-- 1.7 include discount calculation products
	INSERT INTO @Products(ProductId,ProductCode,ToBeDiscounted)
	SELECT DISTINCT s.ProductId,a.ProductPrefix, 0
	FROM #tmpDiscountSettings s
	INNER JOIN dbo.LA_f_Products3rd('') a ON a.ProductID = s.ProductId
	WHERE CalculationType IN (@ToBeCalculated, @CalculateAndDiscount)
		AND s.ProductId NOT IN (SELECT p.ProductId FROM @Products p)

	-- 1.8 update product code & partyids
	SET @ProductCodes = STUFF((SELECT ',' + ProductCode FROM @Products FOR XML PATH('')),1,1,'')
	SET @PartyIds = STUFF((SELECT ',' + CAST(PartyId AS VARCHAR(10)) FROM @PartyIdTable FOR XML PATH('')),1,1,'')

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
	CREATE	TABLE #Exchange (FirstExchangeDateByMonth DATE, LastExchangeDateByMonth DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate DECIMAL(9,8))
	INSERT INTO #Exchange(FirstExchangeDateByMonth, LastExchangeDateByMonth, ExchangeID,  CurrencyCode, Rate)
	SELECT FirstExchangeDateByMonth, LastExchangeDateByMonth, ExchangeId,  Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_SubExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
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
		WHERE @IsSkinView = 0 
			AND (mf.FeeTypeId = 1 OR (mf.FeeTypeId = 2 
				AND EXISTS (SELECT PartyId FROM dbo.LA_MinFee m WITH(NOLOCK)
					WHERE m.FeeTypeId = 1
						AND m.PartyId = mf.PartyId
						AND m.ProductId = mf.ProductId
						AND ((m.FromDate BETWEEN @FirstDate AND @LastDate)
							OR (m.ToDate BETWEEN @FirstDate AND @LastDate)
							OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
						)
				)
			))
			AND mf.ProductId IN (SELECT ProductId FROM @Products)
			AND mf.PartyId IN (SELECT p.PartyId FROM @PartyIdTable p)
			AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
				OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
				OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
			)
	)

	DELETE @MinFeeGroup WHERE ToDate < FromDate
	UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
	INNER JOIN #Exchange e ON m.ToDate BETWEEN e.FirstExchangeDateByMonth AND e.LastExchangeDateByMonth AND m.CurrencyId = e.ExchangeID
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
	SELECT DISTINCT c.LicenseeId, c.CustId, c.Currency, c.Fromdate, c.Todate, c.PartyId 
	FROM Cust c	
 
	CREATE CLUSTERED INDEX ix_LicenseeCustInfo_cl ON #LicenseeCustInfo(CustId, CurrencyId)
	-- end region

	-- 6. get move bet info
	DECLARE @BalanceUpDay TABLE (BalanceUpDay DATETIME, MoveBetsDay DATETIME)
	INSERT INTO @BalanceUpDay EXEC bodb02.dbo.Lrf_SelBalanceUpDay	
	DECLARE @MoveBetsDay DATETIME = (SELECT TOP 1 MoveBetsDay FROM @BalanceUpDay)
	-- end region

	-- 7. if data from moveBetsDay: get data from bettrans else get data from rptWinLoss2
	CREATE TABLE #Result (
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
	
		CREATE TABLE #BettypeList  (Bettype SMALLINT, ProductId INT ) 
		INSERT INTO #BettypeList (Bettype, ProductID)
		SELECT bettype, ProductID FROM LA_f_BettypeProductMapping(0,@ProductCodes) 
		
		DECLARE @TempFromDate SMALLDATETIME = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY,1,@MoveBetsDay) ELSE @FromDate END
		INSERT INTO #Result(ReportDate, CurrencyId, BetFrom, Turnover, LicenseeWinLoss, ProductId, PartyId)
		(
			SELECT
				b.winlostdate,
				l.CurrencyId,
				CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END,
				SUM(b.stake * e.Rate),
				SUM(-(b.winlost - b.actual_stake) * e.Rate),
				bt.ProductID,
				l.PartyId
			FROM bodb02.dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #LicenseeCustInfo l 
					ON l.CustId = b.recommend 					
						AND b.currency=l.CurrencyId 
						AND b.winlostdate BETWEEN l.Fromdate AND l.Todate
				INNER JOIN #BettypeList bt 
					ON bt.Bettype=b.bettype
				INNER JOIN #Exchange e 
					ON b.Currency = e.ExchangeID 
						AND b.winlostdate BETWEEN e.FirstExchangeDateByMonth AND e.LastExchangeDateByMonth
			WHERE b.statusID IN (111, 112, 113) 
				AND b.winlostdate BETWEEN @TempFromDate AND @ToDate
				AND NOT EXISTS (SELECT 1 FROM dbo.LicenseeBATransaction ba WITH(NOLOCK) WHERE b.transid = ba.transid)
				AND b.bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY b.winlostdate, l.CurrencyId, CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END, bt.ProductID,l.PartyId
		)

		DROP TABLE #BettypeList
	END
	
	-- 7.2. get data from rptWinLoss2
	-- notes: ps.ProductId <> p.ProductId
	IF @FromDate <= @MoveBetsDay
	BEGIN	
		CREATE TABLE #SportypeList  (SportType SMALLINT, ProductCode Varchar(10), ProductId INT) 
		INSERT INTO #SportypeList (SportType, ProductCode, ProductId)
		SELECT s.SportType, s.ProductCode , p.ProductId
		FROM bodb02.dbo.f_LicWinLoss_ProductSportType_Sel(@ProductCodes)  s
		INNER JOIN @Products p ON p.ProductCode=s.ProductCode		
		
		DECLARE @TempToDate SMALLDATETIME = CASE WHEN @ToDate >= @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END
		INSERT INTO #Result(ReportDate, CurrencyId, BetFrom, Turnover, LicenseeWinLoss, ProductID,PartyId)
		(
			SELECT
				b.winlostdate,
				b.Currency,
				CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END,
				SUM(b.turnover * e.Rate),
				SUM(-b.winlost * e.Rate),
				ps.ProductID,
				l.PartyId
			FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH ( NOLOCK )
			CROSS APPLY (SELECT l.PartyId 
						FROM #LicenseeCustInfo l 
						WHERE 
						    b.winlostdate >= l.Fromdate AND b.winlostdate <= l.Todate
							AND b.Currency = l.CurrencyId
							AND b.recommend = l.CustId
							AND b.roleid = 2  
							) l		
			INNER JOIN #SportypeList ps ON ps.SportType = b.sporttype					
			INNER JOIN #Exchange e 
				ON b.Currency = e.ExchangeID 
					AND b.winlostdate BETWEEN e.FirstExchangeDateByMonth AND e.LastExchangeDateByMonth	
			WHERE b.Winlostdate BETWEEN @FromDate AND @TempToDate
				AND b.roleid = 2 -- Sum on agent for better performance
				AND b.statusID NOT IN (-1, 101, 102, 103)
				AND b.bettype NOT IN (901,902,903,904,911,912,913,914)
				AND ISNULL(b.isBA,0) = 0
			GROUP BY b.winlostdate, b.Currency, CASE WHEN b.betfrom IN ('d','a','e', 'u','m','s','l') THEN b.betfrom ELSE '*' END,l.PartyId,ps.ProductID
		)
	END
	-- end region

	-- 10. calculate licensing fee(amount to company)
	UPDATE d SET LicensingFee = (d.LicenseeWinLoss * p.Rate), FeeAfterDiscount=0,FeeAfterRebate=0
	FROM #Result d
	INNER JOIN @PartyChargeInfo p ON p.PartyId = d.PartyId AND p.ProductId=d.ProductId AND d.ReportDate BETWEEN p.FromDate AND p.ToDate

	UPDATE d SET LicensingFee = 0, FeeAfterDiscount=0,FeeAfterRebate=0
	FROM #Result d
	WHERE LicensingFee IS NULL
	-- end region

	-- 11. calculate min fee
	UPDATE t SET t.IsApplyMinFee = 0
	FROM #Result t
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
			FROM #Result td 
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
									FROM	#Result td
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

	-- 12. Get rebate setting
	DECLARE @tmpRebateSettings TABLE(PartyId INT, ProductId INT, Rate DECIMAL(7,5), FromDate DATE)
	
	INSERT INTO @tmpRebateSettings(PartyId, ProductId, Rate, FromDate)
	SELECT a.PartyID, p.ProductId, d.Rate, h.FromDate
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
	INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId=a.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId=h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON d.DiscountGroupId=h.DiscountGroupId
	INNER JOIN @PartyIdTable l ON l.PartyId=a.PartyID AND l.IsSelected=1
	WHERE h.DiscountGroupType=@Rebate
		AND h.FromDate <= @ToDate
		AND h.ToDate >= @FromDate

	-- 12.1 only 1 rebate per month for product/party
	;WITH cte_Rebate AS (
		SELECT PartyID, ProductId, MAX(FromDate) FromDate
		FROM @tmpRebateSettings
		GROUP BY PartyID, ProductId
		HAVING COUNT(1) > 1
	)
	DELETE r FROM @tmpRebateSettings r INNER JOIN cte_Rebate c ON r.FromDate < c.FromDate
		AND c.PartyID = r.PartyID 
		AND c.ProductId = r.ProductId
	-- End Region

	-- 13. sum by licensee
	;WITH a AS (
		SELECT d.PartyId, d.ProductId,
			SUM(d.Turnover)			Turnover,
			SUM(d.LicenseeWinLoss)	LicenseeWinLoss,
			SUM(d.LicensingFee)		LicensingFee,
			CAST(0 AS MONEY)		Discount,
			CAST(0 AS MONEY)		Rebate
		FROM #Result d
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

	-- 13. Apply Discount/rebate
	-- 13.1. Get discount group info
	DECLARE @Unlimited MONEY = 1000000000000
	DECLARE @tmpDiscountCalculation TABLE(
		CalculationGroup	INT,
		DiscountGroupId		SMALLINT,
		DiscountGroupType	TINYINT,
		CurrencyId			INT,
		Winloss				MONEY,
		Fee 				MONEY,
		IsDiscountByCurrency BIT
	)

	-- 13.2 discount by all currency
	INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee,IsDiscountByCurrency)
	SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.LicenseeWinLoss) Winloss,SUM(r.LicensingFee) Fee,0
	FROM #tmpDiscountSettings s
	INNER JOIN @tmpDiscountCurrency c ON s.PartyId = c.PartyId AND c.DiscountGroupId=s.DiscountGroupId AND c.CurrencyId = 0 -- all currency
	INNER JOIN #SumByLicensee r ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
	GROUP BY s.DiscountGroupId, s.DiscountGroupType,s.CurrencyId,s.CalculationGroup

	-- 13.3 discount by currency
	-- only offer discount for licensing fee
	INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee,IsDiscountByCurrency)
	SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.LicenseeWinLoss) Winloss,SUM(r.LicensingFee) Fee,1
	FROM #Result r
	INNER JOIN @tmpDiscountCurrency c ON c.PartyID=r.PartyId AND c.CurrencyId=r.CurrencyId
	INNER JOIN #tmpDiscountSettings s ON s.DiscountGroupId=c.DiscountGroupId AND s.ProductId = r.ProductId AND s.PartyId = c.PartyId
	WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
		AND s.DiscountGroupType IN (@DiscountIndividualFee, @DiscountByGroupFee)
	GROUP BY s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId

	-- 13.4 get discount rate
	DECLARE @Rate TABLE(Rate DECIMAL(6,5), CalculationGroup INT, IsDiscountByCurrency BIT)
	;WITH cte_Detail AS(
		SELECT c.CalculationGroup, d.DiscountGroupId, d.Rate
			,ISNULL(d.FromAmount,0) * e.Rate AS FromAmount
			,CASE WHEN d.ToAmount > @Unlimited THEN d.ToAmount ELSE (d.ToAmount + 1) * e.Rate END AS ToAmount
		FROM dbo.LA_DiscountGroupDetail d
		INNER JOIN @tmpDiscountCalculation c ON d.DiscountGroupId=c.DiscountGroupId
		INNER JOIN #Exchange e ON e.ExchangeId = c.CurrencyId AND e.LastExchangeDateByMonth=@ToDate
	)
	INSERT INTO @Rate(rate, CalculationGroup,IsDiscountByCurrency)
	SELECT d.Rate, c.CalculationGroup, c.IsDiscountByCurrency
	FROM @tmpDiscountCalculation c INNER JOIN cte_Detail d ON c.CalculationGroup=d.CalculationGroup
	WHERE (
			c.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) AND
			c.Fee >= d.FromAmount AND c.Fee < d.ToAmount
		) OR (
			c.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) AND
			c.Winloss >= d.FromAmount AND c.Winloss < d.ToAmount
		)

	-- 13.5 discount by all currencies
	UPDATE r SET Discount = CASE
			WHEN s.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) THEN c.Rate * r.LicensingFee
			WHEN s.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) THEN c.Rate * (CASE WHEN r.LicenseeWinLoss < 0 THEN 0 ELSE r.LicenseeWinLoss END)
		ELSE 0 END
	FROM #SumByLicensee r
	INNER JOIN #tmpDiscountSettings s ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	INNER JOIN @Rate c ON c.CalculationGroup = s.CalculationGroup
	WHERE s.CalculationType IN (@ToBeDiscounted,@CalculateAndDiscount) 
		AND s.IsApplyDiscount = 1
		AND c.IsDiscountByCurrency = 0

	-- 13.6 discount by curency
	-- not support gross win
	-- not support multiple products
	-- not discount if fee after discount less than minfee
	;WITH cte_DiscountByCurrency AS(
		SELECT c.CalculationGroup, c.Rate, c.Rate * (CASE WHEN s.Fee <0 THEN 0 ELSE s.Fee END) Discount
		FROM @tmpDiscountCalculation s
		INNER JOIN @rate c ON c.CalculationGroup = s.CalculationGroup
		WHERE c.IsDiscountByCurrency = 1
	)
	UPDATE t SET Discount = d.Discount
	FROM #SumByLicensee t
	INNER JOIN #tmpDiscountSettings s ON t.PartyID = s.PartyID AND t.ProductID=s.ProductId
	INNER JOIN cte_DiscountByCurrency d on d.CalculationGroup=s.CalculationGroup
	LEFT JOIN @MinFeeGroup m ON m.PartyId = t.PartyId AND m.ProductId = t.ProductId
	WHERE d.Discount > 0 AND (t.LicensingFee - d.Discount) >= ISNULL(m.MinFeeProrate,0)
	-- End Region

	-- 14. licensee group
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentID INT)
	INSERT INTO @PartyList (PartyId, PartyName, BrandName, ParentID)
	EXEC dbo.LA_PartyListSel
	-- end region

	IF @IsSkinView = 0
	BEGIN
		-- calculate rebate
		UPDATE s SET Rebate = CASE WHEN (s.LicensingFee - s.Discount) < 0 THEN 0 ELSE (s.LicensingFee - s.Discount) * ISNULL(r.Rate, 0) END
		FROM #SumByLicensee s INNER JOIN @tmpRebateSettings r ON s.PartyId = r.PartyId AND r.ProductId = s.ProductId

		SELECT p.PartyName 						AS ViewName
			,SUM(ISNULL(s.LicenseeWinLoss,0))	AS WinLoss
			,SUM(ISNULL(s.Turnover,0))			AS Turnover
			,SUM(ISNULL(s.LicensingFee,0))		AS LicensingFee
			,SUM(ISNULL(s.LicensingFee,0) - ISNULL(s.Discount,0) - ISNULL(s.Rebate,0)) AS Discount
			,@FirstDate							AS [Date]
		FROM @PartyIdTable pt
		LEFT JOIN @PartyList p ON p.PartyId=pt.PartyId
		LEFT JOIN #SumByLicensee s ON pt.PartyId=s.PartyId
		WHERE pt.IsSelected = 1 AND p.ParentId > 0
		GROUP BY p.PartyName
	END
	ELSE
	BEGIN
		DECLARE @Skin AS TABLE(BetFrom CHAR(1), Skin VARCHAR(10), [Order] TINYINT)
		INSERT INTO @Skin VALUES ('d','Asia',1),('a','China',2),('e','Euro',3),('u','Euro',3),('m','WAP',4),('s','Smart',5),('l','Smart',5),('*','Other',6)

		-- group by skin
		-- exclude minfee
		-- discount of each skin = total discount * (licensing fee/ total licensing fee)
		SELECT s.Skin, d.ProductId,
			SUM(d.Turnover)			Turnover,
			SUM(d.LicenseeWinLoss)	LicenseeWinLoss,
			SUM(d.LicensingFee)		LicensingFee,
			CAST(0 AS MONEY)		Discount
		INTO #SumBySkin
		FROM #Result d
		INNER JOIN @PartyIdTable pt ON pt.PartyId=d.PartyId
		INNER JOIN @Skin s ON s.BetFrom=d.BetFrom
		WHERE pt.IsSelected = 1
		GROUP BY s.Skin, d.ProductId

		-- total discount by product
		;WITH t AS (
			SELECT s.ProductId
				,SUM(s.LicensingFee)	AS TotalFee
				,SUM(s.Discount)		AS TotalDiscount
			FROM #SumByLicensee s
			GROUP BY s.ProductId
		)
		UPDATE s SET 
			s.Discount = CASE WHEN t.TotalFee=0 THEN 0 ELSE t.TotalDiscount * (s.LicensingFee / t.TotalFee) END
		FROM #SumBySkin s
		INNER JOIN t ON t.ProductId=s.ProductId

		SELECT bs.Skin							AS ViewName
			,SUM(ISNULL(s.LicenseeWinLoss,0))	AS WinLoss
			,SUM(ISNULL(s.Turnover,0))			AS Turnover
			,SUM(ISNULL(s.LicensingFee,0))		AS LicensingFee
			,SUM(ISNULL(s.LicensingFee,0)-ISNULL(s.Discount,0))	AS Discount
			,@FirstDate							AS [Date]
		FROM @Skin bs
		LEFT JOIN #SumBySkin s ON s.Skin = bs.Skin
		GROUP BY bs.Skin, bs.[Order]
		ORDER BY bs.[Order]

		DROP TABLE #SumBySkin
	END	

	DROP TABLE #Exchange
	DROP TABLE #LicenseeCustInfo
	DROP TABLE #Result
	DROP TABLE #SumByLicensee
	DROP TABLE #SportypeList 
END
GO 
 GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicenseeAnalysis] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[LA_Rpt_LicenseeAnalysis] TO [bodbLicenseeNet]
GO 
 GRANT EXECUTE ON [dbo].[LA_Rpt_LicenseeAnalysis] TO [bodbAdminNet]
GO 
