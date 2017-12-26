USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_MicrogamingWinloss]
	  @PartyIds				VARCHAR(4000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @GameTypes			VARCHAR(50)			= '2001,2005'
	, @BaseCurrencyName		VARCHAR(10)			= ''
AS
/*  Created: 20150804@Florent
	Task : Report - Microgaming Casino GMT - 4
	DB: DB052.bodb02
	Modified:
	- Feature 44698.
	- Feature 54152.
	Revisions:
	- 20151201@Forrest: Add Microgaming RNG and change data flow.
	- 20160316@Forrest: Change SporttypeRef to Sporttype.
	- 20160428@Forrest: Update Entire Report
	- 20160530@Forrest: Update new formula
	- 20171219@Bruce: increase length for variables [#88197]
	Param's Explanation:
		+ @PartyIDs	: a string of list PartyID, separate by ','
		+ @Currency	:  0 - All Currencies
		+ @excludeTest: add/remove currency UUS
		+ @@GameTypes	: Products code :
				. 2001 - Generic
				. 2005 - Branded
		+ @BaseCurrencyName: GBP, CNY, USD, EUR, MYR
*/
SET NOCOUNT ON
BEGIN
	-- Region Default Constant

	DECLARE @ProductCodes VARCHAR(50)

	-- Endregion

	-- Region Parties

	DECLARE @Parties AS TABLE  (PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)

	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel

	-- Endregion

	-- Region Products Ref

	DECLARE @ProductsRef AS TABLE (ProductId INT, BettypeRef INT, BettypeId INT, GameTypeName VARCHAR(100))

	INSERT INTO @ProductsRef (ProductId, BettypeId, BettypeRef, GameTypeName)
	SELECT CASE WHEN sp.Sporttype = 203 THEN 14
				WHEN sp.Sporttype = 205 THEN 17 ELSE 0 END AS ProductId, sp.Bettype, pr.BettypeRef,
			CASE WHEN pr.BettypeRef = 2001 THEN 'Generic Games' ELSE 'Branded Games' END AS GameTypeName
	FROM bodb_licensee.dbo.Sport_Bettype_Reference sp WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.LA_Product3rdSub pr WITH (NOLOCK) ON sp.BettypeRef = pr.BettypeRef
	WHERE pr.BettypeRef IN (SELECT val FROM bodb02..strSplit(@GameTypes, ','))
	GROUP BY sp.Sporttype, sp.Bettype, pr.BettypeRef

	-- Endregion

	-- Region Get Product Codes

	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + prd.ProductPrefix
	FROM @ProductsRef pr
		INNER JOIN (SELECT Productid, ProductPrefix
					FROM bodb_licensee..Product3rd WITH (NOLOCK)
					WHERE Productid IN (SELECT [@ProductsRef].ProductId FROM @ProductsRef)) prd
		ON pr.ProductId = prd.Productid
	GROUP BY prd.Productid, prd.ProductPrefix

	-- Endregion

	-- Region Charge Info

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

	-- Endregion

	-- Region Base Currency Data
	DECLARE @tempCurrencyId INT
	DECLARE @tempCurrencyCode VARCHAR(3)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)

	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC bodb_licensee..LA_SelBaseCurrency

	-- Endregion

	-- Region Product Charge Info

	DECLARE @ProductChargeInfo AS TABLE (
			ParentId		INT,
			ProductId		INT,
			BettypeRef		INT,
			ChargeType		INT,
			Rate			MONEY,
			MinAmount		MONEY,
			MaxAmount		MONEY,
			CurrencyId		INT,
			CurrencyCode	VARCHAR(10))

	-- Endregion

	-- Region: Exchange

	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeID INT, CurrencyCode	VARCHAR(10), Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	UPDATE #Exchange
	SET CurrencyCode = 'INH'
	WHERE ExchangeID = 51

	-- Endregion

	-- Region Sum Data

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
	SELECT d.RptDate, pr.BetTypeRef, pr.GameTypeName, pci.PartyId, pci.PartyName, d.CurrencyId, d.ProductId, pci.ParentId,
		SUM(TotalTrans) AS TotalTrans,
		SUM(Turnover) AS Turnover,
		SUM(LicenseeWinLoss) AS LicenseeWinLoss,
		SUM(LicenseeWinLoss - ProgresCont) AS LicenseeNetWin,
		SUM(ProgresCont) AS ProgresCont,
		SUM(ProgresPayout) AS ProgresPayout,
		SUM((LicenseeWinLoss - ProgresCont) * pci.Rate) AS LicensingFee
	FROM (SELECT rpt.RptDate, SiteId, pr.ProductId, pr.BettypeRef, CurrencyId,
				SUM(ISNULL(BetCount, 0)) AS TotalTrans ,
				SUM(ISNULL(Turnover, 0)) AS Turnover,
				-SUM(ISNULL(Winloss, 0)) AS LicenseeWinLoss,
				CASE WHEN pr.ProductId = 17 THEN SUM(ISNULL(ProgressiveContribution, 0)) ELSE 0 END  AS ProgresCont,
				CASE WHEN pr.ProductId = 17 THEN SUM(ISNULL(ProgressivePayout, 0)) ELSE 0 END  AS ProgresPayout
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT rpt
				INNER JOIN @ProductsRef pr ON rpt.BetTypeId = pr.BettypeId
			WHERE rpt.RptDate BETWEEN @FromDate AND @ToDate
				  AND rpt.SiteId IN (SELECT DISTINCT LicenseeId FROM @PartyChargeInfo)
				  AND CurrencyID <> 20
				  AND StatusId NOT IN (-1, 101, 102, 103)
			GROUP BY rpt.RptDate, SiteId, pr.ProductId, pr.BettypeRef, CurrencyId) d
		INNER JOIN @PartyChargeInfo pci ON d.SiteId = pci.LicenseeID AND d.BettypeRef = pci.BettypeRef AND pci.ProductId = d.ProductId
		LEFT JOIN (SELECT DISTINCT BettypeRef, GameTypeName, ProductId FROM @ProductsRef) pr ON d.BettypeRef = pr.BettypeRef AND pr.ProductId = d.ProductId
	WHERE d.RptDate BETWEEN pci.Fromdate AND pci.ToDate
	GROUP BY d.RptDate, pr.GameTypeName, pr.BettypeRef, pci.ParentId, pci.PartyId, pci.PartyName, d.ProductId, d.CurrencyId

	-- Endregion

	-- Region Result

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

	-- Endregion

	-- Region Total Game Type

	DECLARE @TotalGameType AS TABLE (
		GameTypeId						INT,
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

	-- Endregion

	-- Region Total Game Type

	DECLARE @Total AS TABLE (
		GameTypeId						INT,
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

	-- Endregion

	-- Region Grand Total Sum

	DECLARE @SumGrandTotal AS TABLE (
		WinLossDate						DATE,
		ProductId						INT,
		BettypeRef						INT,
		CurrencyId						INT,
		TotalTrans						INT,
		Turnover						MONEY,
		LicenseeWinLoss					MONEY,
		LicenseeNetWin					MONEY,
		ProgressiveContribution			MONEY,
		ProgressivePayout				MONEY,
		LicensingFee					MONEY,
		PayToSupplier					MONEY)

	-- Endregion

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

	-- Region Pay To Supplier by BettypeRef

	DECLARE @PayToSuppiers AS TABLE (
		BettypeRef				INT,
		PayToSupplier			MONEY)

	-- Endregion

	DECLARE @PayToSuppier MONEY

	IF((SELECT COUNT (*) FROM @Result) > 0)
	BEGIN
		WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
		BEGIN
			SET @tempCurrencyId = (SELECT TOP 1 Id FROM @BaseCurrencies WHERE IsApply IS NULL)
			SET @tempCurrencyCode = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
			DELETE FROM #Exchange

			INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
			SELECT ExchangeDate, ExchangeId, Code, BaseCurrencyRate
			FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrencyCode)

			DELETE FROM @ProductChargeInfo
			DELETE FROM @SumGrandTotal
			DELETE FROM @PayToSuppiers
			DELETE FROM @TotalGameType

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

			INSERT INTO @SumGrandTotal (WinLossDate, ProductId, BettypeRef, CurrencyId, TotalTrans, Turnover, LicenseeWinLoss, LicenseeNetWin,
										ProgressiveContribution, ProgressivePayout, LicensingFee)
			SELECT sd.RptDate, sd.ProductId, sd.BettypeRef, sd.CurrencyId,
					SUM(sd.TotalTrans),
					SUM(sd.Turnover * ex.Rate),
					SUM(sd.LicenseeWinLoss * ex.Rate),
					SUM(sd.LicenseeNetWin * ex.Rate),
					SUM(sd.ProgresCont * ex.Rate),
					SUM(sd.ProgresPayout * ex.Rate),
					SUM(sd.LicensingFee * ex.Rate)
			FROM #SumData sd
				INNER JOIN #Exchange ex ON ex.ExchangeDate = sd.RptDate AND ex.ExchangeID = sd.CurrencyId
			GROUP BY sd.RptDate, sd.ProductId, sd.BettypeRef, sd.CurrencyId

			INSERT INTO @PayToSuppiers(BettypeRef, PayToSupplier)
			SELECT BettypeRef, SUM(rs.PayToSupplier) AS PayToSupplier
				 FROM (SELECT BettypeRef, SUM(LicenseeWinLoss - ProgressiveContribution) AS GameFee
					  FROM @SumGrandTotal
					  GROUP BY BettypeRef) d
					  OUTER APPLY	(
						SELECT
						CASE WHEN (ChargeType = 4 AND GameFee BETWEEN MinAmount AND MaxAmount) THEN CASE WHEN MinAmount < 0 THEN (GameFee - 0) * Rate
																										 WHEN MinAmount >=0 THEN (GameFee - MinAmount) * Rate ELSE 0 END
																									ELSE 0 END +
						CASE WHEN (ChargeType = 4 AND GameFee > MaxAmount) THEN CASE WHEN MinAmount < 0 THEN (MaxAmount - 0) * Rate
																					 WHEN MinAmount >= 0 THEN (MaxAmount - MinAmount) * Rate ELSE 0 END
																				ELSE 0 END +
						CASE WHEN (ChargeType = 1) THEN GameFee * Rate ELSE 0 END AS PayToSupplier
						FROM (SELECT BettypeRef, ChargeType, Rate, MinAmount, MaxAmount FROM @ProductChargeInfo GROUP BY BettypeRef, ChargeType, Rate, MinAmount, MaxAmount) pci
						WHERE BettypeRef = d.BettypeRef) rs
			GROUP BY BettypeRef

			INSERT INTO @TotalGameType(GameTypeId, TotalTrans, Turnover, LicenseeWinLoss, LicenseeNetWin, ProgressiveContribution, ProgressivePayout, LicensingFee,
								ProgressiveFee)
			SELECT BettypeRef, SUM(TotalTrans), SUM(Turnover), SUM(LicenseeWinLoss), SUM(LicenseeWinLoss - ProgressiveContribution),
					SUM(ProgressiveContribution),
					SUM(ProgressivePayout),
					CASE WHEN(SUM(LicensingFee) > 0) THEN SUM(LicensingFee) ELSE 0 END,
					SUM(ProgressiveContribution - ProgressivePayout)
			FROM @SumGrandTotal sgt
			GROUP BY BettypeRef

			UPDATE @TotalGameType SET
				PayTosupplier = CASE WHEN(pts.PayToSupplier > 0) THEN pts.PayToSupplier ELSE 0 END,
				NetIncome = t.LicensingFee - CASE WHEN(pts.PayToSupplier > 0) THEN pts.PayToSupplier ELSE 0 END
			FROM @TotalGameType t
			INNER JOIN @PayToSuppiers pts ON t.GameTypeId = pts.BettypeRef

			INSERT INTO @GrandTotal(CurrencyName, TotalTrans, Turnover, LicenseeWinLoss, LicenseeNetWin, ProgressiveContribution, ProgressivePayout,
									LicensingFee, ProgressiveFee, PayTosupplier, NetIncome)
			SELECT @tempCurrencyCode, SUM(TotalTrans), SUM(Turnover), SUM(LicenseeWinLoss), SUM(LicenseeNetWin), SUM(ProgressiveContribution), SUM(ProgressivePayout),
				SUM(LicensingFee), SUM(ProgressiveFee), SUM(PayTosupplier), SUM(NetIncome)
			FROM @TotalGameType

			IF (@BaseCurrencyName = @tempCurrencyCode)
			BEGIN
				INSERT INTO @Total (GameTypeId, TotalTrans, Turnover, LicenseeWinLoss, LicenseeNetWin, ProgressiveContribution, ProgressivePayout,
									LicensingFee, ProgressiveFee, PayTosupplier, NetIncome)
				SELECT GameTypeId, TotalTrans, Turnover, LicenseeWinLoss, LicenseeNetWin, ProgressiveContribution, ProgressivePayout,
									LicensingFee, ProgressiveFee, PayTosupplier, NetIncome
				FROM @TotalGameType
			END

			UPDATE @BaseCurrencies SET IsApply = 1 WHERE Id = @tempCurrencyId
		END
	END

	-- Endregion

	-- Region Result

	SELECT * FROM @Result

	SELECT * FROM @GrandTotal

	SELECT * FROM @Total

	-- Endregion

	DROP TABLE #Exchange
	DROP TABLE #SumData
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_MicrogamingWinloss] TO [vnteam]
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_MicrogamingWinloss] TO [bodbAdminNet]
GO
