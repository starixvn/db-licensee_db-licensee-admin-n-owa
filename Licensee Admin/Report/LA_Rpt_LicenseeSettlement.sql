/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="1"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeSettlement]
	  @PartyId				INT
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @ProductCode			VARCHAR(50)
	, @CurrencyId			INT				= 0
	, @BaseCurrencyName		VARCHAR(10)		= 'GBP'
WITH RECOMPILE
AS
	/*  Created: 20150313@Florent
		Task : Report - Licensee Settlement Report
		Base on : IMS_Rpt_LicenseeSettlement
		DB: DBEXT.bodb02
		
		Revisions:
			- 20150407@Florent: add filter no draw for BA Settlement
			- 20150505@Florent: Integrate Gold Deluxe and Voidbridge
			- 20150519@Florent: Change Product Prefix from VB to VG
			- 20150722@Florent: Implement Microgaming Casino (MGC)
			- 20150910@Florent: Implement Bettrade
			- 20150914@Bravo: Add 2 Column for Grand Total Row.
			- 20160107@Bruce: Split BuyBackAmount into BuyBackAmountSB & BuyBackAmountBA
			- 20160112@Bruce: Bettrade: LicenseeWL = 0 for BA tickets
			- 20160316@Bruce: Bettrade: added BuyBackAmountSportsbookBase and BuyBackAmountBABase
			- 20160428@Bruce: MGCRNG: Support Microgaming - Progressive Contribution
			- 20160929@Scofield: Update for Colossus Bet
			- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
			- 20170329@Scofield: support Cashout [RedmineID :#73310]
			- 20170404@Harper: using new sum table for Cashout Product [RedmineID: #73310]
			- 20170511@bruce: include exchange rate [RedmineID: #76132]
			- 20170712@bruce: include BRVS, LO [RedmineID: #79310]
			- 20171219@Bruce: increase length for variables [#88197]
			- 20180126@Bruce: include Exchange-BX [#87754]
			- 20180419@Scofield: update CB for FreePlay [#93907]
			- 20180515@Scofield: Incorporate 9wickets data [#94950]
			- 20180716@bruce: add new group TEST for credit [#98126]
			- 20181120@Parsons: Integrate Bidme games (GD product) [#103695]
			- 20190312@Parsons: Integrate Promotion Prize (PP product) [#109014]
			- 20191122@Mason: Setup billing terms by Currency  [#120005]
			- 20191205@Parsons: PP tournament [#123958]  
			- 20200228@Parsons: Support-HID-currency [#128856] 
			- 20200412@Parsons: Integrate SA Gaming [#129276]
			- 20200403@Parsons: Indo 4D Integration [#130910] 
		    - 20200719@Parsons: Implement PP Jackpot [RedmineID: #137306]
			- 20201022@Mason: Arcadia Gaming - Add Bonus feature [#143597]

		Param's Explanation:
			+ @ProductCode:		'SB' -> Sportsbook				'RB' -> Racing
								'NG' -> Number Game				'BA' -> BA
								'LC' -> Live Casino				'VS' -> Virtual Sports
								'CS' -> RNG Casino				'BG' -> Bingo
								'BT' -> Bettrade				'MGCLC'->Microgaming Live Casino
								'BX' -> Exchange				'MGCRNG'->Microgaming RNG Casino
								'CB' -> Colossus Bets			'CO' -> Cash Out
								'LO' -> Lottery					'BRVS' -> Betradar Virtual Sports
	*/
