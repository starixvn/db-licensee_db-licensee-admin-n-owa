USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_ColossusBetWinloss]
	  @PartyIds				VARCHAR(4000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @BaseCurrencyName		VARCHAR(10)		= 'GBP'
	, @TicketType			VARCHAR(50) 	
WITH RECOMPILE
AS
/*  Created: 20160310@Bruce
	Task : Support settlement for Colossus Bets
	DB: DBEXT/bodb02
	Revisions:
		- 20160310@Bruce: Create SP
		- 20171219@Bruce: increase length for variables [#88197]
		- 20190321@Scofield: Implement Colossus Bets Freeplay [#89768]
	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	-- Commission share & Cash in share
	BEGIN
		DECLARE @CBShare AS TABLE (
			Rate			MONEY,
			MinAmount		MONEY,
			MaxAmount		MONEY,
			MinAmountEx		MONEY,
			MaxAmountEx		MONEY,
			BaseCurrencyId	SMALLINT,
			TypeId			SMALLINT,
			FromDate		DATETIME,
			ToDate			DATETIME
		)

		INSERT INTO @CBShare(Rate, MinAmount, MaxAmount, BaseCurrencyId, TypeId, FromDate, ToDate)
		SELECT	ci.Rate, MinAmount, MaxAmount, BaseCurrencyId, ChargeType,
				CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
				CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
		FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
		WHERE FromParty = 1 AND ProductID = 15 AND ChargeType IN (6,7) AND (
			@FromDate BETWEEN ci.FromDate AND ci.ToDate OR
			@ToDate BETWEEN ci.FromDate AND ci.ToDate OR
			ci.FromDate BETWEEN @FromDate AND @ToDate OR
			ci.ToDate BETWEEN @FromDate AND @ToDate
		)
		-- Product - 15: Colossus bet
		-- ChargeType: 6,7 are turnover and commission
	END

	BEGIN
		DECLARE @LaunchDateFilter AS TABLE (			
			PartyId			INT,
			FromDate		DATETIME,
			ToDate			DATETIME
		)

		INSERT INTO @LaunchDateFilter(PartyId, FromDate, ToDate)
		SELECT DISTINCT ci.partyid, ci.Fromdate,ci.Todate			
		FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'CB', 'OA', 1) ci 		
	END	

	SET @FromDate = (SELECT MIN(FromDate) FROM @CBShare)
	SET @ToDate = (SELECT MAX(ToDate) FROM @CBShare)

	-- Party List
	BEGIN
		DECLARE @PartyList AS TABLE (
			PartyId		INT,
			PartyName	VARCHAR(100),
			BranchName	VARCHAR(100),
			ParentId	INT
		)

		INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
		EXEC LA_PartyListSel
	END

	-- Get Winloss data
	BEGIN
		CREATE TABLE #TempData (
			LicenseeId		INT,
			PartyId			INT,
			rptDate			DATETIME,
			CurrencyId		INT,
			TotalTrans		INT,
			Turnover		MONEY,
			TurnoverForCommision MONEY,
			Prize			MONEY,
			CashOut			MONEY,
			CashInAmount	MONEY
		)

		INSERT INTO #TempData (LicenseeId, PartyId, rptDate, CurrencyId, TotalTrans, Turnover, TurnoverForCommision, Prize, CashOut, CashInAmount)
		SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(b.BetCount) TotalTrans,
				SUM(ISNULL(b.Turnover,0)) Turnover,
				SUM(CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN b.Turnover ELSE b.ExtraAmount END) TurnoverForCommision,
				SUM(ISNULL(b.WinPrizeAmount,0)) Prize,
				SUM(ISNULL(b.CashOutAmount,0)) CashOut,
				SUM(ISNULL(b.BuyBackAmount,0)) CashInAmount
		FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		LEFT JOIN dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
		INNER JOIN bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			ON	b.ProductID = 15 AND
				b.StatusId NOT IN (-1, 101, 102, 103) AND
				b.SiteID = (CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN p.OldRefID ELSE lb.LabelID END) AND
				b.rptDate BETWEEN @FromDate AND @ToDate
		INNER JOIN @LaunchDateFilter ld 
			ON  ld.PartyId = p.PartyID
				AND b.rptDate BETWEEN ld.FromDate AND ld.ToDate
		WHERE	b.CurrencyID <> 20 AND b.customercategory NOT IN (27, 28)
				AND p.PartyID IN (SELECT val FROM dbo.strSplit(@PartyIds, ','))
				AND ISNULL(b.TicketType, 0) IN (SELECT val FROM dbo.strSplit(@TicketType, ','))				
		GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId
	END

	-- Result data
	BEGIN
		CREATE TABLE #Result (
			PartyId			INT,
			PartyName		VARCHAR(100),
			ParentId		INT,
			ParentName		VARCHAR(100),
			WinLossDate		DATETIME,
			CurrencyName	VARCHAR(20),
			CurrencyId		INT,
			TotalTrans		INT,
			Turnover		MONEY,
			TurnoverForCommision MONEY,
			Prize			MONEY,
			CashOut			MONEY,
			CashInAmount	MONEY,
			Commission				MONEY,
			CashInShare				MONEY,
			AmountDueToColossusBet	MONEY,
			TurnoverBase		MONEY,
			PrizeBase			MONEY,
			CashOutBase			MONEY,
			CashInAmountBase	MONEY,
			CommissionBase				MONEY,
			CashInShareBase				MONEY,
			AmountDueToColossusBetBase	MONEY
		)
		
		INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, CurrencyName, TotalTrans, Turnover, TurnoverForCommision, Prize, CashOut, CashInAmount)
			SELECT 
				p.PartyId, 
				p.PartyName, 
				g.PartyId, 
				g.PartyName, 
				td.rptDate, 
				td.CurrencyId, 
				e.Code, 				
				td.TotalTrans, 			
				td.Turnover, 
				td.TurnoverForCommision,
				td.Prize, 
				td.CashOut, 
				td.CashInAmount
			FROM #TempData td 
				INNER JOIN bodb02.dbo.Exchange e ON td.CurrencyId = e.ExchangeID
				INNER JOIN @PartyList p ON td.PartyId = p.PartyID
				INNER JOIN @PartyList g ON p.ParentId = g.PartyId
	END

	-- Region: Grand total data
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)
	
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	DECLARE @GrandTotal AS TABLE(
		CurrencyName			VARCHAR(10),
		TotalTrans				INT,
		Turnover				MONEY,
		Prize					MONEY,
		CashOut					MONEY,
		CashInAmount			MONEY,
		Commission				MONEY,
		CashInShare				MONEY,
		AmountDueToColossusBet	MONEY
	)
	
	-- get commissionRate, cashinshareRate for every Period in @CBShare
	DECLARE @RateByPeriod AS TABLE (
		FromDate		DATETIME,
		ToDate			DATETIME,
		CommissionRate	FLOAT,
		CashInShareRate	FLOAT		
	)
	
	DECLARE @TotalByPeriod AS TABLE (
		FromDate		DATETIME,
		ToDate			DATETIME,
		TurnoverForCommision		MONEY,
		CashInAmount	MONEY		
	)
	
	SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
	
	INSERT INTO @TotalByPeriod(FromDate, Todate, TurnoverForCommision, CashInAmount)
	SELECT 
		s.FromDate, 
		s.ToDate, 
		SUM(td.TurnoverForCommision*e.BaseCurrencyRate),
		SUM(td.CashInAmount*e.BaseCurrencyRate)
	FROM #TempData td
	INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
	INNER JOIN (SELECT DISTINCT FromDate, ToDate FROM @CBShare) s ON td.rptDate BETWEEN s.FromDate AND s.ToDate
	GROUP BY s.FromDate, s.ToDate
		
	UPDATE s SET
		MinAmountEx = MinAmount * e.BaseCurrencyRate,
		MaxAmountEx = MaxAmount * e.BaseCurrencyRate
	FROM @CBShare s
	INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e ON s.BaseCurrencyId = e.ExchangeID AND e.ExchangeDate = s.ToDate
	
	INSERT INTO @RateByPeriod(FromDate, ToDate, CommissionRate, CashInShareRate)
	SELECT 
		t.FromDate,
		t.ToDate,
		cm.Rate, -- can be null
		cs.Rate
	FROM @TotalByPeriod t
	LEFT JOIN @CBShare cm ON cm.TypeId = 6  -- Commission share
		AND cm.FromDate = t.FromDate 
		AND cm.ToDate = t.ToDate
		AND t.TurnoverForCommision >= cm.MinAmountEx 
		AND t.TurnoverForCommision < cm.MaxAmountEx		 
	LEFT JOIN @CBShare cs ON cs.TypeId = 7 -- Cash in share
		AND cs.FromDate = t.FromDate
		AND cs.ToDate = t.ToDate
		AND t.CashInAmount >= cs.MinAmountEx 
		AND t.CashInAmount < cs.MaxAmountEx 
	
	-- end get commissionRate, cashinshareRate for every Period in @CBShare		
	
	-- Update Commission, CashInShare, AmountDueToColossusBet for #Result
	UPDATE r
	SET
		Commission = r.TurnoverForCommision * rbp.CommissionRate,
		CashInShare = r.CashInAmount * rbp.CashInShareRate,
		AmountDueToColossusBet = Turnover - Prize - CashOut - r.TurnoverForCommision * rbp.CommissionRate - r.CashInAmount * rbp.CashInShareRate		
	FROM #Result r
	INNER JOIN @RateByPeriod rbp ON r.WinLossDate BETWEEN rbp.FromDate AND rbp.ToDate	
	-- End Update Commission, CashInShare, AmountDueToColossusBet for #Result
	
	-- Grand total data
	WHILE EXISTS (SELECT TOP 1 * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,Prize,CashOut,CashInAmount, Commission, CashInShare, AmountDueToColossusBet)
		SELECT	@tempCurrency,
				SUM(r.TotalTrans),
				SUM(r.Turnover*e.BaseCurrencyRate),
				SUM(r.Prize*e.BaseCurrencyRate),
				SUM(r.CashOut*e.BaseCurrencyRate),
				SUM(r.CashInAmount*e.BaseCurrencyRate),
				SUM(r.Commission*e.BaseCurrencyRate),
				SUM(r.CashInShare*e.BaseCurrencyRate),
				SUM(r.AmountDueToColossusBet*e.BaseCurrencyRate)
		FROM #Result r
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency		
	END
	-- End Grand total data

	SELECT	PartyId,
			PartyName,
			ParentId,
			ParentName,
			WinLossDate,
			CASE WHEN CurrencyName='VND' THEN 'INH' ELSE CurrencyName END CurrencyName,
			TotalTrans,
			ISNULL(Turnover, 0) Turnover,
			ISNULL(Prize, 0) Prize,
			ISNULL(CashOut, 0) CashOut,
			ISNULL(CashInAmount, 0) CashInAmount,
			ISNULL(Commission, 0) Commission,
			ISNULL(CashInShare, 0) CashInShare,
			ISNULL(AmountDueToColossusBet, 0) AmountDueToColossusBet,
			ISNULL(Turnover * e.BaseCurrencyRate, 0) TurnoverBase, 
		    ISNULL(Prize * e.BaseCurrencyRate, 0) PrizeBase, 
			ISNULL(CashOut * e.BaseCurrencyRate, 0) CashOutBase, 
			ISNULL(CashInAmount * e.BaseCurrencyRate, 0) CashInAmountBase,
			ISNULL(Commission * e.BaseCurrencyRate, 0) CommissionBase,
			ISNULL(CashInShare * e.BaseCurrencyRate, 0) CashInShareBase,
			ISNULL(AmountDueToColossusBet * e.BaseCurrencyRate, 0) AmountDueToColossusBetBase	
	FROM #Result r
	INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate

	SELECT	CurrencyName,
			ISNULL(AmountDueToColossusBet,0) AmountDueToColossusBet,
			ISNULL(TotalTrans,0) TotalTrans,
			ISNULL(Turnover,0) Turnover,
			ISNULL(Prize,0) Prize,
			ISNULL(CashOut,0) CashOut,
			ISNULL(Commission,0) Commission,
			ISNULL(CashInShare,0) CashInShare,
			ISNULL(CashInAmount,0) CashInAmount
	FROM @GrandTotal

	DROP TABLE #TempData
	DROP TABLE #Result
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_ColossusBetWinloss] TO [vnteam]
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_ColossusBetWinloss] TO bodbAdminNet
GO