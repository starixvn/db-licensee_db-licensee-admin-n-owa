ALTER PROCEDURE [dbo].[GEN_rptBettingByProduct] (
	@date DATE,
	@date2 DATE = NULL
	)
AS
/*  Created: 20150710@Victor
    Task : Generate data for rpt_BettingByProduct
    DB: DBLIC/bodb_LicenseeReport  
    Param's Explanation:   
    
*/

BEGIN  
	IF @date2 IS NULL SET @date2 = @date
	SET @date2 = DATEADD(day,1,@date2)

	DELETE FROM dbo.rpt_BettingByProduct
	WHERE rptDate>=@date AND rptDate<@date2

	DECLARE @BettypeProductMapping TABLE (Bettype INT, ProductID INT)
	
	INSERT INTO @BettypeProductMapping (Bettype, ProductID)
	SELECT Bettype, ProductId 
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0,'SB,NG,VS,RB,LC,CS,KN,BG,MGC')

	-- Import data from rpt_Betting / rpt_Betting_BA
	INSERT INTO [dbo].[rpt_BettingByProduct]
			([rptDate]
			,[SiteID]
			,[ProductID]
			,[Bettype]
			,[CurrencyId]
			,[StatusId]
			,[CustomerCategory]
			,[GrossWL]
			,[MemberWL]
			,[Turnover]
			,[BetCount]
			,[CommissionA]
			,[CommissionP]
			,[BuyBackAmount])
	SELECT
		[rptDate]
		,[SiteID]
		, bt.ProductID
		,CASE WHEN bt.ProductID IN (13,14) THEN b.[Bettype] ELSE -1 END [Bettype]
		,[CurrencyId]
		,Status [StatusId]
		,ISNULL([CustomerCategory],-1)
		,ISNULL(SUM(WinLossA),0) [GrossWL]
		,ISNULL(SUM(WinLoss),0) [MemberWL]
		,ISNULL(SUM([Turnover]),0) [Turnover]
		,ISNULL(SUM([BetCount]),0) [BetCount]
		,ISNULL(SUM([CommissionA]),0) [CommissionA]
		,ISNULL(SUM([CommissionP]),0) [CommissionP]
		,ISNULL(SUM([BuyBackAmount]),0) [BuyBackAmount]
	FROM bodb_licensee.dbo.rpt_Betting b WITH (NOLOCK)
		INNER JOIN @BettypeProductMapping bt ON b.Bettype = bt.Bettype
	WHERE rptDate >= @date AND rptDate < @date2
		AND b.Status IN (111,112,113,114,115)
		AND [CurrencyID] <> 20    
	GROUP BY [rptDate]
			,[SiteID]
			, bt.ProductID
			,CASE WHEN bt.ProductID IN (13,14) THEN b.[Bettype] ELSE -1 END 
			,[CurrencyId]
			,Status
			,ISNULL([CustomerCategory],-1)
	UNION ALL
	SELECT
		[rptDate]
		,[SiteID]
		, 3
		,CASE WHEN bt.ProductID IN (13,14) THEN b.[Bettype] ELSE -1 END [Bettype]
		,[CurrencyId]
		,Status [StatusId]
		,ISNULL([CustomerCategory],-1)
		,ISNULL(SUM(WinLossA),0) [GrossWL]
		,ISNULL(SUM(WinLoss),0) [MemberWL]
		,ISNULL(SUM([Turnover]),0) [Turnover]
		,ISNULL(SUM([BetCount]),0) [BetCount]
		,ISNULL(SUM([CommissionA]),0) [CommissionA]
		,ISNULL(SUM([CommissionP]),0) [CommissionP]
		,ISNULL(SUM([BuyBackAmount]),0) [BuyBackAmount]
	FROM bodb_licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
		INNER JOIN @BettypeProductMapping bt ON b.Bettype = bt.Bettype
	WHERE rptDate >= @date AND rptDate < @date2
		AND b.Status IN (111,112,113,114,115)
		AND [CurrencyID] <> 20    
	GROUP BY [rptDate]
			,[SiteID]
			, bt.ProductID
			,CASE WHEN bt.ProductID IN (13,14) THEN b.[Bettype] ELSE -1 END 
			,[CurrencyId]
			,Status
			,ISNULL([CustomerCategory],-1)

	-- Collect data of 3rd party products
	CREATE TABLE #tmpData (rptDate DATE, CustID INT, ProductID INT, CurrencyId INT, Winlost MONEY, Turnover MONEY, BetCount INT, PlayerComm MONEY)

	-- GD, VG
	INSERT INTO #tmpData (rptDate, CustID, ProductID, CurrencyId, Winlost, Turnover, BetCount, PlayerComm)
	SELECT Winlostdate, Custid, ProductId, Currency, Winlost, Turnover, BetCount, 0 AS PlayerComm
	FROM dbo.rptDepWinlost_ThirdParty WITH (NOLOCK)
	WHERE Winlostdate >= @date AND Winlostdate < @date2
		AND [Currency] <> 20

	-- AGCS
	INSERT INTO #tmpData (rptDate, CustID, ProductID, CurrencyId, Winlost, Turnover, BetCount, PlayerComm)
	SELECT Winlostdate, Custid, 10 AS ProductId, Currency, SUM(Winlost), SUM(Turnover), SUM(BetCount), SUM(PlayerComm)
	FROM DBRPT.bodb_report.dbo.rptDepWinlost_AGCasino WITH (NOLOCK)
	WHERE Winlostdate >= @date AND Winlostdate < @date2
		AND [Currency] <> 20
	GROUP BY Winlostdate, Custid, Currency

	-- PTCS
	INSERT INTO #tmpData (rptDate, CustID, ProductID, CurrencyId, Winlost, Turnover, BetCount, PlayerComm)
	SELECT Winlostdate, Custid, 9 AS ProductId, Currency, Winlost, Turnover, BetCount, PlayerComm
	FROM DBRPT.bodb_report.dbo.rptDepWinlost_PlaytechCS WITH (NOLOCK)
	WHERE Winlostdate >= @date AND Winlostdate < @date2
		AND [Currency] <> 20

	INSERT INTO [dbo].[rpt_BettingByProduct]
			([rptDate]
			,[SiteID]
			,[ProductID]
			,[Bettype]
			,[CurrencyId]
			,[StatusId]
			,[CustomerCategory]
			,[GrossWL]
			,[MemberWL]
			,[Turnover]
			,[BetCount]
			,[CommissionA]
			,[CommissionP]
			,[BuyBackAmount])
	SELECT td.rptDate
		, ISNULL(site.SiteID,-1) AS SiteId
		, td.productId
		, -1 AS bettype
		, td.CurrencyId
		, CASE 
			WHEN td.Winlost > 0 THEN 112
			WHEN td.Winlost < 0 THEN 113
			ELSE 111
		  END AS StatusId
		, -1 AS CustomerCategory
		, 0 AS GrossWL
		, td.Winlost
		, td.Turnover
		, td.BetCount
		, 0 AS CommissionA
		, PlayerComm AS CommissionP
		, 0 AS BuyBackAmount
	FROM #tmpData td WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON c.Custid = td.CustID AND c.roleid = 1
		LEFT JOIN bodb02.dbo.customer ag WITH (NOLOCK) ON c.recommend = ag.custid AND ag.roleid = 2
	    LEFT JOIN bodb02.dbo.Site ibcsite WITH (NOLOCK) ON ag.site=ibcsite.site
	    LEFT JOIN bodb_licensee.dbo.view_site_list [site] WITH (NOLOCK) ON ibcsite.siteid=site.IbcSiteID

	DROP TABLE #tmpData
END

GO