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
	, @ProductCodes			VARCHAR(50)
	, @CurrencyId			INT				= 0
	, @BaseCurrencyName		VARCHAR(3)
	, @ExcludeTest			BIT
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
	
	CREATE TABLE #SumData(
		RptDate				DATE,
		SiteId				INT,
		ProductId			INT,
		BetTypeRef			INT,
		CurrencyId			INT,
		BetCount			BIGINT,
		Turnover			MONEY,
		Winloss				MONEY)
	
	CREATE TABLE #AmountDueToMicrogaming (BettypeRef INT, AmountDueTo MONEY)

	CREATE TABLE #ExchangeRate(ExchangeDate DATE, ExchangeId INT, Rate FLOAT)

	INSERT INTO #ExchangeRate (ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	CREATE TABLE #Parties (PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)

	INSERT INTO #Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel

	CREATE TABLE #GameTypes (ProductId INT, BettypeRef INT, BettypeId INT, GameTypeName VARCHAR(100))

	INSERT INTO #GameTypes (ProductId, BettypeId, BettypeRef)
	SELECT CASE WHEN sp.SporttypeRef = 203 THEN 14
				WHEN sp.SporttypeRef = 205 THEN 17 ELSE 0 END AS ProductId, sp.Bettype, pr.BettypeRef
	FROM bodb_licensee.dbo.Sport_Bettype_Reference sp WITH (NOLOCK)
		LEFT JOIN bodb_licensee.dbo.LA_Product3rdSub pr WITH (NOLOCK) ON sp.BettypeRef = pr.BettypeRef
	GROUP BY sp.SporttypeRef, sp.Bettype, pr.BettypeRef

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
		BettypeRef			INT,
		Rate				MONEY,
		FromDate			DATETIME,
		ToDate				DATETIME)

	INSERT INTO #PartyChargeInfo (ChargeId, PartyId, PartyName, ParentId, LicenseeId, ProductID, BettypeRef, Rate, Fromdate, Todate)
	SELECT DISTINCT ci.ChargeID, ci.PartyID, p.PartyName, p.ParentId, LicenseeID, ci.ProductID, ci.Bettype, DI_Rate, ci.Fromdate, ci.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo_xtest(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @ExcludeTest) ci LEFT JOIN #Parties p ON ci.PartyID = p.PartyId
	
	INSERT INTO #SumData (RptDate, SiteId, ProductId, BetTypeRef, CurrencyId, BetCount, Turnover, Winloss)
	SELECT st.RptDate, SiteId, st.ProductId, st.BettypeRef, CurrencyId, SUM(st.BetCount), SUM(st.Turnover), SUM(st.Winloss)
	FROM (	
		SELECT rpt.RptDate, SiteId, gt.ProductId, gt.BettypeRef, CurrencyId, StatusId, 
			SUM(ISNULL(BetCount, 0)) AS BetCount, 
			SUM(ISNULL(Turnover, 0)) AS Turnover
			, SUM(ISNULL(Winloss, 0)) AS Winloss
		FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT rpt
			INNER JOIN #GameTypes gt ON rpt.BetTypeId = gt.BettypeId
		WHERE rpt.RptDate BETWEEN @FromDate AND @ToDate
			  AND rpt.SiteId IN (SELECT DISTINCT LicenseeId FROM #PartyChargeInfo)
			  AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND CurrencyID = @CurrencyId))
			  AND (@ExcludeTest = 0 OR (@ExcludeTest = 1 AND CurrencyID <> 20))
			  AND StatusId NOT IN (-1, 101, 102, 103)
		GROUP BY rpt.RptDate, SiteId, gt.ProductId, gt.BettypeRef, CurrencyId, StatusId
		) st
	GROUP BY st.RptDate, SiteId, st.ProductId, st.BettypeRef, CurrencyId

	CREATE TABLE #ProductChargeInfo (ParentId INT, ProductId INT, BettypeRef INT, ChargeType INT, Rate MONEY, MinAmount MONEY, MaxAmount MONEY)

	INSERT INTO #ProductChargeInfo (ParentId, ProductId, BettypeRef, ChargeType, Rate, MinAmount, MaxAmount)
	SELECT DISTINCT a.FromParty, a.ProductId, a.BettypeRef, a.ChargeType, a.Rate,
		CASE WHEN a.ChargeType = 4 THEN a.MinAmount * er.Rate ELSE 0 END MinAmount,
		CASE WHEN a.ChargeType = 4 THEN a.MaxAmount * er.Rate ELSE 0 END MaxAmount
	FROM (SELECT DISTINCT tp.ProductId, ci2.ChargeID, cis.FromParty, cis.BettypeRef, cis.ChargeType, cis.Rate, cis.MinAmount, cis.MaxAmount, cis.BaseCurrencyId
	FROM #PartyChargeInfo tp
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON tp.ChargeId = ci.ChargeID
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo ci2 WITH (NOLOCK) ON ci.ToParty = ci2.FromParty AND ci2.ProductID = tp.ProductID
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfoSub cis WITH (NOLOCK) ON ci2.ChargeID = cis.ChargeIdRef
		WHERE tp.ChargeId > 0) a
		LEFT JOIN #ExchangeRate er ON a.BaseCurrencyId = er.ExchangeID
		
	INSERT INTO #Result (ParentId, PartyID, PartyName, BettypeRef, GameTypeName, ProductId, CurrencyId, Turnover, CustomerWinLoss, LicenseeWinLoss, AmountDueToCompany, TotalTrans, AmountDueToProduct)
	SELECT pci.ParentId, pci.PartyId, pci.PartyName, gt.BettypeRef, gt.GameTypeName, d.ProductId, d.CurrencyId,
		SUM(Turnover * er.Rate) AS Turnover,
		SUM(CustomerWinLoss * er.Rate) AS CustomerWinLoss,
		-SUM(CustomerWinLoss * er.Rate) AS LicenseeWinLoss,
		-SUM(CustomerWinLoss * er.Rate * pci.Rate) AS AmountDueToCompany,
		SUM(TotalTrans) AS TotalTrans,
		-SUM(CustomerWinLoss * er.Rate) AS AmountDueToProduct
	FROM (SELECT rd.SiteId, rd.RptDate, rd.CurrencyId, rd.BetTypeRef, pci.PartyId, pci.ProductId, SUM(rd.Winloss) AS CustomerWinLoss, SUM(rd.Turnover) as Turnover, SUM(rd.BetCount) AS TotalTrans
			FROM #SumData rd
				INNER JOIN (SELECT DISTINCT LicenseeId, BettypeRef, PartyId, ProductId FROM #PartyChargeInfo) pci 
				ON rd.SiteId = pci.LicenseeID AND rd.BetTypeRef = pci.BettypeRef AND rd.ProductId = pci.ProductId
			GROUP BY	rd.RptDate, rd.SiteId, rd.CurrencyID, rd.BettypeRef, pci.PartyId, pci.ProductId) d
		INNER JOIN #PartyChargeInfo pci ON d.SiteId = pci.LicenseeID AND d.BettypeRef = pci.BettypeRef AND pci.ProductId = d.ProductId
		INNER JOIN #ExchangeRate er ON d.CurrencyId = er.ExchangeID AND d.RptDate = er.ExchangeDate
		LEFT JOIN (SELECT DISTINCT BettypeRef, GameTypeName, ProductId FROM #GameTypes) gt ON d.BettypeRef = gt.BettypeRef AND gt.ProductId = d.ProductId
	WHERE d.RptDate BETWEEN pci.Fromdate AND pci.Todate
	GROUP BY gt.GameTypeName, gt.BettypeRef, pci.ParentId, pci.PartyId, pci.PartyName, d.ProductId, d.CurrencyId

	DROP TABLE #GameTypes
	DROP TABLE #ExchangeRate
	DROP TABLE #Parties
	DROP TABLE #SumData
	DROP TABLE #PartyChargeInfo

	INSERT INTO #AmountDueToMicrogaming ([@GroupWinloss].BettypeRef, AmountDueTo)
	SELECT BettypeRef, SUM(oa.kq) AS AmtDueto
	FROM (SELECT BettypeRef, SUM(AmountDueToProduct) AS GroupWinloss
		  FROM #Result
		  GROUP BY BettypeRef) d
	OUTER APPLY (
		SELECT
		CASE WHEN (ChargeType = 4 AND GroupWinloss BETWEEN MinAmount AND MaxAmount) THEN CASE WHEN MinAmount < 0 THEN (GroupWinloss - 0) * Rate 
																							  WHEN MinAmount >=0 THEN (GroupWinloss - MinAmount) * Rate ELSE 0 END
																					ELSE 0 END +
		CASE WHEN (ChargeType = 4 AND GroupWinloss > MaxAmount) THEN CASE WHEN MinAmount < 0 THEN (MaxAmount - 0) * Rate
																		  WHEN MinAmount >= 0 THEN (MaxAmount - MinAmount) * Rate ELSE 0 END
																ELSE 0 END +
		CASE WHEN (ChargeType = 1) THEN GroupWinloss * Rate ELSE 0 END AS kq
		FROM (SELECT BettypeRef, ChargeType, Rate, MinAmount, MaxAmount FROM #ProductChargeInfo GROUP BY BettypeRef, ChargeType, Rate, MinAmount, MaxAmount) pci
		WHERE BettypeRef = d.BettypeRef) oa
	GROUP BY BettypeRef
		
	UPDATE r SET r.AmountDueToProduct = g.AmountDueTo FROM #Result r
	LEFT JOIN #AmountDueToMicrogaming g ON r.BettypeRef = g.BettypeRef
	
	SELECT re.BettypeRef AS GameTypeId, re.GameTypeName, re.PartyId, re.PartyName, re.ProductId, pr.ProductName, re.CurrencyId, ex.Code AS CurrencyName,
		SUM(re.TotalTrans) AS TotalTrans,
		SUM(re.Turnover) AS Turnover,
		SUM(re.CustomerWinLoss) AS CustomerWinLoss,
		SUM(re.LicenseeWinLoss) AS LicenseeWinLoss,
		ISNULL(re.AmountDueToCompany, 0) AS AmountCompany,
		ISNULL(re.AmountDueToProduct, 0) AS AmountProduct
	FROM #Result re
	LEFT JOIN dbo.Exchange ex WITH (NOLOCK) ON re.CurrencyId = ex.exchangeid
	LEFT JOIN #Products pr WITH (NOLOCK) ON re.ProductId = pr.ProductId
	GROUP BY	re.BettypeRef, re.GameTypeName, re.PartyId, re.PartyName, re.ProductId, pr.ProductName, re.CurrencyId, ex.Code, re.AmountDueToCompany, re.AmountDueToProduct
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