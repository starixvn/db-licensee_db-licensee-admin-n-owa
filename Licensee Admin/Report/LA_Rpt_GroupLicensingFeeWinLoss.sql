/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet,bodbLicenseeNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_Rpt_GroupLicensingFeeWinLoss]
	@PartyIDs				VARCHAR(5500)	= ''
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME	
AS
/*  Created: Scofield.Huynh
	Date: 2018-12-04
	DB: DB052.bodb_licensee

	Revisions:
	   - 20181204@Scofield: create	
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @ProductCodes VARCHAR(5500) = 'SB,RB,NG,BA,LC,VS,CS,KN,AGC,VG,GD,MGCLC,MGCRNG,VB,AB,FW,VS2,LT,CB,CO,BT,BX,PP'	
	DECLARE @ChargeInfo TABLE(PartyID INT, LicenseeID INT, ProductID INT,BetTypeId INT ,Rate MONEY, Fromdate DATE, Todate DATE)
	CREATE TABLE #Data (rptDate DATE, PartyID INT, ProductID INT, Currency INT,BetTypeId INT, Turnover MONEY, Winloss MONEY, AWinloss MONEY, AComm MONEY, PComm MONEY, Betcount BIGINT)
	CREATE TABLE #Report (PartyID INT, ProductID INT, CurrencyID INT, Company MONEY)						
	
	INSERT INTO @ChargeInfo(PartyID, LicenseeID, ProductID, BetTypeId, Rate, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, Bettype, CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
	
	/* BA Product Id = 3 */
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 3) > 0
	BEGIN
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Winloss, AComm)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID, SUM(b.MemberWL) Winloss, SUM(b.CommissionA) CommBA
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 3
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Report (PartyID, ProductID, CurrencyID, Company)
		(
			SELECT ci.PartyID, b.ProductID, b.currency, -SUM((b.winloss * ci.Rate ) + b.AComm) AS Company				
			FROM #Data b
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM @ChargeInfo WHERE ProductID = 3) ci 
				ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY ci.PartyID, b.ProductID, b.Currency
		)
	END
	
	/* Microgaming Live Casino Product Id = 14, Microgaming RNG Casino Product Id = 17 */
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID IN (14, 17)) > 0
	BEGIN
		DELETE #Data
		
		CREATE TABLE #GameTypes (ProductId INT, BettypeRef INT, BettypeId INT)
		CREATE TABLE #MicrogamingChargeInfo(PartyID INT, LicenseeID INT, ProductID INT,BetTypeId INT ,Rate MONEY, Fromdate DATE, Todate DATE)

		INSERT INTO #GameTypes (ProductId, BettypeId, BettypeRef)
		SELECT CASE WHEN sp.Sporttype = 203 THEN 14
					WHEN sp.Sporttype = 205 THEN 17 ELSE 0 END AS ProductId, sp.Bettype, pr.BettypeRef
		FROM bodb_licensee.dbo.Sport_Bettype_Reference sp WITH (NOLOCK)
			LEFT JOIN bodb_licensee.dbo.LA_Product3rdSub pr WITH (NOLOCK) ON sp.BettypeRef = pr.BettypeRef
		GROUP BY sp.Sporttype, sp.Bettype, pr.BettypeRef
		
		INSERT INTO #MicrogamingChargeInfo(PartyID, LicenseeID, ProductID, BetTypeId, Rate, Fromdate, Todate)
		SELECT PartyID, LicenseeID, ci.ProductID, gt.BetTypeId, Rate, Fromdate, Todate 
		FROM @ChargeInfo ci
		INNER JOIN #GameTypes gt ON ci.ProductID = gt.ProductId AND ci.BetTypeId = gt.BettypeRef
		
		DROP TABLE #GameTypes
			
		CREATE TABLE #MicrogamingProducts (ProductId INT)
		
		IF EXISTS (SELECT * FROM @ChargeInfo WHERE ProductID = 14)
		BEGIN
			INSERT INTO #MicrogamingProducts VALUES(14)
		END
		
		IF EXISTS (SELECT * FROM @ChargeInfo WHERE ProductID = 17)
		BEGIN
			INSERT INTO #MicrogamingProducts VALUES(17)
		END
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, BetTypeId, Winloss)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID, ci.BetTypeId, SUM(b.MemberWL)				
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyID, LicenseeID, ProductID, BetTypeId FROM #MicrogamingChargeInfo) ci 
				ON b.SiteID = ci.LicenseeID AND ci.BetTypeId = b.Bettype AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID IN (SELECT ProductId FROM #MicrogamingProducts)
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID, ci.BetTypeId
		)
			
		INSERT INTO #Report (PartyID, ProductID, CurrencyID, Company)
		(
			SELECT ci.PartyID, b.ProductID, b.currency, -SUM(b.Winloss * ci.Rate) AS Company				
			FROM #Data b
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, BetTypeId, Rate FROM #MicrogamingChargeInfo WHERE ProductID IN(SELECT ProductId FROM #MicrogamingProducts)) ci 
				ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID AND ci.BetTypeId = b.BetTypeId			
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY ci.PartyID, b.ProductID, b.Currency
		)
		
		DROP TABLE #MicrogamingChargeInfo
		DROP TABLE #MicrogamingProducts
	END
	
	/* Racing Product Id = 1 */
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 1) > 0
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Winloss, AWinloss, AComm)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID, SUM(b.MemberWL), SUM(b.GrossWL), SUM(b.CommissionA)
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 1
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Report (PartyID, ProductID, CurrencyID, Company)
		(
			SELECT ci.PartyID, b.ProductID, b.currency, -SUM(b.Winloss + b.AWinloss + b.AComm) AS Company				
			FROM #Data b
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, BetTypeId, Rate FROM @ChargeInfo WHERE ProductID = 1) ci 
				ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID		
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY ci.PartyID, b.Currency, b.ProductID
		)
	END
	
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 15) > 0
	BEGIN
		-- Region: Local variables
		DECLARE @CBProductId INT = 15
		DECLARE @CommChargeType INT = 6
		DECLARE @CashInShareChargeType INT = 7		

		-- Region: Commision and Cash in share Rates
		DECLARE @CBShare AS TABLE(PartyId INT, LicenseeId INT, Rate MONEY, TypeId SMALLINT, FromDate DATETIME, ToDate DATETIME)

		INSERT INTO @CBShare(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)
		SELECT PartyID,LicenseeID,DI_Rate,ChargeType,Fromdate,Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs,@FromDate,@ToDate,'CB','OA',1)		
		-- End Region: Commision and Cash in share Rates

		-- Region: Get Winloss Data
		CREATE TABLE #TempData (
			PartyId							INT,
			rptDate							DATETIME,
			CurrencyId						INT,
			Turnover						MONEY,
			TurnoverForCommission			MONEY,
			WinningPrize					MONEY,
			CashOut							MONEY,
			CommisionShare					MONEY,
			CashInShare						MONEY,
			CashInAmount					MONEY
		)

		INSERT INTO #TempData (PartyId, rptDate, CurrencyId, Turnover, TurnoverForCommission, WinningPrize, CashOut, CashInAmount)
		SELECT	cb.PartyId,
				rptDate,
				CurrencyId,
				SUM(Turnover) Turnover,
				SUM(CASE WHEN ISNULL(TicketType,0)=0 THEN Turnover ELSE ISNULL(ExtraAmount,0) END) TurnoverForCommission,
				SUM(ISNULL(WinPrizeAmount,0)) WinningPrize,
				SUM(ISNULL(CashOutAmount,0)) CashOut,
				SUM(ISNULL(BuyBackAmount,0)) CashInAmount
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN @CBShare cb ON b.SiteID = cb.LicenseeId AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
		WHERE	ProductID = @CBProductId AND
				CustomerCategory NOT IN (27, 28) AND
				b.StatusId NOT IN (-1, 101, 102, 103) AND
				(b.CurrencyID <> 20) AND
				cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
		GROUP BY cb.PartyId, rptdate, CurrencyId
		-- End Region: Get Winloss Data

		UPDATE #TempData
		SET CommisionShare = td.TurnoverForCommission * cm.Rate,
			CashInShare = td.CashInAmount * ci.Rate
		FROM #TempData td
		INNER JOIN @CBShare AS cm ON cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate) AND cm.PartyId = td.PartyId
		INNER JOIN @CBShare AS ci ON ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate) AND ci.PartyId = td.PartyId
		-- End Region: Calculate Commision, Cash In Share

		INSERT INTO #Report (PartyID, ProductId, CurrencyID, Company)
		SELECT td.PartyId, @CBProductId, td.CurrencyId, SUM(Turnover - WinningPrize - Cashout - CommisionShare - CashInShare)
		FROM #TempData td
		GROUP BY td.PartyId, td.CurrencyId
		
		DROP TABLE #TempData
	END

	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 25) > 0
	BEGIN		
		DECLARE @COProductId INT = 25

		INSERT INTO #Report (PartyID, ProductId, CurrencyID, Company)
		(
			SELECT
				d.PartyId,
				@COProductId,
				d.Currency,				
				SUM(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) AS Company
			FROM (
					SELECT ci.PartyId, b.Winlostdate, b.Currency,											
							SUM(b.BuyBackAmt) AS BuyBackAmountSB,
							SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
							SUM(b.TicketPayout) AS TicketsPayout,					
							SUM(b.BuyBackAmt * ci.Rate) AS CashoutCommission	
					FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
						INNER JOIN @ChargeInfo ci ON b.SiteId = ci.LicenseeID AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate AND b.ProductID = ci.ProductId					
					WHERE b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate									
						AND (b.Currency <> 20)
						AND b.ProductID = @COProductId
						AND b.RoleID = 1 -- Member
					GROUP BY ci.PartyId, b.Winlostdate, b.Currency			
			) d
			GROUP BY d.PartyId, d.Currency
		)
	END
	
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 13) > 0
	BEGIN
		DECLARE @BTProductId INT = 13
	
		CREATE TABLE #Bettype ( Bettype INT, ProductId INT)
		INSERT INTO #Bettype (Bettype, ProductId)		
	    SELECT Bettype, ProductID
	    FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'BT,SB,BA')		

		CREATE NONCLUSTERED INDEX IDX_Index_Bettype ON #Bettype(Bettype)
		
		CREATE TABLE #BTChargeInfo (PartyID INT, LicenseeID INT, FromDate DATE, ToDate DATE, Rate MONEY)
		INSERT INTO #BTChargeInfo
		        ( PartyID ,
		          LicenseeID ,
		          FromDate ,
		          ToDate , 
				  Rate
		        )
		SELECT DISTINCT PartyID, LicenseeID, Fromdate, Todate, Rate
		FROM @ChargeInfo
		WHERE ProductID = @BTProductId	   

		INSERT INTO #Report (PartyID, ProductId, CurrencyID, Company)
		(
			SELECT
				d.PartyId,
				@BTProductId,
				d.CurrencyID,
				SUM ((d.BTWinLoss + d.BettradeComm + d.Actual_stake - d.BuyBackAmountTotal)) AS Company
			FROM (				
				SELECT ci.PartyId, b.RptDate, b.CurrencyId
					, SUM(CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount - b.WinLoss) ELSE 0 END) AS Actual_stake
					, SUM(CASE WHEN b.Bettype = 901 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountTotal
					, SUM(CASE WHEN bt.ProductId = 0 THEN b.WinLoss ELSE 0 END) AS BTWinLoss
					, SUM (CASE WHEN b.Bettype = 901 AND b.CustomerCategory = 1001 THEN - b.BuyBackAmount * ci.Rate ELSE 0 END) AS BettradeComm
				FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN #BTChargeInfo ci ON b.SiteId = ci.LicenseeID
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
				WHERE b.RptDate BETWEEN ci.FromDate AND ci.ToDate
					AND (b.CurrencyID <> 20)
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory IN (1001, 1002)					
					AND bt.ProductId IN (0, @BTProductId)
				GROUP BY b.RptDate, b.CurrencyId, ci.PartyId
				
				UNION ALL 
				
				-- rpt_betting_BA only contain original ticket, SOLD BOUGHT COMM ticket will be in rpt_betting
				SELECT ci.PartyId, b.RptDate, b.CurrencyId
					, 0 AS Actual_stake
					, 0 AS BuyBackAmountTotal
					, SUM(b.WinLoss) AS BTWinLoss
					, 0 AS BettradeComm
				FROM bodb_licenseereport.dbo.rpt_Betting_BA b WITH (NOLOCK)		
					INNER JOIN #BTChargeInfo ci ON b.SiteId = ci.LicenseeID 
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
				WHERE b.RptDate BETWEEN ci.FromDate AND ci.ToDate 					
					AND (b.CurrencyID <> 20)
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory = 1002 -- for BT BA	
					AND bt.ProductId = 3				
				GROUP BY b.RptDate, b.CurrencyId, ci.PartyId
			) d
			GROUP BY d.CurrencyID, d.PartyId
		)
	END

	DECLARE @ExcludedProductIds TABLE(ProductId INT)
	INSERT INTO @ExcludedProductIds(ProductId) VALUES (1), (3), (14), (17), (15), (25), (13)

	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) > 0
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Turnover, Winloss, AWinloss, PComm, AComm, Betcount)
		(
			SELECT  b.rptDate, ci.PartyID, b.ProductID, b.currencyID
				, SUM(b.turnover) Turnover
				, SUM(b.MemberWL)
				, 0
				, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END)
				, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionA ELSE 0 END)
				, SUM(b.betcount) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT PartyId, LicenseeId, ProductID FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27,28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY b.rptDate, ci.PartyID, b.ProductID, b.CurrencyID
		)

		INSERT INTO #Report (PartyID, ProductID, CurrencyID, Company)
		SELECT ci.PartyID, b.ProductID, b.Currency
			, SUM(-b.Winloss * ci.Rate - CASE WHEN b.ProductID=31 THEN (b.AComm + b.PComm) ELSE 0 END) AS Company
		FROM #Data b WITH (NOLOCK)
		INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci 
			ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
		WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
		GROUP BY ci.PartyID, b.Currency, b.ProductID
	END	
	
	DECLARE @Exchange AS TABLE (Currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(20))

	INSERT INTO @Exchange(Currency, CurrencyName, CurrencyCode)
	SELECT e.exchangeid, e.currency, e.Code
	FROM bodb02.dbo.Exchange e WITH (NOLOCK)
	WHERE e.exchangeid IN (SELECT DISTINCT CurrencyID FROM #Report)
	
	UPDATE @Exchange
	SET CurrencyCode = (CASE Currency
					WHEN 51 THEN 'INH'
					WHEN 75 THEN 'PTU'
					WHEN 76 THEN 'PS'
					WHEN 77 THEN 'PTH' 
					ELSE CurrencyCode
				END)
	WHERE Currency IN (51, 75, 76, 77)

	UPDATE e
	SET CurrencyCode = e.CurrencyCode + '(' + CurrencyName + ')'
	FROM @Exchange e
	WHERE e.CurrencyCode IN (SELECT CurrencyCode FROM @Exchange GROUP BY CurrencyCode HAVING COUNT(1) > 1)
	

	;WITH tmpResult AS (
		SELECT b.PartyID
			, CASE p.PartyName
				WHEN '18bb' THEN 'PIH'
				WHEN 'IBC'	THEN 'FDL'
				ELSE p.PartyName
				END AS PartyName
			, b.CurrencyID
			, ex.CurrencyCode AS CurrencyName
			, b.ProductId
			, CASE b.ProductId
				WHEN 0 THEN 'Sportsbook'
				ELSE prd.ProductName 
			  END AS ProductName
			, Company AS AmountToCompany
		FROM #Report b
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) 
			ON p.PartyID = b.PartyID
		LEFT JOIN dbo.Product3rd prd WITH(NOLOCK)
			ON prd.ProductId = b.ProductId
		LEFT JOIN @Exchange ex 
			ON b.CurrencyId = ex.Currency
	)
	SELECT PartyName, CurrencyName, ProductName, Sum(AmountToCompany) AS AmountToCompany
	FROM tmpResult t
	GROUP BY PartyName, CurrencyName, ProductName	
	
	DROP TABLE #Report
	DROP TABLE #Data
END
GO
