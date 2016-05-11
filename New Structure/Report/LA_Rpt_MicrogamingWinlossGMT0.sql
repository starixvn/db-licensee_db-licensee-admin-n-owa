USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_MicrogamingWinlossGMT0] 
	  @PartyIds				VARCHAR(1000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME	
	, @ProductCodes			VARCHAR(50)
	, @BaseCurrencyName		VARCHAR(3)			= 'GBP'
WITH RECOMPILE
AS
/*  Created: 20150804@Florent		
	Task : Report - Microgaming Casino GMT + 0
	DB: DB052.bodb02
	Modified:
	- Feature 44698.
	- Feature 54152.
	Revisions:
	- 20151201@Forrest: Add Microgaming RNG and change data flow.
	- 20160316@Forrest: Change SporttypeRef to Sporttype.
	- 20160428@Forrest: Update Entire Report	  			
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
	--Region Parties

	DECLARE @Parties AS TABLE  (PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)

	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel

	--Endregion
	
	--Region Game Type

	DECLARE @GameTypes AS TABLE (ProductId INT, BettypeRef INT, BettypeId INT, GameTypeName VARCHAR(100))

	INSERT INTO @GameTypes (ProductId, BettypeId, BettypeRef)
	SELECT CASE WHEN sp.Sporttype = 203 THEN 14
				WHEN sp.Sporttype = 205 THEN 17 ELSE 0 END AS ProductId, sp.Bettype, pr.BettypeRef
	FROM bodb_licensee.dbo.Sport_Bettype_Reference sp WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.LA_Product3rdSub pr WITH (NOLOCK) ON sp.BettypeRef = pr.BettypeRef
	GROUP BY sp.Sporttype, sp.Bettype, pr.BettypeRef

	UPDATE @GameTypes
	SET GameTypeName = 'Generic'
	WHERE BettypeRef = 2001
	UPDATE @GameTypes
	SET GameTypeName = 'Branded'
	WHERE BettypeRef = 2005

	--Endregion
	
	--Region Charge Info

	DECLARE @PartyChargeInfo AS TABLE (
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

	INSERT INTO @PartyChargeInfo (ChargeId, PartyId, PartyName, ParentId, LicenseeId, ProductID, BettypeRef, Rate, Fromdate, Todate)
	SELECT DISTINCT ci.ChargeID, ci.PartyID, p.PartyName, p.ParentId, LicenseeID, ci.ProductID, ci.Bettype, DI_Rate, ci.Fromdate, ci.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci LEFT JOIN @Parties p ON ci.PartyID = p.PartyId

	--Endregion
	
	--Region Base Currency Data
	DECLARE @tempCurrencyId INT
	DECLARE @tempCurrencyCode VARCHAR(3)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)

	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC bodb_licensee..LA_SelBaseCurrency

	--Endregion
	
	--Region Product Charge Info

	DECLARE @ProductChargeInfo AS TABLE (
			ParentId		INT, 
			ProductId		INT, 
			BettypeRef		INT, 
			ChargeType		INT, 
			Rate			MONEY, 
			MinAmount		MONEY, 
			MaxAmount		MONEY, 
			CurrencyId		INT, 
			CurrencyCode	VARCHAR(3))

	--Endregion
	
	-- Region: Exchange

	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeID INT, CurrencyCode	VARCHAR(10), Rate FLOAT)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate	
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	UPDATE #Exchange 
	SET CurrencyCode = 'INH'
	WHERE ExchangeID = 51

	--Endregion
	
	--Region Sum Data

	CREATE TABLE #SumData(
		RptDate				DATE,
		BettypeRef			INT, 
		GameTypeName		VARCHAR(20),
		PartyId				INT, 
		PartyName			VARCHAR(20), 
		CurrencyId			INT, 
		ProductId			INT,
		ParentId			INT, 
		TotalTrans			INT,
		Turnover			MONEY,
		LicenseeWinLoss		MONEY,
		LicenseeNetWin		MONEY,
		ProgresCont			MONEY,
		ProgresPayout		MONEY,
		LicensingFee		MONEY)
		
	INSERT INTO #SumData (RptDate, BettypeRef, GameTypeName, PartyId, PartyName, CurrencyId, ProductId,
							 ParentId, TotalTrans, Turnover, LicenseeWinLoss, LicenseeNetWin, ProgresCont, ProgresPayout, LicensingFee)
	SELECT d.RptDate3rd, gt.BetTypeRef, gt.GameTypeName, pci.PartyId, pci.PartyName, d.CurrencyId, d.ProductId, pci.ParentId,
		SUM(TotalTrans) AS TotalTrans,
		SUM(Turnover) AS Turnover,
		SUM(LicenseeWinLoss) AS LicenseeWinLoss,
		SUM(LicenseeWinLoss - ProgresCont) AS LicenseeNetWin,
		SUM(ProgresCont) AS ProgresCont,
		SUM(ProgresPayout) AS ProgresPayout,
		SUM((LicenseeWinLoss - ProgresCont) * pci.Rate) AS LicensingFee
	FROM (SELECT rpt.RptDate3rd, SiteId, gt.ProductId, gt.BettypeRef, CurrencyId, 
				SUM(ISNULL(BetCount, 0)) AS TotalTrans , 
				SUM(ISNULL(Turnover, 0)) AS Turnover, 
				-SUM(ISNULL(Winloss, 0)) AS LicenseeWinLoss,
				SUM(ISNULL(ProgressiveContribution, 0)) AS ProgresCont,
				SUM(ISNULL(ProgressivePayout, 0)) AS ProgresPayout
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT rpt
				INNER JOIN @GameTypes gt ON rpt.BetTypeId = gt.BettypeId
			WHERE rpt.RptDate BETWEEN @FromDate AND @ToDate
				  AND rpt.SiteId IN (SELECT DISTINCT LicenseeId FROM @PartyChargeInfo)
				  AND CurrencyID <> 20
				  AND StatusId NOT IN (-1, 101, 102, 103)
				  AND gt.BettypeRef = 2001 --Get Generic Game Only
			GROUP BY rpt.RptDate3rd, SiteId, gt.ProductId, gt.BettypeRef, CurrencyId) d
		INNER JOIN @PartyChargeInfo pci ON d.SiteId = pci.LicenseeID AND d.BettypeRef = pci.BettypeRef AND pci.ProductId = d.ProductId
		LEFT JOIN (SELECT DISTINCT BettypeRef, GameTypeName, ProductId FROM @GameTypes) gt ON d.BettypeRef = gt.BettypeRef AND gt.ProductId = d.ProductId
	WHERE d.RptDate3rd BETWEEN pci.Fromdate AND pci.ToDate
	GROUP BY d.RptDate3rd, gt.GameTypeName, gt.BettypeRef, pci.ParentId, pci.PartyId, pci.PartyName, d.ProductId, d.CurrencyId

	--Endregion

	--Region Result

	DECLARE @Result AS TABLE (
		WinLossDate						DATE,
		GameTypeId						INT,
		GameTypeName					VARCHAR(20),
		PartyId							INT, 
		PartyName						VARCHAR(20), 
		CurrencyName					VARCHAR(20),
		TotalTrans						INT,
		Turnover						MONEY,
		LicenseeWinLoss					MONEY,
		ProgressiveContribution			MONEY,
		ProgressivePayout				MONEY,
		LicensingFee					MONEY,
		ProgressiveFee					MONEY,
		LicenseeNetWin					MONEY)

	IF @BaseCurrencyName = ''
		BEGIN 
			INSERT INTO @Result(WinLossDate, GameTypeId, GameTypeName, PartyId, PartyName, CurrencyName,
								TotalTrans, Turnover, LicenseeWinLoss, ProgressiveContribution, ProgressivePayout, LicensingFee, ProgressiveFee, LicenseeNetWin)
			SELECT sd.RptDate, sd.BettypeRef AS GameTypeId, sd.GameTypeName, sd.PartyId, sd.PartyName, ex.CurrencyCode,
				SUM(TotalTrans), SUM(Turnover), SUM(LicenseeWinLoss), 
				SUM(ProgresCont), SUM(ProgresPayout), SUM(LicensingFee), SUM(ProgresCont - ProgresPayout), SUM(LicenseeNetWin)
			FROM #SumData sd
				INNER JOIN #Exchange ex ON ex.ExchangeDate = sd.RptDate AND ex.ExchangeID = sd.CurrencyId
			GROUP BY sd.RptDate, sd.BettypeRef, sd.GameTypeName, sd.PartyId, sd.PartyName, ex.CurrencyCode
			
		END 
	ELSE 
		BEGIN
			INSERT INTO @Result(WinLossDate, GameTypeId, GameTypeName, PartyId, PartyName, CurrencyName,
								TotalTrans, Turnover, LicenseeWinLoss, ProgressiveContribution, ProgressivePayout, LicensingFee, ProgressiveFee, LicenseeNetWin)
			SELECT sd.RptDate, sd.BettypeRef AS GameTypeId, sd.GameTypeName, sd.PartyId, sd.PartyName, ex.CurrencyCode,
				SUM(TotalTrans), SUM(Turnover * ex.Rate), SUM(LicenseeWinLoss * ex.Rate), 
				SUM(ProgresCont * ex.Rate), SUM(ProgresPayout * ex.Rate), SUM(LicensingFee * ex.Rate), SUM((ProgresCont - ProgresPayout) * ex.Rate),
				SUM(LicenseeNetWin * ex.Rate)
			FROM #SumData sd
				INNER JOIN #Exchange ex ON ex.ExchangeDate = sd.RptDate AND ex.ExchangeID = sd.CurrencyId
			GROUP BY sd.RptDate, sd.BettypeRef, sd.GameTypeName, sd.PartyId, sd.PartyName, ex.CurrencyCode
		END

	--Endregion
	
	-- Region Grand Total

	DECLARE @GrandTotal AS TABLE (
		CurrencyName					VARCHAR(20),
		TotalTrans						INT,
		Turnover						MONEY,
		LicenseeWinLoss					MONEY,
		LicenseeNetWin					MONEY,
		ProgressiveContribution			MONEY,
		ProgressivePayout				MONEY,
		LicensingFee					MONEY,
		PayTosupplier					MONEY,
		ProgressiveFee					MONEY,
		NetIncome						MONEY)

	DECLARE @TempGrandTotal AS TABLE (
		BettypeRef						INT,
		TotalTrans						INT,
		Turnover						MONEY,
		LicenseeWinLoss					MONEY,
		LicenseeNetWin					MONEY,
		ProgressiveContribution			MONEY,
		ProgressivePayout				MONEY,
		LicensingFee					MONEY,
		PayToSupplier					MONEY)

	DECLARE @PayToSupplier MONEY

	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrencyId = (SELECT TOP 1 Id FROM @BaseCurrencies WHERE IsApply IS NULL)
		SET @tempCurrencyCode = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		DELETE FROM #Exchange
		
		INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
		SELECT ExchangeDate, ExchangeId, Code, BaseCurrencyRate	
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrencyCode)
		
		DELETE FROM @ProductChargeInfo
		DELETE FROM @TempGrandTotal
		
		INSERT INTO @ProductChargeInfo (ParentId, ProductId, BettypeRef, ChargeType, Rate, MinAmount, MaxAmount, CurrencyId, CurrencyCode)
		SELECT DISTINCT a.FromParty, a.ProductId, a.BettypeRef, a.ChargeType, a.Rate, 
						CASE WHEN a.ChargeType = 4 THEN a.MinAmount * er.Rate ELSE 0 END MinAmount,
						CASE WHEN a.ChargeType = 4 THEN a.MaxAmount * er.Rate ELSE 0 END MaxAmount,
						@tempCurrencyId, @tempCurrencyCode
		FROM (SELECT DISTINCT tp.ProductId, ci2.ChargeID, cis.FromParty, cis.BettypeRef, cis.ChargeType, cis.Rate, cis.MinAmount, cis.MaxAmount, cis.BaseCurrencyId
				FROM @PartyChargeInfo tp
					INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON tp.ChargeId = ci.ChargeID
					LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo ci2 WITH (NOLOCK) ON ci.ToParty = ci2.FromParty AND ci2.ProductID = tp.ProductID
					LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfoSub cis WITH (NOLOCK) ON ci2.ChargeID = cis.ChargeIdRef
				WHERE tp.ChargeId > 0) a
			LEFT JOIN #Exchange er ON a.BaseCurrencyId = er.ExchangeID
		
		INSERT INTO @TempGrandTotal(BettypeRef, TotalTrans, Turnover, LicenseeWinLoss, LicenseeNetWin, ProgressiveContribution, ProgressivePayout, LicensingFee)
			SELECT sd.BettypeRef, SUM(TotalTrans), SUM(Turnover * ex.Rate), SUM(LicenseeWinLoss * ex.Rate), SUM(LicenseeNetWin * ex.Rate),
				SUM(ProgresCont * ex.Rate), SUM(ProgresPayout * ex.Rate), SUM(LicensingFee * ex.Rate)
			FROM #SumData sd
				INNER JOIN #Exchange ex ON ex.ExchangeDate = sd.RptDate AND ex.ExchangeID = sd.CurrencyId
			GROUP BY sd.BettypeRef
		
		UPDATE g SET g.PayToSupplier = t.PayToSupplier * pci.Rate
		FROM @TempGrandTotal g
		INNER JOIN 	(SELECT BettypeRef, SUM(rs.PayToSupplier) AS PayToSupplier
					 FROM (SELECT BettypeRef, SUM(LicenseeNetWin) AS LicenseeNetWin
						  FROM @TempGrandTotal
						  GROUP BY BettypeRef) d
						  OUTER APPLY	(
							SELECT
							CASE WHEN (ChargeType = 4 AND LicenseeNetWin BETWEEN MinAmount AND MaxAmount) THEN CASE WHEN MinAmount < 0 THEN (LicenseeNetWin - 0) * Rate 
																												  WHEN MinAmount >=0 THEN (LicenseeNetWin - MinAmount) * Rate ELSE 0 END
																										ELSE 0 END +
							CASE WHEN (ChargeType = 4 AND LicenseeNetWin > MaxAmount) THEN CASE WHEN MinAmount < 0 THEN (MaxAmount - 0) * Rate
																							  WHEN MinAmount >= 0 THEN (MaxAmount - MinAmount) * Rate ELSE 0 END
																					ELSE 0 END +
							CASE WHEN (ChargeType = 1) THEN LicenseeNetWin * Rate ELSE 0 END AS PayToSupplier
							FROM (SELECT BettypeRef, ChargeType, Rate, MinAmount, MaxAmount FROM @ProductChargeInfo GROUP BY BettypeRef, ChargeType, Rate, MinAmount, MaxAmount) pci
							WHERE BettypeRef = d.BettypeRef) rs
					GROUP BY BettypeRef) t
		INNER JOIN (SELECT BettypeRef, Rate FROM @PartyChargeInfo GROUP BY BettypeRef, Rate) pci ON pci.BettypeRef = t.BettypeRef
		ON t.BettypeRef = g.BettypeRef
		
		INSERT INTO @GrandTotal(CurrencyName, TotalTrans, Turnover, LicenseeWinLoss, LicenseeNetWin, ProgressiveContribution, ProgressivePayout, 
								LicensingFee, PayTosupplier, ProgressiveFee, NetIncome)
		SELECT @tempCurrencyCode, SUM(t.TotalTrans), SUM(t.Turnover), SUM(t.LicenseeWinLoss), SUM(t.LicenseeNetWin), SUM(t.ProgressiveContribution), SUM(t.ProgressivePayout), 
		CASE WHEN(SUM(t.LicensingFee) > 0) THEN SUM(t.LicensingFee) ELSE 0 END,
		CASE WHEN(SUM(t.PayTosupplier) > 0) THEN SUM(t.PayTosupplier) ELSE 0 END,
		SUM(ProgressiveContribution - ProgressivePayout),
		CASE WHEN(SUM(t.LicensingFee - t.PayTosupplier) > 0) THEN SUM(t.LicensingFee - t.PayTosupplier) ELSE 0 END
		FROM @TempGrandTotal t
		
		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Id = @tempCurrencyId	
	END

	--Endregion

	--Region Return Main Data

	SELECT * FROM @Result

	SELECT * FROM @GrandTotal

	--Endregion

	DROP TABLE #Exchange
	DROP TABLE #SumData
END

GO

SET QUOTED_IDENTIFIER OFF
GO
SET ANSI_NULLS ON
GO


GO
 
 GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_MicrogamingWinlossGMT0] TO [vnteam]
GO
 
 GRANT EXECUTE ON [dbo].[LA_Rpt_MicrogamingWinlossGMT0] TO [bodbAdminNet]
GO