SET NOCOUNT ON
BEGIN
	SET @ProductCode = LTRIM(RTRIM(REPLACE(@ProductCode,',','')))

	DECLARE @LicenseeID INT,
			@DrawFilter SMALLINT = 1
	DECLARE @GD_Tip SMALLINT = 1706,
			@SAG_Tip SMALLINT = 3007

	CREATE TABLE #Result
	(
		Winlostdate					DATETIME,
		CurrencyId					INT,
		Game						VARCHAR(100),
		Turnover					MONEY,
		ActualStake					MONEY,
		BuyBackAmount				MONEY,
		BuyBackAmountSB				MONEY,
		BuyBackAmountBA				MONEY,
		Winlost						MONEY,
		WinningPrize				MONEY,
		Contribution				MONEY,
		JackpotPrize				MONEY,
		Cashout						MONEY,
		PlayerComm					MONEY,
		LicenseeWL					MONEY,
		LicenseeChargeRate			MONEY,
		LicenseeComm				MONEY,
		BettradeComm				MONEY,
		CashInShare					MONEY,
		Company						MONEY,
		ProgressiveContribution		MONEY,
		ProgressivePayout			MONEY,
		ProgressiveFee				MONEY,
		Betcount					BIGINT,
		CashOutTimes				MONEY,
		CashOutTickets				MONEY,
		CashOutValue				MONEY,
		TicketsPayout				MONEY,
		CashoutCommission			MONEY,
		BuyBackAmountAndComm		MONEY,
		TipsAmount					MONEY,
		TipsAmountDue				MONEY
	)

	CREATE TABLE #Exchange
	(
		ExchangeDate			DATE,
		ExchangeID				INT,
		CurrencyCode			VARCHAR(10),
		Rate					DECIMAL(6,5)
	)

	DECLARE @ChargeInfo AS TABLE
	(
		ChargeId 	INT,
		PartyId		INT,
		LicenseeId	INT,
		ProductID	INT,
		Bettype		INT,
		Rate		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME
	)
	INSERT INTO @ChargeInfo(ChargeId, PartyId, LicenseeId, ProductID, Bettype, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT ChargeId, PartyID, LicenseeID, ProductID,
			CASE 
				WHEN ProductID = 11 AND ChargeType = 12 THEN @GD_Tip
				WHEN ProductID = 39 AND ChargeType = 12 THEN @SAG_Tip 
			ELSE Bettype END AS ChargeType
			, DI_Rate, Fromdate, Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyID, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE DI_Rate > 0
	)
	DECLARE @Bettype AS TABLE
	(
		Bettype		INT,
		ProductId	INT
	)
	INSERT INTO @Bettype (Bettype, ProductId)
	(
		SELECT Bettype, ProductID
		FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)
	)
	
	SELECT @LicenseeID = LicenseeID FROM @ChargeInfo
	IF @LicenseeID IS NULL
	BEGIN
		SELECT TOP 0
		''					AS Game
		,@ToDate			AS WinLostDate
		,0					AS CurrencyId
		,''					AS CurrencyName
		,CAST(0 AS MONEY)	AS Betcount
		,CAST(0 AS MONEY)	AS Turnover
		,CAST(0 AS MONEY)	AS ActualStake
		,CAST(0 AS MONEY)	AS BuyBackAmount
		,CAST(0 AS MONEY)	AS MemberWinLoss
		,CAST(0 AS MONEY)	AS WinningPrize
		,CAST(0 AS MONEY)	AS Contribution
		,CAST(0 AS MONEY)	AS JackpotPrize
		,CAST(0 AS MONEY)	AS MemberComm
		,CAST(0 AS MONEY)	AS BettradeComm
		,CAST(0 AS MONEY)	AS LicenseeWL
		,CAST(0 AS MONEY)	AS LicenseeComm
		,CAST(0 AS MONEY)	AS Company
		,CAST(0 AS MONEY)	AS TurnoverBase
		,CAST(0 AS MONEY)	AS ActualStakeBase
		,CAST(0 AS MONEY)	AS BuyBackAmountBase
		,CAST(0 AS MONEY)	AS BettradeCommBase
		,CAST(0 AS MONEY)	AS MemberWinLossBase
		,CAST(0 AS MONEY)	AS WinningPrizeBase
		,CAST(0 AS MONEY)	AS ContributionBase
		,CAST(0 AS MONEY)	AS JackpotPrizeBase
		,CAST(0 AS MONEY)	AS MemberCommBase
		,CAST(0 AS MONEY)	AS LicenseeWLBase
		,CAST(0 AS MONEY)	AS LicenseeCommBase
		,CAST(0 AS MONEY)	AS CompanyBase
		,CAST(0 AS MONEY)	AS BuyBackAmountSB
		,CAST(0 AS MONEY)	AS BuyBackAmountBA
		,CAST(0 AS MONEY)	AS ProgressiveContribution
		,CAST(0 AS MONEY)	AS ProgressiveContributionBase
		,CAST(0 AS MONEY)	AS ProgressivePayoutBase
		,CAST(0 AS MONEY)	AS ProgressivePayout
		,CAST(0 AS MONEY)	AS ProgressiveFee
		,CAST(0 AS MONEY)	AS ProgressiveFeeBase
		,CAST(0 AS MONEY)	AS TipsAmount
		,CAST(0 AS MONEY)	AS TipsAmountBase
		,CAST(0 AS MONEY)	AS TipsAmountDue
		,CAST(0 AS MONEY)	AS TipsAmountDueBase
		RETURN
	END

	DECLARE @Recommend VARCHAR(8000) = '', @SQL VARCHAR(8000) = ''

	CREATE TABLE #DataWinloss3rd
	(
		Recommend		INT,
		Winlostdate		DATETIME,
		SportType		INT,
		Currency		INT,
		Turnover		MONEY,
		TotalTrans		INT,
		Winloss			MONEY
	)

	DECLARE @TempAG AS TABLE
	(
		LicenseeeID INT,
		CustId INT,
		CurrencyId INT
	)

	IF (@ProductCode = 'AGC') -- AG Casino
	BEGIN
		--get licensee recommend
		INSERT INTO @TempAG(LicenseeeID, CustId, CurrencyId)
		SELECT DISTINCT LicenseeID, CustID, Currency
		FROM bodb_licensee.dbo.f_SelLicenseeCust(@LicenseeID)
		WHERE (@CurrencyId = 0 OR Currency = @CurrencyId) AND Currency <> 20

		SELECT @Recommend = @Recommend + CAST(CustID AS VARCHAR) + ','
		FROM @TempAG

		--truncate last comma
		SET @Recommend = SUBSTRING(@Recommend, 0, LEN(@Recommend))

		SELECT @sql = 'SELECT Recommend, Winlostdate, SportType, Currency, Turnover, TotalTrans, Winloss
						FROM OPENQUERY(DBACC,''EXEC bodb02.dbo.LA_Rpt_3rdProductWinloss
												@ProductCodes		= ''''@ProductCodes_''''
											, @Recommend		= ''''@Recommend_''''
											, @Currency 		= @Currency_
											, @FromDate 		= ''''@FromDate_''''
											, @ToDate 			= ''''@ToDate_''''
											'')'
		SET @SQL = REPLACE(@SQL, '@ProductCodes_', @ProductCode)
		SET @SQL = REPLACE(@SQL, '@Recommend_', @Recommend)
		SET @SQL = REPLACE(@SQL, '@Currency_', @CurrencyId)
		SET @SQL = REPLACE(@SQL, '@FromDate_', CONVERT( VARCHAR(10),@FromDate, 120))
		SET @SQL = REPLACE(@SQL, '@ToDate_', CONVERT( VARCHAR(10),@ToDate, 120))

		INSERT INTO #DataWinloss3rd(Recommend, Winlostdate, SportType, Currency, Turnover, TotalTrans, Winloss)
		EXECUTE (@SQL)

		INSERT INTO #Result( Winlostdate, CurrencyId, Turnover, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
		(
			SELECT
				b.Winlostdate
				, ag.CurrencyID
				, SUM(Turnover) AS Turnover
				, SUM(WinLoss) AS Winlost
				, 0 AS PlayerComm
				, - SUM(Winloss * ( 1 - ISNULL(cm.Rate, p.Rate))) AS LicenseeWL
				, 0 AS LicenseeComm
				, - SUM(WinLoss * ISNULL(cm.Rate, p.Rate)) AS Company
				, SUM(b.TotalTrans) AS BetCount
			FROM #DataWinloss3rd b WITH (NOLOCK)
				INNER JOIN @TempAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId
				INNER JOIN @ChargeInfo p ON ag.LicenseeeID = p.LicenseeId
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cm WITH (NOLOCK) ON p.ChargeId = cm.ChargeId AND b.Currency = cm.CurrencyId
			WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate
			GROUP BY b.Winlostdate, ag.CurrencyID
		)
	END
	ELSE IF (@ProductCode = 'VG') -- VG
	BEGIN
		--get licensee recommend
		INSERT INTO @TempAG(LicenseeeID, CustId, CurrencyId)
		SELECT DISTINCT LicenseeID, CustID, Currency
		FROM bodb_licensee.dbo.f_SelLicenseeCust(@LicenseeID)
		WHERE (@CurrencyId = 0 OR (@CurrencyId <> 0 AND Currency = @CurrencyId))
			AND Currency <> 20

		SELECT @Recommend = @Recommend + CAST(CustID AS VARCHAR) + ','
		FROM @TempAG

		--truncate last comma
		SET @Recommend = SUBSTRING(@Recommend, 0, LEN(@Recommend))

		INSERT INTO #DataWinloss3rd(Recommend, Winlostdate, Currency, Turnover, TotalTrans, Winloss)
		EXECUTE dbo.LA_Rpt_ThirdPartyProductWinloss
				@ProductCodes	= @ProductCode
				, @Recommend	= @Recommend
				, @Currency 	= @CurrencyId
				, @DrawFilter	= 1
				, @FromDate 	= @FromDate
				, @ToDate 		= @ToDate

		INSERT INTO #Result( Winlostdate, CurrencyId, Turnover, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
		(
			SELECT
				b.Winlostdate
				, CurrencyID
				, SUM(Turnover) AS Turnover
				, SUM(WinLoss) AS Winlost
				, 0 AS PlayerComm
				, - SUM(Winloss * ( 1 - p.Rate)) AS LicenseeWL
				, 0 AS LicenseeComm
				, - SUM(WinLoss * p.Rate) AS Company
				, SUM(b.TotalTrans) AS BetCount
			FROM #DataWinloss3rd b WITH (NOLOCK)
				INNER JOIN @TempAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId
				INNER JOIN @ChargeInfo p ON ag.LicenseeeID = p.LicenseeId
			WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate
			GROUP BY b.Winlostdate, CurrencyID
		)
	END
	ELSE IF (@ProductCode = 'GD' OR @ProductCode = 'SAG') --GD && SAG
	BEGIN
		DECLARE @Product_Id INT
		SELECT TOP 1 @Product_Id = ProductId FROM @ChargeInfo
		;WITH cte_TempData AS(
			SELECT b.rptDate, b.CurrencyID, b.Bettype
				, SUM(Turnover) AS Turnover
				, SUM(CASE WHEN b.Bettype IN (@GD_Tip, @SAG_Tip) THEN 0 ELSE MemberWL END ) AS MemberWL
				, SUM(CASE WHEN b.Bettype IN (@GD_Tip, @SAG_Tip) THEN -MemberWL ELSE 0 END ) AS TipAmount
				, SUM(CASE WHEN b.Bettype IN (@GD_Tip, @SAG_Tip) THEN 0 ELSE b.BetCount END) AS BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND (@CurrencyId = 0 OR b.CurrencyId = @CurrencyId)
				AND b.StatusId NOT IN (-1, 101, 102, 103)
				AND b.customercategory NOT IN (27, 28)
				AND b.SiteId = @LicenseeID
				AND b.ProductID = @Product_Id
			GROUP BY b.rptDate, b.CurrencyId, b.Bettype
		)
		
		INSERT INTO #Result( Winlostdate, CurrencyId, Turnover, Winlost, PlayerComm, LicenseeWL, LicenseeComm, TipsAmount, TipsAmountDue, Company, Betcount)
		(
			SELECT
				b.rptDate
				, b.CurrencyID
				, SUM(Turnover) AS Turnover
				, SUM(MemberWL) AS Winlost
				, 0 AS PlayerComm
				, SUM(-MemberWL * (1 - ISNULL(cm.Rate, p.Rate))) AS LicenseeWL
				, 0 AS LicenseeComm
				, SUM(TipAmount) AS TipsAmount
				, SUM(TipAmount * p.Rate) AS TipsAmountDue
				, SUM((-MemberWL * ISNULL(cm.Rate, p.Rate)) + (TipAmount * p.Rate)) AS Company
				, SUM(b.betcount) AS BetCount
			FROM cte_TempData b
				INNER JOIN @ChargeInfo p ON (
					b.rptDate BETWEEN p.FromDate AND p.ToDate AND
					p.Bettype = b.Bettype
				)
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cm WITH (NOLOCK) ON p.ChargeId = cm.ChargeId AND b.CurrencyId = cm.CurrencyId
			GROUP BY b.rptDate, b.CurrencyId
		)
	END
	ELSE IF (@ProductCode = 'MGCLC' OR @ProductCode = 'MGCRNG')
	BEGIN
		-- product 3rd sub name
		DECLARE @Product3rdSubName TABLE (Bettype INT, BettypeRef INT, ProductName VARCHAR(100))
		INSERT INTO @Product3rdSubName( Bettype, BettypeRef)
		(
			SELECT s.Bettype, p.BettypeRef
			FROM bodb_licensee.dbo.Sport_Bettype_Reference s WITH (NOLOCK)
			LEFT JOIN bodb_licensee.dbo.LA_Product3rdSub p WITH (NOLOCK) ON s.BettypeRef = p.BettypeRef
			WHERE s.Bettype BETWEEN 2001 AND 2009
			GROUP BY s.Bettype, p.BettypeRef
		)

		IF @ProductCode = 'MGCLC'
		BEGIN
			DELETE FROM @Product3rdSubName WHERE Bettype IN (2008,2009)

			UPDATE @Product3rdSubName
			SET ProductName = 'Live Casino - Generic Games'
			WHERE BettypeRef = 2001

			UPDATE @Product3rdSubName
			SET ProductName = 'Live Casino - Branded Games'
			WHERE BettypeRef = 2005
		END
		ELSE
		BEGIN
			DELETE FROM @Product3rdSubName WHERE Bettype NOT IN (2008,2009)

			UPDATE @Product3rdSubName
			SET ProductName = 'RNG Casino - Generic Games'
			WHERE BettypeRef = 2001

			UPDATE @Product3rdSubName
			SET ProductName = 'RNG Casino - Branded Games'
			WHERE BettypeRef = 2005
		END

		;WITH d AS (
			SELECT b.SiteId, b.rptDate, b.CurrencyID, s.Bettype
				, SUM(ISNULL(b.Turnover, 0)) AS Turnover
				, SUM(ISNULL(b.winloss, 0)) AS Winloss
				, SUM(ISNULL(b.PComm, 0)) AS PComm
				, SUM(ISNULL(b.AComm, 0)) AS AComm
				, SUM(ISNULL(b.BetCount, 0)) AS BetCount
				, SUM(ISNULL(b.ProgressiveContribution, 0)) AS ProgressiveContribution
				, SUM(ISNULL(b.ProgressivePayout, 0)) AS ProgressivePayout
			FROM bodb_licenseereport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN @Product3rdSubName s ON s.Bettype = b.BettypeId
			INNER JOIN (SELECT DISTINCT LicenseeId, Bettype FROM @ChargeInfo) p ON b.SiteId = p.LicenseeID AND p.Bettype=s.BettypeRef
			WHERE b.SiteID = @LicenseeID
				AND b.rptDate BETWEEN @FromDate AND @ToDate
				AND (@CurrencyId = 0 OR b.CurrencyID = @CurrencyId)
				AND (b.CurrencyID <> 20)
				AND b.StatusId NOT IN (-1, 101, 102, 103)
			GROUP BY b.rptDate, b.SiteId, b.CurrencyID, s.Bettype
		)
		INSERT INTO #Result( Winlostdate, CurrencyId, Game, Turnover, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount,ProgressiveContribution,ProgressivePayout,ProgressiveFee)
		SELECT	 d.rptDate
				,d.CurrencyID
				,ps.ProductName
				,SUM(d.Turnover)
				,SUM(d.WinLoss)
				,SUM(d.PComm)
				,SUM((-d.Winloss - d.ProgressiveContribution) * ( 1 - p.Rate))
				,SUM(d.AComm - d.PComm)
				,SUM((-d.WinLoss - d.ProgressiveContribution) * p.Rate - d.AComm)
				,SUM(d.BetCount)
				,SUM(d.ProgressiveContribution)
				,SUM(d.ProgressivePayout)
				,SUM(d.ProgressiveContribution - d.ProgressivePayout)
		FROM d
		INNER JOIN @Product3rdSubName ps ON d.Bettype = ps.Bettype
		INNER JOIN @ChargeInfo p ON d.SiteId = p.LicenseeID AND p.Bettype = ps.BettypeRef
		WHERE d.rptDate BETWEEN p.Fromdate AND p.Todate
		GROUP BY rptDate, CurrencyID , ps.ProductName, d.Bettype
	END
	ELSE IF (@ProductCode = 'BT')--BetTrade
	BEGIN
		-- add more bettype for SB, BA
		INSERT INTO @Bettype (Bettype, ProductId)
		(
			SELECT Bettype, ProductID
			FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'SB,BA')
		)

		INSERT INTO #Result( Winlostdate, CurrencyId, ActualStake, BuyBackAmount, LicenseeWL, Winlost, BettradeComm, Company, Betcount, BuyBackAmountSB, BuyBackAmountBA)
		(
			SELECT
				d.RptDate					AS  Winlostdate
				, d.CurrencyID
				, SUM (d.Actual_stake)		AS ActualStake
				, SUM (d.BuyBackAmountTotal)	AS BuyBackAmount
				, SUM (d.LicWinLoss )		AS LicenseeWL
				, SUM (d.BTWinLoss)			AS Winlost
				, SUM (d.BettradeComm)		AS BettradeComm
				, SUM ((d.BTWinLoss + d.BettradeComm + d.Actual_stake - d.BuyBackAmountTotal)) AS Company
				, SUM (BetCount) AS BetCount
				, SUM (BuyBackAmountSB)
				, SUM (BuyBachAmountBA)
			FROM (
				SELECT b.RptDate, b.CurrencyId
					, SUM(CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount - b.WinLoss) ELSE 0 END) AS Actual_stake
					, SUM(CASE WHEN b.Bettype = 901 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountTotal
					, SUM(CASE WHEN bt.ProductID = 0 THEN b.WinLoss ELSE 0 END) AS BTWinLoss
					, - SUM(CASE WHEN bt.ProductID = 0 AND b.CustomerCategory <> 1002 THEN b.WinLoss ELSE 0 END) AS LicWinLoss -- LicenseeWL on bought BA(1002) = 0
					, SUM (CASE WHEN b.Bettype = 901 AND b.CustomerCategory = 1001 THEN - b.BuyBackAmount * p.Rate ELSE 0 END) AS BettradeComm
					, SUM(CASE WHEN bt.ProductId = 0 THEN ISNULL(b.BetCount, 0) ELSE 0 END) BetCount
					, SUM(CASE WHEN b.bettype = 901 AND b.CustomerCategory = 1001 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountSB -- 1001 : SB
					, SUM(CASE WHEN b.bettype = 901 AND b.CustomerCategory = 1002 THEN b.BuyBackAmount ELSE 0 END) AS BuyBachAmountBA -- 1002 : BA
				FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN @ChargeInfo p ON b.SiteId = p.LicenseeID
					INNER JOIN @Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductId IN (0, 13)
				WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
					AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))
					AND b.CurrencyID <> 20
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory IN (1001, 1002)
				GROUP BY b.RptDate, b.CurrencyId
				UNION ALL
				-- rpt_betting_BA only contain original ticket, SOLD BOUGHT COMM ticket will be in rpt_betting
				SELECT b.RptDate, b.CurrencyId
					, 0 AS Actual_stake
					, 0 AS BuyBackAmountTotal
					, SUM(b.WinLoss) AS BTWinLoss
					, 0 AS LicWinLoss -- LicenseeWL on bought BA = 0
					, 0 AS BettradeComm
					, SUM(ISNULL(b.BetCount, 0)) BetCount
					, 0 AS BuyBackAmountSB
					, 0 AS BuyBackAmountBA
				FROM bodb_licenseereport.dbo.rpt_Betting_BA b WITH (NOLOCK)
					INNER JOIN @ChargeInfo p ON b.SiteId = p.LicenseeID
					INNER JOIN @Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductID IN (3)
				WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
					AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))
					AND b.CurrencyID <> 20
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory = 1002 -- for BT BA
				GROUP BY b.RptDate, b.CurrencyId

			) d
			GROUP BY d.RptDate, d.CurrencyID
		)
	END
	ELSE IF (@ProductCode = 'BA')
	BEGIN
		SET @DrawFilter = 2 -- set case No Darw
		INSERT INTO #Result( Winlostdate, CurrencyId, Turnover, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
		(
			SELECT
				b.rptDate
				, b.CurrencyID
				, SUM(b.turnover *
						CASE WHEN @drawfilter IN (2, 3)
							THEN CASE WHEN b.STATUS = 111 THEN 0
								WHEN b.STATUS IN (114, 115)	THEN 0.5 ELSE 1	END
							ELSE 1
						END) AS turnover
				, SUM(b.WinLoss) AS Winlost
				, 0 AS PlayerComm
				, SUM(b.CommissionA) AS LicenseeWL
				, 0 AS LicenseeComm
				, - SUM(b.WinLoss * p.Rate + b.CommissionA) AS Company
				, SUM(betcount * CASE WHEN @drawfilter = 2 AND b.Status = 111 THEN 0 ELSE 1 END) AS BetCount
			FROM
				bodb_licenseereport.dbo.rpt_Betting_BA b WITH (NOLOCK)
				INNER JOIN @ChargeInfo p ON b.SiteID = p.LicenseeId
			WHERE
				b.rptDate BETWEEN p.FromDate AND p.ToDate
				AND b.SiteID = @LicenseeID
				AND b.Bettype IN (SELECT Bettype FROM @Bettype)
				AND b.Status NOT IN (-1, 101, 102, 103)
				AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))
				AND b.CurrencyID <> 20
			GROUP BY
				b.rptDate, b.CurrencyID
		)
	END
	ELSE IF (@ProductCode = 'CB')
	BEGIN
		-- Region: Local variables
		DECLARE @ProductId INT = (SELECT TOP 1 ProductId FROM bodb_licensee.dbo.Product3rd WITH(NOLOCK) WHERE ProductPrefix='CB')
		DECLARE @CommChargeType INT = 6
		DECLARE @CashInShareChargeType INT = 7

		-- Region: Commision and Cash in share Rates
		DECLARE @CBShare AS TABLE (
			PartyId			INT,
			LicenseeId		INT,
			Rate			MONEY,
			TypeId			SMALLINT,
			FromDate		DATETIME,
			ToDate			DATETIME
		)

		INSERT INTO @CBShare(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)		
		SELECT PartyID,LicenseeID,DI_Rate,ChargeType,Fromdate,Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(CAST(@PartyId as varchar(20)),@FromDate,@ToDate,'CB','OA',1)
		-- End Region: Commision and Cash in share Rates

		-- Region: Get Winloss Data
		CREATE TABLE #TempData (
			rptDate							DATETIME,
			CurrencyId						INT,
			TotalTrans						INT,
			Turnover						MONEY,
			TurnoverForCommision			MONEY,
			TurnoverExchanged				MONEY,
			WinningPrize					MONEY,
			CashOut							MONEY,
			CommisionShare					MONEY,
			CashInShare						MONEY,
			CashInAmount					MONEY
		)

		INSERT INTO #TempData (rptDate, CurrencyId, TotalTrans, Turnover, TurnoverForCommision, WinningPrize, CashOut, CashInAmount)
		SELECT	rptDate,
				CurrencyId,
				SUM(BetCount) TotalTrans,
				SUM(Turnover) Turnover,
				SUM(CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN b.Turnover ELSE b.ExtraAmount END) TurnoverForCommision,
				SUM(ISNULL(WinPrizeAmount,0)) WinningPrize,
				SUM(ISNULL(CashOutAmount,0)) CashOut,
				SUM(ISNULL(BuyBackAmount,0)) CashInAmount
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		JOIN @CBShare cb ON b.SiteID = cb.LicenseeId AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
		WHERE	ProductID = @ProductId AND
				CustomerCategory NOT IN (27, 28) AND
				b.StatusId NOT IN (-1, 101, 102, 103) AND
				CurrencyId <> 20 AND
				(@CurrencyId = 0 OR (@CurrencyId <> 0 AND CurrencyId = @CurrencyId)) AND
				cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
		GROUP BY rptdate, CurrencyId
		-- End Region: Get Winloss Data

		UPDATE #TempData
		SET CommisionShare = td.TurnoverForCommision * cm.Rate,
			CashInShare = td.CashInAmount * ci.Rate
		FROM #TempData td
		JOIN @CBShare AS cm ON cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate)
		JOIN @CBShare AS ci ON ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate)
		-- End Region: Calculate Commision, Cash In Share

		-- Region: Group by Currency
		INSERT INTO #Result(Winlostdate, CurrencyId, Turnover, Betcount, WinningPrize, Cashout, LicenseeComm, CashInShare)
		SELECT @ToDate, CurrencyId, SUM(td.Turnover), SUM(td.TotalTrans), SUM(td.WinningPrize), SUM(td.CashOut), SUM(td.CommisionShare), SUM(td.CashInShare)
		FROM #TempData td
		GROUP BY td.CurrencyId

		UPDATE #Result SET Company = Turnover - WinningPrize - Cashout - LicenseeComm - CashInShare
		-- End Region: Group by Currency

		-- Drop temp tables
		DROP TABLE #TempData
	END
	ELSE IF (@ProductCode = 'CO')
	BEGIN
		DECLARE @SBProductId INT = 0
		DECLARE @BAProductId INT = 3
		DECLARE @COProductId INT = (SELECT Productid FROM bodb_licensee.dbo.Product3rd WHERE ProductPrefix = 'CO')
		-- add more bettype for SB, BA

		INSERT INTO #Result( Winlostdate, CurrencyId, CashoutTimes, CashoutTickets, CashoutValue, BuyBackAmountSB, BuyBackAmountBA, BuyBackAmount, TicketsPayout, CashoutCommission, BuyBackAmountAndComm, Company)
		(
			SELECT
				d.Winlostdate,
				d.Currency,
				SUM(CashoutTimes) AS CashoutTimes,
				SUM(ISNULL(CashoutTickets, 0)) AS CashoutTickets,
				SUM(CashoutValue) AS CashoutValue,
				SUM(BuyBackAmountSB) AS BuyBackAmountSB,
				SUM(BuyBackAmountBA) AS BuyBackAmountBA,
				SUM(BuyBackAmountSB + BuyBackAmountBA) AS BuyBackAmount,
				SUM(TicketsPayout) AS TicketsPayout,
				SUM(CashoutCommission) AS CashoutCommission,
				SUM(BuyBackAmountSB + BuyBackAmountBA + CashoutCommission) AS BuyBackAmountAndComm,
				SUM(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) AS Company
			FROM (
					SELECT p.PartyId, b.Winlostdate, b.Currency,
							SUM(b.NumOfCashoutTrans) AS CashoutTimes,
							SUM(b.NumOfCashoutTicket) AS CashoutTickets,
							SUM(b.CashoutAmount) AS CashoutValue,
							SUM(b.BuyBackAmt) AS BuyBackAmountSB,
							SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
							SUM(b.TicketPayout) AS TicketsPayout,
							SUM(b.BuyBackAmt * p.Rate) AS CashoutCommission
					FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
						INNER JOIN @ChargeInfo p ON b.SiteId = p.LicenseeID AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate
					WHERE b.Winlostdate BETWEEN p.FromDate AND p.ToDate
						AND b.Currency <> 20
						AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.Currency = @CurrencyId))
						AND b.ProductID = 25
						AND b.RoleID = 1 -- Member
					GROUP BY p.PartyId, b.Winlostdate, b.Currency
			) d
			GROUP BY d.Winlostdate, d.Currency
		)
	END
	ELSE IF (@ProductCode = 'BX')
	BEGIN
		DECLARE @ExchangeProductId INT = (SELECT Productid FROM bodb_licensee.dbo.Product3rd WHERE ProductPrefix = 'BX')

		INSERT INTO #Result( Winlostdate, CurrencyId, Turnover, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
		(
			SELECT b.rptDate
				, b.CurrencyId
				, SUM(b.turnover)
				, SUM(b.MemberWL + b.CommissionP) winloss
				, 0
				, SUM(-b.MemberWL * (1 - p.Rate) + b.CommissionA)
				, 0
				, SUM(-b.MemberWL * p.Rate - (b.CommissionA + b.CommissionP))
				, SUM(b.BetCount)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @ChargeInfo p ON b.SiteId = p.LicenseeID AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			WHERE b.CurrencyId <> 20
				AND (@CurrencyId = 0 OR b.CurrencyId = @CurrencyId)
				AND b.ProductID = @ExchangeProductId
				AND b.StatusId NOT IN (-1, 101, 102, 103)
				AND b.customercategory NOT IN (27, 28)
			GROUP BY b.rptDate, b.CurrencyId
		)
	END
	ELSE IF (@ProductCode = 'PP')
	BEGIN
		DECLARE @PP_Contribution SMALLINT = 4297,
				@PP_JackpotPrize SMALLINT = 4298,
				@PPTournament SMALLINT = 4299,   
				@PromotionPrize SMALLINT = 4300 

		;WITH cte_WinLossData AS(
			SELECT b.SiteId, b.rptDate, b.CurrencyID
				, SUM(CASE WHEN b.Bettype NOT IN(@PPTournament, @PromotionPrize, @PP_Contribution, @PP_JackpotPrize) THEN ISNULL(b.BetCount, 0) ELSE 0 END) BetCount
				, SUM(CASE WHEN b.Bettype NOT IN(@PPTournament, @PromotionPrize, @PP_Contribution, @PP_JackpotPrize) THEN ISNULL(b.Turnover, 0) ELSE 0 END) Turnover
				, SUM(CASE WHEN b.Bettype NOT IN(@PPTournament, @PromotionPrize, @PP_Contribution, @PP_JackpotPrize) THEN ISNULL(b.MemberWL, 0) ELSE 0 END) MemberWL
				, SUM(CASE WHEN b.Bettype IN(@PPTournament, @PromotionPrize) THEN ISNULL(b.MemberWL, 0) ELSE 0 END) AS WinningPrize
				, SUM(CASE WHEN b.Bettype = @PP_Contribution THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) AS Contribution
				, SUM(CASE WHEN b.Bettype = @PP_JackpotPrize THEN ISNULL(b.MemberWL, 0) ELSE 0 END) AS JackpotPrize
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				WHERE
					b.ProductID = 32
					AND	b.SiteID = @LicenseeID
					AND b.rptDate BETWEEN @FromDate AND @ToDate
					AND (@CurrencyId = 0 OR b.CurrencyID = @CurrencyId)
					AND b.[StatusId] NOT IN (-1, 101, 102, 103)
				GROUP BY b.rptdate, b.SiteId, b.CurrencyID
		)
		INSERT INTO #Result(Winlostdate, CurrencyId, Betcount, Turnover, Winlost, LicenseeWL, LicenseeChargeRate, WinningPrize, Contribution, JackpotPrize, Company)
		SELECT rptDate, d.CurrencyID
				, SUM(BetCount)		AS BetCount
				, SUM(Turnover)		AS Turnover
				, SUM(MemberWL)		AS Winlost
				, SUM((-MemberWL - Contribution) * (1 - ISNULL(cm.Rate, p.Rate)))  AS LicenseeWL
				, SUM((-MemberWL - Contribution) * ISNULL(cm.Rate, p.Rate))  AS LicenseeChargeRate
				, SUM(WinningPrize) AS WinningPrize
				, SUM(Contribution) AS Contribution
				, SUM(JackpotPrize) AS JackpotPrize
				, SUM((-MemberWL - Contribution) * ISNULL(cm.Rate, p.Rate) + Contribution - JackpotPrize - WinningPrize) AS Company
		FROM cte_WinLossData d
			INNER JOIN @ChargeInfo p ON d.SiteId = p.LicenseeID
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cm WITH (NOLOCK) ON p.ChargeId = cm.ChargeId AND d.CurrencyId = cm.CurrencyId 
		WHERE d.rptDate BETWEEN p.Fromdate AND p.Todate
		GROUP BY rptDate, d.CurrencyID
	END
	ELSE IF (@ProductCode = 'CC')
	BEGIN
		DECLARE @ArcadiaGaming_Bonus SMALLINT = 1906
		;WITH cte_ArcadiaData AS
		(
			SELECT b.SiteId, b.rptDate, b.CurrencyId
				,SUM(CASE WHEN b.Bettype = @ArcadiaGaming_Bonus THEN 0 ELSE ISNULL(b.BetCount, 0) END) AS BetCount
				,SUM(ISNULL(b.Turnover, 0)) AS Turnover
				,SUM(CASE WHEN b.Bettype = @ArcadiaGaming_Bonus THEN 0 ELSE ISNULL(b.MemberWL, 0) END) AS MemberWL
				,SUM(CASE WHEN b.Bettype = @ArcadiaGaming_Bonus THEN ISNULL(b.MemberWL, 0) ELSE 0 END) AS WinningPrize
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			WHERE b.ProductID = 34
				AND b.rptDate BETWEEN @FromDate AND @ToDate
				AND (@CurrencyId = 0 OR b.CurrencyID = @CurrencyId)
				AND b.[StatusId] NOT IN (-1, 101, 102, 103)
			GROUP BY b.SiteId, rptDate, b.CurrencyID
		)
		INSERT INTO #Result(Winlostdate, CurrencyId, Betcount, Turnover, Winlost, LicenseeWL, Company, WinningPrize)
		SELECT b.rptDate, b.CurrencyId
			,SUM(Betcount) 
			,SUM(Turnover) 
			,SUM(MemberWL) 
			,SUM(-MemberWL * (1 - ISNULL(cm.Rate, p.Rate)))				AS LicenseeWL
			,SUM(-MemberWL * ISNULL(cm.Rate, p.Rate) - WinningPrize)	AS Company
			,SUM(WinningPrize) 
		FROM cte_ArcadiaData b
		INNER JOIN @ChargeInfo p ON b.SiteId = p.LicenseeID
		LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cm WITH (NOLOCK) ON p.ChargeId = cm.ChargeId AND b.CurrencyId = cm.CurrencyId
		WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate
		GROUP BY rptDate, b.CurrencyID
	END
	ELSE
	BEGIN
		INSERT INTO #Result( Winlostdate, CurrencyId, Turnover, ActualStake, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
		(
			SELECT
				rptDate
				, d.CurrencyID
				, SUM(Turnover) AS turnover
				, SUM(ActualStake) AS ActualStake
				, SUM(WinLoss) AS Winlost
				, SUM(PComm) AS PlayerComm
				, SUM(-Winloss * ( 1 - ISNULL(cr.Rate, p.Rate))) AS LicenseeWL
				, SUM(AComm - PComm) AS LicenseeComm
				, SUM(-WinLoss * ISNULL(cr.Rate, p.Rate) + AComm) AS Company
				, SUM(BetCount) AS BetCount
			FROM (
				SELECT b.SiteId, b.rptDate, b.CurrencyID
				, SUM(ISNULL(b.turnover, 0)) AS Turnover
				, SUM(CASE WHEN @ProductCode = 'I4D' THEN ISNULL(b.ExtraAmount, 0) ELSE 0 END) AS ActualStake
				, SUM(ISNULL(b.winloss, 0)) Winloss
				, SUM(ISNULL(b.CommissionP, 0)) AS PComm
				, SUM(ISNULL(b.CommissionA, 0)) AS AComm
				, SUM(ISNULL(b.betcount, 0)) BetCount
				FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN @Bettype bt ON b.Bettype = bt.Bettype
				WHERE
					b.SiteID = @LicenseeID
					AND b.rptDate BETWEEN @FromDate AND @ToDate
					AND (@CurrencyId = 0 OR b.CurrencyID = @CurrencyId)
					AND (b.CurrencyID <> 20)
					AND b.[Status] NOT IN (-1, 101, 102, 103)
					AND b.customercategory NOT IN (27, 28)
				GROUP BY b.rptdate, b.SiteId, b.CurrencyID
			) d
				INNER JOIN @ChargeInfo p ON d.SiteId = p.LicenseeID
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeId AND d.CurrencyID = cr.CurrencyId
			WHERE d.rptDate BETWEEN p.Fromdate AND p.Todate
			GROUP BY rptDate, d.CurrencyID
		)
	END	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)	
							
	UPDATE #Exchange
	SET CurrencyCode = (CASE ExchangeId
							WHEN 75 THEN 'PTU'
							WHEN 76 THEN 'PS'
							WHEN 77 THEN 'PTH'
							WHEN 92 THEN 'HID' 
							ELSE CurrencyCode
						END)
	WHERE ExchangeId IN (75, 76, 77, 92)	
	
	;WITH sortedExchange AS (
		SELECT ExchangeID, CurrencyCode, ROW_NUMBER() OVER (PARTITION BY CurrencyCode ORDER BY ExchangeId) RowNumber
		FROM #Exchange
	)
	SELECT
		ISNULL(d.Game, '')			AS Game
		, @ToDate					AS WinLostDate
		, se.ExchangeID		AS CurrencyId
		, se.CurrencyCode			AS CurrencyName
		, e.Rate					AS ExchangeRate
		, SUM(Betcount)				AS Betcount
		--orginal
		, SUM(ISNULL(d.Turnover, 0))					AS Turnover
		, SUM(ISNULL(d.ActualStake, 0))					AS ActualStake
		, SUM(ISNULL(d.BuyBackAmount, 0))				AS BuyBackAmount
		, SUM(ISNULL(d.BuyBackAmountSB, 0))				AS BuyBackAmountSportsbook
		, SUM(ISNULL(d.BuyBackAmountBA, 0))				AS BuyBackAmountBA
		, SUM(ISNULL(d.Winlost, 0))						AS MemberWinLoss
		, SUM(ISNULL(d.WinningPrize, 0))				AS WinningPrize
		, SUM(ISNULL(d.Contribution, 0))				AS Contribution
		, SUM(ISNULL(d.JackpotPrize, 0))				AS JackpotPrize
		, SUM(ISNULL(d.Cashout, 0))						AS Cashout
		, SUM(ISNULL(d.PlayerComm, 0))					AS MemberComm
		, SUM(ISNULL(d.BettradeComm, 0))				AS BettradeComm
		, SUM(ISNULL(d.LicenseeWL, 0))					AS LicenseeWL
		, SUM(ISNULL(d.LicenseeChargeRate, 0))			AS LicenseeChargeRate
		, SUM(ISNULL(d.LicenseeComm, 0))				AS LicenseeComm
		, SUM(ISNULL(d.CashInShare, 0))					AS CashInShare
		, SUM(ISNULL(d.TipsAmount, 0))					AS TipsAmount
		, SUM(ISNULL(d.TipsAmountDue, 0))				AS TipsAmountDue
		, SUM(ISNULL(d.Company, 0))						AS Company
		, SUM(ISNULL(d.ProgressiveContribution, 0))		AS ProgressiveContribution
		, SUM(ISNULL(d.ProgressivePayout, 0))			AS ProgressivePayout
		, SUM(ISNULL(d.ProgressiveFee, 0))				AS ProgressiveFee
		, SUM(ISNULL(d.CashoutTimes, 0))				AS CashoutTimes
		, SUM(ISNULL(d.CashoutTickets, 0))				AS CashoutTickets
		, SUM(ISNULL(d.CashoutValue, 0))				AS CashoutValue
		, SUM(ISNULL(d.TicketsPayout, 0))				AS TicketsPayout
		, SUM(ISNULL(d.CashoutCommission, 0))			AS CashoutCommission
		, SUM(ISNULL(d.BuyBackAmountAndComm, 0))		AS BuyBackAmountAndComm

		--Base on currency
		, CONVERT(MONEY, SUM(ISNULL(d.Turnover * e.Rate, 0)))					AS TurnoverBase
		, CONVERT(MONEY, SUM(ISNULL(d.ActualStake * e.Rate, 0)))				AS ActualStakeBase
		, CONVERT(MONEY, SUM(ISNULL(d.BuyBackAmount * e.Rate, 0)))				AS BuyBackAmountBase
		, CONVERT(MONEY, SUM(ISNULL(d.BuyBackAmountSB * e.Rate, 0)))			AS BuyBackAmountSportsbookBase
		, CONVERT(MONEY, SUM(ISNULL(d.BuyBackAmountBA * e.Rate, 0)))			AS BuyBackAmountBABase
		, CONVERT(MONEY, SUM(ISNULL(d.BettradeComm * e.Rate, 0)))				AS BettradeCommBase
		, CONVERT(MONEY, SUM(ISNULL(d.Winlost * e.Rate, 0)))					AS MemberWinLossBase
		, CONVERT(MONEY, SUM(ISNULL(d.WinningPrize * e.Rate, 0)))				AS WinningPrizeBase
		, CONVERT(MONEY, SUM(ISNULL(d.Contribution * e.Rate, 0)))				AS ContributionBase
		, CONVERT(MONEY, SUM(ISNULL(d.JackpotPrize* e.Rate, 0)))				AS JackpotPrizeBase
		, CONVERT(MONEY, SUM(ISNULL(d.Cashout * e.Rate, 0)))					AS CashoutBase
		, CONVERT(MONEY, SUM(ISNULL(d.PlayerComm * e.Rate, 0)))					AS MemberCommBase
		, CONVERT(MONEY, SUM(ISNULL(d.LicenseeWL * e.Rate, 0)))					AS LicenseeWLBase
		, CONVERT(MONEY, SUM(ISNULL(d.LicenseeChargeRate * e.Rate, 0)))			AS LicenseeChargeRateBase
		, CONVERT(MONEY, SUM(ISNULL(d.LicenseeComm * e.Rate, 0)))				AS LicenseeCommBase
		, CONVERT(MONEY, SUM(ISNULL(d.CashInShare * e.Rate, 0)))				AS CashInShareBase
		, CONVERT(MONEY, SUM(ISNULL(d.TipsAmount * e.Rate, 0)))					AS TipsAmountBase
		, CONVERT(MONEY, SUM(ISNULL(d.TipsAmountDue * e.Rate, 0)))				AS TipsAmountDueBase
		, CONVERT(MONEY, SUM(ISNULL(d.Company* e.Rate, 0)))						AS CompanyBase
		, CONVERT(MONEY, SUM(ISNULL(d.ProgressiveContribution * e.Rate, 0)))	AS ProgressiveContributionBase
		, CONVERT(MONEY, SUM(ISNULL(d.ProgressiveFee * e.Rate, 0)))				AS ProgressiveFeeBase
		, CONVERT(MONEY, SUM(ISNULL(d.ProgressivePayout * e.Rate, 0)))			AS ProgressivePayoutBase
		, CONVERT(MONEY, SUM(ISNULL(d.CashoutTimes * e.Rate, 0)))				AS CashoutTimesBase
		, CONVERT(MONEY, SUM(ISNULL(d.CashoutTickets * e.Rate, 0)))				AS CashoutTicketsBase
		, CONVERT(MONEY, SUM(ISNULL(d.CashoutValue * e.Rate, 0)))				AS CashoutValueBase
		, CONVERT(MONEY, SUM(ISNULL(d.TicketsPayout * e.Rate, 0)))				AS TicketsPayoutBase
		, CONVERT(MONEY, SUM(ISNULL(d.CashoutCommission * e.Rate, 0)))			AS CashoutCommissionBase
		, CONVERT(MONEY, SUM(ISNULL(d.BuyBackAmountAndComm * e.Rate, 0)))		AS BuyBackAmountAndCommBase
	FROM #Result d
	INNER JOIN #Exchange e ON d.Winlostdate = e.ExchangeDate AND d.CurrencyId = e.ExchangeId
	INNER JOIN sortedExchange se ON se.CurrencyCode = e.CurrencyCode
	WHERE se.RowNumber = 1 -- remove duplicate currency codes have different id
	GROUP BY se.ExchangeID,se.CurrencyCode, e.Rate, d.Game
	ORDER BY se.ExchangeID	

	DROP TABLE #Exchange
	DROP TABLE #Result
	DROP TABLE #DataWinloss3rd
END
GO