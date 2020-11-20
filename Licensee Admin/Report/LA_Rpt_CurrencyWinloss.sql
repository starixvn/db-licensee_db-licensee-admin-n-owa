/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_Rpt_CurrencyWinloss]
	@PartyIDs				VARCHAR(5500)	= ''
	, @CurrencyIds			VARCHAR(4000)	= ''
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @ProductCodes			VARCHAR(1000)
	, @SportType			INT				= 0
	, @Bettype				INT				= 0
	, @ReportBy				TINYINT			= 0 
	, @drawfilter			SMALLINT		= 1
	, @IsConvert			BIT				= 0
	, @BaseCurrencyName		VARCHAR(10)		= 'GBP'
	, @GroupByType			SMALLINT		= 1
AS

/*  Created: Florent.Nguyen
	Date: 2014-09-03
	Task : Licensee Currency Winlost Report
	Base on: OA_Rpt_SummaryCurrencyWinloss
	DB: DB052.bodb02

	Revisions:
	   - 20141021@Florent: show credit's licensee
	   - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	   - 20150703@Florent: add GBP
	   - 20160504@Bruce: Remove dynamic sql
	   - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	   - 20170801@Kenny: Filter data for Microgaming [RedmineID: #79311]
	   - 20171220@Parsons: increase length for variables [#88197]
	   - 20180130@Bruce: integrate Exchange product [#87754]
	   - 20180515@Scofield: Incorporate 9wickets data [#94950] 
	   - 20180716@bruce: add new group TEST for credit [#98126]
	   - 20180703@Parsons: Integrate Pragmatic Win Loss [#94108]
	   - 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	   - 20180907@Bruce: Support multiple currency [#101160]
	   - 20181119@bruce: Integrate Bidme games (GD product) [#103695]
	   - 20190322@Parsons: Integrate-PP-Promotion-Prize [#109014]
	   - 20191205@Parsons: PP tournament [#123958]
	   - 20191225@Bruce: billing term by currency [#120005]
	   - 20200228@Parsons: Support-HID-currency [#128856]
	   - 20200409@Parsons: Integrate SA Gaming [#129276]
	   - 20200601@Parsons: Amend Currency WL report [#135055]
	   - 20200806@Happy: Enhancement requests for Currency WL Report and Platform WL Report [#138249]
	   - 20200821@Happy: Implement PP Jackpot changes in reports phase 2 [#139055]
	   - 20201021@Happy: Arcadia Gaming offers Bonus [#143597]
	   - 20201111@Happy: Changing OddsSpread for licensee [#142345]

	Param's Explanation:
	  + @ReportType: 1-Live; 2-Non-Live; 0: All;
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @MoveBetsDay: The day we move tickets to bettrans14
	  + @GroupByType: 1-Group by Licensees; 2-Group by Currency
*/
BEGIN
	SET NOCOUNT ON 
	DECLARE @GD_Tip SMALLINT = 1706,
			@PP_Contribution SMALLINT = 4297,
			@OddSpread_BetType SMALLINT = 999

	DECLARE @CurrencyTest INT = 20
	-- currency list
	--
	DECLARE @IsAllCurrency BIT = 0
	DECLARE @Currency TABLE(CurrencyId INT)

	-- all currency
	--
	IF ISNULL(@CurrencyIds,'') = ''
		SET @IsAllCurrency = 1
	ELSE
		INSERT INTO @Currency SELECT val FROM dbo.strSplit(@CurrencyIds, ',')

	-- convert to base
	--
	IF (@IsAllCurrency = 1 OR (SELECT COUNT(*) FROM @Currency) > 1) SET @IsConvert = 1

	DECLARE @ProductList TABLE (ProductCode VARCHAR(20))

	INSERT INTO @ProductList
	SELECT Val FROM dbo.strSplit(@ProductCodes, ',')

	CREATE TABLE #tmpWinLoss(
		Winlostdate		DATETIME,
		PartyID			INT,
		Currency		INT,
		TurnOver		MONEY,
		Winlost			MONEY,
		LicenseeWL		MONEY,
		AmtDueToBA		MONEY,
		CommBA			MONEY,
		Company			MONEY,
		Betcount		BIGINT,
		Playercomm		MONEY,
		OddsSpreadCost	MONEY
	)

	CREATE INDEX IX_tmpWinloss ON #tmpWinLoss(PartyID, winlostdate, Currency)

	CREATE TABLE #tmpParty (
		PartyID			INT
		,LicenseeID		INT
		,isDeposit		INT
		,AffectedDate	SMALLDATETIME
		,ProductID		INT
		,Rate			MONEY
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
		,Bettype		INT
		,ChargeType		SMALLINT
		,ChargeId		INT
	)

	INSERT INTO #tmpParty (PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Rate, Fromdate, Todate, Bettype, ChargeType, ChargeId)
	(
		SELECT DISTINCT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, 
						CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END,
						Fromdate, Todate,
						CASE WHEN ci.ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END,
						CASE WHEN ci.ProductID IN(11,39) THEN ci.ChargeType ELSE 1 END,
						ci.ChargeId
		FROM		bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
		LEFT JOIN   bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype AND (
					(ci.ProductId NOT IN (14,17)) OR 
					(ci.ProductID = 14 AND sbr.Bettype BETWEEN 2001 AND 2007) OR
					(ci.ProductID = 17 AND sbr.Bettype BETWEEN 2008 AND 2009))
	)
	CREATE INDEX IX_tmpParty ON #tmpParty(LicenseeID, ProductID)

	CREATE TABLE #Bettype (Bettype INT, ProductID INT)
	INSERT INTO #Bettype(Bettype, ProductID)
	SELECT Bettype, ProductID
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(@Bettype, @ProductCodes)
	CREATE INDEX IX_Bettype ON #Bettype(Bettype, ProductID)

	IF EXISTS (SELECT 1 FROM @ProductList WHERE ProductCode='BA')
	BEGIN
		--BA rpt_Betting_BA
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company,Betcount, Playercomm)
		(
			SELECT	b.rptDate,
					tp.PartyID,
					b.currencyID,
					SUM(b.Turnover) * (CASE	WHEN @drawfilter IN (2, 3) AND b.[Status] = 111			THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115)	THEN 0.5
											ELSE 1 END),
					SUM(b.WinLoss),
					0 as LicenseeWL,
					- SUM((b.WinLoss * tp.Rate ) + b.CommissionA) AS AmountDueToBA,
					SUM (CommissionA),
					0 as Company,
					SUM(b.BetCount) * (CASE	WHEN @drawfilter = 2 AND b.[Status] = 111 THEN 0 ELSE 1 END),
					SUM(b.CommissionP)
			FROM bodb_licenseereport.dbo.rpt_Betting_BA b WITH (NOLOCK)
				INNER JOIN #tmpParty tp ON b.SiteID = tp.LicenseeID AND tp.ProductID = 3
				INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND tp.ProductID = bt.ProductID
				LEFT JOIN dbo.League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			WHERE	(b.rptDate BETWEEN tp.Fromdate AND tp.ToDate) AND
					 b.[Status] NOT IN (-1, 101, 102, 103) AND
					(@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c)) AND
					(b.CurrencyID <> @CurrencyTest) AND
					(@SportType = 0 OR (b.bettype NOT IN (9,29) AND l.Sporttype = @SportType)) AND
					((@ReportBy = 0) OR
					 (@ReportBy = 1 AND b.IsLive=1 AND b.bettype NOT IN (9,29,10)) OR
					 (@ReportBy = 2 AND b.IsLive=0))
			GROUP BY b.rptDate, tp.PartyID, b.currencyID, b.[Status]
		)
	END

	IF (EXISTS (SELECT 1 FROM @ProductList WHERE ProductCode IN ('AGC','GD','VG','BX')) AND @SportType = 0 AND @ReportBy = 0 AND @Bettype = 0)
	BEGIN
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount, Playercomm)
		(
			SELECT b.rptDate,p.PartyID,b.CurrencyId
					,SUM(b.Turnover * 
						(CASE WHEN b.Bettype=33 AND b.[StatusId] IN (114,115) THEN 0.5 ELSE 1 END) *
						(CASE WHEN @drawfilter IN (2, 3) AND b.[StatusId] = 111  THEN 0
							  WHEN @drawfilter IN (2, 3) AND b.[StatusId] IN (114,115) THEN 0.5
							  ELSE 1 END))
					,SUM(b.MemberWL + CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END)
					,SUM(-b.MemberWL - CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END)
					,0 AS AmtDueToBA
					,0 AS CommBA
					,SUM(-b.MemberWL * ISNULL(cc.rate,p.Rate) - CASE WHEN b.ProductID=31 THEN (b.CommissionA + b.CommissionP) ELSE 0 END) AS Company
					,SUM(b.Betcount * (CASE WHEN @drawfilter = 2 AND b.[StatusId] = 111 THEN 0 ELSE 1 END)) 
					,SUM(b.commissionP)
			FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON b.SiteID = p.LicenseeID AND p.ProductID=b.ProductID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID = p.ChargeId AND b.CurrencyId=cc.CurrencyID
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					 b.StatusId NOT IN (-1, 101, 102, 103) AND
					(@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c)) AND
					(b.CurrencyID <> @CurrencyTest) AND
					b.CustomerCategory NOT IN (27,28) AND
					p.ProductID IN (10,11,12,31) AND
					p.ChargeType = 1 AND -- gross win
					b.bettype <> @GD_Tip
			GROUP BY b.rptDate
					,p.PartyID
					,b.CurrencyID

			UNION ALL
			-- GD tip
			SELECT b.rptDate,p.PartyID,b.CurrencyId,0,0,0,0,0
					,SUM(-b.MemberWL * p.Rate) AS Company 
					,0 AS Betcount
					,0 AS commissionP
			FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON b.SiteID = p.LicenseeID AND p.ProductID=b.ProductID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					(@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c)) AND
					(b.CurrencyID <> @CurrencyTest) AND
					p.ProductID = 11 AND
					b.Bettype = @GD_Tip AND 
					p.ChargeType = 12 -- GD tip sharing
			GROUP BY b.rptDate
					,p.PartyID
					,b.CurrencyID
		)
	END

	IF EXISTS (SELECT TOP 1 1 FROM @ProductList WHERE ProductCode IN ('MGCLC','MGCRNG'))
	BEGIN
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount, Playercomm)
		(
			SELECT b.RptDate, p.PartyId,b.CurrencyID
				, SUM(b.Turnover * (CASE	WHEN @drawfilter IN (2, 3) AND b.[Status] = 111			THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115)	THEN 0.5
											ELSE 1 END))
				, SUM(b.WinLoss) Winloss
				, -SUM(b.WinLoss) AS LicenseeWL
				, 0 AS AmtDueToBA
				, 0 AS CommBA
				, -SUM(b.WinLoss* p.Rate) AS Company
				, SUM(b.BetCount * (CASE WHEN @drawfilter = 2 AND b.[Status] = 111 THEN 0 ELSE 1 END))
				, 0 as Playercomm
			FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON p.LicenseeId=b.SiteId AND p.Bettype = b.Bettype
			LEFT JOIN dbo.League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
				AND (b.CurrencyID<>20)
				AND b.Status NOT IN (-1, 101, 102, 103)
				AND (@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c))
				AND (@SportType = 0 OR l.Sporttype = @SportType)
				AND (@Bettype = 0 OR b.bettype = @Bettype)
				AND p.ProductId IN (14,17)
			GROUP BY p.PartyId, b.rptDate, b.CurrencyID
		)
	END

	IF EXISTS (SELECT TOP 1 1 FROM @ProductList WHERE ProductCode NOT IN ('BA','MGCLC','MGCRNG','AGC','GD','VG','BX', 'RB'))
	BEGIN
		--exclude RB,BA,MGCLC, MGCRNG,AGC,GD,VG,BX
		DELETE #Bettype WHERE ProductID IN (1,3,14,17,10,11,12,31)
		DELETE #tmpParty WHERE ProductID IN (1,3,14,17,10,11,12,31)

		SELECT b.BetCount,b.turnover,b.rptDate,b.CurrencyID,b.Bettype,b.[Status],b.winloss,b.WinlossA,b.CommissionA,b.commissionP,b.SiteID,b.leagueid,b.IsLive,bt.ProductId
		INTO #tmpData
		FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
		INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
		LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('','999,4297') eb ON b.Bettype = eb.BettypeID
		WHERE b.CurrencyID <> @CurrencyTest
			AND b.[Status] NOT IN (-1, 101, 102, 103)
			AND b.CustomerCategory NOT IN (27,28)
			AND (@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c))
			AND b.SiteID IN (SELECT p.LicenseeId FROM #tmpParty p)
			AND b.rptDate BETWEEN @FromDate AND @ToDate
			AND eb.BettypeID IS NULL

		;WITH cte_Data AS
		(
			SELECT	b.rptDate
					,b.SiteID
					,b.CurrencyID
					,b.ProductID
					,SUM(CASE WHEN b.Bettype = @OddSpread_BetType THEN 0 ELSE b.Turnover * 
									(CASE   WHEN @drawfilter IN (2, 3) AND b.[Status] = 111 THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115) THEN 0.5
											ELSE 1
									 END)
						END) AS Turnover
					,SUM(CASE WHEN b.Bettype IN (@PP_Contribution, @OddSpread_BetType) THEN 0 ELSE b.winloss END)	AS MemberWL
					,SUM(CASE WHEN (@drawfilter = 2 AND b.[Status] = 111) OR b.Bettype IN (@PP_Contribution, @OddSpread_BetType) THEN 0 ELSE b.BetCount END) AS BetCount
					,SUM(CASE WHEN b.ProductId = 32 THEN 0 ELSE b.commissionP END) AS Playercomm
					,SUM(CASE WHEN b.Bettype IN (@PP_Contribution, @OddSpread_BetType) THEN ISNULL(-b.WinLossA, 0) ELSE 0 END) WinlossA
			FROM #tmpData b
			LEFT JOIN dbo.League l WITH(NOLOCK) ON b.leagueid = l.leagueid
			WHERE (@SportType = 0 OR (b.bettype NOT IN (9,29) AND (b.bettype NOT BETWEEN 31 AND 120) AND l.Sporttype = @Sporttype)) AND
				((@ReportBy = 0) OR
					(@ReportBy = 1 AND b.IsLive=1 AND b.bettype NOT IN (9,29,10)) OR
					(@ReportBy = 2 AND b.IsLive=0))
			GROUP BY b.rptDate,b.SiteID,b.CurrencyID,b.ProductID
					-- need to be group by below fields to avoid decimal fraction mismatch
					,b.Bettype
					,b.Status
		)
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount, Playercomm, OddsSpreadCost)
		SELECT a.rptDate
			   ,p.PartyID
			   ,a.CurrencyID
			   ,TurnOver
			   ,MemberWL
			   ,-MemberWL
			   ,0
			   ,0
			   ,(-MemberWL - CASE WHEN a.ProductID = 32 THEN WinlossA ELSE 0 END) * ISNULL(cc.Rate, p.Rate)
			   ,Betcount
			   ,Playercomm
			   ,WinlossA
		FROM cte_Data a
		INNER JOIN #tmpParty p ON p.LicenseeID = a.SiteID AND a.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId=a.ProductId AND p.ChargeType = 1
		LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID = p.ChargeId AND a.CurrencyId=cc.CurrencyID

		DROP TABLE #tmpData
	END

	-- Exchange rate
	SELECT DISTINCT ExchangeDate, ExchangeId, Code, BaseCurrencyRate AS Rate
	INTO #DailyExchange
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	IF @IsConvert = 0
	BEGIN
		UPDATE #DailyExchange
		SET Rate = 1
	END
	DECLARE @Exchange AS TABLE (Currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(20))

	INSERT INTO @Exchange(Currency, CurrencyName, CurrencyCode)
	SELECT e.exchangeid, e.currency, e.Code
	FROM Exchange e WITH (NOLOCK)
	WHERE e.exchangeid IN (SELECT DISTINCT Currency FROM #tmpWinLoss)
	
	UPDATE @Exchange
	SET CurrencyCode = (CASE Currency
							WHEN 51 THEN 'INH'
							WHEN 75 THEN 'PTU'
							WHEN 76 THEN 'PS'
							WHEN 77 THEN 'PTH'
							WHEN 92 THEN 'HID' 
							ELSE CurrencyCode
						END)
	WHERE Currency IN (51, 75, 76, 77, 92)

	UPDATE e
	SET CurrencyCode = e.CurrencyCode + '(' + CurrencyName + ')'
	FROM @Exchange e
	WHERE e.CurrencyCode IN (SELECT CurrencyCode FROM @Exchange GROUP BY CurrencyCode HAVING COUNT(1) > 1)
	
	--Report Group By Licensee
	IF (@GroupByType = 1)
	BEGIN
		SELECT	w.PartyID,
				CASE WHEN p.PartyName ='18bb' THEN 'PIH'
					 WHEN p.PartyName ='IBC' THEN 'FDL'
					 ELSE p.PartyName
				END AS PartyName,
				CASE WHEN w.Currency = @CurrencyTest THEN e.Code
					 ELSE t.CurrencyCode 
				END AS CurrencyName,
				w.currency,
				w.Winlostdate				AS ReportDate,
				SUM(TurnOver * e.Rate)		AS Turnover,
				SUM(Winlost * e.Rate)		AS Winlost,
				SUM(LicenseeWL * e.Rate)	AS LicenseeWL,
				SUM(CommBA * e.Rate)		AS CommBA,
				SUM(AmtDuetoBA * e.Rate)	AS AmtDuetoBA,
				SUM(Company * e.Rate)		AS Company,
				SUM(Betcount)				AS Betcount,
				SUM(Playercomm * e.Rate)	AS Playercomm,
				SUM(OddsSpreadCost*e.Rate)	AS OddsSpreadCost
		FROM #tmpWinLoss w
		INNER JOIN #DailyExchange e ON w.Winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON w.PartyID = p.PartyID
		LEFT JOIN @Exchange t ON w.Currency = t.Currency
		GROUP BY w.PartyID,p.PartyName, CASE WHEN w.Currency = @CurrencyTest THEN e.Code ELSE t.CurrencyCode END, w.currency, w.Winlostdate
		ORDER BY w.PartyID,p.PartyName, CASE WHEN w.Currency = @CurrencyTest THEN e.Code ELSE t.CurrencyCode END, w.Winlostdate
	END

	--Report Group By Currency
	IF (@GroupByType = 2)
	BEGIN
		SELECT CASE 
					WHEN w.Currency = @CurrencyTest THEN e.Code
					ELSE t.CurrencyCode 
				END AS currencyName,
				w.currency,
				SUM(TurnOver * e.Rate)		AS Turnover,
				SUM(Winlost * e.Rate)		AS Winlost,
				SUM(LicenseeWL * e.Rate)	AS LicenseeWL,
				SUM(CommBA * e.Rate)		AS CommBA,
				SUM(AmtDuetoBA * e.Rate)	AS AmtDuetoBA,
				SUM(Company * e.Rate)		AS Company,
				SUM(Betcount)				AS Betcount,
				SUM(Playercomm * e.Rate)	AS Playercomm,
				SUM(OddsSpreadCost*e.Rate)	AS OddsSpreadCost
		FROM #tmpWinLoss w	
		INNER JOIN #DailyExchange e ON w.Winlostdate = e.ExchangeDate AND w.Currency = e.ExchangeId
		LEFT JOIN @Exchange t ON w.Currency = t.Currency
		GROUP BY CASE WHEN w.Currency = @CurrencyTest THEN e.Code ELSE t.CurrencyCode END, w.currency
		ORDER BY CASE WHEN w.Currency = @CurrencyTest THEN e.Code ELSE t.CurrencyCode END
	END

	DROP TABLE #tmpWinLoss
	DROP TABLE #Bettype
	DROP TABLE #tmpParty
	DROP TABLE #DailyExchange
END
GO