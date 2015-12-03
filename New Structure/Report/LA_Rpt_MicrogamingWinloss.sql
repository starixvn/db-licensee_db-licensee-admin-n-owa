USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_MicrogamingWinloss] 
	  @PartyIds				VARCHAR(1000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME	
	, @ProductCodes			VARCHAR(6)
	, @CurrencyId			INT				= 0
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
	, @DrawFilter			SMALLINT		= 1
	, @ExcludeTest			BIT				= 1
WITH RECOMPILE
AS
/*  Created: 20150804@Florent		
	Task : Report - Microgaming Casino GMT - 4
	DB: DB052.bodb02
	Modified:
	- Feature 44698: Add Microgaming RNG and change data flow.
	Revisions:  			
	Param's Explanation:
		+ @PartyIDs	: a string of list PartyID, separate by ','
		+ @Currency	:  0 - All Currencies
		+ @DrawFilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
		+ @excludeTest: add/remove currency UUS
		+ @ProductCodes	: Products code :
				. MGCLC - Microgaming Live Casino
				. MGCRNG - Microgaming RNG Casino
		+ @BaseCurrencyName: GBP, CNY, USD, EUR, MYR  						
*/
SET NOCOUNT ON
BEGIN
			
	CREATE TABLE #Result (
		BettypeRef			INT, 
		GameTypeName		VARCHAR(20),
		PartyId				INT, 
		PartyName			VARCHAR(20), 
		CurrencyId			INT, 
		CurrencyName		VARCHAR(20),
		ProductId			INT,
		ProductName			VARCHAR(20),
		ParentId			INT, 
		TotalTrans			INT,
		Turnover			MONEY,
		CustomerWinLoss		MONEY,
		LicenseeWinLoss		MONEY,
		AmountDueToCompany	MONEY,
		AmountDueToProduct	MONEY)

	CREATE TABLE #AmountDueToMicrogaming (ParentId INT, BettypeRef INT, AmountDueTo MONEY)

	CREATE TABLE #ExchangeRate(ExchangeDate DATE, ExchangeId INT, Rate FLOAT)

	INSERT INTO #ExchangeRate (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	CREATE TABLE #Parties (PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)

	INSERT INTO #Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel

	CREATE TABLE #GameTypes (BettypeRef INT, BettypeId INT, GameTypeName VARCHAR(100))

	INSERT INTO #GameTypes (BettypeId, BettypeRef, GameTypeName)
	SELECT sp.Bettype, pr.BettypeRef, pr.ProductName
	FROM bodb_licensee.dbo.Sport_Bettype_Reference sp WITH (NOLOCK)
		LEFT JOIN bodb_licensee.dbo.LA_Product3rdSub pr WITH (NOLOCK) ON sp.BettypeRef = pr.BettypeRef

	UPDATE #GameTypes
	SET GameTypeName = 'Generic'
	WHERE BettypeRef = 2001
	UPDATE #GameTypes
	SET GameTypeName = 'Branded'
	WHERE BettypeRef = 2005

	CREATE TABLE #Products(ProductId INT,ProductName VARCHAR(50))

	INSERT INTO #Products (ProductId, ProductName)
	SELECT ProductId, ProductName
	FROM bodb_licensee.dbo.Product3rd
	WHERE Productid IN (14, 17) -- 14 = MGC Live Casino, 17 = MGC RNG Casino --

	UPDATE #Products
	SET ProductName = 'Live Casino'
	WHERE ProductId = 14

	UPDATE #Products
	SET ProductName = 'RNG Casino'
	WHERE ProductId = 17
	
	CREATE TABLE #PartyChargeInfo (
		ChargeId			INT,
		PartyId				INT,
		PartyName			VARCHAR(100),
		ParentId			INT,
		LicenseeId			INT,
		ProductId			INT,
		BettypeId			INT,
		Rate				MONEY,
		FromDate			DATETIME,
		ToDate				DATETIME)

	INSERT INTO #PartyChargeInfo (ChargeId, PartyId, PartyName, ParentId, LicenseeId, ProductID, BettypeId, Rate, Fromdate, Todate)
	SELECT DISTINCT ci.ChargeID, ci.PartyID, p.PartyName, p.ParentId, LicenseeID, ci.ProductID, ci.Bettype, DI_Rate, ci.Fromdate, ci.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @ExcludeTest) ci LEFT JOIN #Parties p ON ci.PartyID = p.PartyId

	CREATE TABLE #ProductChargeInfo (ParentId INT, BettypeRef INT, ChargeType INT, Rate MONEY, MinAmount MONEY, MaxAmount MONEY)
	
	INSERT INTO #ProductChargeInfo (ParentId, BettypeRef, ChargeType, Rate, MinAmount, MaxAmount)
	SELECT DISTINCT a.FromParty, a.BettypeRef, a.ChargeType, a.Rate,
		CASE WHEN a.ChargeType = 4 THEN a.MinAmount * er.Rate ELSE 0 END MinAmount,
		CASE WHEN a.ChargeType = 4 THEN a.MaxAmount * er.Rate ELSE 0 END MaxAmount
	FROM (SELECT DISTINCT ci2.ChargeID, cis.FromParty, cis.BettypeRef, cis.ChargeType, cis.Rate, cis.MinAmount, cis.MaxAmount, cis.BaseCurrencyId
	FROM #PartyChargeInfo tp
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON tp.ChargeId = ci.ChargeID
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo ci2 WITH (NOLOCK) ON ci.ToParty = ci2.FromParty AND ci2.ProductID = tp.ProductID
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfoSub cis WITH (NOLOCK) ON ci2.ChargeID = cis.ChargeIdRef) a
		LEFT JOIN #ExchangeRate er ON a.BaseCurrencyId = er.ExchangeID
		
	INSERT INTO #Result (ParentId, PartyID, PartyName, BettypeRef, GameTypeName, ProductId, CurrencyId, Turnover, CustomerWinLoss, LicenseeWinLoss, AmountDueToCompany, TotalTrans)
	SELECT pci.ParentId, pci.PartyId, pci.PartyName, gt.BettypeRef, gt.GameTypeName, d.ProductId, d.CurrencyId,
		SUM(Turnover * er.Rate) AS Turnover,
		SUM(CustomerWinLoss * er.Rate) AS CustomerWinLoss,
		-SUM(CustomerWinLoss * er.Rate) AS LicenseeWinLoss,
		-SUM((CustomerWinLoss * pci.Rate) * er.Rate) AS AmountDueToCompany,
		SUM(TotalTrans) AS TotalTrans
	FROM (SELECT rd.SiteId, rd.RptDate, rd.CurrencyId, rd.BetTypeId, pci.PartyId, pci.ProductId,
				SUM(ISNULL(rd.Turnover, 0) * CASE WHEN @DrawFilter IN (2, 3) THEN CASE
												  WHEN rd.StatusId = 111 THEN 0
												  WHEN rd.StatusId IN (114, 115) THEN 0.5 ELSE 1
												  END ELSE 1 END) AS Turnover,
				SUM(ISNULL(rd.Winloss, 0)) CustomerWinLoss,
				SUM(ISNULL(rd.BetCount, 0) * CASE WHEN @DrawFilter = 2 AND rd.StatusId = 111 THEN 0 ELSE 1 END) AS TotalTrans
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT rd WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT LicenseeId, BettypeId, PartyId, PartyName, ProductId FROM #PartyChargeInfo) pci ON rd.SiteId = pci.LicenseeID AND rd.BetTypeId = pci.BettypeId
			WHERE rd.RptDate BETWEEN @FromDate AND @ToDate
				AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND rd.CurrencyID = @CurrencyId))
				AND (@ExcludeTest = 0 OR (@ExcludeTest = 1 AND rd.CurrencyID <> 20))
				AND rd.StatusId NOT IN (-1, 101, 102, 103)
			GROUP BY	rd.RptDate, rd.SiteId, rd.CurrencyID, rd.BetTypeId, pci.PartyId, pci.PartyName, pci.ProductId) d
		INNER JOIN #PartyChargeInfo pci ON d.SiteId = pci.LicenseeID AND d.BetTypeId = pci.BettypeId
		INNER JOIN #ExchangeRate er ON d.CurrencyId = er.ExchangeID AND d.RptDate = er.ExchangeDate
		LEFT JOIN #GameTypes gt ON d.BetTypeId = gt.BettypeId
	WHERE d.RptDate BETWEEN pci.Fromdate AND pci.Todate
	GROUP BY gt.GameTypeName, gt.BettypeRef, pci.ParentId, pci.PartyId, pci.PartyName, d.ProductId, d.CurrencyId
	
	DROP TABLE #GameTypes
	DROP TABLE #PartyChargeInfo
	DROP TABLE #ExchangeRate
	DROP TABLE #Parties
	
	INSERT INTO #AmountDueToMicrogaming ([@GroupWinloss].BettypeRef, ParentID, AmountDueTo)
	SELECT BettypeRef, ParentId, SUM(CASE WHEN oa.kq > 0 THEN oa.kq ELSE 0 END) AS AmtDueto
	FROM (SELECT BettypeRef, ParentId, SUM(LicenseeWinLoss) AS GroupWinloss
		  FROM #Result
		  GROUP BY BettypeRef, ParentId) d
	OUTER APPLY (
		SELECT
		CASE WHEN (ChargeType = 4 AND GroupWinloss BETWEEN MinAmount AND ISNULL(MaxAmount, 100000000000)) THEN (GroupWinloss - MinAmount) * Rate ELSE 0 END +
		CASE WHEN (ChargeType = 4 AND GroupWinloss > MaxAmount) THEN (MaxAmount - MinAmount) * Rate ELSE 0 END +
		CASE WHEN (ChargeType = 1) THEN GroupWinloss * Rate ELSE 0 END AS kq
		FROM #ProductChargeInfo
		WHERE ParentId = d.ParentId AND BettypeRef = d.BettypeRef) oa
	GROUP BY	BettypeRef, ParentId
	ORDER BY BettypeRef, ParentId
	
	UPDATE r SET r.AmountDueToProduct = g.AmountDueTo FROM #Result r
	LEFT JOIN #AmountDueToMicrogaming g ON r.ParentId = g.ParentID AND r.BettypeRef = g.BettypeRef
	
	SELECT re.BettypeRef AS GameTypeId, re.GameTypeName, re.PartyId, re.PartyName, re.ProductId, pr.ProductName, re.CurrencyId, ex.Code AS CurrencyName,
		SUM(re.TotalTrans) AS TotalTrans,
		SUM(re.Turnover) AS Turnover,
		SUM(re.CustomerWinLoss) AS CustomerWinLoss,
		SUM(re.LicenseeWinLoss) AS LicenseeWinLoss,
		SUM(re.AmountDueToCompany) AS AmountCompany,
		re.AmountDueToProduct AS AmountProduct
	FROM #Result re
	LEFT JOIN dbo.Exchange ex WITH (NOLOCK) ON re.CurrencyId = ex.exchangeid
	LEFT JOIN #Products pr WITH (NOLOCK) ON re.ProductId = pr.ProductId
	GROUP BY	re.BettypeRef, re.GameTypeName, re.PartyId, re.PartyName, re.ProductId, pr.ProductName, re.CurrencyId, ex.Code, re.AmountDueToProduct
	ORDER BY re.BettypeRef

	DROP TABLE #Result
	DROP TABLE #ProductChargeInfo
	DROP TABLE #AmountDueToMicrogaming
	DROP TABLE #Products
END

GO

SET QUOTED_IDENTIFIER OFF
GO
SET ANSI_NULLS ON
GO


GO
 
 GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_MicrogamingWinloss] TO [vnteam]
GO
 
 GRANT EXECUTE ON [dbo].[LA_Rpt_MicrogamingWinloss] TO [bodbAdminNet]
GO